class_name FreeGolfer
extends GolferRig
## The golfer used without the original game files: a realistic person built
## from MakeHuman's CC0 assets, dressed and shaped by the player's look
## (PlayerLook, from the player creator). The skeleton, clubs and animations
## are in the glTF written by tools/golfer/build_free_golfer.py, moving with
## motion capture retargeted by tools/golfer/mocap_swing.py: the address
## (with a look at the target), swing, putt, walk and reactions. At each new
## ball the golfer takes the club from the stand bag, walks round behind the
## ball to look down the line and steps in; on the green they first crouch
## behind the ball to read the putt. GolferFeet plants the feet
## on slopes, GolferLook turns the head to follow the ball and
## GolferHands keeps the right hand on the club for any body shape;
## GolferArms keeps the arms out of a deeper chest than the mocap actor's;
## GolferTwist spreads the forearms' and thighs' roll down
## their length so the skin doesn't wring.
## The body, clothes and hair come from the look pack (GolferParts), baked
## into plain meshes for the look.
## PlaceholderGolferAssets falls back to PlaceholderGolfer if either file is
## missing.

const SCENE_PATH := "res://assets/golfer/free_golfer.glb"
const SPECTATOR_TEXTURE := 512
const BLEND_TIME := 0.15
const REACT_BLEND := 0.4  ## out of the finish into a reaction
const LOOPING: Array[StringName] = [&"address", &"address_iron", &"address_putt", &"walk"]
## Clips with an iron version (`_iron`): a shorter, more upright club, so he
## stands closer to the ball and bends over more.
const IRON_CLIPS: Array[StringName] = [&"address", &"backswing", &"swing"]
## The walk up to a new ball: from this far behind the address spot, at the
## mocap walk's own speed (so the feet don't slide), easing into address.
const WALK_FROM := 2.2
## Measured from the clip's planted feet (0.74 m/s at full size, times
## the model's scale): at 0.89 the feet skated forward a fifth of each step.
const WALK_SPEED := 0.74
## He turns to face the ball over his last steps in, as people do, rather
## than spinning on the spot as he stops.
const TURN_IN := 0.7
const WALK_SETTLE := 0.35
## A move of more than this between addresses is a new ball.
const NEW_BALL := 0.5
## Where a putt is read from: crouched off to his side of the line, part
## way to the hole, looking across it at the slope, in the rig's frame
## (the target is -x). Behind the ball he crouched two metres in front of
## the putting camera, his back filling a third of the screen; from here he
## is a figure to one side of the line, as on TV. READ_AHEAD is how far
## towards the hole (at most READ_SHARE of a short putt).
const READ_SIDE := 1.4
const READ_AHEAD := 1.0
const READ_SHARE := 0.4
## Before a full shot: behind the ball, looking at the target for
## SURVEY_TIME seconds before walking in, as tour players do. He stands a
## step back and to his side of the target line rather than on it: on the
## line he stood a metre in front of the aim camera, his back filling the
## screen.
const SURVEY_SPOT := Vector3(1.1, 0.0, 0.5)
const SURVEY_TIME := 1.6
## Taking the club from the stand bag (pull_club, mocap_swing.py PULL_KEYS):
## the golfer stands on the bag's pocket side facing the way it leans, the
## bag's foot at PULL_BAG_FOOT in the rig's frame (as in the bake), lifts a
## club out by the shaft under its head (they stand heads up) and takes the
## grip in the left hand. The club shows from PULL_GRAB s, when the right
## hand closes on it.
## A bag further than PULL_MAX from the address spot is left alone.
const PULL_BAG_FOOT := Vector3(0.40, 0.0, 0.06)
const PULL_GRAB := 0.62
const PULL_MAX := 6.0
## Where the club meets the ball, seconds into the clip at normal speed:
## swing and swing_iron start at the top (mocap_swing.py downswing), the
## putt at address (back + downswing).
const SWING_IMPACT := 0.30
const PUTT_IMPACT := 0.75
## Each golfer's own tempo (speed of the backswing, swing and putt),
## picked from the look: tour downswings run ~0.25 s (quick players) to
## ~0.33 s (smooth ones).
const TEMPO_MIN := 0.9
const TEMPO_MAX := 1.15
## Everything else plays this much faster or slower each time, and a
## looping clip starts at a random point, so no two shots look the same.
const SPEED_JITTER := 0.06
const SURVEY_JITTER := 0.5  ## seconds either side of SURVEY_TIME
const SWING_CLIPS: Array[StringName] = [&"backswing", &"swing", &"backswing_iron", &"swing_iron", &"putt"]
## Where the ball sits in the rig (GolferRig): a taller or shorter golfer is
## scaled about this point, so the club still meets the ball.
const BALL := Vector3(0.0, 0.0, -0.75)
## The left hand's bones, for the glove (with hand_l).
const GLOVE_FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const SHAFT_COLOURS := {"steel": Color(0.75, 0.76, 0.78), "graphite": Color(0.16, 0.17, 0.19), "black": Color(0.04, 0.04, 0.045)}

