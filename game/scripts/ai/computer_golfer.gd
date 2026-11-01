class_name ComputerGolfer
extends RefCounted
## A computer opponent. It plans each shot by trying clubs, aims and power
## through the round's own ShotModel (the same physics, wind and course the
## player gets), scores where each try ends up with
## OpponentSkill.expected_strokes, and then swings the best one with its own
## mistakes (OpponentSkill.execute), calibrated to real-world numbers.
##
## Who it is (TourPro) decides how it plays: its shot shape, how hard it
## attacks flags and putts, how carefully it weighs its misses, and how its
## form and nerve move its mistakes up and down during a round.
##
## Planning is split into small jobs so the round can spread it over a few
## frames (step) and the web build never stalls; finish() runs it all at once.

const MIN_POWER := 0.12  ## softest full swing it plans
const PUTT_TRIES := 8
## Putts are paced to stop this far past the cup: from dying it in (no
## aggression) to charging it.
const PUTT_PAST_MIN_M := 0.2
const PUTT_PAST_MAX_M := 0.55
const MAX_RISK_CANDIDATES := 4  ## best plans re-tried with likely misses
const SHORT_GAME_M := 45.0  ## inside this, wedges also try lines either side
const SHORT_GAME_OFFSETS_DEG := [-25.0, -10.0, 10.0, 25.0]
## From a bad lie in the short game, wedges also try going this much past the
## flag, so the risk check can choose to make sure of getting out and on.
const SHORT_GAME_PAST_M := [2.5, 5.0]
## Plans re-tried with likely misses from a bad lie in the short game, on top
## of the golfer's own number.
const SHORT_GAME_EXTRA_RISK := 3
## A short-game plan that still finishes this far from the pin also tries
## these multiples of its power, then these aim changes, and keeps the best:
## a slope or a bank can make the finish jump as the power changes.
const SHORT_GAME_SCAN_FROM_M := 1.5
const SHORT_GAME_POWER_SCAN := [0.7, 0.8, 0.9, 1.1, 1.2, 1.35, 1.5]
const SHORT_GAME_AIM_SCAN_DEG := [-6.0, -3.0, 3.0, 6.0]
## Timing (OpponentSkill accuracy) of a full shape (TourPro.shape = +/-1):
## positive fades, negative draws.
const SHAPE_ACCURACY := 0.1
## Below this TourPro.aggression a golfer also looks at a line halfway to the
## middle of the green.
const SAFE_LINE_BELOW := 0.6

var skill: OpponentSkill
var rng: OpponentSkill.Rng
var pro: TourPro
## Classic computer golfers: with Links 2003's physics the game's own miss
## generators make the mistakes (the game shell sets it).
var classic := false
## How tense the moment is, 0 to 1 (the game shell sets it before each shot).
var pressure := 0.0
## This round's form: multiplies its mistakes (start_round).
var form := 1.0
## Recent holes: up after birdies, down after bogeys (end_hole).
var momentum := 0.0

## The chosen shot, valid once planning is done.
var club_index := 0
var power := 1.0
var aim_deg := 0.0
var accuracy := 0.0  ## the shape it means to play
var expected := 0.0  ## strokes still to play after the planned shot
## Where the planned shot finishes if struck perfectly: metres from the pin
## (for the shot log, next to where it really went).
var planned_left := 0.0
var last_error_scale := 1.0  ## the error scale of the last swing()

var _model: ShotModel
var _clubs: Array[Club] = []
var _hole: HoleData
var _from := Vector3.ZERO
var _lie: int = Surface.Type.FAIRWAY
var _wind := Vector3.ZERO
var _teed_up := false
var _jobs: Array[Callable] = []
var _candidates: Array[Candidate] = []
var _best_putt: Candidate


class Candidate:
	var club := 0
	var power := 1.0
	var aim_deg := 0.0
	var accuracy := 0.0  ## the shot's shape
	var score := INF  ## expected strokes after the shot
	var nominal := INF
	var left := 0.0  ## metres from the pin, struck perfectly
	var sure := false  ## played past the pin to make sure of getting out
	var checked := false  ## re-tried with likely misses


