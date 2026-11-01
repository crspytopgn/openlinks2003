class_name Career
extends RefCounted
## Career mode: seasons of tour events against a field of computer golfers.
##
## The person plays every round of an event for real, in a group with up to
## two computer golfers from the field (stroke play, RoundSetup.career). The
## rest of the field is simulated round by round from each golfer's scoring
## average, so a whole tour costs nothing to run. Four-round events have a cut
## after round two (the top `cut` and ties play the weekend); money is paid by
## a tour-style share of the purse, ties splitting the places they fill, and a
## tie for the win goes to a sudden-death playoff. The money list decides who
## moves up a tour, and on the World Tour who keeps their card.
##
## The rounds the person plays also go on their profile like any other round
## (handicap, stats, personal records). Game-side only; kept in
## user://career.cfg.

## Where the career is kept; the tests point this somewhere else.
static var path := "user://career.cfg"
## Set when a career round finishes, so the main menu opens the Career page.
static var open_on_menu := false

## The tours, easiest first. `best` and `worst` are the field's scoring
## averages to par per 18 holes, `sd` the round-to-round spread, `cut` how
## many (and ties) play the weekend, `move_up` how many from the top of the
## money list go up a tour, `keep` (World Tour) how many keep their card.
const TOURS := [
	{"name": "Regional Tour", "field": 59, "best": 0.0, "worst": 9.0, "sd": 3.4, "cut": 30,
		"purse": 60000, "tees": RoundSetup.Tees.MIDDLE, "move_up": 5, "keep": 0,
		"about": "Mini-tour golf for good amateurs: the field averages about 4 over par."},
	{"name": "Challenge Tour", "field": 95, "best": -3.0, "worst": 3.5, "sd": 3.0, "cut": 50,
		"purse": 400000, "tees": RoundSetup.Tees.BACK, "move_up": 5, "keep": 0,
		"about": "The road to the top tour: the field averages about level par."},
	{"name": "World Tour", "field": 131, "best": -3.5, "worst": 1.5, "sd": 2.8, "cut": 65,
		"purse": 8000000, "tees": RoundSetup.Tees.BACK, "move_up": 0, "keep": 100,
		"about": "The best in the world: the field averages about 1 under par."},
]
const SEASON_LENGTHS := [4, 8, 12]
const EVENT_ROUNDS := [4, 2, 1]
const PARTNER_COUNTS := [2, 1, 0]
## Share of the purse (percent) for each place, close to the big tours'
## published tables. Places past the table get a little less each.
const PAYOUT := [
	18.0, 10.9, 6.9, 4.9, 4.1, 3.625, 3.375, 3.125, 2.925, 2.725,
	2.525, 2.325, 2.125, 1.925, 1.825, 1.725, 1.625, 1.525, 1.425, 1.325,
	1.225, 1.125, 1.045, 0.965, 0.885, 0.805, 0.775, 0.745, 0.715, 0.685,
	0.655, 0.625, 0.595, 0.570, 0.545, 0.520, 0.495, 0.475, 0.455, 0.435,
	0.415, 0.395, 0.375, 0.355, 0.335, 0.315, 0.295, 0.279, 0.265, 0.257,
	0.251, 0.245, 0.241, 0.237, 0.235, 0.233, 0.231, 0.229, 0.227, 0.225,
	0.223, 0.221, 0.219, 0.217, 0.215,
]
const EVENT_KINDS := ["Classic", "Open", "Invitational", "Masters", "Championship"]
const _FIRST := [
	"Aaron", "Ben", "Callum", "Dan", "Elliot", "Felix", "Gareth", "Hugo", "Ian", "Jonah",
	"Kieran", "Liam", "Marcus", "Nils", "Owen", "Pablo", "Quinn", "Rafael", "Stefan", "Tomas",
	"Viktor", "Wes", "Yusuke", "Zach", "Anders", "Bruno", "Conor", "Diego", "Emil", "Finn",
	"Hamish", "Jakob", "Kenji", "Lars", "Mateo", "Niall", "Oskar", "Rory", "Soren", "Theo",
]
const _LAST := [
	"Ashdown", "Barrow", "Calloway", "Denholm", "Ellery", "Fairbairn", "Garside", "Halloran",
	"Inglis", "Jarvis", "Kettering", "Lindqvist", "Marlow", "Navarro", "Ockley", "Prescott",
	"Quayle", "Rennick", "Sandoval", "Thursby", "Underhill", "Vance", "Whitcombe", "Yardley",
	"Abernethy", "Brannigan", "Corrigan", "Dunmore", "Eckhardt", "Faulds", "Gilchrist", "Hartigan",
	"Iversen", "Kowalczyk", "Lachlan", "Moreau", "Nakamura", "Oyelaran", "Pellegrini", "Ruskin",
	"Strand", "Tavener", "Valdés", "Wexford", "Albrecht", "Byrne", "Castellano", "Delacroix",
]

