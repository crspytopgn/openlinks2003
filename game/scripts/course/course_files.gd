class_name CourseFiles
extends RefCounted
## Finds the course files (.crz, .rng) in the player's game folder, for the
## course picker. A course decoder registered with AssetProviders turns the
## chosen path into CourseData.

const EXTENSIONS := ["crz", "rng"]
## Extra files that travel with a course (shadows, preview).
const COMPANIONS := ["sha", "tip"]


## Course file paths in `folder`'s Courses (or GAME/Courses) folder, sorted.
static func in_folder(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	if folder.is_empty():
		return out
	for dir_path in [folder, folder.path_join("GAME")]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			if sub.to_lower() != "courses":
				continue
			var courses := DirAccess.open(dir_path.path_join(sub))
			for f in courses.get_files():
				if f.get_extension().to_lower() in EXTENSIONS:
					out.append(dir_path.path_join(sub).path_join(f))
	out.sort()
	return out


## Course entries among stored relative paths (the browser build's list).
static func in_list(paths: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for p: String in paths:
		var lower := p.to_lower()
		if lower.begins_with("courses/") and lower.get_extension() in EXTENSIONS:
			out.append(p)
	out.sort()
	return out


## "Cabo.crz" -> "Cabo"; courses from the course designer are marked.
static func display_name(path: String) -> String:
	var name := path.get_file().get_basename()
	if path.get_extension().to_lower() == DesignedCourse.EXTENSION:
		return name + " (your design)"
	return name
