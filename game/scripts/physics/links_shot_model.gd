class_name LinksShotModel
extends StandardShotModel
## The launch (LinksLaunch), ball flight (LinksAero), bounce and roll
## (LinksGround) of Links 2003, used when the player's game folder has the
## executable. How the swing meter's accuracy maps onto the strike is still a
## stand-in; see docs/formats/physics.md for what is left.

## Face angle at accuracy +/-1 until the game's swing meter is ported.
const MAX_FACE_ERROR_DEG := 4.0
## Sand contact (steps of extra sand) at accuracy +/-1, likewise.
const SAND_CONTACT_AT_FULL_MISS := 10.0

var aero: LinksAero
var clubs: LinksLaunch


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
	# Late (positive accuracy) opens the face: a push-slice.
	s.face_error = -deg_to_rad(MAX_FACE_ERROR_DEG) * clampf(accuracy, -1.0, 1.0)
	# The sand contact comes from the meter too; until the meters are ported
	# a perfect strike is the standard splash and misses take more sand.
	var lie_params := LinksGround.surface_for_class(LinksGround.ground_class_for(lie))
	LinksLaunch.apply_lie(s, lie_params, roundi(absf(accuracy) * SAND_CONTACT_AT_FULL_MISS))
	var b := clubs.launch_state(s)
	b.position = from
	return b


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind, aero)