var player := ""
var career_seed := 1
var tour := 0
var season := 1
var events_per_season := 8
var rounds_per_event := 4
## Nine-hole rounds (the front nine) for quicker events.
var short_rounds := false
var partners := 2
## The courses the schedule is drawn from: their keys (as the setup page
## lists them; "" is the placeholder course) and display names.
var course_keys: Array[String] = []
var course_names: Array[String] = []

## Everyone on the tour: the field, then the person last.
var names: Array[String] = []
## Each field golfer's scoring average to par per 18 holes.
var skills: Array[float] = []
## This season's events: [{name, course_key, course_name, purse}].
var schedule: Array = []
## The person's result in each event played: {pos, tied, to_par, money,
## status ("", "MC" or "WD"), rounds, winner, winning_to_par, playoff}.
var results: Array = []
var event := 0
## The event in progress: each golfer's rounds to par, the holes and par of
## each round played, and (after the cut) who made it.
var scores: Array = []
var round_holes: Array[int] = []
var round_pars: Array[int] = []
var made_cut: Array[bool] = []
var withdrawn := false
## Season earnings, per golfer.
var money: Array[int] = []
## The person's career: {events, wins, top10, cuts_made, cuts_missed,
## earnings, best_pos, rounds, holes, to_par}.
var stats := {}
## Past seasons: [{season, tour, money, rank, events, wins, moved}].
var history: Array = []


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func remove() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A new career for `player_name` on tour `start_tour`, its events spread
## over the given courses (an empty list plays the placeholder course).
static func create(player_name: String, start_tour: int, events: int, rounds: int, short: bool,
		partner_count: int, keys: Array[String], course_titles: Array[String], seed_value: int) -> Career:
	var c := Career.new()
	c.player = player_name.strip_edges()
	c.tour = clampi(start_tour, 0, TOURS.size() - 1)
	c.events_per_season = maxi(1, events)
	c.rounds_per_event = clampi(rounds, 1, 4)
	c.short_rounds = short
	c.partners = clampi(partner_count, 0, RoundSetup.MAX_PLAYERS - 1)
	c.course_keys.assign(keys)
	c.course_names.assign(course_titles)
	if c.course_keys.is_empty():
		c.course_keys.assign([""])
		c.course_names.assign([PlaceholderCourseLoader.NAME])
	c.career_seed = maxi(1, seed_value & 0x7fffffff)
	c.stats = {"events": 0, "wins": 0, "top10": 0, "cuts_made": 0, "cuts_missed": 0,
		"earnings": 0, "best_pos": 0, "rounds": 0, "holes": 0, "to_par": 0}
	c._new_season()
	return c


func tour_info() -> Dictionary:
	return TOURS[tour]


func player_index() -> int:
	return names.size() - 1


func season_over() -> bool:
	return event >= schedule.size()


func rounds_played() -> int:
	return round_pars.size()


func has_cut() -> bool:
	return rounds_per_event == 4


## True while the person still has rounds to play in this event.
func playing_event() -> bool:
	if season_over() or withdrawn:
		return false
	return made_cut.is_empty() or made_cut[player_index()]


## Ties a saved round to the round of the career it was started for.
func round_id() -> String:
	return "%d/%d/%d/%d" % [career_seed, season, event, rounds_played()]


