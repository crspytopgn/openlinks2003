class_name TourPro
extends RefCounted
## A computer golfer's identity: how well it plays (real-world numbers, see
## OpponentSkill) and how it goes about it.
##
## - shape: the shot it plays, -1 a big draw to +1 a big fade (0 straight).
## - aggression: 0 plays to the fat of the green and dies putts in the hole,
##   1 attacks every flag and charges putts.
## - management: 0 picks the shot that is best if struck perfectly, 1 weighs
##   its own likely misses (water, bunkers, short sides) carefully.
## - nerve: under pressure (late in a close round) -1 tightens up and misses
##   more, +1 raises its game.
## - streaky: how much its form swings from round to round and hole to hole.
## - routine_s: its pre-shot routine in real seconds (tour players take about
##   20 to 50); the game plays it faster in proportion.
##
## The named pros share their names with GolferRoster, which gives them their
## looks. Everyone else in a tournament field is made up by generate().
## Game-side only.

const NAME := 0
const STATS := 1
const STYLE := 2
const ABOUT := 3

## name, [drive yd, fairways %, approach ft, chip ft, 8 ft putts %, mishits %],
## [shape, aggression, management, nerve, streaky, routine s, practice swings],
## what they are like.
const ROSTER := [
	["Callum Reid", [296.0, 68.0, 24.5, 6.4, 49.0, 0.15], [0.6, 0.45, 0.85, 0.4, 0.25, 32.0, 1],
		"Low, precise fade. Plots his way round and loves a wind."],
	["Marcus Bell", [318.0, 52.0, 26.5, 6.8, 48.0, 0.3], [-0.3, 0.85, 0.45, 0.2, 0.6, 28.0, 1],
		"The longest hitter out here. Goes for everything."],
	["Kenji Morita", [286.0, 74.0, 26.0, 5.6, 56.0, 0.1], [0.1, 0.3, 0.9, 0.6, 0.15, 45.0, 2],
		"Short but dead straight, and the best putter on tour. Slow and deliberate."],
	["Henrik Lindqvist", [292.0, 64.0, 23.2, 6.6, 46.0, 0.15], [0.35, 0.4, 0.95, 0.7, 0.2, 38.0, 1],
		"Veteran iron player. Ice cold when it matters."],
	["Daniel Okafor", [305.0, 61.0, 25.8, 6.2, 51.0, 0.2], [-0.5, 0.6, 0.7, 0.1, 0.4, 30.0, 1],
		"High draw, no weaknesses."],
	["Ryan Cole", [314.0, 55.0, 27.5, 6.9, 53.0, 0.35], [-0.2, 0.95, 0.35, 0.5, 0.85, 20.0, 0],
		"Young, fearless and streaky. Plays fast."],
	["Sanjay Mehta", [290.0, 63.0, 28.0, 5.2, 52.0, 0.2], [0.2, 0.5, 0.75, 0.3, 0.35, 34.0, 1],
		"Short-game wizard. Gets up and down from anywhere."],
	["Tom Brennan", [278.0, 70.0, 28.5, 5.8, 47.0, 0.25], [0.4, 0.25, 1.0, 0.8, 0.3, 26.0, 0],
		"Crafty old pro. Never in trouble, never rattled."],
	["Luis Navarro", [302.0, 54.0, 27.0, 5.5, 50.0, 0.3], [-0.7, 0.75, 0.5, 0.4, 0.6, 24.0, 1],
		"Big hook, big flair, great scrambler."],
	["Mateo Ibarra", [310.0, 58.0, 24.8, 6.6, 44.0, 0.2], [-0.1, 0.6, 0.65, -0.5, 0.45, 40.0, 2],
		"Superb ball-striker whose putter lets him down under pressure."],
	["Seo-yeon Han", [262.0, 80.0, 26.5, 6.2, 52.0, 0.1], [0.15, 0.35, 0.9, 0.6, 0.15, 42.0, 2],
		"A machine: fairway, green, two putts."],
	["Emma Larsen", [278.0, 66.0, 28.0, 6.9, 49.0, 0.25], [-0.35, 0.75, 0.55, 0.2, 0.5, 27.0, 1],
		"Long and aggressive, a birdie machine on her day."],
	["Aiko Tanaka", [248.0, 78.0, 28.5, 5.6, 56.0, 0.1], [0.25, 0.4, 0.85, 0.4, 0.25, 36.0, 1],
		"Short off the tee, deadly on the greens."],
	["Grace Mensah", [265.0, 70.0, 25.5, 6.8, 47.0, 0.2], [0.45, 0.7, 0.6, 0.0, 0.55, 30.0, 1],
		"Attacks flags with a crisp fade."],
	["Sofia Ricci", [258.0, 72.0, 28.2, 5.4, 50.0, 0.2], [-0.45, 0.6, 0.7, 0.3, 0.5, 29.0, 1],
		"Creative shotmaker with soft hands."],
	["Brooke Ashford", [252.0, 79.0, 27.5, 6.0, 51.0, 0.15], [0.3, 0.3, 0.95, 0.7, 0.2, 33.0, 1],
		"Steady veteran who rarely makes a bogey."],
]
## The women in ROSTER (from Seo-yeon Han on).
const FIRST_WOMAN := 10

