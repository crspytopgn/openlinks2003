class_name PlaceholderCourseLoader
extends CourseLoader
## The built-in course, Kettle Hollow: a parkland nine laid on real ground
## (lidar of glacial farmland), so a round can be played before any
## original course can be read. Built by tools/homecourse/ into a designer
## course file (see docs/home-course.md), so it plays through the same
## DesignedTerrain as courses made in the designer and can be opened there.

const PATH := "placeholder://openlinks-nine"
const FILE := "res://assets/courses/home.olc"
const NAME := "Kettle Hollow"

static var _parsed: DesignedCourse


func can_load(path: String) -> bool:
	return path == PATH or path.is_empty()


func load_course(_path: String) -> CourseData:
	var designed := source()
	if designed == null:
		push_error("The built-in course is missing: %s" % FILE)
		return CourseData.new()
	return designed.to_course_data()


## The built-in course as a designer course, parsed once.
static func source() -> DesignedCourse:
	if _parsed == null:
		_parsed = DesignedCourse.load_file(FILE)
	return _parsed