# --- Seasons and events -------------------------------------------------------

func _rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([career_seed, season, tour, salt])
	return r


## The tour's field: the same golfers every season on a tour, best first.
func _make_field() -> void:
	var info := tour_info()
	var r := RandomNumberGenerator.new()
	r.seed = hash([career_seed, tour, "field"])
	names.clear()
	skills.clear()
	var used := {player.to_lower(): true}
	var n: int = info.field
	while names.size() < n:
		var who: String = "%s %s" % [_FIRST[r.randi() % _FIRST.size()], _LAST[r.randi() % _LAST.size()]]
		if used.has(who.to_lower()):
			continue
		used[who.to_lower()] = true
		var t := float(names.size()) / maxf(1.0, n - 1.0)
		# A few stars, most of the field bunched towards the back.
		skills.append(float(info.best) + (float(info.worst) - float(info.best)) * pow(t, 0.6) + r.randfn(0.0, 0.25))
		names.append(who)
	names.append(player)


func _new_season() -> void:
	_make_field()
	var r := _rng(1)
	var order: Array[int] = []
	schedule.clear()
	var info := tour_info()
	for e in events_per_season:
		if order.is_empty():
			for i in course_keys.size():
				order.append(i)
			# Shuffle each pass through the courses.
			for i in range(order.size() - 1, 0, -1):
				var j := r.randi() % (i + 1)
				var tmp := order[i]
				order[i] = order[j]
				order[j] = tmp
		var ci: int = order.pop_back()
		var kind: String = EVENT_KINDS[r.randi() % 3]
		var mult := 1.0
		if e == events_per_season - 1 and events_per_season > 1:
			kind = "Championship"
			mult = 2.0
		elif events_per_season >= 4 and e == int(events_per_season / 2.0):
			kind = "Masters"
			mult = 1.5
		var title := "%s %s" % [_short_name(course_names[ci]), kind]
		if kind == "Championship":
			title = "%s Championship" % str(info.name).trim_suffix(" Tour")
		schedule.append({"name": title, "course_key": course_keys[ci], "course_name": course_names[ci],
			"purse": int(round(float(info.purse) * mult))})
	results.clear()
	money.clear()
	for _i in names.size():
		money.append(0)
	event = 0
	_start_event()


static func _short_name(course: String) -> String:
	for suffix: String in [" Golf Links", " Golf Club", " Golf Course", " Country Club", " GC"]:
		if course.ends_with(suffix):
			return course.trim_suffix(suffix)
	return course


func _start_event() -> void:
	scores.clear()
	for _i in names.size():
		scores.append([])
	round_holes.clear()
	round_pars.clear()
	made_cut.clear()
	withdrawn = false


## The golfers still playing this event.
func _in_event(i: int) -> bool:
	if i == player_index() and withdrawn:
		return false
	return made_cut.is_empty() or made_cut[i]


## Who plays with the person in round `rounds_played() + 1`: drawn at random
## before the cut, then the golfers next to them on the leaderboard.
func partner_indexes() -> Array[int]:
	var out: Array[int] = []
	if partners <= 0 or not playing_event():
		return out
	if rounds_played() == 0 or (has_cut() and rounds_played() < 2):
		var r := _rng(1000 + event * 10 + rounds_played())
		var guard := 0
		while out.size() < partners and guard < 1000:
			guard += 1
			var i := r.randi() % (names.size() - 1)
			if not out.has(i):
				out.append(i)
		return out
	var rows := standings()
	var me := -1
	for k in rows.size():
		if int(rows[k][0]) == player_index():
			me = k
	# The golfers just ahead of the person, else just behind.
	for step in range(1, rows.size()):
		for k: int in [me - step, me + step]:
			if out.size() >= partners:
				return out
			if k >= 0 and k < rows.size() and str(rows[k][2]).is_empty() and int(rows[k][0]) != player_index():
				out.append(int(rows[k][0]))
	return out


