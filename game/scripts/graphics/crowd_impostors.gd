class_name CrowdImpostors
extends RefCounted
## Real people for the crowd cards. The gallery's far spectators are
## hundreds of camera-facing cards in one draw call (Gallery,
## shaders/crowd_card.gdshader), which used to draw a flat, procedural
## silhouette: from the tee they read as paper cut-outs. This renders
## PEOPLE of the player creator's people (FreeGolfer with a random
## PlayerLook, standing in the crowd's idle with their arms folded, hanging,
## behind the back or in pockets), each from FRAMES directions, into one
## atlas the first time a gallery is built, the way TreeFactory bakes its
## tree impostors. A card then shows one of those people from the side the
## camera is on, so the far crowd has modelled faces, clothes and folds,
## and turns properly as the camera moves round them. Until the bake is
## done (and in headless runs, which render nothing, or without the golfer
## model) the cards keep the silhouette.

const PEOPLE := 16
const FRAMES := 8
## Pixels per person: a cell 1 m wide and 2 m tall. A spectator 20 m from
## the tee camera is about 70 px tall at 1080p, so 160 is plenty and the
## atlas stays small (1280 x 1280, 9 MB with mipmaps).
const CELL := Vector2i(80, 160)
const CELL_METRES := Vector2(1.0, 2.0)
const SHADER := preload("res://shaders/crowd_card.gdshader")

static var _atlas: ImageTexture
static var _baking := false
static var _materials: Array[WeakRef] = []


## The cards' material. It draws silhouettes until the atlas is baked,
## then the baked people.
static func material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("people", float(PEOPLE))
	mat.set_shader_parameter("frames", float(FRAMES))
	if _atlas != null:
		_apply(mat)
	else:
		_materials.append(weakref(mat))
		_start_bake()
	return mat


## The people from two shots of them, over black and over white: where the
## background shows through, the two differ by how much of it shows, which
## gives the alpha; the shot over black is then the colour times that
## alpha. Clear pixels come out clear black, as a transparent viewport's.
static func _matte(black: Image, white: Image) -> Image:
	var b := black.get_data()
	var w := white.get_data()
	var out := PackedByteArray()
	out.resize(b.size())
	for i in range(0, b.size(), 4):
		var through := (int(w[i]) - int(b[i]) + int(w[i + 1]) - int(b[i + 1]) + int(w[i + 2]) - int(b[i + 2])) / 3
		var a := clampi(255 - through, 0, 255)
		if a < 8:
			continue
		out[i] = mini(int(b[i]) * 255 / a, 255)
		out[i + 1] = mini(int(b[i + 1]) * 255 / a, 255)
		out[i + 2] = mini(int(b[i + 2]) * 255 / a, 255)
		out[i + 3] = a
	return Image.create_from_data(black.get_width(), black.get_height(), false, Image.FORMAT_RGBA8, out)


## True while the bake is under way: its off-screen viewport draws the
## sixteen people for a few dozen frames.
static func baking() -> bool:
	return _baking and _atlas == null


## The baked atlas, or null before the first bake (and when headless).
static func atlas() -> ImageTexture:
	return _atlas


static func _apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("atlas", _atlas)
	mat.set_shader_parameter("has_atlas", true)


static func _start_bake() -> void:
	if _baking or DisplayServer.get_name() == "headless":
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_baking = true
	_bake(tree)


static func _bake(tree: SceneTree) -> void:
	var vp := SubViewport.new()
	vp.name = "CrowdImpostorBake"
	vp.own_world_3d = true
	# Forward+ reads opaque people back with no alpha from a transparent
	# viewport (only the hair, drawn blended, came through), so there the
	# atlas is made from two shots over black and white (see _matte); the
	# Compatibility renderer, as on the web, reads alpha back as drawn.
	var matte := GraphicsSettings.is_forward_plus()
	vp.transparent_bg = not matte
	vp.size = Vector2i(PEOPLE * CELL.x, CELL.y)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = CELL_METRES.y
	cam.near = 1.0
	cam.far = 40.0
	cam.position = Vector3(0, CELL_METRES.y * 0.5, 20)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# Soft daylight: a sky fill and a high sun from the front, so every
	# view of a person is lit; the card shader adds the scene's own light
	# on top as a gentle side-to-side shade.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if matte:
		# A set colour (BG_CLEAR_COLOR would draw the project's clear colour).
		env.background_mode = Environment.BG_COLOR
	cam.environment = env
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 20, 0)
	sun.light_energy = 0.85
	vp.add_child(sun)
	var people: Array[Node3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	for i in PEOPLE:
		var look := PlayerLook.random_person(rng.randi())
		look.glove = false
		var person := FreeGolfer.create(look, FreeGolfer.SPECTATOR_TEXTURE)
		if person == null:
			break
		person.walk_in = false
		for node in person.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.name.begins_with("Driver") or mi.name.begins_with("Putter") or mi.name.begins_with("Iron"):
				mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vp.add_child(person)
		people.append(person)
		var player := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			continue
		var skeletons := person.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var arms := CrowdArms.new(Gallery.arm_pose(float(i) / PEOPLE))
			(skeletons[0] as Skeleton3D).add_child(arms)
			player.set_meta(&"arms", arms)
	if people.size() < PEOPLE:
		vp.free()
		_baking = false
		return
	# Deferred: the gallery asking for the material may be mid-way through
	# building the scene, when the root can't take a child.
	tree.root.add_child.call_deferred(vp)
	await RenderingServer.frame_post_draw
	cam.make_current()
	# Placed once in the tree: FreeGolfer settles its own transform as it
	# joins the scene.
	for i in people.size():
		people[i].position = Vector3((i + 0.5 - PEOPLE * 0.5) * CELL_METRES.x, 0, 0)
	for person in people:
		var player := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null:
			Gallery._stand(player)
			player.speed_scale = 0.0  # one still pose, the same in every view
	var img := Image.create_empty(PEOPLE * CELL.x, FRAMES * CELL.y, false, Image.FORMAT_RGBA8)
	# WebGL needs the viewport to keep drawing a few frames before a read-back
	# holds the whole picture (see TreeFactory._bake); the arms also ease in.
	for i in 12:
		await RenderingServer.frame_post_draw
	for k in FRAMES:
		# Row k shows each person as seen from azimuth k * 360 / FRAMES in
		# their own frame (a person faces their -z).
		for person in people:
			person.rotation.y = -float(k) / FRAMES * TAU
		env.background_color = Color.BLACK
		for i in 3:
			await RenderingServer.frame_post_draw
		var shot := vp.get_texture().get_image()
		if shot == null or shot.is_empty():
			vp.queue_free()
			_baking = false
			return
		shot.convert(Image.FORMAT_RGBA8)
		if matte:
			env.background_color = Color.WHITE
			for i in 3:
				await RenderingServer.frame_post_draw
			var white := vp.get_texture().get_image()
			if white == null or white.is_empty():
				vp.queue_free()
				_baking = false
				return
			white.convert(Image.FORMAT_RGBA8)
			shot = _matte(shot, white)
		img.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(0, k * CELL.y))
	vp.queue_free()
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	for ref in _materials:
		var mat := ref.get_ref() as ShaderMaterial
		if mat != null:
			_apply(mat)
	_materials.clear()
