class_name OpponentSkill
extends RefCounted
## How well a computer golfer swings: a GDScript port of
## libs/olcore/src/opponent.cpp. Change both together. The computer plans a
## shot through the real physics (ComputerGolfer), then this adds its
## mistakes to the swing inputs, never to the ball.
##
## A golfer is described by real-world numbers (STATS_*: drive, fairways,
## approach and chip proximity, eight-footers holed, mishits), which are
## turned into swing errors by tables measured through the physics
## (tools/olcalibrate), so a golfer with the PGA Tour's averages drives,
## approaches, chips and putts like the average tour pro.

enum Level { BEGINNER, CLUB, SCRATCH, TOUR }
## The kinds of shot a golfer is rated on. Mirrors olcore::ShotKind.
enum Kind { DRIVE, APPROACH, CHIP, PUTT }

const LEVEL_NAMES := ["Weekend golfer", "Club golfer", "Scratch golfer", "Tour pro"]

## Indexes into a golfer's stats.
const STAT_DRIVE_YD := 0
const STAT_FAIRWAYS := 1
const STAT_APPROACH_FT := 2
const STAT_CHIP_FT := 3
const STAT_PUTT8 := 4
const STAT_MISHIT := 5
## The PGA Tour's averages (ShotLink, 2015 to 2024).
const TOUR_STATS: Array[float] = [300.0, 60.0, 27.0, 6.5, 50.0, 0.2]
## Amateurs of about 18 and 9 handicap, scratch, the average tour pro.
const LEVEL_STATS := [
	[220.0, 45.0, 60.0, 14.0, 33.0, 6.0],
	[245.0, 50.0, 44.0, 10.0, 40.0, 2.5],
	[270.0, 56.0, 33.0, 7.8, 45.0, 0.8],
	[300.0, 60.0, 27.0, 6.5, 50.0, 0.2],
]
## Inside this a full swing is a chip or pitch. Mirrors olcore::kChipRangeM.
const CHIP_RANGE_M := 45.0
## Links 2003's physics: the face turned by a timing error of +/-1, and each
## kind of error's scale, so the same golfer hits the same numbers.
const LINKS_FACE_DEG_PER_ACCURACY := 4.5
const LINKS_ERROR_SCALE: Array[float] = [1.0, 0.9, 1.0, 0.9]
const _LONGEST_DRIVE_YD := 320.0

# (x, y) pairs, measured with tools/olcalibrate.
const _FAIRWAYS := [21.6, 0.750, 22.7, 0.700, 24.1, 0.650, 26.0, 0.600, 28.0, 0.550, 30.8, 0.500, 34.0, 0.450,
	37.6, 0.400, 42.2, 0.350, 48.5, 0.300, 56.2, 0.250, 65.5, 0.200, 78.2, 0.150, 94.0, 0.100]
const _APPROACH := [16.8, 0.600, 21.7, 0.800, 26.4, 1.000, 31.2, 1.200, 35.9, 1.400, 40.5, 1.600, 44.9, 1.800,
	49.2, 2.000, 53.4, 2.200, 57.5, 2.400, 61.5, 2.600, 65.4, 2.800, 69.2, 3.000, 73.0, 3.200, 76.8, 3.400]
const _CHIP := [4.0, 0.600, 5.3, 0.800, 6.6, 1.000, 7.9, 1.200, 9.2, 1.400, 10.5, 1.600, 11.8, 1.800,
	13.1, 2.000, 14.4, 2.200, 15.7, 2.400, 17.0, 2.600, 18.2, 2.800, 19.5, 3.000, 20.7, 3.200, 22.0, 3.400]
const _PUTT8 := [21.2, 3.800, 22.8, 3.600, 24.3, 3.400, 26.4, 3.200, 28.1, 3.000, 30.9, 2.800, 33.8, 2.600,
	36.6, 2.400, 39.8, 2.200, 44.0, 2.000, 49.1, 1.800, 55.0, 1.600, 62.4, 1.400, 70.5, 1.200]
const _LINKS_TEE := [2.7, 0, 3.2, 5, 3.5, 10, 3.9, 15, 5.3, 20, 6.4, 25, 8.0, 30, 9.9, 35, 10.5, 40, 12.4, 45,
	16.9, 50, 21.6, 55, 29.0, 60, 37.9, 65, 50.1, 70, 68.8, 75, 86.6, 80, 98.4, 85, 100.0, 90]
