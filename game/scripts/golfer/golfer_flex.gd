class_name GolferFlex
extends Node
## Skin and muscle that work through the swing: the forearms firm up and
## swell as the grip tightens into the strike, the tendons at the wrist
## and the veins stand out, the inside of a bent elbow creases, and the
## neck's long muscle ropes out on the side away from the head's turn
## while the skin folds on the other. In slow-motion footage of tour
## players these are what move under the skin: the forearms at and just
## after impact, the neck at the top, where the head stays still over the
## ball as the shoulders turn under it.
##
## game/shaders/golfer_flex.gdshaderinc draws it. Each vertex's place on
## a forearm or the neck is baked once per mesh (with_mask), and this
## node, a child of the skeleton, reads the posed bones each frame for the
## shader's uniforms: the grip from how fast the hands move against the
## hips (fast in, slowly let go, as grip pressure rises through the
## downswing and eases in the follow-through), the elbows' and wrists'
## bends, and the head's turn against the chest.
##
## Tiers (detail, from GraphicsSettings.quality via main.gd): Low none,
## Medium the muscles and tendons, High and Ultra the veins and creases.

## 0 off, 1 muscles and tendons, 2 and veins and creases.
static var detail := 2

## The grip's rest and how it rises with the hands' speed (m/s) against
## the hips: about 1 just before the strike.
const GRIP_REST := 0.15
const GRIP_SPEED := Vector2(0.6, 6.5)
## How fast the grip tightens and lets go (time constants, seconds).
const GRIP_ATTACK := 0.06
const GRIP_RELEASE := 0.45
## A joint's bend (radians) where folds start and where they're deepest.
const ELBOW_BEND := Vector2(0.35, 1.7)
const WRIST_BEND := Vector2(0.8, 1.4)
## The head's turn against the chest that counts as full (radians).
const NECK_TURN := 1.2

static var _masked := {}  ## baked mesh -> masked copy
static var _masked_order: Array = []
const MASK_CACHE := 48

var materials: Array[ShaderMaterial] = []
## How much this person's veins show, and their own pattern.
var veins := 1.0
var vein_seed := 0.0
var grip := GRIP_REST
var _skeleton: Skeleton3D
var _bones := {}
var _last := Vector3.ZERO
var _have_last := false
var _signs := Vector3.ONE


func _ready() -> void:
	_skeleton = get_parent() as Skeleton3D
	if _skeleton != null:
		for b in ["pelvis", "spine_03", "neck_01", "head", "upperarm_l", "lowerarm_l", "hand_l",
				"upperarm_r", "lowerarm_r", "hand_r", "index_01_l", "pinky_01_l", "middle_01_l",
				"index_01_r", "pinky_01_r", "middle_01_r"]:
			_bones[b] = _skeleton.find_bone(b)
		_signs = Vector3(frame_of(_skeleton, "l").sign, frame_of(_skeleton, "r").sign, frame_of(_skeleton, "n").sign)


## Adds a material with golfer_flex.gdshaderinc on a mesh from with_mask.
func add_material(m: ShaderMaterial) -> void:
	materials.append(m)
	m.set_shader_parameter("flex_sign", _signs)
	m.set_shader_parameter("flex_veins", veins)
	m.set_shader_parameter("flex_seed", vein_seed)


func clear_materials() -> void:
	materials.clear()


## Veins show most on a lean man's forearms, less on a woman's, and more
## with age; `key` (the person) gives each their own pattern.
func set_person(look: PlayerLook, key: String) -> void:
	var man := look.sex < 0.5
	veins = clampf((1.0 if man else 0.45) + 0.25 * look.age + 0.2 * look.muscle - 0.3 * look.weight, 0.2, 1.4)
	vein_seed = float(absi(key.hash()) % 1000) * 0.0137


func _pose(bone: String) -> Transform3D:
	var i: int = _bones.get(bone, -1)
	return _skeleton.get_bone_global_pose(i) if i >= 0 else Transform3D.IDENTITY


