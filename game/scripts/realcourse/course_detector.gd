class_name CourseDetector
extends RefCounted
## Finds a hole's real green and bunkers where the map doesn't have them,
## for CourseGuesser:
##
## - in the aerial photo, a green is the patch of evenly coloured mown
##   grass round the pin, and a bunker a compact patch of bright sand;
## - in lidar heights, a bunker is a hollow of a few metres beside the
##   green or the fairway.
##
## Outlines come back as course points (x, z), simplified, ready for a
## CourseShape. An empty result means nothing convincing was found.

const GREEN_REACH := 26.0  ## metres from the pin a green may reach
const GREEN_AREA := Vector2(150.0, 1200.0)  ## m2, smallest and largest
const GREEN_STEP := 0.005  ## colour distances tried, in steps of this
const GREEN_STEPS := 18
const SAND_AREA := Vector2(15.0, 600.0)  ## m2
const SAND_THICK := 3.0  ## metres; thinner patches are paths and tracks
const SAND_MAX_SIZE := 50.0  ## metres, longest side
const HOLLOW_DEPTH := 0.3  ## metres below the ground round it
const HOLLOW_CELLS := Vector2i(3, 120)  ## 2 m cells, smallest and largest


## Metres per pixel of a course photo across and down.
static func _res(photo: Image, area: Rect2) -> Vector2:
	return Vector2(area.size.x / photo.get_width(), area.size.y / photo.get_height())


## Photo pixel of a course point (the photo's first pixel is the
## north-west, +x +z, corner).
static func _px(photo: Image, area: Rect2, p: Vector2) -> Vector2i:
	var r := _res(photo, area)
	return Vector2i(floori((area.end.x - p.x) / r.x), floori((area.end.y - p.y) / r.y))


static func _pt(photo: Image, area: Rect2, q: Vector2i) -> Vector2:
	var r := _res(photo, area)
	return Vector2(area.end.x - (q.x + 0.5) * r.x, area.end.y - (q.y + 0.5) * r.y)


## The green round `pin` in the photo: the evenly coloured grass that
## grows out from the pin, with the loosest colour match that doesn't yet
## leak out to GREEN_REACH (into the fringe and fairway, which are much
## the same colour). Empty if none fits.
static func find_green(photo: Image, area: Rect2, pin: Vector2) -> PackedVector2Array:
	if photo == null:
		return PackedVector2Array()
	var res := _res(photo, area)
	var px_area := res.x * res.y
	var seed_px := _px(photo, area, pin)
	var w := photo.get_width()
	var h := photo.get_height()
	if seed_px.x < 1 or seed_px.y < 1 or seed_px.x >= w - 1 or seed_px.y >= h - 1:
		return PackedVector2Array()
	var seed_col := Color(0, 0, 0)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			seed_col += photo.get_pixelv(seed_px + Vector2i(di, dj)) / 9.0
	# Mown grass: green the strongest channel. Not on sand, water or a path.
	if seed_col.g <= seed_col.r or seed_col.g <= seed_col.b or seed_col.get_luminance() < 0.12:
		return PackedVector2Array()
	var reach := ceili(GREEN_REACH / minf(res.x, res.y))
	var best := PackedVector2Array()
	for k in range(3, GREEN_STEPS + 1):
		var step := k * GREEN_STEP
		var region := _grow(photo, seed_px, reach, func(c: Color) -> bool:
			return Vector3(c.r - seed_col.r, c.g - seed_col.g, c.b - seed_col.b).length() < step)
		var cells: Array = region["cells"]
		var size := cells.size() * px_area
		if int(region["edge"]) > 0 or size > GREEN_AREA.y:
			break
		if size >= GREEN_AREA.x:
			best = _outline(photo, area, cells)
	return best


