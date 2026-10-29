class_name LsArchiveFile
extends RefCounted
## Reads LSls archives (.LS, .L3, .TIP) from the player's game folder
## (docs/formats/ls-archive.md).
##
## Temporary GDScript port of libs/olcore/src/ls_archive.cpp and lzw.cpp so
## golfer files load without a compiled extension. It will be replaced by the
## C++ library via GDExtension; keep the two in sync until then.

const BLOCK_HEADER_SIZE := 0x37

var _data: PackedByteArray
## Upper-case name -> [header offset, data offset, stored size, original size, compressed]
var _entries := {}


## Null if the file is missing or not an LSls archive.
static func open(path: String) -> LsArchiveFile:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < BLOCK_HEADER_SIZE or bytes.slice(0, 4).get_string_from_ascii() != "LSls":
		return null
	var archive := LsArchiveFile.new()
	if not archive._parse(bytes):
		return null
	return archive


func names() -> PackedStringArray:
	return PackedStringArray(_entries.keys())


func has(entry_name: String) -> bool:
	return _entries.has(entry_name.to_upper())


## The entry's contents, decompressed; empty if it isn't there.
func read(entry_name: String) -> PackedByteArray:
	var e: Array = _entries.get(entry_name.to_upper(), [])
	if e.is_empty():
		return PackedByteArray()
	var stored := _data.slice(e[1], e[1] + e[2])
	if not e[4]:
		return stored
	var xor5: bool = _data[e[0] + 0x36] != 0
	return lzw_decompress(stored, e[3], xor5)


func _parse(bytes: PackedByteArray) -> bool:
	_data = bytes
	var version := bytes.decode_u16(4)
	var name_width := 13 if version == 0x020b else (64 if version == 0x020c else 0)
	if name_width == 0:
		return false
	var header_size := bytes.decode_u16(6)
	var count := bytes.decode_u32(0x0a)
	var slot := name_width + 4
	for i in count:
		var base := header_size + i * slot
		if base + slot > bytes.size():
			return false
		var end := base
		while end < base + name_width and bytes[end] != 0:
			end += 1
		var entry_name := bytes.slice(base, end).get_string_from_ascii().to_upper()
		var header := bytes.decode_u32(base + name_width)
		if header + BLOCK_HEADER_SIZE > bytes.size():
			return false
		var data_offset := header + bytes.decode_u16(header + 6)
		var stored := bytes.decode_u32(header + 0x1d)
		if data_offset + stored > bytes.size():
			return false
		_entries[entry_name] = [header, data_offset, stored, bytes.decode_u32(header + 0x19), bytes[header + 0x18] == 1]
	return true


## Variable-width LZW: codes LSB first, 9 to 13 bits, 256 clear, 257 end.
## Mirrors olcore::lzw_decompress.
static func lzw_decompress(src: PackedByteArray, max_output: int, xor5 := false) -> PackedByteArray:
	var s := src.duplicate()
	if xor5:
		for i in s.size():
			s[i] ^= 5
	var prefix := PackedInt32Array()
	prefix.resize(8192)
	var suffix := PackedByteArray()
	suffix.resize(8192)
	var stack := PackedByteArray()
	stack.resize(8192)
	var out := PackedByteArray()
	out.resize(max_output)
	var n := 0
	var total_bits := s.size() * 8
	s.append_array(PackedByteArray([0, 0, 0]))  # so a 3-byte window never runs off the end
	var bit := 0
	var width := 9
	var next_free := 258
	var prev := -1
	var first := 0
	while n < max_output and bit + width <= total_bits:
		var byte := bit >> 3
		var window := s[byte] | (s[byte + 1] << 8) | (s[byte + 2] << 16)
		var code := (window >> (bit & 7)) & ((1 << width) - 1)
		bit += width
		if code == 256:
			width = 9
			next_free = 258
			prev = -1
			continue
		if code == 257:
			break
		if prev < 0:
			if code > 255:
				break
			out[n] = code
			n += 1
			prev = code
			first = code
			continue
		if code > next_free or (code == next_free and next_free >= 8192):
			break
		var depth := 0
		var cur := code
		if code == next_free:
			stack[depth] = first
			depth += 1
			cur = prev
		while cur >= 258:
			stack[depth] = suffix[cur]
			depth += 1
			cur = prefix[cur]
		first = cur
		stack[depth] = cur
		depth += 1
		while depth > 0 and n < max_output:
			depth -= 1
			out[n] = stack[depth]
			n += 1
		if next_free < 8192:
			prefix[next_free] = prev
			suffix[next_free] = first
			next_free += 1
			if next_free >= (1 << width) and width < 13:
				width += 1
		prev = code
	out.resize(n)
	return out
