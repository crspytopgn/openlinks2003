class_name XyzModel
extends RefCounted
## Course Designer 3D objects: .XYZ meshes with .CMF textures. See
## docs/formats/model.md; mirrors libs/olcore/src/model.cpp.

const INCH := 0.0254
const LEVELS_PER_TEXTURE := 4


## Reads the textures in a .CMF archive (largest level of each). Returns an
## empty array on error.
static func read_textures(cmf: PackedByteArray) -> Array[Image]:
	var out: Array[Image] = []
	var arc := Arc0.from_bytes(cmf)
	if arc == null:
		return out
	var t := arc.read_named("Textures")
	var pos := 4
	var level := 0
	while pos + 8 <= t.size():
		var w := t.decode_u32(pos)
		var h := t.decode_u32(pos + 4)
		pos += 8
		var bw := (w + 3) / 4
		var bh := (h + 3) / 4
		var blocks := PackedByteArray()
		pos = Btcv.decode_runs(t, pos, bw * bh, blocks)
		if pos < 0:
			return [] as Array[Image]
		if level % LEVELS_PER_TEXTURE == 0:
			var img := Btcv.dxt5_to_image(blocks, bw, bh, w, h)
			if img == null:
				return [] as Array[Image]
			img.generate_mipmaps()
			out.append(img)
		level += 1
	return out


## Builds a mesh in metres from .XYZ bytes and the .CMF textures. Returns null
## on error.
static func build_mesh(xyz: PackedByteArray, textures: Array[Image]) -> ArrayMesh:
	if xyz.size() < 0xa4 or xyz.decode_u32(0) != xyz.size():
		return null
	var counts := PackedInt32Array()
	var offsets := PackedInt32Array()
	for i in 5:
		counts.append(xyz.decode_u32(0x18 + 8 * i))
		offsets.append(xyz.decode_u32(0x1c + 8 * i))
	var positions := PackedVector3Array()
	for i in counts[0]:
		var p := offsets[0] + 12 * i
		positions.append(Vector3(xyz.decode_float(p), xyz.decode_float(p + 4), xyz.decode_float(p + 8)) * INCH)
	var by_texture := {}
	for f in counts[2]:
		var p := offsets[2] + 12 * f
		var n := xyz.decode_u16(p)
		var first := xyz.decode_u16(p + 2)
		var tex := xyz.decode_u16(p + 6)
		if not by_texture.has(tex):
			by_texture[tex] = SurfaceTool.new()
			(by_texture[tex] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
		var st: SurfaceTool = by_texture[tex]
		# Fan from the first corner. Godot treats clockwise as front-facing,
		# the reverse of this data, so emit each triangle backwards.
		for k in range(1, n - 1):
			for c: int in [first, first + k + 1, first + k]:
				var uv := offsets[1] + 8 * c
				st.set_uv(Vector2(xyz.decode_float(uv), xyz.decode_float(uv + 4)))
				st.add_vertex(positions[xyz.decode_u16(offsets[3] + 2 * c)])
	var mesh := ArrayMesh.new()
	var keys := by_texture.keys()
	keys.sort()
	for tex: int in keys:
		var st: SurfaceTool = by_texture[tex]
		st.generate_normals()
		st.commit(mesh)
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if tex < textures.size():
			mat.albedo_texture = ImageTexture.create_from_image(textures[tex])
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh
