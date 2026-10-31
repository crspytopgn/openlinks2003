class_name CaddieAdvice
extends RefCounted
## The caddie's read of one shot (Settings > Caddie): the yardage, what it
## plays like, the club and, on the green, the break and pace. The plan
## behind it is the tour-level computer golfer's (ComputerGolfer), run
## through the round's own physics, wind and course, so the caddie never
## knows less than the game does. How much of that it says follows the
## swing skill setting (detail_for_skill): the easier levels hear the line
## and the break to the inch, Links 2003's hardest only the numbers a real
## caddie reads off the yardage book, so the caddie doesn't make the hard
## levels easier than the original.
##
## Planning runs in small steps (step) so the browser build never stalls.

enum Detail { FULL, STANDARD, SPARSE }

const YARDS_PER_METRE := 1.0936133
const FEET_PER_METRE := 3.2808399
const MPS_PER_MPH := 0.44704
const PLANNER_SEED := 2003
const TAP_IN_M := 0.9  ## "knock it in"
const ROUGH_LIES := [Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH]

var detail: int = Detail.FULL
## What the caddie says, once is_ready().
var text := ""
## The plan, once is_ready(): the club, power and line it would play.
var club_index := 0
var power := 1.0
var aim_deg := 0.0

var _cpu: ComputerGolfer
var _clubs: Array[Club] = []
var _hole: HoleData
var _from := Vector3.ZERO
var _lie: int = Surface.Type.FAIRWAY
var _wind := Vector3.ZERO
var _ready := false


## Skill levels 0 and 1 hear everything, 2 the side to favour and the size
## of the break in words, 3 (Links 2003's hardest) the numbers only.
static func detail_for_skill(skill: int) -> int:
	const BY_SKILL := [Detail.FULL, Detail.FULL, Detail.STANDARD, Detail.SPARSE]
	return BY_SKILL[clampi(skill, 0, BY_SKILL.size() - 1)]


## Starts reading a shot from `from` on `lie`, with `wind` the wind's
## velocity for this shot.
func start(model: ShotModel, clubs: Array[Club], hole: HoleData, from: Vector3, lie: int, wind: Vector3, skill: int) -> void:
	detail = detail_for_skill(skill)
	_clubs = clubs
	_hole = hole
	_from = from
	_lie = lie
	_wind = wind
	_ready = false
	text = ""
	if _flat(from, hole.pin) < TAP_IN_M and _is_putting_lie(lie, _flat(from, hole.pin)):
		club_index = clubs.size() - 1
		_ready = true
		text = "That's a tap-in. Knock it in."
		return
	_cpu = ComputerGolfer.new(OpponentSkill.Level.TOUR, PLANNER_SEED)
	_cpu.plan(model, clubs, hole, from, lie, wind)


## Plans for about `budget_ms`; true once the advice is ready.
func step(budget_ms := 4.0) -> bool:
	if _ready:
		return true
	if _cpu == null or not _cpu.step(budget_ms):
		return false
	club_index = _cpu.club_index
	power = _cpu.power
	aim_deg = _cpu.aim_deg
	_cpu = null
	_ready = true
	text = _compose()
	return true


func finish() -> void:
	while not step(1e9):
		if _cpu == null:
			return


func is_ready() -> bool:
	return _ready


func _compose() -> String:
	var club := _clubs[club_index]
	var dist := _flat(_from, _hole.pin)
	var heading := rad_to_deg(atan2(_hole.pin.x - _from.x, _hole.pin.z - _from.z))
	var aim_off := dist * tan(deg_to_rad(clampf(wrapf(aim_deg - heading, -180.0, 180.0), -60.0, 60.0)))
	if club.is_putter:
		return putt_text(detail, dist, _hole.pin.y - _from.y, aim_off)
	var dir := Vector3(sin(deg_to_rad(heading)), 0.0, cos(deg_to_rad(heading)))
	var left := Vector3.UP.cross(dir)
	var reach := club.total_m * Surface.lie_power(_lie)
	# With the pin in range, a caddie names the club that gets there with a
	# full swing for what the shot plays like, not the planner's soft long
	# club; the planner's line still stands.
	var plays := plays_like_m(dist, _hole.pin.y - _from.y, _wind.dot(dir))
	var full := club_for(_clubs, plays, _lie)
	if full >= 0 and dist <= _clubs[0].total_m * Surface.lie_power(_lie):
		club_index = full
		club = _clubs[full]
		power = 1.0
		reach = club.total_m * Surface.lie_power(_lie)
	return shot_text(detail, {
		"to_pin_m": dist, "rise_m": _hole.pin.y - _from.y,
		"wind_along_mps": _wind.dot(dir), "wind_cross_mps": _wind.dot(left),
		"club": club.full_name, "power": power, "aim_off_m": aim_off,
		"in_range": dist <= reach * 1.08, "lie": _lie, "par": _hole.par,
		"tee": _lie == Surface.Type.TEE,
	})


## The shortest club whose full swing from `lie` reaches `plays_m`, or -1.
static func club_for(clubs: Array[Club], plays_m: float, lie: int) -> int:
	var best := -1
	for i in clubs.size():
		if not clubs[i].is_putter and clubs[i].total_m * Surface.lie_power(lie) >= plays_m:
			best = i
	return best


