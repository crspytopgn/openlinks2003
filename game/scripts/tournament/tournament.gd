class_name Tournament
extends RefCounted
## A tournament the person sets up and plays: the courses, rounds, field
## (size, strength, men, women or mixed), cut, format (stroke play,
## Stableford, knockout match play or a skins game), purse, weather and tee
## times.
##
## The person plays every round for real, with computer golfers from the
## field in their group (they play by the same physics; see ComputerGolfer).
## The rest of the field is simulated hole by hole from each golfer's numbers
## (TourPro.scoring_average), the day's conditions and their form, with
## realistic odds of each score on each par (HOLE_ODDS). Field golfers tee
## off before and after the person's group, so the leaderboard moves while
## the person plays (live_rows). Game-side only; kept in
## user://tournament.cfg.

## Where the tournament is kept; the tests point this somewhere else.
static var path := "user://tournament.cfg"
## Set when a tournament round finishes, so the main menu opens its page.
static var open_on_menu := false

enum Format { STROKE, STABLEFORD, MATCH, SKINS }

const FORMAT_NAMES := ["Stroke play", "Stableford", "Match play (knockout)", "Skins game"]
const FORMAT_HELP := [
	"The lowest total over all the rounds wins.",
	"Points on every hole (2 for par, 1 more for each stroke under, 1 fewer for each over); the most points wins.",
	"A knockout draw of 18-hole matches, seeded by ability. Win and go through to the next round.",
	"You and three tour pros. Every hole is worth money, more on the later holes; ties carry it to the next hole.",
]
## Field strength: the skill level (TourPro.generate) the field is drawn
## around and its spread.
const STRENGTHS := [
	{"name": "Club amateurs", "level": 1.3, "sd": 0.45, "named": false},
	{"name": "Regional tour", "level": 2.3, "sd": 0.25, "named": false},
	{"name": "Challenge tour", "level": 2.8, "sd": 0.2, "named": false},
	{"name": "World tour", "level": 3.05, "sd": 0.22, "named": true},
	{"name": "Major championship", "level": 3.3, "sd": 0.18, "named": true},
]
enum Field { MEN, WOMEN, MIXED }
const FIELD_NAMES := ["Men", "Women", "Mixed"]
const FIELD_SIZES := [12, 24, 48, 72, 96, 120, 144, 156]
const MATCH_SIZES := [8, 16, 32, 64]
const SKINS_PLAYERS := 4
const CUT_NAMES := ["No cut", "Top 65 and ties", "Top 50 and ties", "Top 70 and ties"]
const CUT_PLACES := [0, 65, 50, 70]
const PURSES := [100000, 1000000, 8000000, 20000000]
enum Weather { CALM, BREEZY, WINDY, STORMY, CHANGEABLE }
const WEATHER_NAMES := ["Calm", "Breezy", "Windy", "Stormy", "Changeable"]
## The round's Wind.Level for each weather (Changeable draws one a round).
const WEATHER_WIND := [Wind.Level.OFF, Wind.Level.LIGHT, Wind.Level.MODERATE, Wind.Level.STRONG]
## What the wind costs a tour pro per round, by Wind.Level; worse golfers lose
## more.
const WIND_STROKES := [-0.4, 0.0, 1.0, 2.5]
enum TeeTimes { MORNING, AFTERNOON, DRAW }
const TEE_TIME_NAMES := ["Morning", "Afternoon", "Draw (leaders go out last at the weekend)"]
const MAX_PARTNERS := 3

## The odds of each score against par for the average tour pro on an
## average tour hole, from -3 (albatross) to +4, rounded from PGA Tour
## scoring statistics: about 11% birdies on par 3s, 15% on par 4s and 38% on
## par 5s. They add up to about TourPro.TOUR_TO_PAR on a par 72. A golfer's
## own odds are these tilted to their expected score (hole_odds).
const HOLE_ODDS := {
	3: [0.0, 0.001, 0.11, 0.70, 0.16, 0.025, 0.004, 0.0008],
	4: [0.0, 0.001, 0.15, 0.69, 0.14, 0.017, 0.003, 0.0006],
	5: [0.0005, 0.025, 0.38, 0.52, 0.065, 0.008, 0.0015, 0.0003],
}
const FIRST_SCORE := -3
## Tee times: groups go off this many holes apart (10 minutes at about 14 a
## hole), on two tees, and the afternoon wave about a round after the morning.
const GROUP_GAP_HOLES := 0.7
const WAVE_GAP_HOLES := 18.0
const _WOMEN_FIRST := [
	"Abigail", "Beatriz", "Chloe", "Daniela", "Elena", "Freya", "Gemma", "Hana", "Ines", "Julia",
	"Kirsty", "Laura", "Maja", "Nadia", "Olivia", "Paula", "Rhiannon", "Sara", "Tessa", "Valentina",
	"Wren", "Yuna", "Zoe", "Amelia", "Bonnie", "Carla", "Divya", "Esme", "Ffion", "Greta",
	"Isla", "Jade", "Kaori", "Lucia", "Mirela", "Nora", "Orla", "Priya", "Ruth", "Sienna",
]

static var _odds_cache := {}

# --- Settings ----------------------------------------------------------------

var title := ""
var player := ""
var format: Format = Format.STROKE
## Each round's course key (as the setup page lists them; "" is the
## placeholder course) and name.
var course_keys: Array[String] = []
var course_names: Array[String] = []
var rounds := 4
var short_rounds := false
var strength := 3
var field_kind: Field = Field.MEN
var field_size := 72
var cut := 1
var purse := 1000000
var weather: Weather = Weather.BREEZY
var tee_times: TeeTimes = TeeTimes.DRAW
var partners := 2
var tournament_seed := 1

# --- The field and the results -----------------------------------------------

## Everyone in the field, the person last.
var names: Array[String] = []
## Each field golfer as TourPro.to_dict() (the person's entry is {}).
var pros: Array = []
## Each golfer's scoring average to par per 18 holes.
var averages: Array[float] = []
## Each golfer's rounds: an Array of PackedInt32Array hole scores (0 not
## played).
var scores: Array = []
## Each round's hole pars and the wind it was played in.
var round_pars: Array = []
var round_winds: Array[int] = []
var made_cut: Array[bool] = []
var withdrawn := false
## The final result once over: {pos, tied, money, winner, playoff, text}.
var result := {}
## Money won by each golfer (skins and the final payout).
var money: Array[int] = []
## Match play: each round's matches [[a, b, winner, "3&2"], ...] (winner -1
## until played).
var bracket: Array = []
## Skins: skins won and carried, per round [{skins, money, carried}].
var skins_rounds: Array = []

