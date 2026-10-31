class_name CourseGuesser
extends RefCounted
## Fills in what a real course's map leaves out. Many clubs on
## OpenStreetMap have their hole lines but not every green, tee, fairway or
## bunker. For each hole, whatever is missing is drawn at a typical size
## along the line of play:
##
## - a green round the pin (about 500 to 650 m2 by par, longer along the
##   approach than across);
## - a tee box at each tee;
## - on par 4s and 5s, a fairway from the landing area to the green, about
##   34 m wide, narrowing at its ends;
## - greenside bunkers either side of the green, and on par 4s and 5s a
##   fairway bunker at the driving distance.
##
## Before guessing a green, fairway or bunkers it looks for the real ones
## in the aerial photo (CourseDetector), in a close-up round the green when
## there is one. Found shapes have the meta "detected". (Lidar hollows were
## tried for bunkers and were wrong two times in three, worse than a
## marked guess, so heights aren't used.)
##
## Shapes it adds are marked `guessed`, so the designer can tell them from
## mapped ones. Holes already mapped in full are left as they are.

const GREEN_AREA := {3: 520.0, 4: 600.0, 5: 650.0}  ## m2
const GREEN_LONG := 1.25  ## length along the approach over width across
const TEE_HALF := Vector2(5.0, 8.0)  ## half width across, half length along
const FAIRWAY_WIDTH := 34.0
const FAIRWAY_STEP := 25.0  ## metres between fairway control points
const FAIRWAY_START := 140.0  ## where it begins at most, from the back tee
const DRIVE := 230.0  ## fairway bunker distance from the back tee


