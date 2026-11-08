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
## Half bones: [joint's bone, reach (metres), the bones its skin blends
## from]. Linear skinning collapses a joint that bends far: the armpit folds
## into a dark crease when the arm goes up at the finish or a celebration,
## and the shoe crumples across the toes in the green-reading crouch. A half
## bone sits on the joint and turns half as far as the bone below it; skin
## within reach of the joint moves part of its weight onto it (most at the
## joint, from both sides of it), so the bend is shared over a wider band
## and keeps its volume, as the helper bones in game rigs do. The share
## depends on the rest position alone, so the copies of a vertex along a
## texture seam stay together.
const HALVES := [
	["upperarm_l", 0.15, ["clavicle_l", "spine_03", "spine_02"]],
	["upperarm_r", 0.15, ["clavicle_r", "spine_03", "spine_02"]],
	["ball_l", 0.045, ["foot_l"]],
	["ball_r", 0.045, ["foot_r"]],
]
## Corrective shapes for the armpits. The half bones share a raised arm's
## bend, but linear skinning still pinches the armpit at the far end of the
## range (the finish, the top of the backswing, a pumped fist): the skin of
## the side and the inside of the arm fold through each other into a dark
## crease. For each arm this keeps a few real raised poses from the swing
## and celebration clips (the arm's turn from rest, as a quaternion in its
## parent's frame). correct() poses the skin near the shoulder in each one,
## relaxes the fold out of it there (Taubin smoothing, which keeps the
## volume) and stores the change, in rest space, as a blend shape. Every
## frame each shape fades in as the arm's direction nears its pose's, so
## the skin is smoothed only where and when the arm is up there.
const FIX_POSES := {
	"upperarm_l": [
		Quaternion(-0.6368, 0.6974, 0.2439, -0.2208), Quaternion(-0.5186, 0.5761, -0.4582, -0.4351),
		Quaternion(0.768, -0.0242, 0.5889, 0.2505), Quaternion(0.5751, 0.1723, 0.6953, 0.395),
		Quaternion(0.3487, 0.0841, 0.7211, 0.5928),
	],
	"upperarm_r": [
		Quaternion(0.6261, 0.7248, 0.2871, 0.0159), Quaternion(0.4981, 0.7843, 0.2574, 0.2655),
		Quaternion(0.4293, 0.5378, 0.5537, 0.4689), Quaternion(-0.2913, 0.0121, 0.8002, -0.5241),
		Quaternion(0.5879, 0.4091, -0.3762, 0.5877), Quaternion(0.6081, 0.3448, 0.2269, 0.6781),
	],
}
const FIX_REACH := 0.22  ## metres from the shoulder joint the smoothing reaches
const FIX_ROUNDS := 8  ## Taubin passes
## A shape is full on within FIX_FULL degrees of its pose's arm direction and
## gone past FIX_NONE.
const FIX_FULL := 12.0
const FIX_NONE := 40.0
const MESH_CACHE := 96

static var _cache := {}  ## mesh -> reweighted copy
static var _cache_order: Array = []
static var _fixed := {}  ## mesh -> copy with correct()'s shapes
static var _fixed_order: Array = []

## [twist bone, segment bone, share, far-end axis in the segment's frame].
var _twists: Array = []
## [half bone, joint's bone].
var _halves: Array = []
## [upper arm bone, its rest direction, [arm direction of each pose], shape
## name prefix].
var _fixes: Array = []
## MeshInstance3Ds whose meshes carry correct()'s shapes.
var _fix_meshes: Array[MeshInstance3D] = []


## The half bone's name for joint bone `bone` ("upperarm_l" ->
## "upperarm_half_l").
static func half_name(bone: String) -> String:
	return "%s_half%s" % [bone.substr(0, bone.length() - 2), bone.substr(bone.length() - 2)]


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
	for half: Array in HALVES:
		out.append(half_name(half[0]))
	return out


static func _add_beside(sk: Skeleton3D, bone_name: String, src: int) -> void:
	if sk.find_bone(bone_name) >= 0:
		return
	var b := sk.get_bone_count()
	sk.add_bone(bone_name)
	sk.set_bone_parent(b, sk.get_bone_parent(src))
	sk.set_bone_rest(b, sk.get_bone_rest(src))
	sk.set_bone_pose(b, sk.get_bone_rest(src))