## The computer level that plays field golfer `i` in the person's group.
func partner_level(i: int) -> int:
	var s := skills[i]
	if s <= -1.0:
		return OpponentSkill.Level.TOUR
	if s <= 4.0:
		return OpponentSkill.Level.SCRATCH
	if s <= 11.0:
		return OpponentSkill.Level.CLUB
	return OpponentSkill.Level.BEGINNER


## Field golfer `i` as a computer golfer: their own strengths, weaknesses and
## style, with numbers that average about their scoring average.
func partner_pro(i: int) -> TourPro:
	var r := RandomNumberGenerator.new()
	r.seed = hash([career_seed, tour, "pro", names[i]])
	return TourPro.generate(names[i], TourPro.level_for_average(skills[i]), false, r)


## The round the person plays next, or null if they have none to play.
func next_setup() -> RoundSetup:
	if not playing_event():
		return null
	var ev: Dictionary = schedule[event]
	var s := RoundSetup.new()
	s.mode = GameModes.Mode.STROKE
	s.holes = RoundSetup.Holes.FRONT_NINE if short_rounds else RoundSetup.Holes.ALL
	s.tees = tour_info().tees
	s.course_key = ev.course_key
	s.course_name = ev.course_name
	s.handicaps = false
	s.names.assign([player])
	s.teams.assign([0])
	s.computer.assign([RoundSetup.HUMAN])
	for i in partner_indexes():
		s.names.append(names[i])
		s.teams.append(s.teams.size() % 2)
		s.computer.append(partner_level(i))
		s.pros[names[i]] = partner_pro(i).to_dict()
	s.career = round_id()
	return s


## Adds the person's round (and their partners' real rounds) to the event:
## `played` maps a golfer's name to their score to par. The rest of the field
## is simulated. Returns what it meant ("Round 2: 70 (-2), T14. Made the cut
## at +1."), or "" if `id` isn't this career's next round.
func record_round(id: String, played: Dictionary, holes: int, par: int, gross: int) -> String:
	if id != round_id() or not playing_event():
		return ""
	var real := {}
	for i in names.size():
		if played.has(names[i]) and _in_event(i):
			real[i] = int(played[names[i]])
	if not real.has(player_index()):
		return ""
	_play_round(holes, par, real)
	var me := player_index()
	var to_par: int = real[me]
	stats.rounds = int(stats.rounds) + 1
	stats.holes = int(stats.holes) + holes
	stats.to_par = int(stats.to_par) + to_par
	var round_no := rounds_played()
	var text := "%s, round %d: %d (%s)" % [schedule[event].name, round_no, gross, Scorecard.format_to_par(to_par)]
	if round_no < rounds_per_event:
		if made_cut.is_empty() or made_cut[me]:
			var p := position_of(me)
			text += ", %s%d at %s." % ["T" if p.tied else "", p.pos, Scorecard.format_to_par(total_of(me))]
		else:
			text += ", %s after two rounds." % Scorecard.format_to_par(total_of(me))
		if not made_cut.is_empty():
			if made_cut[me]:
				text += " Made the cut at %s." % Scorecard.format_to_par(cut_line())
			else:
				text += " Missed the cut at %s." % Scorecard.format_to_par(cut_line())
	else:
		text += "."
	if made_cut.size() > 0 and not made_cut[me]:
		_play_out()
	if rounds_played() >= rounds_per_event:
		text += " " + _finish_event()
	return text


## The person withdraws from the event in progress (no money); the event is
## played out without them.
func withdraw() -> void:
	if not playing_event():
		return
	withdrawn = true
	_play_out()
	_finish_event()


func _play_out() -> void:
	while rounds_played() < rounds_per_event:
		var holes: int = round_holes[-1] if not round_holes.is_empty() else (9 if short_rounds else 18)
		var par: int = round_pars[-1] if not round_pars.is_empty() else holes * 4
		_play_round(holes, par, {})


