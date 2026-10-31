class_name Scenery
extends Node3D
## Sky, sun, fog and post-processing for the course. Quality settings switch
## the expensive parts on and off; the Forward+-only effects (SSAO, SSIL,
## soft sun shadows) are left off on the Compatibility renderer used by the
## web build.
##
## Two lighting styles: Classic keeps Links 2003's flat, true-to-texture
## colours (linear tone map, colour ambient); Photoreal uses a filmic tone
## map, a stronger sun with sky-coloured fill light and, on Forward+,
## volumetric haze and screen-space reflections on the water.

const HORIZON := Color(0.68, 0.77, 0.86)
const AMBIENT := Color(0.66, 0.70, 0.76)
const AMBIENT_ENERGY := 0.5
## With the sun 38 degrees up, flat ground gets 0.85 * sin(38) of it.
const SUN_ENERGY := 0.85
## Photoreal: a brighter sun under the ACES curve, which rolls the highlights
## off instead of clipping them.
const PHOTO_SUN_ENERGY := 1.7
const PHOTO_AMBIENT_ENERGY := 0.75
const PHOTO_EXPOSURE := 1.05

var environment: Environment
var sun: DirectionalLight3D
var backdrop: CourseBackdrop
var _free_sky: Material  ## the photographed sky (FreeAssets), or null
var _backdrop_sky: Material  ## the plain sky behind the course's backdrop
var _photo := false


func _init() -> void:
	name = "Scenery"
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.40, 0.74)
	sky_mat.sky_horizon_color = HORIZON
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.14)
	sky_mat.ground_horizon_color = HORIZON
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# The free photographic sky (FreeAssets), when it has been fetched.
	var panorama := FreeAssets.sky()
	if panorama:
		var pano_mat := PanoramaSkyMaterial.new()
		pano_mat.panorama = panorama
		# An HDR photo: keep its sun-lit clouds from clipping to white under
		# the linear tone map.
		pano_mat.energy_multiplier = 0.8
		sky.sky_material = pano_mat
		_free_sky = pano_mat

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Links 2003 draws its photographic ground textures close to their own
	# colours, with shading from the sun and soft shadows. A linear tone map
	# with the sun and ambient light adding up to about 1 on flat ground keeps
	# them that way; a filmic curve washes the greens out to pale lime.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Distance haze, so far trees and hills fade towards the horizon.
	environment.fog_enabled = true
	environment.fog_light_color = HORIZON
	environment.fog_density = 0.0006
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.3
	environment.glow_intensity = 0.25
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.2
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	# Afternoon sun from behind and to the right of the golfer, so the view
	# down the hole is lit from the front and slopes cast soft shade.
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func apply(settings: GraphicsSettings) -> void:
	var fwd := GraphicsSettings.is_forward_plus()
	var q := settings.quality
	var photo := settings.lighting == GraphicsSettings.Lighting.PHOTOREAL
	sun.directional_shadow_max_distance = settings.shadow_distance()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == GraphicsSettings.Quality.LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Angular size of the sun gives contact-hardening soft shadows (Forward+).
	sun.light_angular_distance = 0.6 if fwd and q >= GraphicsSettings.Quality.HIGH else 0.0
	sun.light_energy = PHOTO_SUN_ENERGY if photo else SUN_ENERGY
	sun.light_color = Color(1.0, 0.94, 0.84) if photo else Color(1.0, 0.95, 0.86)
	if photo:
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		# Compatibility has no sky fill light, so the same sun reads hotter.
		environment.tonemap_exposure = PHOTO_EXPOSURE if fwd else PHOTO_EXPOSURE * 0.8
		environment.tonemap_white = 6.0
		environment.ambient_light_energy = PHOTO_AMBIENT_ENERGY
		# Fill light from the sky itself (blue from above, green bounce from
		# below) where the renderer supports it.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if fwd else Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.6
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_exposure = 1.0
		environment.ambient_light_energy = AMBIENT_ENERGY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var bloom: float = GraphicsSettings.BLOOM_LEVELS[settings.bloom]
	# Classic keeps its faint glow on the brightest highlights.
	environment.glow_enabled = bloom > 0.0 or (not photo and q >= GraphicsSettings.Quality.HIGH)
	environment.glow_intensity = bloom * 2.0 if bloom > 0.0 else 0.25
	environment.glow_bloom = bloom * 0.15
	environment.glow_hdr_threshold = 1.0 if photo else 1.2
	environment.ssao_enabled = fwd and settings.ssao
	environment.ssil_enabled = fwd and settings.ssao and q >= GraphicsSettings.Quality.ULTRA
	# Low sun-lit haze that thickens with distance, and light shafts near
	# the camera. Costly, so only at the top quality.
	environment.volumetric_fog_enabled = fwd and photo and q >= GraphicsSettings.Quality.ULTRA
	environment.volumetric_fog_density = 0.0012
	environment.volumetric_fog_albedo = Color(0.9, 0.93, 1.0)
	environment.volumetric_fog_anisotropy = 0.6
	environment.volumetric_fog_length = 160.0
	environment.volumetric_fog_sky_affect = 0.0
	environment.ssr_enabled = fwd and photo and q >= GraphicsSettings.Quality.HIGH
	environment.ssr_max_steps = 48
	environment.fog_aerial_perspective = 0.5 if photo else 0.3
	_photo = photo
	_choose_sky()


## Shows the course's own horizon (null for none) in front of a cloud sky
## from the player's PANSKY.LIB, when the player's files have one; otherwise
## keeps the default sky. Called once per course.
func set_backdrop(horizon: Image) -> void:
	if backdrop != null:
		backdrop.queue_free()
		backdrop = null
	var b := CourseBackdrop.create(horizon)
	if not b.has_sky and not b.has_horizon:
		b.free()
		return
	backdrop = b
	add_child(b)
	# Above the photo bands the plain sky continues their colours, and the
	# haze fades far ground towards the horizon's own colours.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = b.sky_top.darkened(0.08)
	sky_mat.sky_horizon_color = b.sky_top
	sky_mat.sky_curve = 0.3
	sky_mat.ground_horizon_color = b.ground
	sky_mat.ground_bottom_color = b.ground.darkened(0.3)
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	_backdrop_sky = sky_mat
	_choose_sky()


## Photoreal lighting shows the photographed cloud sky with distance haze
## behind the course's horizon instead of the disc's sky; Classic keeps
## the course's own.
func _choose_sky() -> void:
	var real := _photo and _free_sky != null
	if backdrop != null:
		backdrop.set_photo(real, HORIZON)
	if real or _backdrop_sky == null:
		environment.sky.sky_material = _free_sky if _free_sky != null else environment.sky.sky_material
		environment.fog_light_color = HORIZON
		environment.fog_density = 0.0006 if not real else 0.00035
		# A little haze over the sky too, so the far land melts into it.
		environment.fog_sky_affect = 0.25 if real else 0.0
		if _free_sky is PanoramaSkyMaterial:
			# Brighter in Compatibility, which has no sky fill light.
			(_free_sky as PanoramaSkyMaterial).energy_multiplier = 0.8 if GraphicsSettings.is_forward_plus() else 1.5
		return
	environment.sky.sky_material = _backdrop_sky
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = backdrop.sky_haze.lerp(backdrop.ground, 0.35)
	environment.fog_density = 0.00035