# The round being played (not saved: begin_round makes it again).
var _live_round := -1
var _live: Array = []  ## each golfer's simulated scores for the round
var _start: Array[float] = []  ## each golfer's tee time, in holes
var _strokes_index: Array[int] = []
var _live_pars_cache: Array[int] = []


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func remove() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A new tournament. `keys` and `titles` are the courses, one per round
## (repeated if there are fewer).
static func create(settings: Dictionary, keys: Array[String], titles: Array[String]) -> Tournament:
	var t := Tournament.new()
	t.player = str(settings.get("player", "Player 1")).strip_edges()
	t.format = clampi(int(settings.get("format", 0)), 0, FORMAT_NAMES.size() - 1) as Format
	t.rounds = clampi(int(settings.get("rounds", 4)), 1, 4)
	t.short_rounds = bool(settings.get("short", false))
	t.strength = clampi(int(settings.get("strength", 3)), 0, STRENGTHS.size() - 1)
	t.field_kind = clampi(int(settings.get("field_kind", 0)), 0, FIELD_NAMES.size() - 1) as Field
	t.field_size = int(settings.get("field_size", 72))
	t.cut = clampi(int(settings.get("cut", 1)), 0, CUT_PLACES.size() - 1)
	t.purse = maxi(0, int(settings.get("purse", 1000000)))
	t.weather = clampi(int(settings.get("weather", 1)), 0, WEATHER_NAMES.size() - 1) as Weather
	t.tee_times = clampi(int(settings.get("tee_times", 2)), 0, TEE_TIME_NAMES.size() - 1) as TeeTimes
	t.partners = clampi(int(settings.get("partners", 2)), 0, MAX_PARTNERS)
	t.tournament_seed = maxi(1, int(settings.get("seed", 1)) & 0x7fffffff)
	match t.format:
		Format.MATCH:
			t.field_size = MATCH_SIZES[0]
			for n: int in MATCH_SIZES:
				if n <= int(settings.get("field_size", 16)):
					t.field_size = n
			t.rounds = int(round(log(t.field_size) / log(2.0)))
			t.partners = 1
		Format.SKINS:
			t.field_size = SKINS_PLAYERS
			t.rounds = clampi(t.rounds, 1, 2)
			t.partners = SKINS_PLAYERS - 1
		_:
			t.field_size = clampi(t.field_size, 2, 156)
	t.course_keys.assign(keys)
	t.course_names.assign(titles)
	if t.course_keys.is_empty():
		t.course_keys.assign([""])
		t.course_names.assign(["Placeholder Nine"])
	var name_given := str(settings.get("title", "")).strip_edges()
	t.title = name_given if not name_given.is_empty() else t._default_title()
	t._make_field()
	if t.format == Format.MATCH:
		t._make_bracket()
	return t


func _default_title() -> String:
	var course := Career._short_name(course_names[0])
	match format:
		Format.MATCH:
			return "%s Match Play" % course
		Format.SKINS:
			return "%s Skins" % course
	if strength >= 4:
		return "%s Championship" % course
	return "%s %s" % [course, ["Amateur", "Classic", "Challenge", "Open", "Open"][strength]]


