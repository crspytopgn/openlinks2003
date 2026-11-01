extends SceneTree
## Renders the tee shot of hole 1 with the 3D golfer and with the photo
## golfer (PhotoGolfer) at the same moments (address, top, impact, finish)
## for a side-by-side: out-3d.png and out-photo.png, each a row of full-size
## crops round the golfer, and out-tee-*.jpg, the whole tee view at address.
##
##   godot --path game --rendering-method gl_compatibility -s res://tests/photo_golfer_render.gd -- /tmp/out

## The first picture after the round opens can come out black in software
## rendering, so the address is taken twice and the first one dropped.
const POSES := [[&"address", 0.0], [&"address", 0.0], [&"backswing", 0.9], [&"swing", 0.24], [&"swing", 1.2]]
const CROP := Vector2i(560, 640)
const SETTLE := 12

var _game: GolfRound
var _out := ""
var _frames := 0
var _photo := false
var _pose := 0
var _shots: Array[Image] = []
var _start := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/photo_golfer"
	GolfRound.wind_seed = 20031
	GraphicsSettings.force_look = GraphicsSettings.Look.PHOTOREAL
	_new_game()


func _new_game() -> void:
	Engine.time_scale = 1.0
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GolfRound
	root.add_child(_game)
	_frames = 0
	_pose = 0
	_shots.clear()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_game.graphics.dynamic_res = 0
		_game.graphics.photo_golfer = _photo
		_game._apply_graphics()
	elif _frames == 2:
		_game.start_hole(0)
	elif _frames == 20:
		_game.camera.end_flyover()
		_start = 120
	elif _frames == _start and _pose < POSES.size():
		var p: Array = POSES[_pose]
		_set_pose(p[0], p[1])
	elif _frames == _start + SETTLE and _pose < POSES.size():
		var img := root.get_texture().get_image()
		if _pose == 1:
			img.save_jpg("%s-tee-%s.jpg" % [_out, "photo" if _photo else "3d"], 0.9)
		_shots.append(_crop(img))
		_pose += 1
		_start = _frames + 1
		if _pose == POSES.size():
			_save_row()
			if _photo:
				print("PHOTO GOLFER RENDER DONE")
				quit(0)
				return true
			_game.queue_free()
			_photo = true
			_new_game()
	return false


func _set_pose(clip: StringName, seconds: float) -> void:
	var g := _game.golfer
	Engine.time_scale = 1.0
	g.play(clip)
	var player := g.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.is_playing():
		# No blend from the last pose: time is stopped for the picture.
		var anim := player.current_animation
		player.stop()
		player.play(anim, 0.0)
		player.seek(seconds, true)
	if g is PhotoGolfer:
		(g as PhotoGolfer).seek(seconds)
	Engine.time_scale = 0.0


func _crop(img: Image) -> Image:
	var cam := _game.get_viewport().get_camera_3d()
	var at := cam.unproject_position(_game.golfer.global_position + Vector3(0, 0.9, 0))
	var scale := float(img.get_width()) / float(_game.get_viewport().get_visible_rect().size.x)
	var c := Vector2i(at * scale)
	var r := Rect2i(c - CROP / 2, CROP).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out := Image.create(CROP.x, CROP.y, false, img.get_format())
	out.blit_rect(img, r, Vector2i.ZERO)
	return out


func _save_row() -> void:
	_shots.remove_at(0)
	var row := Image.create(CROP.x * _shots.size(), CROP.y, false, _shots[0].get_format())
	for i in _shots.size():
		row.blit_rect(_shots[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * i, 0))
	row.save_png("%s-%s.png" % [_out, "photo" if _photo else "3d"])
