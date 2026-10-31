class_name GolferFeet
extends SkeletonModifier3D
## Plants the golfer's feet on sloping ground. The clips are made on flat
## ground at the golfer's origin; this lowers the hips to the lower foot,
## bends each leg (two-bone IK) so its ankle sits on the ground under it,
## and tilts the feet with the slope. In a bunker the feet are worked down
## into the sand by `sink` (the knees bend; the hips and club stay put).

const MAX_SHIFT := 0.35  ## metres, up or down
const MAX_TILT := deg_to_rad(20.0)
const NORMAL_STEP := 0.15  ## metres between height samples for the slope

## Ground height at (x, z) in world space; an invalid Callable turns this off.
var ground := Callable()
## Metres the feet are dug into the ground (a bunker stance).
var sink := 0.0
var _bones := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not ground.is_valid():
		return
	if _bones.is_empty():
		for b: String in ["Root", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
			_bones[b] = sk.find_bone(b)
		if _bones.values().has(-1):
			return
	elif _bones.values().has(-1):
		return
	var to_world := sk.global_transform
	var to_sk := to_world.affine_inverse()
	var base_y := to_world.origin.y
	var up := (to_sk.basis * Vector3.UP).normalized()
	var drop: Dictionary[String, float] = {}
	var tilt: Dictionary[String, Vector3] = {}
	for s: String in ["l", "r"]:
		var ankle := to_world * sk.get_bone_global_pose(_bones["foot_" + s]).origin
		var h: float = ground.call(ankle.x, ankle.z)
		drop[s] = clampf(h - base_y, -MAX_SHIFT, MAX_SHIFT)
		var e := NORMAL_STEP
		var dx: float = ground.call(ankle.x - e, ankle.z) - ground.call(ankle.x + e, ankle.z)
		var dz: float = ground.call(ankle.x, ankle.z - e) - ground.call(ankle.x, ankle.z + e)
		tilt[s] = (to_sk.basis * Vector3(dx, 2.0 * e, dz)).normalized()
	var shift: float = minf(drop["l"], drop["r"])
	if absf(drop["l"]) < 1e-3 and absf(drop["r"]) < 1e-3 and sink < 1e-3:
		return
	var root: int = _bones["Root"]
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + sk.get_bone_global_pose(root).basis.inverse() * (up * shift))
	for s: String in ["l", "r"]:
		var foot: int = _bones["foot_" + s]
		var pose := sk.get_bone_global_pose(foot)
		# The hips moved by shift; the ankle should end up drop above where
		# the clip put it.
		var lift: float = drop[s] - shift - sink
		var target: Vector3 = pose.origin + up * lift
		_reach(sk, _bones["thigh_" + s], _bones["calf_" + s], foot, target)
		var slope_to: Vector3 = tilt[s]
		var slope := Quaternion(up, slope_to)
		if slope.get_angle() > MAX_TILT:
			slope = Quaternion(slope.get_axis().normalized(), MAX_TILT)
		GolferLook.set_bone_basis(sk, foot, Basis(slope) * pose.basis)


## Bends thigh and calf so the foot bone's origin reaches `target`, keeping
## the knee in the plane it was in.
static func _reach(sk: Skeleton3D, thigh: int, calf: int, foot: int, target: Vector3) -> void:
	var a := sk.get_bone_global_pose(thigh).origin
	var b := sk.get_bone_global_pose(calf).origin
	var c := sk.get_bone_global_pose(foot).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 1e-4 or l2 < 1e-4:
		return
	var to := target - a
	var dist := clampf(to.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var d := to.normalized()
	var pole := b - a
	var bend := pole - d * pole.dot(d)
	if bend.length_squared() < 1e-8:
		return
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var mid := a + d * l1 * cos_a + bend * l1 * sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var tip := a + d * dist
	GolferLook.turn_bone(sk, thigh, Quaternion((b - a).normalized(), (mid - a).normalized()))
	var b2 := sk.get_bone_global_pose(calf).origin
	var c2 := sk.get_bone_global_pose(foot).origin
	if (c2 - b2).length_squared() > 1e-8 and (tip - b2).length_squared() > 1e-8:
		GolferLook.turn_bone(sk, calf, Quaternion((c2 - b2).normalized(), (tip - b2).normalized()))
