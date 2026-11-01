class_name GolferRig
extends Node3D
## A golfer in the world. The rig faces -Z (towards the ball) with the target
## to its left (-X), standing so the ball is at its origin's forward side.
## The golfer animation decoder plugs in through GolferAssets.
##
## Animation names the game uses: &"address", &"backswing", &"swing",
## &"putt", &"celebrate" (an eagle or better), &"fist_pump" (a birdie),
## &"slump" (a short putt missed), &"upset" (after a penalty). A rig without a
## fist pump can play celebrate for it; one without a slump can skip it.
## Before them the round calls set_shot() with the
## club, the distance to the hole and (just before the swing) the power, so
## a rig can pick the club it holds and the swing it plays.


func play(_animation: StringName) -> void:
	pass


func set_shot(_club: Club, _distance_m: float, _power: float = 1.0) -> void:
	pass


## Turns the golfer's head to follow `target` (the ball in flight) after
## `delay` seconds, until the next play().
func watch(_target: Node3D, _delay: float = 0.3) -> void:
	pass


## Ground height at (x, z) in world space, for planting the feet on slopes;
## `sink` digs the feet in that many metres (a bunker stance).
func set_ground(_height: Callable, _sink: float = 0.0) -> void:
	pass
