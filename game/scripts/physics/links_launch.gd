class_name LinksLaunch
extends RefCounted
## How Links 2003 turns a swing into the ball's launch: a GDScript port of
## libs/olcore/src/links_launch.cpp; change both together. See
## docs/formats/physics.md.
##
## Works in the game's frame and units like LinksGround: x to the golfer's
## right, y downrange, z up, feet, seconds, spin in revolutions per second.
## The club table is read from the player's own executable.

const CLUB_COUNT := 19
## The putter's club number; it has no row in the club table.
const PUTTER := 19
## Ball ft/s per unit of putt power.
const PUTT_SPEED := 2.343600034713745
const ROW_BYTES := 4 * (CLUB_COUNT + 1)  ## each row has a spare zero
const TABLE_BYTES := 5 * ROW_BYTES
const FEET_PER_METRE := 1.0 / 0.3048

## Which of the game's clubs each of ours swings, by Club.short_name. The
## game has seven woods (driver first) then twelve irons and wedges.
const CLUB_INDEX := {
	"Dr": 0, "3W": 1, "5W": 3, "3H": 4, "4i": 10, "5i": 11, "6i": 12,
	"7i": 13, "8i": 14, "9i": 15, "PW": 16, "SW": 17, "LW": 18,
}

## Per club: spin per unit of clubhead speed, ball ft/s per percent of
## power, face loft in degrees, the share of speed along the face, and
## degrees of loft per 14 steps of ball position.
var spin := PackedFloat64Array()
var speed := PackedFloat64Array()
var loft_deg := PackedFloat64Array()
var glance := PackedFloat64Array()
var ball_position := PackedFloat64Array()


## The shot setup screen's settings, in the game's own steps. 30 is square
## for the face and the stance; -1 is the club's neutral ball position.
class Setup:
	var ball_position := -1
	var face := 30  ## above 30 opens the face (ball starts right)
	var stance := 30  ## above 30 opens the stance (path to the right)


class Strike:
	var club := 0
	var aim := 0.0  ## heading, radians, positive to the left of +y
	var power := 100.0  ## percent of a full swing
	var face_error := 0.0  ## radians; positive closes the face (ball left)
	var path_error := 0.0  ## radians; positive swings to the left
	var speed_scale := 1.0
	var spin_scale := 1.0
	var loft_scale := 1.0
	var setup := Setup.new()
	var ground_normal := Vector3(0, 0, 1)  ## under the ball; tilts the stance


## Finds the club table in the bytes of LINKSM_1.EXE or LinksMMIII.exe; null
## if it is not there. Mirrors olcore::find_links_clubs.
static func from_exe(exe: PackedByteArray) -> LinksLaunch:
	var off := 0
	while off + TABLE_BYTES <= exe.size():
		# Cheap test first: the driver's speed factor.
		var first := exe.decode_float(off + ROW_BYTES)
		if first < 1.0 or first > 5.0:
			off += 4
			continue
		var spares := true
		for r in 4:
			spares = spares and exe.decode_float(off + r * ROW_BYTES + 4 * CLUB_COUNT) == 0.0
		if spares:
			var t := LinksLaunch.new()
			var rows: Array[PackedFloat64Array] = []
			for r in 5:
				var row := PackedFloat64Array()
				for i in CLUB_COUNT:
					row.append(exe.decode_float(off + r * ROW_BYTES + 4 * i))
				rows.append(row)
			t.spin = rows[0]
			t.speed = rows[1]
			t.loft_deg = rows[2]
			t.glance = rows[3]
			t.ball_position = rows[4]
			if t._plausible():
				return t
		off += 4
	return null


## Reads the executable from the configured game folder, if there is one.
static func from_game_folder() -> LinksLaunch:
	var path := GameFolder.find_file(PackedStringArray(CrzCourseLoader.EXE_NAMES))
	if path.is_empty():
		return null
	return from_exe(FileAccess.get_file_as_bytes(path))


static func neutral_ball_position(club: int) -> int:
	return 2 if club == 0 else 4