## `seed_value` 0 picks a random seed. Without `p_pro` it is a typical
## golfer of `level` with a style of its own.
func _init(level: int, seed_value := 0, p_pro: TourPro = null) -> void:
	if seed_value == 0:
		seed_value = randi() | 1
	pro = p_pro if p_pro != null else TourPro.for_level(level, seed_value)
	skill = pro.skill(level)
	rng = OpponentSkill.Rng.new(seed_value)


## A new round: how well it is playing today.
func start_round() -> void:
	form = exp(rng.normal() * (0.05 + 0.12 * pro.streaky))
	momentum = 0.0


## A hole finished `to_par` (-1 a birdie, +1 a bogey).
func end_hole(to_par: int) -> void:
	momentum = clampf(0.6 * momentum - clampf(float(to_par), -2.0, 2.0), -2.5, 2.0)


## Multiplies its mistakes now: today's form, recent holes (more for a
## streaky golfer) and pressure, which a nervy golfer feels and a clutch one
## thrives on.
func error_scale() -> float:
	var k := form * (1.0 - 0.06 * pro.streaky * momentum) * (1.0 - 0.3 * pressure * pro.nerve)
	return clampf(k, 0.55, 1.8)


## Its pre-shot routine in game seconds (the real one, quicker): planning,
## then standing over the ball.
func think_time() -> float:
	return clampf(0.35 + 0.018 * pro.routine_s, 0.5, 1.6)


func address_time() -> float:
	return clampf(0.5 + 0.03 * pro.routine_s, 0.9, 2.4)


## Starts planning a shot from `from` on `lie`.
func plan(model: ShotModel, clubs: Array[Club], hole: HoleData, from: Vector3, lie: int, wind: Vector3) -> void:
	_model = model
	_clubs = clubs
	_hole = hole
	_from = from
	_lie = lie
	_wind = wind
	_jobs.clear()
	_candidates.clear()
	_best_putt = null
	_teed_up = lie == Surface.Type.TEE
	var to_pin := _flat(from, hole.pin)
	if lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0):
		var putter := clubs.size() - 1
		var c := Candidate.new()
		c.club = putter
		c.aim_deg = _heading(from, hole.pin)
		var rr := Surface.rolling_resistance(Surface.Type.GREEN)
		var v := sqrt(2.0 * rr * BallPhysics.GRAVITY * (to_pin + _putt_past()))
		c.power = clampf(v / clubs[putter].ball_speed_mps, 0.02, 1.0)
		_jobs.append(_job_putt.bind(c, 0))
		return
	var reach_max := _reach(0)
	for i in clubs.size():
		if clubs[i].is_putter:
			continue
		var reach := _reach(i)
		var lofted := i >= clubs.size() - 3  # the wedges are always worth a look
		if not lofted and (to_pin < reach * 0.3 or reach < 0.4 * minf(to_pin, reach_max)):
			continue
		_jobs.append(_job_club.bind(i, 0.0, false))
		# Round a tree or past a bank: a short game shot may need another line.
		if lofted and to_pin < SHORT_GAME_M:
			for offset: float in SHORT_GAME_OFFSETS_DEG:
				_jobs.append(_job_club.bind(i, offset, false))
			if _bad_lie():
				for past: float in SHORT_GAME_PAST_M:
					_jobs.append(_job_club.bind(i, 0.0, false, past))
		# A careful golfer also looks at the safe side of the flag.
		elif pro.aggression < SAFE_LINE_BELOW and to_pin < reach * 1.05 and to_pin > SHORT_GAME_M:
			_jobs.append(_job_club.bind(i, 0.0, true))
	_jobs.append(_job_rank)


## Runs planning jobs for about `budget_ms`; true once the plan is ready.
func step(budget_ms := 6.0) -> bool:
	var start := Time.get_ticks_usec()
	while not _jobs.is_empty():
		var job: Callable = _jobs.pop_front()
		job.call()
		if Time.get_ticks_usec() - start > budget_ms * 1000.0:
			break
	return _jobs.is_empty()


