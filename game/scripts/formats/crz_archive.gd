class_name CrzArchive
extends RefCounted
## Reader for locked course archives (.CRZ, .RNG, .CVT). A GDScript port of
## libs/olcore/src/crz.cpp; change both together. See docs/formats/crz.md.
##
## Only the header and directory are read up front; entries are read from the
## file when asked for, so a 100 MB course costs little memory.

const HEADER_SIZE := 16
const RECORD_SIZE := 64
const DIRECTORY_ROUNDS := 32
const ENTRY_ROUNDS := 4
const KEY_LENGTH := 7
const COPYRIGHT_ENTRY := "copyright"
const COURSE_KEY_OFFSET := 0x2C
const METHOD_ZLIB := 2
## Words 5-7 of the P table: digits of pi, which locate the tables.
const PI_ANCHOR := [0x299f31d0, 0x082efa98, 0xec4e6c89]
const ANCHOR_WORD := 5

## Each entry: {name, offset, packed_size, size, method, locked}
var entries: Array[Dictionary] = []
var error := ""

var _path := ""
var _file_size := 0
var _tables := PackedInt64Array()
var _archive_key := PackedByteArray()
var _course_key := PackedByteArray()


## The cipher tables, or an empty array if `exe` is not a Links 2003
## executable.
static func find_tables(exe: PackedByteArray) -> PackedInt64Array:
	var first: int = PI_ANCHOR[0] & 0xFF
	var i := exe.find(first)
	while i >= 0:
		var start := i - 4 * ANCHOR_WORD
		if (start >= 0 and i + 12 <= exe.size() and exe.decode_u32(i) == PI_ANCHOR[0]
				and exe.decode_u32(i + 4) == PI_ANCHOR[1] and exe.decode_u32(i + 8) == PI_ANCHOR[2]):
			var words := Bunky.P_WORDS + Bunky.S_WORDS
			if start + 4 * words <= exe.size():
				var tables := PackedInt64Array()
				tables.resize(words)
				for w in words:
					tables[w] = exe.decode_u32(start + 4 * w)
				return tables
		i = exe.find(first, i + 1)
	return PackedInt64Array()


## Recovers the tables and the archive key from the player's game executable,
## checking candidates against the course at `course_path`. Returns
## {tables, key} or an empty dictionary.
static func find_keys(exe: PackedByteArray, course_path: String) -> Dictionary:
	var tables := find_tables(exe)
	if tables.is_empty():
		return {}
	var f := FileAccess.open(course_path, FileAccess.READ)
	if f == null:
		return {}
	var file_size := f.get_length()
	var header := f.get_buffer(HEADER_SIZE)
	var plain := is_plain(header)
	var record := PackedByteArray()
	if plain:
		if not _valid_header(header, file_size) or header.decode_u32(8) == 0:
			return {}
		f.seek(header.decode_u32(12))
		record = f.get_buffer(RECORD_SIZE)
	for key in _candidate_keys(exe):
		var cipher := Bunky.new(tables, key, DIRECTORY_ROUNDS)
		if plain:
			if _valid_record(cipher.decrypt(record), file_size):
				return {"tables": tables, "key": key}
		elif _valid_header(cipher.decrypt(header), 0):
			return {"tables": tables, "key": key}
	return {}


## The game passes the 64-bit key to its archive reader as two pushed 32-bit
## immediates (high word first), so every such pair is a candidate. The real
## key is pushed far more often than any other pair, so the most frequent
## pairs come first.
static func _candidate_keys(exe: PackedByteArray) -> Array[PackedByteArray]:
	var counts := {}
	var order: Array[int] = []
	var i := exe.find(0x68)
	while i >= 0 and i + 10 <= exe.size():
		if exe[i + 5] == 0x68:
			var pair := exe.decode_u32(i + 6) | (exe.decode_u32(i + 1) << 32)
			if counts.has(pair):
				counts[pair] += 1
			else:
				counts[pair] = 1
				order.append(pair)
		i = exe.find(0x68, i + 1)
	# Most frequent first, then in the order they appear.
	var n := order.size()
	var most := 0
	for pair in order:
		most = maxi(most, int(counts[pair]))
	var ranked: Array[int] = []
	for k in n:
		ranked.append((most - int(counts[order[k]])) * n + k)
	ranked.sort()
	var keys: Array[PackedByteArray] = []
	for rank in ranked:
		var pair := order[rank % n]
		var key := PackedByteArray()
		key.resize(8)
		key.encode_u32(0, pair & Bunky.MASK32)
		key.encode_u32(4, (pair >> 32) & Bunky.MASK32)
		keys.append(key)
	return keys


static func is_plain(header: PackedByteArray) -> bool:
	return header.size() >= 4 and header[0] == 0x41 and header[1] == 0x52 and header[2] == 0x43 and header[3] == 0x30


static func _valid_header(h: PackedByteArray, file_size: int) -> bool:
	if not is_plain(h):
		return false
	if file_size == 0:
		return true
	var count := h.decode_u32(8)
	var dir := h.decode_u32(12)
	return h.decode_u32(4) == file_size and dir <= file_size and count <= (file_size - dir) / RECORD_SIZE