## Velocity (ft/s) and spin (rev/s) of the ball as it leaves the club, as
## [velocity, spin]. Mirrors olcore::links_launch.
func launch(s: Strike) -> Array[Vector3]:
	var c := clampi(s.club, 0, CLUB_COUNT - 1)
	var bp := neutral_ball_position(c) if s.setup.ball_position < 0 else s.setup.ball_position
	# Moving the ball back in the stance takes loft off, forward adds it.
	var loft := deg_to_rad(s.loft_scale * loft_deg[c] + (neutral_ball_position(c) - bp) * ball_position[c] / 14.0)

	# The slope under the ball, along and across the aim line. A side slope
	# turns the face a tenth of its angle; an up or down slope tilts the swing.
	var n := _turn_z(s.ground_normal, -s.aim)
	var across := clampf(rad_to_deg(atan2(n.x, n.z)), -30.0, 30.0)
	var along := clampf(rad_to_deg(atan2(n.y, n.z)), -15.0, 15.0)

	var path := deg_to_rad(s.setup.stance - 30) - s.path_error
	var face := deg_to_rad(s.setup.face - 30 + s.setup.stance - 30) - s.face_error
	var f := Vector3(cos(loft) * sin(face), cos(loft) * cos(face), sin(loft))
	f = _turn_x(_turn_z(f, deg_to_rad(-0.1 * across)), deg_to_rad(-along))
	var p := _turn_x(Vector3(sin(path), cos(path), 0), deg_to_rad(-along))

	# The ball leaves along the face normal with a little of the path left
	# over along the face; spin comes from the glancing part of the blow.
	var square := f.dot(p)
	var g := p - f * square
	g = g.normalized() if g.length() > 0.0 else Vector3.ZERO
	var spd := s.speed_scale * speed[c] * s.power
	var vel := (f * square + g * (square * glance[c])) * spd
	var w := g.cross(f) * (spd * s.spin_scale * spin[c] * 0.25 * square)
	return [_turn_z(vel, s.aim), _turn_z(w, s.aim)]


## What the lie does to a strike; mirrors olcore::links_apply_lie. Every lie
## scales spin and ball speed by its lie values. Sand ignores the face error
## and sets both from `sand_contact`, the meter's miss in whole steps: 0 is
## the standard splash, positive is heavier, negative cleaner, and below -5
## thin, which also takes loft off.
static func apply_lie(s: Strike, lie: LinksGround.Params, sand_contact := 0) -> void:
	var k := Vector2.ONE
	if lie.ground_class == LinksGround.SAND:
		s.face_error = 0.0
		k = _sand(s, sand_contact)
	s.spin_scale = k.y * lie.lie_spin
	s.speed_scale = k.x * lie.lie_power


## The C runtime's rand(), which the game's swing code draws from. Mirrors
## olcore::LinksRand.
class Rand:
	var state := 1

	func _init(p_seed := 1) -> void:
		state = p_seed & 0xffffffff

	## 0..32767.
	func next() -> int:
		state = (state * 214013 + 2531011) & 0xffffffff
		return (state >> 16) & 0x7fff


enum Method { POWERSTROKE, MOUSE }

const SKILL_COUNT := 4

## One human swing, as it reaches the shot. Mirrors olcore::LinksSwing.
class SwingInput:
	var method := Method.POWERSTROKE
	var skill := 3  ## 0 (easiest) to 3
	var contact := 0  ## the meter's accuracy in whole steps (meter_contact)
	var full_power := 100.0  ## power above this is an overswing
	## The mouse swing's own face and path (degrees, positive closes the face
	## or swings left) and loft multiplier.
	var mouse_face_deg := 0.0
	var mouse_path_deg := 0.0
	var mouse_loft := 1.0
	var left_handed := false
	## A ball on the tee peg strikes cleanly whatever the meter says; a
	## PowerStroke swing only wobbles its power and aim a little.
	var teed_up := false


