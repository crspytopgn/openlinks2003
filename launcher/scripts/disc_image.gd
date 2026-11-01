extends RefCounted
## Reads the ISO 9660 file system on a CD image: cooked (.iso) or raw
## sectors (BlindWrite .b6i, .bin, Nero .nrg, Alcohol .mdf), with or without
## a pregap or subchannel data. The same reader as the web build's
## game/web/game_files.js and tools/cdimage/cdimage.py, in GDScript.

## Sector size and where the 2048 data bytes start in each: cooked, raw
## Mode 1, raw Mode 2 Form 1, and raw with 96 bytes of subchannel data.
const LAYOUTS := [[2048, 0], [2352, 16], [2352, 24], [2448, 16], [2448, 24]]
const PREGAPS := [0, 150]
## How far into an image to look for the volume when the usual layouts
## don't fit (other pregaps, a leading audio track, an image header).
const SCAN_BYTES := 64 * 1024 * 1024
const EXTENSIONS := ["b6i", "b5i", "bwi", "iso", "bin", "img", "nrg", "mdf"]
## The small files beside an image that hold no data of their own.
const DESCRIPTORS := ["b6t", "b5t", "bwt", "bws", "bwa", "b6s", "cue", "mds", "ccd", "sub", "toc"]

var path := ""
var sector_size := 2048
var header := 0
var pregap := 0
var base := 0
var _f: FileAccess


static func is_image(file: String) -> bool:
	return EXTENSIONS.has(file.get_extension().to_lower())


static func is_descriptor(file: String) -> bool:
	return DESCRIPTORS.has(file.get_extension().to_lower())


## Opens `file` and finds its layout. False if it holds no ISO 9660 volume.
func open(file: String) -> bool:
	path = file
	_f = FileAccess.open(file, FileAccess.READ)
	if _f == null:
		return false
	for layout: Array in LAYOUTS:
		for gap: int in PREGAPS:
			sector_size = layout[0]
			header = layout[1]
			pregap = gap
			base = 0
			if _is_descriptor(sector(16)):
				return true
	return _scan()


func close() -> void:
	_f = null


static func _is_descriptor(s: PackedByteArray) -> bool:
	return s.size() >= 6 and s.slice(1, 6).get_string_from_ascii() == "CD001"


## Looks for the volume descriptor anywhere in the first SCAN_BYTES, then
## takes the layout that puts it at sector 16.
func _scan() -> bool:
	var chunk := 4 * 1024 * 1024
	var end := mini(_f.get_length(), SCAN_BYTES)
	var start := 0
	while start < end:
		_f.seek(start)
		var buf := _f.get_buffer(chunk + 8)
		var i := buf.find(0x43)
		while i >= 1 and i + 5 <= buf.size():
			if buf[i - 1] == 1 and buf.slice(i, i + 5).get_string_from_ascii() == "CD001":
				var at := start + i - 1
				for layout: Array in LAYOUTS:
					var b: int = at - int(layout[1]) - 16 * int(layout[0])
					if b < 0:
						continue
					sector_size = layout[0]
					header = layout[1]
					pregap = 0
					base = b
					if _is_descriptor(sector(17)):
						return true
				base = 0
			i = buf.find(0x43, i + 1)
		start += chunk
	return false


func offset(lba: int) -> int:
	return base + (lba + pregap) * sector_size + header


## The 2048 data bytes of sector `lba`.
func sector(lba: int) -> PackedByteArray:
	var off := offset(lba)
	if off < 0 or off + 2048 > _f.get_length():
		return PackedByteArray()
	_f.seek(off)
	return _f.get_buffer(2048)


## `length` bytes of the extent at `lba`, from `start` bytes in.
func read(lba: int, length: int, start := 0) -> PackedByteArray:
	if length <= 0:
		return PackedByteArray()
	var first := lba + start / 2048
	var skip := start % 2048
	if sector_size == 2048:
		_f.seek(offset(first) + skip)
		return _f.get_buffer(length)
	var count := (skip + length + 2047) / 2048
	_f.seek(offset(first))
	var raw := _f.get_buffer(count * sector_size)
	var out := PackedByteArray()
	for s in count:
		var a := s * sector_size + (skip if s == 0 else 0)
		var n := mini(length - out.size(), s * sector_size + 2048 - a)
		if n <= 0 or a >= raw.size():
			break
		out.append_array(raw.slice(a, a + n))
	return out


