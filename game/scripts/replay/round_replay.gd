class_name RoundReplay
extends RefCounted
## Plays a RoundRecord again through a ShotModel and checks it: the wind drawn
## from the round seed, each shot's stopping point and, in stroke play, every
## card. GolfRound plays its shots through run_shot too, so a live shot and
## its replay take the same path. See docs/online-play.md.

## How far a replayed ball may stop from the recorded one, metres. Desktop and
## the browser build can round a few maths functions differently; each shot
## starts from its recorded spot, so the difference never adds up.
const REST_TOLERANCE_M := 0.05
const WIND_TOLERANCE := 1e-3
const INPUT_TOLERANCE := 1e-6


## Launches and flies a shot from its record. Sets the LinksShotModel up the
## way GolfRound does and gives it the shot's own random draws.
static func run_shot(model: ShotModel, r: ShotRecord, club: Club, terrain: CourseTerrain, pin: Vector3, wind: Vector3, round_seed: int) -> ShotResult:
	if model is LinksShotModel:
		var links := model as LinksShotModel
		links.skill = r.skill
		links.computer = r.computer
		links.computer_ratings = null
		if r.computer and r.cpu_rating >= 0:
			links.computer_ratings = LinksLaunch.GolferRatings.even(r.cpu_rating)
			links.to_hole_m = r.to_hole_m
		links.chip = r.chip
		links.mouse_swing = null
		if not r.computer and r.stroke != null:
			links.mouse_swing = mouse_outcome(r.stroke, round_seed, r.index, copy_help(r.help))
		links.rng = LinksLaunch.Rand.new(RoundRecord.shot_seed(round_seed, r.index, RoundRecord.SALT_MODEL))
	model.setup = r.setup()
	var start := monitor_launch(r, club, model) if not r.monitor.is_empty() \
			else model.launch(club, r.power, r.accuracy, r.aim_deg, r.lie, r.from)
	# Back to square, so planners (computer golfers, the caddie) see plain shots.
	model.setup = LinksLaunch.Setup.new()
	var result := model.simulate(start, terrain, pin, wind)
	result.launch = start
	return result


## A launch monitor's shot as measured, with the lie's loss of speed and
## spin (rough, sand) as the swing would have.
static func monitor_launch(r: ShotRecord, club: Club, model: ShotModel) -> BallState:
	var l := OpenConnect.Launch.from_array(r.monitor)
	if not club.is_putter:
		l.speed_mph *= Surface.lie_power(r.lie)
		l.total_rpm *= Surface.lie_spin(r.lie)
	else:
		l.vla_deg = 0.0
	var b := OpenConnect.ball_state(l, r.aim_deg)
	b.position = r.from
	b.on_ground = club.is_putter and model is LinksShotModel
	return b


## The PowerStroke mouse swing of shot `index`, with that shot's draws.
## `help` is counted on, as in the game.
static func mouse_outcome(stroke: LinksMouse.Stroke, round_seed: int, index: int, help: LinksMouse.Help = null) -> LinksMouse.Outcome:
	return LinksMouse.swing(stroke, LinksLaunch.Rand.new(RoundRecord.shot_seed(round_seed, index, RoundRecord.SALT_MOUSE)), help)


## A copy of a swing help count (null stays null).
static func copy_help(help: LinksMouse.Help) -> LinksMouse.Help:
	if help == null:
		return null
	var h := LinksMouse.Help.new()
	h.enabled = help.enabled
	h.strokes = help.strokes
	h.still_strokes = help.still_strokes
	return h


## The meter power and accuracy a mouse swing stands for (what GolfRound
## passes to play_shot).
static func mouse_inputs(stroke: LinksMouse.Stroke, outcome: LinksMouse.Outcome) -> Vector2:
	var full := LinksShotModel.PUTT_POWER_AT_FULL if stroke.shot == LinksMouse.Shot.PUTT else 100.0
	return Vector2(clampf(outcome.power / full, 0.0, 1.0), clampf(-outcome.face_deg / 10.0, -1.0, 1.0))


## The holes a round with these RoundSetup holes and tees plays on `course`,
## in order, with the tee set as GolfRound sets it.
static func holes_for(course: CourseData, holes_setting: int, tees: int) -> Array[HoleData]:
	var s := RoundSetup.new()
	s.holes = holes_setting as RoundSetup.Holes
	s.tees = tees as RoundSetup.Tees
	var out: Array[HoleData] = []
	for i in s.hole_indices(course.holes.size()):
		var h := course.holes[i]
		if h.tees.size() > 1:
			h.tee = h.tees[s.tee_index(h.tees.size())]
		out.append(h)
	return out


