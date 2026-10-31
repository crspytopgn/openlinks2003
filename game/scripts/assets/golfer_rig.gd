class_name GolferRig
extends Node3D
## A golfer in the world. The rig faces -Z (towards the ball) with the target
## to its left (-X), standing so the ball is at its origin's forward side.
## The golfer animation decoder plugs in through GolferAssets.
##
## Animation names the game uses: &"address", &"backswing", &"swing",
## &"putt", &"celebrate". Before them the round calls set_shot() with the
## club, the distance to the hole and (just before the swing) the power, so
## a rig can pick the club it holds and the swing it plays.


func play(_animation: StringName) -> void:
	pass


func set_shot(_club: Club, _distance_m: float, _power: float = 1.0) -> void:
	pass
