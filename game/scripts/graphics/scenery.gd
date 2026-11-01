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
## Photoreal: a strong sun under the AgX curve, which rolls highlights off
## to white without ACES's lime greens and orange skin, against a fill
## light about a fifth as bright, as in real sunshine.
const PHOTO_SUN_ENERGY := 3.0
const PHOTO_AMBIENT_ENERGY := 0.5
const PHOTO_EXPOSURE := 1.0
## Links 2003's afternoon sun height, which Classic lighting keeps.
const CLASSIC_SUN_ELEVATION := 38.0
const SKY_SHADER := preload("res://shaders/photo_sky.gdshader")
## Photoreal light by time of day (GraphicsSettings.time_of_day): the sun's
## height and bearing (degrees), its colour and strength, the fill light,
## the photographed sky's tint (overall and at the horizon), the glow round
## a low sun, the haze colour and thickness and an exposure that makes up
## for a low sun. Afternoon sits lower and warmer than Classic's sun
## (CLASSIC_SUN_ELEVATION), for long shadows as in TV golf.
const TIMES := {
	"morning": {elevation = 17.0, bearing = 100.0, sun = Color(1.0, 0.86, 0.7), energy = 0.85, fill = 0.95,
		ambient = Color(0.62, 0.69, 0.8), sky = Color(0.92, 0.96, 1.04), horizon = Color(1.05, 1.0, 0.95), glow = 0.25,
		haze = Color(0.76, 0.8, 0.86), fog = 2.2, exposure = 1.15},
	"midday": {elevation = 62.0, bearing = 160.0, sun = Color(1.0, 0.97, 0.93), energy = 1.0, fill = 1.0,
		ambient = Color(0.66, 0.70, 0.76), sky = Color(1.0, 1.0, 1.02), horizon = Color(1.0, 1.0, 1.0), glow = 0.0,
		haze = Color(0.70, 0.78, 0.88), fog = 0.9, exposure = 0.95},
	"afternoon": {elevation = 30.0, bearing = 145.0, sun = Color(1.0, 0.92, 0.8), energy = 1.0, fill = 1.0,
		ambient = Color(0.66, 0.70, 0.76), sky = Color(1.0, 1.0, 1.0), horizon = Color(1.0, 1.0, 1.0), glow = 0.0,
		haze = HORIZON, fog = 1.2, exposure = 1.0},
	"golden": {elevation = 9.0, bearing = 205.0, sun = Color(1.0, 0.66, 0.38), energy = 0.95, fill = 1.0,
		ambient = Color(0.72, 0.66, 0.64), sky = Color(1.02, 0.86, 0.74), horizon = Color(1.15, 0.92, 0.72), glow = 0.8,
		haze = Color(0.9, 0.74, 0.58), fog = 1.6, exposure = 1.35},
}
## "Through the round": the light at these points of the round, blended.
const ROUND_TIMES := [[0.0, "morning"], [0.35, "midday"], [0.7, "afternoon"], [1.0, "golden"]]