func _process(delta: float) -> void:
	if materials.is_empty() or _skeleton == null:
		return
	if detail <= 0:
		for m in materials:
			m.set_shader_parameter("flex_on", 0.0)
		return
	var world := _skeleton.global_transform
	# The grip: the hands' speed against the hips, fast in, slow out.
	var rel := world * ((_pose("hand_l").origin + _pose("hand_r").origin) * 0.5) - world * _pose("pelvis").origin
	var speed := 0.0
	if _have_last and delta > 0.0:
		speed = (rel - _last).length() / delta
		if speed > 40.0:  # a teleport, not a swing
			speed = 0.0
	_last = rel
	_have_last = true
	var wrist := Vector2(_wrist("l"), _wrist("r"))
	grip = step_grip(grip, speed, wrist.x, delta)
	var elbow := Vector2(_bend("upperarm_l", "lowerarm_l", "hand_l", ELBOW_BEND), _bend("upperarm_r", "lowerarm_r", "hand_r", ELBOW_BEND))
	var turn := clampf(head_turn() / NECK_TURN, -1.0, 1.0)
	var basis := world.basis
	var axis_l := basis * (_pose("hand_l").origin - _pose("lowerarm_l").origin)
	var axis_r := basis * (_pose("hand_r").origin - _pose("lowerarm_r").origin)
	var axis_n := basis * (_pose("head").origin - _pose("neck_01").origin)
	for m in materials:
		m.set_shader_parameter("flex_on", 1.0)
		m.set_shader_parameter("flex_detail", float(mini(detail, 2)))
		m.set_shader_parameter("flex_axis_l", axis_l.normalized())
		m.set_shader_parameter("flex_axis_r", axis_r.normalized())
		m.set_shader_parameter("flex_axis_n", axis_n.normalized())
		# The neck's frame runs 7 cm below its joint to 3 cm past the head's (frame_of).
		m.set_shader_parameter("flex_len", Vector3(axis_l.length(), axis_r.length(), axis_n.length() + 0.1 * basis.get_scale().x))
		m.set_shader_parameter("flex_scale", basis.get_scale().x)
		# The trail hand grips a little lighter than the lead.
		m.set_shader_parameter("flex_grip", Vector2(grip, grip * 0.85))
		m.set_shader_parameter("flex_elbow", elbow)
		m.set_shader_parameter("flex_wrist", wrist)
		m.set_shader_parameter("flex_neck", Vector2(turn, grip * 0.6))


## One frame of the grip: towards how hard the hands work at `speed`
## (m/s against the hips) and the lead wrist's hinge, tightening fast and
## easing off slowly.
static func step_grip(current: float, speed: float, lead_wrist: float, delta: float) -> float:
	var target := clampf(GRIP_REST + (1.0 - GRIP_REST) * smoothstep(GRIP_SPEED.x, GRIP_SPEED.y, speed) + 0.25 * lead_wrist, 0.0, 1.0)
	var tau := GRIP_ATTACK if target > current else GRIP_RELEASE
	return lerpf(current, target, 1.0 - exp(-maxf(delta, 0.0) / tau))


## The head's turn against the chest about the neck, radians, + to the
## golfer's left.
func head_turn() -> float:
	var axis := (_pose("head").origin - _pose("neck_01").origin).normalized()
	var head := _pose("head").basis * Vector3(0, 0, -1)
	var chest := _pose("spine_03").basis * Vector3(0, 0, -1)
	head = (head - axis * head.dot(axis)).normalized()
	chest = (chest - axis * chest.dot(axis)).normalized()
	# The rig faces -z with its left at -x, so a turn to the left is a
	# positive turn about the neck's axis (up).
	return chest.signed_angle_to(head, axis)


## How far past straight the joint at b is bent, 0..1 over `limits`.
func _bend(a: String, b: String, c: String, limits: Vector2) -> float:
	var u := (_pose(b).origin - _pose(a).origin).normalized()
	var v := (_pose(c).origin - _pose(b).origin).normalized()
	return smoothstep(limits.x, limits.y, u.angle_to(v))


## How far the hand on side `side` is bent at the wrist from its rest
## (cocked, bowed or cupped, not turned), 0..1 over WRIST_BEND: the
## fingers' direction seen from the forearm, now against at rest.
func _wrist(side: String) -> float:
	return smoothstep(WRIST_BEND.x, WRIST_BEND.y, _wrist_angle(side))


func _wrist_angle(side: String) -> float:
	var arm: int = _bones.get("lowerarm_" + side, -1)
	var hand: int = _bones.get("hand_" + side, -1)
	var finger: int = _bones.get("middle_01_" + side, -1)
	if arm < 0 or hand < 0 or finger < 0:
		return 0.0
	var now := _skeleton.get_bone_global_pose(arm).basis.inverse() * (_skeleton.get_bone_global_pose(finger).origin - _skeleton.get_bone_global_pose(hand).origin)
	var rest := _skeleton.get_bone_global_rest(arm).basis.inverse() * (_skeleton.get_bone_global_rest(finger).origin - _skeleton.get_bone_global_rest(hand).origin)
	return now.angle_to(rest)


