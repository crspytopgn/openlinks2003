class_name GolferHands
extends SkeletonModifier3D
## Keeps the right hand on the club. The club hangs from the left hand; the
## clips put the right hand on the grip for the stock body, but the player
## creator's shapes move the joints (shorter or longer arms, narrower
## shoulders), which leaves the right hand centimetres off the grip, and at
## the finish the trail arm can't quite reach. Each frame this puts the
## right hand back where the address reference clips hold it relative to the
## left hand (two-bone IK on the arm). When the grip is out of the arm's
## reach, both hands give way towards the right shoulder by the difference,
## the left arm bending to carry the club, so the hands never come apart.

## Reference clip (the grip at address) for each clip that holds the club
## in both hands.
const GRIP_CLIPS := {
	&"address": &"ref_address", &"backswing": &"ref_address", &"swing": &"ref_address",
	&"address_iron": &"ref_address_iron", &"backswing_iron": &"ref_address_iron", &"swing_iron": &"ref_address_iron",
	&"address_putt": &"ref_address_putt", &"putt": &"ref_address_putt",
}
## Bones from the chest out to the hands, for reading the reference grip.
const CHAIN := ["spine_03", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
## Keeps the arm a hair short of straight, so the elbow's bend stays defined.
const REACH := 0.998

## The right hand in the left hand's frame, by reference clip.
var grips: Dictionary[StringName, Transform3D] = {}
## The grip in use; `holding` false lets the arms swing free (walk, reactions).
var grip := Transform3D.IDENTITY
var holding := false
var _bones := {}
var _fade: Tween


## Reads the reference grips from the clips, through the stock skeleton's
## rests (call before the look reshapes the skeleton).
func read_grips(sk: Skeleton3D, player: AnimationPlayer) -> void:
	for ref: StringName in GRIP_CLIPS.values():
		if not grips.has(ref) and player.has_animation(ref):
			grips[ref] = reference_grip(sk, player.get_animation(ref))


## hand_l⁻¹ · hand_r at the start of `anim`, posed on the skeleton's rests.
static func reference_grip(sk: Skeleton3D, anim: Animation) -> Transform3D:
	var world := {}
	for bone_name: String in CHAIN:
		var bone := sk.find_bone(bone_name)
		if bone < 0:
			return Transform3D.IDENTITY
		var local := sk.get_bone_rest(bone)
		var pos := _track(anim, bone_name, Animation.TYPE_POSITION_3D)
		if pos >= 0:
			local.origin = anim.position_track_interpolate(pos, 0.0)
		var rot := _track(anim, bone_name, Animation.TYPE_ROTATION_3D)
		if rot >= 0:
			local.basis = Basis(anim.rotation_track_interpolate(rot, 0.0))
		var parent := sk.get_bone_name(sk.get_bone_parent(bone))
		world[bone_name] = (world[parent] as Transform3D) * local if world.has(parent) else local
	return (world["hand_l"] as Transform3D).affine_inverse() * (world["hand_r"] as Transform3D)


static func _track(anim: Animation, bone_name: String, type: int) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type and String(anim.track_get_path(i)).ends_with(":" + bone_name):
			return i
	return -1


## Follows the clip about to play: on for the clips that hold the club in
## both hands, eased in and out over `blend` seconds.
func follow(clip: StringName, blend: float) -> void:
	var ref: StringName = GRIP_CLIPS.get(clip, &"")
	var on := grips.has(ref)
	if on:
		grip = grips[ref]
	if on == holding:
		return
	holding = on
	if _fade and _fade.is_valid():
		_fade.kill()
	if blend <= 0.0 or not is_inside_tree():
		influence = 1.0 if on else 0.0
		return
	_fade = create_tween()
	_fade.tween_property(self, "influence", 1.0 if on else 0.0, blend)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or (not holding and influence <= 0.0):
		return
	if _bones.is_empty():
		for b: String in ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"]:
			_bones[b] = sk.find_bone(b)
	if _bones.values().has(-1):
		return
	var left := sk.get_bone_global_pose(_bones["hand_l"])
	var target := left * grip
	var shoulder := sk.get_bone_global_pose(_bones["upperarm_r"]).origin
	var elbow := sk.get_bone_global_pose(_bones["lowerarm_r"]).origin
	var reach := (shoulder.distance_to(elbow) + elbow.distance_to(sk.get_bone_global_pose(_bones["hand_r"]).origin)) * REACH
	var gap := target.origin.distance_to(shoulder) - reach
	if gap > 0.0:
		# Out of the right arm's reach: both hands come in by the gap.
		var shift := (shoulder - target.origin).normalized() * gap
		GolferFeet._reach(sk, _bones["upperarm_l"], _bones["lowerarm_l"], _bones["hand_l"], left.origin + shift)
		GolferLook.set_bone_basis(sk, _bones["hand_l"], left.basis)
		left = sk.get_bone_global_pose(_bones["hand_l"])
		target = left * grip
	GolferFeet._reach(sk, _bones["upperarm_r"], _bones["lowerarm_r"], _bones["hand_r"], target.origin)
	GolferLook.set_bone_basis(sk, _bones["hand_r"], target.basis)