## Spin lost and ball speed lost per step of a miss from a lie, and how far
## the lie magnifies a miss (TerrainTypes LieAngularSnap, LiePowerSnap and
## Snap). Mirrors olcore::links_lie_snap.
static func lie_snap(ground_class: int) -> Vector3:
	match ground_class:
		LinksGround.ROUGH:
			return Vector3(0.1, 0.03, 1.5)
		LinksGround.SAND:
			return Vector3(0.2, 0.2, 2.0)
		LinksGround.PATH:
			return Vector3(0.1, 0.0, 4.0)
		LinksGround.DIRT, LinksGround.ROCKS:
			return Vector3(0.1, 0.0, 3.0)
		LinksGround.BUSHES:
			return Vector3(0.1, 0.0, 1.5)
		LinksGround.DEEP_GRASS:
			return Vector3(0.1, 0.05, 2.0)
	return Vector3(0.1, 0.0, 1.0)


## How much a lie scales a computer golfer's misses (TerrainTypes AngleMiss
## and PowerMiss, equal in every record). Mirrors olcore::links_lie_snap's
## `miss`.
static func lie_miss(ground_class: int) -> float:
	match ground_class:
		LinksGround.ROUGH, LinksGround.DIRT:
			return 1.5
		LinksGround.SAND:
			return 1.9
		LinksGround.PATH, LinksGround.ROCKS:
			return 2.0
		LinksGround.BUSHES:
			return 1.4
		LinksGround.DEEP_GRASS:
			return 1.7
	return 1.0


## The PowerStroke mouse swing's stroke; mirrors olcore::LinksMouseStroke.
## `release` is how far past the snap line the button came up (negative is
## early) and `drift` how far right the stroke moved from the top of the
## backswing to the line, over `height`, all in the game's meter units.
class MouseStroke:
	var power := 100.0
	var release := 0.0
	var drift := 0.0
	var height := 100.0
	var skill := 3


## What the stroke makes of the swing; mirrors olcore::LinksMouseSwing.
class MouseSwing:
	var power := 100.0
	var face_deg := 0.0
	var path_deg := 0.0
	var whiff := false


const MOUSE_STROKE_SCALE: Array[float] = [1.0, 1.3, 1.7, 2.0]


## Mirrors olcore::links_mouse_swing (see there).
static func mouse_swing(m: MouseStroke, rng: Rand) -> MouseSwing:
	var skill := clampi(m.skill, 0, SKILL_COUNT - 1)
	var out := MouseSwing.new()
	var path := rad_to_deg(atan2(-m.drift * MOUSE_STROKE_SCALE[skill], m.height)) if m.height > 0.0 else 0.0
	path = clampf(path, -20.0, 20.0)
	var x := m.release
	if skill == 0 and absf(x) >= 18.0:
		x = 17.0 if x > 0.0 else -17.0
	var face := 0.0
	if absf(x) > 10.0:
		if absf(x) >= 18.0:
			out.whiff = true
		else:
			face = absf(x) * 0.1 * x
	else:
		path += x
		face += x * (2.0 / 3.0)
	var power := m.power * absf(1.0 - absf(x / (80.0 if skill == 3 else 120.0)))
	if power < 1.0:
		power = 1.0
	if power > 145.0:
		power = _wobble(145.0, rng)
	out.face_deg = _wobble(face, rng)
	out.path_deg = _wobble(path, rng)
	out.power = 0.0 if out.whiff else power
	return out


## The game's random wobble: up to 5% either way, from three draws.
static func _wobble(x: float, rng: Rand) -> float:
	var j := (rng.next() % 100 + 1) * 1e-4 * 5.0
	var a := rng.next() % 100
	var b := rng.next() % 100
	return (1.0 + j) * x if a < b else x - j * x