## Adds the missing shapes to `c` and returns them.
static func fill(c: DesignedCourse, seed_value := 1, photo: Image = null, details: Array[Dictionary] = []) -> Array[CourseShape]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var added: Array[CourseShape] = []
	for n in c.holes.size():
		var h := c.holes[n]
		if h.tees.is_empty():
			continue
		var line := PackedVector2Array([h.tees[0]])
		line.append_array(h.route)
		line.append(h.pin)
		var length := _length(line)
		if length < 40.0:
			continue
		var par := clampi(h.par, 3, 5)
		var approach := (h.pin - _point_at(line, maxf(length - 60.0, 0.0))).normalized()
		if approach == Vector2.ZERO:
			approach = Vector2(0, 1)

		# Round the green, a close-up photo if there is one.
		var near_photo := photo
		var near_area := c.area
		for d in details:
			if (d["area"] as Rect2).grow(-45.0).has_point(h.pin):
				near_photo = d["image"]
				near_area = d["area"]
				break

		# Green.
		var radius := 0.0
		var green := _find(c, Surface.Type.GREEN, h.pin, 20.0)
		if green == null:
			var ring := CourseDetector.find_green(near_photo, near_area, h.pin)
			if ring.size() >= 3:
				green = CourseShape.new(Surface.Type.GREEN, ring)
				_add(c, added, green, true)
		if green == null:
			var a_m2: float = GREEN_AREA[par] * rng.randf_range(0.85, 1.15)
			var along := sqrt(a_m2 * GREEN_LONG / PI)
			var across := a_m2 / (PI * along)
			# The pin sits a little off the middle, as on most greens.
			var centre := h.pin - approach * rng.randf_range(-3.0, 3.0)
			green = _ellipse(Surface.Type.GREEN, centre, approach, along, across, 10, 0.08, rng)
			_add(c, added, green)
			radius = (along + across) * 0.5
		else:
			var b := green.bounds()
			radius = (b.size.x + b.size.y) * 0.25

		# Tees.
		var first_dir := (line[1] - line[0]).normalized()
		for t in h.tees:
			if _find(c, Surface.Type.TEE, t, 6.0) == null:
				_add(c, added, _box(Surface.Type.TEE, t, first_dir, TEE_HALF))

		# Fairway: the real one in the photo, else a typical one.
		if par >= 4 and not _has_fairway(c, line, length):
			var stop := length - radius - 4.0
			var ring := CourseDetector.find_fairway(photo, c.area, line, minf(60.0, length * 0.2), stop)
			if ring.size() >= 3:
				_add(c, added, CourseShape.new(Surface.Type.FAIRWAY, ring), true)
			else:
				var start := minf(length * (0.3 if par == 4 else 0.22), FAIRWAY_START)
				if stop - start > 60.0:
					_add(c, added, _fairway(line, start, stop, FAIRWAY_WIDTH * rng.randf_range(0.9, 1.1), rng))

		# Bunkers only on holes with none mapped: a mapper who drew one
		# bunker of a hole drew them all.
		var mapped_sand := _sand_along(c, line)
		# Real bunkers by the green and at the driving distance.
		if not mapped_sand:
			var found: Array[PackedVector2Array] = []
			var spots := [[h.pin, radius + 22.0]]
			if par >= 4 and length > DRIVE + 90.0:
				spots.append([_point_at(line, DRIVE), 45.0])
			for k in spots.size():
				var spot: Array = spots[k]
				for ring in CourseDetector.find_sand(near_photo if k == 0 else photo, near_area if k == 0 else c.area, spot[0], spot[1]):
					var mid := _ring_centre(ring)
					if (green == null or not Geometry2D.is_point_in_polygon(mid, green.outline())) and not _on_path(c, mid):
						found.append(ring)
			for ring in found:
				_add(c, added, CourseShape.new(Surface.Type.SAND, ring), true)
			mapped_sand = not found.is_empty()
		# Greenside bunkers: one either side, sometimes one behind.
		if not mapped_sand:
			var sides := [-1.0, 1.0]
			if par == 3 or rng.randf() < 0.3:
				sides.append(0.0)
			for side: float in sides:
				var ang := deg_to_rad(rng.randf_range(55.0, 85.0)) * side if side != 0.0 else PI + deg_to_rad(rng.randf_range(-25.0, 25.0))
				var out := approach.rotated(ang)
				var half_long := rng.randf_range(6.0, 9.0)
				var half_short := rng.randf_range(3.0, 4.5)
				var centre := h.pin + out * (radius + half_short + 1.5)
				_add(c, added, _ellipse(Surface.Type.SAND, centre, out.orthogonal(), half_long, half_short, 8, 0.12, rng))

		# A fairway bunker at the driving distance, on alternate sides.
		if par >= 4 and length > DRIVE + 90.0 and not mapped_sand:
			var at := _point_at(line, DRIVE)
			if not _has_sand(c, at, 40.0):
				var dir := _dir_at(line, DRIVE)
				var side := 1.0 if n % 2 == 0 else -1.0
				var centre := at + dir.orthogonal() * side * (FAIRWAY_WIDTH * 0.5 + 1.0)
				_add(c, added, _ellipse(Surface.Type.SAND, centre, dir, rng.randf_range(9.0, 13.0), rng.randf_range(3.5, 5.0), 8, 0.1, rng))
	return added


static func _add(c: DesignedCourse, added: Array[CourseShape], s: CourseShape, detected := false) -> void:
	s.guessed = true
	if detected:
		s.set_meta("detected", true)
	c.shapes.append(s)
	added.append(s)


## A shape of `surface` at or within `radius` of a point, or null.
static func _find(c: DesignedCourse, surface: int, p: Vector2, radius: float) -> CourseShape:
	for s in c.shapes:
		if s.surface != surface or not s.bounds().grow(radius).has_point(p):
			continue
		var ring := s.outline()
		if Geometry2D.is_point_in_polygon(p, ring):
			return s
		for k in ring.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, ring[k], ring[(k + 1) % ring.size()])) < radius:
				return s
	return null


## A fairway covers the line's landing area or the middle of the hole.
static func _has_fairway(c: DesignedCourse, line: PackedVector2Array, length: float) -> bool:
	for d in [minf(DRIVE, length * 0.55), length * 0.5]:
		if _find(c, Surface.Type.FAIRWAY, _point_at(line, d), 8.0) != null:
			return true
	return false


