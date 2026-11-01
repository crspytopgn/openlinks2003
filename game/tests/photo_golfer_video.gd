extends SceneTree
## Records the tee shot of hole 1 as a video: the address, the backswing,
## the swing and the ball away, with the photo golfer ("photo" argument) or
## the 3D golfer. Run with Godot's movie writer so every frame is 1/30 s:
##
##   godot --path game --rendering-method gl_compatibility --write-movie /tmp/shot.avi --fixed-fps 30 \
##       -s res://tests/photo_golfer_video.gd -- photo

const BACKSWING_AT := 60
const SWING_AT := 90
const END_AT := 240

var _game: GolfRound
var _frames := 0
var _photo := false


func _initialize() -> void:
	_photo = OS.get_cmdline_user_args().has("photo")
	GolfRound.wind_seed = 20031
	GraphicsSettings.force_look = GraphicsSettings.Look.PHOTOREAL
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_game.graphics.dynamic_res = 0
		_game.graphics.photo_golfer = _photo
		_game._apply_graphics()
	elif _frames == 2:
		_game.start_hole(0)
		_game.camera.end_flyover()
		_game.golfer.play(&"address")
	elif _frames == BACKSWING_AT:
		_game._on_backswing_started()
	elif _frames == SWING_AT:
		_game.play_shot(0.95, 0.0)
	elif _frames == END_AT:
		quit(0)
		return true
	return false
