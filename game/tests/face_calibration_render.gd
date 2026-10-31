extends SceneTree
## Part of tools/golfer/face_calibration.sh: renders golfers' faces from the
## front with random known face sliders (and a mix of bodies), as photos for
## MediaPipe. Writes face_N.png and truth.json (the looks) to the folder
## given after "--".

const FACES := 48
## The face sliders varied: those a photo from the front could show.
const VARIED := [
	"face_width", "face_length", "face_full", "jaw", "chin_height", "nose_width", "nose_length",
	"eye_size", "eye_spacing", "brows", "mouth_width", "lips",
]

var _frames := 0
var _out := ""
var _looks: Array[PlayerLook] = []
var _golfer: FreeGolfer
var _cam: Camera3D
var _i := 0


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.82, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 10, 0)
	sun.light_energy = 0.8
	scene.add_child(sun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in FACES:
		var l := PlayerLook.random(1000 + k)
		l.cap = false
		l.hair = ["crop", "short", "side_part", "ponytail"][k % 4]
		for key: String in l.face:
			l.face[key] = 0.0
		if k > 0:
			for key: String in VARIED:
				l.face[key] = snappedf(rng.randf_range(-0.9, 0.9), 0.01)
		_looks.append(l)
	_golfer = FreeGolfer.create(_looks[0])
	scene.add_child(_golfer)
	_cam = Camera3D.new()
	_cam.fov = 28
	scene.add_child(_cam)
	var truth := []
	for l in _looks:
		truth.append(l.to_dict())
	FileAccess.open(_out + "/truth.json", FileAccess.WRITE).store_string(JSON.stringify(truth))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 4 == 1:
		_golfer.apply_look(_looks[_i])
		(_golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer).stop()
		for s in _golfer.find_children("*", "Skeleton3D", true, false):
			(s as Skeleton3D).reset_bone_poses()
		var y := _looks[_i].height_cm / 100.0 * 0.925
		_cam.position = Vector3(0, y, -0.75)
		_cam.look_at(Vector3(0, y, 0))
	if _frames % 4 == 0:
		root.get_viewport().get_texture().get_image().save_png("%s/face_%d.png" % [_out, _i])
		_i += 1
		if _i == _looks.size():
			print("rendered %d faces" % _i)
			return true
	return false