func _rng(salt: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([tournament_seed, salt])
	return r


## The field: the roster's tour pros in a top field, the rest made up, best
## first; the person last.
func _make_field() -> void:
	var r := _rng("field")
	var info: Dictionary = STRENGTHS[strength]
	names.clear()
	pros.clear()
	averages.clear()
	var used := {player.to_lower(): true}
	var n := field_size - 1
	var list: Array[TourPro] = []
	if bool(info.named) or format == Format.SKINS:
		var roster := TourPro.roster()
		for k in roster.size():
			var woman := k >= TourPro.FIRST_WOMAN
			if (field_kind == Field.MEN and woman) or (field_kind == Field.WOMEN and not woman):
				continue
			list.append(roster[k])
		# Shuffle so a small field gets a different few each time.
		for i in range(list.size() - 1, 0, -1):
			var j := r.randi() % (i + 1)
			var tmp := list[i]
			list[i] = list[j]
			list[j] = tmp
		list.resize(mini(list.size(), n))
	for p in list:
		used[p.name.to_lower()] = true
	var guard := 0
	while list.size() < n and guard < 10000:
		guard += 1
		var woman := field_kind == Field.WOMEN or (field_kind == Field.MIXED and r.randf() < 0.5)
		var first: Array = _WOMEN_FIRST if woman else Career._FIRST
		var who := "%s %s" % [first[r.randi() % first.size()], Career._LAST[r.randi() % Career._LAST.size()]]
		if used.has(who.to_lower()):
			continue
		used[who.to_lower()] = true
		var level := float(info.level) + r.randfn(0.0, float(info.sd))
		list.append(TourPro.generate(who, level, woman, r))
	list.sort_custom(func(a: TourPro, b: TourPro) -> bool: return a.scoring_average() < b.scoring_average())
	for p in list:
		names.append(p.name)
		pros.append(p.to_dict())
		averages.append(p.scoring_average())
	names.append(player)
	pros.append({})
	averages.append(player_average())
	scores.clear()
	money.clear()
	for _i in names.size():
		scores.append([])
		money.append(0)


func player_index() -> int:
	return names.size() - 1


func pro(i: int) -> TourPro:
	return TourPro.from_dict(pros[i]) if i < pros.size() and not (pros[i] as Dictionary).is_empty() else null


## The person's scoring average to par per 18 holes: from their handicap
## index if they have one (a scratch golfer on a tour course is a few over),
## else from their rounds here, else a middling club golfer's.
func player_average() -> float:
	var profiles := PlayerProfiles.load_saved()
	var index := profiles.index_of(player)
	if index != Handicap.NONE:
		return 3.0 + index / 10.0
	return 8.0


func rounds_played() -> int:
	return round_pars.size()


func over() -> bool:
	return not result.is_empty()


func has_cut() -> bool:
	return (format == Format.STROKE or format == Format.STABLEFORD) and rounds >= 3 and CUT_PLACES[cut] > 0 \
		and CUT_PLACES[cut] < names.size()


## True while the person still has a round to play.
func playing() -> bool:
	if over() or withdrawn:
		return false
	if format == Format.MATCH:
		return _alive_in_bracket(player_index())
	return made_cut.is_empty() or made_cut[player_index()]


## Ties a saved round to the tournament round it was started for.
func round_id() -> String:
	return "T%d/%d" % [tournament_seed, rounds_played()]


func course_index(round_no: int) -> int:
	return round_no % course_keys.size()


## The round's Wind.Level.
func wind_for(round_no: int) -> int:
	if weather == Weather.CHANGEABLE:
		var r := _rng(["wind", round_no])
		return Wind.Level.LIGHT + r.randi() % 3
	return WEATHER_WIND[weather]


# --- The person's rounds -----------------------------------------------------

## Who plays with the person in the next round, as field indexes.
func partner_indexes() -> Array[int]:
	var out: Array[int] = []
	var me := player_index()
	match format:
		Format.SKINS:
			for i in me:
				out.append(i)
			return out
		Format.MATCH:
			var m := _player_match()
			if not m.is_empty():
				out.append(int(m[1]) if int(m[0]) == me else int(m[0]))
			return out
	if partners <= 0 or not playing():
		return out
	var round_no := rounds_played()
	if round_no < 2 or tee_times != TeeTimes.DRAW:
		var r := _rng(["partners", round_no])
		var guard := 0
		while out.size() < partners and guard < 1000:
			guard += 1
			var i := r.randi() % me
			if not out.has(i) and _in_event(i):
				out.append(i)
		return out
	# At the weekend the draw goes by score: the golfers next to the person.
	var rows := standings()
	var at := -1
	for k in rows.size():
		if int(rows[k].index) == me:
			at = k
	for step in range(1, rows.size()):
		for k: int in [at - step, at + step]:
			if out.size() >= partners:
				return out
			if k >= 0 and k < rows.size() and str(rows[k].status).is_empty() and int(rows[k].index) != me:
				out.append(int(rows[k].index))
	return out


## The computer level a field golfer plays at (it plays its own numbers;
## the level gives its handicap index and course management).
func level_of(i: int) -> int:
	var avg := averages[i]
	if avg <= 2.0:
		return OpponentSkill.Level.TOUR
	if avg <= 6.0:
		return OpponentSkill.Level.SCRATCH
	if avg <= 13.0:
		return OpponentSkill.Level.CLUB
	return OpponentSkill.Level.BEGINNER


## The person's next round, or null if they have none to play.
func next_setup() -> RoundSetup:
	if not playing():
		return null
	var s := RoundSetup.new()
	var round_no := rounds_played()
	s.mode = GameModes.Mode.STROKE
	match format:
		Format.STABLEFORD:
			s.mode = GameModes.Mode.STABLEFORD
		Format.MATCH:
			s.mode = GameModes.Mode.MATCH
		Format.SKINS:
			s.mode = GameModes.Mode.SKINS
	s.holes = RoundSetup.Holes.FRONT_NINE if short_rounds else RoundSetup.Holes.ALL
	s.tees = RoundSetup.Tees.BACK if strength >= 2 else RoundSetup.Tees.MIDDLE
	var ci := course_index(round_no)
	s.course_key = course_keys[ci]
	s.course_name = course_names[ci]
	s.handicaps = false
	s.wind_level = wind_for(round_no)
	s.pin_seed = hash([tournament_seed, "pins", round_no]) & 0x7fffffff
	s.pins = 1 if round_no > 0 else 0  # new hole positions each day
	s.names.assign([player])
	s.teams.assign([0])
	s.computer.assign([RoundSetup.HUMAN])
	for i in partner_indexes():
		s.names.append(names[i])
		s.teams.append(s.teams.size() % 2)
		s.computer.append(level_of(i))
		s.pros[names[i]] = pros[i]
	s.tournament = round_id()
	return s


# --- Simulating the field ----------------------------------------------------

## The odds of each score (FIRST_SCORE up) on a par `par` hole for a golfer
## expected to score `mean` over par there: HOLE_ODDS tilted (exponentially)
## until their average is `mean`, which keeps the shape real: a better golfer
## makes more birdies and fewer bogeys, a weak one more doubles.
static func hole_odds(par: int, mean: float) -> PackedFloat64Array:
	var p := clampi(par, 3, 5)
	var key := p * 100000 + roundi(clampf(mean, -1.5, 3.0) * 400.0)
	if _odds_cache.has(key):
		return _odds_cache[key]
	var base: Array = HOLE_ODDS[p]
	var target := clampf(mean, -1.5, 3.0)
	var lo := -12.0
	var hi := 12.0
	var odds := PackedFloat64Array()
	for _it in 50:
		var lam := 0.5 * (lo + hi)
		odds = _tilt(base, lam)
		var m := 0.0
		for k in odds.size():
			m += odds[k] * (k + FIRST_SCORE)
		if m > target:
			lo = lam
		else:
			hi = lam
	_odds_cache[key] = odds
	return odds


static func _tilt(base: Array, lam: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var total := 0.0
	for k in base.size():
		var w := float(base[k]) * exp(-lam * (k + FIRST_SCORE))
		out.append(w)
		total += w
	for k in out.size():
		out[k] /= total
	return out


## The average score over par of HOLE_ODDS on a par `par`.
static func base_mean(par: int) -> float:
	var base: Array = HOLE_ODDS[clampi(par, 3, 5)]
	var m := 0.0
	var total := 0.0
	for k in base.size():
		m += float(base[k]) * (k + FIRST_SCORE)
		total += float(base[k])
	return m / total


## One hole's strokes.
static func draw_hole(par: int, mean: float, r: RandomNumberGenerator) -> int:
	var odds := hole_odds(par, mean)
	var u := r.randf()
	var acc := 0.0
	for k in odds.size():
		acc += odds[k]
		if u < acc:
			return maxi(1, par + k + FIRST_SCORE)
	return par + odds.size() - 1 + FIRST_SCORE


## A whole round for a golfer averaging `average` to par per 18 holes on a
## tour course, with `extra` strokes for the day (conditions and form).
## `stroke_index` (optional, 1 hardest) makes hard holes harder.
static func simulate_round(pars: Array[int], average: float, extra: float, r: RandomNumberGenerator,
		stroke_index: Array[int] = []) -> PackedInt32Array:
	var out := PackedInt32Array()
	var shift := (average + extra - TourPro.TOUR_TO_PAR) / 18.0
	for h in pars.size():
		var m := base_mean(pars[h]) + shift
		if h < stroke_index.size() and stroke_index[h] > 0:
			m += 0.12 * (1.0 - 2.0 * (stroke_index[h] - 1) / 17.0)
		out.append(draw_hole(pars[h], m, r))
	return out


## Starts round `rounds_played()`: draws every field golfer's round (the
## same every time for this tournament and round) and their tee times.
## `pars` and `stroke_index` are the holes the person is about to play.
func begin_round(id: String, pars: Array[int], stroke_index: Array[int] = []) -> bool:
	if id != round_id():
		return false
	var round_no := rounds_played()
	_live_round = round_no
	_strokes_index = stroke_index.duplicate()
	_live_pars_cache = pars.duplicate()
	var r := _rng(["round", round_no])
	var wind_level := wind_for(round_no)
	var day := r.randfn(0.0, 0.8)  # pins, firmness: the same for everyone
	_live.clear()
	_start.clear()
	var waves := _tee_times(round_no)
	for i in names.size():
		var p := pro(i)
		var streaky := p.streaky if p != null else 0.4
		var form := r.randfn(0.0, 0.7 + 1.0 * streaky)
		var avg := averages[i]
		var wind_cost: float = WIND_STROKES[wind_level] * (1.0 + clampf(avg / 12.0, 0.0, 1.5))
		var afternoon := waves[i] >= WAVE_GAP_HOLES - 0.01
		var wave_cost := (0.35 if afternoon else -0.15) * float(wind_level) / 2.0
		_live.append(simulate_round(pars, avg, day + form + wind_cost + wave_cost, r, stroke_index))
		_start.append(waves[i])
	return true


## Each golfer's tee time in holes from the first group of the day: two
## tees and two waves in the first two rounds, then (after the cut, with
## the draw) one tee in reverse order of score so the leaders go out last.
## Morning and Afternoon put the person's group near the start of that wave.
func _tee_times(round_no: int) -> Array[float]:
	var r := _rng(["tees", round_no])
	var me := player_index()
	var group := partner_indexes()
	group.append(me)
	var others: Array[int] = []
	for i in names.size():
		if not group.has(i) and _in_event(i):
			others.append(i)
	var by_score := tee_times == TeeTimes.DRAW and round_no >= 2
	if by_score:
		var rows := standings()
		var order: Array[int] = []
		for k in range(rows.size() - 1, -1, -1):
			var idx := int(rows[k].index)
			if others.has(idx):
				order.append(idx)
		others = order
	else:
		for i in range(others.size() - 1, 0, -1):
			var j := r.randi() % (i + 1)
			var tmp := others[i]
			others[i] = others[j]
			others[j] = tmp
	var times: Array[float] = []
	times.resize(names.size())
	times.fill(-1000.0)
	var size := 3
	var groups := int(ceil(others.size() / float(size))) + 1
	# Where the person's group goes in the order.
	var slot := 0
	if by_score:
		slot = groups - 1
		var rows := standings()
		for k in rows.size():
			if int(rows[k].index) == me:
				slot = clampi(groups - 1 - int(k / float(size)), 0, groups - 1)
	else:
		var morning := tee_times == TeeTimes.MORNING or (tee_times == TeeTimes.DRAW and (round_no + r.randi()) % 2 == 0)
		var half := int(groups / 2.0)
		slot = 1 if morning else half + 1
		slot = mini(slot, groups - 1)
	var g := 0
	var k := 0
	var two_tees := not by_score
	while g < groups:
		var t := _group_time(g, groups, two_tees)
		if g == slot:
			for i in group:
				times[i] = t
		else:
			for _m in size:
				if k < others.size():
					times[others[k]] = t
					k += 1
		g += 1
	return times


static func _group_time(g: int, groups: int, two_tees: bool) -> float:
	if not two_tees:
		return g * GROUP_GAP_HOLES
	var half := maxi(1, int(ceil(groups / 2.0)))
	var wave := 0 if g < half else 1
	var within := g - wave * half
	# Two tees: alternate groups start on the 1st and the 10th, the same time.
	return wave * WAVE_GAP_HOLES + int(within / 2.0) * GROUP_GAP_HOLES


## How many holes golfer `i` has played in the live round when the person
## has played `my_holes`.
func live_thru(i: int, my_holes: int) -> int:
	if _live_round != rounds_played() or i >= _live.size():
		return 0
	var holes: int = (_live[i] as PackedInt32Array).size()
	if i == player_index():
		return my_holes
	return clampi(int(floor(my_holes + _start[player_index()] - _start[i])), 0, holes)


## The live leaderboard while the person plays: every golfer still in,
## best first, as {index, name, total (to par, or points), today, thru,
## status, pos}. `real` maps the person's group by name to their hole
## scores so far.
func live_rows(my_holes: int, real: Dictionary) -> Array:
	var rows: Array = []
	for i in names.size():
		if not _in_event(i):
			continue
		var today := 0
		var thru := 0
		var played := PackedInt32Array()
		if real.has(names[i]):
			played = PackedInt32Array(real[names[i]])
			for s in played:
				if s > 0:
					thru += 1
		elif i < _live.size():
			thru = live_thru(i, my_holes)
			played = (_live[i] as PackedInt32Array).slice(0, thru)
		today = _round_value(played, _live_pars())
		rows.append({"index": i, "name": names[i], "today": today, "thru": thru,
			"total": _total(i) + today, "status": ""})
	_sort_rows(rows)
	_place(rows)
	return rows


func _live_pars() -> Array[int]:
	return _live_pars_cache


## Score of a (part) round: strokes to par, or Stableford points.
func _round_value(strokes: PackedInt32Array, pars: Array[int]) -> int:
	var v := 0
	for h in mini(strokes.size(), pars.size()):
		if strokes[h] <= 0:
			continue
		if format == Format.STABLEFORD:
			v += GameModes.stableford_points(strokes[h], pars[h])
		else:
			v += strokes[h] - pars[h]
	return v


## Golfer `i`'s total over the finished rounds.
func _total(i: int) -> int:
	var t := 0
	var rs: Array = scores[i]
	for k in rs.size():
		var pars: Array[int] = []
		pars.assign(Array(round_pars[k]))
		t += _round_value(rs[k], pars)
	return t


func total_of(i: int) -> int:
	return _total(i)


func _better(a: int, b: int) -> bool:
	return a > b if format == Format.STABLEFORD else a < b


func _sort_rows(rows: Array) -> void:
	var stableford := format == Format.STABLEFORD
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := 0 if str(a.status).is_empty() else (1 if a.status == "MC" else 2)
		var rb := 0 if str(b.status).is_empty() else (1 if b.status == "MC" else 2)
		if ra != rb:
			return ra < rb
		if a.total != b.total:
			return a.total > b.total if stableford else a.total < b.total
		if a.thru != b.thru:
			return a.thru > b.thru
		return a.index < b.index)


static func _place(rows: Array) -> void:
	for k in rows.size():
		if not str(rows[k].status).is_empty():
			rows[k].pos = str(rows[k].status)
			continue
		var first := k
		while first > 0 and rows[first - 1].total == rows[k].total and str(rows[first - 1].status).is_empty():
			first -= 1
		var tied: bool = first < k or (k + 1 < rows.size() and rows[k + 1].total == rows[k].total and str(rows[k + 1].status).is_empty())
		rows[k].pos = ("T%d" if tied else "%d") % (first + 1)


## The leaderboard between rounds, best first (as live_rows, with thru the
## holes of the last round).
func standings() -> Array:
	var rows: Array = []
	for i in names.size():
		var status := ""
		if i == player_index() and withdrawn:
			status = "WD"
		elif not made_cut.is_empty() and not made_cut[i]:
			status = "MC"
		var rs: Array = scores[i]
		var today := 0
		if not rs.is_empty():
			var pars: Array[int] = []
			pars.assign(Array(round_pars[rs.size() - 1]))
			today = _round_value(rs[-1], pars)
		rows.append({"index": i, "name": names[i], "total": _total(i), "today": today, "thru": rs.size(), "status": status})
	_sort_rows(rows)
	_place(rows)
	return rows


func _in_event(i: int) -> bool:
	if i == player_index() and withdrawn:
		return false
	return made_cut.is_empty() or made_cut[i]


## Adds the round just played: `played` maps the names in the person's group
## to their hole scores; everyone else's comes from begin_round. Returns what
## it meant ("Round 2: 68 (-4), T3. Made the cut at +1."), or "" if `id`
## isn't this tournament's next round.
func record_round(id: String, played: Dictionary, pars: Array[int], stroke_index: Array[int] = []) -> String:
	if id != round_id() or not playing():
		return ""
	if not played.has(player):
		return ""
	if _live_round != rounds_played():
		begin_round(id, pars, stroke_index)
	var round_no := rounds_played()
	match format:
		Format.MATCH:
			return _record_match(played, pars)
		Format.SKINS:
			return _record_skins(played, pars)
	for i in names.size():
		if not _in_event(i):
			continue
		var s: PackedInt32Array = PackedInt32Array(played[names[i]]) if played.has(names[i]) else _live[i]
		(scores[i] as Array).append(s)
	round_pars.append(PackedInt32Array(pars))
	round_winds.append(wind_for(round_no))
	_live_round = -1
	var me := player_index()
	var mine: PackedInt32Array = PackedInt32Array(played[player])
	var gross := 0
	for v in mine:
		gross += v
	var text := "%s, round %d: %d (%s)" % [title, round_no + 1, gross, _value_text(_round_value(mine, pars))]
	if has_cut() and rounds_played() == 2:
		_make_cut()
	if rounds_played() < rounds:
		var p := position_of(me)
		if made_cut.is_empty() or made_cut[me]:
			text += ", %s at %s." % [p.pos, _value_text(_total(me))]
		if not made_cut.is_empty() and rounds_played() == 2:
			text += (" Made the cut at %s." if made_cut[me] else " Missed the cut at %s.") % _value_text(cut_line())
		if not made_cut.is_empty() and not made_cut[me]:
			_play_out()
			text += " " + _finish()
	else:
		text += ". " + _finish()
	return text


func _value_text(v: int) -> String:
	return ("%d pts" % v) if format == Format.STABLEFORD else Scorecard.format_to_par(v)


## The person withdraws: the tournament is played out without them.
func withdraw() -> void:
	if not playing():
		return
	withdrawn = true
	if format == Format.MATCH:
		_play_out_bracket()
	elif format == Format.SKINS:
		_finish_skins()
	else:
		_play_out()
		_finish()


## Everyone still in plays the remaining rounds, simulated.
func _play_out() -> void:
	while rounds_played() < rounds:
		var pars: Array[int] = []
		if not round_pars.is_empty():
			pars.assign(Array(round_pars[-1]))
		else:
			for _h in (9 if short_rounds else 18):
				pars.append(4)
		begin_round(round_id(), pars, _strokes_index)
		for i in names.size():
			if _in_event(i):
				(scores[i] as Array).append(_live[i])
		round_pars.append(PackedInt32Array(pars))
		round_winds.append(wind_for(rounds_played()))
		_live_round = -1
		if has_cut() and rounds_played() == 2 and made_cut.is_empty():
			_make_cut()


func _make_cut() -> void:
	var line := cut_line()
	var made: Array[bool] = []
	for i in names.size():
		made.append(_in_event(i) and (scores[i] as Array).size() >= 2 and not _better(line, _total(i)))
	made_cut = made


## The score that makes the cut: the CUT_PLACES[cut]th best after two rounds.
func cut_line() -> int:
	var totals: Array[int] = []
	for i in names.size():
		if _in_event(i) and (scores[i] as Array).size() >= 2:
			totals.append(_total(i))
	if totals.is_empty():
		return 0
	totals.sort()
	if format == Format.STABLEFORD:
		totals.reverse()
	return totals[mini(CUT_PLACES[cut], totals.size()) - 1]


## Golfer `i`'s place: {pos ("T3"), place (3), tied}.
func position_of(i: int) -> Dictionary:
	for row: Dictionary in standings():
		if int(row.index) == i:
			var pos := str(row.pos)
			return {"pos": pos, "place": pos.trim_prefix("T").to_int(), "tied": pos.begins_with("T")}
	return {"pos": "", "place": 0, "tied": false}


## Sudden death between `tied` golfers (simulated holes); returns the winner.
func _playoff(tied: Array[int]) -> int:
	var r := _rng("playoff")
	var left := tied.duplicate()
	var guard := 0
	while left.size() > 1 and guard < 50:
		guard += 1
		var best := 99
		var hole := {}
		for i in left:
			var s := draw_hole(4, base_mean(4) + (averages[i] - TourPro.TOUR_TO_PAR) / 18.0, r)
			hole[i] = s
			best = mini(best, s)
		var next: Array[int] = []
		for i in left:
			if hole[i] == best:
				next.append(i)
		left = next
	return left[0]


## Pays out and keeps the person's result.
func _finish() -> String:
	var rows := standings()
	var finishers: Array[int] = []
	var keys: Array[int] = []
	for row: Dictionary in rows:
		if str(row.status).is_empty():
			finishers.append(int(row.index))
			keys.append(-int(row.total) if format == Format.STABLEFORD else int(row.total))
	var playoff := false
	if keys.size() > 1 and keys[0] == keys[1]:
		var tied: Array[int] = []
		for k in keys.size():
			if keys[k] == keys[0]:
				tied.append(finishers[k])
		var winner := _playoff(tied)
		finishers.erase(winner)
		finishers.insert(0, winner)
		playoff = true
	var paid: int = CUT_PLACES[cut] if has_cut() else mini(65, finishers.size())
	var pay := Career.payouts(keys, purse, mini(paid, finishers.size()), finishers.size() if has_cut() else paid, playoff)
	for k in finishers.size():
		money[finishers[k]] += pay[k]
	var me := player_index()
	var k_me := finishers.find(me)
	result = {"pos": 0, "tied": false, "money": 0, "winner": names[finishers[0]] if not finishers.is_empty() else "",
		"winning": keys[0] if not keys.is_empty() else 0, "playoff": playoff, "status": ""}
	if withdrawn:
		result.status = "WD"
	elif k_me < 0:
		result.status = "MC"
	else:
		var mine := keys[k_me]
		var pos := 1
		for v in keys:
			if v < mine:
				pos += 1
		var tied := keys.count(mine) > 1
		if playoff and mine == keys[0]:
			pos = 1 if k_me == 0 else 2
			tied = k_me > 0 and keys.count(mine) > 2
		result.pos = pos
		result.tied = tied
		result.money = pay[k_me]
	result.text = result_text()
	return str(result.text)


## "Won the Kauri Open at -14 ($1,800,000)!" and the like.
func result_text() -> String:
	if result.is_empty():
		return ""
	var winning := int(result.winning)
	var won_by := "%s won at %s%s." % [result.winner, _value_text(-winning if format == Format.STABLEFORD else winning),
		" in a playoff" if result.playoff else ""]
	if format == Format.MATCH or format == Format.SKINS:
		won_by = "%s won." % result.winner
	match str(result.status):
		"MC":
			return "Missed the cut. " + won_by
		"WD":
			return "Withdrew. " + won_by
		"OUT":
			return str(result.get("detail", "Knocked out.")) + " " + won_by
	var me := player_index()
	if int(result.pos) == 1:
		return "Won the %s%s! %s." % [title, " in a playoff" if result.playoff else "", Career.format_money(money[me])]
	return "Finished %s, %s. %s" % [Career.place_text(int(result.pos), result.tied), Career.format_money(money[me]), won_by]


# --- Match play --------------------------------------------------------------

## Seeds by scoring average (the person by theirs), drawn 1 v 16, 8 v 9...
func _make_bracket() -> void:
	var order: Array[int] = []
	for i in names.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return averages[a] < averages[b] or (averages[a] == averages[b] and a < b))
	var seeds := _seed_order(names.size())
	var first: Array = []
	for k in range(0, seeds.size(), 2):
		first.append([order[seeds[k] - 1], order[seeds[k + 1] - 1], -1, ""])
	bracket = [first]


