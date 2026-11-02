extends SceneTree
## Close-ups of every realistic person's cap for review against real photos:
## front, three-quarter, side, back and from above, at rest and at address,
## the top of the backswing and the finish. Pass the output folder after
## "--", optionally followed by "dad" (the dad cap) and person ids.
##
##   xvfb-run godot --rendering-driver vulkan --path game \
##     -s res://tests/golfer_cap_render.gd -- /tmp/caps

const SIZE := Vector2i(1200, 1200)
## Camera offsets from the head (metres), in the golfer's frame (the
## golfer faces -z).
const VIEWS := {
	"face": Vector3(0, -0.02, -0.75),
	"face_three_quarter": Vector3(-0.5, -0.01, -0.55),
	"face_high": Vector3(-0.35, 0.12, -0.65),
	"side": Vector3(0.75, 0.0, 0),
	"behind": Vector3(0.3, 0.05, 0.7),
	"above": Vector3(0.25, 0.6, 0.35),
}
## Swing clips and the time (s) to pose each at.
const POSES := [["rest", "idle", 0.0], ["address", "address", 0.0], ["top", "swing", 0.0], ["finish", "swing", 1.4]]

var _out := ""
var _frames := 0
var _people: Array[String] = []
var _golfer: FreeGolfer
var _scene: Node3D
var _cam: Camera3D
var _jobs: Array = []
var _job := -1
var _wait := 0
var _person := ""
var _style := "tour"
var _golfer_fresh := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/caps"
	DirAccess.make_dir_recursive_absolute(_out)
	for k in range(1, args.size()):
		if args[k] == "dad":
			_style = "dad"
		else:
			_people.append(args[k])
	if _people.is_empty():
		for p: Array in PlayerLook.PEOPLE:
			_people.append(p[0])
	root.size = SIZE
	_scene = Node3D.new()
	root.add_child(_scene)
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
	_scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 3.0
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	_scene.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_scene.add_child(_cam)
	for person in _people:
		for pose: Array in POSES:
			for view: String in VIEWS:
				if pose[0] != "rest" and view == "above":
					continue
				_jobs.append([person, pose, view])


func _make(person: String) -> void:
	if _golfer != null:
		_golfer.queue_free()
	var look := PlayerLook.new()
	look.person = person
	look.sex = PlayerLook.person_sex(person)
	look.cap = true
	look.cap_style = _style
	look.cap_colour = Color(0.08, 0.1, 0.18)
	_golfer = FreeGolfer.create(look)
	_golfer.walk_in = false
	_scene.add_child(_golfer)


func _pose(pose: Array) -> void:
	var player := _golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for node in _golfer.find_children("*", "MeshInstance3D", true, false):
		var n := str(node.name)
		if n.begins_with("Putter") or n.begins_with("Iron"):
			(node as MeshInstance3D).visible = false
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var clip := StringName(str(pose[1]))
	if not player.has_animation(clip):
		return
	player.play(clip)
	var t := minf(float(pose[2]), player.get_animation(clip).length)
	player.seek(t, true)
	player.advance(0.0)


func _head() -> Vector3:
	var skel := _golfer.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skel.find_bone("head")
	return (skel.global_transform * skel.get_bone_global_pose(head)).origin + Vector3(0, 0.09, 0)


func _process(_delta: float) -> bool:
	_frames += 1
	if _wait > 0:
		_wait -= 1
		if _wait == 0 and not _golfer_fresh:
			var done: Array = _jobs[_job]
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [_out, done[0], done[1][0], done[2]])
		if _wait == 0:
			_golfer_fresh = false
		return false
	_job += 1
	if _job >= _jobs.size():
		print("rendered %d cap views" % _jobs.size())
		return true
	var j: Array = _jobs[_job]
	if _golfer == null or _person != j[0]:
		_person = j[0]
		_make(_person)
		_job -= 1
		_wait = 4
		_golfer_fresh = true
		return false
	_pose(j[1])
	var h := _head()
	var basis := _golfer.global_transform.basis
	_cam.position = h + basis * (VIEWS[j[2]] as Vector3)
	_cam.look_at(h)
	_wait = 3
	return false
