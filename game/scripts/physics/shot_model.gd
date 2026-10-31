class_name ShotModel
extends RefCounted
## The physics behind a shot. The round only talks to this interface, so the
## stand-in model can be replaced by the C++ core (through GDExtension) or by
## one tuned against the original game without touching the game flow.


## Launch state for a swing, with the ball sitting at `from` on a `lie`.
func launch(_club: Club, _power: float, _accuracy: float, _aim_deg: float, _lie: int, from: Vector3) -> BallState:
	push_error("ShotModel.launch() is not implemented")
	return BallState.new(from)


## Flies, bounces and rolls the ball until it stops, drops into the cup at
## `cup`, or ends in water or out of bounds. `wind` is the velocity of the air
## in m/s (see Wind).
func simulate(_start: BallState, _terrain: CourseTerrain, _cup: Vector3, _wind := Vector3.ZERO) -> ShotResult:
	push_error("ShotModel.simulate() is not implemented")
	return ShotResult.new()
