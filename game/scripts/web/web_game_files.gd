class_name WebGameFiles
extends RefCounted
## The browser build's access to the player's own game files, through
## game/web/game_files.js. The player picks their disc images (or a game
## folder) once; the browser keeps them in IndexedDB on their machine, and
## nothing is uploaded. Files are then copied into the in-memory filesystem
## under ROOT, where GameFolder and the format readers find them as usual.

signal progress(file_name: String, done: int, total: int)
signal _replied(ok: bool, value: Variant)

const ROOT := "/tmp/links2003"
const SCRIPT_PATH := "res://web/game_files.js"
const CHUNK := 8 * 1024 * 1024
## Files bigger than this wait until something asks for them.
const EAGER_LIMIT := 40 * 1024 * 1024
## Read by the course loader for every course, so always copied at startup:
## the executables hold the course key, the .lib the standard ground textures.
const ALWAYS := ["linksm_1.exe", "linksmmiii.exe", "stdter_1.lib", "stdterrain.lib"]

var last_error := ""
var _api: JavaScriptObject
var _reply_cb: JavaScriptObject
var _progress_cb: JavaScriptObject


static func is_supported() -> bool:
	return OS.has_feature("web")


func _init() -> void:
	if not is_supported():
		return
	JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)
	_api = JavaScriptBridge.get_interface("olFiles")
	_reply_cb = JavaScriptBridge.create_callback(_on_reply)
	_progress_cb = JavaScriptBridge.create_callback(_on_progress)


## Opens the browser's file picker (disc images, or a folder when `folder`
## is true) and stores what the player picks. Returns how many game files
## are now stored, 0 if the picker was cancelled, or -1 on error.
func pick_and_import(folder: bool) -> int:
	_api.pick(folder, _progress_cb, _reply_cb)
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return -1
	return int(r[1])


## Opens the browser's file picker for add-on courses (a course's .zip
## download, or .crz and companion files) and stores them under Courses/.
## Returns how many game files are now stored, 0 if cancelled, -1 on error.
func pick_courses() -> int:
	_api.pickCourses(_progress_cb, _reply_cb)
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return -1
	return int(r[1])


## Stored files as {relative path: size}. Empty when nothing is imported.
func stored_files() -> Dictionary:
	_api.list(_reply_cb)
	var r: Array = await _replied
	var out := {}
	if not r[0]:
		last_error = str(r[1])
		return out
	var parsed: Variant = JSON.parse_string(str(r[1]))
	if parsed is Array:
		for entry: Variant in parsed:
			out[str(entry[0])] = int(entry[1])
	return out


## Copies the files the game reads at startup into ROOT: everything but the
## courses, the large audio folders and anything over EAGER_LIMIT, which
## copy_file() fetches on demand. Returns false if a copy failed.
func copy_startup_files(files: Dictionary) -> bool:
	var wanted: Array[String] = []
	var total := 0
	for rel: String in files:
		if is_startup_file(rel, files[rel]):
			wanted.append(rel)
			total += int(files[rel])
	var done := 0
	for rel in wanted:
		progress.emit(rel, done, total)
		if not await copy_file(rel, files[rel]):
			return false
		done += int(files[rel])
	progress.emit("", total, total)
	return true


static func is_startup_file(rel: String, size: int) -> bool:
	var lower := rel.to_lower()
	if lower.get_file() in ALWAYS:
		return true
	for lazy in ["courses/", "sounds/", "polyani/"]:
		if lower.begins_with(lazy):
			return false
	return size <= EAGER_LIMIT


## Copies one stored file into ROOT, unless it is already there.
func copy_file(rel: String, size: int) -> bool:
	var path := ROOT.path_join(rel)
	if FileAccess.file_exists(path) and FileAccess.open(path, FileAccess.READ).get_length() == size:
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s" % path
		return false
	var offset := 0
	while offset < size:
		var n := mini(CHUNK, size - offset)
		_api.read(rel, offset, n, _reply_cb)
		var r: Array = await _replied
		if not r[0]:
			last_error = str(r[1])
			f.close()
			return false
		f.store_buffer(JavaScriptBridge.js_buffer_to_packed_byte_array(r[1]))
		offset += n
	f.close()
	return true


## Removes every imported file from the browser's storage.
func forget() -> void:
	_api.forget(_reply_cb)
	await _replied


func _on_reply(args: Array) -> void:
	_replied.emit(bool(args[0]), args[1] if args.size() > 1 else null)


func _on_progress(args: Array) -> void:
	progress.emit(str(args[0]), int(args[1]), int(args[2]))
