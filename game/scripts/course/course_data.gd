class_name CourseData
extends RefCounted
## A loaded course.

var course_name := ""
var holes: Array[HoleData] = []
## Trees, plants, 3D objects and spectators read from the course file (null
## for courses that have none; their holes may list objects instead).
var objects: CourseObjects
## The course's horizon panorama (hills and trees round the course), or null.
var horizon: Image
## The cloud sky the course asks for: skyNN.btc in PANSKY.LIB (1 to 12), or
## 0 for none (CourseBackdrop then uses its default).
var sky := 0
## Reads a named entry from the course file (for its ambient sounds); an
## empty Callable for courses without one.
var read_entry: Callable


func pars() -> Array[int]:
	var out: Array[int] = []
	for h in holes:
		out.append(h.par)
	return out
