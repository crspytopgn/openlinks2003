extends SceneTree
## Renders golfers for side-by-side review against real photos: a full-body
## lineup and a face close-up of each, in outdoor daylight. Pass the output
## folder after "--", then optionally "random" to render random looks
## instead of the tour roster (GolferRoster).
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_lineup_render.gd -- /tmp/lineup

const SIZE := Vector2i(1600, 900)
## Eight golfers to a lineup picture; the next eight stand this far along.
const ROW_GAP := 20.0

var _out := ""
var _frames := 0
var _looks: Array[PlayerLook] = []
var _names: Array[String] = []
var _golfers: Array[FreeGolfer] = []
var _cam: Camera3D
var _step := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/lineup"
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = SIZE
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.32, 0.5, 0.78)
	psky.sky_horizon_color = Color(0.72, 0.78, 0.85)
	psky.ground_horizon_color = Color(0.45, 0.5, 0.4)
	psky.ground_bottom_color = Color(0.2, 0.28, 0.15)
	sky.sky_material = psky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# The game's Photoreal light (Scenery): sun 3.0, sky fill 0.5, AgX.
	env.ambient_light_energy = 0.5
	env.ambient_light_sky_contribution = 0.6
	env.tonemap_white = 6.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	# Mid-morning sun from in front and to one side of the golfers.
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 3.0
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.36, 0.12)
	gm.roughness = 0.95
	ground.material_override = gm
	scene.add_child(ground)
	if args.size() > 1 and args[1] == "random":
		for k in 8:
			_looks.append(PlayerLook.random(hash("Opponent %d" % k)))
			_names.append("random %d" % k)
	else:
		for g: Dictionary in GolferRoster.golfers():
			_looks.append(g["look"])
			_names.append(g["name"])
	var spacing := 0.95
	var x0 := -spacing * 3.5
	for k in _looks.size():
		var golfer := FreeGolfer.create(_looks[k])
		golfer.walk_in = false
		scene.add_child(golfer)
		golfer.position = Vector3(x0 + spacing * (k % 8) + ROW_GAP * (k / 8), 0, 0)
		golfer.rotation_degrees.y = 180.0
		_golfers.append(golfer)
	_cam = Camera3D.new()
	scene.add_child(_cam)


func _pose() -> void:
	for golfer in _golfers:
		for m in golfer.find_children("*", "SkeletonModifier3D", true, false):
			(m as SkeletonModifier3D).active = false
		for node in golfer.find_children("*", "MeshInstance3D", true, false):
			var n := str(node.name)
			if n.begins_with("Driver") or n.begins_with("Putter") or n.begins_with("Iron"):
				(node as MeshInstance3D).visible = false
		var player := golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player.has_animation(&"idle"):
			player.play(&"idle")
			player.seek(0.0, true)
			player.pause()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_pose()
		_cam.fov = 30.0
	var rows := ceili(_looks.size() / 8.0)
	if _frames >= 3 and _frames < 3 + rows * 5:
		var row := (_frames - 3) / 5
		if (_frames - 3) % 5 == 0:
			_cam.position = Vector3(ROW_GAP * row, 1.05, 8.6)
			_cam.look_at(Vector3(ROW_GAP * row, 0.9, 0))
		elif (_frames - 3) % 5 == 4:
			root.get_viewport().get_texture().get_image().save_png("%s/lineup_%d.png" % [_out, row])
	var start := 3 + rows * 5
	if _frames >= start and (_frames - start) % 5 == 0:
		if _step > 0:
			root.get_viewport().get_texture().get_image().save_png("%s/face_%d.png" % [_out, _step - 1])
		if _step == _golfers.size():
			print("rendered lineup and %d faces" % _step)
			return true
		_face(_step)
		_step += 1
	return false


## Aims the camera at golfer k's face, a little from the side, as a TV
## close-up would.
func _face(k: int) -> void:
	var golfer := _golfers[k]
	var skel := golfer.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.stop()
	player.active = false
	skel.reset_bone_poses()
	var head := skel.find_bone("head")
	var pos := golfer.global_position + Vector3(0, _looks[k].height_cm / 100.0 * 0.93, 0)
	if head >= 0:
		pos = (skel.global_transform * skel.get_bone_global_pose(head)).origin + Vector3(0, 0.03, 0)
	_cam.fov = 22.0
	_cam.position = pos + Vector3(0.3, 0.0, 1.0)
	_cam.look_at(pos)
