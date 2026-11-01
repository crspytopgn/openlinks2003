class_name PuttingPractice
extends RefCounted
## Putting practice the way a club's practice green works: several cups cut
## round the green, each with a short stick instead of a flag; drop a ball,
## putt to any cup, and drop again. Links 2003's own practice had "Putting
## Only" with New Position and Auto-Mulligan (the ball comes back to the same
## spot); this keeps those and adds the drills golfers do on practice greens.
##
## The cups are cut on each hole's own green, so each green's real slopes are
## there to learn. Only the chosen cup is a cup to the physics (the hole's
## pin); the others are just shown. Pure logic, no nodes: main.gd places the
## ball and draws the cups (PracticeCups).

enum Drill { FREE, CLOCK, LADDER }
enum Slope { ANY, UPHILL, DOWNHILL, LEFT_TO_RIGHT, RIGHT_TO_LEFT }

const DRILL_NAMES := ["Free putting", "Around the clock", "Lag ladder"]
const DRILL_HELP := [
	"Same spot until you move it: N for a new spot, [ and ] for the distance, L for the slope.",
	"Six balls in a ring 3 ft round the cup. Hole them all in a row; a miss starts again.",
	"Lag putts of 20, 30, 40 and 50 ft. Each one that stops within 3 ft scores.",
]
const SLOPE_NAMES := ["Any slope", "Uphill", "Downhill", "Left to right", "Right to left"]
const DRILLS_HELP := "Drills: free putting, around the clock and a lag ladder. Nothing is scored or saved."
const SETUP_HELP := "Putting practice: the first player on a practice green with several cups on each chosen hole's green. " + DRILLS_HELP
const DISTANCES_FT: Array[int] = [3, 4, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60]
const DEFAULT_DISTANCE := 4  ## index of 10 ft
const CLOCK_FT := 3.0
const CLOCK_BALLS := 6
const LADDER_FT: Array[float] = [20.0, 30.0, 40.0, 50.0]
const LADDER_ZONE_FT := 3.0
const MAX_CUPS := 6
const CUP_SPACING := 5.0  ## metres between cups
const CUP_EDGE := 1.3  ## metres of green all round a cup
const CUP_MAX_SLOPE := 3.0  ## percent; cups are cut on the flatter parts
const SEARCH := 35.0  ## metres either side of the hole's pin
const FT := 0.3048
## A spot matches the slope asked for if its line rises, falls or breaks by
## at least this (percent).
const SLOPE_MATCH := 0.5

var terrain: CourseTerrain
var cups: Array[Vector3] = []
var cup := 0
var drill: Drill = Drill.FREE
var slope: Slope = Slope.ANY
var distance_index := DEFAULT_DISTANCE
## Where the ball is dropped for the next putt.
var spot := Vector3.ZERO
## False when no spot on the green matched the slope asked for.
var slope_found := true

# The session so far.
var putts := 0
var holed := 0
var misses := 0
var miss_total_m := 0.0
var clock_best := 0
var ladder_best := 0

var _rng := RandomNumberGenerator.new()
var _step := 0  ## which ball of a drill is next
var _clock_turn := 0.0  ## where the clock's first ball sits round the cup
var _ladder_dir := Vector2(0, 1)
var _ladder_score := 0


func _init(seed_value := 1) -> void:
	_rng.seed = seed_value


## Cuts the cups on `hole`'s green (its own pin first) and drops the first
## ball. Returns the spot.
func setup(hole: HoleData) -> Vector3:
	terrain = hole.terrain
	cups = find_cups(terrain, hole.pin, _rng)
	cup = 0
	_restart_drill()
	return spot


func cup_position() -> Vector3:
	return cups[cup]


func distance_ft() -> float:
	return float(DISTANCES_FT[distance_index])


