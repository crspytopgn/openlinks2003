class_name GameFolder
extends RefCounted
## Finds the player's own Links 2003 files. Nothing from the original game
## ships with this project (docs/clean-room.md).
##
## The folder comes from, in order:
##   0. override_path (the browser build's in-memory copy)
##   1. the command line: --links-dir=/path/to/links2003
##   2. the LINKS2003_DIR environment variable
##   3. user://settings.cfg, key "folder" in section [game], which the boot
##      screen's folder picker writes
## It can be the install folder, the GAME folder on the CD, or a folder of
## extracted files; file names are matched without regard to case.

const SETTINGS_PATH := "user://settings.cfg"


## Set by the boot screen: a folder the player picked this session, or the
## in-memory copy of their files in the browser build. Wins over the rest.
static var override_path := ""


static func configured_path() -> String:
	if not override_path.is_empty():
		return override_path
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--links-dir="):
			return arg.trim_prefix("--links-dir=")
	var env := OS.get_environment("LINKS2003_DIR")
	if not env.is_empty():
		return env
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return str(cfg.get_value("game", "folder", ""))
	return ""


## A value from [game] in user://settings.cfg, or `fallback` if unset.
static func setting(key: String, fallback: String = "") -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return str(cfg.get_value("game", key, fallback))
	return fallback


## Full path of the first of `names` found in the folder or its GAME
## subfolder, or "" if none is there.
static func find_file(names: PackedStringArray) -> String:
	for dir in _search_dirs():
		for file_name in names:
			var found := _find_entry(dir, file_name, false)
			if not found.is_empty():
				return found
	return ""


## Full paths of the files in a subfolder (such as "POLYANI") of the folder
## or of its GAME subfolder, sorted by name.
static func list_files(subdir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for dir in _search_dirs():
		var sub := _find_entry(dir, subdir, true)
		if sub.is_empty():
			continue
		var files := DirAccess.get_files_at(sub)
		files.sort()
		for f in files:
			result.append(sub.path_join(f))
		break
	return result


static func _search_dirs() -> Array[String]:
	var dirs: Array[String] = []
	var root := configured_path()
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return dirs
	dirs.append(root)
	var game := _find_entry(root, "game", true)
	if not game.is_empty():
		dirs.append(game)
	return dirs


static func _find_entry(dir_path: String, entry_name: String, want_dir: bool) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	var entries := dir.get_directories() if want_dir else dir.get_files()
	for entry in entries:
		if entry.to_lower() == entry_name.to_lower():
			return dir_path.path_join(entry)
	return ""
