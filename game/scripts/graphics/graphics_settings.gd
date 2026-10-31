class_name GraphicsSettings
extends RefCounted
## Display and quality settings, saved to user://settings.cfg under
## [graphics], plus the wind strength, the presentation and the swing skill
## level under [game].
## Other sections of that file (such as the game folder) are left alone.
##
## A "look" preset sets everything at once (see apply_look()); changing a
## single option makes the look Custom. On the first run the look is picked
## for the device (detect_look()), so phones and the browser start light and
## gaming PCs start on Photoreal. See docs/graphics.md.

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
## Classic frames and dresses the round like Links 2003; Broadcast like a TV
## golf broadcast (ShotDirector cameras, tracer, replays, BroadcastOverlay).
## Tour is Broadcast with the tour graphics package (TourGraphics): the
## leaderboard rail, the shot-data bar, the driving zone and the putt read.
enum Presentation { CLASSIC, BROADCAST, TOUR }
enum Look { PHOTOREAL, NATURAL, CINEMATIC, CLASSIC, PERFORMANCE, CUSTOM }
enum Lighting { CLASSIC, PHOTOREAL }
enum Upscaler { OFF, FSR1, FSR2 }
enum Grade { NEUTRAL, VIVID, WARM, COOL, FILM }

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const GAME_SECTION := "game"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const MSAA_CHOICES := [0, 2, 4, 8]
const RENDER_SCALES := [0.5, 0.75, 1.0, 1.25, 1.5]
const PRESENTATION_NAMES := ["Classic Links", "Broadcast", "Tour"]
const LOOK_NAMES := ["Photoreal", "Natural", "Cinematic", "Classic Links", "Performance", "Custom"]
const LIGHTING_NAMES := ["Classic Links", "Photoreal"]
const UPSCALER_NAMES := ["Off", "FSR 1", "FSR 2"]
const GRADE_NAMES := ["Neutral", "Vivid", "Warm afternoon", "Cool morning", "Film"]
const LEVEL_NAMES := ["Off", "Low", "Medium", "High"]
const PUTTING_GRID_NAMES := ["Off", "Yellow (Links)", "Coloured by height (Links)", "Coloured by slope (TV)"]
## Trees: the course's own (classic) or 3D, by how far out they stay 3D
## before turning into impostors (TreeFactory.IMPOSTOR_DISTANCE).
const TREE_NAMES := ["Classic", "3D near", "3D", "3D far"]
const DYNAMIC_NAMES := ["Off", "Keep 30 fps", "Keep 60 fps"]
const DYNAMIC_FPS := [0, 30, 60]
## Strength of each level (Off, Low, Medium, High) of the post effects.
const SHARPEN_LEVELS := [0.0, 0.25, 0.5, 0.8]
const BLOOM_LEVELS := [0.0, 0.15, 0.3, 0.55]
const VIGNETTE_LEVELS := [0.0, 0.15, 0.3, 0.5]
const GRAIN_LEVELS := [0.0, 0.025, 0.05, 0.1]

## Tests and the CI render check set this to fix the look (-1: as saved).
static var force_look := -1

var quality: int = Quality.HIGH
var fullscreen := false
var vsync := true
var msaa := 2  ## samples: 0, 2, 4 or 8
var render_scale := 1.0  ## 3D resolution relative to the window
var fov := 50.0  ## vertical field of view, degrees (Links frames shots fairly tight)
var wind: int = Wind.Level.MODERATE
var presentation: int = Presentation.BROADCAST
## Web only: copy the disc's crowd, menu and golfer voice sounds into memory
## at startup (tens of MB) instead of using the light placeholder sounds.
## Desktop builds always read them from the game folder.
var web_disc_sounds := false
## Swing skill level for the people playing, 0 (easiest) to 3: how hard the
## Links 2003 swing punishes a missed snap (LinksLaunch.apply_swing).
var skill := 3
## The game's green options (LinksGround.set_greens): firmness 0 soft, 1
## medium, 2 firm; speed 0 slow, 1 normal, 2 fast.
var green_firmness := 1
var green_speed := 1
## How the people playing swing: 0 the three-click meter, 1 Links 2003's
## PowerStroke mouse swing (MouseSwingControl). Space always uses the meter.
var swing_method := 1
## Links 2003's swing help for the mouse swing: once most of a player's
## strokes have had no sideways movement at all, strokes are nudged a few
## degrees off line (LinksMouse.Help).
var swing_help := false
## Green reading (GreenRead): the putting grid, 0 off, 1 Links 2003's yellow
## grid, 2 its grid coloured by height, 3 the TV grid coloured by slope
## (GreenGrid.Style + 1). As in the game, the grid isn't there at Elite
## skill, except as the Broadcast presentation's TV graphic.
var putting_grid := 3
## Links 2003's Breakline Indicator at the foot of the aiming marker.
var breakline := false
## Links 2003's Putting Assistant: the line and power at Amateur skill, a
## band round the line at Professional, nothing harder.
var putting_assistant := false
## A caddie at the players' shots with a read scaled to the swing skill
## (Caddie, CaddieAdvice). Off by default, as in Links 2003.
var caddie := false
## Draw the ball at its true size everywhere. Off by default: like Links,
## the ball is drawn bigger with distance so it stays easy to follow.
var true_size_ball := false
## Drive a golf buggy to the ball between shots (GolfBuggy). Off by default.
var buggy := false

