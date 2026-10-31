class_name OpponentSkill
extends RefCounted
## How well a computer golfer swings: a GDScript port of
## libs/olcore/src/opponent.cpp. Change both together. The computer plans a
## shot through the real physics (ComputerGolfer), then this adds the mistakes
## of its level to the swing inputs, never to the ball.

enum Level { BEGINNER, CLUB, SCRATCH, TOUR }

const LEVEL_NAMES := ["Weekend golfer", "Club golfer", "Scratch golfer", "Tour pro"]

# power sd, accuracy sd, aim sd (deg), putt pace sd, putt aim sd (deg),
# mishit chance, strength, course management
const PROFILES := [
	[0.075, 0.60, 2.0, 0.160, 1.90, 0.060, 0.80, false],
	[0.055, 0.38, 1.4, 0.110, 1.50, 0.025, 0.88, true],
	[0.040, 0.26, 1.0, 0.080, 1.25, 0.008, 0.95, true],
	[0.030, 0.18, 0.8, 0.060, 1.00, 0.002, 1.00, true],
]

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
var power_sd := 0.0
var accuracy_sd := 0.0
var aim_sd_deg := 0.0
var putt_power_sd := 0.0
var putt_aim_sd_deg := 0.0
var mishit_chance := 0.0
var strength := 1.0
var course_management := true


func _init(p_level: int = Level.CLUB) -> void:
	level = clampi(p_level, 0, PROFILES.size() - 1) as Level
	var p: Array = PROFILES[level]
	power_sd = p[0]
	accuracy_sd = p[1]
	aim_sd_deg = p[2]
	putt_power_sd = p[3]
	putt_aim_sd_deg = p[4]
	mishit_chance = p[5]
	strength = p[6]
	course_management = p[7]


func level_name() -> String:
	return LEVEL_NAMES[level]


## Mirrors olcore::execute_swing: the swing made when meaning to make
## (power, accuracy, aim_deg). Returns [power, accuracy, aim_deg].
func execute(power: float, accuracy: float, aim_deg: float, putter: bool, rng: Rng) -> PackedFloat64Array:
	if putter:
		var pace := rng.normal()
		var line := rng.normal()
		rng.normal()  # keeps the draws the same as a full swing's
		return PackedFloat64Array([clampf(power * (1.0 + pace * putt_power_sd), 0.0, 1.0), accuracy, aim_deg + line * putt_aim_sd_deg])
	var dp := rng.normal()
	var timing := rng.normal()
	var da := rng.normal()
	var p := power * (1.0 + dp * power_sd)
	var acc := accuracy + timing * accuracy_sd
	var aim := aim_deg + da * aim_sd_deg
	if rng.uniform() < mishit_chance:
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
