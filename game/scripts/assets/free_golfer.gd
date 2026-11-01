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
## on slopes, GolferLook turns the head to follow the ball and
## GolferHands keeps the right hand on the club for any body shape. The body, clothes
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
## The left hand's bones, for the glove (with hand_l).
const GLOVE_FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
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
var _hands: GolferHands
var _cloth: GolferCloth


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
	golfer._hands = GolferHands.new()
	golfer._skeleton.add_child(golfer._hands)
	golfer._hands.read_grips(golfer._skeleton, player)
	golfer._cloth = GolferCloth.new()
	golfer._skeleton.add_child(golfer._cloth)
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
	_cloth.clear_materials()
	var weights := look.shape_weights()
	_fit_skeleton(parts.joint_offsets(weights))
	var skin := Skin.new()
	var glove_bones := PackedInt32Array()
	var names := parts.bone_names()
	for i in names.size():
		if names[i] == "hand_l" or (names[i].ends_with("_l") and names[i].split("_")[0] in GLOVE_FINGERS):
			glove_bones.append(i)
	for bone_name in parts.bone_names():
		var bone := _skeleton.find_bone(bone_name)
		var rest := _skeleton.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		skin.add_named_bind(bone_name, rest.affine_inverse())
	for part_name in parts_for(look, parts.info):
		if not parts.has_part(part_name):
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_name
		var mat_name := parts.part_material(part_name)
		var is_skin := str(parts.info.materials[mat_name].get("tint", "")) == "skin"
		mi.mesh = parts.bake(part_name, weights, glove_bones if is_skin and look.glove else PackedInt32Array())
		if part_name.begins_with("Hair_") and look.wears_cap():
			mi.mesh = under_cap(mi.mesh, parts, weights)
		mi.skin = skin
		var std := _material(parts, mat_name)
		var mat: Material = null
		if is_skin:
			mat = GolferSurface.skin_shader(std, look, _skin_regions(parts, mat_name))
			if mat == null:
				mat = GolferSurface.skin(std)
		elif str(parts.info.materials[mat_name].get("tint", "")) == "hair" and std.albedo_texture != null:
			mat = GolferSurface.hair(std)
		elif mat_name == "Eyelashes" or mat_name == "Eyebrows":
			mat = GolferSurface.fine_hair(std, mat_name == "Eyelashes", look.hair_colour)
		elif _moves(parts, part_name, mat_name):
			# Shirt, trousers, shorts and the polo's collar, placket and
			# buttons: moving in the wind and the swing (GolferCloth).
			mi.mesh = GolferCloth.with_mask(mi.mesh, names, _skeleton)
			var cloth := GolferCloth.material(std)
			if part_name.begins_with("Buttons_"):
				cloth.set_shader_parameter("roughness", std.roughness)
			_cloth.add_material(cloth)
			mat = cloth
		else:
			mat = GolferSurface.cloth(std) if _is_cloth(parts, mat_name) else _matt(std)
		if mi.mesh.get_surface_count() > 1:
			mi.set_surface_override_material(0, mat)
			mi.set_surface_override_material(1, GolferSurface.glove())
		else:
			mi.material_override = mat
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
	# Polo collars, plackets and buttons (tools/golfer/collar.py).
	for extra: String in ["Collar_", "Placket_", "Buttons_"]:
		if (info.get("parts", {}) as Dictionary).has(extra + p_look.outfit):
			out.append(extra + p_look.outfit)
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


## The hair without the part the cap covers: the cap fits the skull with
## room for flattened hair (tools/golfer/cap.py), as a real one presses
## the hair down, so the full hair would poke through it. Triangles whose
## middle is above the crown's lower edge ("cap_band", the band ring of
## the cap shaped like this golfer) are dropped, short of a ponytail.
## How far below the band at the front the hair is cut (the fringe).
const FRINGE_TUCK := 0.05


