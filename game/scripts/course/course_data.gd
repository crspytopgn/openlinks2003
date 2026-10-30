class_name CourseData
extends RefCounted
## A loaded course.

var course_name := ""
var holes: Array[HoleData] = []
## Trees, plants, 3D objects and spectators read from the course file (null
## for courses that have none; their holes may list objects instead).
var objects: CourseObjects


func pars() -> Array[int]:
	var out: Array[int] = []
	for h in holes:
		out.append(h.par)
	return out
