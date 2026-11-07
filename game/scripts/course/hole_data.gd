class_name HoleData
extends RefCounted
## One hole: par, tee, pin, the ground it plays over and the objects on it.

var number := 1
var par := 4
## Stroke index from the course: 1 is the hardest hole, where handicap
## strokes go first. 0 if the course doesn't say.
var stroke_index := 0
## The tee in play.
var tee := Vector3.ZERO
## Every tee box, back to forward, when the course has more than one.
var tees: Array[Vector3] = []
var pin := Vector3.ZERO
## Every hole position the course has (Links 2003 courses keep 18 per hole),
## the usual one first; empty when the course has only `pin`.
var pins: Array[Vector3] = []
var terrain: CourseTerrain
var objects: Array[PlacedObject] = []
## Points (x, z) the hole is designed to be played along, from the tee to the
## green. Used for auto-aim and the hole length.
var route := PackedVector2Array()
## The length to show for the hole in metres when the route doesn't give it
## (a driving range, whose route visits each target); 0 to measure the route.
var card_length := 0.0
## True when the route points are targets to hit at (a driving range), not
## the line of a hole: aim_point then stops at a point, never between two.
var route_targets := false

## A route point where the line bends less than this is only shaping the
## fairway, not a corner to lay up at: aim_point carries on along the next
## leg as far as the club reaches. (Kettle Hollow's 1st bends 8 degrees 128 m
## out, so everyone, the tour pro too, used to hit a half driver to 140 yd.)
const GENTLE_BEND_DEG := 25.0


## Playing length along the route, in metres.
func length_m() -> float:
	if card_length > 0.0:
		return card_length
	var total := 0.0
	var prev := Vector2(tee.x, tee.z)
	for p in route:
		total += prev.distance_to(p)
		prev = p
	total += prev.distance_to(Vector2(pin.x, pin.z))
	return total


## Where to aim from `from` with a club that reaches `reach` metres: the pin
## if it is in range, otherwise the furthest route point in range that is
## closer to the pin than the ball is, or failing that the next route point.
func aim_point(from: Vector3, reach: float) -> Vector3:
	var here := Vector2(from.x, from.z)
	var pin2 := Vector2(pin.x, pin.z)
	var to_pin := here.distance_to(pin2)
	if to_pin <= reach:
		return pin
	var best := pin2
	var best_d := -1.0
	for p in route:
		var d := here.distance_to(p)
		if d <= reach and d > best_d and p.distance_to(pin2) < to_pin - 1.0:
			best = p
			best_d = d
	if best_d >= 0.0 and not route_targets:
		return _slide_on(here, best, pin2, reach)
	if best_d < 0.0:
		# Every route point is out of reach: head for the next one anyway.
		# Straight at the pin cut the corner of a dogleg over the trees
		# (Kettle Hollow's 9th, whose corner is just past driver reach).
		var next_d := INF
		for p in route:
			var d := here.distance_to(p)
			if d < next_d and p.distance_to(pin2) < to_pin - 1.0:
				best = p
				next_d = d
		if next_d == INF:
			return pin
	return Vector3(best.x, terrain.height_at(best.x, best.y), best.y)


## From route point `at` (in reach of `here`), the furthest point in reach
## along the line after it, if the line only bends gently there.
func _slide_on(here: Vector2, at: Vector2, pin2: Vector2, reach: float) -> Vector3:
	var k := route.find(at)
	var next := pin2 if k < 0 or k + 1 >= route.size() else route[k + 1]
	var leg := next - at
	var come := at - here
	var out := at
	if leg.length() > 0.01 and come.length() > 0.01 and rad_to_deg(absf(come.angle_to(leg))) < GENTLE_BEND_DEG:
		# |at + t * leg - here| = reach, for the t in (0, 1] past `at`.
		var a := leg.dot(leg)
		var b := 2.0 * leg.dot(come)
		var c := come.dot(come) - reach * reach
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var t := clampf((-b + sqrt(disc)) / (2.0 * a), 0.0, 1.0)
			out = at + leg * t
	return Vector3(out.x, terrain.height_at(out.x, out.y), out.y)
