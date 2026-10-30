class_name Wind
extends RefCounted
## Wind for a round: a prevailing direction for the whole round, a speed and
## a shift for each hole, and a small change between shots. The physics takes
## velocity(), the velocity of the air in m/s.
##
## The ranges are guesses, not values from Links 2003 (see docs/formats/physics.md).

enum Level { OFF, LIGHT, MODERATE, STRONG }

const LEVEL_NAMES := ["Off", "Light", "Moderate", "Strong"]
const MAX_MPH := [0.0, 8.0, 15.0, 25.0]  ## strongest hole wind at each level
const MIN_FRACTION := 0.2  ## a hole's wind is 20% to 100% of the level's top speed
const HOLE_SHIFT_DEG := 45.0  ## a hole's direction strays this far from the prevailing one
const SHOT_SHIFT_DEG := 10.0  ## and moves this much between shots
const SHOT_SPEED_CHANGE := 0.15  ## speed changes by up to 15% between shots
const MPS_PER_MPH := 0.44704
const CALM_MPH := 0.5

var level: int = Level.MODERATE
var speed_mps := 0.0
## Direction the wind blows towards, as an azimuth like the aim: 0 is +z,
## positive is towards +x (the golfer's left when aiming down +z).
var towards_deg := 0.0

var _rng := RandomNumberGenerator.new()
var _prevailing_deg := 0.0
var _hole_deg := 0.0
var _hole_fraction := 0.0
var _shot_factor := 1.0


## `seed_value` 0 picks a random seed.
func _init(wind_level: int = Level.MODERATE, seed_value := 0) -> void:
	level = clampi(wind_level, Level.OFF, Level.STRONG)
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_prevailing_deg = _rng.randf_range(-180.0, 180.0)
	start_hole()


## New conditions for the next hole.
func start_hole() -> void:
	_hole_deg = _prevailing_deg + _rng.randf_range(-HOLE_SHIFT_DEG, HOLE_SHIFT_DEG)
	_hole_fraction = _rng.randf_range(MIN_FRACTION, 1.0)
	_shot_factor = 1.0
	towards_deg = wrapf(_hole_deg, -180.0, 180.0)
	_update_speed()


## A small change before the next shot on the same hole.
func next_shot() -> void:
	towards_deg = wrapf(_hole_deg + _rng.randf_range(-SHOT_SHIFT_DEG, SHOT_SHIFT_DEG), -180.0, 180.0)
	_shot_factor = 1.0 + _rng.randf_range(-SHOT_SPEED_CHANGE, SHOT_SPEED_CHANGE)
	_update_speed()


## Changes the strength setting; takes effect at once.
func set_level(wind_level: int) -> void:
	level = clampi(wind_level, Level.OFF, Level.STRONG)
	_update_speed()


func velocity() -> Vector3:
	var r := deg_to_rad(towards_deg)
	return Vector3(sin(r), 0.0, cos(r)) * speed_mps


func speed_mph() -> float:
	return speed_mps / MPS_PER_MPH


func is_calm() -> bool:
	return speed_mph() < CALM_MPH


## Where the wind blows relative to a shot aimed at `aim_deg`: 0 is straight
## downrange (helping), 90 towards the golfer's left, 180 into the face.
func relative_deg(aim_deg: float) -> float:
	return wrapf(towards_deg - aim_deg, -180.0, 180.0)


## For the HUD, such as "12 mph, helping, right to left".
func describe(aim_deg: float) -> String:
	if is_calm():
		return "calm"
	var mph := speed_mph()
	var rel := deg_to_rad(relative_deg(aim_deg))
	var along := cos(rel)
	var side := sin(rel)
	var parts := PackedStringArray(["%d mph" % roundi(mph)])
	if along > 0.38:
		parts.append("helping")
	elif along < -0.38:
		parts.append("against")
	if side > 0.38:
		parts.append("right to left")
	elif side < -0.38:
		parts.append("left to right")
	return ", ".join(parts)


func _update_speed() -> void:
	speed_mps = float(MAX_MPH[level]) * _hole_fraction * _shot_factor * MPS_PER_MPH
