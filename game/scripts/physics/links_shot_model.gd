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

var aero: LinksAero
var clubs: LinksLaunch
## The swing skill level of the person playing, 0 (easiest) to 3.
var skill := 3
## Set while a computer golfer swings. The game sends computer swings past
## the human miss model (they make their own mistakes, see ComputerGolfer),
## so only the lie applies and the accuracy turns the face, until the game's
## own computer miss generator is ported.
var computer := false
var rng := LinksLaunch.Rand.new(randi())


func _init(p_aero: LinksAero, p_clubs: LinksLaunch = null) -> void:
	aero = p_aero
	clubs = p_clubs


## Null when no game folder is set up or its executable lacks the tables.
static func from_game_folder() -> LinksShotModel:
	var found := LinksAero.from_game_folder()
	return LinksShotModel.new(found, LinksLaunch.from_game_folder()) if found != null else null


func launch(club: Club, power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	if clubs == null or not LinksLaunch.CLUB_INDEX.has(club.short_name):
		return super.launch(club, power, accuracy, aim_deg, lie, from)
	var s := LinksLaunch.Strike.new()
	s.club = LinksLaunch.CLUB_INDEX[club.short_name]
	s.aim = deg_to_rad(aim_deg)
	s.power = 100.0 * clampf(power, 0.0, 1.0)
	var lie_params := LinksGround.surface_for_class(LinksGround.ground_class_for(lie))
	if computer:
		s.face_error = -deg_to_rad(COMPUTER_FACE_ERROR_DEG) * clampf(accuracy, -1.0, 1.0)
		LinksLaunch.apply_lie(s, lie_params)
		var cb := clubs.launch_state(s)
		cb.position = from
		return cb
	# Late (positive accuracy) is a push-slice, which is a negative contact.
	var w := LinksLaunch.SwingInput.new()
	w.skill = skill
	w.teed_up = lie == Surface.Type.TEE
	w.contact = LinksLaunch.meter_contact(-METER_UNITS_AT_FULL_MISS * clampf(accuracy, -1.0, 1.0), skill)
	LinksLaunch.apply_swing(s, w, lie_params, rng)
	var b := clubs.launch_state(s)
	b.position = from
	return b


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind, aero)
