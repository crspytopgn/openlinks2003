class_name WebGameFiles
extends RefCounted
## The browser build's access to the player's own game files, through
## game/web/game_files.js. The player picks their disc images (or a game
## folder); the script indexes them without copying anything, and nothing is
## uploaded. Chrome and Edge remember the picked files between visits; other
## browsers ask for them again. The files the game reads are copied into the
## in-memory filesystem under ROOT, where GameFolder and the format readers
## find them as usual: a small startup set (see startup_files()) and the
## chosen course.

signal progress(file_name: String, done: int, total: int)
signal _replied(ok: bool, value: Variant)

const ROOT := "/tmp/links2003"
const SCRIPT_PATH := "res://web/game_files.js"
const CHUNK := 8 * 1024 * 1024
## Copied at startup, by file name in either spelling: the object catalog,
## the sound effects, the executables (they hold the course key) and the
## standard ground textures the course loader reads for every course.
const STARTUP := [
	"object.lib", "predefined.ssf", "predef_1.ssf", "linksm_1.exe", "linksmmiii.exe", "stdter_1.lib", "stdterrain.lib",
]

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


## True when the browser remembers the picked files between visits.
func remembers() -> bool:
	return bool(_api.remembers)


## "ready" (files picked this visit or remembered and readable), "reconnect"
## (remembered, but the browser wants the player's OK: call reconnect() from
## a button) or "empty". "error" sets last_error.
func state() -> String:
	_api.state(_reply_cb)
	return await _string_reply()


## Asks the browser for access to the remembered files again. Returns
## "ready", "denied", "empty" or "error".
func reconnect() -> String:
	_api.reconnect(_reply_cb)
	return await _string_reply()


## Opens the browser's file picker (disc images, or a folder when `folder`
## is true) and indexes what the player picks. Returns how many game files
## were found, 0 if the picker was cancelled, or -1 on error.
func pick_and_import(folder: bool) -> int:
	_api.pick(folder, _progress_cb, _reply_cb)
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return -1
	return int(r[1])


## Opens the browser's file picker for add-on courses (a course's .zip
## download, or .crz and companion files) and keeps them in the browser
## under Courses/. Returns how many course files are now added, 0 if the
## picker was cancelled, or -1 on error.
func pick_courses() -> int:
	_api.pickCourses(_progress_cb, _reply_cb)
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return -1
	return int(r[1])


## The picked game files as {relative path: size}.
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


## Copies the files the game reads before a round into ROOT (see
## startup_files()), then the objects that stand in for the placeholder
## course's trees. Returns false if a copy failed.
func copy_startup_files(files: Dictionary) -> bool:
	if not await copy_files(files, startup_files(files, GameFolder.setting("golfer"))):
		return false
	var lib := DecodedObjectLibrary.open(ROOT)
	if lib == null:
		return true
	return await copy_files(files, object_files(files, lib, ObjectLibraryChain.tree_aliases(lib).values()))


## Copies `wanted` (relative paths from `files`) into ROOT with progress.
func copy_files(files: Dictionary, wanted: Array[String]) -> bool:
	var total := 0
	for rel in wanted:
		total += int(files[rel])
	var done := 0
	for rel in wanted:
		progress.emit(rel, done, total)
		if not await copy_file(rel, files[rel]):
			return false
		done += int(files[rel])
	progress.emit("", total, total)
	return true


## The files the game reads at startup: the STARTUP names and one golfer
## (`golfer`, an archive name such as ERIC.L3, or else the first one).
## Everything else stays in the player's images until asked for.
static func startup_files(files: Dictionary, golfer: String) -> Array[String]:
	var out: Array[String] = []
	var golfers: Array[String] = []
	for rel: String in files:
		var lower := rel.to_lower()
		if lower.get_file() in STARTUP and lower.count("/") == 0:
			out.append(rel)
		elif lower.begins_with("polyani/") and lower.get_extension() == "l3" and lower.get_file() != "clubs.l3":
			golfers.append(rel)
	golfers.sort()
	var chosen := "" if golfers.is_empty() else golfers[0]
	for rel in golfers:
		if rel.get_file().to_lower() == golfer.to_lower():
			chosen = rel
	if not chosen.is_empty():
		out.append(chosen)
	return out


## The files in `files` that make up the given library objects (ids or
## catalog names): the .btx of a billboard, the .XYZ and .cmf of a model.
static func object_files(files: Dictionary, lib: DecodedObjectLibrary, ids: Array) -> Array[String]:
	var by_lower := {}
	for rel: String in files:
		by_lower[rel.to_lower()] = rel
	var out: Array[String] = []
	for id: Variant in ids:
		var o := lib.find(str(id))
		if o.is_empty():
			continue
		var path := ("object/" + str(o.path)).to_lower()
		var parts := [path]
		if o.kind == ObjectCatalog.KIND_MODEL:
			parts = [path.get_basename() + ".xyz", path.get_basename() + ".cmf"]
		for p: String in parts:
			if by_lower.has(p) and not out.has(by_lower[p]):
				out.append(by_lower[p])
	return out


## Copies one picked file into ROOT, unless it is already there.
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


## Forgets the picked files.
func forget() -> void:
	_api.forget(_reply_cb)
	await _replied


func _string_reply() -> String:
	var r: Array = await _replied
	if not r[0]:
		last_error = str(r[1])
		return "error"
	return str(r[1])


func _on_reply(args: Array) -> void:
	_replied.emit(bool(args[0]), args[1] if args.size() > 1 else null)


func _on_progress(args: Array) -> void:
	progress.emit(str(args[0]), int(args[1]), int(args[2]))