func finish() -> void:
	while not step(1e9):
		pass


func is_putt() -> bool:
	return _clubs[club_index].is_putter


## The kind of shot planned (OpponentSkill.Kind).
func kind() -> int:
	return OpponentSkill.kind_of(is_putt(), _teed_up, _is_wood(_clubs[club_index]), _flat(_from, _hole.pin))


## The swing the computer actually makes: the plan plus its own mistakes.
## Returns [power, accuracy, aim_deg].
func swing() -> PackedFloat64Array:
	var k := kind()
	var scale := error_scale()
	if _model is LinksShotModel:
		scale *= OpponentSkill.LINKS_ERROR_SCALE[k]
	last_error_scale = scale
	return skill.execute(power, accuracy, aim_deg, k, scale, rng)


# --- Jobs --------------------------------------------------------------------

## A club: aim at the pin if it is in range (with the power to get there) or
## down the hole's route, then correct for wind, curve and slopes. A nonzero
## `offset_deg` starts the line that far off the target (short game only) and
## corrects only the power, to find a way round trees or up a bank. A
## nonzero `past_m` plays to stop that far beyond the pin.
func _job_club(i: int, offset_deg: float, safe: bool, past_m := 0.0) -> void:
	var reach := _reach(i)
	var target := _hole.aim_point(_from, reach)
	var at_pin := target.is_equal_approx(_hole.pin)
	if safe:
		if not at_pin:
			return
		var centre := _green_centre()
		if _flat(centre, _hole.pin) < 3.0:
			return
		target = _hole.pin.lerp(centre, 0.5)
	if past_m > 0.0 and at_pin:
		var line := Vector3(target.x - _from.x, 0.0, target.z - _from.z)
		if line.length() > 0.5:
			target += line.normalized() * past_m
	var to_target := _flat(_from, target)
	var top := _strength()
	var c := Candidate.new()
	c.club = i
	c.sure = past_m > 0.0
	c.accuracy = _shape(i)
	c.aim_deg = _heading(_from, target) + offset_deg
	c.power = top
	if at_pin:
		c.power = clampf(top * to_target / reach, MIN_POWER, top)
	var r := _simulate(c.club, c.power, c.aim_deg, c.accuracy)
	var best_r := r
	var best_power := c.power
	var best_aim := c.aim_deg
	for attempt in (3 if at_pin else 2):
		var rest := r.rest if r.outcome != ShotResult.Outcome.HOLED else _hole.pin
		if r.outcome == ShotResult.Outcome.HOLED:
			break
		# Progress towards the target: a ball that comes back down a bank or
		# off a tree has made little or none, so hit it harder.
		var progress := _flat(_from, rest) * cos(deg_to_rad(_heading(_from, rest) - _heading(_from, target)))
		if offset_deg == 0.0 and progress > 1.0:
			c.aim_deg += wrapf(_heading(_from, target) - _heading(_from, rest), -180.0, 180.0)
		if not at_pin:
			if attempt > 0:
				break
		elif progress > 1.0:
			c.power = clampf(c.power * minf(to_target / progress, 3.0), MIN_POWER, top)
		else:
			c.power = minf(c.power * 2.0, top)
		r = _simulate(c.club, c.power, c.aim_deg, c.accuracy)
		# Keep the best try: a correction can overshoot.
		if _value(r) < _value(best_r):
			best_r = r
			best_power = c.power
			best_aim = c.aim_deg
	if at_pin and offset_deg == 0.0 and _flat(_from, _hole.pin) < SHORT_GAME_M and _left(best_r) > SHORT_GAME_SCAN_FROM_M:
		var base := best_power
		for f: float in SHORT_GAME_POWER_SCAN:
			var p := clampf(base * f, MIN_POWER, top)
			var t := _simulate(c.club, p, best_aim, c.accuracy)
			if _value(t) < _value(best_r):
				best_r = t
				best_power = p
		var aim0 := best_aim
		for d: float in SHORT_GAME_AIM_SCAN_DEG:
			var t := _simulate(c.club, best_power, aim0 + d, c.accuracy)
			if _value(t) < _value(best_r):
				best_r = t
				best_aim = aim0 + d
	c.power = best_power
	c.aim_deg = best_aim
	c.nominal = _value(best_r)
	c.score = c.nominal
	c.left = _left(best_r)
	_candidates.append(c)


