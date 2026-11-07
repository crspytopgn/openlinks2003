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


## Seconds from play(&"swing") to the club meeting the ball. The round holds
## the ball (and the strike sound) that long, so the ball leaves the club.
## Rigs whose swing starts at impact return 0.
func impact_delay() -> float:
	return 0.0


## The same for play(&"putt"): seconds to the putter meeting the ball.
func putt_impact_delay() -> float:
	return 0.0


## Turns the golfer's head to follow `target` (the ball in flight) after
## `delay` seconds, until the next play().
func watch(_target: Node3D, _delay: float = 0.3) -> void:
	pass


## Plays a reaction (&"fore_left", &"fore_right": pointing after a shot
## heading well offline) `delay` seconds into the clip playing now, unless
## another clip has started by then. Rigs without it do nothing.
func react(_animation: StringName, _delay: float) -> void:
	pass


## Ground height at (x, z) in world space, for planting the feet on slopes;
## `sink` digs the feet in that many metres (a bunker stance).
func set_ground(_height: Callable, _sink: float = 0.0) -> void:
	pass


## The player's stand bag for this shot (null with a caddie or the buggy),
## set before play(&"address") at a new ball: a rig can take its club out
## of it before walking in.
func set_bag(_bag: Node3D) -> void:
	pass


## True while the golfer is still taking the club from the bag or walking
## from it: the computer golfers wait for it before their routine.
func busy() -> bool:
	return false


## True until the golfer is over the ball at the end of his walk in (the
## bag, the look down the line, the steps in): a computer golfer's address
## and swing wait for it.
func walking() -> bool:
	return false
