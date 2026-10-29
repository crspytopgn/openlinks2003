class_name GolferAnimData
extends RefCounted
## Reads golfer skeletons (.SKL) and animation clips (.CLP): the Carrera
## object store described in docs/formats/carrera-store.md.
##
## Temporary GDScript port of libs/olcore/src/carrera_store.cpp and
## golfer_anim.cpp. It will be replaced by the C++ library via GDExtension;
## keep the two in sync until then.

const SECTION_MAGIC := 0xdeadbeef
const SAMPLE_SCALE := 1.0 / 2048.0
const FRAMES_PER_SECOND := 30.0
const NODE_PARENT := 0x1c
const NODE_TRANSLATE := 280
const NODE_ROTATE := 292
const JOINT_ORIENT := 440

static var _crc_table := PackedInt64Array()


## CRC-32 of the name, which is how clips refer to nodes.
static func name_hash(text: String) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for k in 8:
				c = (c >> 1) ^ 0xedb88320 if c & 1 else c >> 1
			_crc_table[i] = c
	var crc := 0xffffffff
	for b in text.to_ascii_buffer():
		crc = _crc_table[(crc ^ b) & 0xff] ^ (crc >> 8)
	return crc ^ 0xffffffff


## Allocations of a store: Array of {offset, size, class_name, name}.
## Empty if the bytes are not a store.
static func read_allocations(d: PackedByteArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sections: Array[PackedInt32Array] = []  # [count, element size, body]
	var pos := 0
	for i in 7:
		var pad := 0
		while pos + pad + 16 <= d.size() and d.decode_u32(pos + pad) != SECTION_MAGIC:
			pad += 1
			if pad > 3:
				return result
		pos += pad
		if pos + 16 > d.size():
			return result
		var count := d.decode_u32(pos + 4)
		var size := d.decode_u32(pos + 12)
		sections.append(PackedInt32Array([count, size, pos + 16]))
		pos += 16 + count * size
		if pos > d.size():
			return result
	var strings := PackedStringArray()
	var table := sections[4]
	var pool_body := sections[5][2]
	for i in table[0]:
		var length := d.decode_u32(table[2] + i * 8)
		var off := d.decode_u32(table[2] + i * 8 + 4)
		strings.append(d.slice(pool_body + off, pool_body + off + length - 1).get_string_from_ascii())
	var classes := PackedStringArray()
	var cls := sections[6]
	for i in cls[0]:
		var si := d.decode_s32(cls[2] + i * 20)
		classes.append(strings[si] if si >= 0 and si < strings.size() else "")
	var al := sections[1]
	for i in al[0]:
		var rec := al[2] + i * 44
		var ci := d.decode_s32(rec + 12)
		var ni := d.decode_s32(rec + 16)
		result.append({
			"offset": d.decode_u32(rec + 4),
			"size": d.decode_u32(rec + 8),
			"class_name": classes[ci] if ci >= 0 and ci < classes.size() else "",
			"name": strings[ni] if ni >= 0 and ni < strings.size() else "",
		})
	return result


## Joints and transforms, parents first. Each node:
## {name, hash, parent (index or -1), joint, translate, rotate, orient}.
static func read_skeleton(d: PackedByteArray) -> Array[Dictionary]:
	var raw: Array[Dictionary] = []
	var by_offset := {}
	for a in read_allocations(d):
		var joint: bool = a["class_name"] == "class Carrera::Joint"
		if not joint and a["class_name"] != "class Carrera::Transform" and a["class_name"] != "class Carrera::TransformEx":
			continue
		var o: int = a["offset"]
		var node := {
			"name": a["name"],
			"hash": name_hash(a["name"]),
			"joint": joint,
			"translate": Vector3(d.decode_float(o + NODE_TRANSLATE), d.decode_float(o + NODE_TRANSLATE + 4), d.decode_float(o + NODE_TRANSLATE + 8)),
			"rotate": Vector3(d.decode_float(o + NODE_ROTATE), d.decode_float(o + NODE_ROTATE + 4), d.decode_float(o + NODE_ROTATE + 8)),
			"orient": Quaternion.IDENTITY,
			"parent_offset": d.decode_u32(o + NODE_PARENT),
		}
		if joint:
			node["orient"] = Quaternion(d.decode_float(o + JOINT_ORIENT), d.decode_float(o + JOINT_ORIENT + 4),
					d.decode_float(o + JOINT_ORIENT + 8), d.decode_float(o + JOINT_ORIENT + 12)).normalized()
		by_offset[o] = raw.size()
		raw.append(node)
	var ordered: Array[Dictionary] = []
	var new_index := PackedInt32Array()
	new_index.resize(raw.size())
	new_index.fill(-1)
	for i in raw.size():
		_place(i, raw, by_offset, new_index, ordered, 0)
	return ordered


static func _place(i: int, raw: Array[Dictionary], by_offset: Dictionary, new_index: PackedInt32Array,
		ordered: Array[Dictionary], depth: int) -> int:
	if new_index[i] >= 0 or depth > 1000:
		return new_index[i]
	var parent := -1
	var po: int = raw[i]["parent_offset"]
	if po != 0 and by_offset.has(po):
		parent = _place(by_offset[po], raw, by_offset, new_index, ordered, depth + 1)
	var node: Dictionary = raw[i].duplicate()
	node.erase("parent_offset")
	node["parent"] = parent
	new_index[i] = ordered.size()
	ordered.append(node)
	return new_index[i]


## The first clip with channels, or {} if none:
## {name, frames, dynamic, node_hashes, attributes, samples}.
## attributes: 0-2 translate x/y/z, 3-5 rotate x/y/z, -1 unknown.
static func read_clip(d: PackedByteArray) -> Dictionary:
	for a in read_allocations(d):
		if a["class_name"] != "class Carrera::AnimClip":
			continue
		var o: int = a["offset"]
		var channel_count := d.decode_u32(o + 0x30)
		if channel_count == 0:
			continue
		var frames := d.decode_u32(o + 0x2c)
		var dynamic := d.decode_u32(o + 0x34)
		var channels := d.decode_u32(o + 0x38)
		var samples := d.decode_u32(o + 0x3c)
		var sample_count := channel_count + (frames - 1) * dynamic
		if frames == 0 or dynamic > channel_count or channels + channel_count * 20 > d.size() \
				or samples + sample_count * 2 > d.size():
			return {}
		var node_hashes := PackedInt64Array()
		var attributes := PackedInt32Array()
		for i in channel_count:
			node_hashes.append(d.decode_u32(channels + i * 20 + 4))
			var field := d.decode_u32(channels + i * 20 + 8)
			var attr := -1
			if field >= NODE_TRANSLATE and field <= NODE_ROTATE + 8 and (field - NODE_TRANSLATE) % 4 == 0:
				attr = (field - NODE_TRANSLATE) / 4
			attributes.append(attr)
		var values := PackedFloat32Array()
		values.resize(sample_count)
		for i in sample_count:
			values[i] = d.decode_s16(samples + i * 2) * SAMPLE_SCALE
		var name_ptr := d.decode_u32(o + 0x10)
		var clip_name := ""
		if name_ptr > 0 and name_ptr < d.size():
			var end := name_ptr
			while end < d.size() and d[end] != 0:
				end += 1
			clip_name = d.slice(name_ptr, end).get_string_from_ascii()
		return {
			"name": clip_name,
			"frames": frames,
			"dynamic": dynamic,
			"node_hashes": node_hashes,
			"attributes": attributes,
			"samples": values,
		}
	return {}


## Value of a clip channel at a frame (constant channels keep frame 0).
static func clip_value(clip: Dictionary, channel: int, frame: int) -> float:
	var values: PackedFloat32Array = clip["samples"]
	var hashes: PackedInt64Array = clip["node_hashes"]
	var count := hashes.size()
	var index := channel
	if frame > 0 and channel < int(clip["dynamic"]):
		index = count + (frame - 1) * int(clip["dynamic"]) + channel
	return values[index] if index < values.size() else 0.0


## Local transform of a node: rotate X, then Y, then Z, then the joint
## orient, then translate (feet). Mirrors olcore::Skeleton::local_matrix.
static func local_transform(node: Dictionary, rotate: Vector3, translate: Vector3) -> Transform3D:
	var r := Basis(Vector3.BACK, rotate.z) * Basis(Vector3.UP, rotate.y) * Basis(Vector3.RIGHT, rotate.x)
	var orient: Quaternion = node["orient"]
	var b := Basis(orient) * r
	return Transform3D(b, translate)


## Influence numbers skip 19: numbers above it name the skin joint one lower.
## Mirrors kSkippedInfluence in golfer_mesh.cpp.
static func influence_joint(number: int) -> int:
	return number - 1 if number > 19 else number


## A triangle strip (indices relative to `first`) as a triangle list of
## absolute indices: degenerate triangles dropped, every other one flipped
## so that all keep the strip's winding. Mirrors MeshPart::triangles().
static func strip_to_triangles(strip: PackedInt32Array, first: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in strip.size() - 2:
		var a := strip[k]
		var b := strip[k + 1]
		var c := strip[k + 2]
		if a == b or b == c or a == c:
			continue
		if k % 2:
			var t := a
			a = b
			b = t
		out.append_array([first + a, first + b, first + c])
	return out


## Row-major, row-vector 4x4 matrix (as stored) at an offset, as a Transform3D.
static func read_matrix(d: PackedByteArray, o: int) -> Transform3D:
	var m := PackedFloat32Array()
	for k in 16:
		m.append(d.decode_float(o + 4 * k))
	return Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])),
			Vector3(m[12], m[13], m[14]))


