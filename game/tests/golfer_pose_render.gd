extends SceneTree
## Renders the golfer's body in chosen poses, full size, for checking the
## joints against photos of real golfers (tools/golfer/anatomy.py measures
## the same poses by numbers). Pass the output folder after "--", then a
## person (PlayerLook.PEOPLE, "" for the default, "-" for the Custom body) and jobs written
## name=clip@seconds/view, where view is one of VIEWS.
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_pose_render.gd -- /tmp/pose "" \
##     read=read@2.0/side putt=address_putt@0.5/hands_front

const SIZE := Vector2i(1280, 960)
const DT := 1.0 / 60.0
## Camera offset from the target point, in the golfer's frame (he faces
## -z, the target is at -x), the bone it looks at and the field of view.
const VIEWS := {
	"front": [Vector3(0.0, 0.2, -3.6), "pelvis", 30.0],
	"side": [Vector3(-3.6, 0.1, 0.0), "pelvis", 30.0],
	"back": [Vector3(3.0, 0.4, 2.0), "pelvis", 30.0],
	"behind": [Vector3(0.0, 0.3, 3.6), "pelvis", 30.0],
	"dtl": [Vector3(3.6, 0.15, -0.4), "pelvis", 30.0],
	"hands_front": [Vector3(0.1, 0.1, -1.1), "hands", 30.0],
	"hands_side": [Vector3(-1.1, 0.15, -0.2), "hands", 30.0],
	"hands_top": [Vector3(0.15, 1.0, -0.35), "hands", 32.0],
	"hands_trail": [Vector3(1.0, 0.2, -0.5), "hands", 30.0],
	"grip_trail": [Vector3(0.45, -0.05, -0.3), "hands", 30.0],
	"grip_front": [Vector3(0.05, 0.0, -0.55), "hands", 30.0],
	"grip_dtl": [Vector3(0.7, 0.05, -0.05), "hands", 30.0],
	"grip_lead": [Vector3(-0.6, 0.0, -0.3), "hands", 30.0],
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
	_out = args[0] if args.size() > 0 else "/tmp/pose"
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
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -150, 0)
	sun.light_energy = 2.6
	sun.shadow_enabled = true
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
	if args.size() > 1 and args[1] == "-":
		look.person = ""  # the sculpted "Custom" body
	elif args.size() > 1 and args[1] != "":
		look.person = args[1]
	_golfer = FreeGolfer.create(look)
	_golfer.walk_in = false
	scene.add_child(_golfer)
	_player = _golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_cam = Camera3D.new()
	_cam.near = 0.02
	scene.add_child(_cam)
	for i in range(2, args.size()):
		var job := args[i]
		var name := job.get_slice("=", 0)
		var rest := job.get_slice("=", 1)
		_jobs.append([name, StringName(rest.get_slice("@", 0)), float(rest.get_slice("@", 1).get_slice("/", 0)),
			rest.get_slice("/", 1)])


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


func _run(job: Array) -> void:
	var clip: StringName = job[1]
	_golfer._show_putter(String(clip).contains("putt") or clip == &"read")
	_player.play(clip)
	_player.seek(0.0, true)
	if _golfer._hands:
		# The right hand's grip IK, as FreeGolfer.play turns it on.
		_golfer._hands.follow(clip, 0.0)
	var t := 0.0
	while t < float(job[2]) - 0.001:
		_player.advance(DT)
		t += DT
	_player.advance(0.0)
	var view: Array = VIEWS.get(job[3], VIEWS["front"])
	var target: Vector3
	if view[1] == "hands":
		target = (_bone("hand_l") + _bone("hand_r")) * 0.5
	else:
		target = _bone(view[1]) + Vector3(0.0, -0.1, 0.0)
	_cam.fov = view[2]
	_cam.position = target + _golfer.global_basis * (view[0] as Vector3)
	_cam.look_at(target)
