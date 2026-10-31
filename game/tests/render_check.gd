extends SceneTree
## Renders the round with a real GPU driver (Mesa's software renderers in CI)
## so shader and material errors show up, which the headless test run can't
## catch. Shows hole 2 (it has a pond), plays one shot, saves a screenshot
## and checks that the sky is blue and the ground green. Then opens the
## course designer and saves a screenshot of it too (out-designer.jpg).
##
##   godot --path game --rendering-method gl_compatibility -s res://tests/render_check.gd -- out.png

const SHOT_FRAME := 40
const CAPTURE_FRAME := 100
const DESIGNER_FRAME := 150

var _game: GolfRound
var _designer: Node
var _frames := 0
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://render_check.png"
	print("renderer: %s" % RenderingServer.get_current_rendering_method())
	# Fixed wind, so the shots (and what the camera sees) are the same every run.
	GolfRound.wind_seed = 20031
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_game.start_hole(1)
		_game.scenery.set_backdrop(_test_horizon())
	elif _frames == SHOT_FRAME:
		_save_jpg(root.get_texture().get_image(), "-tee")
		_game.auto_play_step()
	elif _frames == CAPTURE_FRAME:
		if not _capture():
			return true
		_game.queue_free()
		_designer = (load("res://scenes/course_designer.tscn") as PackedScene).instantiate()
		root.add_child(_designer)
	elif _frames == DESIGNER_FRAME:
		_save_jpg(root.get_texture().get_image(), "-designer")
		print("RENDER CHECK DONE")
		quit(0)
		return true
	return false


## Saves the round's screenshot; false (and quits) if it looks wrong.
func _capture() -> bool:
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("RENDER CHECK FAILED: no image")
		quit(1)
		return false
	img.save_png(_out)
	_save_jpg(img, "")
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	var top := _mean(img, Rect2i(img.get_width() / 3, 0, img.get_width() / 3, img.get_height() / 8))
	var bottom := _mean(img, Rect2i(img.get_width() / 4, img.get_height() * 3 / 4, img.get_width() / 2, img.get_height() / 8))
	print("sky %s  ground %s" % [top, bottom])
	var ok := top.b > top.r and top.b > 0.3 and bottom.g > bottom.b and bottom.g > 0.08
	if not ok:
		print("RENDER CHECK FAILED: unexpected colours")
		quit(1)
	return ok


## A smaller JPEG copy next to the PNG (out-tee.jpg for the view from the
## tee), which CI can print when asked for screenshots.
func _save_jpg(img: Image, suffix: String) -> void:
	if img == null or img.is_empty():
		return
	var small := img.duplicate() as Image
	small.resize(1280, 1280 * small.get_height() / small.get_width(), Image.INTERPOLATE_LANCZOS)
	small.save_jpg(_out.get_basename() + suffix + ".jpg", 0.85)


## A stand-in horizon so the backdrop's shader compiles here: green land
## below eye level, transparent above, like a course's Panorama.
func _test_horizon() -> Image:
	var img := Image.create_empty(1024, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(0, 64, 1024, 32), Color(0.25, 0.4, 0.2))
	return img


func _mean(img: Image, r: Rect2i) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(r.position.y, r.end.y, 4):
		for x in range(r.position.x, r.end.x, 4):
			sum += img.get_pixel(x, y)
			n += 1
	return sum / float(maxi(n, 1))