## Adds the twist bones to `sk` (once) and returns the modifier that drives
## them; add it to the skeleton after every modifier that moves the limbs.
static func rig(sk: Skeleton3D) -> GolferTwist:
	for chain: Array in CHAINS:
		var src := sk.find_bone(chain[0])
		if src < 0 or sk.find_bone(chain[1]) < 0:
			continue
		for twist_name in twist_names(chain[0]):
			_add_beside(sk, twist_name, src)
	for half: Array in HALVES:
		var src := sk.find_bone(half[0])
		if src >= 0:
			_add_beside(sk, half_name(half[0]), src)
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
	for half: Array in HALVES:
		var src := sk.find_bone(half[0])
		var b := sk.find_bone(half_name(half[0]))
		if src >= 0 and b >= 0:
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
	_halves.clear()
	for half: Array in HALVES:
		var src := sk.find_bone(half[0])
		var b := sk.find_bone(half_name(half[0]))
		if src >= 0 and b >= 0:
			_halves.append([b, src])
	_fixes.clear()
	for bone: String in FIX_POSES:
		var src := sk.find_bone(bone)
		var lower := sk.find_bone(bone.replace("upper", "lower"))
		if src < 0 or lower < 0:
			continue
		var along := sk.get_bone_rest(lower).origin.normalized()
		var dirs: Array[Vector3] = []
		for q: Quaternion in FIX_POSES[bone]:
			dirs.append(q * along)
		_fixes.append([src, along, dirs, fix_prefix(bone)])


## Blend shape names of correct()'s shapes for `bone` start with this.
static func fix_prefix(bone: String) -> String:
	return "armpit%s_" % bone.substr(bone.length() - 2)


## Drives correct()'s shapes on `mi` from now on.
func add_fix_mesh(mi: MeshInstance3D) -> void:
	if mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
		_fix_meshes.append(mi)


func _drive_fixes(sk: Skeleton3D) -> void:
	var gone := cos(deg_to_rad(FIX_NONE))
	var full := cos(deg_to_rad(FIX_FULL))
	var values := {}
	for f: Array in _fixes:
		var rest := sk.get_bone_rest(f[0]).basis.get_rotation_quaternion()
		var turn := rest.inverse() * sk.get_bone_pose_rotation(f[0])
		var dir: Vector3 = turn * (f[1] as Vector3)
		var dirs: Array = f[2]
		var ws: Array[float] = []
		var total := 0.0
		for d: Vector3 in dirs:
			var w := smoothstep(gone, full, dir.dot(d))
			ws.append(w)
			total += w
		for k in dirs.size():
			values["%s%d" % [f[3], k]] = ws[k] / maxf(1.0, total)
	var alive: Array[MeshInstance3D] = []
	for mi in _fix_meshes:
		if not is_instance_valid(mi) or mi.is_queued_for_deletion():
			continue
		alive.append(mi)
		var mesh := mi.mesh as ArrayMesh
		for i in mesh.get_blend_shape_count():
			mi.set_blend_shape_value(i, values.get(String(mesh.get_blend_shape_name(i)), 0.0))
	_fix_meshes = alive


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
	for h: Array in _halves:
		var src: int = h[1]
		var rest := sk.get_bone_rest(src).basis.get_rotation_quaternion()
		var turn := rest.inverse() * sk.get_bone_pose_rotation(src)
		sk.set_bone_pose_rotation(h[0], rest * Quaternion.IDENTITY.slerp(turn, 0.5))
		sk.set_bone_pose_position(h[0], sk.get_bone_pose_position(src))
	if not _fix_meshes.is_empty():
		_drive_fixes(sk)


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
	# [joint, reach, half bind, joint bone's bind, {bind of a bone above}].
	var halves := []
	var wanted := segs.duplicate()
	for half: Array in HALVES:
		var src_bind := names.find(half[0])
		var src := sk.find_bone(half[0])
		if src_bind < 0 or src < 0:
			continue
		var above := {}
		for n: String in half[2]:
			if names.find(n) >= 0:
				above[names.find(n)] = true
		halves.append([sk.get_bone_global_rest(src).origin, float(half[1]), twist_bind + all.find(half_name(half[0])), src_bind, above])
		wanted[src_bind] = true
	if not _uses(mesh, wanted):
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
				if wanted.has(bones[v * per + k]) and weights[v * per + k] > 0.0:
					touched = true
					break
			if not touched:
				continue
			var had := {}
			for k in per:
				if weights[v * per + k] > 0.0:
					had[bones[v * per + k]] = had.get(bones[v * per + k], 0.0) + weights[v * per + k]
			for h: Array in halves:
				var near := 1.0 - verts[v].distance_to(h[0]) / float(h[1])
				if near <= 0.0:
					continue
				var moved := 0.0
				for bone: int in had.keys():
					var share := near if bone == h[3] else (0.5 * near if (h[4] as Dictionary).has(bone) else 0.0)
					if share > 0.0:
						moved += had[bone] * share
						had[bone] *= 1.0 - share
				had[h[2]] = had.get(h[2], 0.0) + moved
			var got := {}
			for bone: int in had:
				var w: float = had[bone]
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