## The standard draw: seed pairs top to bottom (1, 16, 8, 9, ...).
static func _seed_order(n: int) -> Array[int]:
	var s: Array[int] = [1, 2]
	while s.size() < n:
		var m := s.size() * 2
		var next: Array[int] = []
		for x in s:
			next.append(x)
			next.append(m + 1 - x)
		s = next
	return s


func _player_match() -> Array:
	if bracket.is_empty():
		return []
	for m: Array in bracket[-1]:
		if (int(m[0]) == player_index() or int(m[1]) == player_index()) and int(m[2]) < 0:
			return m
	return []


func _alive_in_bracket(i: int) -> bool:
	if bracket.is_empty():
		return false
	for m: Array in bracket[-1]:
		if int(m[0]) == i or int(m[1]) == i:
			return int(m[2]) < 0 or int(m[2]) == i
	return false


## A match from two cards: {winner (0, 1 or -1 level), text ("3&2", "1 up",
## "AS")}. Stops once it is decided.
static func match_result(a: PackedInt32Array, b: PackedInt32Array) -> Dictionary:
	var up := 0
	var n := mini(a.size(), b.size())
	for h in n:
		if a[h] <= 0 or b[h] <= 0:
			break
		if a[h] < b[h]:
			up += 1
		elif b[h] < a[h]:
			up -= 1
		var left := n - h - 1
		if absi(up) > left:
			var text := ("%d up" % absi(up)) if left == 0 else ("%d&%d" % [absi(up), left])
			return {"winner": 0 if up > 0 else 1, "text": text}
	return {"winner": -1, "text": "AS"}


