class_name BallState
extends RefCounted
## Position, velocity and spin of the ball. Mirrors olcore::BallState.
## The position is the bottom of the ball, so a ball at rest sits at the
## terrain height.

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var spin := Vector3.ZERO  ## angular velocity, rad/s
## A putt: starts rolling on the ground rather than in flight, tilted onto
## the slope by the Links model (LinksLaunch.putt_slope).
var on_ground := false


func _init(p_position := Vector3.ZERO, p_velocity := Vector3.ZERO, p_spin := Vector3.ZERO) -> void:
	position = p_position
	velocity = p_velocity
	spin = p_spin


func copy() -> BallState:
	var b := BallState.new(position, velocity, spin)
	b.on_ground = on_ground
	return b