var look: int = Look.CLASSIC
var lighting: int = Lighting.CLASSIC
var upscaler: int = Upscaler.OFF
var dynamic_res := 0  ## index into DYNAMIC_FPS
## Post effects, as levels 0 (off) to 3 (high).
var sharpen := 0
var bloom := 0
var vignette := 0
var grain := 0
var grade: int = Grade.NEUTRAL
var ssao := false
var dof := false
## 3D grass in the rough, 0 (off) to 3 (dense and far).
var grass := 0
var foliage_wind := false
## Shadows of passing clouds drifting over the course with the wind.
var cloud_shadows := false
## 0 classic trees, 1 to 3 photo-textured 3D trees (see TREE_NAMES).
var trees := 0


func _init() -> void:
	# The browser build runs on everything from phones to desktops, on the
	# simpler renderer, so it starts a notch lower, but with 2x MSAA:
	# without it trees, flags and the golfer look jagged and low-res.
	if OS.has_feature("web"):
		quality = Quality.MEDIUM
		msaa = 2


## The look to start with on this device: Photoreal on a dedicated graphics
## card, Natural on built-in graphics and desktop browsers, Performance on
## phones, tablets and software renderers.
static func detect_look() -> int:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return Look.PERFORMANCE
	if OS.has_feature("web"):
		return Look.NATURAL
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return Look.PHOTOREAL
		RenderingDevice.DEVICE_TYPE_CPU:
			return Look.PERFORMANCE
	return Look.NATURAL


## Sets every option to the preset `which` (a Look). Options the renderer
## can't do (SSAO, depth of field and FSR in the browser) are still stored
## and simply skipped when applied. The browser build keeps quality and grass
## a notch lower, as it shares one thread with the game.
func apply_look(which: int) -> void:
	look = which
	match which:
		Look.PHOTOREAL:
			_set_look(Quality.ULTRA, Lighting.PHOTOREAL, Upscaler.FSR2, 0, 1.0, [1, 2, 1, 1], Grade.NEUTRAL, true, true, 3)
		Look.NATURAL:
			_set_look(Quality.HIGH, Lighting.PHOTOREAL, Upscaler.OFF, 2, 1.0, [1, 1, 1, 0], Grade.NEUTRAL, true, false, 2)
		Look.CINEMATIC:
			_set_look(Quality.ULTRA, Lighting.PHOTOREAL, Upscaler.FSR2, 0, 1.0, [1, 3, 2, 2], Grade.FILM, true, true, 3)
		Look.CLASSIC:
			_set_look(Quality.HIGH, Lighting.CLASSIC, Upscaler.OFF, 2, 1.0, [0, 0, 0, 0], Grade.NEUTRAL, false, false, 0)
			foliage_wind = false
			cloud_shadows = false
			dynamic_res = 0
			trees = 0
			return
		Look.PERFORMANCE:
			# A lower 3D resolution, upscaled with FSR 1 where it's
			# available and sharpened, costs far less than it shows.
			_set_look(Quality.LOW, Lighting.PHOTOREAL, Upscaler.FSR1, 0, 0.75, [2, 0, 0, 0], Grade.NEUTRAL, false, false, 1)
		_:
			return
	foliage_wind = true
	cloud_shadows = which != Look.PERFORMANCE
	dynamic_res = 2
	trees = 1 if which == Look.PERFORMANCE else (3 if quality >= Quality.ULTRA else 2)
	if OS.has_feature("web"):
		quality = mini(quality, Quality.MEDIUM)
		grass = mini(grass, 1)
		trees = mini(trees, 1)
		msaa = maxi(msaa, 2) if which != Look.PERFORMANCE else 0


