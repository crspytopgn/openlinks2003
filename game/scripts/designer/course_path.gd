class_name CoursePath
extends RefCounted
## A cart path or a bridge on a designed course: a line of points (x, z)
## and a width. Paths lie on the ground and play as fairway. Bridges run in
## a straight slope from one end to the other (never below the ground), and
## their deck is solid for the ball.

const MIN_WIDTH := 1.0
const MAX_WIDTH := 8.0
const STEP := 1.0  ## metres between ribbon samples
const DECK_RAISE := 0.4  ## bridge ends above the ground
const DECK_CLEARANCE := 0.6  ## bridge deck above the ground or water under it

var points := PackedVector2Array()
var width := 2.5
var bridge := false


func _init(p_points := PackedVector2Array(), p_width := 2.5, p_bridge := false) -> void:
	points = p_points
	width = clampf(p_width, MIN_WIDTH, MAX_WIDTH)
	bridge = p_bridge


func is_valid() -> bool:
	return points.size() >= 2 and length() > 0.5


func length() -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func bounds() -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO) if not points.is_empty() else Rect2()
	for p in points:
		r = r.expand(p)
	return r.grow(width)


## Distance from `p` to the centre line.
func distance_to(p: Vector2) -> float:
	var best := INF
	for i in range(1, points.size()):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, points[i - 1], points[i])))
	return best


## Samples along the centre line about STEP apart: each is [point, unit
## direction, distance along].
func samples() -> Array:
	var out: Array = []
	var along := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var dir := (b - a) / seg
		var n := maxi(1, ceili(seg / STEP))
		for k in n:
			out.append([a + dir * seg * k / n, dir, along + seg * k / n])
		along += seg
	if points.size() >= 2:
		var last := points[points.size() - 1]
		out.append([last, (last - points[points.size() - 2]).normalized(), along])
	return out


## The ground the path covers, as a polygon (left edge out, right edge back).
func outline() -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for s: Array in samples():
		var side: Vector2 = (s[1] as Vector2).orthogonal() * width * 0.5
		left.append(s[0] + side)
		right.append(s[0] - side)
	right.reverse()
	return left + right


## Height of a bridge deck at distance `along` given the ground under the
## deck there (`ground`) and at both ends.
func deck_height(along: float, ground: float, start_ground: float, end_ground: float) -> float:
	var t := along / maxf(length(), 0.01)
	return maxf(lerpf(start_ground, end_ground, t) + DECK_RAISE, ground + DECK_CLEARANCE)


func to_dict() -> Dictionary:
	var flat: Array[float] = []
	for p in points:
		flat.append(snappedf(p.x, 0.01))
		flat.append(snappedf(p.y, 0.01))
	return {"points": flat, "width": snappedf(width, 0.01), "bridge": bridge}


static func from_dict(d: Dictionary) -> CoursePath:
	var pts := PackedVector2Array()
	var flat: Variant = d.get("points", [])
	if flat is Array:
		for i in range(0, (flat as Array).size() - 1, 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return CoursePath.new(pts, float(d.get("width", 2.5)), bool(d.get("bridge", false)))
