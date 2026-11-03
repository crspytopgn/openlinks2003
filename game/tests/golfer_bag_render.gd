extends SceneTree
## Renders the golfer taking a club out of the stand bag (pull_club) for
## review against tour footage: full-size frames through the clip from the
## front and down the line, with the bag where the game stands it. Pass the
## output folder after "--", then optionally a person (PlayerLook.PEOPLE)
## and "iron".
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_bag_render.gd -- /tmp/bag Male_Adult_14

const SIZE := Vector2i(1280, 960)
const DT := 1.0 / 60.0
const TIMES: Array[float] = [0.0, 0.4, 0.65, 0.9, 1.15, 1.35, 1.5, 1.65, 1.8, 2.0, 2.2, 2.5]
## Camera offsets in the golfer's frame (he faces -z, his left is -x), and
## where they look.
const VIEWS := {
	"front": [Vector3(-1.2, 1.35, -3.0), Vector3(0.15, 1.05, -0.2)],
	"side": [Vector3(3.2, 1.3, 0.6), Vector3(0.15, 1.05, -0.2)],
	"hand": [Vector3(-0.5, 1.5, -1.7), Vector3(0.2, 1.15, -0.3)],
}

var _out := ""
var _golfer: FreeGolfer
var _player: AnimationPlayer
var _cam: Camera3D
var _frames := 0
var _jobs: Array = []
var _job := -1
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/bag"
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
	_golfer.set_shot(_club(args.size() > 2 and args[2] == "iron"), 150.0)
	_golfer.play(&"address")
	_player = _golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_golfer._cloth.set_process(false)
	# The bag where the game stands the golfer to it (FreeGolfer.pull_spot).
	var bag := StandBag.new()
	scene.add_child(bag)
	var model: Node3D = _golfer._model
	bag.global_transform = Transform3D(Basis(), model.global_transform * FreeGolfer.PULL_BAG_FOOT)
	bag.visible = true
	_cam = Camera3D.new()
	_cam.fov = 40.0
	scene.add_child(_cam)
	for view: String in VIEWS:
		for t in TIMES:
			_jobs.append(["%s_%03d" % [view, int(roundf(t * 100))], t, view])


func _club(iron: bool) -> Club:
	for c in Club.standard_set():
		if c.full_name == ("7 Iron" if iron else "Driver"):
			return c
	return null


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


## Plays the clip up to the job's time in 60 Hz steps, the club showing from
## the moment the hand closes on it, as in the game.
func _run(job: Array) -> void:
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_golfer._play(&"pull_club", 0.0, 1.0)  # the right hand off the grip too
	_player.seek(0.0, true)
	var t := 0.0
	while t < float(job[1]) - 0.001:
		_player.advance(DT)
		t += DT
	_player.advance(0.0)
	if t < FreeGolfer.PULL_GRAB:
		_golfer._hide_clubs()
	else:
		_golfer._show_putter(false)  # the driver or the iron, as set_shot chose
	var v: Array = VIEWS[job[2]]
	_cam.position = _golfer.global_transform * (v[0] as Vector3)
	_cam.look_at(_golfer.global_transform * (v[1] as Vector3))
