class_name PhotoGolfer
extends GolferRig
## The "Photo golfer" option: a real person filmed swinging, played back
## frame by frame like the filmed golfers of the early Links games, so the
## golfer looks like a photograph. The frames are cut out of a freely
## licensed video by tools/photo_golfer/build_photo_golfer.py, each a WebP
## in res://assets/photo_golfer/<take>/frames.olp, with a take.json (per
## frame where it is in the pack, its size and where the ball is; per clip
## the frames, their times and the moment of impact). Only the frame on
## screen is decoded, into one small texture, so a take of any length costs
## about a megabyte of video memory; the last few frames are kept decoded.
##
## The frames are drawn on a card at the ball that turns about the vertical
## to face the camera, placed so the ball in the picture sits on the real
## ball, and scaled to the take's pixels per metre (measured from the ball in
## the film), then to the player's height (PlayerLook.height_cm) against the
## filmed golfer's. A second card turned to
## the sun draws the same frame into the shadow map only.
##
## A take is filmed from one side. When the camera looks at the golfer from
## too far round (more than VIEW_LIMIT from the filmed view) or the round
## asks for a clip the take doesn't have (putts, reactions, the walk), the
## 3D golfer it wraps stands in instead, so the option never leaves a gap.

const TAKE_DIR := "res://assets/photo_golfer/"
const DEFAULT_TAKE := "suvichaya_iron_dtl"
## Where the ball is in the rig (GolferRig).
const BALL := Vector3(0.0, 0.0, -0.75)
## The direction from the ball to the camera that filmed the take, in the
## rig's frame (target -x): behind the ball on the target line, a little
## towards the golfer's back.
const FILMED_VIEW := Vector3(1.0, 0.0, 0.3)
const VIEW_LIMIT := deg_to_rad(50.0)
## Light from the filmed day (overcast) pulled towards the course's light.
const EXPOSURE := 1.0
## Decoded frames kept for going back (the address after a swing).
const CACHE := 8

var _fallback: GolferRig
var _take := {}
var _pack: FileAccess
var _texture: ImageTexture
var _decoded := {}  ## frame key -> Image, the last CACHE shown
var _decoded_order: Array[String] = []
var _px_per_m := 200.0
## The player's height over the filmed golfer's.
var _height_scale := 1.0
var _pivot: Node3D
var _card: MeshInstance3D
var _shadow: MeshInstance3D
var _material: ShaderMaterial
var _shadow_material: ShaderMaterial
var _clip := {}
var _clip_name := &""
var _time := 0.0
var _frame := ""
var _photo_on := false  ## the take is playing the current clip
var _sun: DirectionalLight3D


## Wraps `fallback` (the 3D golfer) with the photo golfer. Returns the
## fallback itself if the take can't be read.
## `look` gives the player's height; without one the filmed golfer keeps
## her own.
static func wrap(fallback: GolferRig, look: PlayerLook = null, take := DEFAULT_TAKE) -> GolferRig:
	var data := read_take(take)
	if data.is_empty():
		return fallback
	var g := PhotoGolfer.new()
	g._take = data
	g._fallback = fallback
	var filmed := float(data.get("golfer_height_m", 0.0))
	if look != null and filmed > 0.0:
		g._height_scale = clampf(look.height_cm / 100.0 / filmed, 0.8, 1.3)
	g._build(take)
	return g


## The take's take.json, or {} if it is missing or broken.
static func read_take(take: String) -> Dictionary:
	var path := TAKE_DIR + take + "/take.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).has("frames"):
		return {}
	if not FileAccess.file_exists(TAKE_DIR + take + "/" + String((parsed as Dictionary).get("pack", ""))):
		return {}
	return parsed


## The take's source and licence, for the credits.
func source() -> Dictionary:
	return _take.get("source", {})


func _build(take: String) -> void:
	name = "PhotoGolfer"
	add_child(_fallback)
	_px_per_m = float(_take.get("px_per_m", 200.0))
	_pack = FileAccess.open(TAKE_DIR + take + "/" + String(_take["pack"]), FileAccess.READ)
	_pivot = Node3D.new()
	_pivot.position = BALL
	add_child(_pivot)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/photo_golfer.gdshader")
	_material.set_shader_parameter("exposure", EXPOSURE)
	_card = MeshInstance3D.new()
	_card.mesh = quad
	_card.material_override = _material
	_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(_card)
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = preload("res://shaders/photo_golfer_shadow.gdshader")
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.material_override = _shadow_material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(_shadow)
	_set_photo(false)


func play(animation: StringName) -> void:
	_fallback.play(animation)
	var clips: Dictionary = _take.get("clips", {})
	_clip_name = animation
	_clip = clips.get(String(animation), {})
	_time = 0.0
	_show_frame()


func set_shot(club: Club, distance_m: float, power: float = 1.0) -> void:
	_fallback.set_shot(club, distance_m, power)