## Plays a match between field golfers a and b, simulated, with sudden death
## if level.
func _sim_match(a: int, b: int, pars: Array[int], r: RandomNumberGenerator) -> Array:
	var sa := simulate_round(pars, averages[a], r.randfn(0.0, 1.2), r, _strokes_index)
	var sb := simulate_round(pars, averages[b], r.randfn(0.0, 1.2), r, _strokes_index)
	var res := match_result(sa, sb)
	if int(res.winner) >= 0:
		return [a, b, a if int(res.winner) == 0 else b, res.text]
	var winner := _playoff_pair(a, b, r)
	return [a, b, winner, "at the %d%s" % [pars.size() + 1, "th"]]


func _playoff_pair(a: int, b: int, r: RandomNumberGenerator) -> int:
	for _h in 30:
		var x := draw_hole(4, base_mean(4) + (averages[a] - TourPro.TOUR_TO_PAR) / 18.0, r)
		var y := draw_hole(4, base_mean(4) + (averages[b] - TourPro.TOUR_TO_PAR) / 18.0, r)
		if x != y:
			return a if x < y else b
	return a


func _record_match(played: Dictionary, pars: Array[int]) -> String:
	var m := _player_match()
	var me := player_index()
	var them := int(m[1]) if int(m[0]) == me else int(m[0])
	var mine := PackedInt32Array(played[player])
	var theirs := PackedInt32Array(played.get(names[them], []))
	var res := match_result(mine, theirs)
	var r := _rng(["match", rounds_played()])
	var winner := me if int(res.winner) == 0 else them
	var text := str(res.text)
	if int(res.winner) < 0:
		# Level after 18: sudden death (simulated for now).
		winner = _playoff_pair(me, them, r)
		text = "at the %dth" % (pars.size() + 1)
	m[2] = winner
	m[3] = text
	var round_name := _match_round_name(bracket.size() - 1)
	var out := "%s: %s %s %s." % [round_name, "You beat" if winner == me else "You lost to", names[them], text]
	_finish_bracket_round(pars, r)
	round_pars.append(PackedInt32Array(pars))
	round_winds.append(wind_for(rounds_played()))
	if winner != me:
		result = {"status": "OUT", "detail": "Knocked out in the %s." % round_name.to_lower(), "pos": 0, "tied": false,
			"money": 0, "winner": "", "winning": 0, "playoff": false}
		_play_out_bracket()
		return out + " " + str(result.text)
	if bracket[-1].size() == 1 and int(bracket[-1][0][2]) >= 0:
		_finish_match_play()
		return out + " " + str(result.text)
	return out + " Next: the %s." % _match_round_name(bracket.size() - 1).to_lower()


