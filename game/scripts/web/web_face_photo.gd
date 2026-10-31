class_name WebFacePhoto
extends RefCounted
## The browser build's face from a photo, through game/web/face_photo.js:
## the player picks (or takes) a photo and MediaPipe's Face Landmarker finds
## the face on their device. Nothing is uploaded; only MediaPipe's code and
## model are downloaded, the first time.

signal _replied(ok: bool, value: Variant)

const SCRIPT_PATH := "res://web/face_photo.js"

var last_error := ""
var _api: JavaScriptObject
var _reply_cb: JavaScriptObject


static func is_supported() -> bool:
	return OS.has_feature("web")


func _init() -> void:
	if not is_supported():
		return
	JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)
	_api = JavaScriptBridge.get_interface("olFace")
	_reply_cb = JavaScriptBridge.create_callback(_on_reply)


## Asks the browser for a photo (`camera`: offer the front camera on
## phones). Null if cancelled or it failed (see last_error).
func pick(camera: bool) -> Image:
	last_error = ""
	_api.pick(camera, _reply_cb)
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return null
	var text := str(r[1])
	if text.is_empty():
		return null
	var info: Variant = JSON.parse_string(text)
	if not info is Dictionary:
		last_error = "the photo didn't come through"
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(Marshalls.base64_to_raw(str(info.jpeg))) != OK:
		last_error = "the photo couldn't be read"
		return null
	return img


## Every face landmark MediaPipe finds in the last picked photo, in its
## pixels; empty if there is no face or it failed (see last_error).
func find_face() -> PackedVector2Array:
	last_error = ""
	_api.find(_reply_cb)
	var r: Array = await _replied
	var out := PackedVector2Array()
	if not r[0]:
		last_error = str(r[1])
		return out
	var info: Variant = JSON.parse_string(str(r[1]))
	if not info is Dictionary:
		return out
	var flat: Array = info.get("points", [])
	for i in flat.size() / 2:
		out.append(Vector2(float(flat[2 * i]), float(flat[2 * i + 1])))
	return out


## Lets the browser drop the photo.
func forget() -> void:
	if _api != null:
		_api.clear()


func _on_reply(args: Array) -> void:
	_replied.emit(bool(args[0]), args[1] if args.size() > 1 else null)
