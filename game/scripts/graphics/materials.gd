class_name Materials
extends RefCounted
## Shared materials for course rendering, so placeholder and decoded courses
## look alike. Both shaders work on Forward+ and Compatibility.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

static var _terrain: ShaderMaterial
static var _water: ShaderMaterial
static var _water_surface: ShaderMaterial
static var _ground_shade: ShaderMaterial


## For meshes whose vertex colours hold the surface colour, and whose UV2
## holds the rough and sand weights (see terrain_weights()). Uses the free
## photo textures when they have been fetched.
static func terrain() -> ShaderMaterial:
	if _terrain == null:
		_terrain = ShaderMaterial.new()
		_terrain.shader = TERRAIN_SHADER
		if FreeAssets.has_grounds():
			_terrain.set_shader_parameter("textured", true)
			for slot in FreeAssets.GROUNDS:
				var albedo := FreeAssets.ground(slot, "albedo")
				_terrain.set_shader_parameter(slot + "_albedo", albedo)
				_terrain.set_shader_parameter(slot + "_normal", FreeAssets.ground(slot, "normal"))
				var mean := FreeAssets.mean_color(albedo).srgb_to_linear()
				_terrain.set_shader_parameter(slot + "_mean", Vector3(mean.r, mean.g, mean.b))
			var gh := FreeAssets.ground("grass", "height")
			var rh := FreeAssets.ground("rough", "height")
			if gh != null and rh != null:
				_terrain.set_shader_parameter("grass_height", gh)
				_terrain.set_shader_parameter("rough_height", rh)
				_terrain.set_shader_parameter("grass_height_mean", FreeAssets.mean_color(gh).r)
				_terrain.set_shader_parameter("rough_height_mean", FreeAssets.mean_color(rh).r)
				_terrain.set_shader_parameter("has_height", true)
	return _terrain


## The UV2 value terrain() reads for a surface: x is the rough weight, y the
## sand weight, and anything else is grass.
static func terrain_weights(surface: Surface.Type) -> Vector2:
	match FreeAssets.slot_for(surface):
		"sand":
			return Vector2(0.0, 1.0)
		"rough":
			return Vector2(1.0, 0.0)
	return Vector2.ZERO


## How closely `surface` is cut, for the terrain shader's `surface_cut`:
## 1 the green (fine, dense, smooth turf), about half the collar round it
## and a little for the tee, 0 for everything else.
static func terrain_cut(surface: int) -> float:
	match surface:
		Surface.Type.GREEN:
			return 1.0
		Surface.Type.FRINGE:
			return 0.5
		Surface.Type.TEE:
			return 0.25
	return 0.0


## A next pass for ground with a standard material that adds the baked
## ground shade (GroundShade); the ground shader does it itself.
static func ground_shade_pass() -> ShaderMaterial:
	if _ground_shade == null:
		_ground_shade = ShaderMaterial.new()
		_ground_shade.shader = preload("res://shaders/ground_shade_overlay.gdshader")
	return _ground_shade


static func water() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
		_reflect_sky(_water)
	return _water


## For water drawn as part of a course's ground mesh: the same shader
## without the round cut-out.
static func water_surface() -> ShaderMaterial:
	if _water_surface == null:
		_water_surface = ShaderMaterial.new()
		_water_surface.shader = WATER_SHADER
		_water_surface.set_shader_parameter("disc", false)
		_reflect_sky(_water_surface)
	return _water_surface


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


## Lets the water reflect the photographed sky, when it has been fetched.
static func _reflect_sky(mat: ShaderMaterial) -> void:
	var sky := FreeAssets.sky()
	if sky == null:
		return
	mat.set_shader_parameter("sky_pano", sky)
	mat.set_shader_parameter("has_pano", true)
	# As bright as the sky itself shows (Scenery's panorama energy).
	mat.set_shader_parameter("pano_energy", 0.8 if GraphicsSettings.is_forward_plus() else 1.5)
