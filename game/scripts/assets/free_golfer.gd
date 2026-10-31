class_name FreeGolfer
extends GolferRig
## The golfer used without the original game files: a realistic person built
## from MakeHuman's CC0 assets, dressed and shaped by the player's look
## (PlayerLook, from the player creator). The skeleton, clubs and animations
## are in the glTF written by tools/golfer/build_free_golfer.py, moving with
## motion capture retargeted by tools/golfer/mocap_swing.py: the address
## (with a look at the target), swing, putt, walk and reactions. At each new
## ball the golfer walks up to it before settling over it; on the green they
## first crouch behind the ball to read the putt. GolferFeet plants the feet
## on slopes and GolferLook turns the head to follow the ball. The body, clothes
## and hair come from the look pack (GolferParts), baked into plain meshes
## for the look.
## PlaceholderGolferAssets falls back to PlaceholderGolfer if either file is
## missing.

const SCENE_PATH := "res://assets/golfer/free_golfer.glb"
const BLEND_TIME := 0.15
const LOOPING: Array[StringName] = [&"address", &"address_iron", &"address_putt", &"walk"]
## Clips with an iron version (`_iron`): a shorter, more upright club, so he
## stands closer to the ball and bends over more.
const IRON_CLIPS: Array[StringName] = [&"address", &"backswing", &"swing"]
## The walk up to a new ball: from this far behind the address spot, at the
## mocap walk's own speed (so the feet don't slide), easing into address.
const WALK_FROM := 2.2
const WALK_SPEED := 0.89
const WALK_SETTLE := 0.35
## A move of more than this between addresses is a new ball.
const NEW_BALL := 0.5
## Where a putt is read from: behind the ball, on the line to the hole
## (the target is -x), in the rig's frame.
const READ_SPOT := Vector3(1.6, 0.0, -0.75)
## Where the ball sits in the rig (GolferRig): a taller or shorter golfer is
## scaled about this point, so the club still meets the ball.
const BALL := Vector3(0.0, 0.0, -0.75)
const SHAFT_COLOURS := {"steel": Color(0.75, 0.76, 0.78), "graphite": Color(0.16, 0.17, 0.19), "black": Color(0.04, 0.04, 0.045)}

var look: PlayerLook
## False to settle into address on the spot (the player creator's preview).
var walk_in := true
var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _base_rests: Array[Transform3D] = []
var _look_nodes: Array[Node] = []
var _driver: Array[Node3D] = []
var _putter: Array[Node3D] = []
var _iron_meshes: Array[Node3D] = []
var _iron := false
var _putting := false
## Where the model sits at address: off the origin when it is scaled for
## height (it is scaled about the ball).
var _rest := Vector3.ZERO
var _walk: Tween
var _last_spot := Vector3.INF
var _look: GolferLook
var _feet: GolferFeet


## Null if the model or the look pack is missing, or the model has no
## animations.
static func create(p_look: PlayerLook = null) -> FreeGolfer:
	if not ResourceLoader.exists(SCENE_PATH) or GolferParts.shared() == null:
		return null
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if player == null or skeletons.is_empty():
		model.free()
		return null
	var golfer := FreeGolfer.new()
	golfer.add_child(model)
	golfer._model = model
	golfer._player = player
	golfer._skeleton = skeletons[0]
	golfer._feet = GolferFeet.new()
	golfer._skeleton.add_child(golfer._feet)
	golfer._look = GolferLook.new()
	golfer._skeleton.add_child(golfer._look)
	for i in golfer._skeleton.get_bone_count():
		golfer._base_rests.append(golfer._skeleton.get_bone_rest(i))
	for anim_name in LOOPING:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Driver"):
			golfer._driver.append(node)
		elif node.name.begins_with("Putter"):
			golfer._putter.append(node)
		elif node.name.begins_with("Iron"):
			golfer._iron_meshes.append(node)
	golfer._show_putter(false)
	golfer.apply_look(p_look if p_look != null else PlayerLook.new())
	return golfer


