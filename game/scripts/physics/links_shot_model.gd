class_name LinksShotModel
extends StandardShotModel
## The launch (LinksLaunch), ball flight (LinksAero), bounce and roll
## (LinksGround) of Links 2003, used when the player's game folder has the
## executable, with its PowerStroke miss model (LinksLaunch.apply_swing). See
## docs/formats/physics.md for what is left.

## How far past the perfect zone, in the game's meter units, our meter's
## accuracy of +/-1 lands: the game clamps a snap at 25 units.
const METER_UNITS_AT_FULL_MISS := 25.0
## Face angle at accuracy +/-1 for a computer golfer's swing.
const COMPUTER_FACE_ERROR_DEG := 4.0
## The same for a putt (the game turns a putter's face the other way).
const COMPUTER_PUTT_FACE_ERROR_DEG := 2.0
## Putt power at a full meter. The game's putt meter has its own scales
## (not decoded); ours is linear in ball speed, and a full putt (58.6 ft/s)
## skids and rolls about 110 ft on a flat, medium, normal-speed green.
const PUTT_POWER_AT_FULL := 25.0
## A full swing's power at the meter's top (position 67): 8 points past full.
const OVERSWING_MAX := 1.08

var aero: LinksAero
var clubs: LinksLaunch
## The swing skill level of the person playing, 0 (easiest) to 3.
var skill := 3
## Set while a computer golfer swings or plans. The game sends computer
## swings past the human miss model: only the lie applies, and the accuracy
## turns the face (how ComputerGolfer tries out likely misses).
var computer := false
## Set for a computer golfer's real swing or putt: Links 2003's own computer
## miss generators (LinksLaunch.computer_miss and computer_putt_miss) with
## these ratings replace the accuracy.
var computer_ratings: LinksLaunch.GolferRatings = null
## A person's PowerStroke mouse swing for this shot (LinksMouse.swing), or
## null for the meter: its power, face and path replace the meter's.
var mouse_swing: LinksMouse.Outcome = null
## The shot is a Chip: its power is already in the game's units (the chip
## meter's table, or the mouse chip's), a PowerStroke miss keeps it, and a
## computer golfer misses by its chip rating.
var chip := false
## From the ball to the hole, metres, for computer_ratings.
var to_hole_m := 0.0
var rng := LinksLaunch.Rand.new(randi())


func _init(p_aero: LinksAero, p_clubs: LinksLaunch = null) -> void:
	aero = p_aero
	clubs = p_clubs


## Null when no game folder is set up or its executable lacks the tables.
static func from_game_folder() -> LinksShotModel:
	var found := LinksAero.from_game_folder()
	return LinksShotModel.new(found, LinksLaunch.from_game_folder()) if found != null else null