var look: PlayerLook
## False to settle into address on the spot (the player creator's preview).
var walk_in := true
## Largest texture side for this golfer's look (0: the pack's own). The
## crowd uses SPECTATOR_TEXTURE: six realistic people at full size would
## take some 300 MB of video memory for faces seen from 20 m.
var texture_cap := 0
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
var _bag: Node3D
## Taking the club from the bag or walking from it (busy()).
var _busy := false
## Which way he faces walking from the bag (rotation.y, unwrapped).
var _walk_yaw := 0.0
var _last_spot := Vector3.INF
## How far this shot is from the hole (set_shot), for where a putt is read.
var _to_hole := 10.0
## The clip he settles into at the end of the walk in (a club change on
## the way takes effect there).
var _walk_clip := &"address"
## A club in his hands (not on the way to the bag for one).
var _holding := true
var _look: GolferLook
## This golfer's swing tempo (TEMPO_MIN..TEMPO_MAX), from the look.
var tempo := 1.0
var _rng := RandomNumberGenerator.new()
## The speed the clip playing now runs at (the walk moves with it).
var _speed := 1.0
var _feet: GolferFeet
var _hands: GolferHands
var _twist: GolferTwist
var _cloth: GolferCloth
## Forearm and neck muscles working through the swing; none on spectators.
var _flex: GolferFlex
var _arms: GolferArms


