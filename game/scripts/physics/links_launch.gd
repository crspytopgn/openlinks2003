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
	var spin_k := 1.0
	var speed_k := 1.0
	if lie.ground_class == LinksGround.SAND:
		s.face_error = 0.0
		var c := sand_contact
		if c >= 0:
			speed_k = 0.3 + (15 - c) / 150.0
			spin_k = 0.25 + (15 - c) / 12.0
		else:
			var clean := float(-c)
			spin_k = 1.5 - 0.1 * clean
			if c >= -5:
				speed_k = 0.4 + 0.1 * clean
			else:
				speed_k = 0.9 - 0.065 * (clean - 5.0)
				s.loft_scale = 1.0 - 0.09 * (clean - 5.0)
	s.spin_scale = spin_k * lie.lie_spin
	s.speed_scale = speed_k * lie.lie_power


## The same launch in the game shell's SI frame, with the ball at the origin.
func launch_state(s: Strike) -> BallState:
	var l := launch(s)
	var b := BallState.new(Vector3.ZERO)
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