func launch(club: Club, power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	if clubs == null:
		return super.launch(club, power, accuracy, aim_deg, lie, from)
	if club.is_putter:
		return _putt(power, accuracy, aim_deg, lie, from)
	if not LinksLaunch.CLUB_INDEX.has(club.short_name):
		return super.launch(club, power, accuracy, aim_deg, lie, from)
	var s := LinksLaunch.Strike.new()
	s.club = LinksLaunch.CLUB_INDEX[club.short_name]
	s.aim = deg_to_rad(aim_deg)
	# A full swing's power is a share of the club's own rating (112 for the
	# driver down to 80 for the wedges), and an overswing (power past 1, from
	# LinksPowerStroke.full_power) adds the same points for every club. A
	# chip's power is already in the game's units.
	var rating := 100.0 if chip else club_rating(club)
	var share := clampf(power, 0.0, OVERSWING_MAX)
	s.power = rating * minf(share, 1.0) + 100.0 * maxf(share - 1.0, 0.0)
	s.setup.ball_position = setup.ball_position
	s.setup.face = setup.face
	s.setup.stance = setup.stance
	var lie_params := LinksGround.surface_for_class(LinksGround.ground_class_for(lie))
	if computer:
		if computer_ratings != null:
			var cw := LinksLaunch.ComputerSwing.new()
			# The plan goes in as a percentage of the club, so its forced-power
			# penalty (past max_power) is the same for every club.
			cw.power = 100.0 * share if not chip else s.power
			LinksLaunch.computer_miss(cw, computer_ratings, s.club, lie == Surface.Type.TEE, chip,
					lie_params.ground_class, to_hole_m * LinksLaunch.FEET_PER_METRE, rng)
			s.power = cw.power if chip else cw.power * rating / 100.0
			s.face_error = deg_to_rad(cw.face_deg)
			s.path_error = deg_to_rad(cw.path_deg)
		else:
			s.face_error = -deg_to_rad(COMPUTER_FACE_ERROR_DEG) * clampf(accuracy, -1.0, 1.0)
		LinksLaunch.apply_lie(s, lie_params)
		var cb := clubs.launch_state(s)
		cb.position = from
		return cb
	# Late (positive accuracy) is a push-slice, which is a negative contact.
	var w := LinksLaunch.SwingInput.new()
	w.skill = skill
	w.teed_up = lie == Surface.Type.TEE
	w.chip = chip
	if mouse_swing != null:
		w.method = LinksLaunch.Method.MOUSE
		w.mouse_face_deg = mouse_swing.face_deg
		w.mouse_path_deg = mouse_swing.path_deg
		s.power = mouse_swing.power
	else:
		w.contact = LinksLaunch.meter_contact(-METER_UNITS_AT_FULL_MISS * clampf(accuracy, -1.0, 1.0), skill)
	w.full_power = rating
	LinksLaunch.apply_swing(s, w, lie_params, rng)
	var b := clubs.launch_state(s)
	b.position = from
	return b


## Links 2003's putt: the putter's own launch, rolling from the start, with
## the PowerStroke putt miss (only the face turns).
func _putt(power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	var s := LinksLaunch.Strike.new()
	s.club = LinksLaunch.PUTTER
	s.aim = deg_to_rad(aim_deg)
	s.power = PUTT_POWER_AT_FULL * clampf(power, 0.0, 1.0)
	var acc := clampf(accuracy, -1.0, 1.0)
	if computer and computer_ratings != null:
		var cw := LinksLaunch.ComputerSwing.new()
		cw.power = s.power
		LinksLaunch.computer_putt_miss(cw, computer_ratings, LinksGround.ground_class_for(lie),
				to_hole_m * LinksLaunch.FEET_PER_METRE, rng)
		s.power = cw.power
		s.path_error = deg_to_rad(cw.path_deg)
	elif computer:
		s.face_error = deg_to_rad(COMPUTER_PUTT_FACE_ERROR_DEG) * acc
	else:
		var w := LinksLaunch.SwingInput.new()
		w.skill = skill
		if mouse_swing != null:
			# The mouse putt's power is the putter's own (about 15 at most);
			# LinksMouse.swing has already turned the face for a putter.
			w.method = LinksLaunch.Method.MOUSE
			w.mouse_face_deg = mouse_swing.face_deg
			w.mouse_path_deg = mouse_swing.path_deg
			s.power = mouse_swing.power
		else:
			w.contact = LinksLaunch.meter_contact(-METER_UNITS_AT_FULL_MISS * acc, skill)
		LinksLaunch.apply_swing(s, w, LinksGround.surface_for_class(LinksGround.ground_class_for(lie)), rng)
	var b := clubs.launch_state(s)
	b.position = from
	return b


## The club's full-swing power rating from the game's default club records:
## 112 for the driver down to 80 for the wedges (LinksMouse.MAX_POWER), 100
## for a club the game doesn't have.
static func club_rating(club: Club) -> float:
	if club.is_putter or not LinksLaunch.CLUB_INDEX.has(club.short_name):
		return 100.0
	return LinksMouse.MAX_POWER[LinksLaunch.CLUB_INDEX[club.short_name]]


## Club distances (Club.total_m) are at power 100; a full swing here gives
## the club's rating instead, so reach scales by it (a little rough, as
## distance isn't quite in proportion to power).
func reach_scale(club: Club) -> float:
	if clubs == null:
		return 1.0
	return club_rating(club) / 100.0


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind, aero)
