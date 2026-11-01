class_name GolferArms
extends SkeletonModifier3D
## Keeps the arms out of the chest. The swing is motion capture of a
## slimmer actor, so where an arm crosses the body (the lead arm at the top
## of the backswing, the trail arm at the finish) a deeper chest swallows
## the upper arm. A real golfer's arm lies against the chest there with the
## shoulder rolled forward, so this moves the shoulder joint just far enough
## to bring the arm onto the chest's surface, then bends the arm back to
## where the hand was, so the hand and the club in it don't move at all. Runs before GolferHands, which
## then puts the right hand back on the grip.
##
## The chest is an elliptic cylinder about spine_03, sized per look from the
## shirt (set_torso).

## Upper arm radius in a polo's sleeve, metres.
const ARM_RADIUS := 0.05
## Most the shoulder is moved, metres.
const MAX_PUSH := 0.05
## Where along the chest's height the cylinder applies, about spine_03.
const BAND := Vector2(-0.16, 0.34)
## How far past the chest's middle (towards its own side, m) an arm point
## still counts as crossed.
const CROSSED := 0.03

## Chest half-width (x), half-depth (z) and the depth centre's z offset
## from spine_03, in the rest frame.
var half_width := 0.16
var half_depth := 0.12
var centre_z := 0.0
var _bones := {}


## Sizes the chest from a baked shirt mesh (rest pose): the torso's
## vertices between the waist and the armpits, arms left out.
func set_torso(mesh: Mesh, skeleton: Skeleton3D) -> void:
	if mesh == null or skeleton == null:
		return
	var spine := skeleton.find_bone("spine_03")
	var arm := skeleton.find_bone("upperarm_l")
	if spine < 0 or arm < 0:
		return
	var c := skeleton.get_bone_global_rest(spine).origin
	var shoulder := skeleton.get_bone_global_rest(arm).origin
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var p := v - c
		if p.y > -0.12 and p.y < shoulder.y - c.y - 0.04 and absf(p.x) < absf(shoulder.x) * 0.8:
			xs.append(absf(p.x))
			zs.append(p.z)
	if zs.size() < 20:
		return
	xs.sort()
	zs.sort()
	# Near-extremes rather than extremes, so a stray fold doesn't count.
	half_width = xs[int(xs.size() * 0.97)]
	var front := zs[int(zs.size() * 0.02)]
	var back := zs[int(zs.size() * 0.98)]
	half_depth = (back - front) * 0.5
	centre_z = (back + front) * 0.5


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		for b: String in ["spine_03", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]:
			_bones[b] = sk.find_bone(b)
	if _bones.values().has(-1):
		return
	for side in ["_l", "_r"]:
		var hand: int = _bones["hand" + side]
		var held := sk.get_bone_global_pose(hand)
		var moved := false
		# Twice: the arm's nearest point can change once it moves.
		for i in 2:
			var push := _push(sk, side)
			if push.length() < 0.001:
				break
			_roll_shoulder(sk, side, push, held.origin)
			moved = true
		if moved:
			# The hand (and the club in it) stays exactly where it was: the
			# upper arm swings out round it.
			GolferFeet._reach(sk, _bones["upperarm" + side], _bones["lowerarm" + side], hand, held.origin)
			GolferLook.set_bone_basis(sk, hand, held.basis)


## How far (skeleton space) the arm on `side` must move to sit on the chest.
func _push(sk: Skeleton3D, side: String) -> Vector3:
	var chest := sk.get_bone_global_pose(_bones["spine_03"])
	var to_chest := chest.affine_inverse()
	var s := sk.get_bone_global_pose(_bones["upperarm" + side]).origin
	var e := sk.get_bone_global_pose(_bones["lowerarm" + side]).origin
	var best := Vector3.ZERO
	# The upper arm only, and only where it has crossed the chest's middle
	# (the lead arm at the top, the trail arm at the finish): an arm at
	# its own side, as at address and impact, is left exactly as captured,
	# so the club still meets the ball.
	var own := -1.0 if side == "_l" else 1.0
	for k in 8:
		var p := to_chest * s.lerp(e, lerpf(0.15, 1.0, float(k) / 7.0))
		if p.x * own > CROSSED:
			continue
		var need := depth_out(p, half_width + ARM_RADIUS, half_depth + ARM_RADIUS, centre_z, BAND)
		if need.length() > best.length():
			best = need
	return chest.basis * best if best != Vector3.ZERO else Vector3.ZERO


## The move (in the chest's frame) that takes point `p` out of the elliptic
## cylinder of half-axes `a` (x) and `b` (z) centred at z = `cz`, along the
## ellipse's outward direction, or zero if it is outside (or outside the
## band of heights).
static func depth_out(p: Vector3, a: float, b: float, cz: float, band: Vector2) -> Vector3:
	if p.y < band.x or p.y > band.y:
		return Vector3.ZERO
	var x := p.x / a
	var z := (p.z - cz) / b
	var q := sqrt(x * x + z * z)
	if q >= 1.0 or q < 0.0001:
		return Vector3.ZERO
	# Scale out to the surface (exact for a circle, close for an ellipse).
	return Vector3(p.x, 0.0, p.z - cz) * (1.0 / q - 1.0)


## Moves the shoulder joint by `push` (the part of it across the line to
## the hand, capped at MAX_PUSH): the shoulder rolling forward over the
## chest.
func _roll_shoulder(sk: Skeleton3D, side: String, push: Vector3, hand: Vector3) -> void:
	var bone: int = _bones["upperarm" + side]
	# Only across the line to the hand, so the hand stays in reach.
	var to_hand := (hand - sk.get_bone_global_pose(bone).origin).normalized()
	push = (push - to_hand * push.dot(to_hand)).limit_length(MAX_PUSH)
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(bone))
	sk.set_bone_pose_position(bone, sk.get_bone_pose_position(bone) + parent.basis.inverse() * push)