var environment: Environment
var sun: DirectionalLight3D
var backdrop: CourseBackdrop
var _free_sky: Material  ## the photographed sky (FreeAssets), or null
var _backdrop_sky: Material  ## the plain sky behind the course's backdrop
var _photo := false
var _gi := false  ## global illumination on (Ultra Photoreal on a real GPU)
## The sun and fill light apply() set, before the weather scales them.
var _sun_energy := SUN_ENERGY
var _sun_color := Color(1.0, 0.95, 0.86)
var _ambient_energy := AMBIENT_ENERGY
var _sun_angle := 0.0
## The time of day's light (TIMES entries blended), and how far through the
## round it is, for "Through the round".
var _time: Dictionary = TIMES["afternoon"]
var _time_setting := 0
var _round_progress := 0.0


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
		var pano_mat := ShaderMaterial.new()
		pano_mat.shader = SKY_SHADER
		pano_mat.set_shader_parameter("panorama", panorama)
		# An HDR photo: keep its sun-lit clouds from clipping to white under
		# the linear tone map.
		pano_mat.set_shader_parameter("energy", 0.8)
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
		environment.tonemap_mode = Environment.TONE_MAPPER_AGX
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
	# Glow only off what is really bright (the sun on sand, white
	# clouds): a whole-image bloom lays a milky veil over the course that
	# reads as haze and greys the sky, most of all in Forward+.
	environment.glow_bloom = bloom * 0.15 if not photo else 0.0
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
	# Real-time global illumination at the top end (Ultra, Forward+, a real
	# graphics card): sunlight bouncing off the turf into the shade, green
	# light under the trees and the sky shut out beneath them, as UE5's
	# Lumen does. Software renderers would crawl, so never there.
	_gi = gi_available(settings)
	environment.sdfgi_enabled = _gi
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_cascades = 6
	environment.sdfgi_min_cell_size = 0.4
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	environment.sdfgi_bounce_feedback = 0.5
	environment.sdfgi_energy = 1.0
	environment.ssr_max_steps = 48
	environment.fog_aerial_perspective = 0.5 if photo else 0.3
	_photo = photo
	_time_setting = settings.time_of_day
	_apply_time()
	_sun_energy = sun.light_energy
	_sun_color = sun.light_color
	_ambient_energy = environment.ambient_light_energy
	_sun_angle = sun.light_angular_distance
	_choose_sky()


## Whether `settings` get global illumination on this machine.
static func gi_available(settings: GraphicsSettings) -> bool:
	return GraphicsSettings.is_forward_plus() and settings.lighting == GraphicsSettings.Lighting.PHOTOREAL \
		and settings.quality >= GraphicsSettings.Quality.ULTRA \
		and RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_CPU


## Shows the course's own horizon (null for none) in front of a cloud sky
## from the player's files (the course's own, `course_sky`, unless the
## player picked one), when the player's files have one; otherwise keeps
## the default sky. Called once per course.
func set_backdrop(horizon: Image, course_sky := 0) -> void:
	if backdrop != null:
		backdrop.queue_free()
		backdrop = null
	var b := CourseBackdrop.create(horizon, course_sky)
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
## behind the course's horizon instead of the disc's sky, unless the player
## picked a sky; Classic keeps the course's own.
func _choose_sky() -> void:
	var real := _photo and _free_sky != null and not (backdrop != null and backdrop.chosen and backdrop.has_sky)
	_apply_weather()
	if backdrop != null:
		backdrop.set_photo(real, HORIZON)
	if real or _backdrop_sky == null:
		environment.sky.sky_material = _free_sky if _free_sky != null else environment.sky.sky_material
		environment.fog_light_color = _time.haze if real else HORIZON
		environment.fog_density = 0.0006 if not real else 0.00035 * float(_time.fog)
		# A little haze over the sky too, so the far land melts into it.
		environment.fog_sky_affect = 0.25 if real else 0.0
		if _free_sky is ShaderMaterial:
			# Brighter in Compatibility, which has no sky fill light.
			var sky_mat := _free_sky as ShaderMaterial
			sky_mat.set_shader_parameter("energy", 0.8 if GraphicsSettings.is_forward_plus() else 1.5)
			sky_mat.set_shader_parameter("tint", _time.sky)
			sky_mat.set_shader_parameter("horizon_tint", _time.horizon)
			sky_mat.set_shader_parameter("glow", _time.glow)
			sky_mat.set_shader_parameter("glow_color", _time.sun)
		return
	environment.sky.sky_material = _backdrop_sky
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = backdrop.sky_haze.lerp(backdrop.ground, 0.35)
	environment.fog_density = 0.00035


