class_name CourseData
extends RefCounted
## A loaded course.

var course_name := ""
var holes: Array[HoleData] = []


func pars() -> Array[int]:
	var out: Array[int] = []
	for h in holes:
		out.append(h.par)
	return out