## Cups for a practice green: the pin, then up to MAX_CUPS - 1 more on the
## same green, each with green all round it, on gentle ground and apart.
static func find_cups(t: CourseTerrain, pin: Vector3, rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3(pin.x, t.height_at(pin.x, pin.z), pin.z)]
	var candidates: Array[Vector3] = []
	var steps := int(SEARCH)
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var x := pin.x + i
			var z := pin.z + j
			if _cup_fits(t, x, z):
				candidates.append(Vector3(x, t.height_at(x, z), z))
	# Shuffle with the session's own generator, so a seed gives the same green.
	for i in range(candidates.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[k]
		candidates[k] = tmp
	for c in candidates:
		if out.size() >= MAX_CUPS:
			break
		var apart := true
		for o in out:
			if Vector2(c.x - o.x, c.z - o.z).length() < CUP_SPACING:
				apart = false
				break
		if apart:
			out.append(c)
	return out


static func _cup_fits(t: CourseTerrain, x: float, z: float) -> bool:
	if t.surface_at(x, z) != Surface.Type.GREEN:
		return false
	if GreenRead.fall(t, x, z).length() * 100.0 > CUP_MAX_SLOPE:
		return false
	for k in 8:
		var a := k * TAU / 8.0
		if t.surface_at(x + cos(a) * CUP_EDGE, z + sin(a) * CUP_EDGE) != Surface.Type.GREEN:
			return false
	return true


# --- Choosing where to drop the ball ------------------------------------------

## A spot `dist_m` from `target` on the green whose putt best fits `want`,
## trying 36 directions; null-free: falls back to shorter putts, then to the
## cup's side. Sets slope_found.
func pick_spot(target: Vector3, dist_m: float, want: Slope) -> Vector3:
	var turn := _rng.randf() * TAU
	var d := dist_m
	for _attempt in 4:
		var best := Vector3.INF
		var best_score := -INF
		var valid: Array[Vector3] = []
		for k in 36:
			var a := turn + k * TAU / 36.0
			var p := Vector3(target.x + sin(a) * d, 0.0, target.z + cos(a) * d)
			if terrain.surface_at(p.x, p.z) != Surface.Type.GREEN:
				continue
			p.y = terrain.height_at(p.x, p.z)
			valid.append(p)
			var s := slope_score(terrain, p, target, want)
			if s > best_score:
				best_score = s
				best = p
		if not valid.is_empty():
			if want == Slope.ANY:
				slope_found = true
				return valid[_rng.randi_range(0, valid.size() - 1)]
			slope_found = best_score >= SLOPE_MATCH
			return best
		d *= 0.7
	slope_found = false
	var p := target + Vector3(0.0, 0.0, -minf(dist_m, 1.0))
	p.y = terrain.height_at(p.x, p.z)
	return p


## How well the putt from `from` to `to` fits `want`, in percent of slope:
## the rise for uphill, the fall for downhill, the break for the others.
static func slope_score(t: CourseTerrain, from: Vector3, to: Vector3, want: Slope) -> float:
	var r := GreenRead.line(t, from, to)
	var dist := maxf(float(r.distance_m), 0.1)
	var rise_pct := float(r.rise_m) / dist * 100.0
	var side := float(r.side_percent)
	match want:
		Slope.UPHILL:
			return rise_pct - absf(side) * 0.5
		Slope.DOWNHILL:
			return -rise_pct - absf(side) * 0.5
		Slope.LEFT_TO_RIGHT:
			return -side  # falls to the right
		Slope.RIGHT_TO_LEFT:
			return side
	return 0.0


# --- The session ------------------------------------------------------------

## A new spot for free putting (N), or the drill from the start.
func new_spot() -> Vector3:
	if drill == Drill.FREE:
		spot = pick_spot(cup_position(), distance_ft() * FT, slope)
	else:
		_restart_drill()
	return spot


## Moves to the next cup (T) and drops again.
func next_cup() -> Vector3:
	cup = (cup + 1) % cups.size()
	_restart_drill()
	return spot


## Changes the free-putting distance by `step` places ([ and ]).
func change_distance(step: int) -> Vector3:
	distance_index = clampi(distance_index + step, 0, DISTANCES_FT.size() - 1)
	if drill == Drill.FREE:
		new_spot()
	return spot


func next_slope() -> Vector3:
	slope = ((slope + 1) % SLOPE_NAMES.size()) as Slope
	if drill == Drill.FREE:
		new_spot()
	return spot


func next_drill() -> Vector3:
	drill = ((drill + 1) % DRILL_NAMES.size()) as Drill
	_restart_drill()
	return spot


func _restart_drill() -> void:
	_step = 0
	_ladder_score = 0
	match drill:
		Drill.FREE:
			spot = pick_spot(cup_position(), distance_ft() * FT, slope)
		Drill.CLOCK:
			_clock_turn = _rng.randf() * TAU
			spot = _clock_spot()
		Drill.LADDER:
			var far := pick_spot(cup_position(), LADDER_FT[LADDER_FT.size() - 1] * FT, Slope.ANY)
			var c := cup_position()
			_ladder_dir = Vector2(far.x - c.x, far.z - c.z).normalized()
			if _ladder_dir == Vector2.ZERO:
				_ladder_dir = Vector2(0, -1)
			spot = _ladder_spot()


func _clock_spot() -> Vector3:
	var c := cup_position()
	var a := _clock_turn + _step * TAU / CLOCK_BALLS
	var p := Vector3(c.x + sin(a) * CLOCK_FT * FT, 0.0, c.z + cos(a) * CLOCK_FT * FT)
	p.y = terrain.height_at(p.x, p.z)
	return p


## Along one line from the cup, as the drill is set out, shortened where
## the green runs out.
func _ladder_spot() -> Vector3:
	var c := cup_position()
	var d := LADDER_FT[_step] * FT
	while d > 1.0:
		var x := c.x + _ladder_dir.x * d
		var z := c.z + _ladder_dir.y * d
		if terrain.surface_at(x, z) == Surface.Type.GREEN:
			return Vector3(x, terrain.height_at(x, z), z)
		d *= 0.85
	return pick_spot(c, LADDER_FT[_step] * FT, Slope.ANY)


## Scores the putt from `spot` that stopped at `rest` (or in the cup), moves
## the drill on and sets the next spot. Returns what to tell the player.
func record(rest: Vector3, was_holed: bool) -> String:
	var c := cup_position()
	var from := spot
	putts += 1
	var leave := Vector2(rest.x - c.x, rest.z - c.z).length()
	if was_holed:
		holed += 1
		leave = 0.0
	else:
		misses += 1
		miss_total_m += leave
	var how := "Holed!" if was_holed else miss_text(from, c, rest)
	match drill:
		Drill.CLOCK:
			if was_holed:
				_step += 1
				if _step >= CLOCK_BALLS:
					clock_best = CLOCK_BALLS
					_clock_turn = _rng.randf() * TAU
					_step = 0
					spot = _clock_spot()
					return "Holed! Around the clock: all %d in a row." % CLOCK_BALLS
				clock_best = maxi(clock_best, _step)
				spot = _clock_spot()
				return "Holed! %d of %d." % [_step, CLOCK_BALLS]
			var made := _step
			_step = 0
			spot = _clock_spot()
			return "%s\n%d in a row. Start again." % [how, made]
		Drill.LADDER:
			if leave <= LADDER_ZONE_FT * FT:
				_ladder_score += 1
			var rung := _step + 1
			_step += 1
			var score := _ladder_score
			if _step >= LADDER_FT.size():
				ladder_best = maxi(ladder_best, score)
				_restart_drill()
				return "%s\nLadder: %d of %d within %d ft (best %d)." % [how, score, LADDER_FT.size(), roundi(LADDER_ZONE_FT), ladder_best]
			spot = _ladder_spot()
			return "%s\nRung %d of %d: %d inside %d ft so far." % [how, rung, LADDER_FT.size(), score, roundi(LADDER_ZONE_FT)]
	# Free putting: the ball comes back to the same spot (the original's
	# Auto-Mulligan) until the player moves it.
	return "%s\n%s" % [how, tally()]


## "Holed 7 of 12 (58%), misses finish 1' 6" away on average".
func tally() -> String:
	if putts == 0:
		return "No putts yet"
	var text := "Holed %d of %d (%d%%)" % [holed, putts, roundi(100.0 * holed / putts)]
	if misses > 0:
		text += ", misses finish %s away on average" % GreenRead.length_text(miss_total_m / misses)
	return text


## "2' 4\" long, 3\" left" for a ball from `from` to the cup `c` that
## stopped at `rest`.
static func miss_text(from: Vector3, c: Vector3, rest: Vector3) -> String:
	var line := Vector2(c.x - from.x, c.z - from.z)
	var fwd := line.normalized() if line.length() > 1e-4 else Vector2(0, 1)
	var off := Vector2(rest.x - c.x, rest.z - c.z)
	var along := off.dot(fwd)
	var side := off.dot(GreenRead.left_of(fwd))
	var parts: Array[String] = []
	if absf(along) * 39.3701 >= 1.0:
		parts.append("%s %s" % [GreenRead.length_text(along), "long" if along > 0.0 else "short"])
	if absf(side) * 39.3701 >= 1.0:
		parts.append("%s %s" % [GreenRead.length_text(side), "left" if side > 0.0 else "right"])
	if parts.is_empty():
		return "Lipped out"
	return ", ".join(parts)


## The practice line for the HUD.
func status_text() -> String:
	var what := DRILL_NAMES[drill] as String
	match drill:
		Drill.FREE:
			what += "    %d ft    %s" % [DISTANCES_FT[distance_index], SLOPE_NAMES[slope]]
			if not slope_found:
				what += " (none here)"
		Drill.CLOCK:
			what += "    Ball %d of %d    Best %d" % [_step + 1, CLOCK_BALLS, clock_best]
		Drill.LADDER:
			what += "    %d ft (rung %d of %d)" % [roundi(LADDER_FT[mini(_step, LADDER_FT.size() - 1)]), _step + 1, LADDER_FT.size()]
	return "%s    Cup %d of %d\n%s" % [what, cup + 1, cups.size(), tally()]