## A computer golfer's steadiness with each kind of shot, 0 to 100 (more is
## steadier). Mirrors olcore::LinksGolferRatings.
class GolferRatings:
	var tee := 85  ## tee shots
	var woods := 85  ## clubs 0..6 off the ground
	var long_irons := 85  ## clubs 7..9
	var mid_irons := 85  ## clubs 10..12
	var short_irons := 85  ## clubs 13..15
	var wedges := 85  ## clubs 16..18
	var chips := 85
	var long_putts := 85  ## putts from 15 ft and more
	var short_putts := 85  ## putts up to 3 ft (blended in between)
	var max_power := 100  ## percent; a plan past it is forced and misses more
	var steady := false  ## halves the misses

	## The same rating for every kind of shot.
	static func even(rating: int) -> GolferRatings:
		var g := GolferRatings.new()
		g.tee = rating
		g.woods = rating
		g.long_irons = rating
		g.mid_irons = rating
		g.short_irons = rating
		g.wedges = rating
		g.chips = rating
		g.long_putts = rating
		g.short_putts = rating
		return g


## A computer golfer's planned swing, angles in degrees. Mirrors
## olcore::LinksComputerSwing.
class ComputerSwing:
	var power := 100.0
	var face_deg := 0.0
	var path_deg := 0.0


## The game's computer miss generator. Mirrors olcore::links_computer_miss
## (see there and docs/formats/physics.md).
@warning_ignore("integer_division")
static func computer_miss(w: ComputerSwing, g: GolferRatings, club: int, teed_up: bool, chip: bool,
		ground_class: int, feet_to_hole: float, rng: Rand) -> void:
	var forced := int(w.power) - g.max_power if w.power > g.max_power else 0
	var line := 0
	var length := 0
	if teed_up:
		line = _draw(100 - (g.tee - forced), 6, rng)
		length = _draw(100 - g.tee, 8, rng)
	elif chip:
		line = _draw(100 - g.chips, 8, rng)
		length = _draw(100 - g.chips, 8, rng)
	else:
		var r := 0
		if club >= 0 and club <= 6:
			r = g.woods
		elif club >= 7 and club <= 9:
			r = g.long_irons
		elif club >= 10 and club <= 12:
			r = g.mid_irons
		elif club >= 13 and club <= 15:
			r = g.short_irons
		elif club >= 16 and club <= 18:
			r = g.wedges
		line = _draw(100 - (r - 2 * forced), 8, rng)
		length = _draw(100 - r, 8, rng)
	var lie := lie_miss(ground_class)
	var power_miss := length * lie * 0.125
	var turn := minf(line * 0.5 * lie * 0.125, 5.0 if g.steady else 10.0)

	# The direction miss turns the face or the path, either way.
	if rng.next() % 100 < 50:
		w.face_deg += turn if rng.next() % 100 < 50 else -turn
	else:
		w.path_deg += turn if rng.next() % 100 < 50 else -turn
	if teed_up:
		# The game means a random sign here but always adds.
		power_miss += (rng.next() % 100) * 0.01
		rng.next()
		turn += (rng.next() % 100) * 0.01
		rng.next()
	if g.steady:
		turn *= 0.5
		power_miss *= 0.5

	var power := w.power
	if int(feet_to_hole) / 3 > 230 or rng.next() % 100 < 50:
		power -= power_miss
		power = _keep_positive(power, power_miss, 0.75)
	else:
		power += power_miss  # a positive plan stays positive
	if turn != 0.0:
		power -= turn * 0.5
		power = _keep_positive(power, turn, 0.4)
	w.power = power


## Half the sum of two draws below `n` plus n / `bias` (0 when n is 0).
@warning_ignore("integer_division")
static func _draw(n: int, bias: int, rng: Rand) -> int:
	if n == 0:
		return 0
	var a := rng.next() % n
	var b := rng.next() % n
	return (a + b + n / bias) / 2


## A miss that would take all the power is backed off, step by step.
static func _keep_positive(power: float, step: float, k: float) -> float:
	while power <= 0.0:
		step *= k
		power += step
	return power


## The PowerStroke meter's accuracy in whole steps for a snap `miss` meter
## units past the perfect zone (positive is late; clamped at 25). Mirrors
## olcore::links_meter_contact; `meter_width` is 150, 192 or 238.
static func meter_contact(miss: float, skill: int, meter_width := 192) -> int:
	var x := int(clampf(miss, -25.0, 25.0))
	var level := clampi(skill, 0, SKILL_COUNT - 1)
	var scale: float = [2.0, 1.5, 1.5, 1.4][level]
	var steps: int = [225, 180, 180, 165][level]
	var window := int(meter_width * scale)
	var t := int(float(x * steps) / window)
	@warning_ignore("integer_division")
	return int(0.2 * t) / 2


