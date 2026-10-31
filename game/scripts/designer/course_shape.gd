class_name CourseShape
extends RefCounted
## One painted area of a designed course: a closed outline of control points
## (x, z) and the surface inside it. The outline is drawn through the points
## as a smooth closed curve, the way Links-style designers draw fairways and
## greens with splines.

const SUBDIVISIONS := 6  ## curve points per control-point segment

var surface: int = Surface.Type.FAIRWAY
var points := PackedVector2Array()

var _outline := PackedVector2Array()
var _bounds := Rect2()
var _dirty := true


func _init(p_surface: int = Surface.Type.FAIRWAY, p_points := PackedVector2Array()) -> void:
	surface = p_surface
	points = p_points


## Call after changing `points`.
func changed() -> void:
	_dirty = true


## The smoothed closed outline (Catmull-Rom through the control points).
func outline() -> PackedVector2Array:
	if _dirty:
		_rebuild()
	return _outline


func bounds() -> Rect2:
	if _dirty:
		_rebuild()
	return _bounds


func is_valid() -> bool:
	return points.size() >= 3


func contains(p: Vector2) -> bool:
	if not is_valid() or not bounds().has_point(p):
		return false
	return Geometry2D.is_point_in_polygon(p, outline())


## Distance from `p` to the outline: negative inside, positive outside.
func signed_distance(p: Vector2) -> float:
	var poly := outline()
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return -best if Geometry2D.is_point_in_polygon(p, poly) else best


## The index of the control point nearest `p` within `radius`, or -1.
func nearest_point(p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in points.size():
		var d := points[i].distance_to(p)
		if d <= best_d:
			best = i
			best_d = d
	return best


## Inserts a control point on the outline segment nearest `p`.
func insert_point(p: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
		if d < best_d:
			best_d = d
			best = i + 1
	points.insert(best, p)
	changed()
	return best


func translate(by: Vector2) -> void:
	for i in points.size():
		points[i] += by
	changed()


func area() -> float:
	var poly := outline()
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


func to_dict() -> Dictionary:
	var flat: Array[float] = []
	for p in points:
		flat.append(snappedf(p.x, 0.01))
		flat.append(snappedf(p.y, 0.01))
	return {"surface": Surface.name_of(surface), "points": flat}


static func from_dict(d: Dictionary) -> CourseShape:
	var s := CourseShape.new(maxi(0, Surface.NAMES.find(str(d.get("surface", "Fairway")))))
	var flat: Array = d.get("points", [])
	for i in range(0, flat.size() - 1, 2):
		s.points.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return s


## An oval of control points, for shapes placed with one click.
static func oval(p_surface: int, centre: Vector2, radii: Vector2, angle := 0.0, count := 8) -> CourseShape:
	var pts := PackedVector2Array()
	for i in count:
		var a := TAU * i / count
		pts.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(angle))
	return CourseShape.new(p_surface, pts)


## A strip of the given width along a polyline, for fairways.
static func strip(p_surface: int, line: PackedVector2Array, width: float) -> CourseShape:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in line.size():
		var prev := line[maxi(i - 1, 0)]
		var next := line[mini(i + 1, line.size() - 1)]
		var side := (next - prev).normalized().orthogonal() * width * 0.5
		left.append(line[i] + side)
		right.append(line[i] - side)
	right.reverse()
	return CourseShape.new(p_surface, left + right)


func _rebuild() -> void:
	_dirty = false
	_outline = PackedVector2Array()
	var n := points.size()
	if n < 3:
		_bounds = Rect2()
		return
	for i in n:
		var p0 := points[(i - 1 + n) % n]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p3 := points[(i + 2) % n]
		for k in SUBDIVISIONS:
			var t := float(k) / SUBDIVISIONS
			var t2 := t * t
			var t3 := t2 * t
			_outline.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	_bounds = Rect2(_outline[0], Vector2.ZERO)
	for p in _outline:
		_bounds = _bounds.expand(p)
