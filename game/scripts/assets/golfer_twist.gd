class_name GolferTwist
extends SkeletonModifier3D
## Twist bones for the free golfer's forearms and thighs.
##
## The rig has one bone per limb segment, so when a forearm rolls (the palm
## turning up or down) its whole sleeve and skin turn with it, right up to
## the elbow, and the skin wrings like a towel there. A real forearm rolls
## by the radius turning about the ulna: nothing turns at the elbow and the
## whole roll is there at the wrist. The thigh rolling in the hip does the
## same at its top end.
##
## Not the upper arms: an arm raised from the rig's A-pose rest to overhead
## swings so far (over 160 degrees at the finish) that its roll can't be
## told apart from the swing, and spreading that "roll" down the sleeve
## tore the armpit at the finish.
##
## For each of those segments this adds two twist bones beside it, both
## children of its parent and in its place: one near the top end that takes
## none of the roll and one halfway that takes half. The segment's own bone
## keeps the full roll at the bottom end. Every frame, after the animation
## and the other modifiers (put it after GolferHands), each twist bone takes
## the segment's swing and its share of the roll. reweight() hands the
## segment's skin weights over to them by how far along the segment each
## vertex is, so the roll spreads evenly down its length.

## [segment, the bone at its far end].
const CHAINS := [
	["lowerarm_l", "hand_l"], ["lowerarm_r", "hand_r"],
	["thigh_l", "calf_l"], ["thigh_r", "calf_r"],
]
## Where along the segment (0 the top end, 1 the far end) each twist bone
## sits and the share of the roll it takes there; the segment's own bone is
## the last point, at 1 with all of it.
const POINTS := [0.0, 0.5]
const MESH_CACHE := 96

static var _cache := {}  ## mesh -> reweighted copy
static var _cache_order: Array = []

## [twist bone, segment bone, share, far-end axis in the segment's frame].
var _twists: Array = []


## The twist bones' names for segment `bone` ("lowerarm_l" ->
## "lowerarm_twist_01_l", "lowerarm_twist_02_l").
static func twist_names(bone: String) -> PackedStringArray:
	var side := bone.substr(bone.length() - 2)
	var stem := bone.substr(0, bone.length() - 2)
	var out := PackedStringArray()
	for k in POINTS.size():
		out.append("%s_twist_%02d%s" % [stem, k + 1, side])
	return out


## Every twist bone's name, in the order add_bones() adds them.
static func all_names() -> PackedStringArray:
	var out := PackedStringArray()
	for chain: Array in CHAINS:
		out.append_array(twist_names(chain[0]))
	return out


## Adds the twist bones to `sk` (once) and returns the modifier that drives
## them; add it to the skeleton after every modifier that moves the limbs.
static func rig(sk: Skeleton3D) -> GolferTwist:
	for chain: Array in CHAINS:
		var src := sk.find_bone(chain[0])
		if src < 0 or sk.find_bone(chain[1]) < 0:
			continue
		for twist_name in twist_names(chain[0]):
			if sk.find_bone(twist_name) >= 0:
				continue
			var b := sk.get_bone_count()
			sk.add_bone(twist_name)
			sk.set_bone_parent(b, sk.get_bone_parent(src))
			sk.set_bone_rest(b, sk.get_bone_rest(src))
			sk.set_bone_pose(b, sk.get_bone_rest(src))
	var m := GolferTwist.new()
	m.name = "GolferTwist"
	m._read(sk)
	return m


## Puts every twist bone back on its segment's rest (call after the look
## moves the joints).
static func sync_rests(sk: Skeleton3D) -> void:
	for chain: Array in CHAINS:
		var src := sk.find_bone(chain[0])
		if src < 0:
			continue
		for twist_name in twist_names(chain[0]):
			var b := sk.find_bone(twist_name)
			if b >= 0:
				sk.set_bone_rest(b, sk.get_bone_rest(src))


func _read(sk: Skeleton3D) -> void:
	_twists.clear()
	for chain: Array in CHAINS:
		var src := sk.find_bone(chain[0])
		var end := sk.find_bone(chain[1])
		if src < 0 or end < 0:
			continue
		var axis := sk.get_bone_rest(end).origin.normalized()
		var names := twist_names(chain[0])
		for k in names.size():
			var b := sk.find_bone(names[k])
			if b >= 0:
				_twists.append([b, src, float(POINTS[k]), axis])


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for t: Array in _twists:
		var src: int = t[1]
		var rest := sk.get_bone_rest(src).basis.get_rotation_quaternion()
		var turn := rest.inverse() * sk.get_bone_pose_rotation(src)
		var parts := swing_twist(turn, t[3])
		var rot: Quaternion = rest * parts[0] * Quaternion.IDENTITY.slerp(parts[1], t[2])
		sk.set_bone_pose_rotation(t[0], rot)
		sk.set_bone_pose_position(t[0], sk.get_bone_pose_position(src))
		sk.set_bone_pose_scale(t[0], sk.get_bone_pose_scale(src))