static func under_cap(hair: ArrayMesh, parts: GolferParts, weights: Dictionary) -> ArrayMesh:
	var band_ids: Array = parts.info.get("cap_band", [])
	var cap := parts.bake("Cap", weights)
	if band_ids.is_empty() or cap == null or hair == null:
		return hair
	var cap_verts: PackedVector3Array = cap.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ring := PackedVector3Array()
	var centre := Vector3.ZERO
	for i: int in band_ids:
		ring.append(cap_verts[i])
		centre += cap_verts[i]
	centre /= ring.size()
	# The band point nearest each degree round the head.
	var nearest := PackedInt32Array()
	nearest.resize(360)
	for deg in 360:
		var ang := deg_to_rad(deg - 180.0)
		var best_d := TAU
		for k in ring.size():
			var d := absf(wrapf(ang - atan2(ring[k].x - centre.x, ring[k].z - centre.z), -PI, PI))
			if d < best_d:
				best_d = d
				nearest[deg] = k
	var arrays := hair.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var m := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		var deg := clampi(int(rad_to_deg(atan2(m.x - centre.x, m.z - centre.z)) + 180.0), 0, 359)
		var best := nearest[deg]
		var edge := ring[best]
		var reach := Vector2(edge.x - centre.x, edge.z - centre.z).length()
		var out := Vector2(m.x - centre.x, m.z - centre.z).length()
		# Above the band and no further out than a ponytail's root; at the
		# front a fringe tucks up under the peak, so from a little lower.
		var front := maxf(0.0, -(m.z - centre.z) / maxf(out, 0.001))
		if m.y > edge.y - FRINGE_TUCK * front and out < reach + 0.03:
			continue
		kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	if kept.size() == idx.size():
		return hair
	arrays[Mesh.ARRAY_INDEX] = kept
	var mesh := ArrayMesh.new()
	if not kept.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The look pack's map of the face's regions for the skin shader, or null.
static func _skin_regions(parts: GolferParts, material_name: String) -> Texture2D:
	var index := int(parts.info.materials[material_name].get("regions", -1))
	return parts.texture(index) if index >= 0 else null


## Whether a part is clothing that moves (the cap stays put on the head).
static func _moves(parts: GolferParts, part_name: String, material_name: String) -> bool:
	var tint := str(parts.info.materials[material_name].get("tint", ""))
	return tint in ["top", "bottom"] or part_name.begins_with("Collar_") or part_name.begins_with("Placket_") or part_name.begins_with("Buttons_")


static func _is_cloth(parts: GolferParts, material_name: String) -> bool:
	return str(parts.info.materials[material_name].get("tint", "")) in ["top", "bottom", "cap"]


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
			_paint_crown(mi, look.club_head)
			continue
		if colour.a == 0.0:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.metallic = metal
		mat.roughness = 0.3 if metal > 0.0 else 0.9
		mi.material_override = mat


## The driver's crown takes the player's head colour; its face, sole and
## ferrule keep their own materials (tools/golfer/clubs.py).
static func _paint_crown(mi: MeshInstance3D, colour: Color) -> void:
	for i in mi.mesh.get_surface_count():
		var own := mi.mesh.surface_get_material(i)
		if own == null or own.resource_name != "DriverHead":
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colour
		mat.metallic = 0.4
		mat.roughness = 0.22
		mi.set_surface_override_material(i, mat)


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
		_play(clip, BLEND_TIME)


## Plays a clip, the right hand following onto the club or off it.
func _play(clip: StringName, blend: float) -> void:
	_player.play(clip, blend)
	if _hands:
		_hands.follow(clip, blend)


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
		_play(&"read", BLEND_TIME)
		_walk.tween_interval(_player.get_animation(&"read").length - WALK_SETTLE)
		from = READ_SPOT
		var heading := -from.normalized()
		var yaw := atan2(-heading.x, -heading.z)
		_walk.tween_callback(func() -> void: _play(&"walk", WALK_SETTLE))
		_walk.tween_property(_model, "rotation:y", yaw, WALK_SETTLE)
	else:
		_model.position = _rest + from
		_play(&"walk", BLEND_TIME)
	_walk.tween_property(_model, "position", _rest, from.length() / WALK_SPEED)
	_walk.tween_callback(func() -> void:
		if _player.has_animation(clip):
			_play(clip, WALK_SETTLE))
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