## `post` is [sharpen, bloom, vignette, grain] levels.
func _set_look(q: int, light: int, up: int, samples: int, scale: float, post: Array, g: int, ao: bool, blur: bool, grass_level: int) -> void:
	quality = q
	lighting = light
	upscaler = up
	msaa = samples
	render_scale = scale
	sharpen = post[0]
	bloom = post[1]
	vignette = post[2]
	grain = post[3]
	grade = g
	ssao = ao
	dof = blur
	grass = grass_level


static func load_saved(path := PATH) -> GraphicsSettings:
	var s := GraphicsSettings.new()
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file (first run) leaves it empty
	s.quality = clampi(int(cfg.get_value(SECTION, "quality", s.quality)), Quality.LOW, Quality.ULTRA)
	s.fullscreen = bool(cfg.get_value(SECTION, "fullscreen", s.fullscreen))
	s.vsync = bool(cfg.get_value(SECTION, "vsync", s.vsync))
	var samples := int(cfg.get_value(SECTION, "msaa", s.msaa))
	s.msaa = samples if MSAA_CHOICES.has(samples) else s.msaa
	s.render_scale = clampf(float(cfg.get_value(SECTION, "render_scale", s.render_scale)), 0.25, 2.0)
	s.fov = clampf(float(cfg.get_value(SECTION, "fov", s.fov)), 40.0, 90.0)
	s.wind = clampi(int(cfg.get_value(GAME_SECTION, "wind", s.wind)), Wind.Level.OFF, Wind.Level.STRONG)
	s.presentation = clampi(int(cfg.get_value(GAME_SECTION, "presentation", s.presentation)), Presentation.CLASSIC, Presentation.TOUR)
	s.web_disc_sounds = bool(cfg.get_value(GAME_SECTION, "web_disc_sounds", s.web_disc_sounds))
	s.skill = clampi(int(cfg.get_value(GAME_SECTION, "skill", s.skill)), 0, LinksLaunch.SKILL_COUNT - 1)
	s.green_firmness = clampi(int(cfg.get_value(GAME_SECTION, "green_firmness", s.green_firmness)), 0, 2)
	s.green_speed = clampi(int(cfg.get_value(GAME_SECTION, "green_speed", s.green_speed)), 0, 2)
	s.swing_method = clampi(int(cfg.get_value(GAME_SECTION, "swing_method", s.swing_method)), 0, 1)
	s.swing_help = bool(cfg.get_value(GAME_SECTION, "swing_help", s.swing_help))
	s.putting_grid = clampi(int(cfg.get_value(GAME_SECTION, "putting_grid", s.putting_grid)), 0, PUTTING_GRID_NAMES.size() - 1)
	s.breakline = bool(cfg.get_value(GAME_SECTION, "breakline", s.breakline))
	s.putting_assistant = bool(cfg.get_value(GAME_SECTION, "putting_assistant", s.putting_assistant))
	s.caddie = bool(cfg.get_value(GAME_SECTION, "caddie", s.caddie))
	s.true_size_ball = bool(cfg.get_value(GAME_SECTION, "true_size_ball", s.true_size_ball))
	s.buggy = bool(cfg.get_value(GAME_SECTION, "buggy", s.buggy))
	if force_look >= 0:
		s.apply_look(force_look)
		return s
	if not cfg.has_section_key(SECTION, "look"):
		# First run, or settings from before the looks: pick for the device.
		s.apply_look(detect_look())
		return s
	s.look = clampi(int(cfg.get_value(SECTION, "look", s.look)), Look.PHOTOREAL, Look.CUSTOM)
	s.lighting = clampi(int(cfg.get_value(SECTION, "lighting", s.lighting)), Lighting.CLASSIC, Lighting.PHOTOREAL)
	s.upscaler = clampi(int(cfg.get_value(SECTION, "upscaler", s.upscaler)), Upscaler.OFF, Upscaler.FSR2)
	s.dynamic_res = clampi(int(cfg.get_value(SECTION, "dynamic_res", s.dynamic_res)), 0, DYNAMIC_FPS.size() - 1)
	s.sharpen = clampi(int(cfg.get_value(SECTION, "sharpen", s.sharpen)), 0, 3)
	s.bloom = clampi(int(cfg.get_value(SECTION, "bloom", s.bloom)), 0, 3)
	s.vignette = clampi(int(cfg.get_value(SECTION, "vignette", s.vignette)), 0, 3)
	s.grain = clampi(int(cfg.get_value(SECTION, "grain", s.grain)), 0, 3)
	s.grade = clampi(int(cfg.get_value(SECTION, "grade", s.grade)), Grade.NEUTRAL, Grade.FILM)
	s.ssao = bool(cfg.get_value(SECTION, "ssao", s.ssao))
	s.dof = bool(cfg.get_value(SECTION, "dof", s.dof))
	s.grass = clampi(int(cfg.get_value(SECTION, "grass", s.grass)), 0, 3)
	s.foliage_wind = bool(cfg.get_value(SECTION, "foliage_wind", s.foliage_wind))
	s.cloud_shadows = bool(cfg.get_value(SECTION, "cloud_shadows", s.cloud_shadows))
	s.trees = clampi(int(cfg.get_value(SECTION, "trees", s.trees)), 0, TREE_NAMES.size() - 1)
	return s