## Everyone still in the event plays a round: the scores in `real`, the rest
## simulated (their average, the day's conditions and their own form).
func _play_round(holes: int, par: int, real: Dictionary) -> void:
	var r := _rng(5000 + event * 10 + rounds_played())
	var f := holes / 18.0
	var info := tour_info()
	var day := r.randfn(0.0, 1.2)  # wind, pins, firmness: the same for everyone
	for i in names.size():
		var draw := r.randfn(0.0, float(info.sd) * sqrt(f))
		if not _in_event(i):
			continue
		var score := 0
		if real.has(i):
			score = int(real[i])
		elif i == player_index():
			continue
		else:
			score = roundi((skills[i] + day) * f + draw)
		(scores[i] as Array).append(score)
	round_holes.append(holes)
	round_pars.append(par)
	if has_cut() and rounds_played() == 2 and made_cut.is_empty():
		_make_cut()


## The top `cut` and ties play on.
func _make_cut() -> void:
	var line := cut_line()
	var made: Array[bool] = []
	for i in names.size():
		made.append(_in_event(i) and (scores[i] as Array).size() == 2 and total_of(i) <= line)
	made_cut = made


## The score that makes the cut: the `cut`th best total after two rounds.
func cut_line() -> int:
	var totals: Array[int] = []
	for i in names.size():
		if not (i == player_index() and withdrawn) and (scores[i] as Array).size() >= 2:
			totals.append(int(scores[i][0]) + int(scores[i][1]))
	totals.sort()
	if totals.is_empty():
		return 0
	return totals[mini(int(tour_info().cut), totals.size()) - 1]


func total_of(i: int) -> int:
	var t := 0
	for s: int in scores[i]:
		t += s
	return t


## The event leaderboard, best first: [[golfer, total to par, status], ...]
## with status "" (still in or finished), "MC" or "WD".
func standings() -> Array:
	var rows: Array = []
	for i in names.size():
		var status := ""
		if i == player_index() and withdrawn:
			status = "WD"
		elif not made_cut.is_empty() and not made_cut[i]:
			status = "MC"
		rows.append([i, total_of(i), status, (scores[i] as Array).size()])
	rows.sort_custom(_leaderboard_order)
	return rows


static func _leaderboard_order(a: Array, b: Array) -> bool:
	var ra := 0 if str(a[2]).is_empty() else (1 if a[2] == "MC" else 2)
	var rb := 0 if str(b[2]).is_empty() else (1 if b[2] == "MC" else 2)
	if ra != rb:
		return ra < rb
	if a[3] != b[3]:
		return a[3] > b[3]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[0] < b[0]


## Golfer `i`'s place on the leaderboard: {pos, tied}.
func position_of(i: int) -> Dictionary:
	var mine := total_of(i)
	var pos := 1
	var tied := false
	for j in names.size():
		if j == i or not _in_event(j):
			continue
		var t := total_of(j)
		if t < mine:
			pos += 1
		elif t == mine:
			tied = true
	return {"pos": pos, "tied": tied}


## The money for each finisher, best first, from their `totals` to par: a
## share of the purse by place (the shares of the first `norm_places` add up
## to the purse), tied golfers splitting the places they fill. Finishers from
## `pay_places` on get nothing unless tied with a paid place. `split_first`:
## the first two are level but a playoff has put the winner first.
static func payouts(totals: Array[int], purse: int, norm_places: int, pay_places: int, split_first: bool) -> Array[int]:
	var norm := 0.0
	for p in norm_places:
		norm += _share(p)
	var out: Array[int] = []
	var k := 0
	while k < totals.size():
		var n := 1
		if not (k == 0 and split_first):
			while k + n < totals.size() and totals[k + n] == totals[k]:
				n += 1
		var sum := 0.0
		if k < pay_places:
			for p in range(k, k + n):
				sum += _share(p)
		var each := roundi(float(purse) * sum / n / norm) if norm > 0.0 else 0
		for _p in n:
			out.append(each)
		k += n
	return out


static func _share(place: int) -> float:
	if place < PAYOUT.size():
		return PAYOUT[place]
	return maxf(0.15, float(PAYOUT[-1]) - 0.002 * (place - PAYOUT.size() + 1))


