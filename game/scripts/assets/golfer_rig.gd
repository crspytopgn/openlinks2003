class_name GolferRig
extends Node3D
## A golfer in the world. The rig faces -Z (towards the ball) with the target
## to its left (-X), standing so the ball is at its origin's forward side.
## The golfer animation decoder plugs in through GolferAssets.
##
## Animation names the game uses: &"address", &"backswing", &"swing",
## &"putt", &"celebrate".


func play(_animation: StringName) -> void:
	pass
