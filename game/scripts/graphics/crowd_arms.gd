class_name CrowdArms
extends SkeletonModifier3D
## What a spectator does with their arms while they watch, on top of the
## standing idle (whose arms hang a little forward, as a golfer's do
## between shots with a club in hand). Real galleries stand with their
## arms folded, hands behind the back or in the pockets, or just hanging,
## so each spectator gets one of those. Works from the bones' own
## positions, like the caddie's arms, so it doesn't depend on how the
## rig's bones are oriented. Fades out for a reaction (clapping, a groan),
## which has its own arms.

enum Pose { HANGING, FOLDED, BEHIND, POCKETS }

## Directions in the skeleton's space (the body faces -z, +y up) for the
## upper arm (shoulder to elbow) and the forearm (elbow to wrist), with x
## pointing out from that side of the body. FOLDED lifts the left forearm
## a little above the right, so the arms lie one over the other.
const ARMS := {
	Pose.HANGING: [Vector3(0.17, -1.0, 0.02), Vector3(0.03, -1.0, -0.15)],
	Pose.FOLDED: [Vector3(-0.07, -1.0, -0.55), Vector3(-1.0, 0.18, -0.1)],
	Pose.BEHIND: [Vector3(0.15, -1.0, 0.4), Vector3(-0.75, -0.45, 0.25)],
	Pose.POCKETS: [Vector3(0.3, -1.0, 0.1), Vector3(-0.12, -0.9, -0.28)],
}
const FOLD_LIFT := 0.07  ## left forearm over the right
const FOLD_TWIST := -1.4  ## radians, about the forearm: palms in against the body
const FADE := 0.3  ## seconds

var pose := Pose.HANGING
var _bones := {}
var _fade: Tween


func _init(p_pose: Pose = Pose.HANGING) -> void:
	pose = p_pose


## Eases the arms in (`on`) or out over FADE seconds.
func set_on(on: bool) -> void:
	if _fade:
		_fade.kill()
	if not is_inside_tree():
		influence = 1.0 if on else 0.0
		return
	_fade = create_tween()
	_fade.tween_property(self, "influence", 1.0 if on else 0.0, FADE)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		for b: String in ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]:
			_bones[b] = sk.find_bone(b)
	for side: String in ["l", "r"]:
		var upper: int = _bones["upperarm_" + side]
		var lower: int = _bones["lowerarm_" + side]
		var hand: int = _bones["hand_" + side]
		if upper < 0 or lower < 0 or hand < 0:
			return
		var out := signf(sk.get_bone_global_pose(upper).origin.x)
		if out == 0.0:
			out = 1.0 if side == "r" else -1.0
		var dirs: Array = ARMS[pose]
		var up_dir: Vector3 = dirs[0]
		var fore: Vector3 = dirs[1]
		if pose == Pose.FOLDED and out < 0.0:
			fore.y += FOLD_LIFT
		point(sk, upper, lower, Vector3(up_dir.x * out, up_dir.y, up_dir.z))
		point(sk, lower, hand, Vector3(fore.x * out, fore.y, fore.z))
		if pose == Pose.FOLDED:
			twist(sk, lower, hand, FOLD_TWIST * out)


## Rolls `bone` by `angle` about its own length (towards `child`).
static func twist(sk: Skeleton3D, bone: int, child: int, angle: float) -> void:
	var g := sk.get_bone_global_pose(bone)
	var along := sk.get_bone_global_pose(child).origin - g.origin
	if along.length_squared() < 1e-8:
		return
	var turn := Basis(along.normalized(), angle)
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * (turn * g.basis)
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion().normalized())


## Turns `bone` so that its child `child` lies along `want` from it.
static func point(sk: Skeleton3D, bone: int, child: int, want: Vector3) -> void:
	var g := sk.get_bone_global_pose(bone)
	var along := sk.get_bone_global_pose(child).origin - g.origin
	if along.length_squared() < 1e-8:
		return
	var turn := Basis(Quaternion(along.normalized(), want.normalized()))
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * (turn * g.basis)
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion().normalized())
