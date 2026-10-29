class_name CourseTerrain
extends RefCounted
## What the game needs from a course's ground: height, surface type and the
## visible mesh. Mirrors olcore::Terrain. A course loader returns one per hole
## (holes may share one). Override height_at(), surface_at() and
## build_visual(); normal_at() has a finite-difference default.

## Trees, walls and the like the ball can hit; null for none.
var obstacles: ObstacleField


func height_at(_x: float, _z: float) -> float:
	return 0.0


## A Surface.Type value.
func surface_at(_x: float, _z: float) -> int:
	return Surface.Type.FAIRWAY


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.25
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## The first obstacle the ball meets moving from -> to, as
## ObstacleField.segment_hit() returns it ({} for none). Mirrors
## olcore::Terrain::obstacle_hit.
func obstacle_hit(from: Vector3, to: Vector3) -> Dictionary:
	return obstacles.segment_hit(from, to) if obstacles != null else {}


## Builds the visible ground (and water) for this terrain. Called once each
## time a hole using it is shown; the caller owns the returned node.
func build_visual() -> Node3D:
	return Node3D.new()