## `mesh` (bound to `names` then all_names(), as apply_look binds it) with
## the armpit corrective shapes added (see FIX_POSES), or `mesh` itself when
## none of it is near a shoulder. Call it last, after every other step that
## rebuilds the mesh, since those drop blend shapes.
static func correct(mesh: ArrayMesh, names: PackedStringArray, sk: Skeleton3D) -> ArrayMesh:
	if mesh == null or mesh.get_blend_shape_count() > 0:
		return mesh
	if _fixed.has(mesh):
		return _fixed[mesh]
	var surfaces: Array = []
	for si in mesh.get_surface_count():
		surfaces.append(mesh.surface_get_arrays(si))
	# Welded points: copies of a vertex along a texture seam are one point,
	# so the seam can't open.
	var key_of := {}
	var point_pos: Array[Vector3] = []
	var refs: Array = []  # point -> [surface, vertex] of its first copy
	var point_of: Array = []  # surface -> PackedInt32Array
	for si in surfaces.size():
		var verts: PackedVector3Array = surfaces[si][Mesh.ARRAY_VERTEX]
		var ids := PackedInt32Array()
		ids.resize(verts.size())
		for v in verts.size():
			var key := Vector3i((verts[v] * 10000.0).round())
			if not key_of.has(key):
				key_of[key] = point_pos.size()
				point_pos.append(verts[v])
				refs.append([si, v])
			ids[v] = key_of[key]
		point_of.append(ids)
	var shapes: Array = []  # [name, PackedVector3Array per surface]
	for bone: String in FIX_POSES:
		var src := sk.find_bone(bone)
		var half := sk.find_bone(half_name(bone))
		if src < 0:
			continue
		var joint := sk.get_bone_global_rest(src).origin
		var region := {}
		for p in point_pos.size():
			if point_pos[p].distance_to(joint) < FIX_REACH:
				region[p] = true
		if region.size() < 8:
			continue
		var below := {}  # binds that turn with the upper arm
		var halves := {}
		for i in names.size():
			var b := sk.find_bone(names[i])
			if b < 0:
				continue
			if b == half:
				halves[i] = true
				continue
			var up := b
			while up >= 0 and up != src:
				up = sk.get_bone_parent(up)
			if up == src:
				below[i] = true
		# Neighbours of every point in the region (and the fixed ring round it).
		var nbrs := {}
		var tris: Array = []  # triangles (point ids) touching the region
		for si in surfaces.size():
			var idx = surfaces[si][Mesh.ARRAY_INDEX]
			var ids: PackedInt32Array = point_of[si]
			var count: int = (idx as PackedInt32Array).size() if idx != null else ids.size()
			for t in range(0, count - 2, 3):
				var tri := [0, 0, 0]
				for c in 3:
					tri[c] = ids[idx[t + c] if idx != null else t + c]
				if region.has(tri[0]) or region.has(tri[1]) or region.has(tri[2]):
					tris.append(tri)
				for c in 3:
					var a: int = tri[c]
					var b: int = tri[(c + 1) % 3]
					if a == b:
						continue
					if region.has(a):
						if not nbrs.has(a):
							nbrs[a] = {}
						nbrs[a][b] = true
					if region.has(b):
						if not nbrs.has(b):
							nbrs[b] = {}
						nbrs[b][a] = true
		var poses: Array = FIX_POSES[bone]
		for k in poses.size():
			var q: Quaternion = poses[k]
			var turn := Basis(q)
			var halfway := Basis(Quaternion.IDENTITY.slerp(q, 0.5))
			# Skin every point of the region and its ring in this pose.
			var posed := {}
			var turned := {}  # the same point turned by its share of the turn
			var lin := {}
			for p: int in nbrs:
				for n: int in nbrs[p]:
					if not posed.has(n):
						var r: Array = refs[n]
						var arrays: Array = surfaces[r[0]]
						var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
						var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
						var per := bones.size() / maxi(1, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
						var at := point_pos[n] - joint
						var pos := Vector3.ZERO
						var m := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
						var share := 0.0
						for j in per:
							var w := weights[r[1] * per + j]
							if w <= 0.0:
								continue
							var bind := bones[r[1] * per + j]
							var b := turn if below.has(bind) else (halfway if halves.has(bind) else Basis.IDENTITY)
							pos += (joint + b * at) * w
							m = Basis(m.x + b.x * w, m.y + b.y * w, m.z + b.z * w)
							share += w if below.has(bind) else (0.5 * w if halves.has(bind) else 0.0)
						posed[n] = pos
						turned[n] = joint + Basis(Quaternion.IDENTITY.slerp(q, clampf(share, 0.0, 1.0))) * at
						lin[n] = m
				if not posed.has(p):
					posed[p] = point_pos[p]
					turned[p] = point_pos[p]
					lin[p] = Basis.IDENTITY
			# Linear skinning averages the points the arm's and the body's
			# bones would put a vertex at, which cuts the corner and pinches
			# the armpit; turning the vertex about the shoulder by its share
			# of the arm's turn keeps it at its distance from the joint
			# instead (as dual quaternion skinning would). Then relax what
			# fold is left, fading to nothing at FIX_REACH.
			var smooth := {}
			for p: int in posed:
				var f := smoothstep(0.0, 0.6, 1.0 - point_pos[p].distance_to(joint) / FIX_REACH) if nbrs.has(p) else 0.0
				smooth[p] = (posed[p] as Vector3).lerp(turned[p], f)
			for round_i in FIX_ROUNDS * 2:
				var step := 0.6 if round_i % 2 == 0 else -0.63
				var next := smooth.duplicate()
				for p: int in nbrs:
					var ring: Dictionary = nbrs[p]
					var mean := Vector3.ZERO
					for n: int in ring:
						mean += smooth[n]
					mean /= float(ring.size())
					var f := smoothstep(0.0, 0.6, 1.0 - point_pos[p].distance_to(joint) / FIX_REACH)
					next[p] = (smooth[p] as Vector3) + (mean - (smooth[p] as Vector3)) * step * f
				smooth = next
			# Each point's normal turns as its surface turned.
			var bent := {}
			var face_before := _point_normals(tris, posed)
			var face_after := _point_normals(tris, smooth)
			for p: int in nbrs:
				if face_before.has(p) and face_after.has(p):
					var a: Vector3 = face_before[p]
					var b: Vector3 = face_after[p]
					if a.dot(b) < 0.99999:
						bent[p] = Quaternion(a, b) if a.dot(b) > -0.999 else Quaternion.IDENTITY
			var per_surface: Array = []
			var per_normals: Array = []
			for si in surfaces.size():
				var normals = surfaces[si][Mesh.ARRAY_NORMAL]
				# Stored as each vertex's move: Godot's relative blend shapes
				# take offsets, not positions.
				var dn := PackedVector3Array()
				if normals != null:
					dn.resize((normals as PackedVector3Array).size())
				var verts := PackedVector3Array()
				verts.resize((surfaces[si][Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				var ids: PackedInt32Array = point_of[si]
				for v in verts.size():
					var p := ids[v]
					if not nbrs.has(p):
						continue
					var m: Basis = lin[p]
					if absf(m.determinant()) < 1e-4:
						continue
					var undo := m.inverse()
					verts[v] = undo * ((smooth[p] as Vector3) - (posed[p] as Vector3))
					if normals != null and bent.has(p):
						var n: Vector3 = normals[v]
						var spun: Vector3 = (bent[p] as Quaternion) * (m * n).normalized()
						dn[v] = (undo * spun).normalized() - n
				per_surface.append(verts)
				per_normals.append(dn)
			shapes.append(["%s%d" % [fix_prefix(bone), k], per_surface, per_normals])
	if shapes.is_empty():
		_fixed[mesh] = mesh
		return mesh
	var out := ArrayMesh.new()
	out.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for shape: Array in shapes:
		out.add_blend_shape(shape[0])
	for si in surfaces.size():
		var arrays: Array = surfaces[si]
		var blends: Array = []
		for shape: Array in shapes:
			var b := []
			b.resize(Mesh.ARRAY_MAX)
			b[Mesh.ARRAY_VERTEX] = shape[1][si]
			if arrays[Mesh.ARRAY_NORMAL] != null:
				b[Mesh.ARRAY_NORMAL] = shape[2][si]
			if arrays[Mesh.ARRAY_TANGENT] != null:
				var tg := PackedFloat32Array()
				tg.resize((arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size())
				b[Mesh.ARRAY_TANGENT] = tg
			blends.append(b)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends, {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_name(si, mesh.surface_get_name(si))
	# Godot grows the mesh's box round the offsets as if they were points;
	# the skin moves a few centimetres at most, so keep the mesh's own box.
	out.custom_aabb = mesh.get_aabb().grow(0.05)
	_fixed[mesh] = out
	_fixed_order.append(mesh)
	while _fixed_order.size() > MESH_CACHE:
		_fixed.erase(_fixed_order.pop_front())
	return out


## Area-weighted normal at every point of `tris` from positions `at`.
static func _point_normals(tris: Array, at: Dictionary) -> Dictionary:
	var sums := {}
	for tri: Array in tris:
		if not (at.has(tri[0]) and at.has(tri[1]) and at.has(tri[2])):
			continue
		var a: Vector3 = at[tri[0]]
		var face := ((at[tri[1]] as Vector3) - a).cross((at[tri[2]] as Vector3) - a)
		for c in 3:
			sums[tri[c]] = sums.get(tri[c], Vector3.ZERO) + face
	var out := {}
	for p: int in sums:
		var n: Vector3 = sums[p]
		if n.length_squared() > 1e-14:
			out[p] = n.normalized()
	return out
