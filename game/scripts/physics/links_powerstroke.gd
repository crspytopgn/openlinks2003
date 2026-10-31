class_name LinksPowerStroke
extends RefCounted
## Links 2003's three-click PowerStroke meter: its positions, its speed and
## what each position is worth (docs/formats/physics.md, "The PowerStroke
## meter"). SwingMeter draws it; this does the timing.
##
## The meter has 69 positions. A full swing starts at the snap line
## (position 15) and climbs; position 54 is full power and up to 67 is
## overswing. Chips and putts start at the bottom (0) and run to 68. The
## marker moves one position at a time, each step waiting a number of the
## game's 8 ms frames that depends on the shot and the position: slow at the
## start of the backswing and quicker towards the top, with an ease in and
## out on a 40-position cycle.

enum Mode { FULL, CHIP, PUTT, SHORT_PUTT }

const SNAP := 15  ## the snap line (perfect contact)
const FULL_POWER := 54  ## a full swing's 100 percent
const TOP := 67  ## the top of the backswing
const LAST := 68  ## a chip's or putt's highest position
const FRAME_S := 0.008  ## the game's frame while the meter runs
## The earliest a power click takes; an earlier click waits for it.
const MIN_POWER: Array[int] = [25, 16, 16, 16]
## An early snap waits until the marker comes down to here.
const EARLY_SNAP := 30
## The ease of the steps: the weight 70 at the middle of a run down to 42,
## repeating every 40 positions (the step's wait is inversely proportional).
const EASE: Array[float] = [70.0, 69.9, 69.6, 69.2, 68.6, 67.9, 66.9, 65.8, 64.6, 63.3, 61.8,
		60.2, 58.5, 56.7, 54.7, 52.8, 50.6, 48.6, 46.3, 44.2, 42.0]


## Frames a step up to `pos` takes before easing, by mode: [from, frames] runs.
static func climb_frames(mode: int, pos: int) -> int:
	var runs: Array = [
		[[63, 1], [47, 2], [28, 3], [22, 4], [17, 5], [13, 6], [0, 0]],
		[[45, 2], [29, 3], [20, 4], [0, 5]],
		[[48, 2], [38, 3], [28, 4], [0, 5]],
		[[48, 2], [38, 3], [28, 4], [0, 5]],
	]
	for r: Array in runs[mode]:
		if pos >= int(r[0]):
			return int(r[1])
	return 0


## Frames a step down takes before easing.
static func fall_frames(mode: int) -> int:
	return 1 if mode == Mode.FULL else 2


static func _ease(pos: int, centre: int) -> float:
	var d := posmod(pos - centre, 40)
	return EASE[d if d <= 20 else 40 - d]


static func ease_up(pos: int) -> float:
	return _ease(pos, SNAP)


static func ease_down(pos: int) -> float:
	return _ease(pos, SNAP + 1)


## A full swing's power for a power click at `pos`, as a share of the
## club's full power: (pos - 15) / 39 to position 54, then 8 percent of a
## full swing over the 13 positions of overswing (counting full as 100).
static func full_power(pos: int) -> float:
	if pos <= FULL_POWER:
		return float(pos - SNAP) / float(FULL_POWER - SNAP)
	return 1.0 + (pos - FULL_POWER) * 8.0 / 13.0 / 100.0


## A chip's power for a power click at `pos`, in the game's power units:
## 7 at the snap line, rising 0.4 a position, then 0.45, 0.5, 0.55, 0.6 and
## 0.65 a position every nine positions, to about 35 at the top.
static func chip_power(pos: int) -> float:
	var v := 7.0
	for q in range(SNAP + 1, mini(pos, LAST) + 1):
		if q <= 23:
			v += 0.4
		elif q <= 32:
			v += 0.45
		elif q <= 41:
			v += 0.5
		elif q <= 50:
			v += 0.55
		elif q <= 59:
			v += 0.6
		else:
			v += 0.65
	return v