const _LINKS_APPROACH := [0.0, 100, 1.6, 95, 4.3, 90, 7.3, 85, 10.8, 80, 12.8, 75, 14.4, 70, 18.0, 65, 18.4, 60,
	20.8, 55, 22.8, 50, 24.5, 45, 26.6, 40, 28.9, 35, 31.1, 30, 37.2, 20, 40.1, 10, 41.9, 5, 44.2, 0]
const _LINKS_CHIP := [0.0, 100, 0.9, 95, 1.7, 90, 2.4, 85, 4.1, 80, 4.5, 75, 6.5, 70, 7.3, 65, 8.4, 60, 9.2, 50,
	10.0, 45, 11.1, 40, 11.7, 35, 13.9, 30, 14.1, 25, 16.9, 15, 18.9, 0]
const _LINKS_PUTT8 := [41.2, 0, 42.9, 5, 46.9, 10, 50.3, 15, 53.0, 20, 55.9, 25, 63.8, 30, 69.0, 35, 72.8, 40,
	79.7, 45, 83.9, 50, 89.0, 55, 92.8, 60, 96.3, 65, 99.0, 70, 100.0, 75]

# (distance, strokes) pairs: putts by feet, and from the fairway by yards.
const _GREEN := [
	0.0, 1.0, 2.0, 1.01, 3.0, 1.04, 5.0, 1.23, 8.0, 1.50, 10.0, 1.61,
	15.0, 1.78, 20.0, 1.87, 30.0, 1.98, 40.0, 2.06, 60.0, 2.20, 90.0, 2.40,
]
const _FAIRWAY := [
	0.0, 1.9, 10.0, 2.18, 20.0, 2.40, 40.0, 2.60, 60.0, 2.70, 100.0, 2.80,
	150.0, 2.98, 200.0, 3.19, 250.0, 3.45, 300.0, 3.71, 400.0, 4.08, 500.0, 4.50,
]
const _YARDS_PER_METRE := 1.0936133
const _FEET_PER_METRE := 3.2808399

var level: Level = Level.CLUB
## The golfer's numbers (STAT_*).
var stats := PackedFloat64Array()
## Swing errors by Kind: [power sd, accuracy sd, aim sd (deg)].
var shots: Array[PackedFloat64Array] = []
var mishit_chance := 0.0
var strength := 1.0
var links_strength := 1.0
## Weighs the risk of a miss when choosing a shot.
var course_management := true
## Ratings for Links 2003's own miss generators (Classic computer golfers):
## tee, woods and irons, chips, putts, max power.
var links_tee := 85
var links_irons := 85
var links_chips := 85
var links_putts := 85
var links_max_power := 100


## A golfer of `p_level`, or with the numbers in `p_stats` (STAT_* order).
func _init(p_level: int = Level.CLUB, p_stats: PackedFloat64Array = PackedFloat64Array()) -> void:
	level = clampi(p_level, 0, LEVEL_STATS.size() - 1) as Level
	stats = p_stats.duplicate() if p_stats.size() >= 6 else PackedFloat64Array(LEVEL_STATS[level])
	course_management = level != Level.BEGINNER
	_make_profile()


func level_name() -> String:
	return LEVEL_NAMES[level]


## Mirrors olcore::golfer_profile.
func _make_profile() -> void:
	var reach := clampf(stats[STAT_DRIVE_YD] / _LONGEST_DRIVE_YD, 0.3, 1.0)
	var drive := _interpolate(_FAIRWAYS, stats[STAT_FAIRWAYS], 0.0) / pow(reach, 1.7)
	var mishit := clampf(stats[STAT_MISHIT] / 100.0, 0.0, 0.5)
	var approach := _interpolate(_APPROACH, maxf(5.0, stats[STAT_APPROACH_FT] - 150.0 * mishit), 0.0)
	var chip := _interpolate(_CHIP, stats[STAT_CHIP_FT], 0.0)
	var line := _interpolate(_PUTT8, stats[STAT_PUTT8], 0.0)
	shots = [
		PackedFloat64Array([0.17 * drive, drive, 3.5 * drive]),
		PackedFloat64Array([0.06 * approach, 0.30 * approach, 1.8 * approach]),
		PackedFloat64Array([0.07 * chip, 0.25 * chip, 2.2 * chip]),
		PackedFloat64Array([0.025 * line, 0.0, line]),
	]
	mishit_chance = mishit
	strength = clampf(pow(reach, 1.45), 0.2, 1.0)
	links_strength = reach
	links_tee = _rating(_LINKS_TEE, stats[STAT_FAIRWAYS])
	links_irons = _rating(_LINKS_APPROACH, stats[STAT_APPROACH_FT])
	links_chips = _rating(_LINKS_CHIP, stats[STAT_CHIP_FT])
	links_putts = _rating(_LINKS_PUTT8, stats[STAT_PUTT8])
	links_max_power = roundi(100.0 * strength)


