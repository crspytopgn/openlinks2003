class_name LaunchMonitor
extends RefCounted
## The numbers a launch monitor shows for a shot (ball speed, launch, spin,
## carry, total, offline, apex, descent), and a practice session's averages
## per club. Reads the launch the shot model made (ShotResult.launch) and the
## flight it simulated; nothing here changes the physics.

const MPH_PER_MPS := 2.2369363
const YARDS_PER_METRE := 1.0936133
const FEET_PER_METRE := 3.2808399
const RPM_PER_RAD_S := 60.0 / TAU


class Reading:
	var club := ""
	var ball_mph := 0.0
	var launch_deg := 0.0
	var back_rpm := 0.0
	## Positive spins the ball left (a draw or hook), negative right.
	var side_rpm := 0.0
	var carry_yd := 0.0
	var total_yd := 0.0
	## Where it finished across the aim line: positive left, negative right.
	var offline_yd := 0.0
	var apex_ft := 0.0
	var descent_deg := 0.0


## `aim_deg` is the shot's heading (positive left of +z), `from` where it
## was played from.
static func read(club_name: String, shot: ShotResult, from: Vector3, aim_deg: float) -> Reading:
	var r := Reading.new()
	r.club = club_name
	r.carry_yd = shot.carry_m * YARDS_PER_METRE
	r.total_yd = shot.total_m * YARDS_PER_METRE
	r.apex_ft = shot.apex_m * FEET_PER_METRE
	var a := deg_to_rad(aim_deg)
	var left := Vector3(cos(a), 0.0, -sin(a))
	r.offline_yd = (shot.rest - from).dot(left) * YARDS_PER_METRE
	var start := shot.launch
	if start != null:
		var v := start.velocity
		var flat := Vector2(v.x, v.z).length()
		r.ball_mph = v.length() * MPH_PER_MPS
		r.launch_deg = rad_to_deg(atan2(v.y, flat))
		var right := Vector3(v.x, 0.0, v.z).normalized().cross(Vector3.UP) if flat > 1e-6 else Vector3.LEFT
		r.back_rpm = start.spin.dot(right) * RPM_PER_RAD_S
		r.side_rpm = start.spin.dot(Vector3.UP) * RPM_PER_RAD_S
	if shot.bounces > 0 and shot.times.size() > 1:
		var t := _time_at(shot, shot.first_landing)
		var d := shot.position_at(t) - shot.position_at(maxf(0.0, t - 0.05))
		var horiz := Vector2(d.x, d.z).length()
		if horiz > 1e-6 or d.y < 0.0:
			r.descent_deg = rad_to_deg(atan2(-d.y, horiz))
	return r


static func _time_at(shot: ShotResult, p: Vector3) -> float:
	var best := 0.0
	var best_d := INF
	for i in shot.points.size():
		var dist := shot.points[i].distance_squared_to(p)
		if dist < best_d:
			best_d = dist
			best = shot.times[i]
	return best


## "L 12" / "R 4" / "0" for a sideways number.
static func side_text(v: float, unit := "") -> String:
	var n := roundi(absf(v))
	if n == 0:
		return "0" + unit
	return "%s %d%s" % ["L" if v > 0.0 else "R", n, unit]


## The shot's numbers as label and value pairs, in display order.
static func rows(r: Reading) -> Array:
	return [
		["Ball speed", "%d mph" % roundi(r.ball_mph)],
		["Launch", "%.1f°" % r.launch_deg],
		["Back spin", "%d rpm" % roundi(r.back_rpm)],
		["Side spin", side_text(r.side_rpm, " rpm")],
		["Carry", "%d yd" % roundi(r.carry_yd)],
		["Total", "%d yd" % roundi(r.total_yd)],
		["Offline", side_text(r.offline_yd, " yd")],
		["Apex", "%d ft" % roundi(r.apex_ft)],
		["Descent", "%d°" % roundi(r.descent_deg)],
	]


## A practice session: every reading, grouped by club.
class Session:
	var readings: Array[Reading] = []

	func add(r: Reading) -> void:
		readings.append(r)

	func of_club(club: String) -> Array[Reading]:
		var out: Array[Reading] = []
		for r in readings:
			if r.club == club:
				out.append(r)
		return out

	## "7 shots: carry 152 yd, total 160 yd, offline spread 9 yd" for `club`;
	## empty with no shots.
	func summary(club: String) -> String:
		var shots := of_club(club)
		if shots.is_empty():
			return ""
		var carry := 0.0
		var total := 0.0
		var off := 0.0
		for r in shots:
			carry += r.carry_yd
			total += r.total_yd
			off += r.offline_yd
		var n := float(shots.size())
		var mean_off := off / n
		var spread := 0.0
		for r in shots:
			spread += (r.offline_yd - mean_off) * (r.offline_yd - mean_off)
		spread = sqrt(spread / n)
		return "%d shot%s: carry %d yd, total %d yd, spread %d yd" % [
			shots.size(), "" if shots.size() == 1 else "s", roundi(carry / n), roundi(total / n), roundi(spread)]