## A printable, NUL-terminated name that points inside the file.
static func _valid_record(rec: PackedByteArray, file_size: int) -> bool:
	if rec.decode_u32(0) != 0 or rec[4] == 0:
		return false
	var length := 0
	while length < 32 and rec[4 + length] != 0:
		if rec[4 + length] < 0x20 or rec[4 + length] > 0x7E:
			return false
		length += 1
	if length == 32:
		return false
	var offset := rec.decode_u32(36)
	return offset <= file_size and rec.decode_u32(40) <= file_size - offset


## Opens an archive. `keys` is find_keys()'s result, or {} for an archive
## that is not locked. Returns null (with a warning) if it cannot be read.
static func open(path: String, keys: Dictionary) -> CrzArchive:
	var a := CrzArchive.new()
	a._path = path
	if not keys.is_empty():
		a._tables = keys.tables
		a._archive_key = keys.key
	a.error = a._read_directory()
	if not a.error.is_empty():
		push_warning("%s: %s" % [path, a.error])
		return null
	return a


func _read_directory() -> String:
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return "cannot open"
	_file_size = f.get_length()
	if _file_size < HEADER_SIZE:
		return "too short"
	var h := f.get_buffer(HEADER_SIZE)
	var locked := not is_plain(h)
	if locked:
		if _tables.is_empty():
			return "the course is locked and the game keys were not found"
		h = _cipher(_archive_key, DIRECTORY_ROUNDS).decrypt(h)
	if not _valid_header(h, _file_size):
		return "not a course archive, or the wrong key"
	var count := h.decode_u32(8)
	f.seek(h.decode_u32(12))
	var d := f.get_buffer(count * RECORD_SIZE)
	if locked:
		d = _cipher(_archive_key, DIRECTORY_ROUNDS).decrypt(d)
		if not _parse_directory(d, count):
			return "unreadable directory"
	elif not _parse_directory(d, count):
		# Some converted courses have a plain header but a locked directory.
		if _tables.is_empty():
			return "the directory is locked and the game keys were not found"
		if not _parse_directory(_cipher(_archive_key, DIRECTORY_ROUNDS).decrypt(d), count):
			return "unreadable directory"

	var c := find(COPYRIGHT_ENTRY)
	if c >= 0 and (not entries[c].locked or not _tables.is_empty()):
		var bytes := _unpack(entries[c], _archive_key)
		if bytes.size() >= COURSE_KEY_OFFSET + 8:
			_course_key = bytes.slice(COURSE_KEY_OFFSET, COURSE_KEY_OFFSET + 8)
	return ""


func _parse_directory(d: PackedByteArray, count: int) -> bool:
	entries.clear()
	if d.size() < count * RECORD_SIZE:
		return false
	for i in count:
		var r := i * RECORD_SIZE
		if d.decode_u32(r) != 0:
			entries.clear()
			return false
		var e := {
			"name": d.slice(r + 4, r + 36).get_string_from_ascii(),
			"offset": d.decode_u32(r + 36),
			"packed_size": d.decode_u32(r + 40),
			"size": d.decode_u32(r + 44),
			"method": d.decode_u32(r + 48),
			"locked": (d.decode_u32(r + 56) & 1) != 0,
		}
		if e.offset > _file_size or e.packed_size > _file_size - e.offset:
			entries.clear()
			return false
		entries.append(e)
	return true


func _cipher(key: PackedByteArray, rounds: int) -> Bunky:
	return Bunky.new(_tables, key, rounds)


func find(entry_name: String) -> int:
	var wanted := entry_name.to_lower()
	for i in entries.size():
		if (entries[i].name as String).to_lower() == wanted:
			return i
	return -1


func has(entry_name: String) -> bool:
	return find(entry_name) >= 0


## Reads and unpacks entry i. Returns an empty array on error.
func read(i: int) -> PackedByteArray:
	var e: Dictionary = entries[i]
	var key := _archive_key if (e.name as String).to_lower() == COPYRIGHT_ENTRY else _course_key
	return _unpack(e, key)


func read_named(entry_name: String) -> PackedByteArray:
	var i := find(entry_name)
	return read(i) if i >= 0 else PackedByteArray()


func _unpack(e: Dictionary, key: PackedByteArray) -> PackedByteArray:
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(e.offset)
	var packed := f.get_buffer(e.packed_size)
	if e.locked:
		if _tables.is_empty() or key.is_empty():
			push_warning("%s: entry %s is locked" % [_path, e.name])
			return PackedByteArray()
		packed = Bunky.new(_tables, key.slice(0, KEY_LENGTH), ENTRY_ROUNDS).decrypt(packed)
	if e.method == 0:
		return packed
	if e.method != METHOD_ZLIB:
		push_warning("%s: entry %s uses unknown method %d" % [_path, e.name, e.method])
		return PackedByteArray()
	# Godot's DEFLATE mode expects the zlib wrapper, which is what ARC0 stores.
	var out := packed.decompress(e.size, FileAccess.COMPRESSION_DEFLATE)
	if out.size() != e.size:
		push_warning("%s: entry %s did not unpack" % [_path, e.name])
		return PackedByteArray()
	return out