static func _has_sand(c: DesignedCourse, p: Vector2, radius: float) -> bool:
	return _find(c, Surface.Type.SAND, p, radius) != null


## Whether the hole already has a bunker within 45 m of the hole's line.
static func _sand_along(c: DesignedCourse, line: PackedVector2Array) -> bool:
	for s in c.shapes:
		if s.surface != Surface.Type.SAND:
			continue
		var p := s.bounds().get_center()
		for k in range(1, line.size()):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])) < 45.0:
				return true
	return false


## An ellipse of control points: `along` is the half length in `dir`,
## `across` the half width; `wobble` roughens the edge a little.
static func _ellipse(surface: int, centre: Vector2, dir: Vector2, along: float, across: float, count: int, wobble: float, rng: RandomNumberGenerator) -> CourseShape:
	var pts := PackedVector2Array()
	var side := dir.orthogonal()
	for k in count:
		var t := TAU * k / count
		var f := 1.0 + rng.randf_range(-wobble, wobble)
		pts.append(centre + (dir * cos(t) * along + side * sin(t) * across) * f)
	return CourseShape.new(surface, pts)


## A box with corner and edge points, so the smooth outline stays square.
static func _box(surface: int, centre: Vector2, dir: Vector2, half: Vector2) -> CourseShape:
	var side := dir.orthogonal()
	var pts := PackedVector2Array()
	for k in [[1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1], [1, 0]]:
		pts.append(centre + side * half.x * float(k[0]) + dir * half.y * float(k[1]))
	return CourseShape.new(surface, pts)


## A fairway along the line from `start` to `stop` metres: full width in
## the middle, narrowing toward each end, with gently wandering edges.
static func _fairway(line: PackedVector2Array, start: float, stop: float, width: float, rng: RandomNumberGenerator) -> CourseShape:
	var count := maxi(3, ceili((stop - start) / FAIRWAY_STEP))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in count + 1:
		var t := float(k) / count
		var d := lerpf(start, stop, t)
		var p := _point_at(line, d)
		var side := _dir_at(line, d).orthogonal()
		var half := width * 0.5 * (0.7 + 0.3 * sin(PI * t))
		left.append(p + side * half * rng.randf_range(0.9, 1.1))
		right.append(p - side * half * rng.randf_range(0.9, 1.1))
	right.reverse()
	left.append_array(right)
	return CourseShape.new(Surface.Type.FAIRWAY, left)


## Whether a point is on (or just beside) one of the course's paths.
static func _on_path(c: DesignedCourse, p: Vector2) -> bool:
	for path in c.paths:
		var pts := path.points
		for k in range(1, pts.size()):
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k - 1], pts[k])) < path.width * 0.5 + 3.0:
				return true
	return false


static func _ring_centre(ring: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in ring:
		sum += p
	return sum / maxf(ring.size(), 1.0)


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for k in range(1, line.size()):
		total += line[k - 1].distance_to(line[k])
	return total


## The point `d` metres along a polyline (clamped to its ends).
static func _point_at(line: PackedVector2Array, d: float) -> Vector2:
	var left := maxf(d, 0.0)
	for k in range(1, line.size()):
		var seg := line[k - 1].distance_to(line[k])
		if left <= seg and seg > 0.0:
			return line[k - 1].lerp(line[k], left / seg)
		left -= seg
	return line[line.size() - 1]


## The direction of a polyline `d` metres along it.
static func _dir_at(line: PackedVector2Array, d: float) -> Vector2:
	var left := maxf(d, 0.0)
	for k in range(1, line.size()):
		var seg := line[k - 1].distance_to(line[k])
		if left <= seg or k == line.size() - 1:
			return (line[k] - line[k - 1]).normalized()
		left -= seg
	return Vector2(0, 1)