## Copies a file's extent to `dest` in 1 MB pieces; calls `progress` with
## each piece's size. False on a write error.
func copy_to(lba: int, length: int, dest: String, progress := Callable()) -> bool:
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		return false
	var piece := 512 * 2048
	var done := 0
	while done < length:
		var n := mini(piece, length - done)
		var data := read(lba, n, done)
		if data.size() != n:
			return false
		out.store_buffer(data)
		done += n
		if progress.is_valid():
			progress.call(n)
	out.close()
	return true


## The volume label (such as 2003DISK1).
func label() -> String:
	return sector(16).slice(40, 72).get_string_from_ascii().strip_edges()


## The root directory record, preferring the Joliet (long name) tree:
## [record, joliet].
func root() -> Array:
	var primary := PackedByteArray()
	for lba in range(16, 32):
		var d := sector(lba)
		if not _is_descriptor(d) or d[0] == 255:
			break
		if d[0] == 1 and primary.is_empty():
			primary = d.slice(156, 190)
		var esc := d.slice(88, 91).get_string_from_ascii()
		if d[0] == 2 and esc in ["%/@", "%/C", "%/E"]:
			return [d.slice(156, 190), true]
	return [primary, false]


## Every file on the disc: [{path: "/GAME/X.LS", lba, size}].
func files() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := root()
	if (r[0] as PackedByteArray).is_empty():
		return out
	_walk(r[0], r[1], "", out, 0)
	return out


func _walk(record: PackedByteArray, joliet: bool, prefix: String, out: Array[Dictionary], depth: int) -> void:
	if depth > 8:
		return
	var data := read(record.decode_u32(2), record.decode_u32(10))
	var pos := 0
	while pos < data.size():
		var length := data[pos]
		if length == 0:
			pos = (pos / 2048 + 1) * 2048  # records never cross sectors
			continue
		var rec := data.slice(pos, pos + length)
		pos += length
		if rec.size() < 34:
			continue
		var raw := rec.slice(33, 33 + rec[32])
		if raw.size() == 1 and raw[0] <= 1:
			continue  # "." and ".."
		var file_name := ""
		if joliet:
			for i in range(0, raw.size() - 1, 2):
				file_name += char((raw[i] << 8) | raw[i + 1])
		else:
			file_name = raw.get_string_from_ascii()
		file_name = file_name.split(";")[0]
		var p := prefix + "/" + file_name
		if rec[25] & 2:
			_walk(rec, joliet, p, out, depth + 1)
		else:
			out.append({"path": p, "lba": rec.decode_u32(2), "size": rec.decode_u32(10)})


## Setup's table of disc paths to installed names (docs/formats/
## object-library.md): u32 0x50, u16 length, "game\DIR\FILE" NUL,
## "Install\Path" NUL. Returns {"DIR/FILE" (upper case): "Install/Path"}.
static func long_names(exe: PackedByteArray) -> Dictionary:
	var names := {}
	var game := "game\\".to_ascii_buffer()
	var i := exe.find(0x50)
	while i >= 0 and i + 11 < exe.size():
		if exe[i + 1] == 0 and exe[i + 2] == 0 and exe[i + 3] == 0 and exe.slice(i + 6, i + 11) == game:
			var a := i + 6
			var a_end := exe.find(0, a)
			if a_end > a:
				var b_end := exe.find(0, a_end + 1)
				if b_end > a_end + 1 and exe[a_end + 1] >= 32:
					var disc_path := exe.slice(a + 5, a_end).get_string_from_ascii().replace("\\", "/").to_upper()
					var install := exe.slice(a_end + 1, b_end).get_string_from_ascii().replace("\\", "/")
					names[disc_path] = install
					i = b_end
		i = exe.find(0x50, i + 1)
	return names
