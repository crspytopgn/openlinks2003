class_name CourseModels
extends RefCounted
## 3D objects (bridges, benches, fences, buildings) of a course exported by
## `olcourse export`, read from models.bin. See docs/formats/course-objects.md.


## A parsed models.bin: "meshes" is an Array of meshes, each an Array of
## surfaces {texture, positions, uvs, indices}; "placements" is an Array of
## {model, transform}. Returns an empty Dictionary if the data is not valid.
static func read(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "OLMD" or bytes.decode_u32(4) != 1:
		return {}
	var pos := 8
	var meshes: Array = []
	var model_count := bytes.decode_u32(pos)
	pos += 4
	for _m in model_count:
		if pos + 4 > bytes.size():
			return {}
		var surfaces: Array = []
		var surface_count := bytes.decode_u32(pos)
		pos += 4
		for _s in surface_count:
			if pos + 4 > bytes.size():
				return {}
			var name_length := bytes.decode_u32(pos)
			pos += 4
			if pos + name_length + 4 > bytes.size():
				return {}
			var texture := bytes.slice(pos, pos + name_length).get_string_from_utf8()
			pos += name_length
			var vertex_count := bytes.decode_u32(pos)
			pos += 4
			if pos + vertex_count * 20 + 4 > bytes.size():
				return {}
			var floats := bytes.slice(pos, pos + vertex_count * 12).to_float32_array()
			pos += vertex_count * 12
			var uv_floats := bytes.slice(pos, pos + vertex_count * 8).to_float32_array()
			pos += vertex_count * 8
			var index_count := bytes.decode_u32(pos)
			pos += 4
			if pos + index_count * 4 > bytes.size():
				return {}
			var indices := bytes.slice(pos, pos + index_count * 4).to_int32_array()
			pos += index_count * 4
			var positions := PackedVector3Array()
			var uvs := PackedVector2Array()
			positions.resize(vertex_count)
			uvs.resize(vertex_count)
			for i in vertex_count:
				positions[i] = Vector3(floats[3 * i], floats[3 * i + 1], floats[3 * i + 2])
				uvs[i] = Vector2(uv_floats[2 * i], uv_floats[2 * i + 1])
			surfaces.append({"texture": texture, "positions": positions, "uvs": uvs, "indices": indices})
		meshes.append(surfaces)
	if pos + 4 > bytes.size():
		return {}
	var placements: Array = []
	var placement_count := bytes.decode_u32(pos)
	pos += 4
	if pos + placement_count * 52 > bytes.size():
		return {}
	for _p in placement_count:
		var model := bytes.decode_u32(pos)
		var t := bytes.slice(pos + 4, pos + 52).to_float32_array()
		pos += 52
		# Row-major 3x4 to a Basis of columns plus an origin.
		var basis := Basis(Vector3(t[0], t[4], t[8]), Vector3(t[1], t[5], t[9]), Vector3(t[2], t[6], t[10]))
		placements.append({"model": model, "transform": Transform3D(basis, Vector3(t[3], t[7], t[11]))})
	return {"meshes": meshes, "placements": placements}


## Builds one node per placement; textures load from `dir`.
static func build(dir: String, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Models"
	var textures := {}
	var meshes: Array[ArrayMesh] = []
	for surfaces: Array in data.get("meshes", []):
		meshes.append(_mesh(dir, surfaces, textures))
	for placement: Dictionary in data.get("placements", []):
		var model: int = placement["model"]
		if model >= meshes.size():
			continue
		var node := MeshInstance3D.new()
		node.mesh = meshes[model]
		node.transform = placement["transform"]
		root.add_child(node)
	return root


static func _mesh(dir: String, surfaces: Array, textures: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface: Dictionary in surfaces:
		var positions: PackedVector3Array = surface["positions"]
		var uvs: PackedVector2Array = surface["uvs"]
		var indices: PackedInt32Array = surface["indices"]
		if indices.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in positions.size():
			st.set_uv(uvs[i])
			st.add_vertex(positions[i])
		# The files wind triangles the other way round from Godot.
		for i in range(0, indices.size() - 2, 3):
			st.add_index(indices[i])
			st.add_index(indices[i + 2])
			st.add_index(indices[i + 1])
		st.generate_normals()
		st.set_material(_material(dir, str(surface["texture"]), textures))
		st.commit(mesh)
	return mesh


static func _material(dir: String, file: String, textures: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # thin parts are single-sided
	mat.roughness = 1.0
	if not textures.has(file):
		var image: Image = null
		var path := dir.path_join(file)
		if not file.is_empty() and FileAccess.file_exists(path):
			image = Image.load_from_file(path)
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			textures[file] = ImageTexture.create_from_image(image)
		else:
			textures[file] = null
	var tex: Texture2D = textures[file]
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = Color(0.6, 0.6, 0.6)
	return mat