## A forearm's ("l", "r") or the neck's ("n") frame in the rest pose:
## {from, axis (unit), length, front (the palm side or the throat), side
## (towards the thumb or the golfer's left), sign: +1 where side is
## axis x front, as the shader's angle needs}.
static func frame_of(skeleton: Skeleton3D, which: String) -> Dictionary:
	var rest := func(b: String) -> Vector3:
		var i := skeleton.find_bone(b)
		return skeleton.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO
	var from: Vector3
	var to: Vector3
	var front: Vector3
	var side: Vector3
	if which == "n":
		from = rest.call("neck_01")
		to = rest.call("head")
		var d: Vector3 = to - from
		# The neck from its base (a little below the neck joint) to under the ear.
		from -= d.normalized() * 0.07
		to += d.normalized() * 0.03
		front = Vector3(0, 0, -1)
		side = Vector3(-1, 0, 0)
	else:
		from = rest.call("lowerarm_" + which)
		to = rest.call("hand_" + which)
		var fingers: Vector3 = (rest.call("middle_01_" + which) as Vector3) - to
		if fingers.length() < 0.01:
			fingers = to - from
		# Towards the thumb: across the knuckles from the little finger.
		side = (rest.call("index_01_" + which) as Vector3) - (rest.call("pinky_01_" + which) as Vector3)
		# The palm faces this way: a right hand's is radial x fingers, a
		# left hand's the mirror (the rig's left is -x).
		front = side.cross(fingers) if which == "r" else fingers.cross(side)
	var axis := (to - from).normalized()
	front = (front - axis * front.dot(axis)).normalized()
	side = side - axis * side.dot(axis) - front * side.dot(front)
	side = side.normalized()
	return {
		"from": from, "axis": axis, "length": from.distance_to(to), "front": front, "side": side,
		"sign": 1.0 if axis.cross(front).dot(side) >= 0.0 else -1.0,
	}


## `mesh` (a baked look pack part in `skeleton`'s rest pose) with each
## vertex's place on the forearms and the neck in UV2 and its colours (see
## golfer_flex.gdshaderinc). Cached per mesh.
static func with_mask(mesh: ArrayMesh, bone_names: PackedStringArray, skeleton: Skeleton3D) -> ArrayMesh:
	if mesh == null:
		return null
	if _masked.has(mesh):
		return _masked[mesh]
	var frames := {"l": frame_of(skeleton, "l"), "r": frame_of(skeleton, "r"), "n": frame_of(skeleton, "n")}
	# Which bones carry an arm (by side) and the neck.
	var arm_side := PackedInt32Array()  # 1 left, -1 right, 0 neither
	var neckish := PackedByteArray()
	for n in bone_names:
		var stem := n.split("_")[0]
		var s := 0
		if stem in ["upperarm", "lowerarm", "hand"] or stem in GolferCloth.ARM_BONES:
			s = 1 if n.ends_with("_l") else (-1 if n.ends_with("_r") else 0)
		arm_side.append(s)
		neckish.append(1 if n in ["neck_01", "head", "spine_03"] else 0)
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, verts.size())
		var colours := PackedColorArray()
		var uv2 := PackedVector2Array()
		colours.resize(verts.size())
		uv2.resize(verts.size())
		for v in verts.size():
			var left := 0.0
			var right := 0.0
			var neck := 0.0
			for k in per:
				var b := bones[v * per + k]
				var w := weights[v * per + k]
				if b < arm_side.size():
					if arm_side[b] > 0:
						left += w
					elif arm_side[b] < 0:
						right += w
					elif neckish[b] == 1:
						neck += w
			var p := verts[v]
			var colour := Color(0.5, 0.5, 0.0, 1.0)
			var place := Vector2.ZERO
			var which := "l" if left > 0.5 else ("r" if right > 0.5 else "")
			if which != "":
				var f: Dictionary = frames[which]
				var c := limb_coords(p, f)
				# The forearm from a little above the elbow (its crease) to
				# just past the wrist.
				var m := smoothstep(-0.3, -0.18, c.x) * (1.0 - smoothstep(1.04, 1.12, c.x)) * (1.0 - smoothstep(0.065, 0.085, c.z))
				place = Vector2(c.x, m * (1.0 if which == "l" else -1.0))
				colour.r = cos(c.y) * 0.5 + 0.5
				colour.g = sin(c.y) * 0.5 + 0.5
			elif neck > 0.5:
				var f: Dictionary = frames.n
				var c := limb_coords(p, f)
				# Not the chin and jaw (further out than the neck) or the
				# chest and the head above.
				var m := smoothstep(-0.05, 0.08, c.x) * (1.0 - smoothstep(0.95, 1.08, c.x)) * (1.0 - smoothstep(0.062, 0.078, c.z))
				place = Vector2(c.x, 0.0)
				colour = Color(cos(c.y) * 0.5 + 0.5, sin(c.y) * 0.5 + 0.5, m, 1.0)
			colours[v] = colour
			uv2[v] = place
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_name(si, mesh.surface_get_name(si))
	_masked[mesh] = out
	_masked_order.append(mesh)
	while _masked_order.size() > MASK_CACHE:
		_masked.erase(_masked_order.pop_front())
	return out


## Point `p`'s place on limb frame `f`: x along it (0..1), y the angle
## round it from the front towards the side, z how far it is from the axis.
static func limb_coords(p: Vector3, f: Dictionary) -> Vector3:
	var d: Vector3 = p - (f.from as Vector3)
	var axis: Vector3 = f.axis
	var along := d.dot(axis)
	var r := d - axis * along
	var angle := atan2(r.dot(f.side), r.dot(f.front))
	return Vector3(along / float(f.length), angle, r.length())