## The other matches of the round, then the next round's draw.
func _finish_bracket_round(pars: Array[int], r: RandomNumberGenerator) -> void:
	var current: Array = bracket[-1]
	for m: Array in current:
		if int(m[2]) < 0:
			var done := _sim_match(int(m[0]), int(m[1]), pars, r)
			m[2] = done[2]
			m[3] = done[3]
	if current.size() > 1:
		var next: Array = []
		for k in range(0, current.size(), 2):
			next.append([int(current[k][2]), int(current[k + 1][2]), -1, ""])
		bracket.append(next)


func _play_out_bracket() -> void:
	var pars: Array[int] = []
	if not round_pars.is_empty():
		pars.assign(Array(round_pars[-1]))
	else:
		for _h in (9 if short_rounds else 18):
			pars.append(4)
	var guard := 0
	while not (bracket[-1].size() == 1 and int(bracket[-1][0][2]) >= 0) and guard < 10:
		guard += 1
		_finish_bracket_round(pars, _rng(["bracket", bracket.size()]))
	_finish_match_play()


## Match play money: the winner a fifth of the purse, the runner-up half
## that, then shares by the round each golfer went out in.
func _finish_match_play() -> void:
	var champion := int(bracket[-1][0][2])
	var share := [0.2, 0.1, 0.05, 0.03, 0.015, 0.008, 0.004]
	var out_round := {}
	for k in bracket.size():
		for m: Array in bracket[k]:
			for who: int in [int(m[0]), int(m[1])]:
				if int(m[2]) >= 0 and who != int(m[2]):
					out_round[who] = k
	var last := bracket.size() - 1
	for i in names.size():
		var depth := 0 if i == champion else (1 + last - int(out_round.get(i, 0)))
		money[i] += roundi(purse * float(share[mini(depth, share.size() - 1)]))
	var me := player_index()
	var keep := result.duplicate()
	result = {"pos": 1 if champion == me else 0, "tied": false, "money": money[me], "winner": names[champion],
		"winning": 0, "playoff": false, "status": ""}
	if str(keep.get("status", "")) == "OUT":
		result.status = "OUT"
		result.detail = keep.detail
	elif withdrawn:
		result.status = "WD"
	elif champion != me:
		result.pos = 2
	result.text = result_text()


