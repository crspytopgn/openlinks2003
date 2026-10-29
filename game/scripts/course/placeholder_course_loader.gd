class_name PlaceholderCourseLoader
extends CourseLoader
## A made-up nine-hole course built from procedural terrain, so the round can
## be played before any original course can be read. Each hole has its own
## ground with the tee near the origin, playing towards +z.

const PATH := "placeholder://openlinks-nine"

# par, route (tee first, green centre last), bunkers (x, z, r), ponds (x, z, r)
const HOLES: Array = [
	[4, [Vector2(0, 0), Vector2(0, 225), Vector2(-28, 350)],
		[Vector3(18, 235, 8), Vector3(-42, 340, 6), Vector3(-14, 362, 5)], []],
	[3, [Vector2(0, 0), Vector2(6, 150)],
		[Vector3(-10, 150, 5), Vector3(20, 156, 5)], [Vector3(2, 95, 16)]],
	[5, [Vector2(0, 0), Vector2(8, 240), Vector2(40, 400), Vector2(30, 480)],
		[Vector3(-12, 250, 7), Vector3(52, 410, 8), Vector3(16, 488, 5)], [Vector3(20, 330, 12)]],
	[4, [Vector2(0, 0), Vector2(0, 325)],
		[Vector3(-16, 215, 7), Vector3(15, 230, 7), Vector3(12, 333, 5)], []],
	[4, [Vector2(0, 0), Vector2(0, 235), Vector2(58, 365)],
		[Vector3(70, 375, 5), Vector3(50, 350, 4)], [Vector3(34, 250, 18)]],
	[3, [Vector2(0, 0), Vector2(-10, 175)],
		[Vector3(-26, 172, 6), Vector3(4, 180, 5), Vector3(-12, 158, 4)], []],
	[4, [Vector2(0, 0), Vector2(-18, 220), Vector2(-10, 345)],
		[Vector3(-38, 215, 8)], [Vector3(-6, 300, 11)]],
	[5, [Vector2(0, 0), Vector2(-14, 255), Vector2(16, 420), Vector2(10, 505)],
		[Vector3(4, 250, 7), Vector3(34, 430, 7), Vector3(-6, 512, 5)], [Vector3(-30, 380, 14)]],
	[4, [Vector2(0, 0), Vector2(0, 250), Vector2(-30, 390)],
		[Vector3(-48, 385, 6), Vector3(-14, 402, 5), Vector3(16, 262, 8)], []],
]


func can_load(path: String) -> bool:
	return path == PATH or path.is_empty()


func load_course(_path: String) -> CourseData:
	var course := CourseData.new()
	course.course_name = "Placeholder Nine"
	for i in HOLES.size():
		course.holes.append(_make_hole(i + 1, HOLES[i]))
	return course


func _make_hole(number: int, spec: Array) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * number

	var t := PlaceholderTerrain.new()
	var route := PackedVector2Array()
	for p in spec[1]:
		route.append(p)
	t.route = route
	t.tee = route[0]
	for b in spec[2]:
		t.bunkers.append(b)
	for w in spec[3]:
		t.ponds.append(w)
	t.fairway_width = rng.randf_range(30.0, 40.0)
	t.green_radius = rng.randf_range(11.0, 15.0)
	t.green_slope = Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.025, 0.01))
	t.phase = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))

	var lo := route[0]
	var hi := route[0]
	for p in route:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	t.bounds = Rect2(lo - Vector2(55, 30), hi - lo + Vector2(110, 75))
	t.finalize()

	var hole := HoleData.new()
	hole.number = number
	hole.par = spec[0]
	hole.terrain = t
	hole.tee = Vector3(t.tee.x, t.height_at(t.tee.x, t.tee.y), t.tee.y)
	var g := t.green_center()
	var off := Vector2.from_angle(rng.randf_range(0.0, TAU)) * t.green_radius * rng.randf_range(0.2, 0.55)
	var pin2 := g + off
	hole.pin = Vector3(pin2.x, t.height_at(pin2.x, pin2.y), pin2.y)
	# The route the player sees skips the tee itself.
	hole.route = route.slice(1)
	hole.objects = _place_trees(t, rng)
	return hole


func _place_trees(t: PlaceholderTerrain, rng: RandomNumberGenerator) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	var g := t.green_center()
	var tries := 0
	while out.size() < 70 and tries < 600:
		tries += 1
		var x := rng.randf_range(t.bounds.position.x, t.bounds.end.x)
		var z := rng.randf_range(t.bounds.position.y, t.bounds.end.y)
		if t.surface_at(x, z) != Surface.Type.DEEP_ROUGH:
			continue
		if t.route_distance(x, z).x < t.fairway_width * 0.5 + 14.0:
			continue
		if Vector2(x, z).distance_to(g) < t.green_radius + 14.0 or Vector2(x, z).distance_to(t.tee) < 18.0:
			continue
		var id := "tree_pine" if rng.randf() < 0.55 else "tree_broadleaf"
		out.append(PlacedObject.new(id, Vector3(x, t.height_at(x, z), z), rng.randf_range(0.0, 360.0), rng.randf_range(0.8, 1.3)))
	return out