## How far through the round the player is (0 the first hole, 1 the last),
## for the "Through the round" time of day. Call before the hole's ground
## shade is baked, as the sun moves.
func set_round_progress(f: float) -> void:
	_round_progress = clampf(f, 0.0, 1.0)
	if _photo and _time_setting == GraphicsSettings.TimeOfDay.ROUND:
		_apply_time()
		_sun_energy = sun.light_energy
		_sun_color = sun.light_color
		_ambient_energy = environment.ambient_light_energy
		_choose_sky()


## The light of the time of day: TIMES for one setting, or a blend of
## them through the round.
static func time_light(setting: int, progress: float) -> Dictionary:
	match setting:
		GraphicsSettings.TimeOfDay.MORNING:
			return TIMES["morning"]
		GraphicsSettings.TimeOfDay.MIDDAY:
			return TIMES["midday"]
		GraphicsSettings.TimeOfDay.GOLDEN:
			return TIMES["golden"]
		GraphicsSettings.TimeOfDay.ROUND:
			for i in ROUND_TIMES.size() - 1:
				var a: Array = ROUND_TIMES[i]
				var b: Array = ROUND_TIMES[i + 1]
				if progress <= b[0]:
					return _blend(TIMES[a[1]], TIMES[b[1]], (progress - a[0]) / (b[0] - a[0]))
			return TIMES["golden"]
	return TIMES["afternoon"]


static func _blend(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for key: String in a:
		if a[key] is Color:
			out[key] = (a[key] as Color).lerp(b[key], f)
		else:
			out[key] = lerpf(a[key], b[key], f)
	return out


## Sets the sun, fill light and exposure for the time of day. Classic
## lighting keeps Links 2003's afternoon sun.
func _apply_time() -> void:
	_time = time_light(_time_setting, _round_progress) if _photo else TIMES["afternoon"]
	var elevation: float = _time.elevation if _photo else CLASSIC_SUN_ELEVATION
	sun.rotation_degrees = Vector3(-elevation, float(_time.bearing), 0.0)
	RenderingServer.global_shader_parameter_set("sky_tint", Vector3(1, 1, 1))
	if not _photo:
		environment.ambient_light_color = AMBIENT
		return
	var c: Color = _time.sun
	sun.light_color = c
	sun.light_energy = PHOTO_SUN_ENERGY * float(_time.energy)
	# Compatibility has no sky light, so its flat fill is a little stronger,
	# or shade goes near black.
	environment.ambient_light_energy = PHOTO_AMBIENT_ENERGY * float(_time.fill) * (1.0 if GraphicsSettings.is_forward_plus() else 1.25)
	if _gi:
		# The bounced light does much of the fill's work.
		environment.ambient_light_energy *= 0.6
	environment.ambient_light_color = _time.ambient
	var fwd := GraphicsSettings.is_forward_plus()
	environment.tonemap_exposure = (PHOTO_EXPOSURE if fwd else PHOTO_EXPOSURE * 0.8) * float(_time.exposure)
	var sky: Color = _time.sky
	RenderingServer.global_shader_parameter_set("sky_tint", Vector3(sky.r, sky.g, sky.b))


## Photoreal light follows a sky the player picked: under cloud the sun
## dims and its shadows soften while the sky's fill light grows; a sunrise
## or sunset sky warms the sun. Classic and the photographed sky keep the
## light apply() set.
func _apply_weather() -> void:
	sun.light_energy = _sun_energy
	sun.light_color = _sun_color
	environment.ambient_light_energy = _ambient_energy
	sun.light_angular_distance = _sun_angle
	if not _photo or backdrop == null or not backdrop.chosen or not backdrop.has_sky:
		return
	var o := backdrop.overcast
	sun.light_energy = _sun_energy * (1.0 - 0.65 * o)
	environment.ambient_light_energy = _ambient_energy * (1.0 + 0.6 * o)
	if backdrop.warm:
		sun.light_color = Color(1.0, 0.78, 0.55)
	if GraphicsSettings.is_forward_plus():
		sun.light_angular_distance = maxf(_sun_angle, 4.0 * o)