func _match_round_name(k: int) -> String:
	var left: int = (bracket[k] as Array).size() * 2
	match left:
		2:
			return "Final"
		4:
			return "Semi-finals"
		8:
			return "Quarter-finals"
	return "Round of %d" % left


## The draw, round by round: "Round of 16", then "Callum Reid beat Ryan Cole 3&2".
func bracket_lines() -> Array[String]:
	var out: Array[String] = []
	for k in bracket.size():
		out.append(_match_round_name(k).to_upper())
		for m: Array in bracket[k]:
			var a := names[int(m[0])]
			var b := names[int(m[1])]
			if int(m[2]) < 0:
				out.append("  %s v %s" % [a, b])
			else:
				var w := int(m[2])
				out.append("  %s beat %s %s" % [names[w], b if w == int(m[0]) else a, m[3]])
	return out


# --- Skins -------------------------------------------------------------------

## What hole `h` (0-based) of a round is worth: holes 1-6 one share, 7-12 two,
## 13-18 three (fewer holes: in thirds the same way).
func skin_value(h: int, holes: int) -> int:
	var third := maxi(1, int(ceil(holes / 3.0)))
	var shares := 0
	for k in holes:
		shares += 1 + int(k / float(third))
	return roundi(float(purse) / (shares * rounds) * (1 + int(h / float(third))))


func _record_skins(played: Dictionary, pars: Array[int]) -> String:
	var cards: Array = []
	for i in names.size():
		var s := PackedInt32Array(played.get(names[i], []))
		if s.size() < pars.size():
			s = simulate_round(pars, averages[i], 0.0, _rng(["skins", i, rounds_played()]), _strokes_index)
		cards.append(Array(s))
		(scores[i] as Array).append(s)
	var carried_in := 0
	var won_money: Array[int] = []
	won_money.resize(names.size())
	won_money.fill(0)
	if not skins_rounds.is_empty():
		carried_in = int(skins_rounds[-1].carried_money)
	var pot := carried_in
	var skins_count: Array[int] = []
	skins_count.resize(names.size())
	skins_count.fill(0)
	var res := GameModes.skins(cards)
	var winners: Array = res.hole_winner
	for h in winners.size():
		pot += skin_value(h, pars.size())
		var w := int(winners[h])
		if w >= 0:
			won_money[w] += pot
			skins_count[w] += 1
			pot = 0
	for i in names.size():
		money[i] += won_money[i]
	skins_rounds.append({"skins": skins_count, "money": won_money, "carried_money": pot})
	round_pars.append(PackedInt32Array(pars))
	round_winds.append(wind_for(rounds_played()))
	var me := player_index()
	var text := "%s, round %d: you won %s." % [title, rounds_played(), Career.format_money(won_money[me])]
	if pot > 0:
		text += " %s carries over." % Career.format_money(pot)
	if rounds_played() >= rounds:
		_finish_skins()
		text += " " + str(result.text)
	return text


func _finish_skins() -> void:
	var pot := int(skins_rounds[-1].carried_money) if not skins_rounds.is_empty() else purse
	if pot > 0:
		# Whatever is left goes to a sudden-death playoff.
		var all: Array[int] = []
		for i in names.size():
			if not (i == player_index() and withdrawn):
				all.append(i)
		money[_playoff(all)] += pot
		if not skins_rounds.is_empty():
			skins_rounds[-1].carried_money = 0
	var best := 0
	for i in names.size():
		if money[i] > money[best]:
			best = i
	var me := player_index()
	var place := 1
	for i in names.size():
		if money[i] > money[me]:
			place += 1
	result = {"pos": place, "tied": false, "money": money[me], "winner": names[best], "winning": 0, "playoff": false,
		"status": "WD" if withdrawn else ""}
	result.text = "Skins: you won %s, %s. %s won the most (%s)." % [Career.format_money(money[me]),
		Career.place_text(place, false) + _ordinal_suffix(place), names[best], Career.format_money(money[best])]


