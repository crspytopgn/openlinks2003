class_name Scenery
extends Node3D
## Sky, sun, fog and post-processing for the course. Quality settings switch
## the expensive parts on and off; the Forward+-only effects (SSAO, SSIL,
## soft sun shadows) are left off on the Compatibility renderer used by the
## web build.

const HORIZON := Color(0.68, 0.77, 0.86)
const AMBIENT := Color(0.66, 0.70, 0.76)
const AMBIENT_ENERGY := 0.5
## With the sun 38 degrees up, flat ground gets 0.85 * sin(38) of it.
const SUN_ENERGY := 0.85

var environment: Environment
var sun: DirectionalLight3D
var backdrop: CourseBackdrop


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
	sun.directional_shadow_max_distance = settings.shadow_distance()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == GraphicsSettings.Quality.LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Angular size of the sun gives contact-hardening soft shadows (Forward+).
	sun.light_angular_distance = 0.6 if fwd and q >= GraphicsSettings.Quality.HIGH else 0.0
	environment.glow_enabled = q >= GraphicsSettings.Quality.HIGH
	environment.ssao_enabled = fwd and q >= GraphicsSettings.Quality.HIGH
	environment.ssil_enabled = fwd and q >= GraphicsSettings.Quality.ULTRA


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
	environment.sky.sky_material = sky_mat
	environment.fog_light_color = b.sky_haze.lerp(b.ground, 0.35)
	environment.fog_density = 0.00035
