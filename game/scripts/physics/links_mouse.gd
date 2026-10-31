class_name LinksMouse
extends RefCounted
## Links 2003's PowerStroke mouse swing, a GDScript port of
## libs/olcore/src/links_mouse.cpp (change both together). See there and
## docs/formats/physics.md, "The mouse swing".
##
## Each frame (the game assumes 60 a second) the cursor's movement in whole
## pixels drives a club up and down the swing meter: pulling the mouse back
## (down the screen) takes it back, pushing it forward swings it down, and it
## strikes the ball when it comes back down to the ball line. MouseClub does the
## frames and swing() turns the stroke into the swing.

enum Shot { FULL, CHIP, PUTT }
enum Phase { BACKSWING, DOWNSWING, IMPACT, FAILED }

const PUTTER := 19
const SKILL_COUNT := 4
const FRAME_MS := 16.6668
const RAD_TO_DEG := 57.29578
## Power per unit of club speed, by club.
const GAIN: Array[float] = [10.5, 10.5, 10.5, 10.5, 10.0, 9.5, 9.0, 10.5, 9.75, 9.6,
		9.35, 9.15, 8.9, 8.9, 8.6, 8.6, 8.0, 8.5, 8.4, 0.75]
## The most power each club gives a mouse swing.
const MAX_POWER: Array[float] = [112, 108, 106, 104, 102, 100, 98, 98, 96, 94,
		92, 90, 88, 86, 84, 82, 80, 80, 80, 0]
const PATH_SCALE: Array[float] = [1.0, 1.3, 1.7, 2.0]
const PUTT_FACE: Array[float] = [0.5, 0.55, 0.6, 0.65]
const PUTT_WINDOW: Array[float] = [0.3, 0.33, 0.36, 0.4]
const DRIFT_POWER_LOSS: Array[float] = [120.0, 120.0, 80.0, 80.0]
const BONUS: Array[float] = [4500.0, 3000.0, 2250.0, 2250.0]


## The meter's size in pixels; mirrors olcore::LinksMouseMeter.
class Meter:
	var height := 442
	var ball_line := 119

	func _init(p_height := 442, p_ball_line := 119) -> void:
		height = p_height
		ball_line = p_ball_line


## The game's meter for a screen this many pixels wide.
static func meter_for(screen_width: int) -> Meter:
	if screen_width < 1024:
		return Meter.new(278, 75)
	if screen_width < 1280:
		return Meter.new(355, 96)
	return Meter.new(442, 119)


## The stroke at the moment the club meets the ball; mirrors
## olcore::LinksMouseStroke.
class Stroke:
	var skill := 3
	var shot := Shot.FULL
	var club := 0
	var speed := 0.0
	var drift := 0.0  ## positive to the left
	var drift_before := 0.0
	var down := 1
	var backswing := 1.0
	var straight := 0


## What the stroke makes of the swing; mirrors olcore::LinksMouseSwing.
class Outcome:
	var power := 0.0
	var face_deg := 0.0
	var path_deg := 0.0
	var loft := 1.0
	var whiff := false
	var quality := 0


class Sample:
	var dy := 0
	var smooth := 0
	var speed := 0
	var accel := 0
	var v := 0.0
	var pos := 0.0
	var drift := 0.0
	var frames := 0


static func club_response(club: int) -> float:
	if club >= PUTTER:
		return 0.75
	return 1.25 if club <= 7 else 1.15


## The game's wobble: up to 0.03% (mode 0) or 5% (mode 1) either way.
static func wobble(x: float, mode: int, rng: LinksLaunch.Rand) -> float:
	var j := (rng.next() % 100 + 1) * 1e-4 * (0.3 if mode == 0 else 5.0)
	var a := rng.next() % 100
	var b := rng.next() % 100
	return (j + 1.0) * x if a < b else x - j * x


## C's integer division by 3 (rounds towards zero).
@warning_ignore("integer_division")
static func _div3(a: int) -> int:
	return a / 3 if a >= 0 else -(-a / 3)


static func _round_away(x: float) -> int:
	return int(ceilf(x - 0.5)) if x < 0.0 else int(floorf(x + 0.5))