## The filmed club meets the ball this far into the swing clip; while the 3D
## golfer stands in (a side view), its own timing.
func impact_delay() -> float:
	var swing: Dictionary = _take.get("clips", {}).get("swing", {})
	if not swing.has("impact") or not filmed_view_ok():
		return _fallback.impact_delay()
	return float(swing["impact"])


func watch(target: Node3D, delay: float = 0.3) -> void:
	_fallback.watch(target, delay)


func set_ground(height: Callable, sink: float = 0.0) -> void:
	_fallback.set_ground(height, sink)


## Shows the current clip `seconds` in (for renders and tests).
func seek(seconds: float) -> void:
	_time = seconds
	_show_frame()


func _process(delta: float) -> void:
	if _clip.is_empty():
		return
	_time += delta
	_show_frame()


## True while the camera is near enough to the filmed view for the picture
## to be right.
func filmed_view_ok() -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return true
	var local := global_transform.affine_inverse() * cam.global_position - BALL
	local.y = 0.0
	if local.length() < 0.01:
		return true
	return local.angle_to(FILMED_VIEW) <= VIEW_LIMIT


func _show_frame() -> void:
	var frames: Array = _clip.get("frames", [])
	if frames.is_empty() or not filmed_view_ok():
		_set_photo(false)
		return
	var times: Array = _clip.get("times", [])
	var i := 0
	var t := _time
	if _clip.get("loop", false) and not times.is_empty():
		var length := float(times[-1]) + 1.0 / 30.0
		t = fmod(t, maxf(length, 0.001))
	while i + 1 < frames.size() and i + 1 < times.size() and float(times[i + 1]) <= t:
		i += 1
	_set_photo(true)
	_use_frame(str(int(frames[i])))


func _set_photo(on: bool) -> void:
	_photo_on = on
	_card.visible = on
	_shadow.visible = on
	_fallback.visible = not on


func _use_frame(key: String) -> void:
	_face_camera()
	if key == _frame:
		return
	_frame = key
	var f: Dictionary = _take["frames"].get(key, {})
	if f.is_empty():
		return
	var image := _decode(key, f)
	if image == null:
		return
	if _texture != null and _texture.get_size() == Vector2(image.get_size()):
		_texture.update(image)
	else:
		_texture = ImageTexture.create_from_image(image)
		for mat: ShaderMaterial in [_material, _shadow_material]:
			mat.set_shader_parameter("sheet", _texture)
	var r: Array = f["size"]
	var ball: Array = f["ball"]
	var ppm := _px_per_m / _height_scale
	var metres := Vector2(float(r[0]), float(r[1])) / ppm
	# The card's centre from the ball: the ball's pixel is on the ball.
	var offset := Vector3((float(r[0]) * 0.5 - float(ball[0])) / ppm,
			(float(ball[1]) - float(r[1]) * 0.5) / ppm, 0.0)
	_card.scale = Vector3(metres.x, metres.y, 1.0)
	_card.position = offset
	_shadow.scale = _card.scale
	_shadow.set_meta("offset", offset)
	_face_camera()


## Frame `key` decoded from the pack (with mipmaps, for the long tee
## views), or null if it can't be read.
func _decode(key: String, f: Dictionary) -> Image:
	if _decoded.has(key):
		return _decoded[key]
	if _pack == null:
		return null
	_pack.seek(int(f["offset"]))
	var image := Image.new()
	if image.load_webp_from_buffer(_pack.get_buffer(int(f["bytes"]))) != OK:
		return null
	image.generate_mipmaps()
	_decoded[key] = image
	_decoded_order.append(key)
	if _decoded_order.size() > CACHE:
		_decoded.erase(_decoded_order.pop_front())
	return image


## Turns the card to the camera and the shadow card to the sun, both about
## the vertical.
func _face_camera() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var ball := to_global(BALL)
	if cam != null:
		var to_cam := cam.global_position - ball
		_pivot.global_basis = Basis(Vector3.UP, atan2(to_cam.x, to_cam.z))
	var to_sun := _sun_direction()
	to_sun.y = 0.0
	var yaw := atan2(to_sun.x, to_sun.z)
	var turn := Basis(Vector3.UP, yaw)
	var offset: Vector3 = _shadow.get_meta("offset", Vector3.ZERO)
	# Turned about the golfer's feet (the rig's origin), not the ball, so the
	# shadow starts at the feet: in the picture they are BALL's distance to
	# the left of the ball.
	var feet := global_position
	offset.x += -BALL.z
	_shadow.global_transform = Transform3D(turn * Basis.from_scale(_card.scale), feet + turn * offset)


func _sun_direction() -> Vector3:
	if _sun == null or not is_instance_valid(_sun):
		_sun = _find_sun(get_tree().root)
	if _sun == null:
		return Vector3(0.3, 0.0, 1.0)
	return _sun.global_basis.z


static func _find_sun(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D and (node as DirectionalLight3D).visible:
		return node
	for child in node.get_children():
		var found := _find_sun(child)
		if found != null:
			return found
	return null