## `q` as [swing, twist] with q = swing * twist, the twist about `axis` (in
## q's own frame) and the shorter way round.
static func swing_twist(q: Quaternion, axis: Vector3) -> Array:
	var v := Vector3(q.x, q.y, q.z)
	var p := axis * v.dot(axis)
	var twist := Quaternion(p.x, p.y, p.z, q.w)
	if twist.length_squared() < 1e-12:
		return [q, Quaternion.IDENTITY]
	twist = twist.normalized()
	if twist.w < 0.0:
		twist = -twist
	return [q * twist.inverse(), twist]


## `mesh` (bound to `names`, as the look pack's parts are) with each
## segment's weights shared out to its twist bones, which bind after
## `names` in all_names() order. Up to four weights a vertex are kept,
## the smallest dropped. Vertex positions are in the skeleton's rest space.
static func reweight(mesh: ArrayMesh, names: PackedStringArray, sk: Skeleton3D) -> ArrayMesh:
	if mesh == null:
		return null
	if _cache.has(mesh):
		return _cache[mesh]
	var twist_bind := names.size()
	# segment bind index -> [start, end - start, [bind at each point]].
	var segs := {}
	var all := all_names()
	for chain: Array in CHAINS:
		var src_bind := names.find(chain[0])
		var src := sk.find_bone(chain[0])
		var end := sk.find_bone(chain[1])
		if src_bind < 0 or src < 0 or end < 0:
			continue
		var a := sk.get_bone_global_rest(src).origin
		var b := sk.get_bone_global_rest(end).origin
		var binds := []
		for twist_name in twist_names(chain[0]):
			binds.append(twist_bind + all.find(twist_name))
		binds.append(src_bind)
		segs[src_bind] = [a, b - a, binds]
	if not _uses(mesh, segs):
		return mesh
	var points: Array = POINTS.duplicate()
	points.append(1.0)
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, verts.size())
		for v in verts.size():
			var touched := false
			for k in per:
				if segs.has(bones[v * per + k]) and weights[v * per + k] > 0.0:
					touched = true
					break
			if not touched:
				continue
			var got := {}
			for k in per:
				var bone := bones[v * per + k]
				var w := weights[v * per + k]
				if w <= 0.0:
					continue
				if not segs.has(bone):
					got[bone] = got.get(bone, 0.0) + w
					continue
				var seg: Array = segs[bone]
				var d: Vector3 = seg[1]
				var t := clampf((verts[v] - (seg[0] as Vector3)).dot(d) / d.length_squared(), 0.0, 1.0)
				var binds: Array = seg[2]
				for p in points.size() - 1:
					var t0: float = points[p]
					var t1: float = points[p + 1]
					if t <= t1 or p == points.size() - 2:
						var f := clampf((t - t0) / (t1 - t0), 0.0, 1.0)
						got[binds[p]] = got.get(binds[p], 0.0) + w * (1.0 - f)
						got[binds[p + 1]] = got.get(binds[p + 1], 0.0) + w * f
						break
			var order: Array = got.keys()
			order.sort_custom(func(x: int, y: int) -> bool: return got[x] > got[y])
			var total := 0.0
			for k in mini(per, order.size()):
				total += got[order[k]]
			for k in per:
				if k < order.size() and got[order[k]] > 0.0:
					bones[v * per + k] = order[k]
					weights[v * per + k] = got[order[k]] / total
				else:
					bones[v * per + k] = 0
					weights[v * per + k] = 0.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	_cache[mesh] = out
	_cache_order.append(mesh)
	while _cache_order.size() > MESH_CACHE:
		_cache.erase(_cache_order.pop_front())
	return out


## Whether any vertex of `mesh` follows one of `segs`' bones.
static func _uses(mesh: ArrayMesh, segs: Dictionary) -> bool:
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in bones.size():
			if weights[i] > 0.0 and segs.has(bones[i]):
				return true
	return false
