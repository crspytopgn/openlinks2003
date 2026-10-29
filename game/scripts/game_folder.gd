class_name GameFolder
extends RefCounted
## Finds the player's own Links 2003 files. Nothing from the original game
## ships with this project (docs/clean-room.md).
##
## Until the folder picker exists, the folder comes from, in order:
##   1. the command line: --links-dir=/path/to/links2003
##   2. the LINKS2003_DIR environment variable
##   3. user://settings.cfg, key "folder" in section [game]
## It can be the install folder, the GAME folder on the CD, or a folder of
## extracted files; file names are matched without regard to case.

const SETTINGS_PATH := "user://settings.cfg"


static func configured_path() -> String:
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


## Full path of the first of `names` found in the folder or its GAME
## subfolder, or "" if none is there.
static func find_file(names: PackedStringArray) -> String:
	var root := configured_path()
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return ""
	var dirs := [root]
	var game := _find_entry(root, "game", true)
	if not game.is_empty():
		dirs.append(game)
	for dir in dirs:
		for file_name in names:
			var found := _find_entry(dir, file_name, false)
			if not found.is_empty():
				return found
	return ""


static func _find_entry(dir_path: String, entry_name: String, want_dir: bool) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	var entries := dir.get_directories() if want_dir else dir.get_files()
	for entry in entries:
		if entry.to_lower() == entry_name.to_lower():
			return dir_path.path_join(entry)
	return ""
