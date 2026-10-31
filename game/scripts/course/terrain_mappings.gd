class_name TerrainMappings
extends RefCounted
## The course's `Mappings` entry: how each terrain triangle lays its
## textures on the ground, and how a blended material fades one texture
## into another through its mask. Ports libs/olcore/src/terrain_mapping.cpp;
## change both together. See "Mappings" in docs/formats/crz.md.

const VERSION := 5
const HEADER_SIZE := 48

enum Kind { PLANAR = 0, CYLINDRICAL = 1, STRIP = 3, BLEND = 4 }


## `Mappings` entry: one dictionary per record, in order (triangles refer to
## records by position). Every record has kind and name. Planar and
## cylindrical: scale (Vector2), frame (16 floats: the u, v and w axes in
## feet per repeat, then the origin, each as a row of four). Strip: scale,
## strip_triangles (triangle index, then three corner indices, per
## triangle), corner_vertex (vertex index per corner), corner_uv. Blend:
## layers (the mask's strip, then the mapping of each layer). Empty on
## error.
static func parse(b: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if b.size() < HEADER_SIZE or b.decode_u32(0) != VERSION:
		return out
	var count := b.decode_u32(4)
	if count > b.size() / 12:
		return out
	var o := HEADER_SIZE
	for _i in count:
		if o + 12 > b.size():
			return []
		var kind := b.decode_u32(o)
		var name_length := b.decode_u32(o + 8)
		o += 12
		if o + name_length > b.size():
			return []
		var m := {"kind": kind, "name": b.slice(o, o + name_length).get_string_from_ascii()}
		o += name_length
		match kind:
			Kind.BLEND:
				if o + 20 > b.size():
					return []
				var layers := PackedInt32Array([b.decode_u32(o), b.decode_u32(o + 4), b.decode_u32(o + 8)])
				for l in layers:
					if l >= count:
						return []
				m.layers = layers
				o += 20
			Kind.PLANAR, Kind.CYLINDRICAL:
				if o + 72 > b.size():
					return []
				m.scale = Vector2(b.decode_float(o), b.decode_float(o + 4))
				var frame := PackedFloat32Array()
				frame.resize(16)
				for k in 16:
					frame[k] = b.decode_float(o + 8 + 4 * k)
				m.frame = frame
				o += 72
			Kind.STRIP:
				if o + 12 > b.size():
					return []
				m.scale = Vector2(b.decode_float(o), b.decode_float(o + 4))
				var nt := b.decode_u32(o + 8)
				o += 12
				if nt > (b.size() - o) / 20:
					return []
				var tris := PackedInt32Array()
				tris.resize(nt * 4)
				for t in nt:
					tris[4 * t] = b.decode_u32(o + 4)  # skips the index in an older mesh
					for k in 3:
						tris[4 * t + 1 + k] = b.decode_u32(o + 8 + 4 * k)
					o += 20
				if o + 4 > b.size():
					return []
				var nc := b.decode_u32(o)
				o += 4
				if nc > (b.size() - o) / 16:
					return []
				var verts := PackedInt32Array()
				verts.resize(nc)
				var uvs := PackedVector2Array()
				uvs.resize(nc)
				for c in nc:
					verts[c] = b.decode_u32(o + 4)
					uvs[c] = Vector2(b.decode_float(o + 8), b.decode_float(o + 12))
					o += 16
				for t in nt:
					for k in 3:
						if tris[4 * t + 1 + k] >= nc:
							return []
				m.strip_triangles = tris
				m.corner_vertex = verts
				m.corner_uv = uvs
			_:
				return []
		out.append(m)
	if o != b.size():
		return []
	return out


## Texture coordinates of a course point `p` (feet, z up) under a planar or
## cylindrical mapping `m`.
static func uv(m: Dictionary, p: Vector3) -> Vector2:
	var f: PackedFloat32Array = m.frame
	var basis := Basis(Vector3(f[0], f[1], f[2]), Vector3(f[4], f[5], f[6]), Vector3(f[8], f[9], f[10]))
	if absf(basis.determinant()) < 1e-12:
		return Vector2.ZERO
	# p = origin + u * a + v * b + w * c, with a, b, c the basis columns.
	var local := basis.inverse() * (p - Vector3(f[12], f[13], f[14]))
	var scale: Vector2 = m.scale
	if m.kind == Kind.CYLINDRICAL:
		return Vector2(atan2(local.y, local.x) / TAU * scale.x, local.z * scale.y)
	return Vector2(local.x * scale.x, local.y * scale.y)


## Godot metres (y up) to course feet (z up): the inverse of
## CrzCourseLoader.to_godot().
static func to_course(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y) / CrzCourseLoader.FEET


## A `Materials` record (from CrzCourseLoader.parse_materials) as texture
## layers: {blended, mask (texture index or -1), layers (base texture index
## per layer)}. Each layer is a base texture followed by up to two detail
## variants (two bits per layer in the record's kind), which are skipped.
static func material_layers(m: Dictionary) -> Dictionary:
	var textures: PackedInt32Array = m.textures
	var bits: int = m.get("kind", 0)
	var blended: bool = m.get("mode", 0) == 3 and m.get("layer_count", 1) >= 3
	var mask := -1
	var layers := PackedInt32Array()
	var slot := 0
	var layer := 0
	while slot < textures.size():
		var base := textures[slot]
		var details := (bits >> (2 * layer)) & 3
		slot += 1 + (details & 1) + ((details >> 1) & 1)
		if blended and layer == 0:
			mask = base
		else:
			layers.append(base)
		layer += 1
	return {"blended": blended, "mask": mask, "layers": layers}