## Meshes of a model (docs/formats/carrera-store.md). Each:
## {name, transform, positions, normals, uvs, parts, skin_joints,
##  inverse_bind, bones, weights}. parts: Array of {first_vertex,
## last_vertex, strip, material, diffuse, texture}. bones and weights hold
## four entries per vertex (bones index skin_joints); both are empty for a
## rigid mesh. Mirrors olcore::read_meshes.
static func read_meshes(d: PackedByteArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var allocs := read_allocations(d)
	var by_offset := {}
	for a in allocs:
		by_offset[a["offset"]] = a
	for a in allocs:
		if a["class_name"] != "class Carrera::Mesh" or int(a["size"]) < 0xf4:
			continue
		var o: int = a["offset"]
		var nv := d.decode_u32(o + 0xe4)
		var pos := d.decode_u32(o + 0xe8)
		var uv := d.decode_u32(o + 0xec)
		var nrm := d.decode_u32(o + 0xf0)
		if pos == 0 or uv == 0 or nrm == 0 or pos + nv * 12 > d.size() or uv + nv * 8 > d.size() \
				or nrm + nv * 12 > d.size():
			continue
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for v in nv:
			positions.append(Vector3(d.decode_float(pos + 12 * v), d.decode_float(pos + 12 * v + 4), d.decode_float(pos + 12 * v + 8)))
			normals.append(Vector3(d.decode_float(nrm + 12 * v), d.decode_float(nrm + 12 * v + 4), d.decode_float(nrm + 12 * v + 8)))
			uvs.append(Vector2(d.decode_float(uv + 8 * v), d.decode_float(uv + 8 * v + 4)))
		var parts: Array[Dictionary] = []
		var shapes := d.decode_u32(o + 0xe0)
		var shape_count := d.decode_u32(o + 0xdc)
		if shapes + shape_count * 52 > d.size():
			continue
		for s in shape_count:
			var rec := shapes + s * 52
			var count := d.decode_u32(rec + 0x18)
			var idx := d.decode_u32(rec + 0x14)
			var first := d.decode_u32(rec + 0x24)
			if idx == 0 or idx + count * 2 > d.size():
				continue
			var strip := PackedInt32Array()
			for i in count:
				strip.append(d.decode_u16(idx + 2 * i))
			var part := {
				"first_vertex": first,
				"last_vertex": d.decode_u32(rec + 0x28),
				"strip": strip,
				"material": "",
				"diffuse": Color.WHITE,
				"texture": "",
			}
			var shader := d.decode_u32(rec + 0x2c)
			if by_offset.has(shader):
				part["material"] = by_offset[shader]["name"]
				part["diffuse"] = Color(d.decode_float(shader + 0x14), d.decode_float(shader + 0x18),
						d.decode_float(shader + 0x1c), d.decode_float(shader + 0x20))
				var tex := d.decode_u32(shader + 0x58)
				if by_offset.has(tex):
					part["texture"] = _string_at(d, d.decode_u32(tex + 0x14))
			parts.append(part)
		var no_binds: Array[Transform3D] = []
		var mesh := {
			"name": a["name"],
			"transform": by_offset[d.decode_u32(o + 0x1c)]["name"] if by_offset.has(d.decode_u32(o + 0x1c)) else "",
			"positions": positions,
			"normals": normals,
			"uvs": uvs,
			"parts": parts,
			"skin_joints": PackedStringArray(),
			"inverse_bind": no_binds,
			"bones": PackedInt32Array(),
			"weights": PackedFloat32Array(),
		}
		var skin := d.decode_u32(o + 0xd4)
		if by_offset.has(skin):
			_read_skin(d, skin, by_offset, mesh)
		result.append(mesh)
	return result


static func _read_skin(d: PackedByteArray, skin: int, by_offset: Dictionary, mesh: Dictionary) -> void:
	var joint_count := d.decode_u32(skin + 0x20)
	var vertex_count := d.decode_u32(skin + 0xb0)
	var joints := d.decode_u32(skin + 0x1c)
	var bind := d.decode_u32(skin + 0xa4)
	var pool := d.decode_u32(skin + 0xb4)
	if vertex_count != (mesh["positions"] as PackedVector3Array).size() or joints + joint_count * 4 > d.size() \
			or bind + joint_count * 64 > d.size() or pool + vertex_count * 20 > d.size():
		return
	var names := PackedStringArray()
	var inverse_bind: Array[Transform3D] = []
	for j in joint_count:
		var p := d.decode_u32(joints + 4 * j)
		names.append(by_offset[p]["name"] if by_offset.has(p) else "")
		inverse_bind.append(read_matrix(d, bind + 64 * j))
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in vertex_count:
		var rec := pool + 20 * v
		for k in 4:
			var w := d.decode_float(rec + 4 + 4 * k)
			var j := influence_joint(d[rec + k])
			if w == 0.0 or j >= joint_count:
				j = 0
				w = 0.0
			bones.append(j)
			weights.append(w)
	mesh["skin_joints"] = names
	mesh["inverse_bind"] = inverse_bind
	mesh["bones"] = bones
	mesh["weights"] = weights


static func _string_at(d: PackedByteArray, o: int) -> String:
	if o <= 0 or o >= d.size():
		return ""
	var end := o
	while end < d.size() and d[end] != 0:
		end += 1
	return d.slice(o, end).get_string_from_ascii()
