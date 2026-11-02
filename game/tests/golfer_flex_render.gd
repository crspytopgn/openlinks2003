extends SceneTree
## Renders the golfers' working forearms and neck (GolferFlex) for review
## against slow-motion swing footage: full-size close-ups through the
## swing with the flex off and on. Pass the output folder after "--",
## then optionally a person (PlayerLook.PEOPLE) and "mask" (the baked
## forearm and neck map in colour instead).
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_flex_render.gd -- /tmp/flex Male_Adult_14

const SIZE := Vector2i(1280, 960)
const DT := 1.0 / 60.0

var _out := ""
var _golfer: FreeGolfer
var _player: AnimationPlayer
var _flex: GolferFlex
var _cam: Camera3D
var _frames := 0
var _jobs: Array = []
var _job := -1
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/flex"
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = SIZE
	var scene := Node3D.new()
	root.add_child(scene)
	var env := Environment.new()
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.32, 0.5, 0.78)
	psky.sky_horizon_color = Color(0.72, 0.78, 0.85)
	sky.sky_material = psky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -150, 0)
	sun.light_energy = 3.0
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20.0
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.36, 0.12)
	gm.roughness = 0.95
	ground.material_override = gm
	scene.add_child(ground)
	var look := PlayerLook.default_look()
	if args.size() > 1 and args[1] != "":
		look.person = args[1]
	look.top = Color(0.12, 0.25, 0.5)
	look.bottom = Color(0.25, 0.25, 0.27)
	_golfer = FreeGolfer.create(look)
	_golfer.walk_in = false
	scene.add_child(_golfer)
	_player = _golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_flex = _golfer._flex
	_flex.set_process(false)
	_golfer._cloth.set_process(false)
	if args.size() > 2 and args[2] == "mask":
		for m in _flex.materials:
			m.set_shader_parameter("flex_debug", 1.0)
	_cam = Camera3D.new()
	_cam.fov = 22.0
	scene.add_child(_cam)
	# [name, clip, time, detail, view]
	# The swing clip starts at the top: impact is at about 0.3 s.
	for f: float in [0.0, 0.22, 0.3, 0.36, 0.5]:
		for d in [0, 2]:
			_jobs.append(["arms_%03d_d%d" % [int(f * 100), d], &"swing", f, d, "arms"])
			_jobs.append(["neck_%03d_d%d" % [int(f * 100), d], &"swing", f, d, "neck"])
	for d in [0, 2]:
		_jobs.append(["arms_address_d%d" % d, &"address", 0.5, d, "arms"])
		_jobs.append(["trail_000_d%d" % d, &"swing", 0.0, d, "trail"])
		_jobs.append(["trail_030_d%d" % d, &"swing", 0.3, d, "trail"])
		_jobs.append(["body_030_d%d" % d, &"swing", 0.3, d, "body"])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _job < 0 or _wait == 0:
		if _job >= 0:
			var img := root.get_viewport().get_texture().get_image()
			img.save_jpg("%s/%s.jpg" % [_out, _jobs[_job][0]], 0.92)
		_job += 1
		if _job >= _jobs.size():
			return true
		_run(_jobs[_job])
		_wait = 3
		return false
	_wait -= 1
	return false


func _bone(name: String) -> Vector3:
	var sk: Skeleton3D = _golfer._skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin


## Plays the clip up to the job's time in 60 Hz steps, so the grip carries
## the motion that led there.
func _run(job: Array) -> void:
	GolferFlex.detail = job[3]
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_flex.grip = GolferFlex.GRIP_REST
	_flex._have_last = false
	var steps: Array = [[&"address", 0.5]]
	if job[1] == &"swing":
		steps.append([&"backswing", _player.get_animation(&"backswing").length])
	steps.append([job[1], float(job[2])])
	for st: Array in steps:
		_player.play(st[0])
		_player.seek(0.0, true)
		var t := 0.0
		while t < float(st[1]) - 0.001:
			_player.advance(DT)
			_flex._process(DT)
			t += DT
	var target: Vector3
	var from: Vector3
	match job[4]:
		"arms":
			target = (_bone("lowerarm_l") + _bone("hand_l")) * 0.5
			from = target + _golfer.global_basis * Vector3(0.15, 0.1, -1.2)
		"trail":
			target = (_bone("lowerarm_r") + _bone("hand_r")) * 0.5
			from = target + _golfer.global_basis * Vector3(1.0, 0.15, -0.6)
		"neck":
			target = (_bone("neck_01") + _bone("head")) * 0.5
			from = target + _golfer.global_basis * Vector3(-0.75, -0.12, -0.45)
		_:
			target = _bone("spine_03")
			from = target + _golfer.global_basis * Vector3(0.0, 0.1, -3.2)
	_cam.position = from
	_cam.look_at(target)
