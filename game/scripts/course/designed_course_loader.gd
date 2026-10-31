class_name DesignedCourseLoader
extends CourseLoader
## Plays courses made in the course designer (`.olc`, DesignedCourse).


func can_load(path: String) -> bool:
	return path.get_extension().to_lower() == DesignedCourse.EXTENSION


func load_course(path: String) -> CourseData:
	var designed := DesignedCourse.load_file(path)
	if designed == null:
		push_warning("Not a designed course: %s" % path)
		return null
	var course := designed.to_course_data()
	if course.holes.is_empty():
		push_warning("%s has no holes with a tee yet" % path)
		return null
	return course
