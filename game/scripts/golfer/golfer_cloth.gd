class_name GolferCloth
extends Node
## Clothes that move: the free golfer's shirt, trousers, shorts or skort
## ripple in the course wind and lag a touch behind the body through the
## swing, and fold across the back and at the elbows and knees as the body
## turns and bends. No cloth simulation: the shirt and trousers stay the
## skinned meshes they were, and game/shaders/golfer_cloth.gdshader moves
## their vertices a centimetre or two and bends their shading.
##
## What each vertex may do is baked once per mesh into its vertex colour
## (with_mask): R how loose the cloth is there (a short sleeve's hem flaps,
## the collar and a tucked-in waist hardly move), G and B how much of it
## follows the arms and the legs, A how far round to the front.
## UV2 keeps its rest-pose x and y, for the fold patterns. The collar, placket and buttons get the
## same mask from the same rules, so they move with the shirt under them.
##
## This node, a child of the skeleton, runs the cheap part each frame:
## damped springs on the torso's turn and on each arm and leg (driven by
## how fast the bones speed up, so steady movement leaves the clothes
## alone), and the body's twist and elbow and knee bends for the folds.
##
## Tiers (detail, from GraphicsSettings.quality via main.gd): Low leaves
## the clothes still (the shader's offsets stay zero), Medium (the web)
## adds the wind and the swing lag, High the folds, Ultra a finer second
## ripple in the wind.

## 0 still, 1 wind and lag, 2 and folds, 3 and fine ripples.
static var detail := 2

const SHADER := preload("res://shaders/golfer_cloth.gdshader")
## The springs: about 3 Hz, a little damped, like a polo's sleeve.
const LAG_HZ := 3.2
const LAG_DAMPING := 0.35
## Longest a sleeve or trouser leg trails, in metres, and the torso's turn
## the shirt can trail by, in radians.
const MAX_LAG := 0.045
const MAX_TURN_LAG := 0.22
## The first twist of the shoulders against the hips (or bend of a joint)
## that already shows folds, and where they are at their deepest.
const TWIST_FOLDS := Vector2(0.12, 0.7)
const BEND_FOLDS := Vector2(0.35, 1.6)

## Arm and leg bones by side, for the mask.
const ARM_BONES := ["upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"]
const LEG_BONES := ["thigh", "calf", "foot", "ball"]

static var _masked := {}  ## baked mesh -> masked copy
static var _masked_order: Array = []
const MASK_CACHE := 48

var materials: Array[ShaderMaterial] = []
var _skeleton: Skeleton3D
var _bones := {}
var _springs := {}  ## name -> [offset: Vector3, velocity: Vector3, last pos, last vel]
var _turn := [0.0, 0.0, 0.0, 0.0, 0]  ## lag, lag rate, last yaw, last yaw rate, samples seen


