class_name GreenRead
extends RefCounted
## Reading a green: what a golfer can see and feel (the fall of the ground
## along and across the line, the speed of the greens) and which of Links
## 2003's own aids each swing skill level gets. See
## docs/formats/green-reading.md for the original's aids and
## docs/game-shell.md#putting-practice-and-green-reading for ours.
##
## Coordinates as everywhere: +y up, +z downrange, +x to the golfer's left.

## The camera views for reading a putt. PLAY is the normal view behind the
## ball. The first three are what a golfer does on a real green; OVERHEAD
## stands in for the original's Green Analyzer.
enum View { PLAY, CROUCH, BEHIND_HOLE, LOW_SIDE, OVERHEAD }
const VIEW_NAMES := ["Behind the ball", "Crouched behind the ball", "From behind the hole",
	"From the low side", "Green Analyzer: from above"]

## How fast a stimpmeter's ball leaves the ramp on the green: 6 ft/s.
const STIMP_SPEED_FPS := 6.0
const FEET_PER_METRE := 3.2808
## Below this slope (percent) a green reads as flat.
const FLAT_PERCENT := 0.3


## The way the ground falls at (x, z): the downhill direction on the flat,
## as long as the slope's rise over run (0.02 is a 2% slope).
static func fall(terrain: CourseTerrain, x: float, z: float) -> Vector2:
	var n := terrain.normal_at(x, z)
	return Vector2(n.x, n.z) / maxf(n.y, 0.01)


## The golfer's left, on the flat, facing along `forward` (x, z).
static func left_of(forward: Vector2) -> Vector2:
	return Vector2(forward.y, -forward.x)


## Reads the line from `from` to `to` (usually the ball and the hole):
## distance_m; rise_m, up to `to`; side_percent, the average fall across the
## line (+ falls to the golfer's left, so a putt breaks right to left); and
## steepest_percent, the steepest slope along it.
static func line(terrain: CourseTerrain, from: Vector3, to: Vector3) -> Dictionary:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var dist := d.length()
	var forward := d / dist if dist > 1e-4 else Vector2(0, 1)
	var left := left_of(forward)
	var side := 0.0
	var steepest := 0.0
	const SAMPLES := 9
	for i in SAMPLES:
		var t := (i + 1.0) / (SAMPLES + 1.0)
		var p := Vector2(from.x, from.z) + d * t
		var f := fall(terrain, p.x, p.y)
		side += f.dot(left)
		steepest = maxf(steepest, f.length())
	return {
		"distance_m": dist,
		"rise_m": terrain.height_at(to.x, to.z) - terrain.height_at(from.x, from.z),
		"side_percent": side / SAMPLES * 100.0,
		"steepest_percent": steepest * 100.0,
	}


## "Breaks left to right (moderate)", "Straight" and the like.
static func break_text(side_percent: float) -> String:
	var a := absf(side_percent)
	if a < FLAT_PERCENT:
		return "Straight"
	var how := "gentle" if a < 1.0 else ("moderate" if a < 2.5 else "strong")
	return "Breaks %s (%s)" % ["right to left" if side_percent > 0.0 else "left to right", how]


## The slope under the ball, said against the line `forward` (x, z): "1.4%,
## falls left and toward the hole".
static func lie_text(terrain: CourseTerrain, at: Vector3, forward: Vector2) -> String:
	var f := fall(terrain, at.x, at.z)
	var pct := f.length() * 100.0
	if pct < FLAT_PERCENT:
		return "Flat"
	var fwd := forward.normalized()
	var along := f.dot(fwd)
	var across := f.dot(left_of(fwd))
	var parts: Array[String] = []
	if absf(across) >= FLAT_PERCENT * 0.01:
		parts.append("left" if across > 0.0 else "right")
	if absf(along) >= FLAT_PERCENT * 0.01:
		parts.append("toward the hole" if along > 0.0 else "away from the hole")
	return "%.1f%%, falls %s" % [pct, " and ".join(parts)]


## A length in feet and inches: 2' 4", 8".
static func length_text(m: float) -> String:
	var inches := roundi(absf(m) * 39.3701)
	if inches < 12:
		return "%d\"" % inches
	return "%d' %d\"" % [inches / 12, inches % 12]


