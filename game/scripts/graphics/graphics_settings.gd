class_name GraphicsSettings
extends RefCounted
## Display and quality settings, saved to user://settings.cfg under
## [graphics], plus the wind strength under [game]. Other sections of that
## file (such as the game folder) are left alone.

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const GAME_SECTION := "game"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const MSAA_CHOICES := [0, 2, 4, 8]
const RENDER_SCALES := [0.5, 0.75, 1.0, 1.25, 1.5]

var quality: int = Quality.HIGH
var fullscreen := false
var vsync := true
var msaa := 2  ## samples: 0, 2, 4 or 8
var render_scale := 1.0  ## 3D resolution relative to the window
var fov := 60.0  ## vertical field of view, degrees
var wind: int = Wind.Level.MODERATE


func _init() -> void:
	# The browser build runs on everything from phones to desktops, on the
	# simpler renderer, so it starts a notch lower.
	if OS.has_feature("web"):
		quality = Quality.MEDIUM
		msaa = 0


static func load_saved(path := PATH) -> GraphicsSettings:
	var s := GraphicsSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.quality = clampi(int(cfg.get_value(SECTION, "quality", s.quality)), Quality.LOW, Quality.ULTRA)
	s.fullscreen = bool(cfg.get_value(SECTION, "fullscreen", s.fullscreen))
	s.vsync = bool(cfg.get_value(SECTION, "vsync", s.vsync))
	var samples := int(cfg.get_value(SECTION, "msaa", s.msaa))
	s.msaa = samples if MSAA_CHOICES.has(samples) else s.msaa
	s.render_scale = clampf(float(cfg.get_value(SECTION, "render_scale", s.render_scale)), 0.25, 2.0)
	s.fov = clampf(float(cfg.get_value(SECTION, "fov", s.fov)), 40.0, 90.0)
	s.wind = clampi(int(cfg.get_value(GAME_SECTION, "wind", s.wind)), Wind.Level.OFF, Wind.Level.STRONG)
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
	var err := cfg.save(path)
	if err != OK:
		push_warning("Could not save graphics settings to %s (error %d)" % [path, err])


## True on the Forward+ renderer (desktop), which supports SSAO and the other
## screen-space effects. The web build uses Compatibility.
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
	# FXAA is cheap and softens the edges MSAA would otherwise catch.
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if msaa == 0 and quality >= Quality.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_scale = render_scale
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft_shadow_quality())
