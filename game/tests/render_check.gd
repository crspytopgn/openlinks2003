extends SceneTree
## Renders the round with a real GPU driver (Mesa's software renderers in CI)
## so shader and material errors show up, which the headless test run can't
## catch. Shows hole 2 (it has a pond), plays one shot, saves a screenshot
## and checks that the sky is blue and the ground green. Then opens the
## course designer and saves a screenshot of it too (out-designer.jpg), and
## close-ups of the free golfer at the top, just before impact and at the
## finish (out-golfer.jpg).
##
##   godot --path game --rendering-method gl_compatibility -s res://tests/render_check.gd -- out.png

const FLYOVER_FRAME := 20
const SHOT_FRAME := 40
const CAPTURE_FRAME := 100
const DESIGNER_FRAME := 150
const GOLFER_FRAME := 160
## Free golfer poses for the close-up: clip and seconds into it.
const GOLFER_POSES := [[&"backswing", 0.93], [&"swing", 0.25], [&"swing", 0.29], [&"swing", 1.2]]
## Performance budget for the round, per frame, checked at the flyover and
## from the tee (Photoreal look at Ultra trees and grass, the heaviest a
## player can pick). Counts, not times: the CI machines render in
## software, so their frame times say nothing about a player's GPU, but
## draw calls, triangles, scene objects and video memory are the same
## everywhere and are what make a scene slow on phones and in the browser.
## Raise a limit only with a reason in docs/graphics.md. Video memory is
## the browser and phone limit in Compatibility; Forward+ is desktop only
## and its Ultra shadow atlas alone (8192 squared) takes 256 MB.
const BUDGET := {
	"draw calls": 1500,
	"triangles (millions)": 2.0,
	"objects": 2500,
	"video memory (MB)": 512.0,
}
const FORWARD_PLUS_VIDEO_MB := 1024.0

var _game: GolfRound
var _designer: Node
var _frames := 0
var _out := ""
var _golfer_scene: Node3D
var _golfer_player: AnimationPlayer
var _golfer_shots: Array[Image] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://render_check.png"
	print("renderer: %s" % RenderingServer.get_current_rendering_method())
	# Fixed wind, so the shots (and what the camera sees) are the same every run.
	GolfRound.wind_seed = 20031
	# The richest look, so every effect's shader compiles; a fixed 3D
	# resolution, as software rendering is far too slow for 60 fps.
	GraphicsSettings.force_look = GraphicsSettings.Look.PHOTOREAL
	var scene: PackedScene = load("res://scenes/main.tscn")
	_game = scene.instantiate() as GolfRound
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# The round is ready by now.
		_game.graphics.dynamic_res = 0
		_game._apply_graphics()
	elif _frames == 2:
		_game.start_hole(1)
		_game.scenery.set_backdrop(_test_horizon())
	elif _frames == 3:
		print("post process: visible %s, covers %s" % [_game.post.visible, _game.post.covered_size()])
	elif _frames == FLYOVER_FRAME:
		# The Broadcast presentation opens the hole with a flyover.
		_save_jpg(root.get_texture().get_image(), "-flyover")
		if not _check_budget("flyover"):
			return true
		_game.camera.end_flyover()
	elif _frames == SHOT_FRAME:
		_save_jpg(root.get_texture().get_image(), "-tee")
		if not _check_budget("tee"):
			return true
		_game.auto_play_step()
	elif _frames == CAPTURE_FRAME:
		if not _capture():
			return true
		_game.queue_free()
		_designer = (load("res://scenes/course_designer.tscn") as PackedScene).instantiate()
		root.add_child(_designer)
	elif _frames == DESIGNER_FRAME:
		_save_jpg(root.get_texture().get_image(), "-designer")
		_designer.queue_free()
		_golfer_stage()
	elif _frames >= GOLFER_FRAME and _frames < GOLFER_FRAME + 4 * GOLFER_POSES.size():
		# Each pose gets a few frames to settle, then its quarter of the image.
		var k: int = (_frames - GOLFER_FRAME) / 4
		if (_frames - GOLFER_FRAME) % 4 == 0:
			var p: Array = GOLFER_POSES[k]
			_golfer_pose(p[0], p[1])
		elif (_frames - GOLFER_FRAME) % 4 == 3:
			_golfer_shots.append(root.get_texture().get_image())
	elif _frames == GOLFER_FRAME + 4 * GOLFER_POSES.size():
		_save_golfer_sheet()
		print("RENDER CHECK DONE")
		quit(0)
		return true
	return false



## A plain lit stage with the free golfer, seen from in front.
func _golfer_stage() -> void:
	_golfer_scene = Node3D.new()
	root.add_child(_golfer_scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	_golfer_scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	_golfer_scene.add_child(sun)
	var golfer := FreeGolfer.create()
	if golfer == null:
		print("golfer close-up: no free golfer model")
		return
	_golfer_scene.add_child(golfer)
	_golfer_player = golfer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var cam := Camera3D.new()
	cam.fov = 40.0
	_golfer_scene.add_child(cam)
	cam.look_at_from_position(Vector3(0.3, 1.2, -4.2), Vector3(0, 1.0, 0))
	cam.make_current()


func _golfer_pose(clip: StringName, seconds: float) -> void:
	if _golfer_player and _golfer_player.has_animation(clip):
		_golfer_player.play(clip, 0.0)
		_golfer_player.seek(seconds, true)
		_golfer_player.pause()


## The poses side by side, as out-golfer.jpg.
func _save_golfer_sheet() -> void:
	if _golfer_shots.is_empty():
		return
	var w := _golfer_shots[0].get_width()
	var h := _golfer_shots[0].get_height()
	var crop := Rect2i(w * 3 / 10, 0, w * 2 / 5, h)
	var sheet := Image.create_empty(crop.size.x * _golfer_shots.size(), h, false, _golfer_shots[0].get_format())
	for i in _golfer_shots.size():
		sheet.blit_rect(_golfer_shots[i], crop, Vector2i(crop.size.x * i, 0))
	_save_jpg(sheet, "-golfer")


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


## The last frame's counts against BUDGET; false (and quits) if over.
func _check_budget(view: String) -> bool:
	var used := {
		"draw calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles (millions)": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video memory (MB)": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}
	var limits := BUDGET.duplicate()
	if GraphicsSettings.is_forward_plus():
		limits["video memory (MB)"] = FORWARD_PLUS_VIDEO_MB
	var ok := true
	var line := "budget %s:" % view
	for key: String in limits:
		var value: float = used[key]
		line += "  %s %.1f/%.1f" % [key, value, float(limits[key])]
		if value > float(limits[key]):
			ok = false
	print(line)
	if not ok:
		print("RENDER CHECK FAILED: over the performance budget")
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