## Bunkers (bright sand) in the photo within `radius` of `centre`.
static func find_sand(photo: Image, area: Rect2, centre: Vector2, radius: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if photo == null:
		return out
	var res := _res(photo, area)
	var px_area := res.x * res.y
	var c0 := _px(photo, area, centre)
	var reach := ceili(radius / minf(res.x, res.y))
	var w := photo.get_width()
	var h := photo.get_height()
	var seen := {}
	for j in range(maxi(c0.y - reach, 0), mini(c0.y + reach + 1, h)):
		for i in range(maxi(c0.x - reach, 0), mini(c0.x + reach + 1, w)):
			var q := Vector2i(i, j)
			if seen.has(q) or (q - c0).length() > reach or not is_sand(photo.get_pixelv(q)):
				continue
			var region := _grow(photo, q, reach * 2, CourseDetector.is_sand)
			var cells: Array = region["cells"]
			for k in cells:
				seen[k] = true
			var size := cells.size() * px_area
			if size < SAND_AREA.x or size > SAND_AREA.y:
				continue
			var ring := _outline(photo, area, cells)
			var b := Rect2(ring[0], Vector2.ZERO)
			for p in ring:
				b = b.expand(p)
			# A bunker is compact; paths, roads and roofs are long or square.
			var longest := maxf(b.size.x, b.size.y)
			if longest > SAND_MAX_SIZE or size < absf(_area_of(ring)) * 0.45 or size / longest < SAND_THICK:
				continue
			out.append(ring)
	return out


## Bright, whitish or pale yellow: sand rather than grass, trees, dead
## bracken or water.
static func is_sand(c: Color) -> bool:
	var lum := c.get_luminance()
	var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
	return lum > 0.6 and c.r >= c.g * 0.95 and c.g >= c.b * 0.95 and sat < 0.22


## Bunkers as hollows in the course's own heights (2 m grid; use only when
## they came from lidar): cells a little below the mean of the ground
## round them, within `radius` of `centre`.
static func find_hollows(c: DesignedCourse, centre: Vector2, radius: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var cell := DesignedCourse.CELL
	var c0 := c.cell_of(centre)
	var reach := ceili(radius / cell)
	var deep := {}
	for j in range(maxi(c0.y - reach, 4), mini(c0.y + reach + 1, c.rows - 4)):
		for i in range(maxi(c0.x - reach, 4), mini(c0.x + reach + 1, c.cols - 4)):
			if Vector2(i - c0.x, j - c0.y).length() > reach:
				continue
			var sum := 0.0
			var n := 0
			# The ring of ground 6 to 8 m out.
			for dj in range(-4, 5):
				for di in range(-4, 5):
					if maxi(absi(di), absi(dj)) >= 3:
						sum += c.heights[(j + dj) * c.cols + i + di]
						n += 1
			if sum / n - c.heights[j * c.cols + i] > HOLLOW_DEPTH:
				deep[Vector2i(i, j)] = true
	var seen := {}
	for q: Vector2i in deep:
		if seen.has(q):
			continue
		var cells: Array[Vector2i] = []
		var stack: Array[Vector2i] = [q]
		seen[q] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			cells.append(p)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nq: Vector2i = p + d
				if deep.has(nq) and not seen.has(nq):
					seen[nq] = true
					stack.append(nq)
		if cells.size() < HOLLOW_CELLS.x or cells.size() > HOLLOW_CELLS.y:
			continue
		var pts := PackedVector2Array()
		for p in cells:
			var s := c.sample_pos(p.x, p.y)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(s + corner * cell * 0.5)
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		if hull.size() >= 3:
			out.append(RealCourseBuilder.simplify_ring(hull, 0.6))
	return out


## Pixels 4-connected to `start` that pass `ok`, at most `reach` pixels
## away: {"cells": [Vector2i], "edge": pixels at the reach limit}.
static func _grow(photo: Image, start: Vector2i, reach: int, ok: Callable) -> Dictionary:
	var w := photo.get_width()
	var h := photo.get_height()
	var cells: Array[Vector2i] = []
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	var edge := 0
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		cells.append(p)
		if (p - start).length() >= reach - 1:
			edge += 1
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen.has(q):
				continue
			seen[q] = true
			if ok.call(photo.get_pixelv(q)):
				stack.append(q)
	return {"cells": cells, "edge": edge}


## A simplified outline round photo pixels (their convex hull).
static func _outline(photo: Image, area: Rect2, cells: Array) -> PackedVector2Array:
	var r := _res(photo, area) * 0.5
	var pts := PackedVector2Array()
	for q: Vector2i in cells:
		var p := _pt(photo, area, q)
		pts.append_array([p + Vector2(-r.x, -r.y), p + Vector2(r.x, -r.y), p + Vector2(r.x, r.y), p + Vector2(-r.x, r.y)])
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return RealCourseBuilder.simplify_ring(hull, 0.5) if hull.size() >= 3 else PackedVector2Array()


static func _area_of(ring: PackedVector2Array) -> float:
	var a := 0.0
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
