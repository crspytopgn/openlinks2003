extends SceneTree
## Renders the round with a real GPU driver (Mesa's software renderers in CI)
## so shader and material errors show up, which the headless test run can't
## catch. Shows hole 2 (it has a pond), plays one shot, saves a screenshot
## and checks that the sky is blue and the ground green.
##
##   godot --path game --rendering-method gl_compatibility -s res://tests/render_check.gd -- out.png

const SHOT_FRAME := 40
const CAPTURE_FRAME := 100

var _game: GolfRound
var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://render_check.png"
	print("renderer: %s" % RenderingServer.get_current_rendering_method())
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_game.start_hole(1)
	elif _frames == SHOT_FRAME:
		_save_jpg(root.get_texture().get_image(), "-tee")
		_game.auto_play_step()
	elif _frames == CAPTURE_FRAME:
		_capture()
		return true
	return false


func _capture() -> void:
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("RENDER CHECK FAILED: no image")
		quit(1)
		return
	img.save_png(_out)
	_save_jpg(img, "")
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	var top := _mean(img, Rect2i(img.get_width() / 3, 0, img.get_width() / 3, img.get_height() / 8))
	var bottom := _mean(img, Rect2i(img.get_width() / 4, img.get_height() * 3 / 4, img.get_width() / 2, img.get_height() / 8))
	print("sky %s  ground %s" % [top, bottom])
	var ok := top.b > top.r and top.b > 0.3 and bottom.g > bottom.b and bottom.g > 0.08
	if ok:
		print("RENDER CHECK DONE")
		quit(0)
	else:
		print("RENDER CHECK FAILED: unexpected colours")
		quit(1)


## A smaller JPEG copy next to the PNG (out-tee.jpg for the view from the
## tee), which CI can print when asked for screenshots.
func _save_jpg(img: Image, suffix: String) -> void:
	if img == null or img.is_empty():
		return
	var small := img.duplicate() as Image
	small.resize(1280, 1280 * small.get_height() / small.get_width(), Image.INTERPOLATE_LANCZOS)
	small.save_jpg(_out.get_basename() + suffix + ".jpg", 0.85)


func _mean(img: Image, r: Rect2i) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(r.position.y, r.end.y, 4):
		for x in range(r.position.x, r.end.x, 4):
			sum += img.get_pixel(x, y)
			n += 1
	return sum / float(maxi(n, 1))
