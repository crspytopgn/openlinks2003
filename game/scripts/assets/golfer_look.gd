class_name GolferLook
extends SkeletonModifier3D
## Turns the golfer's head, and some of his neck, to follow a node in the
## world (the ball in flight), on top of whatever clip is playing. It eases
## in after a delay and out when the target goes away.

const MAX_TURN := deg_to_rad(85.0)
const NECK_SHARE := 0.4
const EASE_TIME := 0.35

var target: Node3D
var weight := 0.0
var _delay := 0.0
var _neck := -1
var _head := -1


## Follows `node` after `delay` seconds; null stops.
func track(node: Node3D, delay: float) -> void:
	target = node
	_delay = delay


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _head < 0:
		_head = sk.find_bone("head")
		_neck = sk.find_bone("neck_01")
	if _head < 0 or _neck < 0:
		return
	var dt := get_process_delta_time()
	_delay -= dt
	var live := target != null and is_instance_valid(target) and target.is_visible_in_tree()
	weight = move_toward(weight, 1.0 if live and _delay <= 0.0 else 0.0, dt / EASE_TIME)
	if weight <= 0.0 or not live:
		return
	var head := sk.get_bone_global_pose(_head)
	var want := sk.global_transform.affine_inverse() * target.global_position - head.origin
	# The model faces -z and its bones rest unrotated, so the face is the
	# head bone's -z.
	var face := head.basis * Vector3.FORWARD
	if want.length_squared() < 1e-6 or face.length_squared() < 1e-6:
		return
	var turn := Quaternion(face.normalized(), want.normalized())
	var angle := turn.get_angle()
	if angle < 1e-4:
		return
	if angle > MAX_TURN:
		turn = Quaternion(turn.get_axis().normalized(), MAX_TURN)
	turn = Quaternion.IDENTITY.slerp(turn, weight)
	var neck_turn := Quaternion.IDENTITY.slerp(turn, NECK_SHARE)
	GolferLook.turn_bone(sk, _neck, neck_turn)
	GolferLook.turn_bone(sk, _head, turn * neck_turn.inverse())


## Turns a bone by `q` in skeleton space, keeping its parent where it is.
static func turn_bone(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(bone)
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := (parent_basis.inverse() * (Basis(q) * g.basis)).orthonormalized()
	sk.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


## Gives a bone the skeleton-space orientation `basis`.
static func set_bone_basis(sk: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := sk.get_bone_parent(bone)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())
