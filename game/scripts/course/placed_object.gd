class_name PlacedObject
extends RefCounted
## One object instance on a hole: which library object, and where.

var id: String  ## key understood by the ObjectLibrary
var position := Vector3.ZERO
var yaw_deg := 0.0
var scale := 1.0


func _init(p_id := "", p_position := Vector3.ZERO, p_yaw_deg := 0.0, p_scale := 1.0) -> void:
	id = p_id
	position = p_position
	yaw_deg = p_yaw_deg
	scale = p_scale
