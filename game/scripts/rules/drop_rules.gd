class_name DropRules
extends RefCounted
## Taking a drop: from water, from an unplayable lie, and free relief from a
## cart path. Links 2003 lets the player drop (one stroke) from water or a
## lie they don't like, gives a free drop on cart paths, and won't let the
## ball be dropped nearer the pin, in a hazard, out of bounds or on the
## green; a ball unplayable in a bunker must be dropped in the sand. The drop
## zones themselves follow the Rules of Golf (rules 16, 17 and 19).
## GDScript port of libs/olcore/src/rules.cpp; change both together.

const CLUB_LENGTH := 1.143  ## a 45-inch driver
const STEP := 0.25  ## metres between spots tried
const MARGIN := 1.0  ## extra room back on the line, off the hazard edge
const MAX_BACK_ON_LINE := 200.0
const FREE_RELIEF_SEARCH := 30.0
const EPS := 1e-3

enum Reason { WATER, UNPLAYABLE, FREE_RELIEF }
enum Option { STROKE_AND_DISTANCE, BACK_ON_LINE, LATERAL, FREE_DROP }
enum Check { OK, OUTSIDE_ZONE, NEARER_PIN, HAZARD, OUT_OF_BOUNDS, GREEN, NOT_SAND, STILL_ON_PATH }

const OPTION_NAMES: Array[String] = [
	"Replay from the last spot", "Drop back on the line", "Drop within two club lengths", "Free drop",
]
const CHECK_TEXT: Array[String] = [
	"", "Stay inside the drop zone.", "You can't drop nearer the pin.", "You can't drop in a hazard.",
	"You can't drop out of bounds.", "You can't drop on the green.", "The drop has to stay in the bunker.",
	"That's still on the path.",
]


## Where the ball may be dropped for one option, and the default spot.
class Zone:
	var option: int = Option.STROKE_AND_DISTANCE
	## The ball, where it last went into the water, or the nearest point of relief.
	var reference := Vector3.ZERO
	## BACK_ON_LINE: unit vector (y = 0) away from the pin.
	var direction := Vector3.ZERO
	## LATERAL and FREE_DROP: relief area around the reference.
	var radius := 0.0
	var in_sand := false  ## the drop must stay in the bunker
	var found := false  ## `spot` is a legal drop
	var spot := Vector3.ZERO  ## the default drop, on the ground


static func penalty(reason: int) -> int:
	return 0 if reason == Reason.FREE_RELIEF else 1


## The options, in menu order. Lateral relief from water only where it is a
## red (lateral) hazard.
static func options(reason: int, lateral_water: bool) -> Array[int]:
	if reason == Reason.FREE_RELIEF:
		return [Option.FREE_DROP]
	if reason == Reason.WATER and not lateral_water:
		return [Option.BACK_ON_LINE, Option.STROKE_AND_DISTANCE]
	return [Option.BACK_ON_LINE, Option.LATERAL, Option.STROKE_AND_DISTANCE]


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _on_ground(x: float, z: float, t: CourseTerrain) -> Vector3:
	return Vector3(x, t.height_at(x, z), z)


static func _away_from_pin(p: Vector3, pin: Vector3) -> Vector3:
	var dx := p.x - pin.x
	var dz := p.z - pin.z
	var length := sqrt(dx * dx + dz * dz)
	if length < 1e-6:
		return Vector3(0, 0, -1)
	return Vector3(dx / length, 0, dz / length)


## The j-th direction tried around `base`: 0, +10, -10, +20, ... +180 degrees.
static func _ring_direction(base: Vector3, j: int) -> Vector3:
	@warning_ignore("integer_division")
	var k := (j + 1) / 2
	var a := (1.0 if j % 2 == 1 else -1.0) * k * 10.0 * PI / 180.0
	var c := cos(a)
	var s := sin(a)
	return Vector3(base.x * c + base.z * s, 0, -base.x * s + base.z * c)


static func _general_area(s: int) -> bool:
	return s != Surface.Type.WATER and s != Surface.Type.OUT_OF_BOUNDS and s != Surface.Type.GREEN


## Where a ball that finished in water last crossed into it: the path is
## walked back from the end to the last step from dry ground into water, and
## that step is bisected. The first sample if it never leaves the water.
static func water_entry(path: PackedVector3Array, t: CourseTerrain) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	for i in range(path.size() - 1, 0, -1):
		if _wet(path[i - 1], t) or not _wet(path[i], t):
			continue
		var a := path[i - 1]
		var b := path[i]
		for n in 30:
			var m := (a + b) * 0.5
			if _wet(m, t):
				b = m
			else:
				a = m
		return _on_ground(b.x, b.z, t)
	return _on_ground(path[0].x, path[0].z, t)


static func _wet(p: Vector3, t: CourseTerrain) -> bool:
	return t.surface_at(p.x, p.z) == Surface.Type.WATER