## The club on the meter, frame by frame; mirrors olcore::LinksMouseClub.
class MouseClub:
	var meter: Meter
	var phase := Phase.BACKSWING
	var stroke := Stroke.new()
	var _skill: int
	var _shot: int
	var _club: int
	var _k: float
	var _gain: float
	var _max_power: float
	var _drift_scale: float
	var _top: float
	var _slow: float
	var _back_scale: float
	var _down_scale: float
	var _dir := 0
	var _idle := 0
	var _moving := 0
	var _samples := 0
	var _frame := 1
	var _rounds := 1
	var _impacted := false
	var _hold := false
	var _over := false
	var _low_accel := true
	var _watch_peak := true
	var _watch_dip := false
	var _watch_rise := false
	var _rose := false
	var _surge := false
	var _turned := false
	var _hit := false
	var _reversed := 0
	var _peak := 0
	var _rise := 0
	var _dip := 0
	var _rise_frame := 0
	var _last_v := 0.0
	var _delta := 0.0
	var _pos := 0.0
	var _drift := 0.0
	var _backswing := 1.0
	var _top_set := false
	var _straight := 0
	var _s: Array[Sample] = [Sample.new(), Sample.new(), Sample.new(), Sample.new()]

	func _init(skill: int, shot: int, club: int, p_meter: Meter = null) -> void:
		_skill = clampi(skill, 0, SKILL_COUNT - 1)
		_shot = shot
		_club = clampi(club, 0, PUTTER)
		meter = p_meter if p_meter != null else Meter.new()
		_k = LinksMouse.club_response(_club) * (0.75 if _shot == Shot.CHIP else 1.0)
		_gain = GAIN[_club]
		_max_power = MAX_POWER[_club]
		if _skill == 0:
			_drift_scale = 0.02
		elif _shot == Shot.PUTT:
			_drift_scale = 0.04 if _skill == 1 else 0.06
		else:
			_drift_scale = 0.05 if _skill == 3 else 0.03
		_top = meter.height - 10
		_slow = _top - 65.0
		_back_scale = 1000.0 / (meter.height - meter.ball_line - 1)
		_down_scale = 640.0 / meter.height
		_pos = meter.ball_line

	func done() -> bool:
		return phase == Phase.IMPACT or phase == Phase.FAILED

	## The club's height on the meter, pixels up from its bottom.
	func club_height() -> float:
		return _pos

	func drift() -> float:
		return _drift

	## The meter's reading, 0..100 (a putt shows its own curve).
	func backswing_percent() -> float:
		var p := minf((_pos - meter.ball_line) * 100.0 / (_top - meter.ball_line), 100.0)
		if _shot == Shot.PUTT:
			p = (2.0 + p * 0.01) * p * 0.01 / 3.0 * 100.0
		return p

	## One frame: the cursor moved `dx` pixels right and `dy` down.
	@warning_ignore("integer_division")
	func step(dx: int, dy: int, rng: LinksLaunch.Rand) -> void:
		if done():
			return
		var reading := backswing_percent()
		var main := dy
		var side := float(-dx)
		_straight += absi(dx)
		if main < 0 and _dir == 0:
			return
		_idle += 1
		if main == 0 and dx == 0:
			if _idle <= 2:
				return
		if _dir == 0 and main != 0:
			_dir = 1 if main > 0 else -1
		if not _hold and ((_dir == -1 and main > 0) or (_dir != -1 and main < 0)):
			_reversed = 1
		if _reversed != 0:
			main = -main
		_s[3] = _s[2]
		_s[2] = _s[1]
		_s[1] = _s[0]
		_s[0] = Sample.new()
		_s[0].dy = main
		_s[0].smooth = main
		_s[0].speed = main
		if main != 0 and _idle > 1:
			_idle = 1
		_s[0].frames = _idle
		_idle = 0
		if _samples == 0:
			_samples = 1
			return
		_s[0].smooth = LinksMouse._div3(main + _s[1].smooth * 2)
		_s[0].accel = LinksMouse._div3(_s[1].accel * 2 - _s[1].dy + main)
		_samples += 1

		if _hold:
			_s[1].speed = 127
		var prev := _s[1].dy
		if prev > 127:
			_over = true
			_hold = false
			_s[1].speed = 127
		if _frame > 2 and not _over:
			var accel := _s[1].accel
			if accel <= 0:
				_low_accel = true
			if _watch_peak:
				if _peak > main:
					_watch_peak = false
					_watch_dip = true
					_dip = main
				else:
					_peak = main
			if _watch_dip:
				if _dip < main:
					_watch_dip = false
					_watch_rise = true
				else:
					_dip = main
			if _watch_rise:
				if _rise >= main:
					_watch_rise = false
					_rose = true
				else:
					_rise_frame = _frame + 1
					_rise = main
			if _hold and ((_rose and _rise_frame == _frame) or (prev + accel > 125 and _low_accel) \
					or (prev > 110 and accel < 3)):
				_s[1].speed = LinksMouse._div3(prev + _s[2].speed * 2)
				_s[0].speed = LinksMouse._div3(main + _s[1].speed * 2)
				_hold = false
			if not _hold and _rounds != 0 and (prev > 127 or prev + accel > 110) and phase != Phase.BACKSWING:
				_hold = true
				_low_accel = false
				_rounds = 0
				_s[1].speed = 127
		if _reversed == 1:
			_dir = -_dir
			_reversed = 2
			if phase == Phase.BACKSWING:
				_rounds = 1
			else:
				_watch_peak = true
				_watch_rise = false
				_rose = false
				_watch_dip = false
				_rise_frame = 0
				_rounds += 1
		if not _surge:
			if phase != Phase.BACKSWING and _s[2].speed - _s[1].speed > 50:
				_surge = true
				_s[1].speed = 90
		elif prev == 0 and main == 0:
			_surge = false
		else:
			var n := _s[2].speed
			if n > 0:
				_s[1].speed = (6 * n - 1) / 5
			elif n < 0:
				_s[1].speed = -((-6 * n - 1) / 5)
			else:
				_s[1].speed = 0

		if _shot == Shot.FULL:
			var a := _s[1].speed * _k
			if _reversed != 0:
				a = -a
			a -= 10.0 * _s[2].v
			if a == 0.0:
				a = 1.0
			var w := LinksMouse.wobble(a, 0, rng)
			var dt := _s[1].frames * FRAME_MS * 0.001
			_s[1].v = dt * w + _s[2].v
			_s[1].pos = _s[2].v * dt + dt * dt * w * 0.5 + _s[2].pos
			_delta = (_s[1].pos - _s[2].pos) * 800.0
		else:
			var a := _s[1].speed * _k
			if _reversed != 0:
				a = -a
			_s[1].v = LinksMouse.wobble(a / (_s[1].frames * FRAME_MS), 1, rng)
			_s[1].pos = a
			_delta = a
		if _s[1].v > 0.2 and _moving == 0:
			_moving = _frame
		var started := _moving != 0 and _moving != _frame
		if _reversed == 0 and _s[1].v < 0.0 and started:
			_s[1].v = 0.0
			_s[1].pos = _s[2].pos
		if _s[1].v * _last_v < 0.0 and started:
			_reversed = 3
			if phase == Phase.BACKSWING:
				_turned = true
				_rounds = 1
			elif phase == Phase.DOWNSWING:
				_turned = false
				_top_set = false
				phase = Phase.BACKSWING
			else:
				phase = Phase.FAILED
		if _s[1].v != 0.0:
			_last_v = _s[1].v
		if _moving != 0:
			_move_club(_delta / (_back_scale if phase == Phase.BACKSWING else _down_scale), side)
		if not _top_set and phase != Phase.BACKSWING:
			_top_set = true
			if phase == Phase.DOWNSWING:
				_backswing = reading * 0.01
		_s[1].drift = _drift
		if phase == Phase.IMPACT and not _impacted:
			_impacted = true
			_impact(rng)
		_frame += 1

	func _move_club(delta: float, side: float) -> void:
		if _shot != Shot.PUTT and _slow < _pos and delta > 0.0:
			delta = (1.0 - (_pos - _slow) / 65.0) * delta * (0.3 if _shot == Shot.CHIP else 0.25)
		if phase == Phase.DOWNSWING and _top < _pos + delta:
			_pos = _top
		_pos += delta
		_drift = clampf(_drift_scale * side + _drift, -50.0, 50.0)
		if phase == Phase.BACKSWING and _turned:
			phase = Phase.DOWNSWING
		if phase == Phase.IMPACT and _pos <= -120.0:
			phase = Phase.FAILED
			return
		if phase == Phase.DOWNSWING and _pos <= meter.ball_line and not _hit:
			phase = Phase.IMPACT
			_hit = true

	func _impact(rng: LinksLaunch.Rand) -> void:
		var speed: float
		if _shot == Shot.FULL:
			speed = (_s[2].v + _s[1].v) * 0.5
			var share := absf(speed * _gain) / _max_power
			if share > 1.2:
				speed = LinksMouse.wobble(_max_power / _gain, 1, rng) * 1.2
			if _surge and share > 0.9:
				speed = LinksMouse.wobble(_max_power / _gain, 1, rng) * 0.9
		else:
			speed = (_s[3].v + _s[2].v + _s[1].v) / 3.0
		stroke.skill = _skill
		stroke.shot = _shot
		stroke.club = _club
		stroke.speed = speed
		stroke.drift = _s[1].drift
		stroke.drift_before = _s[3].drift
		stroke.down = _s[1].speed
		stroke.backswing = _backswing
		stroke.straight = _straight


