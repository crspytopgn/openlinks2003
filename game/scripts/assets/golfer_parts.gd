class_name GolferParts
extends RefCounted
## The free golfer's wardrobe: every body part, outfit and hair style the
## player creator offers, with their blend shapes (body and face shapes) and
## textures, from res://assets/golfer/free_golfer_parts.olg (written by
## tools/golfer/build_free_golfer.py; the layout is in tools/golfer/look_pack.py).
##
## bake() turns a part and a set of shape weights into a plain skinned mesh:
## the shape is applied once on the CPU, so the GPU draws an ordinary mesh
## with no blend shapes, in both renderers. Meshes are cached by part and
## weights, so every hole of a round (and every golfer with the same look)
## reuses them.

const PATH := "res://assets/golfer/free_golfer_parts.olg"
const VERSION := 2
## Blend shape normal offsets are stored as 128 + offset * NORMAL_STEPS.
const NORMAL_STEPS := 100.0
## Baked meshes kept; a round with four players uses about 40.
const MESH_CACHE := 96

static var _shared: GolferParts
static var _load_failed := false

## The header: images, materials, parts, bones, shapes, defaults, ...
var info := {}
var _data := PackedByteArray()
var _parts := {}  ## name -> decoded part (Dictionary)
var _textures := {}  ## image index -> Texture2D
var _meshes := {}  ## cache key -> ArrayMesh
var _mesh_order: Array[String] = []


## The shared pack, loaded on first use; null if it is missing or damaged.
static func shared() -> GolferParts:
	if _shared == null and not _load_failed:
		_shared = load_pack(PATH)
		_load_failed = _shared == null
	return _shared


static func load_pack(path: String) -> GolferParts:
	if not FileAccess.file_exists(path):
		return null
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.size() < 12 or raw.slice(0, 4).get_string_from_ascii() != "OLGL" or raw.decode_u32(4) != VERSION:
		push_warning("GolferParts: %s is not a version %d look pack" % [path, VERSION])
		return null
	var size := raw.decode_u32(8)
	var data := raw.slice(12).decompress(size, FileAccess.COMPRESSION_GZIP)
	if data.size() != size:
		push_warning("GolferParts: %s did not inflate" % path)
		return null
	var head_size := data.decode_u32(0)
	var header: Variant = JSON.parse_string(data.slice(4, 4 + head_size).get_string_from_utf8())
	if not header is Dictionary:
		return null
	var p := GolferParts.new()
	p.info = header
	p._data = data.slice(4 + head_size)
	return p


func has_part(part_name: String) -> bool:
	return (info.get("parts", {}) as Dictionary).has(part_name)


func part_material(part_name: String) -> String:
	return str(info.parts[part_name].material)


## The bone each vertex weight refers to, by name, in bind order.
func bone_names() -> PackedStringArray:
	return PackedStringArray(info.get("bones", []))


## Shapes `weights` names (other names are ignored) -> how far they move
## each joint, summed: bone name -> offset (metres).
func joint_offsets(weights: Dictionary) -> Dictionary:
	var out := {}
	var shapes: Dictionary = info.get("shapes", {})
	for shape: String in weights:
		var w := float(weights[shape])
		if is_zero_approx(w) or not shapes.has(shape):
			continue
		var joints: Dictionary = shapes[shape].joints
		for bone: String in joints:
			var d: Array = joints[bone]
			out[bone] = out.get(bone, Vector3.ZERO) + Vector3(d[0], d[1], d[2]) * w
	return out


## Standing height (top of the head, metres) with these shape weights,
## before any scaling.
func standing_height(weights: Dictionary) -> float:
	var h := float(info.get("height", 1.75))
	var shapes: Dictionary = info.get("shapes", {})
	for shape: String in weights:
		if shapes.has(shape):
			h += float(shapes[shape].height) * float(weights[shape])
	return h


