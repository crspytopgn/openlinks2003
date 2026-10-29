class_name ShotResult
extends RefCounted
## A simulated shot: where it went and a time-stamped path for playback.
## Mirrors olcore::ShotResult.

enum Outcome { REST, HOLED, WATER, OUT_OF_BOUNDS, TIMED_OUT }

var outcome: Outcome = Outcome.REST
var rest := Vector3.ZERO  ## final position (the cup centre when holed)
var first_landing := Vector3.ZERO
var rest_surface: int = Surface.Type.FAIRWAY
var carry_m := 0.0
var total_m := 0.0
var apex_m := 0.0
var time_s := 0.0
var bounces := 0
var times := PackedFloat32Array()
var points := PackedVector3Array()


func add_sample(t: float, p: Vector3) -> void:
	times.append(t)
	points.append(p)


## Ball position at time t, interpolated between samples.
func position_at(t: float) -> Vector3:
	var n := times.size()
	if n == 0:
		return rest
	if t <= times[0]:
		return points[0]
	if t >= times[n - 1]:
		return points[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if times[mid] <= t:
			lo = mid
		else:
			hi = mid
	var span := times[hi] - times[lo]
	var f := 0.0 if span <= 0.0 else (t - times[lo]) / span
	return points[lo].lerp(points[hi], f)


## Index of the last sample at or before t, for drawing the trail so far.
func sample_index_at(t: float) -> int:
	var i := times.bsearch(t, false) - 1
	return clampi(i, 0, maxi(0, times.size() - 1))
