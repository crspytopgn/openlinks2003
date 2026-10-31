class_name DesignedHole
extends RefCounted
## One hole of a designed course: par, tee boxes (back to forward), the pin
## and the aim points the hole is meant to be played along. Positions are
## (x, z) on the course; heights come from the terrain.

const MAX_TEES := 3
const TEE_NAMES := ["Back tee", "Middle tee", "Forward tee"]

var par := 4
var tees := PackedVector2Array()
var pin := Vector2.ZERO
var route := PackedVector2Array()  ## aim points between the tee and the pin


## Length from the back tee along the aim points to the pin, in metres.
func length_m() -> float:
	if tees.is_empty():
		return 0.0
	var total := 0.0
	var prev := tees[0]
	for p in route:
		total += prev.distance_to(p)
		prev = p
	return total + prev.distance_to(pin)


## The usual par for a hole of this length (men's yardage guide).
static func par_for_length(metres: float) -> int:
	var yards := metres * 1.0936
	if yards <= 250.0:
		return 3
	if yards <= 470.0:
		return 4
	return 5


func to_dict() -> Dictionary:
	return {"par": par, "tees": _flat(tees), "pin": [snappedf(pin.x, 0.01), snappedf(pin.y, 0.01)], "route": _flat(route)}


static func from_dict(d: Dictionary) -> DesignedHole:
	var h := DesignedHole.new()
	h.par = clampi(int(d.get("par", 4)), 3, 6)
	h.tees = _points(d.get("tees", []))
	var p: Array = d.get("pin", [0, 0])
	if p.size() >= 2:
		h.pin = Vector2(float(p[0]), float(p[1]))
	h.route = _points(d.get("route", []))
	return h


static func _flat(pts: PackedVector2Array) -> Array[float]:
	var out: Array[float] = []
	for p in pts:
		out.append(snappedf(p.x, 0.01))
		out.append(snappedf(p.y, 0.01))
	return out


static func _points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out