## The part with the shape applied, as a skinned ArrayMesh (no material).
## Weights below 0.001 are ignored.
func bake(part_name: String, weights: Dictionary) -> ArrayMesh:
	var used := {}
	var part := _part(part_name)
	if part.is_empty():
		return null
	for shape: String in weights:
		var w := float(weights[shape])
		if absf(w) >= 0.001 and (part.shapes as Dictionary).has(shape):
			used[shape] = snappedf(w, 0.001)
	var keys := used.keys()
	keys.sort()
	var key := part_name
	for k: String in keys:
		key += "|%s=%.3f" % [k, used[k]]
	if _meshes.has(key):
		_mesh_order.erase(key)
		_mesh_order.append(key)
		return _meshes[key]
	var verts: PackedVector3Array = (part.positions as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = (part.normals as PackedVector3Array).duplicate()
	var bent_normals := false
	for shape: String in keys:
		var w: float = used[shape]
		var s: Dictionary = _shape(part, shape)
		var rows: PackedInt32Array = s.rows
		var d: PackedVector3Array = s.positions
		for i in rows.size():
			verts[rows[i]] += d[i] * w
		if s.has("normals"):
			bent_normals = true
			var dn: PackedVector3Array = s.normals
			for i in rows.size():
				normals[rows[i]] += dn[i] * w
	if bent_normals:
		for i in normals.size():
			normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if part.has("tangents"):
		arrays[Mesh.ARRAY_TANGENT] = part.tangents
	arrays[Mesh.ARRAY_TEX_UV] = part.uvs
	arrays[Mesh.ARRAY_BONES] = part.bones
	arrays[Mesh.ARRAY_WEIGHTS] = part.weights
	arrays[Mesh.ARRAY_INDEX] = part.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	_mesh_order.append(key)
	while _mesh_order.size() > MESH_CACHE:
		_meshes.erase(_mesh_order.pop_front())
	return mesh


## The part's material, with `tint` multiplied in (the tinted materials'
## textures are grey detail). `texture_override` >= 0 swaps the texture
## (eye colours, the female skin).
func make_material(material_name: String, tint := Color.WHITE, texture_override := -1) -> StandardMaterial3D:
	var m: Dictionary = info.materials[material_name]
	var mat := StandardMaterial3D.new()
	mat.resource_name = material_name
	var colour: Array = m.get("colour", [1, 1, 1])
	mat.albedo_color = Color(colour[0], colour[1], colour[2]) * tint
	mat.albedo_color.a = 1.0
	var tex := texture_override if texture_override >= 0 else int(m.texture)
	if tex >= 0:
		mat.albedo_texture = texture(tex)
	if int(m.normal) >= 0:
		mat.normal_enabled = true
		mat.normal_texture = texture(int(m.normal))
	mat.roughness = float(m.roughness)
	if float(m.cutoff) > 0.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = float(m.cutoff)
	if bool(m.double_sided):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Image `index` of the pack as a mipmapped texture (decoded once).
func texture(index: int) -> Texture2D:
	if _textures.has(index):
		return _textures[index]
	var entry: Dictionary = info.images[index]
	var bytes := _slice(entry.data)
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes) if entry.kind == "png" else img.load_jpg_from_buffer(bytes)
	if err != OK:
		push_warning("GolferParts: image %d did not decode" % index)
		return null
	# Grey-and-alpha images become RGBA: WebGL has no swizzle for them.
	if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8 if img.detect_alpha() != Image.ALPHA_NONE else Image.FORMAT_RGB8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[index] = tex
	return tex


func _slice(span: Array) -> PackedByteArray:
	return _data.slice(int(span[0]), int(span[0]) + int(span[1]))


## Half floats (3 per row) to Vector3s, through Image's converter.
func _halves3(span: Array) -> PackedVector3Array:
	var bytes := _slice(span)
	var n := bytes.size() / 6
	var img := Image.create_from_data(n, 1, false, Image.FORMAT_RGBH, bytes)
	img.convert(Image.FORMAT_RGBF)
	return _vec3(img.get_data().to_float32_array())


## Offset bytes (3 per row, see NORMAL_STEPS) to Vector3s.
func _bytes3(span: Array) -> PackedVector3Array:
	var bytes := _slice(span)
	var out := PackedVector3Array()
	out.resize(bytes.size() / 3)
	var k := 1.0 / NORMAL_STEPS
	for i in out.size():
		out[i] = Vector3(bytes[3 * i] - 128, bytes[3 * i + 1] - 128, bytes[3 * i + 2] - 128) * k
	return out


static func _vec3(f: PackedFloat32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(f.size() / 3)
	for i in out.size():
		out[i] = Vector3(f[3 * i], f[3 * i + 1], f[3 * i + 2])
	return out


func _part(part_name: String) -> Dictionary:
	if _parts.has(part_name):
		return _parts[part_name]
	if not has_part(part_name):
		return {}
	var e: Dictionary = info.parts[part_name]
	var p := {}
	p.positions = _vec3(_slice(e.positions).to_float32_array())
	p.normals = _halves3(e.normals)
	var uv := _slice(e.uvs).to_float32_array()
	var uvs := PackedVector2Array()
	uvs.resize(uv.size() / 2)
	for i in uvs.size():
		uvs[i] = Vector2(uv[2 * i], uv[2 * i + 1])
	p.uvs = uvs
	p.bones = _slice(e.bones).to_int32_array()
	p.weights = _slice(e.weights).to_float32_array()
	p.indices = _slice(e.indices).to_int32_array()
	if e.has("tangents"):
		var bytes := _slice(e.tangents)
		var img := Image.create_from_data(bytes.size() / 8, 1, false, Image.FORMAT_RGBAH, bytes)
		img.convert(Image.FORMAT_RGBAF)
		p.tangents = img.get_data().to_float32_array()
	p.shapes = e.shapes
	p.decoded = {}
	_parts[part_name] = p
	return p


func _shape(part: Dictionary, shape: String) -> Dictionary:
	var decoded: Dictionary = part.decoded
	if decoded.has(shape):
		return decoded[shape]
	var e: Dictionary = part.shapes[shape]
	var s := {"rows": _slice(e.rows).to_int32_array(), "positions": _halves3(e.positions)}
	if e.has("normals_u8"):
		s.normals = _bytes3(e.normals_u8)
	decoded[shape] = s
	return s