## Dresses and shapes the golfer: replaces the body, clothes and hair
## meshes, moves the joints to the new shape and scales to the height.
func apply_look(p_look: PlayerLook) -> void:
	look = p_look
	var parts := GolferParts.shared()
	for node in _look_nodes:
		node.queue_free()
	_look_nodes.clear()
	var weights := look.shape_weights()
	_fit_skeleton(parts.joint_offsets(weights))
	var skin := Skin.new()
	for bone_name in parts.bone_names():
		var bone := _skeleton.find_bone(bone_name)
		var rest := _skeleton.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		skin.add_named_bind(bone_name, rest.affine_inverse())
	for part_name in parts_for(look, parts.info):
		if not parts.has_part(part_name):
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_name
		mi.mesh = parts.bake(part_name, weights)
		mi.skin = skin
		mi.material_override = _matt(_material(parts, parts.part_material(part_name)))
		_skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		_look_nodes.append(mi)
	var s := clampf(look.height_cm / 100.0 / parts.standing_height(weights), 0.7, 1.4)
	_model.scale = Vector3.ONE * s
	_rest = BALL * (1.0 - s)
	if _walk == null:
		_model.position = _rest
	_dress_clubs()


## The look pack parts this look shows: the body pieces its outfit doesn't
## cover, the outfit, shoes, face and hair, and the cap.
static func parts_for(p_look: PlayerLook, info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var chunks: Dictionary = info.get("body_chunks", {})
	for part_name: String in info.get("parts", {}):
		if part_name == "Body" or (part_name.begins_with("Body_") and not (chunks.get(part_name, []) as Array).has(p_look.outfit)):
			out.append(part_name)
	out.append_array(["Top_" + p_look.outfit, "Bottom_" + p_look.outfit, "Shoes", "Eyes", "Eyebrows", "Eyelashes"])
	if p_look.hair != "bald":
		out.append("Hair_" + p_look.hair)
	if p_look.wears_cap():
		out.append("Cap")
	return out


func _material(parts: GolferParts, material_name: String) -> StandardMaterial3D:
	var m: Dictionary = parts.info.materials[material_name]
	match str(m.get("tint", "")):
		"skin":
			var female := look.sex >= 0.5 and parts.info.has("skin_female")
			return parts.make_material(material_name, look.skin, int(parts.info.skin_female) if female else -1)
		"top":
			return parts.make_material(material_name, look.top)
		"bottom":
			return parts.make_material(material_name, look.bottom)
		"shoes":
			return parts.make_material(material_name, look.shoes)
		"hair":
			return parts.make_material(material_name, look.hair_colour)
		"brows":
			return parts.make_material(material_name, look.hair_colour.darkened(0.15))
		"cap":
			return parts.make_material(material_name, look.cap_colour)
	if material_name == "Eyes":
		var eyes: Dictionary = parts.info.get("eyes", {})
		return parts.make_material(material_name, Color.WHITE, int(eyes.get(look.eyes, -1)))
	return parts.make_material(material_name)


## Cloth, skin and hair as matt as they are in daylight: shinier materials
## look like plastic under the Photoreal sun.
static func _matt(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.roughness = maxf(mat.roughness, 0.8)
	mat.metallic_specular = minf(mat.metallic_specular, 0.3)
	return mat


## Moves each joint by the shape's offsets (bone name -> offset in the rig).
## Every rest rotation is the identity, so a joint's own move less its
## parent's is the change to its rest position.
func _fit_skeleton(offsets: Dictionary) -> void:
	var moved: Array[Vector3] = []
	moved.resize(_skeleton.get_bone_count())
	for i in _skeleton.get_bone_count():
		var parent := _skeleton.get_bone_parent(i)
		var inherited := moved[parent] if parent >= 0 and parent < i else Vector3.ZERO
		moved[i] = offsets.get(_skeleton.get_bone_name(i), inherited)
		var rest := _base_rests[i]
		rest.origin += moved[i] - inherited
		_skeleton.set_bone_rest(i, rest)
	_skeleton.reset_bone_poses()


func _dress_clubs() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if _look_nodes.has(mi):
			continue
		var colour := Color.TRANSPARENT
		var metal := 0.0
		if mi.name.ends_with("_shaft"):
			colour = SHAFT_COLOURS.get(look.shaft, SHAFT_COLOURS.steel)
			metal = 1.0 if look.shaft == "steel" else 0.2
		elif mi.name.ends_with("_grip"):
			colour = look.grip
		elif mi.name == "Driver_head":
			colour = look.club_head
			metal = 0.5
		if colour.a == 0.0:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.metallic = metal
		mat.roughness = 0.3 if metal > 0.0 else 0.9
		mi.material_override = mat


func has_animation(animation: StringName) -> bool:
	return _player.has_animation(animation)


## Address in the putting stance with the putter on the green, and with an
## iron for every club but the woods and hybrids.
func set_shot(club: Club, _distance_m: float, _power: float = 1.0) -> void:
	_putting = club.is_putter
	_iron = not _putting and not _iron_meshes.is_empty() and not is_long_club(club)


## Driver, woods and hybrids: swung from the driver's address.
static func is_long_club(club: Club) -> bool:
	return club.full_name == "Driver" or club.full_name.contains("Wood") or club.full_name.contains("Hybrid")


## The putter stays out after a putt, for the next address and the
## celebration, until a full swing.
func play(animation: StringName) -> void:
	_stop_walk()
	if _look:
		_look.track(null, 0.0)
	match animation:
		&"putt":
			_putting = true
		&"backswing", &"swing":
			_putting = false
	var clip := animation
	if animation == &"address" and _putting:
		clip = &"address_putt"
	elif _iron and not _putting and animation in IRON_CLIPS and _player.has_animation(StringName(String(animation) + "_iron")):
		clip = StringName(String(animation) + "_iron")
	_show_putter(_putting)
	if animation == &"address" and walk_in and is_inside_tree() and _player.has_animation(&"walk"):
		var spot := global_position
		var new_ball := _last_spot == Vector3.INF or spot.distance_to(_last_spot) > NEW_BALL
		_last_spot = spot
		if new_ball:
			_walk_in(clip)
			return
	if _player.has_animation(clip):
		_player.play(clip, BLEND_TIME)


func watch(target: Node3D, delay: float = 0.3) -> void:
	if _look:
		_look.track(target, delay)


func set_ground(height: Callable, sink: float = 0.0) -> void:
	if _feet:
		_feet.ground = height
		_feet.sink = sink


## Walks forward to the address spot, then settles into the clip. Before a
## putt the golfer reads it first, crouched behind the ball looking down the
## line.
func _walk_in(clip: StringName) -> void:
	_walk = create_tween()
	var from := Vector3(0, 0, WALK_FROM)
	if clip == &"address_putt" and _player.has_animation(&"read"):
		_model.position = _rest + READ_SPOT
		_model.rotation.y = PI / 2.0  # facing the hole (-x)
		_player.play(&"read", BLEND_TIME)
		_walk.tween_interval(_player.get_animation(&"read").length - WALK_SETTLE)
		from = READ_SPOT
		var heading := -from.normalized()
		var yaw := atan2(-heading.x, -heading.z)
		_walk.tween_callback(func() -> void: _player.play(&"walk", WALK_SETTLE))
		_walk.tween_property(_model, "rotation:y", yaw, WALK_SETTLE)
	else:
		_model.position = _rest + from
		_player.play(&"walk", BLEND_TIME)
	_walk.tween_property(_model, "position", _rest, from.length() / WALK_SPEED)
	_walk.tween_callback(func() -> void:
		if _player.has_animation(clip):
			_player.play(clip, WALK_SETTLE))
	_walk.tween_property(_model, "rotation:y", 0.0, WALK_SETTLE)


func _stop_walk() -> void:
	if _walk and _walk.is_valid():
		_walk.kill()
	_walk = null
	if _model:
		_model.position = _rest
		_model.rotation.y = 0.0


func _show_putter(on: bool) -> void:
	for node in _driver:
		node.visible = not on and not _iron
	for node in _iron_meshes:
		node.visible = not on and _iron
	for node in _putter:
		node.visible = on
