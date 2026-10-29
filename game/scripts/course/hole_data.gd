class_name HoleData
extends RefCounted
## One hole: par, tee, pin, the ground it plays over and the objects on it.

var number := 1
var par := 4
var tee := Vector3.ZERO
var pin := Vector3.ZERO
var terrain: CourseTerrain
var objects: Array[PlacedObject] = []
## Points (x, z) the hole is designed to be played along, from the tee to the
## green. Used for auto-aim and the hole length.
var route := PackedVector2Array()


## Playing length along the route, in metres.
func length_m() -> float:
	var total := 0.0
	var prev := Vector2(tee.x, tee.z)
	for p in route:
		total += prev.distance_to(p)
		prev = p
	total += prev.distance_to(Vector2(pin.x, pin.z))
	return total


## Where to aim from `from` with a club that reaches `reach` metres: the pin
## if it is in range, otherwise the furthest route point in range that is
## closer to the pin than the ball is.
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
	if best_d < 0.0:
		return pin
	return Vector3(best.x, terrain.height_at(best.x, best.y), best.y)