## Metres from the pin a result finishes (0 when holed).
func _left(r: ShotResult) -> float:
	return 0.0 if r.outcome == ShotResult.Outcome.HOLED else _flat(r.rest, _hole.pin)


## Picks the best plan. A golfer with course management first re-plays the
## best few with a likely miss either way, long and short, and goes with the
## best average, so it stays away from water and bunkers.
func _job_rank() -> void:
	if _candidates.is_empty():
		_choose_fallback()
		return
	_candidates.sort_custom(func(a: Candidate, b: Candidate) -> bool: return a.nominal < b.nominal)
	if _manages():
		var n := _risk_candidates()
		for k in _candidates.size():
			var c := _candidates[k]
			# The sure plans always get a fair look, even if a perfect strike
			# of another one would finish closer.
			if k < n or c.sure:
				c.checked = true
				_jobs.append(_job_risk.bind(c))
	_jobs.append(_job_choose)


## A plan's likely misses: pulled and hooked, pushed and sliced, short and
## long, by this golfer's own errors for the shot. An aggressive golfer
## gives them less weight than the shot it means to hit.
func _job_risk(c: Candidate) -> void:
	var e: PackedFloat64Array = skill.shots[OpponentSkill.kind_of(false, _teed_up, _is_wood(_clubs[c.club]), _flat(_from, _hole.pin))]
	var k := error_scale()
	var acc := e[1] * k
	var aim := e[2] * k
	var pw := 1.5 * e[0] * k
	var misses := 0.0
	misses += _value(_simulate(c.club, c.power, c.aim_deg + aim, c.accuracy - acc))
	misses += _value(_simulate(c.club, c.power, c.aim_deg - aim, c.accuracy + acc))
	misses += _value(_simulate(c.club, c.power * (1.0 - pw), c.aim_deg, c.accuracy))
	misses += _value(_simulate(c.club, minf(c.power * (1.0 + pw), 1.0), c.aim_deg, c.accuracy))
	var weight := 1.25 - pro.aggression  # each miss against the plan itself
	c.score = (c.nominal + weight * misses) / (1.0 + 4.0 * weight)


## The best of the plans weighed alike: only the re-tried ones when there
## was a risk check, since a single try flatters a plan.
func _job_choose() -> void:
	var managed := _manages()
	var best: Candidate = null
	for c in _candidates:
		if managed and not c.checked:
			continue
		if best == null or c.score < best.score:
			best = c
	_use(best)


## Putts: aim and pace at the hole, then read the green from where the ball
## stops and try again, keeping the best.
func _job_putt(c: Candidate, attempt: int) -> void:
	var r := _simulate(c.club, c.power, c.aim_deg)
	c.score = _value(r)
	if _best_putt == null or c.score < _best_putt.score:
		_best_putt = Candidate.new()
		_best_putt.club = c.club
		_best_putt.power = c.power
		_best_putt.aim_deg = c.aim_deg
		_best_putt.score = c.score
		_best_putt.left = 0.0 if r.outcome == ShotResult.Outcome.HOLED else _flat(r.rest, _hole.pin)
	if r.outcome == ShotResult.Outcome.HOLED or attempt + 1 >= PUTT_TRIES:
		_use(_best_putt)
		return
	var pin := _hole.pin
	var want := _flat(_from, pin) + _putt_past()
	var travelled := _flat(_from, r.rest)
	if travelled > 0.05:
		c.aim_deg += wrapf(_heading(_from, pin) - _heading(_from, r.rest), -180.0, 180.0)
		# Distance goes with the square of the speed.
		c.power = clampf(c.power * sqrt(want / travelled), 0.02, 1.0)
	else:
		c.power = minf(c.power * 2.0, 1.0)
	_jobs.append(_job_putt.bind(c, attempt + 1))