## Null if the model or the look pack is missing, or the model has no
## animations.
static func create(p_look: PlayerLook = null, p_texture_cap := 0) -> FreeGolfer:
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
	golfer.texture_cap = p_texture_cap
	golfer.add_child(model)
	golfer._model = model
	golfer._player = player
	golfer._skeleton = skeletons[0]
	var twist := GolferTwist.rig(golfer._skeleton)
	golfer._feet = GolferFeet.new()
	golfer._skeleton.add_child(golfer._feet)
	golfer._look = GolferLook.new()
	golfer._skeleton.add_child(golfer._look)
	golfer._arms = GolferArms.new()
	golfer._skeleton.add_child(golfer._arms)
	golfer._hands = GolferHands.new()
	golfer._skeleton.add_child(golfer._hands)
	golfer._hands.read_grips(golfer._skeleton, player)
	golfer._skeleton.add_child(twist)
	golfer._twist = twist
	golfer._cloth = GolferCloth.new()
	golfer._skeleton.add_child(golfer._cloth)
	if p_texture_cap == 0:
		golfer._flex = GolferFlex.new()
		golfer._skeleton.add_child(golfer._flex)
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
	tempo = tempo_of(p_look)
	var parts := GolferParts.shared()
	for node in _look_nodes:
		node.queue_free()
	_look_nodes.clear()
	_cloth.clear_materials()
	if _flex != null:
		_flex.clear_materials()
	var who := person_info(look, parts.info)
	var weights := look.shape_weights() if who.is_empty() else {}
	var offsets := parts.joint_offsets(weights)
	if not who.is_empty():
		for bone: String in who.joints:
			var d: Array = who.joints[bone]
			offsets[bone] = Vector3(d[0], d[1], d[2])
	_fit_skeleton(offsets)
	if _flex != null:
		_flex.set_person(look, look.person)
	var skin := Skin.new()
	var glove_bones := PackedInt32Array()
	var names := parts.bone_names()
	names.append_array(GolferTwist.all_names())
	for i in names.size():
		if names[i] == "hand_l" or (names[i].ends_with("_l") and names[i].split("_")[0] in GLOVE_FINGERS):
			glove_bones.append(i)
	for bone_name in names:
		var bone := _skeleton.find_bone(bone_name)
		var rest := _skeleton.get_bone_global_rest(bone) if bone >= 0 else Transform3D.IDENTITY
		skin.add_named_bind(bone_name, rest.affine_inverse())
	var part_names := parts_for(look, parts.info) if who.is_empty() else person_parts(look, who, parts.info)
	# A person in their cap: whatever the cap presses down (a bun, modelled
	# hair) moves in under it (tools/golfer/person_cap.py "cap_press").
	var part_weights := weights
	if not who.is_empty() and part_names.has(cap_part(look)):
		part_weights = {"cap_press": 1.0}
	for part_name in part_names:
		if not parts.has_part(part_name):
			continue
		var mi := MeshInstance3D.new()
		mi.name = part_name
		var mat_name := parts.part_material(part_name)
		var is_skin := str(parts.info.materials[mat_name].get("tint", "")) == "skin"
		var gloved := (is_skin or str(parts.info.materials[mat_name].get("tint", "")) == "person") and look.glove
		mi.mesh = parts.bake(part_name, part_weights, glove_bones if gloved else PackedInt32Array())
		mi.mesh = GolferTwist.reweight(mi.mesh, parts.bone_names(), _skeleton)
		if part_name.begins_with("Hair_") and look.wears_cap():
			mi.mesh = under_cap(mi.mesh, parts, weights)
		mi.skin = skin
		var std := _material(parts, mat_name)
		var mat: Material = null
		var tint := str(parts.info.materials[mat_name].get("tint", ""))
		if tint == "person":
			var pm := GolferSurface.person(std, look, _skin_regions(parts, mat_name),
				parts.info.materials[mat_name].get("region_means", []))
			_cloth.add_occluded(pm)
			if _flex != null:
				mi.mesh = GolferFlex.with_mask(mi.mesh, names, _skeleton)
				_flex.add_material(pm)
			mat = pm
		elif tint == "person_hair":
			mat = _matt(std)
		elif is_skin:
			mat = GolferSurface.skin_shader(std, look, _skin_regions(parts, mat_name), _face_detail(parts, mat_name))
			if mat == null:
				mat = GolferSurface.skin(std)
			else:
				_cloth.add_occluded(mat)
				if _flex != null:
					mi.mesh = GolferFlex.with_mask(mi.mesh, names, _skeleton)
					_flex.add_material(mat)
		elif str(parts.info.materials[mat_name].get("tint", "")) == "hair" and std.albedo_texture != null:
			mat = GolferSurface.hair(std)
		elif mat_name == "Eyes" and std.albedo_texture != null:
			mat = GolferSurface.eye(std)
		elif mat_name == "Eyelashes" or mat_name == "Eyebrows":
			mat = GolferSurface.fine_hair(std, mat_name == "Eyelashes", look.hair_colour, look.sex >= 0.5)
		elif _moves(parts, part_name, mat_name):
			# Shirt, trousers, shorts and the polo's collar, placket and
			# buttons: moving in the wind and the swing (GolferCloth).
			mi.mesh = GolferCloth.with_mask(mi.mesh, names, _skeleton)
			if part_name.begins_with("Top_"):
				_arms.set_torso(mi.mesh, _skeleton)
			var cloth := GolferCloth.material(std)
			if part_name.begins_with("Buttons_"):
				cloth.set_shader_parameter("roughness", std.roughness)
			_cloth.add_material(cloth)
			_cloth.add_occluded(cloth)
			mat = cloth
		else:
			mat = GolferSurface.cloth(std) if _is_cloth(parts, mat_name) else _matt(std)
		if mi.mesh.get_surface_count() > 1:
			mi.set_surface_override_material(0, mat)
			mi.set_surface_override_material(1, GolferSurface.glove())
		else:
			mi.material_override = mat
		mi.mesh = GolferTwist.correct(mi.mesh, names, _skeleton)
		_skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		_twist.add_fix_mesh(mi)
		_look_nodes.append(mi)
	var standing := parts.standing_height(weights) if who.is_empty() else float(who.height)
	var s := clampf(look.height_cm / 100.0 / standing, 0.7, 1.4)
	_model.scale = Vector3.ONE * s
	_rest = BALL * (1.0 - s)
	if _walk == null:
		_model.position = _rest
	_dress_clubs()


## The look pack's realistic person `look` asks for (info["people"]), or
## an empty dictionary for the creator's own body.
static func person_info(p_look: PlayerLook, info: Dictionary) -> Dictionary:
	if p_look.person == "":
		return {}
	return (info.get("people", {}) as Dictionary).get(p_look.person, {})


## The person's cap part for the look's cap style (person_cap.py).
static func cap_part(p_look: PlayerLook) -> String:
	return "RB_%s_%s" % [p_look.person, "dadcap" if p_look.cap_style == "dad" else "cap"]