## Sudden death between the golfers in `tied`: each plays holes until one
## wins outright. Returns the winner.
func _playoff(tied: Array[int]) -> int:
	var r := _rng(9000 + event)
	var left := tied.duplicate()
	var guard := 0
	while left.size() > 1 and guard < 50:
		guard += 1
		var best := 99
		var hole_scores := {}
		for i in left:
			var avg: float = skills[i] if i < skills.size() else player_average()
			var s := roundi(avg / 18.0 + r.randfn(0.0, 0.6))
			hole_scores[i] = s
			best = mini(best, s)
		var next: Array[int] = []
		for i in left:
			if hole_scores[i] == best:
				next.append(i)
		left = next
	return left[0]


## The person's scoring average to par per 18 holes in career rounds (a
## middling tour average before any).
func player_average() -> float:
	if int(stats.get("holes", 0)) == 0:
		return 1.0
	return 18.0 * float(stats.to_par) / float(stats.holes)


## Pays out the event, keeps the person's result and moves on.
func _finish_event() -> String:
	var ev: Dictionary = schedule[event]
	var rows := standings()
	var finishers: Array[int] = []
	var totals: Array[int] = []
	for row: Array in rows:
		if str(row[2]).is_empty():
			finishers.append(int(row[0]))
			totals.append(int(row[1]))
	var playoff := false
	if totals.size() > 1 and totals[0] == totals[1]:
		var tied: Array[int] = []
		for k in totals.size():
			if totals[k] == totals[0]:
				tied.append(finishers[k])
		var winner := _playoff(tied)
		finishers.erase(winner)
		finishers.insert(0, winner)
		playoff = true
	var cut: int = tour_info().cut
	var pay := payouts(totals, int(ev.purse), cut, finishers.size() if has_cut() else cut, playoff)
	for k in finishers.size():
		money[finishers[k]] += pay[k]
	var me := player_index()
	var result := {"pos": 0, "tied": false, "to_par": total_of(me), "money": 0, "status": "",
		"rounds": (scores[me] as Array).duplicate(), "winner": names[finishers[0]] if not finishers.is_empty() else "",
		"winning_to_par": totals[0] if not totals.is_empty() else 0, "playoff": playoff}
	var k_me := finishers.find(me)
	stats.events = int(stats.events) + 1
	if withdrawn:
		result.status = "WD"
	elif k_me < 0:
		result.status = "MC"
		stats.cuts_missed = int(stats.cuts_missed) + 1
	else:
		var mine := totals[k_me]
		var pos := 1
		for t in totals:
			if t < mine:
				pos += 1
		var tied := totals.count(mine) > 1
		if playoff and mine == totals[0]:
			# Lost the playoff: second, tied if more than one lost it.
			pos = 1 if k_me == 0 else 2
			tied = k_me > 0 and totals.count(mine) > 2
		result.pos = pos
		result.tied = tied
		result.money = pay[k_me]
		if has_cut():
			stats.cuts_made = int(stats.cuts_made) + 1
		if pos == 1:
			stats.wins = int(stats.wins) + 1
		if pos <= 10:
			stats.top10 = int(stats.top10) + 1
		stats.earnings = int(stats.earnings) + pay[k_me]
		if int(stats.best_pos) == 0 or pos < int(stats.best_pos):
			stats.best_pos = pos
	results.append(result)
	event += 1
	_start_event()
	return result_text(results.size() - 1)


## "Won the Kauri Classic at -12 ($1,440,000)." or "Missed the cut. Ann
## Byrne won at -9."
func result_text(e: int) -> String:
	var r: Dictionary = results[e]
	var won_by := "%s won at %s%s." % [r.winner, Scorecard.format_to_par(int(r.winning_to_par)), " in a playoff" if r.playoff else ""]
	match str(r.status):
		"MC":
			return "Missed the cut. " + won_by
		"WD":
			return "Withdrew. " + won_by
	if int(r.pos) == 1:
		return "Won the %s at %s%s! %s." % [schedule[e].name, Scorecard.format_to_par(int(r.to_par)),
			" in a playoff" if r.playoff else "", format_money(int(r.money))]
	return "Finished %s at %s, %s. %s" % [place_text(int(r.pos), r.tied), Scorecard.format_to_par(int(r.to_par)),
		format_money(int(r.money)), won_by]


