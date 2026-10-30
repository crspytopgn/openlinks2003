class_name LinksShotModel
extends StandardShotModel
## The ball flight (LinksAero), bounce and roll (LinksGround) of Links 2003,
## used when the player's game folder has the executable. The launch is still
## the stand-in one; see docs/formats/physics.md for what is left.

var aero: LinksAero


func _init(p_aero: LinksAero) -> void:
	aero = p_aero


## Null when no game folder is set up or its executable lacks the tables.
static func from_game_folder() -> LinksShotModel:
	var found := LinksAero.from_game_folder()
	return LinksShotModel.new(found) if found != null else null


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind, aero)
