class_name ComputerGolfer
extends RefCounted
## A computer opponent. It plans each shot by trying clubs, aims and power
## through the round's own ShotModel (the same physics, wind and course the
## player gets), scores where each try ends up with
## OpponentSkill.expected_strokes, and then swings the best one with the
## mistakes of its level (OpponentSkill.execute).
##
## Planning is split into small jobs so the round can spread it over a few
## frames (step) and the web build never stalls; finish() runs it all at once.

const MIN_POWER := 0.12  ## softest full swing it plans
const PUTT_TRIES := 8
const PUTT_PAST_M := 0.35  ## putts are paced to stop this far past the cup
const RISK_CANDIDATES := 3  ## best plans re-tried with likely misses

var skill: OpponentSkill
var rng: OpponentSkill.Rng

## The chosen shot, valid once planning is done.
var club_index := 0
var power := 1.0
var aim_deg := 0.0
var expected := 0.0  ## strokes still to play after the planned shot

var _model: ShotModel
var _clubs: Array[Club] = []
var _hole: HoleData
var _from := Vector3.ZERO
var _lie: int = Surface.Type.FAIRWAY
var _wind := Vector3.ZERO
var _jobs: Array[Callable] = []
var _candidates: Array[Candidate] = []
var _best_putt: Candidate


class Candidate:
	var club := 0
	var power := 1.0
	var aim_deg := 0.0
	var score := INF  ## expected strokes after the shot
	var nominal := INF


## `seed_value` 0 picks a random seed.
func _init(level: int, seed_value := 0) -> void:
	skill = OpponentSkill.new(level)
	if seed_value == 0:
		seed_value = randi() | 1
	rng = OpponentSkill.Rng.new(seed_value)


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
	var to_pin := _flat(from, hole.pin)
	if lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0):
		var putter := clubs.size() - 1
		var c := Candidate.new()
		c.club = putter
		c.aim_deg = _heading(from, hole.pin)
		var rr := Surface.rolling_resistance(Surface.Type.GREEN)
		var v := sqrt(2.0 * rr * BallPhysics.GRAVITY * (to_pin + PUTT_PAST_M))
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
		_jobs.append(_job_club.bind(i))
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


## The swing the computer actually makes: the plan plus its level's mistakes.
## Returns [power, accuracy, aim_deg].
func swing() -> PackedFloat64Array:
	return skill.execute(power, 0.0, aim_deg, is_putt(), rng)


# --- Jobs --------------------------------------------------------------------

## A club: aim at the pin if it is in range (with the power to get there) or
## down the hole's route, then correct once or twice for wind and curve.
func _job_club(i: int) -> void:
	var reach := _reach(i)
	var target := _hole.aim_point(_from, reach)
	var to_target := _flat(_from, target)
	var at_pin := target.is_equal_approx(_hole.pin)
	var c := Candidate.new()
	c.club = i
	c.aim_deg = _heading(_from, target)
	c.power = skill.strength
	if at_pin:
		c.power = clampf(skill.strength * to_target / reach, MIN_POWER, skill.strength)
	var r := _simulate(c.club, c.power, c.aim_deg)
	for attempt in 2:
		var rest := r.rest if r.outcome != ShotResult.Outcome.HOLED else _hole.pin
		var travelled := _flat(_from, rest)
		if travelled > 1.0:
			c.aim_deg += wrapf(_heading(_from, target) - _heading(_from, rest), -180.0, 180.0)
		if at_pin and travelled > 1.0:
			c.power = clampf(c.power * to_target / travelled, MIN_POWER, skill.strength)
		elif attempt > 0:
			break
		r = _simulate(c.club, c.power, c.aim_deg)
	c.nominal = _value(r)
	c.score = c.nominal
	_candidates.append(c)


## Picks the best plan. A golfer with course management first re-plays the
## best few with a likely miss either way, long and short, and goes with the
## best average, so it stays away from water and bunkers.
func _job_rank() -> void:
	if _candidates.is_empty():
		_choose_fallback()
		return
	_candidates.sort_custom(func(a: Candidate, b: Candidate) -> bool: return a.nominal < b.nominal)
	if skill.course_management:
		for k in mini(RISK_CANDIDATES, _candidates.size()):
			_jobs.append(_job_risk.bind(_candidates[k]))
	_jobs.append(_job_choose)


func _job_risk(c: Candidate) -> void:
	var acc := skill.accuracy_sd
	var aim := skill.aim_sd_deg
	var pw := 1.5 * skill.power_sd
	var total := c.nominal
	# Pulled and hooked, then pushed and sliced.
	total += _value(_simulate(c.club, c.power, c.aim_deg + aim, -acc))
	total += _value(_simulate(c.club, c.power, c.aim_deg - aim, acc))
	total += _value(_simulate(c.club, c.power * (1.0 - pw), c.aim_deg))
	total += _value(_simulate(c.club, minf(c.power * (1.0 + pw), 1.0), c.aim_deg))
	c.score = total / 5.0


## The best of the plans weighed alike: only the re-tried ones when there
## was a risk check, since a single try flatters a plan.
func _job_choose() -> void:
	var count := mini(RISK_CANDIDATES, _candidates.size()) if skill.course_management else _candidates.size()
	var best: Candidate = null
	for k in count:
		var c := _candidates[k]
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
	if r.outcome == ShotResult.Outcome.HOLED or attempt + 1 >= PUTT_TRIES:
		_use(_best_putt)
		return
	var pin := _hole.pin
	var want := _flat(_from, pin) + PUTT_PAST_M
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
	expected = c.score


## No club made sense (it shouldn't happen): a soft wedge at the pin.
func _choose_fallback() -> void:
	var c := Candidate.new()
	c.club = maxi(0, _clubs.size() - 2)
	c.power = 0.5
	c.aim_deg = _heading(_from, _hole.pin)
	_use(c)


func _simulate(club: int, p: float, aim: float, accuracy := 0.0) -> ShotResult:
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
	return maxf(1.0, _clubs[i].total_m * Surface.lie_power(_lie) * skill.strength)


static func _heading(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, to.z - from.z))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