## What a stimpmeter would read on these greens, in feet: how far a ball
## leaving the ramp at 6 ft/s rolls on the flat. `links` uses Links 2003's
## roll (LinksGround, frame by frame, as the game steps it) for the game's
## firmness and speed options; otherwise the standard model's green.
static func stimp(firmness: int, speed: int, links: bool) -> float:
	if links:
		var resist := LinksGround.GRAVITY * LinksGround.green_for(firmness, speed).roll_resistance
		var dt := LinksGround.FRAME_DT
		var v := STIMP_SPEED_FPS
		var d := 0.0
		while resist * dt < v:
			v -= resist * dt
			d += v * dt
		return d
	var v_m := STIMP_SPEED_FPS / FEET_PER_METRE
	var a := Surface.rolling_resistance(Surface.Type.GREEN) * BallPhysics.GRAVITY
	return v_m * v_m / (2.0 * maxf(a, 1e-4)) * FEET_PER_METRE


## "Medium, normal speed (stimp 5.3)".
static func speed_text(firmness: int, speed: int, links: bool) -> String:
	const FIRMNESS := ["Soft", "Medium", "Firm"]
	const SPEED := ["slow", "normal speed", "fast"]
	return "%s, %s (stimp %.1f)" % [FIRMNESS[clampi(firmness, 0, 2)], SPEED[clampi(speed, 0, 2)], stimp(firmness, speed, links)]


# --- Links 2003's aids by skill level ---------------------------------------
# Skill levels 0 to 3 are the game's Amateur, Professional, Championship and
# Elite.

## The grid: every level but Elite.
static func grid_allowed(skill: int) -> bool:
	return skill <= 2


## The Green Analyzer (here, the overhead view): every level but Elite.
static func analyzer_allowed(skill: int) -> bool:
	return skill <= 2


## The Putting Assistant: 2 the exact line and power (Amateur), 1 a wider
## band round the line (Professional), 0 none (Championship and Elite).
static func assistant_level(skill: int) -> int:
	match skill:
		0:
			return 2
		1:
			return 1
	return 0


## The read views a player at `skill` can use, PLAY first.
static func views_for(skill: int) -> Array[int]:
	var out: Array[int] = [View.PLAY, View.CROUCH, View.BEHIND_HOLE, View.LOW_SIDE]
	if analyzer_allowed(skill):
		out.append(View.OVERHEAD)
	return out


## Where the camera stands and what it looks at, [position, look], for a
## read `view` of the putt from `ball` to `pin`. Eye heights are a crouching
## golfer's (about 0.6 m) for the views on the green.
static func view_pose(view: int, terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> Array:
	var d := Vector2(pin.x - ball.x, pin.z - ball.z)
	var dist := maxf(d.length(), 0.1)
	var fwd := d / dist if d.length() > 1e-4 else Vector2(0, 1)
	var fwd3 := Vector3(fwd.x, 0.0, fwd.y)
	var left3 := Vector3(fwd.y, 0.0, -fwd.x)
	var mid := (ball + pin) * 0.5
	mid.y = terrain.height_at(mid.x, mid.z)
	var pos := ball
	var look := pin
	match view:
		View.CROUCH:
			pos = _on_ground(terrain, ball - fwd3 * 1.3, 0.55)
			look = pin + Vector3.UP * 0.05
		View.BEHIND_HOLE:
			pos = _on_ground(terrain, pin + fwd3 * 1.6, 0.6)
			look = ball + Vector3.UP * 0.05
		View.LOW_SIDE:
			# Real golfers look at the slope from the side it falls to.
			var side := 1.0 if float(line(terrain, ball, pin).side_percent) >= 0.0 else -1.0
			pos = _on_ground(terrain, mid + left3 * side * maxf(3.0, dist * 0.6), 0.7)
			look = mid + Vector3.UP * 0.1
		View.OVERHEAD:
			pos = mid - fwd3 * (dist * 0.25 + 2.0)
			pos.y = mid.y + dist * 0.9 + 5.0
			look = mid
		_:
			pos = _on_ground(terrain, ball - fwd3 * 2.6, 1.2)
			look = ball + fwd3 * 6.0
	return [pos, look]


static func _on_ground(terrain: CourseTerrain, p: Vector3, eye: float) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z) + eye, p.z)