static func _ordinal_suffix(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "th"
	match n % 10:
		1: return "st"
		2: return "nd"
		3: return "rd"
	return "th"


# --- Text for the menus and the broadcast ------------------------------------

## "Round 2 of 4 at Kauri Cliffs. Windy. Purse $8,000,000."
func next_text() -> String:
	if over():
		return result_text()
	var round_no := rounds_played()
	var text := "%s. Round %d of %d at %s. %s. Purse %s." % [FORMAT_NAMES[format], round_no + 1, rounds,
		course_names[course_index(round_no)], WEATHER_NAMES[mini(weather, WEATHER_NAMES.size() - 1)] if weather != Weather.CHANGEABLE else Wind.LEVEL_NAMES[wind_for(round_no)] + " wind",
		Career.format_money(purse)]
	if format == Format.MATCH:
		var m := _player_match()
		if not m.is_empty():
			var them := int(m[1]) if int(m[0]) == player_index() else int(m[0])
			text = "%s: you play %s. Purse %s." % [_match_round_name(bracket.size() - 1), names[them], Career.format_money(purse)]
	return text


## The top of the leaderboard plus the person's line: "T3  Ann Byrne  -7".
func leaderboard_lines(top: int) -> Array[String]:
	var out: Array[String] = []
	if format == Format.MATCH:
		return bracket_lines()
	if format == Format.SKINS:
		for i in names.size():
			out.append("%s  %s" % [names[i], Career.format_money(money[i])])
		return out
	if rounds_played() == 0:
		return out
	var rows := standings()
	for k in rows.size():
		var row: Dictionary = rows[k]
		if k < top or int(row.index) == player_index():
			out.append("%s  %s  %s" % [row.pos, row.name, _value_text(int(row.total))])
		if k >= top and int(row.index) == player_index():
			break
	return out


## The field's notable scores on the holes they finished since `before`
## (the person's holes then) and `after`: birdies and better for the top of
## the board, as broadcast captions ("Birdie at the 7th: Callum Reid -6").
func live_news(before: int, after: int, top: int, real: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if format == Format.MATCH or format == Format.SKINS:
		return out
	var rows := live_rows(after, real)
	var pars := _live_pars()
	for k in mini(top, rows.size()):
		var i := int(rows[k].index)
		if real.has(names[i]) or i >= _live.size():
			continue
		var was := live_thru(i, before)
		var now := live_thru(i, after)
		for h in range(was, now):
			if h >= pars.size():
				break
			var diff: int = (_live[i] as PackedInt32Array)[h] - pars[h]
			if diff <= -1:
				var what := "Eagle" if diff == -2 else ("Albatross" if diff <= -3 else "Birdie")
				out.append("%s at the %d%s: %s %s, %s" % [what, h + 1, _ordinal_suffix(h + 1), names[i],
					_value_text(int(rows[k].total)), rows[k].pos])
	return out


# --- Saving -------------------------------------------------------------------

const _SAVED := ["title", "player", "format", "course_keys", "course_names", "rounds", "short_rounds", "strength",
	"field_kind", "field_size", "cut", "purse", "weather", "tee_times", "partners", "tournament_seed", "names",
	"pros", "averages", "scores", "round_pars", "round_winds", "made_cut", "withdrawn", "result", "money",
	"bracket", "skins_rounds"]


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _SAVED:
		var v: Variant = get(key)
		if v is Array:
			v = Array(v)
		cfg.set_value("tournament", key, v)
	cfg.save(path)


static func load_saved() -> Tournament:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("tournament"):
		return null
	var t := Tournament.new()
	t.title = str(cfg.get_value("tournament", "title", ""))
	t.player = str(cfg.get_value("tournament", "player", ""))
	t.format = clampi(int(cfg.get_value("tournament", "format", 0)), 0, FORMAT_NAMES.size() - 1) as Format
	t.course_keys.assign(cfg.get_value("tournament", "course_keys", []))
	t.course_names.assign(cfg.get_value("tournament", "course_names", []))
	t.rounds = clampi(int(cfg.get_value("tournament", "rounds", 4)), 1, 6)
	t.short_rounds = cfg.get_value("tournament", "short_rounds", false) == true
	t.strength = clampi(int(cfg.get_value("tournament", "strength", 3)), 0, STRENGTHS.size() - 1)
	t.field_kind = clampi(int(cfg.get_value("tournament", "field_kind", 0)), 0, FIELD_NAMES.size() - 1) as Field
	t.field_size = int(cfg.get_value("tournament", "field_size", 72))
	t.cut = clampi(int(cfg.get_value("tournament", "cut", 0)), 0, CUT_PLACES.size() - 1)
	t.purse = int(cfg.get_value("tournament", "purse", 1000000))
	t.weather = clampi(int(cfg.get_value("tournament", "weather", 1)), 0, WEATHER_NAMES.size() - 1) as Weather
	t.tee_times = clampi(int(cfg.get_value("tournament", "tee_times", 2)), 0, TEE_TIME_NAMES.size() - 1) as TeeTimes
	t.partners = int(cfg.get_value("tournament", "partners", 2))
	t.tournament_seed = int(cfg.get_value("tournament", "tournament_seed", 1))
	t.names.assign(cfg.get_value("tournament", "names", []))
	t.pros = cfg.get_value("tournament", "pros", [])
	t.averages.assign(cfg.get_value("tournament", "averages", []))
	t.scores = cfg.get_value("tournament", "scores", [])
	t.round_pars = cfg.get_value("tournament", "round_pars", [])
	t.round_winds.assign(cfg.get_value("tournament", "round_winds", []))
	t.made_cut.assign(cfg.get_value("tournament", "made_cut", []))
	t.withdrawn = cfg.get_value("tournament", "withdrawn", false) == true
	t.result = cfg.get_value("tournament", "result", {})
	t.money.assign(cfg.get_value("tournament", "money", []))
	t.bracket = cfg.get_value("tournament", "bracket", [])
	t.skins_rounds = cfg.get_value("tournament", "skins_rounds", [])
	if t.names.is_empty() or t.player.is_empty() or t.pros.size() != t.names.size() \
			or t.averages.size() != t.names.size() or t.scores.size() != t.names.size() \
			or t.money.size() != t.names.size() or t.course_keys.is_empty():
		return null
	return t