## Strokes gained per round for each number better than the tour average,
## rounded from published strokes-gained studies (Broadie, "Every Shot
## Counts", 2014): 20 yards of driving is worth about 0.75 a round, a foot
## closer from 150 yards about 0.2, a point of eight-footers about 0.1.
const SG_PER := [0.0375, 0.02, -0.22, -0.33, 0.11, -0.21]
## The average tour pro's score to par on an average par-72 tour course
## (Tournament.HOLE_ODDS adds up to this).
const TOUR_TO_PAR := -0.6

var name := ""
var stats := PackedFloat64Array(OpponentSkill.TOUR_STATS)
var shape := 0.0
var aggression := 0.5
var management := 0.7
var nerve := 0.0
var streaky := 0.4
var routine_s := 30.0
var practice_swings := 1
var about := ""
## A named pro from ROSTER.
var named := false


static func roster() -> Array[TourPro]:
	var out: Array[TourPro] = []
	for row: Array in ROSTER:
		out.append(_from_row(row))
	return out


static func roster_names() -> Array[String]:
	var out: Array[String] = []
	for row: Array in ROSTER:
		out.append(str(row[NAME]))
	return out


static func _from_row(row: Array) -> TourPro:
	var p := TourPro.new()
	p.name = str(row[NAME])
	p.stats = PackedFloat64Array(row[STATS])
	var style: Array = row[STYLE]
	p.shape = style[0]
	p.aggression = style[1]
	p.management = style[2]
	p.nerve = style[3]
	p.streaky = style[4]
	p.routine_s = style[5]
	p.practice_swings = int(style[6])
	p.about = str(row[ABOUT])
	p.named = true
	return p


## The named pro called `who` (any case), or null.
static func find(who: String) -> TourPro:
	var key := who.strip_edges().to_lower()
	for row: Array in ROSTER:
		if str(row[NAME]).to_lower() == key:
			return _from_row(row)
	return null


## A middle-of-the-road golfer of a skill level, with a style drawn from
## `seed_value` so two of them don't play alike.
static func for_level(level: int, seed_value: int) -> TourPro:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var p := TourPro.new()
	p.stats = PackedFloat64Array(OpponentSkill.LEVEL_STATS[clampi(level, 0, OpponentSkill.LEVEL_STATS.size() - 1)])
	_draw_style(p, r)
	if level == OpponentSkill.Level.BEGINNER:
		p.management = r.randf_range(0.0, 0.3)  # weekend golfers rarely play the percentages
	return p


## A made-up golfer of skill `level` (0 the weekend golfer to 3 the tour
## average, up to about 3.6 for the very best; see OpponentSkill.LEVEL_STATS),
## with their own strengths, weaknesses and style. `women`: numbers like the
## women's tour (shorter, straighter).
static func generate(who: String, level: float, women: bool, r: RandomNumberGenerator) -> TourPro:
	var p := TourPro.new()
	p.name = who
	var base := level_stats(level)
	if women:
		# The LPGA Tour against the PGA Tour: about 45 yards shorter, more
		# fairways, a little further away with longer clubs.
		base[OpponentSkill.STAT_DRIVE_YD] -= 45.0
		base[OpponentSkill.STAT_FAIRWAYS] += 11.0
		base[OpponentSkill.STAT_APPROACH_FT] += 1.5
	# Real players trade one strength for another: longer hitters find fewer
	# fairways.
	var long := r.randfn(0.0, 9.0)
	base[OpponentSkill.STAT_DRIVE_YD] += long
	base[OpponentSkill.STAT_FAIRWAYS] += -0.45 * long + r.randfn(0.0, 4.5)
	base[OpponentSkill.STAT_APPROACH_FT] *= exp(r.randfn(0.0, 0.07))
	base[OpponentSkill.STAT_CHIP_FT] *= exp(r.randfn(0.0, 0.08))
	base[OpponentSkill.STAT_PUTT8] += r.randfn(0.0, 3.0)
	base[OpponentSkill.STAT_FAIRWAYS] = clampf(base[OpponentSkill.STAT_FAIRWAYS], 25.0, 88.0)
	base[OpponentSkill.STAT_PUTT8] = clampf(base[OpponentSkill.STAT_PUTT8], 20.0, 65.0)
	p.stats = base
	_draw_style(p, r)
	return p


static func _draw_style(p: TourPro, r: RandomNumberGenerator) -> void:
	p.shape = clampf(r.randfn(0.0, 0.4), -0.9, 0.9)
	p.aggression = r.randf_range(0.2, 0.9)
	p.management = r.randf_range(0.4, 1.0)
	p.nerve = clampf(r.randfn(0.0, 0.4), -1.0, 1.0)
	p.streaky = r.randf_range(0.1, 0.8)
	p.routine_s = clampf(r.randfn(32.0, 7.0), 18.0, 55.0)
	p.practice_swings = r.randi() % 3