static func place_text(pos: int, tied: bool) -> String:
	return "%s%d" % ["T" if tied else "", pos]


static func format_money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-$" if amount < 0 else "$") + digits + out


## The season's money list, richest first: [[golfer, money], ...].
func money_list() -> Array:
	var rows: Array = []
	for i in names.size():
		rows.append([i, money[i]])
	rows.sort_custom(_money_order)
	return rows


static func _money_order(a: Array, b: Array) -> bool:
	return a[1] > b[1] if a[1] != b[1] else a[0] < b[0]


func money_rank() -> int:
	var rows := money_list()
	for k in rows.size():
		if int(rows[k][0]) == player_index():
			return k + 1
	return rows.size()


## What the season's money list does for the person: +1 up a tour, -1 down
## (World Tour card lost), 0 stays.
func season_move() -> int:
	var info := tour_info()
	var rank := money_rank()
	if int(info.move_up) > 0 and rank <= int(info.move_up) and tour + 1 < TOURS.size():
		return 1
	if int(info.keep) > 0 and rank > int(info.keep) and tour > 0:
		return -1
	return 0


## Closes the season (only once every event is played) and starts the next,
## on a new tour if the money list says so.
func start_next_season() -> void:
	if not season_over():
		return
	var wins := 0
	for r: Dictionary in results:
		if int(r.pos) == 1:
			wins += 1
	var move := season_move()
	history.append({"season": season, "tour": tour, "money": money[player_index()], "rank": money_rank(),
		"events": results.size(), "wins": wins, "moved": move})
	tour = clampi(tour + move, 0, TOURS.size() - 1)
	season += 1
	_new_season()


# --- Text for the menus -------------------------------------------------------

## "Kauri Classic, Kauri Cliffs. Round 2 of 4. Purse $8,000,000."
func next_text() -> String:
	if season_over():
		return "Season %d is over." % season
	var ev: Dictionary = schedule[event]
	var text := "Event %d of %d: %s. Purse %s." % [event + 1, schedule.size(), event_title(event), format_money(int(ev.purse))]
	if playing_event():
		text += " Round %d of %d." % [rounds_played() + 1, rounds_per_event]
	elif withdrawn:
		text += " Withdrawn."
	else:
		text += " Missed the cut."
	return text


## "Kauri Cliffs Open", or "World Championship at Kauri Cliffs" when the
## name doesn't say where.
func event_title(e: int) -> String:
	var ev: Dictionary = schedule[e]
	var title := str(ev.name)
	if title.begins_with(_short_name(str(ev.course_name))):
		return title
	return "%s at %s" % [title, ev.course_name]


## The top of the leaderboard plus the person's own line: "T3. Ann Byrne -7".
func leaderboard_lines(top: int) -> Array[String]:
	var out: Array[String] = []
	if rounds_played() == 0:
		return out
	var rows := standings()
	for k in rows.size():
		var row: Array = rows[k]
		var i := int(row[0])
		if k < top or i == player_index():
			var place := str(row[2])
			if place.is_empty():
				var p := position_of(i)
				place = place_text(int(p.pos), p.tied)
			out.append("%s. %s  %s" % [place, names[i], Scorecard.format_to_par(int(row[1]))])
		if k >= top and i == player_index():
			break
	return out


## The top of the money list plus the person's line: "1. Ann Byrne $2,100,000".
func money_lines(top: int) -> Array[String]:
	var out: Array[String] = []
	var rows := money_list()
	for k in rows.size():
		var i := int(rows[k][0])
		if k < top or i == player_index():
			out.append("%d. %s  %s" % [k + 1, names[i], format_money(int(rows[k][1]))])
		if k >= top and i == player_index():
			break
	return out


