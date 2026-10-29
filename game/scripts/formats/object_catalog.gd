class_name ObjectCatalog
extends RefCounted
## The Course Designer catalog, OBJECT.LIB. See
## docs/formats/object-library.md; mirrors libs/olcore/src/object_library.cpp.

const KIND_BILLBOARD := 1
const KIND_MODEL := 2

## Each category: {name: String, objects: Array[Dictionary]}. Each object:
## {name, path, kind, params, size, id, top_view, collision, shape}.
var categories: Array[Dictionary] = []

var _bytes: PackedByteArray
var _pos := 0
var _ok := true


static func from_bytes(bytes: PackedByteArray) -> ObjectCatalog:
	var lib := ObjectCatalog.new()
	lib._bytes = bytes
	lib._parse()
	lib._bytes = PackedByteArray()
	return lib if lib._ok else null


func _u32() -> int:
	if _pos + 4 > _bytes.size():
		_ok = false
		return 0
	var v := _bytes.decode_u32(_pos)
	_pos += 4
	return v


func _f32() -> float:
	if _pos + 4 > _bytes.size():
		_ok = false
		return 0.0
	var v := _bytes.decode_float(_pos)
	_pos += 4
	return v


func _floats(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(_f32())
	return out


## u32 length including the NUL, then the bytes.
func _string() -> String:
	var n := _u32()
	if n == 0:
		return ""
	if _pos + n > _bytes.size():
		_ok = false
		return ""
	var s := _bytes.slice(_pos, _pos + n).get_string_from_ascii()
	_pos += n
	return s


func _parse() -> void:
	_u32()  # counter, see the format notes
	var category_count := _u32()
	for c in category_count:
		if not _ok:
			return
		var cat := {"name": _string(), "objects": [] as Array[Dictionary]}
		var count := _u32()
		for i in count:
			if not _ok:
				return
			var o := {}
			o.name = _string()
			o.path = _string()
			o.kind = _u32()
			o.params = _floats(4)
			o.size = _floats(3)
			_floats(2)
			o.id = _u32()
			o.top_view = _string()
			o.collision = _u32()
			o.shape = _floats(6)
			cat.objects.append(o)
		categories.append(cat)


func find_id(id: int) -> Dictionary:
	for cat in categories:
		for o: Dictionary in cat.objects:
			if o.id == id:
				return o
	return {}


## Default height in metres for a billboard: the middle of the Designer's size
## range, which the format notes read as feet. Courses will store their own.
static func default_height_m(o: Dictionary) -> float:
	var p: PackedFloat32Array = o.params
	return (p[1] + p[2]) * 0.5 * 0.3048