## What the swing and the lie do to a human player's strike, in place of
## apply_lie. Mirrors olcore::links_apply_swing; see docs/formats/physics.md.
static func apply_swing(s: Strike, w: SwingInput, lie: LinksGround.Params, rng: Rand) -> void:
	var ls := lie_snap(lie.ground_class)
	var sand := lie.ground_class == LinksGround.SAND
	var skill := clampi(w.skill, 0, SKILL_COUNT - 1)
	s.loft_scale = 1.0
	s.spin_scale = lie.lie_spin
	s.speed_scale = lie.lie_power

	if s.club == PUTTER:
		_putt_miss(s, w, skill, ls.z, rng)
		if sand:
			s.face_error = 0.0
		return

	if w.method == Method.POWERSTROKE:
		if skill > 0:
			# The miss, magnified by an overswing, the skill and the lie, then
			# scattered by up to a third either way.
			var miss := w.contact
			var over := (s.power - w.full_power) * 0.5
			if s.power > w.full_power and over > 1.0:
				miss = int(over * miss)
			miss *= 6 if skill == 3 else (5 if skill == 2 else 2)
			miss = int(miss * ls.z)
			if miss != 0:
				var sum := rng.next() % 101 + rng.next() % 101 + rng.next() % 101
				miss = int((sum * 0.001 + 0.35) * miss)
			miss = clampi(miss, -60, 60)
			# Aim and path turned apart: a late miss pushes and slices.
			var turn := ((rng.next() % 25) + 75.0) * 0.01 * miss
			turn *= 0.5 if skill == 3 else (1.0 / 1.9 if skill == 2 else 2.0 / 3.0)
			turn = deg_to_rad(turn)
			s.path_error -= turn
			if not sand:
				s.aim += turn
			if skill >= 2:
				var lost := 0.0
				if miss != 0:
					lost = rng.next() % absi(miss) + 1.0
					if not lost < s.power:
						lost = s.power - 1.0
				s.power -= lost
				var dp := (rng.next() % 100) * 0.0025
				var df := deg_to_rad((rng.next() % 100) * 0.001)
				s.power += -dp if rng.next() % 100 < 50 else dp
				s.face_error += -df if rng.next() % 100 < 50 else df
	else:
		s.face_error = deg_to_rad(w.mouse_face_deg)
		s.path_error = deg_to_rad(w.mouse_path_deg)
		s.loft_scale = w.mouse_loft
	if sand:
		s.face_error = 0.0
	if w.teed_up:
		if w.method == Method.POWERSTROKE:
			s.power += (rng.next() % 200 - 100) * 0.01
			s.aim += (rng.next() % 200 - 100) * 1e-5
		return

	# The strike: the further off the meter, the more spin and speed the lie
	# takes, and below a quality limit the ball comes off slower.
	var c := absi(w.contact)
	var quality: float
	match lie.ground_class:
		LinksGround.GREEN:
			quality = 1.0
		LinksGround.ROUGH:
			quality = 0.6 - 0.03 * c
		LinksGround.SAND:
			quality = 0.4 - 0.03 * c
		LinksGround.PATH, LinksGround.DIRT, LinksGround.BUSHES, LinksGround.ROCKS:
			quality = 0.95 - 0.06 * c
		_:
			quality = (rng.next() % 200 - 100) * 5e-5 + (SINGLE_0_9 - 0.01 * c)
	if lie.ground_class != LinksGround.GREEN:
		quality = maxf(quality, 0.3)
	# Only the driver, the 3-wood and the two longest irons feel it.
	match s.club:
		0:
			pass
		1:
			quality = 1.0 - (1.0 - quality) * 0.5
		7:
			quality = 1.0 - (1.0 - quality) * 0.2
		8:
			quality = 1.0 - (1.0 - quality) * 0.05
		_:
			quality = 1.0
	if skill == 0:
		quality = (quality + 1.0) * 0.5
	elif skill == 1:
		quality = quality * 0.8 + 0.2
	elif skill == 2:
		quality = quality * 0.9 + 0.1

	# The easier levels forgive the first steps of a miss.
	var steps := c
	var k := 1.0
	if skill == 0:
		steps = maxi(c - 2, 0)
		k = 0.6
	elif skill == 1:
		steps = maxi(c - 1, 0)
		k = 0.8
	var power_snap := 0.0 if (not sand and w.method == Method.MOUSE) else ls.y
	var speed := maxf(lie.lie_power - power_snap * steps * k, 0.25)
	s.spin_scale = maxf(lie.lie_spin - steps * ls.x * k, 0.25)
	s.speed_scale = minf(speed, quality)

	if sand:
		s.path_error = 0.0
		var contact := w.contact
		if w.method == Method.POWERSTROKE and w.left_handed:
			contact = -contact
		var f := _sand(s, contact)
		s.speed_scale = f.x * lie.lie_power
		s.spin_scale = f.y * lie.lie_spin