## Checks a friend's round on the course at `course_path` with this game's
## shot model: verify() plus the course file and physics matching. Adds
## {course_ok: bool} to verify's answer.
static func check(record: RoundRecord, course_path: String) -> Dictionary:
	AssetProviders.ensure_defaults()
	var model := AssetProviders.shot_model
	var mine := "links" if model is LinksShotModel else "standard"
	var errors: Array[String] = []
	if record.model != mine:
		errors.append("the round used the %s physics, this game has the %s physics" % [record.model, mine])
	if RoundRecord.file_hash(course_path) != record.course_hash:
		errors.append("your copy of %s is different from theirs" % record.course_name)
	if not errors.is_empty():
		return {"ok": false, "checked": 0, "errors": errors, "cards_checked": false, "course_ok": false}
	var course := AssetProviders.load_course(course_path)
	var answer := verify(record, model, Club.standard_set(), holes_for(course, record.holes, record.tees))
	answer["course_ok"] = true
	return answer


## Checks `record` against `holes` (the round's holes, in order) with `model`
## and `clubs`. Returns {ok: bool, checked: shots replayed, errors: [String],
## cards_checked: bool}.
static func verify(record: RoundRecord, model: ShotModel, clubs: Array[Club], holes: Array[HoleData]) -> Dictionary:
	var errors: Array[String] = []
	if record == null:
		return {"ok": false, "checked": 0, "errors": ["no record"], "cards_checked": false}
	if record.version != RoundRecord.VERSION:
		errors.append("record version %d, expected %d" % [record.version, RoundRecord.VERSION])
	if record.resumed:
		errors.append("the round was resumed, so its wind can't be drawn again")
	if not errors.is_empty():
		return {"ok": false, "checked": 0, "errors": errors, "cards_checked": false}
	var wind := Wind.new(record.wind_level, record.round_seed)
	var started := 0
	var checked := 0
	for i in record.shots.size():
		var r := record.shots[i]
		var where := "shot %d (player %d, hole %d)" % [i + 1, r.player + 1, r.hole + 1]
		if r.index != i:
			errors.append("%s: numbered %d" % [where, r.index])
		if r.hole < 0 or r.hole >= holes.size() or r.club < 0 or r.club >= clubs.size():
			errors.append("%s: no such hole or club" % where)
			continue
		if r.holes_started < started:
			errors.append("%s: holes played out of order" % where)
		while started < r.holes_started:
			wind.start_hole()
			started += 1
		wind.set_level(r.wind_level)
		if wind.velocity().distance_to(r.wind) > WIND_TOLERANCE:
			errors.append("%s: wind %s, the seed gives %s" % [where, r.wind, wind.velocity()])
		if r.stroke != null and not r.computer:
			var want := mouse_inputs(r.stroke, mouse_outcome(r.stroke, record.round_seed, r.index, copy_help(r.help)))
			if absf(want.x - r.power) > INPUT_TOLERANCE or absf(want.y - r.accuracy) > INPUT_TOLERANCE:
				errors.append("%s: power and accuracy don't match the mouse swing" % where)
		var h := holes[r.hole]
		var result := run_shot(model, r, clubs[r.club], h.terrain, h.pin, wind.velocity(), record.round_seed)
		wind.next_shot()
		checked += 1
		if result.outcome != r.outcome:
			errors.append("%s: %s, recorded %s" % [where, ShotResult.Outcome.keys()[result.outcome], ShotResult.Outcome.keys()[r.outcome]])
		elif result.rest.distance_to(r.rest) > REST_TOLERANCE_M:
			errors.append("%s: stops %.2f m from where it was recorded" % [where, result.rest.distance_to(r.rest)])
	var cards_checked := record.finished and record.mode == GameModes.Mode.STROKE
	if cards_checked:
		_check_cards(record, errors)
	return {"ok": errors.is_empty(), "checked": checked, "errors": errors, "cards_checked": cards_checked}


## Stroke play: each hole's score is the shots played, a stroke for each ball
## in the water or out of bounds, and the penalty of each other drop. Holes
## picked up at the stroke limit are left alone.
static func _check_cards(record: RoundRecord, errors: Array[String]) -> void:
	for ball in record.cards.size():
		var card: Array = record.cards[ball]
		for hole in card.size():
			var got := int(card[hole])
			if got == 0 or got >= GolfRound.MAX_STROKES:
				continue
			var want := 0
			for s in record.shots_on(ball, hole):
				want += 1
				if s.outcome == ShotResult.Outcome.WATER or s.outcome == ShotResult.Outcome.OUT_OF_BOUNDS:
					want += 1
			for d in record.drops:
				if int(d.get("ball", -1)) == ball and int(d.get("hole", -1)) == hole:
					want += int(d.get("penalty", 0))
			if want != got:
				errors.append("player %d hole %d: card says %d, the shots make %d" % [ball + 1, hole + 1, got, want])