# --- Helpers -----------------------------------------------------------------

func _use(c: Candidate) -> void:
	club_index = c.club
	power = c.power
	aim_deg = c.aim_deg
	accuracy = c.accuracy
	expected = c.score
	planned_left = c.left


func _manages() -> bool:
	return skill.course_management and pro.management >= 0.15


func _risk_candidates() -> int:
	var n := clampi(roundi(1.0 + 3.0 * pro.management), 1, MAX_RISK_CANDIDATES)
	if _bad_lie() and _flat(_from, _hole.pin) < SHORT_GAME_M:
		n += SHORT_GAME_EXTRA_RISK
	return n


## Sand or rough, where a short shot comes off the face less predictably.
func _bad_lie() -> bool:
	return _lie == Surface.Type.SAND or _lie == Surface.Type.ROUGH or _lie == Surface.Type.DEEP_ROUGH


func _putt_past() -> float:
	return lerpf(PUTT_PAST_MIN_M, PUTT_PAST_MAX_M, clampf(pro.aggression, 0.0, 1.0))


## The shape it plays with club `i`: none for chips and pitches.
func _shape(i: int) -> float:
	if _clubs[i].is_putter or _flat(_from, _hole.pin) < OpponentSkill.CHIP_RANGE_M:
		return 0.0
	return clampf(pro.shape, -1.0, 1.0) * SHAPE_ACCURACY


## The most power it swings with, for the physics in use.
func _strength() -> float:
	return skill.links_strength if _model is LinksShotModel else skill.strength


## The middle of the green: where the hole's pin positions average out.
func _green_centre() -> Vector3:
	if _hole.pins.size() < 2:
		return _hole.pin
	var sum := Vector3.ZERO
	for p in _hole.pins:
		sum += p
	return sum / _hole.pins.size()


## No club made sense (it shouldn't happen): a soft wedge at the pin.
func _choose_fallback() -> void:
	var c := Candidate.new()
	c.club = maxi(0, _clubs.size() - 2)
	c.power = 0.5
	c.aim_deg = _heading(_from, _hole.pin)
	_use(c)


func _simulate(club: int, p: float, aim: float, accuracy := 0.0) -> ShotResult:
	if _model is LinksShotModel:
		(_model as LinksShotModel).computer = true  # plan without the human miss model
		(_model as LinksShotModel).computer_ratings = null  # nor the computer's own
	var start := _model.launch(_clubs[club], p, accuracy, aim, _lie, _from)
	return _model.simulate(start, _hole.terrain, _hole.pin, _wind)


## Strokes still to play after a shot that ends as `r`.
func _value(r: ShotResult) -> float:
	var pin := _hole.pin
	match r.outcome:
		ShotResult.Outcome.HOLED:
			return 0.0
		ShotResult.Outcome.WATER:
			return 1.0 + OpponentSkill.expected_strokes(_flat(r.rest, pin), Surface.Type.ROUGH)
		ShotResult.Outcome.OUT_OF_BOUNDS:
			return 1.0 + OpponentSkill.expected_strokes(_flat(_from, pin), _lie)
	var s := _hole.terrain.surface_at(r.rest.x, r.rest.z)
	if s == Surface.Type.WATER or s == Surface.Type.OUT_OF_BOUNDS:
		return 1.0 + OpponentSkill.expected_strokes(_flat(_from, pin), _lie)
	return OpponentSkill.expected_strokes(_flat(r.rest, pin), s)


## Full-power total distance with club `i` from this lie, at this golfer's
## strength.
func _reach(i: int) -> float:
	return maxf(1.0, _clubs[i].total_m * _model.reach_scale(_clubs[i]) * Surface.lie_power(_lie) * _strength())


## The driver and fairway woods: from the tee they are drives.
static func _is_wood(c: Club) -> bool:
	return c.short_name == "Dr" or (c.short_name.length() == 2 and c.short_name.ends_with("W") and c.short_name.left(1).is_valid_int())


static func _heading(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, to.z - from.z))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