## 0.9 as the game stores it, in single precision.
const SINGLE_0_9 := 0.89999997615814209


## Sand: how much sand the club takes for a contact. Returns the speed (x)
## and spin (y) factors and sets the loft, which only a thin strike reduces.
static func _sand(s: Strike, c: int) -> Vector2:
	s.loft_scale = 1.0
	if c >= 0:
		return Vector2(0.3 + (15 - c) / 150.0, 0.25 + (15 - c) / 12.0)
	var clean := float(-c)
	if c >= -5:
		return Vector2(0.4 + 0.1 * clean, 1.5 - 0.1 * clean)
	s.loft_scale = 1.0 - 0.09 * (clean - 5.0)
	return Vector2(0.9 - 0.065 * (clean - 5.0), 1.5 - 0.1 * clean)


## A putt only turns the face: the miss as for a full swing without the
## overswing, flipped and added to the face error, with no power lost.
static func _putt_miss(s: Strike, w: SwingInput, skill: int, snap: float, rng: Rand) -> void:
	if w.method != Method.POWERSTROKE:
		s.face_error = deg_to_rad(w.mouse_face_deg)
		s.path_error = deg_to_rad(w.mouse_path_deg)
		return
	if skill <= 0:
		return
	var miss := w.contact * (6 if skill == 3 else (5 if skill == 2 else 2))
	miss = int(miss * snap)
	if miss != 0:
		var sum := rng.next() % 101 + rng.next() % 101 + rng.next() % 101
		miss = int((sum * 0.001 + 0.35) * miss)
	miss = -clampi(miss, -60, 60)
	var turn := ((rng.next() % 25) + 75.0) * 0.01 * miss
	turn *= 0.5 if skill == 3 else (1.0 / 1.9 if skill == 2 else 2.0 / 3.0)
	s.face_error += deg_to_rad(turn)
	# The game still draws the power it would lose, then keeps it all.
	if skill >= 2 and miss != 0:
		rng.next()