func save(path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections; a missing file is fine
	cfg.set_value(SECTION, "quality", quality)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "msaa", msaa)
	cfg.set_value(SECTION, "render_scale", render_scale)
	cfg.set_value(SECTION, "fov", fov)
	cfg.set_value(GAME_SECTION, "wind", wind)
	cfg.set_value(GAME_SECTION, "presentation", presentation)
	cfg.set_value(GAME_SECTION, "web_disc_sounds", web_disc_sounds)
	cfg.set_value(GAME_SECTION, "skill", skill)
	cfg.set_value(GAME_SECTION, "green_firmness", green_firmness)
	cfg.set_value(GAME_SECTION, "green_speed", green_speed)
	cfg.set_value(GAME_SECTION, "swing_method", swing_method)
	cfg.set_value(GAME_SECTION, "swing_help", swing_help)
	cfg.set_value(GAME_SECTION, "putting_grid", putting_grid)
	cfg.set_value(GAME_SECTION, "breakline", breakline)
	cfg.set_value(GAME_SECTION, "putting_assistant", putting_assistant)
	cfg.set_value(GAME_SECTION, "caddie", caddie)
	cfg.set_value(GAME_SECTION, "true_size_ball", true_size_ball)
	cfg.set_value(GAME_SECTION, "buggy", buggy)
	for key in ["look", "lighting", "upscaler", "dynamic_res", "sharpen", "bloom", "vignette", "grain", "grade", "ssao", "dof", "grass", "foliage_wind", "cloud_shadows", "trees"]:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(path)
	if err != OK:
		push_warning("Could not save graphics settings to %s (error %d)" % [path, err])


## True on the Forward+ renderer (desktop), which supports SSAO and the other
## screen-space effects. The web build uses Compatibility.
func broadcast() -> bool:
	return presentation != Presentation.CLASSIC


## The tour graphics package on top of the Broadcast presentation.
func tour() -> bool:
	return presentation == Presentation.TOUR


## Whether the disc's crowd, menu and voice sounds are used: always on the
## desktop, and on the web when the player has turned "Disc sounds" on.
static func disc_sounds() -> bool:
	return not OS.has_feature("web") or load_saved().web_disc_sounds


static func is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


func shadow_distance() -> float:
	return [150.0, 250.0, 400.0, 600.0][quality]


func shadow_atlas_size() -> int:
	return [2048, 4096, 4096, 8192][quality]


func soft_shadow_quality() -> RenderingServer.ShadowQuality:
	match quality:
		Quality.LOW:
			return RenderingServer.SHADOW_QUALITY_HARD
		Quality.MEDIUM:
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		Quality.HIGH:
			return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	return RenderingServer.SHADOW_QUALITY_SOFT_HIGH


## Applies the settings that belong to the window and the renderer.
func apply_display(viewport: Viewport) -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match msaa:
		2:
			viewport.msaa_3d = Viewport.MSAA_2X
		4:
			viewport.msaa_3d = Viewport.MSAA_4X
		8:
			viewport.msaa_3d = Viewport.MSAA_8X
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
	var fsr2 := is_forward_plus() and upscaler == Upscaler.FSR2
	# FXAA is cheap and softens the edges MSAA would otherwise catch. FSR 2
	# does its own (temporal) anti-aliasing, even at full resolution.
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if msaa == 0 and not fsr2 and quality >= Quality.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
	if fsr2:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	# The FSR upscalers need Forward+; the browser's renderer stretches.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if is_forward_plus():
		match upscaler:
			Upscaler.FSR1:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			Upscaler.FSR2:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		viewport.fsr_sharpness = 0.3
	viewport.scaling_3d_scale = render_scale
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft_shadow_quality())


## The frame rate dynamic resolution keeps to, or 0 for off.
func target_fps() -> int:
	return DYNAMIC_FPS[dynamic_res]