## "12 events, 1 win, 4 top 10s, 9 of 11 cuts, $1,250,000. Scoring average
## 70.8 (par 72)."
func career_text() -> String:
	var parts: Array[String] = []
	var ev := int(stats.get("events", 0))
	parts.append("%d event%s" % [ev, "" if ev == 1 else "s"])
	var w := int(stats.get("wins", 0))
	parts.append("%d win%s" % [w, "" if w == 1 else "s"])
	parts.append("%d top 10%s" % [int(stats.top10), "" if int(stats.top10) == 1 else "s"])
	var cuts := int(stats.cuts_made) + int(stats.cuts_missed)
	if cuts > 0:
		parts.append("%d of %d cuts made" % [int(stats.cuts_made), cuts])
	parts.append("earnings %s" % format_money(int(stats.earnings)))
	var text := ", ".join(parts) + "."
	if int(stats.holes) > 0:
		var avg := player_average()
		var avg_text := "level par" if absf(avg) < 0.05 else "%s%.1f" % ["+" if avg > 0.0 else "-", absf(avg)]
		text += " Scoring %s per 18 holes." % avg_text
	return text


func season_text() -> String:
	var info := tour_info()
	var text := "%s, season %d. %s on the money list with %s." % [info.name, season, _ordinal(money_rank()), format_money(money[player_index()])]
	if season_over():
		match season_move():
			1:
				text += " Top %d: you move up to the %s!" % [int(info.move_up), TOURS[tour + 1].name]
			-1:
				text += " Outside the top %d: you lose your card and drop to the %s." % [int(info.keep), TOURS[tour - 1].name]
			_:
				if int(info.keep) > 0:
					text += " You keep your card."
				elif int(info.move_up) > 0:
					text += " The top %d move up; another season on the %s." % [int(info.move_up), info.name]
	return text


static func _ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]


# --- Saving -------------------------------------------------------------------

func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in ["player", "career_seed", "tour", "season", "events_per_season", "rounds_per_event",
			"short_rounds", "partners", "course_keys", "course_names", "names", "skills", "schedule",
			"results", "event", "scores", "round_holes", "round_pars", "made_cut", "withdrawn", "money",
			"stats", "history"]:
		var v: Variant = get(key)
		if v is Array:
			v = Array(v)
		cfg.set_value("career", key, v)
	cfg.save(path)


static func load_saved() -> Career:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("career"):
		return null
	var c := Career.new()
	c.player = str(cfg.get_value("career", "player", ""))
	c.career_seed = int(cfg.get_value("career", "career_seed", 1))
	c.tour = clampi(int(cfg.get_value("career", "tour", 0)), 0, TOURS.size() - 1)
	c.season = int(cfg.get_value("career", "season", 1))
	c.events_per_season = int(cfg.get_value("career", "events_per_season", 8))
	c.rounds_per_event = clampi(int(cfg.get_value("career", "rounds_per_event", 4)), 1, 4)
	c.short_rounds = cfg.get_value("career", "short_rounds", false) == true
	c.partners = int(cfg.get_value("career", "partners", 2))
	c.course_keys.assign(cfg.get_value("career", "course_keys", []))
	c.course_names.assign(cfg.get_value("career", "course_names", []))
	c.names.assign(cfg.get_value("career", "names", []))
	c.skills.assign(cfg.get_value("career", "skills", []))
	c.schedule = cfg.get_value("career", "schedule", [])
	c.results = cfg.get_value("career", "results", [])
	c.event = int(cfg.get_value("career", "event", 0))
	c.scores = cfg.get_value("career", "scores", [])
	c.round_holes.assign(cfg.get_value("career", "round_holes", []))
	c.round_pars.assign(cfg.get_value("career", "round_pars", []))
	c.made_cut.assign(cfg.get_value("career", "made_cut", []))
	c.withdrawn = cfg.get_value("career", "withdrawn", false) == true
	c.money.assign(cfg.get_value("career", "money", []))
	c.stats = cfg.get_value("career", "stats", {})
	c.history = cfg.get_value("career", "history", [])
	if c.names.is_empty() or c.skills.size() != c.names.size() - 1 or c.scores.size() != c.names.size() \
			or c.money.size() != c.names.size() or c.player.is_empty():
		return null
	return c