## A computer golfer's putt; mirrors olcore::links_computer_putt_miss (see
## there and docs/formats/physics.md). Works in double precision.
@warning_ignore("integer_division")
static func computer_putt_miss(w: ComputerSwing, g: GolferRatings, ground_class: int, feet_to_hole: float, rng: Rand) -> void:
	var d := feet_to_hole
	if not d > (3.5 if g.steady else 2.0):
		return
	var feet := int(d)
	var spread := maxi((100 - feet) / 3, 10) if d < 100.0 else 10
	var long_r := _s8(g.long_putts)
	var r := _s8(g.short_putts)
	if r != long_r and feet > 3:
		if feet >= 15:
			if g.steady:
				r = long_r
			elif long_r > 30:
				r = maxi(_s8(_s8(_s8(15 - feet) * 2) + long_r), long_r - 30)
			else:
				r = 10
		else:
			r = _s8(r - int((r - long_r) * 0.0833333358168602 * (feet - 3)))
	var line_k := 0.5 if d <= 6.0 else 1.0
	if r == 100:
		if line_k == 1.0:
			return
		r = 98
	var n := 100 - r
	var a := rng.next() % n
	a = (a + rng.next() % n) / 3
	var b := rng.next() % n
	b = (b + rng.next() % n) / 3
	var length := float(b)
	var line := a * line_k * 0.5
	if feet > 2 and feet < 7:
		line *= 0.4
		length *= 2.0 / 7.0
	elif feet <= 2:
		if r > 60:
			line = 0.0
			length = 0.0
		else:
			line /= 3.0
			length *= 0.25
	else:
		length *= 0.5
	if ground_class == LinksGround.ROUGH:
		line *= 2.0
		length *= 2.0
	elif ground_class == LinksGround.FAIRWAY:
		line *= 1.5
		length *= 1.5
	line /= 30.0
	length /= spread
	var path := deg_to_rad(w.path_deg)
	path += line if rng.next() % 100 < 50 else -line
	w.path_deg = rad_to_deg(path)
	var power := w.power
	if rng.next() % 100 >= 25:
		power += length
		while power <= 0.0:
			length *= 0.75
			power -= length
	else:
		power -= length
		while power <= 0.0:
			length *= 0.75
			power += length
	w.power = power


## A signed byte, as the game keeps the ratings.
static func _s8(x: int) -> int:
	return ((x + 128) & 255) - 128


## The putter's launch; mirrors olcore::links_putt. Velocity (ft/s) and spin
## (rev/s) on flat ground: putt_slope tilts them onto the slope.
static func putt(s: Strike) -> Array[Vector3]:
	var a := s.face_error + deg_to_rad(s.setup.face - 30 + s.setup.stance - 30)
	var b := s.path_error + deg_to_rad(s.setup.stance - 30)
	var spd := cos(a - b) * s.power * PUTT_SPEED
	var vel := Vector3(sin(a), cos(a), 0.0) * spd
	var w := Vector3(absf(spd) * 2.273642507507853, 0.0, 0.0)
	return [_turn_z(vel, s.aim), _turn_z(w, s.aim)]


## Tilts a putt's velocity or spin onto ground with unit normal n (game
## frame, z up); mirrors olcore::links_putt_slope.
static func putt_slope(v: Vector3, n: Vector3) -> Vector3:
	var a := atan2(n.y, n.z)
	var x := v.x
	var y := v.y * cos(a) - v.z * sin(a)
	var z := v.z * cos(a) + v.y * sin(a)
	var b := -atan2(n.x, n.z)
	return Vector3(z * sin(b) + x * cos(b), y, z * cos(b) - x * sin(b))


## The same launch in the game shell's SI frame, with the ball at the origin.
## The putter's starts on the ground.
func launch_state(s: Strike) -> BallState:
	var l := putt(s) if s.club == PUTTER else launch(s)
	var b := BallState.new(Vector3.ZERO)
	b.on_ground = s.club == PUTTER
	b.velocity = Vector3(-l[0].x, l[0].z, l[0].y) / FEET_PER_METRE
	b.spin = Vector3(-l[1].x, l[1].z, l[1].y) * TAU
	return b


func _plausible() -> bool:
	if not (_within(spin, 0.5, 20.0) and _within(speed, 1.0, 5.0) and _within(loft_deg, 5.0, 80.0)
			and _within(glance, 0.0, 1.0) and _within(ball_position, 1.0, 40.0)):
		return false
	for i in range(1, CLUB_COUNT):
		if i != 7 and not loft_deg[i] > loft_deg[i - 1]:
			return false
	return true


static func _within(v: PackedFloat64Array, lo: float, hi: float) -> bool:
	for x in v:
		if x < lo or x > hi:
			return false
	return true


## Rotation about z by a, taking +y towards -x.
static func _turn_z(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z)


## Rotation about x by a, taking +y towards +z.
static func _turn_x(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a))