## One swing on the meter.
class Run:
	var mode := Mode.FULL
	var pos := SNAP
	var rising := true
	var power_pos := 0  ## where power was set, 0 until then
	var snap_pos := -1  ## where the snap landed, -1 until then
	var done := false
	var _stop := 0  ## a chip's or putt's turn, six past the power click
	var _wait_power := false
	var _wait_snap := false
	var _frames := 0.0
	var _need := 1
	var _carry := 0.0

	func _init(p_mode := Mode.FULL) -> void:
		mode = p_mode
		pos = SNAP if mode == Mode.FULL else 0
		_need = maxi(LinksPowerStroke.climb_frames(mode, pos), 1)

	## How far up the meter: 0 at the snap line, 1 at full power (a chip's
	## or putt's top), negative below the snap line.
	func value() -> float:
		var full := FULL_POWER if mode == Mode.FULL else LAST
		return float(pos - SNAP) / float(full - SNAP)

	func value_of(p: int) -> float:
		var full := FULL_POWER if mode == Mode.FULL else LAST
		return float(p - SNAP) / float(full - SNAP)

	## Runs the meter for `seconds`.
	func advance(seconds: float) -> void:
		if done:
			return
		_frames += seconds / FRAME_S
		while not done and _frames >= _need:
			_frames -= _need
			_step()

	## The second click.
	func click_power() -> void:
		if done or power_pos != 0:
			return
		if rising:
			if pos < MIN_POWER[mode]:
				_wait_power = true
			else:
				_set_power(pos)
		elif mode == Mode.FULL and pos > FULL_POWER:
			_set_power(pos)  # overswing, set on the way down

	## The third click.
	func click_snap() -> void:
		if done or power_pos == 0 or rising or _wait_snap:
			return
		if pos >= power_pos:
			snap_pos = power_pos - 6 if mode == Mode.FULL else power_pos
			done = true
		elif pos > EARLY_SNAP:
			_wait_snap = true
		else:
			snap_pos = pos
			done = true

	## The snap's accuracy: 0 on the snap line, up to -1 early (above it,
	## a pull or hook) and +1 late (below it, a push or slice).
	func accuracy() -> float:
		return clampf(float(SNAP - snap_pos) / float(SNAP), -1.0, 1.0)

	func _set_power(p: int) -> void:
		power_pos = p
		_wait_power = false
		if mode != Mode.FULL:
			_stop = mini(p + 6, LAST)

	func _step() -> void:
		var before := pos
		if rising:
			pos += 1
			if _wait_power and pos >= MIN_POWER[mode]:
				_set_power(pos)
			if (mode != Mode.FULL and power_pos != 0 and pos >= _stop) or pos > TOP:
				rising = false
				if pos > TOP:
					pos = TOP
		else:
			pos -= 1
			if mode == Mode.FULL and power_pos == 0 and pos < 49:
				# No power by now: the game takes a weak swing for you.
				power_pos = pos - 12
				snap_pos = power_pos - 3
				done = true
				return
			if _wait_snap and pos <= EARLY_SNAP:
				snap_pos = pos
				done = true
				return
			if pos <= 0:
				pos = 0
				if power_pos == 0:
					power_pos = SNAP + 1
				snap_pos = 0
				done = true
				return
		# The next step's wait, in whole frames; the fraction carries over.
		var frames: int
		var held := mode != Mode.FULL and power_pos != 0
		var ease: float
		if rising:
			frames = LinksPowerStroke.climb_frames(mode, power_pos if held else pos)
			ease = LinksPowerStroke.ease_up(pos)
		else:
			frames = LinksPowerStroke.climb_frames(mode, power_pos) if held else LinksPowerStroke.fall_frames(mode)
			ease = LinksPowerStroke.ease_down(pos)
		var wait := frames * 70.0 / (1.2 * ease) + _carry
		if not rising and (mode == Mode.PUTT or mode == Mode.SHORT_PUTT) and absi(power_pos - before) < 5:
			wait *= 1.5
		_need = int(wait)
		_carry = wait - _need
		_need = maxi(_need, 1)
