class_name CaseInsensitiveDir
extends RefCounted
## A folder of the player's Links 2003 files (an install, or a folder made with
## `tools/cdimage/cdimage.py install`). File names in the game's data use
## any case and Windows separators, so lookups ignore case.

var root: String


func _init(p_root: String) -> void:
	root = p_root.trim_suffix("/").trim_suffix("\\")


## Returns the real path of `relative` ("Object\\Tall Trees\\X.btx"), or ""
## if it does not exist.
func find(relative: String) -> String:
	var path := root
	for part in relative.replace("\\", "/").split("/", false):
		var dir := DirAccess.open(path)
		if dir == null:
			return ""
		var match_name := ""
		if dir.file_exists(part) or dir.dir_exists(part):
			match_name = part
		else:
			var wanted := part.to_lower()
			for entry in dir.get_files() + dir.get_directories():
				if entry.to_lower() == wanted:
					match_name = entry
					break
		if match_name.is_empty():
			return ""
		path = path.path_join(match_name)
	return path


func read(relative: String) -> PackedByteArray:
	var path := find(relative)
	if path.is_empty():
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)
