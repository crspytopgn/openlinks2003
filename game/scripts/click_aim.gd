class_name ClickAim
extends RefCounted
## Right-click on the course to aim there: the spot under the mouse, and the
## club that reaches it. See docs/game-shell.md#click-to-aim.

## How far along the ray to look, and the first step of the search.
const MAX_RANGE_M := 2500.0
const STEP_M := 2.0


## Where the ray from `origin` along `dir` first meets `terrain`, or null
## when it points at the sky or runs off the course.
static func ray_ground(terrain: CourseTerrain, origin: Vector3, dir: Vector3) -> Variant:
	var d := dir.normalized()
	if terrain.height_at(origin.x, origin.z) >= origin.y:
		return null
	var t := 0.0
	while t < MAX_RANGE_M:
		var next := t + STEP_M
		var p := origin + d * next
		if p.y <= terrain.height_at(p.x, p.z):
			# Halve the step until it is within a few centimetres.
			var lo := t
			var hi := next
			for i in 8:
				var mid := (lo + hi) * 0.5
				var q := origin + d * mid
				if q.y <= terrain.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var hit := origin + d * hi
			return Vector3(hit.x, terrain.height_at(hit.x, hit.z), hit.z)
		t = next
	return null


## The shortest non-putter club whose full swing reaches `distance_m`, given
## each club's full reach in `reaches` (metres, in bag order, longest first;
## a negative reach marks the putter). The longest club when none does.
static func club_for(reaches: Array[float], distance_m: float) -> int:
	var best := 0
	for i in reaches.size():
		if reaches[i] >= 0.0 and reaches[i] >= distance_m:
			best = i
	return best
