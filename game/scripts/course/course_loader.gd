class_name CourseLoader
extends RefCounted
## Turns a course on disk into CourseData. The .CRZ decoder plugs in here:
## subclass this, return true from can_load() for the paths it understands,
## and register it with AssetProviders.register_course_loader().


func can_load(_path: String) -> bool:
	return false


## Returns null if the course cannot be read.
func load_course(_path: String) -> CourseData:
	return null