## The nearest spot off the cart path, no nearer the pin, that isn't in a
## hazard, out of bounds or on the green; null if none within the search.
static func nearest_relief(ball: Vector3, pin: Vector3, t: CourseTerrain) -> Variant:
	var base := _away_from_pin(ball, pin)
	var limit := _flat_distance(ball, pin) - EPS
	var i := 1
	while i * STEP <= FREE_RELIEF_SEARCH + 1e-9:
		for j in 36:
			var d := _ring_direction(base, j)
			var x := ball.x + d.x * i * STEP
			var z := ball.z + d.z * i * STEP
			if not _general_area(t.surface_at(x, z)) or t.free_drop_at(x, z):
				continue
			if Vector2(x - pin.x, z - pin.z).length() < limit:
				continue
			return _on_ground(x, z, t)
		i += 1
	return null


## The zone for one option and its default spot. `reference` is the ball for
## an unplayable lie or free relief, the water entry for water; `previous` is
## where the last shot was played from.
static func zone(option: int, reference: Vector3, previous: Vector3, pin: Vector3, in_sand: bool, t: CourseTerrain) -> Zone:
	var z := Zone.new()
	z.option = option
	z.reference = reference
	z.direction = _away_from_pin(reference, pin)
	z.in_sand = in_sand and option != Option.STROKE_AND_DISTANCE
	match option:
		Option.STROKE_AND_DISTANCE:
			z.reference = previous
			z.spot = previous
			z.found = true
		Option.BACK_ON_LINE:
			var k := 0
			while k * STEP <= MAX_BACK_ON_LINE + 1e-9:
				var d := k * STEP
				var p := reference + z.direction * d
				k += 1
				if check(z, p, pin, t) != Check.OK:
					continue
				var q := reference + z.direction * (d + MARGIN)
				if check(z, q, pin, t) == Check.OK:
					p = q
				z.spot = _on_ground(p.x, p.z, t)
				z.found = true
				break
		Option.LATERAL, Option.FREE_DROP:
			if option == Option.FREE_DROP:
				z.radius = CLUB_LENGTH
				var point: Variant = nearest_relief(reference, pin, t)
				if point == null:
					return z
				z.reference = point
				z.direction = _away_from_pin(z.reference, pin)
			else:
				z.radius = 2.0 * CLUB_LENGTH
			# Lateral relief starts a step out: the reference is the ball
			# itself, or the water's edge.
			var c := z.reference
			var i := 1 if option == Option.LATERAL else 0
			while i * STEP <= z.radius + 1e-9 and not z.found:
				for j in (1 if i == 0 else 36):
					var d := _ring_direction(z.direction, j)
					var x := c.x + d.x * i * STEP
					var zz := c.z + d.z * i * STEP
					if check(z, Vector3(x, 0, zz), pin, t) != Check.OK:
						continue
					z.spot = _on_ground(x, zz, t)
					z.found = true
					break
				i += 1
	return z


## Whether the ball may be dropped at `spot` (a Check value).
static func check(z: Zone, spot: Vector3, pin: Vector3, t: CourseTerrain) -> int:
	if z.option == Option.STROKE_AND_DISTANCE:
		return Check.OK if _flat_distance(spot, z.spot) < 0.01 else Check.OUTSIDE_ZONE
	var s := t.surface_at(spot.x, spot.z)
	if s == Surface.Type.OUT_OF_BOUNDS:
		return Check.OUT_OF_BOUNDS
	if s == Surface.Type.WATER:
		return Check.HAZARD
	if s == Surface.Type.GREEN:
		return Check.GREEN
	if z.in_sand and s != Surface.Type.SAND:
		return Check.NOT_SAND
	if z.option == Option.FREE_DROP and t.free_drop_at(spot.x, spot.z):
		return Check.STILL_ON_PATH
	var ref := z.reference
	if z.option == Option.BACK_ON_LINE:
		var dx := spot.x - ref.x
		var dz := spot.z - ref.z
		var along := dx * z.direction.x + dz * z.direction.z
		var across := absf(dx * z.direction.z - dz * z.direction.x)
		if along < -EPS or along > MAX_BACK_ON_LINE + MARGIN + EPS or across > CLUB_LENGTH + EPS:
			return Check.OUTSIDE_ZONE
	elif _flat_distance(spot, ref) > z.radius + EPS:
		return Check.OUTSIDE_ZONE
	if _flat_distance(spot, pin) < _flat_distance(ref, pin) - EPS:
		return Check.NEARER_PIN
	return Check.OK


## The zone a computer golfer (or a player who just confirms) takes: the
## legal drop that leaves the shortest way to the pin, stroke and distance if
## there is none.
static func best(zones: Array[Zone], pin: Vector3) -> int:
	var best_i := -1
	var best_d := 0.0
	for i in zones.size():
		if zones[i].option == Option.STROKE_AND_DISTANCE or not zones[i].found:
			continue
		var d := _flat_distance(zones[i].spot, pin)
		if best_i < 0 or d < best_d:
			best_i = i
			best_d = d
	if best_i >= 0:
		return best_i
	for i in zones.size():
		if zones[i].option == Option.STROKE_AND_DISTANCE:
			return i
	return 0
