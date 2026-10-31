class_name WindGust
extends RefCounted
## Visual gusts and lulls on top of the hole's steady wind. Real wind is
## never steady: flags, trees and grass surge and settle every few seconds.
## This only moves what the player sees (the flag, the grass, the trees and
## the water ripples, through the `wind_vector` shader global); the ball
## still flies in the game's own per-shot wind, so the physics is unchanged.
##
## The gust factor is a sum of a few slow, unrelated sines, so it never
## repeats in a way the eye can pick up, and it stays between LULL and PEAK.

const LULL := 0.55  ## the wind drops to this much of its speed in a lull
const PEAK := 1.45  ## and rises to this much in a gust
## Seconds per cycle of each part: a slow swell, the gusts, and flutter.
const PERIODS: Array[float] = [23.0, 8.3, 3.7, 1.9]
const WEIGHTS: Array[float] = [0.35, 0.35, 0.2, 0.1]


## The gust factor at `time` seconds; `phase` offsets each round or hole.
static func factor(time: float, phase := 0.0) -> float:
	var sum := 0.0
	for i in PERIODS.size():
		sum += WEIGHTS[i] * sin(TAU * time / PERIODS[i] + phase * (1.0 + 1.37 * i))
	# `sum` runs from -1 to 1 at most; map it onto LULL..PEAK.
	return lerpf(LULL, PEAK, 0.5 + 0.5 * sum)


## The wind the eye sees at `time`: the steady wind scaled by the gust,
## with its direction swinging a few degrees as gusts pass.
static func visual_wind(steady: Vector2, time: float, phase := 0.0) -> Vector2:
	if steady.length() < 0.01:
		return Vector2.ZERO
	var swing := deg_to_rad(8.0) * sin(TAU * time / 11.0 + phase * 2.1)
	return steady.rotated(swing) * factor(time, phase)