## A realistic person's parts: body and head, and either their hair or,
## with the cap on, the cap built on their own head (person_cap.py; the
## hair painted on the scalp still shows below it).
static func person_parts(p_look: PlayerLook, who: Dictionary, info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var cap := cap_part(p_look)
	var capped := p_look.cap and (info.get("parts", {}) as Dictionary).has(cap)
	for part: String in who.parts:
		if capped and part.ends_with("_opacity"):
			continue
		out.append(part)
	if capped:
		out.append(cap)
	return out


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
			return parts.make_material(material_name, look.skin, int(parts.info.skin_female) if female else -1, texture_cap)
		"top":
			return parts.make_material(material_name, look.top, -1, texture_cap)
		"bottom":
			return parts.make_material(material_name, look.bottom, -1, texture_cap)
		"shoes":
			return parts.make_material(material_name, look.shoes, -1, texture_cap)
		"hair":
			return parts.make_material(material_name, look.hair_colour, -1, texture_cap)
		"brows":
			return parts.make_material(material_name, look.hair_colour.darkened(0.15), -1, texture_cap)
		"cap":
			return parts.make_material(material_name, look.cap_colour, -1, texture_cap)
	if material_name == "Eyes":
		var eyes: Dictionary = parts.info.get("eyes", {})
		return parts.make_material(material_name, Color.WHITE, int(eyes.get(look.eyes, -1)), texture_cap)
	return parts.make_material(material_name, Color.WHITE, -1, texture_cap)


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


## The look pack's scanned face detail for the skin shader at
## GolferSurface.face_detail's tier, or empty (that tier is off, or an
## older pack).
static func _face_detail(parts: GolferParts, material_name: String) -> Dictionary:
	var fd: Variant = parts.info.materials[material_name].get("face_detail")
	if GolferSurface.face_detail <= 0 or not fd is Dictionary:
		return {}
	var size := 0 if GolferSurface.face_detail >= 2 else 512
	var r: Array = fd.rect
	return {"albedo": parts.texture(int(fd.albedo), size), "normal": parts.texture(int(fd.normal), size),
		"rect": Vector4(r[0], r[1], r[2], r[3])}


## Whether a part is clothing that moves (the cap stays put on the head).
static func _moves(parts: GolferParts, part_name: String, material_name: String) -> bool:
	var tint := str(parts.info.materials[material_name].get("tint", ""))
	return tint in ["top", "bottom"] or part_name.begins_with("Collar_") or part_name.begins_with("Placket_") or part_name.begins_with("Buttons_")


static func _is_cloth(parts: GolferParts, material_name: String) -> bool:
	return str(parts.info.materials[material_name].get("tint", "")) in ["top", "bottom", "cap"]


## Cloth, skin and hair as matt as they are in daylight: shinier materials
## look like plastic under the Photoreal sun.
static func _matt(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.albedo_color = GolferSurface.real_albedo(mat.albedo_color)
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
	GolferTwist.sync_rests(_skeleton)
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
func set_shot(club: Club, distance_m: float, _power: float = 1.0) -> void:
	_to_hole = distance_m
	_putting = club.is_putter
	_iron = not _putting and not _iron_meshes.is_empty() and not is_long_club(club)


## Driver, woods and hybrids: swung from the driver's address.
static func is_long_club(club: Club) -> bool:
	return club.full_name == "Driver" or club.full_name.contains("Wood") or club.full_name.contains("Hybrid")


## The putter stays out after a putt, for the next address and the
## celebration, until a full swing.
func play(animation: StringName) -> void:
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
	if animation == &"address" and _keep_address(clip):
		return
	_stop_walk()
	if _look:
		_look.track(null, 0.0)
	_show_putter(_putting)
	if animation == &"address":
		var new_ball := _last_spot == Vector3.INF or _ball_spot().distance_to(_last_spot) > NEW_BALL
		_last_spot = _ball_spot()
		if new_ball and walk_in and is_inside_tree() and _player.has_animation(&"walk"):
			_walk_in(clip)
			return
	if _player.has_animation(clip):
		_play(clip, BLEND_TIME)


## Asked to address the same ball again (every frame while the player turns
## to aim, on a club change, as the computer settles its plan): he carries
## on with what he is doing, taking the new club, rather than snapping to
## the ball mid-walk or restarting the address clip at a random frame each
## time, which made him twitch while the aim turned. False to (re)start.
func _keep_address(clip: StringName) -> bool:
	if _last_spot == Vector3.INF or _ball_spot().distance_to(_last_spot) > NEW_BALL:
		return false
	_last_spot = _ball_spot()
	if _walk != null and _walk.is_valid():
		_walk_clip = clip
		if _holding:
			_show_putter(_putting)
		return true
	if _player.current_animation != clip or not _player.is_playing():
		return false
	_show_putter(_putting)
	return true


## Where the ball is: the address spot, which stays put as the golfer turns
## round it to aim (the rig itself circles the ball).
func _ball_spot() -> Vector3:
	return (global_transform if is_inside_tree() else transform) * BALL


func impact_delay() -> float:
	return SWING_IMPACT / tempo


func putt_impact_delay() -> float:
	return PUTT_IMPACT / tempo


## A tempo for a look, the same every time for the same golfer.
static func tempo_of(p_look: PlayerLook) -> float:
	if p_look == null:
		return 1.0
	var h := hash(var_to_str(p_look.to_dict()))
	return lerpf(TEMPO_MIN, TEMPO_MAX, float(posmod(h, 1000)) / 999.0)


func react(animation: StringName, delay: float) -> void:
	if not is_inside_tree() or not _player.has_animation(animation):
		return
	var during := _player.current_animation
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(self) and _player.current_animation == during:
			_play(animation, REACT_BLEND))


## Plays a clip, the right hand following onto the club or off it.
func _play(clip: StringName, blend: float, speed := 0.0) -> void:
	_speed = speed if speed > 0.0 else (tempo if clip in SWING_CLIPS else 1.0 + _rng.randf_range(-SPEED_JITTER, SPEED_JITTER))
	_player.play(clip, blend, _speed)
	var anim := _player.get_animation(clip)
	if anim and anim.loop_mode != Animation.LOOP_NONE and clip != &"walk":
		_player.seek(_rng.randf() * anim.length, false)
	if _hands:
		_hands.follow(clip, blend)


func watch(target: Node3D, delay: float = 0.3) -> void:
	if _look:
		_look.track(target, delay)


func set_ground(height: Callable, sink: float = 0.0) -> void:
	if _feet:
		_feet.ground = height
		_feet.sink = sink


func set_bag(bag: Node3D) -> void:
	_bag = bag


func busy() -> bool:
	return _busy


func walking() -> bool:
	return _walk != null and _walk.is_valid()


## Walks forward to the address spot, then settles into the clip. Before a
## putt the golfer reads it first, crouched behind the ball looking down the
## line; before a full shot he stands behind the ball looking at the target.
func _walk_in(clip: StringName) -> void:
	_walk = create_tween()
	_busy = false
	# The stride and the walk across the ground at the same pace, so the
	# feet don't slide.
	var pace := 1.0 + _rng.randf_range(-SPEED_JITTER, SPEED_JITTER)
	var from := Vector3(0, 0, WALK_FROM)
	var putt := clip == &"address_putt"
	var last := 0.0  # which way he walks in (rotation.y, unwrapped)
	if putt and _player.has_animation(&"read"):
		from = read_spot(_to_hole)
		_model.position = _rest + from
		_model.rotation.y = 0.0  # facing the line from the side
		_play(&"read", BLEND_TIME)
		_walk.tween_interval(_player.get_animation(&"read").length - WALK_SETTLE)
		var heading := -from.normalized()
		last = atan2(-heading.x, -heading.z)
		_walk.tween_callback(func() -> void: _play(&"walk", WALK_SETTLE, pace))
		_walk.tween_property(_model, "rotation:y", last, WALK_SETTLE)
	elif not putt and _player.has_animation(&"survey"):
		# The club from the bag and round behind the ball, or there already;
		# then looking down the target line, and in.
		var turned := PI / 2.0
		if _pull_club(pace):
			_walk.tween_callback(func() -> void: _play(&"survey", WALK_SETTLE))
			turned = _near_yaw(_walk_yaw, PI / 2.0)
			_walk.tween_property(_model, "rotation:y", turned, WALK_SETTLE)
		else:
			_model.position = _rest + SURVEY_SPOT
			_model.rotation.y = PI / 2.0
			_play(&"survey", BLEND_TIME)
		_walk.tween_interval(SURVEY_TIME + _rng.randf_range(-SURVEY_JITTER, SURVEY_JITTER))
		from = SURVEY_SPOT
		var heading := -from.normalized()
		last = _near_yaw(turned, atan2(-heading.x, -heading.z))
		_walk.tween_callback(func() -> void: _play(&"walk", WALK_SETTLE, pace))
		_walk.tween_property(_model, "rotation:y", last, WALK_SETTLE)
	else:
		_model.position = _rest + from
		_play(&"walk", BLEND_TIME, pace)
	var steps := from.length() / _walk_speed(pace)
	_walk.tween_property(_model, "position", _rest, steps)
	var turn := minf(TURN_IN, steps)
	_walk.parallel().tween_property(_model, "rotation:y", _near_yaw(last, 0.0), turn) \
		.set_delay(steps - turn).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_walk_clip = clip
	_walk.tween_callback(func() -> void:
		if _player.has_animation(_walk_clip):
			_play(_walk_clip, WALK_SETTLE))
	_walk.tween_interval(WALK_SETTLE)


## Where a putt of `to_hole` metres is read from, in the rig's frame.
static func read_spot(to_hole: float) -> Vector3:
	return Vector3(-minf(READ_AHEAD, to_hole * READ_SHARE), 0.0, READ_SIDE)


## How fast he covers the ground walking at `pace`: the clip's own speed,
## for his size.
func _walk_speed(pace: float) -> float:
	return WALK_SPEED * _model.scale.x * pace


## Stands the golfer at the bag and has him draw the club out of it
## (pull_club), then walk to the survey spot behind the ball. False (and
## nothing done) without a bag nearby or the clip.
func _pull_club(pace: float) -> bool:
	if _bag == null or not is_instance_valid(_bag) or not _bag.visible or not _bag.is_inside_tree() \
			or not _player.has_animation(&"pull_club"):
		return false
	var spot := pull_spot(global_transform.affine_inverse() * _bag.global_transform, _model.scale.x)
	var at := Vector3(spot.origin.x, _rest.y, spot.origin.z)
	if at.distance_to(_rest) > PULL_MAX:
		return false
	var yaw := spot.basis.get_euler().y
	_model.position = at
	_model.rotation.y = yaw
	_hide_clubs()
	_play(&"pull_club", BLEND_TIME)
	var speed := _speed
	_walk.tween_interval(PULL_GRAB / speed)
	_walk.tween_callback(func() -> void: _show_putter(_putting))
	_walk.tween_interval(maxf(0.0, (_player.get_animation(&"pull_club").length - PULL_GRAB) / speed - WALK_SETTLE))
	# Round to the survey spot, turning as he sets off.
	var to := _rest + SURVEY_SPOT
	var heading := to - at
	heading.y = 0.0
	var walk_yaw := _near_yaw(yaw, atan2(-heading.x, -heading.z))
	_walk.tween_callback(func() -> void: _play(&"walk", WALK_SETTLE, pace))
	_walk.tween_property(_model, "rotation:y", walk_yaw, WALK_SETTLE)
	_walk.tween_property(_model, "position", to, heading.length() / _walk_speed(pace))
	_walk_yaw = walk_yaw
	_busy = true
	_walk.tween_callback(func() -> void: _busy = false)
	return true


## Where the golfer stands to take a club from a bag at `bag` (the bag's
## transform in this golfer's frame) and which way he faces: the bag's foot
## at PULL_BAG_FOOT (times the model's `size`) in his frame, at his right
## front, facing the way the bag leans (its -z), as in the baked clip.
static func pull_spot(bag: Transform3D, size: float) -> Transform3D:
	var lean := -bag.basis.z
	lean.y = 0.0
	if lean.length_squared() < 1e-6:
		lean = Vector3.FORWARD
	lean = lean.normalized()
	var b := Basis(Vector3.UP, atan2(-lean.x, -lean.z))
	return Transform3D(b, bag.origin - b * (PULL_BAG_FOOT * size))


## `yaw` turned by whole turns to within half a turn of `from`, so a tween
## between them takes the short way round.
static func _near_yaw(from: float, yaw: float) -> float:
	return from + angle_difference(from, yaw)


## Empty-handed on the way to the bag.
func _hide_clubs() -> void:
	_holding = false
	for node in _driver + _iron_meshes + _putter:
		node.visible = false


func _stop_walk() -> void:
	if _walk and _walk.is_valid():
		_walk.kill()
	_walk = null
	_busy = false
	if _model:
		_model.position = _rest
		_model.rotation.y = 0.0


func _show_putter(on: bool) -> void:
	_holding = true
	for node in _driver:
		node.visible = not on and not _iron
	for node in _iron_meshes:
		node.visible = not on and _iron
	for node in _putter:
		node.visible = on