## Mirrors olcore::links_mouse_swing (see there).
@warning_ignore("integer_division")
static func swing(m: Stroke, rng: LinksLaunch.Rand) -> Outcome:
	var skill := clampi(m.skill, 0, SKILL_COUNT - 1)
	var club := clampi(m.club, 0, PUTTER)
	var k := club_response(club) * (0.75 if m.shot == Shot.CHIP else 1.0)
	var gain: float = GAIN[club]
	var f := m.backswing
	var cap := k * 0.8 * 10.5
	var speed := minf(absf(m.speed), cap)
	var out := Outcome.new()
	var x := -m.drift
	if skill == 0:
		if not (x > -18.0):
			x = -17.0
		elif x >= 18.0:
			x = 17.0
	var t := (m.drift - m.drift_before) * PATH_SCALE[skill]
	var path := atan2(t, float(m.down)) * RAD_TO_DEG if t != 0.0 else 0.0
	if path > 180.0:
		path -= 360.0
	path = clampf(path, -20.0, 20.0)
	var stroke_angle := path
	var face := 0.0
	var power: float
	var loft: float
	if m.shot == Shot.PUTT:
		var mid := f * 2.5 + 1.0
		var w := 0.5 - PUTT_WINDOW[skill] * f
		var e := w / 15.0
		var g: float
		if speed > mid + w:
			g = 1.0 + e
		elif mid - w <= speed:
			g = (speed - (mid - w)) / 6.0 + (1.0 - e)
		else:
			g = (1.0 - e) / (mid - w) * speed
		loft = g * f
		power = wobble((f + 2.0) * f / 3.0 * 14.6 * g, 1, rng)
		if absf(x) > 18.0:
			out.whiff = true
		else:
			face = PUTT_FACE[skill] * path
		power *= absf(1.0 - absf(x / DRIFT_POWER_LOSS[skill]))
	elif m.shot == Shot.CHIP:
		var want := (cap - 1.0) * f + 0.1
		var g := speed / (want - 0.2) if not (want + 0.2 < speed) and speed < want - 0.2 else 1.0
		loft = g * f
		power = wobble((f + 1.0) * f * 0.5 * 14.6 * g * 3.0, 1, rng)
	else:
		var fp := minf(f + 0.05, 1.0)
		var g := 2.0 * fp - fp * fp
		power = wobble(speed * gain * g, 0, rng)
		loft = power / (g * gain * cap) * (f + 0.05)
		var ax := absf(x)
		if ax > 10.0:
			if ax > 18.0:
				out.whiff = true
			else:
				face = ax * 0.1 * x
		else:
			path += x
			face += x * (2.0 / 3.0)
		power *= absf(1.0 - absf(x / DRIFT_POWER_LOSS[skill]))
	loft = minf(loft, 1.0)
	power = maxf(power, 1.0)
	if power > 145.0:
		power = wobble(145.0, 1, rng)
	face = wobble(face, 1, rng)
	path = wobble(path, 1, rng)
	if out.whiff:
		wobble(gain * speed, 1, rng)
		power = 0.0
	if absf(x) < 1.0:
		x = 0.0
	var q := clampf(x * -4.0, -50.0, 50.0)
	var b := clampi(_round_away(stroke_angle * -2.0) + 10, 0, 20)
	out.quality = mini(int(absf(q * 0.2) + float(absi(b - 10) / 2)), 15)
	var bonus := (15.0 - out.quality) * (15.0 - out.quality) / BONUS[skill] + 1.0
	loft *= bonus / (225.0 / BONUS[skill] + 1.0)
	path *= 0.66667
	if m.shot == Shot.PUTT:
		face = -face
	if m.shot == Shot.FULL and skill < 2:
		face *= 0.4
		path *= 0.4
	out.power = power * bonus
	out.face_deg = face
	out.path_deg = path
	out.loft = loft
	return out
