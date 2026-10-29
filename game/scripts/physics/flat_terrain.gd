class_name FlatTerrain
extends CourseTerrain
## Level ground of one surface type. Used by tests and distance estimates.

var surface: int
var level: float


func _init(p_surface: int = Surface.Type.FAIRWAY, p_level := 0.0) -> void:
	surface = p_surface
	level = p_level


func height_at(_x: float, _z: float) -> float:
	return level


func surface_at(_x: float, _z: float) -> int:
	return surface


func normal_at(_x: float, _z: float) -> Vector3:
	return Vector3.UP
