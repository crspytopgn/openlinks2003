class_name Swing
extends RefCounted
## Turns a swing meter result into a launch. Mirrors olcore::launch_from_swing
## in libs/olcore/src/swing.cpp.

const MAX_SIDESPIN_RPM := 1500.0  ## at accuracy +/-1
const MAX_PUSH_DEG := 2.5  ## start-line error at accuracy +/-1
const MAX_PUTT_PUSH_DEG := 2.0


## power: 0..1. accuracy: -1..1, 0 is perfect, negative is early (pull-hook),
## positive is late (push-slice). aim_deg: heading, positive = left of +z.
## The ball starts at the origin; move it with BallState.position.
static func launch_from_swing(club: Club, power: float, accuracy: float, aim_deg: float, lie: int) -> BallState:
	var p := clampf(power, 0.0, 1.0)
	var acc := clampf(accuracy, -1.0, 1.0)
	if club.is_putter:
		return BallPhysics.make_launch(club.ball_speed_mps * p, 0.0, aim_deg - acc * MAX_PUTT_PUSH_DEG, 0.0, 0.0)
	var speed := club.ball_speed_mps * p * Surface.lie_power(lie)
	var backspin := club.backspin_rpm * Surface.lie_spin(lie) * (0.6 + 0.4 * p)
	return BallPhysics.make_launch(speed, club.launch_deg, aim_deg - acc * MAX_PUSH_DEG, backspin, -acc * MAX_SIDESPIN_RPM)
