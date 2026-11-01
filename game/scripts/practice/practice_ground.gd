class_name PracticeGround
extends CourseLoader
## The club's practice ground, built in: a driving range and a practice
## putting green. Laid out from photos of real club and tour ranges: a wide
## grass tee line, a striped field with flagged target greens at set
## yardages (each with a yardage board), and a big rolling putting green
## with several cups. Nothing here comes from Links 2003; with the game's
## files its own .RNG range plays instead.
##
## Hole 1 is the range (RoundSetup.practice), hole 2 the putting green
## (RoundSetup.putting). The range's targets are the target game's
## (RangeGame) too.

const PATH := "placeholder://practice-ground"
const RANGE := 0  ## index of the range hole
const PUTTING_GREEN := 1  ## index of the practice green
const YARD := 0.9144

## The range's targets: yards from the tee line, metres across (+x is left
## looking down the range), radius in metres, flag colour. Real ranges put
## them at round yardages, staggered left and right, bigger further out.
## The last is the "green" the hole is built round, straight down the middle.
const TARGETS: Array = [
	[50, -8.0, 5.0, Color(0.86, 0.07, 0.05)],
	[75, 13.0, 6.0, Color(0.95, 0.78, 0.08)],
	[100, -14.0, 7.0, Color(0.95, 0.95, 0.92)],
	[125, 10.0, 8.0, Color(0.1, 0.25, 0.75)],
	[150, -5.0, 9.0, Color(0.86, 0.07, 0.05)],
	[175, 17.0, 10.0, Color(0.95, 0.78, 0.08)],
	[200, -16.0, 11.0, Color(0.95, 0.95, 0.92)],
	[250, 0.0, 13.0, Color(0.1, 0.25, 0.75)],
]
## Range field: metres wide (mown as fairway), and how far back it runs.
const FIELD_WIDTH := 110.0
const FIELD_LENGTH := 285.0
## The grass tee line: half its width and depth.
const TEE_LINE := Vector2(40.0, 6.0)
## The player's station along the tee line (x).
const STATION_X := 3.5


func can_load(path: String) -> bool:
	return path == PATH


func load_course(_path: String) -> CourseData:
	var course := CourseData.new()
	course.course_name = "Practice Ground"
	course.holes.append(make_range())
	course.holes.append(make_putting_green())
	return course


## Target i's centre on the ground.
static func target_position(terrain: CourseTerrain, i: int) -> Vector3:
	var t: Array = TARGETS[i]
	var z := float(t[0]) * YARD
	return Vector3(t[1], terrain.height_at(t[1], z), z)


static func target_radius(i: int) -> float:
	return TARGETS[i][2]


static func make_range() -> HoleData:
	var t := PlaceholderTerrain.new()
	# The player's station sits in the middle of a mowing stripe (the
	# terrain shader's are 7 m wide from x = 0), not on the line between two.
	t.tee = Vector2(STATION_X, 0.0)
	t.tee_half = TEE_LINE
	# The route ends at the furthest target (the terrain's green); the field,
	# mown as fairway within half its width of the route, rounds off past it.
	var last: Array = TARGETS[TARGETS.size() - 1]
	t.route = PackedVector2Array([Vector2.ZERO, Vector2(last[1], float(last[0]) * YARD)])
	t.fairway_width = FIELD_WIDTH
	t.fairway_start = TEE_LINE.y
	t.green_radius = last[2]
	for i in TARGETS.size() - 1:
		var tg: Array = TARGETS[i]
		t.targets.append(Vector3(tg[1], float(tg[0]) * YARD, tg[2]))
	# Two bunkers short of targets, as ranges build them to practise from.
	t.bunkers.append(Vector3(-5.0, 150 * YARD - 13.0, 3.5))
	t.bunkers.append(Vector3(17.0, 175 * YARD + 13.5, 3.5))
	t.phase = Vector3(1.1, 2.3, 0.4)
	t.bounds = Rect2(-FIELD_WIDTH * 0.5 - 22.0, -25.0, FIELD_WIDTH + 44.0, FIELD_LENGTH + 40.0)
	t.finalize()
	var hole := HoleData.new()
	hole.number = 1
	hole.par = 3
	hole.terrain = t
	hole.tee = Vector3(STATION_X, t.height_at(STATION_X, 0), 0)
	var g := t.green_center()
	hole.pin = Vector3(g.x, t.height_at(g.x, g.y), g.y)
	hole.card_length = float(last[0]) * YARD
	# Auto-aim picks the furthest target the club reaches (HoleData.aim_point).
	for i in TARGETS.size() - 1:
		var p := target_position(t, i)
		hole.route.append(Vector2(p.x, p.z))
	hole.objects = _trees(t, 7001)
	return hole


static func make_putting_green() -> HoleData:
	var t := PlaceholderTerrain.new()
	t.tee = Vector2.ZERO
	t.route = PackedVector2Array([Vector2.ZERO, Vector2(0, 34.0)])
	t.fairway_width = 50.0
	t.fairway_start = 8.0
	# Practice greens are big (often 1,000 m2 or more) and roll, so every
	# break can be practised on one green.
	t.green_radius = 19.0
	t.green_slope = Vector2(0.008, -0.012)
	t.green_undulation = 0.12
	t.phase = Vector3(0.3, 1.7, 2.9)
	t.bounds = Rect2(-45.0, -20.0, 90.0, 95.0)
	t.finalize()
	var hole := HoleData.new()
	hole.number = 2
	hole.par = 3
	hole.terrain = t
	hole.tee = Vector3(0, t.height_at(0, 0), 0)
	var g := t.green_center()
	hole.pin = Vector3(g.x, t.height_at(g.x, g.y), g.y)
	hole.objects = _trees(t, 7002)
	return hole


## Trees and shrubs off the mown ground, as round a club's practice area.
static func _trees(t: PlaceholderTerrain, seed_value: int) -> Array[PlacedObject]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[PlacedObject] = []
	var tries := 0
	while out.size() < 60 and tries < 800:
		tries += 1
		var x := rng.randf_range(t.bounds.position.x, t.bounds.end.x)
		var z := rng.randf_range(t.bounds.position.y, t.bounds.end.y)
		if t.surface_at(x, z) != Surface.Type.DEEP_ROUGH:
			continue
		if t.route_distance(x, z).x < t.fairway_width * 0.5 + 12.0 or z < -8.0:
			continue
		var id := "tree_pine" if rng.randf() < 0.5 else "tree_broadleaf"
		out.append(PlacedObject.new(id, Vector3(x, t.height_at(x, z), z), rng.randf_range(0.0, 360.0), rng.randf_range(0.8, 1.3)))
	return out