func _ready() -> void:
	_skeleton = get_parent() as Skeleton3D
	if _skeleton != null:
		for b in ["pelvis", "spine_03", "neck_01", "clavicle_l", "clavicle_r", "upperarm_l", "lowerarm_l", "hand_l",
				"upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
			_bones[b] = _skeleton.find_bone(b)


## The cloth material for one piece of clothing: `std`'s colour, texture,
## fold normal map and roughness, with the rim cloth catches.
static func material(std: StandardMaterial3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = std.resource_name
	m.shader = SHADER
	m.set_shader_parameter("albedo", std.albedo_color)
	m.set_shader_parameter("texture_albedo", std.albedo_texture)
	m.set_shader_parameter("use_normal", std.normal_enabled and std.normal_texture != null)
	m.set_shader_parameter("texture_normal", std.normal_texture)
	m.set_shader_parameter("roughness", maxf(std.roughness, 0.85))
	return m


## Tells a new look's cloth materials where its joints rest (the folds are
## laid out around them).
func add_material(m: ShaderMaterial) -> void:
	materials.append(m)
	if _skeleton == null:
		return
	m.set_shader_parameter("joints_l", _joint_uniform("upperarm_l", "lowerarm_l"))
	m.set_shader_parameter("joints_r", _joint_uniform("upperarm_r", "lowerarm_r"))
	m.set_shader_parameter("knees", Vector2(_rest("calf_l").y, _rest("calf_r").y))
	var waist := _rest("pelvis").y
	m.set_shader_parameter("torso_band", Vector2(waist, _rest("neck_01").y))


func clear_materials() -> void:
	materials.clear()


func _joint_uniform(shoulder: String, elbow: String) -> Vector4:
	var s := _rest(shoulder)
	var e := _rest(elbow)
	return Vector4(s.x, s.y, e.x, e.y)


func _rest(bone: String) -> Vector3:
	var i: int = _bones.get(bone, -1)
	return _skeleton.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO


func _pose(bone: String) -> Transform3D:
	var i: int = _bones.get(bone, -1)
	return _skeleton.get_bone_global_pose(i) if i >= 0 else Transform3D.IDENTITY


func _process(delta: float) -> void:
	if materials.is_empty() or _skeleton == null or delta <= 0.0:
		return
	delta = minf(delta, 0.05)
	var on := detail >= 1
	var to_local := _skeleton.global_transform.affine_inverse().basis
	var world := _skeleton.global_transform
	var lags := {}
	# Each arm and leg trails the bone's acceleration, felt in the world.
	for pair: Array in [["arm_l", "upperarm_l", "lowerarm_l"], ["arm_r", "upperarm_r", "lowerarm_r"],
			["leg_l", "calf_l", "foot_l"], ["leg_r", "calf_r", "foot_r"]]:
		var p := world * ((_pose(pair[1]).origin + _pose(pair[2]).origin) * 0.5)
		lags[pair[0]] = to_local * _spring(pair[0], p, delta) if on else Vector3.ZERO
	var torso_lag := to_local * _spring("torso", world * _pose("spine_03").origin, delta) if on else Vector3.ZERO
	# The shirt trails the chest's turn about the spine.
	var shoulders := _pose("upperarm_l").origin - _pose("upperarm_r").origin
	var hips := _pose("thigh_l").origin - _pose("thigh_r").origin
	var turn_lag := _turn_spring(atan2(shoulders.z, shoulders.x), delta) if on else 0.0
	var twist := wrapf(atan2(shoulders.z, shoulders.x) - atan2(hips.z, hips.x), -PI, PI)
	var spine := _pose("spine_03").origin
	var axis := (_pose("neck_01").origin - _pose("pelvis").origin).normalized()
	var folds := detail >= 2
	var fold_twist := smoothstep(TWIST_FOLDS.x, TWIST_FOLDS.y, absf(twist)) * signf(twist) if folds else 0.0
	var bends := Vector4.ZERO
	if folds:
		bends = Vector4(
			_bend("upperarm_l", "lowerarm_l", "hand_l"), _bend("upperarm_r", "lowerarm_r", "hand_r"),
			_bend("thigh_l", "calf_l", "foot_l"), _bend("thigh_r", "calf_r", "foot_r"))
	for m in materials:
		m.set_shader_parameter("motion", 1.0 if on else 0.0)
		m.set_shader_parameter("fine", 1.0 if detail >= 3 else 0.0)
		m.set_shader_parameter("lag_torso", torso_lag)
		m.set_shader_parameter("lag_arm_l", lags.arm_l)
		m.set_shader_parameter("lag_arm_r", lags.arm_r)
		m.set_shader_parameter("lag_leg_l", lags.leg_l)
		m.set_shader_parameter("lag_leg_r", lags.leg_r)
		m.set_shader_parameter("turn_lag", turn_lag)
		m.set_shader_parameter("spine", spine)
		m.set_shader_parameter("spine_axis", axis)
		m.set_shader_parameter("twist", fold_twist)
		m.set_shader_parameter("bends", bends)


## How far past straight a joint is bent, as fold depth 0..1.
func _bend(a: String, b: String, c: String) -> float:
	var pa := _pose(a).origin
	var pb := _pose(b).origin
	var pc := _pose(c).origin
	var u := (pb - pa).normalized()
	var v := (pc - pb).normalized()
	return smoothstep(BEND_FOLDS.x, BEND_FOLDS.y, u.angle_to(v))


func _spring(key: String, pos: Vector3, delta: float) -> Vector3:
	if not _springs.has(key):
		_springs[key] = [Vector3.ZERO, Vector3.ZERO, pos, Vector3.ZERO, false]
		return Vector3.ZERO
	var s: Array = _springs[key]
	var vel: Vector3 = (pos - s[2]) / delta
	var acc: Vector3 = (vel - s[3]) / delta if s[4] else Vector3.ZERO
	s[4] = true
	# A teleport (a new hole, the walk-in snapping) is not a swing.
	if vel.length() > 40.0:
		vel = Vector3.ZERO
		acc = Vector3.ZERO
		s[0] = Vector3.ZERO
		s[1] = Vector3.ZERO
	s[2] = pos
	s[3] = vel
	var r := step_spring(s[0], s[1], acc, delta, MAX_LAG)
	s[0] = r[0]
	s[1] = r[1]
	return s[0]


func _turn_spring(yaw: float, delta: float) -> float:
	var t := _turn
	if int(t[4]) == 0:
		t[2] = yaw
		t[4] = 1
		return 0.0
	var rate := wrapf(yaw - float(t[2]), -PI, PI) / delta
	var acc := (rate - float(t[3])) / delta if int(t[4]) > 1 else 0.0
	t[4] = 2
	if absf(rate) > 60.0:
		rate = 0.0
		acc = 0.0
		t[0] = 0.0
		t[1] = 0.0
	t[2] = yaw
	t[3] = rate
	var r := step_spring(Vector3(t[0], 0, 0), Vector3(t[1], 0, 0), Vector3(acc, 0, 0), delta, MAX_TURN_LAG)
	t[0] = (r[0] as Vector3).x
	t[1] = (r[1] as Vector3).x
	return t[0]


## One step of the cloth's damped spring: the offset is pulled back to rest
## and pushed against the body's acceleration `acc` (so cloth trails a
## speeding-up arm and swings on past one that stops). [offset, velocity].
static func step_spring(offset: Vector3, velocity: Vector3, acc: Vector3, delta: float, limit: float) -> Array:
	var w := TAU * LAG_HZ
	# Semi-implicit Euler, in a few sub-steps so a slow frame stays stable.
	var n := maxi(1, ceili(delta / 0.008))
	var h := delta / n
	for i in n:
		velocity += (-w * w * offset - 2.0 * LAG_DAMPING * w * velocity - acc) * h
		offset += velocity * h
		if offset.length() > limit:
			offset = offset.normalized() * limit
			velocity *= 0.5
	return [offset, velocity]


## `mesh` (a baked look pack part, in the rest pose of `skeleton`) with the
## cloth mask in its vertex colours and its rest x, y in UV2. Cached per
## mesh, as the meshes themselves are.
static func with_mask(mesh: ArrayMesh, bone_names: PackedStringArray, skeleton: Skeleton3D) -> ArrayMesh:
	if mesh == null:
		return null
	if _masked.has(mesh):
		return _masked[mesh]
	var joints := {}
	for b in ["pelvis", "neck_01", "upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r", "thigh_l", "foot_l", "thigh_r", "foot_r"]:
		var i := skeleton.find_bone(b)
		joints[b] = skeleton.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO
	# The body's front-to-back middle: a little in front of the spine.
	var spine_bone := skeleton.find_bone("spine_03")
	var mid_z := (skeleton.get_bone_global_rest(spine_bone).origin.z if spine_bone >= 0 else 0.03) - 0.06
	var kinds := PackedInt32Array()  # 0 torso, 1 arm, 2 leg
	for n in bone_names:
		var stem := n.split("_")[0]
		kinds.append(1 if stem in ARM_BONES else (2 if stem in LEG_BONES else 0))
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
			var arm := 0.0
			var leg := 0.0
			for k in per:
				var b := bones[v * per + k]
				var kind := kinds[b] if b < kinds.size() else 0
				if kind == 1:
					arm += weights[v * per + k]
				elif kind == 2:
					leg += weights[v * per + k]
			var p := verts[v]
			# A: how far round to the front of the body the point is (the
			# front folds most). The side comes from UV2's x in the shader:
			# a flag here would flip halfway across the triangles on the
			# body's middle and draw a dotted line down the spine.
			var front := clampf(0.5 - (p.z - mid_z) / 0.1, 0.0, 1.0)
			colours[v] = Color(looseness(p, arm, leg, joints), arm, leg, front)
			uv2[v] = Vector2(p.x, p.y)
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	_masked[mesh] = out
	_masked_order.append(mesh)
	while _masked_order.size() > MASK_CACHE:
		_masked.erase(_masked_order.pop_front())
	return out


## How freely the cloth at rest point `p` moves, 0..1, from how much of it
## follows the arms (`arm`) and legs (`leg`). The rig's left is -x and it
## faces -z.
##
## - Torso: held at the collar and shoulders and at a tucked-in waist,
##   loosest across the middle of the back and chest where a polo blouses.
## - Sleeves: tight at the shoulder seam, loosest at a short sleeve's hem
##   (about half way to the elbow); a long sleeve stays loose to the cuff.
## - Legs: held at the hips and the thigh, freest down the shin where a
##   trouser leg hangs off the knee, settling onto the shoe (so no sock shows under the cuff).
static func looseness(p: Vector3, arm: float, leg: float, joints: Dictionary) -> float:
	var waist: float = (joints.pelvis as Vector3).y + 0.02
	var neck: float = (joints.neck_01 as Vector3).y
	var t := clampf((p.y - waist) / maxf(neck - waist, 0.1), 0.0, 1.0)
	var torso := 0.1 + 0.4 * sin(PI * pow(t, 0.8))
	var side := "_l" if p.x < 0.0 else "_r"
	var sh: Vector3 = joints["upperarm" + side]
	var el: Vector3 = joints["lowerarm" + side]
	var upper := maxf(sh.distance_to(el), 0.1)
	var along := (p - sh).dot((el - sh) / upper)
	var sleeve := 0.15 + 0.75 * smoothstep(0.0, 0.6 * upper, along)
	if along > upper:
		sleeve = lerpf(0.9, 0.6, clampf((along - upper) / upper, 0.0, 1.0))
	var hip: float = (joints["thigh" + side] as Vector3).y
	var ankle: float = (joints["foot" + side] as Vector3).y
	var d := clampf((hip - p.y) / maxf(hip - ankle, 0.1), 0.0, 1.0)
	var trouser := 0.1 + 0.8 * smoothstep(0.1, 0.7, d) - 0.55 * smoothstep(0.8, 1.0, d)
	var body := clampf(1.0 - arm - leg, 0.0, 1.0)
	return clampf(body * torso + arm * sleeve + leg * trouser, 0.0, 1.0)