## The numbers of a golfer of skill `level` (fractional levels in between,
## past 3 better than the tour average).
static func level_stats(level: float) -> PackedFloat64Array:
	var rows := OpponentSkill.LEVEL_STATS
	var x := clampf(level, 0.0, 4.0)
	var i := mini(int(floor(x)), rows.size() - 2)
	var f := x - i
	var a: Array = rows[i]
	var b: Array = rows[i + 1]
	var out := PackedFloat64Array()
	for k in a.size():
		out.append(lerpf(float(a[k]), float(b[k]), f))
	out[OpponentSkill.STAT_MISHIT] = maxf(0.05, out[OpponentSkill.STAT_MISHIT])
	return out


func to_dict() -> Dictionary:
	return {"name": name, "stats": Array(stats), "shape": shape, "aggression": aggression, "management": management,
		"nerve": nerve, "streaky": streaky, "routine_s": routine_s, "practice_swings": practice_swings, "about": about,
		"named": named}


static func from_dict(d: Dictionary) -> TourPro:
	var p := TourPro.new()
	p.name = str(d.get("name", ""))
	var st: Array = d.get("stats", [])
	if st.size() >= OpponentSkill.TOUR_STATS.size():
		p.stats = PackedFloat64Array(st)
	p.shape = float(d.get("shape", 0.0))
	p.aggression = float(d.get("aggression", 0.5))
	p.management = float(d.get("management", 0.7))
	p.nerve = float(d.get("nerve", 0.0))
	p.streaky = float(d.get("streaky", 0.4))
	p.routine_s = float(d.get("routine_s", 30.0))
	p.practice_swings = int(d.get("practice_swings", 1))
	p.about = str(d.get("about", ""))
	p.named = bool(d.get("named", false))
	return p


## The skill level (as generate takes it) whose golfer averages `avg` to
## par per 18 holes.
static func level_for_average(avg: float) -> float:
	var best := 3.0
	var err := INF
	var p := TourPro.new()
	for k in 201:
		var lv := k * 0.02
		p.stats = level_stats(lv)
		var e := absf(p.scoring_average() - avg)
		if e < err:
			err = e
			best = lv
	return best


## How it swings.
func skill(level := OpponentSkill.Level.TOUR) -> OpponentSkill:
	return OpponentSkill.new(level, stats)


## Strokes gained against the average tour pro per round, from its numbers.
func strokes_gained() -> float:
	var sg := 0.0
	for k in SG_PER.size():
		sg += float(SG_PER[k]) * (stats[k] - OpponentSkill.TOUR_STATS[k])
	return sg


## Its scoring average to par per 18 holes on an average tour course.
func scoring_average() -> float:
	return TOUR_TO_PAR - strokes_gained()


## Strengths and weaknesses in a few words: "Long, wild, great putter".
func profile_text() -> String:
	var parts: Array[String] = []
	var d := stats[OpponentSkill.STAT_DRIVE_YD]
	var tour := OpponentSkill.TOUR_STATS
	if d >= 310.0:
		parts.append("very long")
	elif d >= 302.0:
		parts.append("long")
	elif d < 285.0:
		parts.append("short")
	var fw := stats[OpponentSkill.STAT_FAIRWAYS]
	if fw >= 70.0:
		parts.append("very straight")
	elif fw < 54.0:
		parts.append("wild off the tee")
	var ap := stats[OpponentSkill.STAT_APPROACH_FT]
	if ap <= tour[OpponentSkill.STAT_APPROACH_FT] - 2.5:
		parts.append("great iron player")
	elif ap >= tour[OpponentSkill.STAT_APPROACH_FT] + 2.5:
		parts.append("loose irons")
	var ch := stats[OpponentSkill.STAT_CHIP_FT]
	if ch <= 5.6:
		parts.append("brilliant short game")
	elif ch >= 7.5:
		parts.append("weak short game")
	var pt := stats[OpponentSkill.STAT_PUTT8]
	if pt >= 54.0:
		parts.append("great putter")
	elif pt <= 45.0:
		parts.append("shaky putter")
	if shape >= 0.4:
		parts.append("fade")
	elif shape <= -0.4:
		parts.append("draw")
	if aggression >= 0.8:
		parts.append("aggressive")
	elif aggression <= 0.3:
		parts.append("cautious")
	if nerve >= 0.6:
		parts.append("clutch")
	elif nerve <= -0.4:
		parts.append("nervy")
	if parts.is_empty():
		return "Solid all round"
	var text := ", ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


## "302 yd, 61% fairways, 26 ft from 150, 51% from 8 ft".
func stats_text() -> String:
	return "%d yd, %d%% fairways, %d ft from 150 yd, %d%% from 8 ft" % [roundi(stats[0]), roundi(stats[1]),
		roundi(stats[2]), roundi(stats[4])]
