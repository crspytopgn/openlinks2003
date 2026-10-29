class_name Materials
extends RefCounted
## Shared materials for course rendering, so placeholder and decoded courses
## look alike. Both shaders work on Forward+ and Compatibility.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

static var _terrain: ShaderMaterial
static var _water: ShaderMaterial


## For meshes whose vertex colours hold the surface colour.
static func terrain() -> ShaderMaterial:
	if _terrain == null:
		_terrain = ShaderMaterial.new()
		_terrain.shader = TERRAIN_SHADER
	return _terrain


static func water() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
	return _water


## A round pond of the given radius, centred on its node's origin. The
## shader cuts the square plane to a disc with a soft, foamy edge.
static func water_disc(radius: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var inst := MeshInstance3D.new()
	inst.name = "Water"
	inst.mesh = plane
	inst.material_override = water()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
