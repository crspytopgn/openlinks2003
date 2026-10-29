class_name Arc0
extends RefCounted
## Reader for ARC0 archives (.LIB, .BTX, .TOP, .CMF). See docs/formats/arc0.md
## and libs/olcore/src/arc0.cpp, which this mirrors.

const METHOD_ZLIB := 2

var data: PackedByteArray
## Each entry: {name, offset, packed_size, size, method}
var entries: Array[Dictionary] = []


static func is_arc0(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 16 and bytes.slice(0, 4).get_string_from_ascii() == "ARC0"


static func from_bytes(bytes: PackedByteArray) -> Arc0:
	if not is_arc0(bytes):
		return null
	var a := Arc0.new()
	a.data = bytes
	var count := bytes.decode_u32(8)
	var dir := bytes.decode_u32(12)
	if dir + count * 64 > bytes.size():
		return null
	for i in count:
		var r := dir + i * 64
		var e := {
			"name": bytes.slice(r + 4, r + 36).get_string_from_ascii(),
			"offset": bytes.decode_u32(r + 36),
			"packed_size": bytes.decode_u32(r + 40),
			"size": bytes.decode_u32(r + 44),
			"method": bytes.decode_u32(r + 48),
		}
		if e.offset + e.packed_size > bytes.size():
			return null
		a.entries.append(e)
	return a


func find(entry_name: String) -> int:
	var wanted := entry_name.to_lower()
	for i in entries.size():
		if (entries[i].name as String).to_lower() == wanted:
			return i
	return -1


## Unpacks entry i. Returns an empty array on error.
func read(i: int) -> PackedByteArray:
	var e: Dictionary = entries[i]
	if e.method != METHOD_ZLIB:
		push_warning("ARC0 entry %s uses unknown method %d" % [e.name, e.method])
		return PackedByteArray()
	var packed := data.slice(e.offset, e.offset + e.packed_size)
	# Godot's DEFLATE mode expects the zlib wrapper, which is what ARC0 stores.
	var out := packed.decompress(e.size, FileAccess.COMPRESSION_DEFLATE)
	if out.size() != e.size:
		push_warning("ARC0 entry %s did not unpack" % e.name)
		return PackedByteArray()
	return out


func read_named(entry_name: String) -> PackedByteArray:
	var i := find(entry_name)
	return read(i) if i >= 0 else PackedByteArray()
