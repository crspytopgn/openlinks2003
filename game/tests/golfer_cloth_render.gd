extends SceneTree
## Renders the golfer's clothes moving (GolferCloth) for review against
## slow-motion swing footage: full-size close-ups of the shirt and trousers
## through the swing, still against moving cloth, and a strip of frames in
## a strong wind. Pass the output folder after "--", then optionally an
## outfit (polo, sleeves, shorts) and "woman".
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_cloth_render.gd -- /tmp/cloth polo

const SIZE := Vector2i(1280, 960)
const DT := 1.0 / 60.0
## Wind for the wind strip, m/s (x, z): a 25 mph wind from the golfer's
## right-front.
const WIND := Vector2(-9.0, 7.0)

var _out := ""
var _golfer: FreeGolfer
var _player: AnimationPlayer
var _cloth: GolferCloth
var _cam: Camera3D
var _frames := 0
var _jobs: Array = []
var _job := -1
var _t := 0.0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/cloth"
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
	var look := PlayerLook.new()
	if args.size() > 1:
		look.outfit = args[1]
	if args.size() > 2 and args[2] == "woman":
		look.sex = 1.0
		look.hair = "ponytail"
	look.top = Color(0.12, 0.25, 0.5)
	look.bottom = Color(0.78, 0.74, 0.66)
	_golfer = FreeGolfer.create(look)
	_golfer.walk_in = false
	scene.add_child(_golfer)
	_player = _golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_cloth = _golfer._cloth
	_cloth.set_process(false)
	_cam = Camera3D.new()
	_cam.fov = 28.0
	scene.add_child(_cam)
	# [name, clip, time, detail, wind, camera pos, look at]
	var face_on := [Vector3(0.0, 1.15, -3.3), Vector3(0.0, 1.0, -0.4)]
	var behind := [Vector3(3.2, 1.2, -0.45), Vector3(0.0, 1.0, -0.45)]
	var shirt := [Vector3(0.4, 1.3, -1.7), Vector3(0.0, 1.15, -0.3)]
	var legs := [Vector3(0.3, 0.6, -2.0), Vector3(0.0, 0.5, -0.4)]
	# The swing clip starts at the top: impact is at about 0.3 s.
	for f: float in [0.0, 0.15, 0.25, 0.3, 0.36, 0.45, 0.8]:
		for d in [0, 3]:
			_jobs.append(["swing_%03d_d%d" % [int(f * 100), d], &"swing", f, d, Vector2.ZERO, face_on])
	for f: float in [0.0, 0.3]:
		for d in [0, 3]:
			_jobs.append(["shirt_%03d_d%d" % [int(f * 100), d], &"swing", f, d, Vector2.ZERO, shirt])
			_jobs.append(["behind_%03d_d%d" % [int(f * 100), d], &"swing", f, d, Vector2.ZERO, behind])
	for k in 6:
		_jobs.append(["wind_%d" % k, &"address", 0.5 + k * 0.08, 3, WIND, face_on])
		_jobs.append(["windlegs_%d" % k, &"address", 0.5 + k * 0.08, 3, WIND, legs])
	_jobs.append(["windlegs_still", &"address", 0.5, 0, WIND, legs])
	_jobs.append(["wind_still", &"address", 0.5, 0, WIND, face_on])


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


## Plays the clip up to the job's time in 60 Hz steps, so the springs
## carry the motion that led there.
func _run(job: Array) -> void:
	GolferCloth.detail = job[3]
	RenderingServer.global_shader_parameter_set("wind_vector", job[4])
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_cloth._springs.clear()
	_cloth._turn = [0.0, 0.0, 0.0, 0.0, 0]
	# A swing starts from the address and the backswing, so the springs
	# carry the backswing into it.
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
			_cloth._process(DT)
			t += DT
	var cam: Array = job[5]
	_cam.position = _golfer.to_global(cam[0])
	_cam.look_at(_golfer.to_global(cam[1]))