static func _rating(table: Array, x: float) -> int:
	return roundi(clampf(_interpolate(table, x, 0.0), 0.0, 100.0))


## The golfer for Links 2003's own computer miss generators.
func links_ratings() -> LinksLaunch.GolferRatings:
	var g := LinksLaunch.GolferRatings.new()
	g.tee = links_tee
	g.woods = links_irons
	g.long_irons = links_irons
	g.mid_irons = links_irons
	g.short_irons = links_irons
	g.wedges = links_irons
	g.chips = links_chips
	g.long_putts = links_putts
	g.short_putts = links_putts
	g.max_power = links_max_power
	return g


## Mirrors olcore::shot_kind.
static func kind_of(putter: bool, teed_up: bool, wood: bool, distance_m: float) -> Kind:
	if putter:
		return Kind.PUTT
	if distance_m < CHIP_RANGE_M:
		return Kind.CHIP
	return Kind.DRIVE if teed_up and wood else Kind.APPROACH


## Mirrors olcore::execute_shot: the swing made when meaning to make
## (power, accuracy, aim_deg). `error_scale` multiplies every error (form and
## pressure). Returns [power, accuracy, aim_deg].
func execute(power: float, accuracy: float, aim_deg: float, kind: int, error_scale: float, rng: Rng) -> PackedFloat64Array:
	var e: PackedFloat64Array = shots[clampi(kind, 0, shots.size() - 1)]
	var k := maxf(0.0, error_scale)
	if kind == Kind.PUTT:
		var pace := rng.normal()
		var line := rng.normal()
		rng.normal()  # keeps the draws the same as a full swing's
		return PackedFloat64Array([clampf(power * (1.0 + pace * e[0] * k), 0.0, 1.0), accuracy, aim_deg + line * e[2] * k])
	var dp := rng.normal()
	var timing := rng.normal()
	var da := rng.normal()
	var p := power * (1.0 + dp * e[0] * k)
	var acc := accuracy + timing * e[1] * k
	var aim := aim_deg + da * e[2] * k
	if rng.uniform() < mishit_chance * minf(k, 2.0):
		# A duff or a top: well short, and often off line.
		p *= 0.35 + 0.35 * rng.uniform()
		acc += (rng.uniform() - 0.5) * 1.2
	return PackedFloat64Array([clampf(p, 0.0, 1.0), clampf(acc, -1.0, 1.0), aim])


## Mirrors olcore::expected_strokes: average strokes for a good player to hole
## out from `distance_m` on `lie`.
static func expected_strokes(distance_m: float, lie: int) -> float:
	var green := _interpolate(_GREEN, distance_m * _FEET_PER_METRE, 0.004)
	var fairway := _interpolate(_FAIRWAY, distance_m * _YARDS_PER_METRE, 0.0045)
	match lie:
		Surface.Type.GREEN:
			return green
		Surface.Type.FRINGE:
			return minf(green + 0.1, fairway)
		Surface.Type.ROUGH:
			return fairway + 0.2
		Surface.Type.DEEP_ROUGH:
			return fairway + 0.45
		Surface.Type.SAND:
			return fairway + 0.35
	return fairway


static func _interpolate(table: Array, x: float, slope_past_end: float) -> float:
	if x <= float(table[0]):
		return table[1]
	var n := table.size()
	for i in range(2, n, 2):
		var x1: float = table[i]
		if x <= x1:
			var x0: float = table[i - 2]
			var y0: float = table[i - 1]
			var y1: float = table[i + 1]
			return y0 + (x - x0) / (x1 - x0) * (y1 - y0)
	return float(table[n - 1]) + (x - float(table[n - 2])) * slope_past_end


## Mirrors olcore::OpponentRng (xorshift32), so seeded rounds match the core.
class Rng:
	var state := 0x9e3779b9

	func _init(seed_value: int = 1) -> void:
		var s := seed_value & 0xffffffff
		state = s if s != 0 else 0x9e3779b9

	func next() -> int:
		var x := state
		x ^= (x << 13) & 0xffffffff
		x ^= x >> 17
		x ^= (x << 5) & 0xffffffff
		state = x
		return x

	## [0, 1), 24 bits.
	func uniform() -> float:
		return float(next() >> 8) / 16777216.0

	## Standard normal (Box-Muller, one value per call).
	func normal() -> float:
		var u1 := 1.0 - uniform()
		var u2 := uniform()
		return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
