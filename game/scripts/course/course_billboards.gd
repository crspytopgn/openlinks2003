class_name CourseBillboards
extends RefCounted
## Billboard objects (trees, bushes, grass) of a course exported by
## `olcourse export`: course.json lists the types under "billboards" and
## objects.bin holds the placements. See docs/formats/course-objects.md.
##
## Placements are grouped into square chunks per type, one MultiMesh each, so
## small plants can be hidden beyond a distance chunk by chunk.

const CHUNK_METRES := 100.0
const FLOATS_PER_PLACEMENT := 4  ## x, y, z (base, Godot metres), height


## Reads objects.bin: one PackedFloat32Array per type, FLOATS_PER_PLACEMENT
## values per placement. Returns an empty array if the data is not valid.
static func read_placements(bytes: PackedByteArray) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "OLOB" or bytes.decode_u32(4) != 1:
		return out
	var types := bytes.decode_u32(8)
	var pos := 12
	for _t in types:
		if pos + 4 > bytes.size():
			out.clear()
			return out
		var count := bytes.decode_u32(pos)
		pos += 4
		var length := count * FLOATS_PER_PLACEMENT * 4
		if pos + length > bytes.size():
			out.clear()
			return out
		out.append(bytes.slice(pos, pos + length).to_float32_array())
		pos += length
	return out


## Beyond this distance a chunk of billboards of this height is hidden
## (0 = always drawn).
static func visibility_end(height_m: float) -> float:
	if height_m < 0.6:
		return 150.0
	if height_m < 2.0:
		return 300.0
	if height_m < 5.0:
		return 700.0
	return 0.0


## Builds the billboards. `types` is course.json's "billboards" array and
## `placements` comes from read_placements(); textures load from `dir`.
static func build(dir: String, types: Array, placements: Array[PackedFloat32Array]) -> Node3D:
	var root := Node3D.new()
	root.name = "Billboards"
	for t in mini(types.size(), placements.size()):
		var data: PackedFloat32Array = placements[t]
		if data.is_empty():
			continue
		var info: Dictionary = types[t]
		var material := _material(dir.path_join(str(info.get("texture", ""))))
		var quad := QuadMesh.new()
		quad.size = Vector2(float(info.get("aspect", 1.0)), 1.0)
		quad.center_offset = Vector3(0, 0.5, 0)
		quad.material = material

		# Group placements by chunk, keeping the tallest height for culling.
		var chunks := {}
		var tallest := {}
		@warning_ignore("integer_division")
		var count := data.size() / FLOATS_PER_PLACEMENT
		for i in count:
			var k := i * FLOATS_PER_PLACEMENT
			var key := Vector2i(floori(data[k] / CHUNK_METRES), floori(data[k + 2] / CHUNK_METRES))
			if not chunks.has(key):
				chunks[key] = []
				tallest[key] = 0.0
			var list: Array = chunks[key]
			list.append(k)
			tallest[key] = maxf(float(tallest[key]), data[k + 3])

		for key: Vector2i in chunks:
			var list: Array = chunks[key]
			var buffer := PackedFloat32Array()
			buffer.resize(list.size() * 12)
			# Origins relative to the chunk centre: visibility ranges are
			# measured from the node.
			var ground := 0.0
			for k: int in list:
				ground += data[k + 1]
			var centre := Vector3((key.x + 0.5) * CHUNK_METRES, ground / list.size(), (key.y + 0.5) * CHUNK_METRES)
			var b := 0
			for k: int in list:
				var h: float = data[k + 3]
				# Row-major 3x4: uniform scale by the height, then the origin.
				buffer[b] = h
				buffer[b + 3] = data[k] - centre.x
				buffer[b + 5] = h
				buffer[b + 7] = data[k + 1] - centre.y
				buffer[b + 10] = h
				buffer[b + 11] = data[k + 2] - centre.z
				b += 12
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = quad
			mm.instance_count = list.size()
			mm.buffer = buffer
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.position = centre
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = visibility_end(float(tallest[key]))
			root.add_child(node)
	return root


static func _material(path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # the sprites are pre-lit
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var image: Image = null
	if FileAccess.file_exists(path):
		image = Image.load_from_file(path)
	if image != null and not image.is_empty():
		image.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(image)
	else:
		mat.albedo_color = Color(0.2, 0.4, 0.15)
	return mat