## What a shot of `distance_m` plays like, with the pin `rise_m` above the
## ball and `wind_along_mps` of wind down the line (negative: into the
## face). The caddie's rules of thumb: a yard per yard of rise, one per cent
## per mph into the wind and half that helping.
static func plays_like_m(distance_m: float, rise_m: float, wind_along_mps: float) -> float:
	var mph := wind_along_mps / MPS_PER_MPH
	var factor := -0.005 * mph if mph > 0.0 else -0.01 * mph
	return distance_m * (1.0 + factor) + rise_m


## A full shot's advice. `info` keys: to_pin_m, rise_m, wind_along_mps,
## wind_cross_mps (+ blows towards the golfer's left), club (its name),
## power (0..1), aim_off_m (+ left of the pin), in_range (the pin is within
## the club's reach), lie (Surface.Type), par, tee.
static func shot_text(level: int, info: Dictionary) -> String:
	var parts := PackedStringArray()
	var yards := roundi(float(info.to_pin_m) * YARDS_PER_METRE)
	var first := "%d to the pin" % yards
	if bool(info.in_range):
		var plays := roundi(plays_like_m(info.to_pin_m, info.rise_m, info.wind_along_mps) * YARDS_PER_METRE)
		if absi(plays - yards) >= 3:
			first += ", playing %d %s" % [plays, _why(info)]
	elif bool(info.get("tee", false)) and int(info.get("par", 0)) >= 4:
		first += ", par %d" % int(info.par)
	parts.append(first + ".")
	var lie: int = info.get("lie", Surface.Type.FAIRWAY)
	var club_words := _club_words(str(info.club), float(info.power))
	if lie == Surface.Type.SAND:
		club_words = "Out of the sand, " + club_words.to_lower()
	elif ROUGH_LIES.has(lie):
		club_words = "It'll come out heavy from there. " + club_words
	parts.append(club_words + ".")
	if level == Detail.SPARSE:
		return " ".join(parts)
	var off_yd := float(info.aim_off_m) * YARDS_PER_METRE
	var cross_mph := absf(float(info.wind_cross_mps)) / MPS_PER_MPH
	var for_wind := " for the wind" if cross_mph >= 4.0 else ""
	if absf(off_yd) >= 2.0:
		var side := "left" if off_yd > 0.0 else "right"
		if level == Detail.FULL:
			parts.append("Start it %d yards %s%s." % [roundi(absf(off_yd)), side, for_wind])
		else:
			parts.append("Favour the %s side%s." % [side, for_wind])
	elif bool(info.in_range) and level == Detail.FULL:
		parts.append("Straight at the flag.")
	return " ".join(parts)


## A putt's advice: `distance_m` to the hole, the hole `rise_m` above the
## ball, and `aim_off_m` how far left (+) or right of the hole to start it.
static func putt_text(level: int, distance_m: float, rise_m: float, aim_off_m: float) -> String:
	if distance_m < TAP_IN_M:
		return "That's a tap-in. Knock it in."
	var parts := PackedStringArray()
	var feet := roundi(distance_m * FEET_PER_METRE)
	var pct := rise_m / maxf(distance_m, 0.1) * 100.0
	var slope := "fairly flat"
	if pct >= 2.0:
		slope = "uphill"
	elif pct >= 0.5:
		slope = "slightly uphill"
	elif pct <= -2.0:
		slope = "downhill"
	elif pct <= -0.5:
		slope = "slightly downhill"
	parts.append("%d feet, %s." % [feet, slope])
	var inches := absf(aim_off_m) * 39.3701
	# Starting it left of the hole means it breaks back to the right.
	var way := "left to right" if aim_off_m > 0.0 else "right to left"
	match level:
		Detail.FULL:
			if inches < 2.0:
				parts.append("Inside the hole, it's straight.")
			else:
				parts.append("Breaks %s, start it %s of the hole." % [way, PuttRead.aim_text(aim_off_m)])
		Detail.STANDARD:
			if inches < 2.0:
				parts.append("Looks straight.")
			else:
				var size := "a touch"
				if inches >= 18.0:
					size = "a lot"
				elif inches >= 6.0:
					size = "a fair bit"
				parts.append("Breaks %s %s." % [size, way])
		_:
			parts.append("Looks straight." if inches < 4.0 else "Breaks %s." % way)
	if level != Detail.SPARSE:
		if pct >= 1.5:
			parts.append("Be firm with it.")
		elif pct <= -1.5:
			parts.append("Just get it rolling.")
	return " ".join(parts)


## Why it plays longer or shorter: the bigger of the slope and the wind.
static func _why(info: Dictionary) -> String:
	var rise_yd := float(info.rise_m) * YARDS_PER_METRE
	var dist := float(info.to_pin_m)
	var wind_yd := (plays_like_m(dist, 0.0, info.wind_along_mps) - dist) * YARDS_PER_METRE
	if absf(rise_yd) >= absf(wind_yd):
		return "uphill" if rise_yd > 0.0 else "downhill"
	return "into the wind" if wind_yd > 0.0 else "downwind"


static func _club_words(club_name: String, p: float) -> String:
	if p >= 0.93:
		return club_name
	if p >= 0.8:
		return "Smooth " + club_name.to_lower()
	if p >= 0.6:
		return "Three-quarter " + club_name.to_lower()
	return "Half " + club_name.to_lower()


static func _is_putting_lie(lie: int, to_pin: float) -> bool:
	return lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
