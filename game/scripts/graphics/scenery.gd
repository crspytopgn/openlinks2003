class_name Scenery
extends Node3D
## Sky, sun, fog and post-processing for the course. Quality settings switch
## the expensive parts on and off; the Forward+-only effects (SSAO, SSIL,
## soft sun shadows) are left off on the Compatibility renderer used by the
## web build.

const HORIZON := Color(0.68, 0.77, 0.86)

var environment: Environment
var sun: DirectionalLight3D


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
		sky.sky_material = pano_mat

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	# Distance haze, so far trees and hills fade into the sky.
	environment.fog_enabled = true
	environment.fog_light_color = HORIZON
	environment.fog_density = 0.0009
	environment.fog_sky_affect = 0.25
	environment.fog_aerial_perspective = 0.5
	if panorama:
		# The photo sky is bright and blue: less of it as ambient light, so
		# the shade on the grass stays green, and less haze towards it.
		environment.ambient_light_sky_contribution = 0.7
		environment.ambient_light_color = Color(0.60, 0.64, 0.55)
		environment.fog_aerial_perspective = 0.15
		environment.tonemap_exposure = 0.95
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	# Afternoon sun from behind and to the right of the golfer, so the view
	# down the hole is lit from the front and slopes cast soft shade.
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func apply(settings: GraphicsSettings) -> void:
	var fwd := GraphicsSettings.is_forward_plus()
	var q := settings.quality
	sun.directional_shadow_max_distance = settings.shadow_distance()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == GraphicsSettings.Quality.LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Angular size of the sun gives contact-hardening soft shadows (Forward+).
	sun.light_angular_distance = 0.6 if fwd and q >= GraphicsSettings.Quality.HIGH else 0.0
	environment.glow_enabled = q >= GraphicsSettings.Quality.MEDIUM
	environment.ssao_enabled = fwd and q >= GraphicsSettings.Quality.HIGH
	environment.ssil_enabled = fwd and q >= GraphicsSettings.Quality.ULTRA
