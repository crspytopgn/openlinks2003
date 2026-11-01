extends RefCounted
## The game options the launcher offers before starting, read from and
## written to the game's own user://settings.cfg (Paths.game_settings()).
##
## Most are the game's own keys, written as the game writes them
## (game/scripts/graphics/graphics_settings.gd). The look preset and the
## quality are left under [launcher] instead, because a preset sets a dozen
## options that only the game knows: it applies them at its next start
## (GraphicsSettings.apply_launcher_requests). Volumes are under [audio]
## (game/scripts/audio/audio_settings.gd).

const Paths := preload("res://scripts/paths.gd")

## The game's GraphicsSettings.Look order; Custom is shown, not offered.
const LOOKS := ["Photoreal", "Natural", "Cinematic", "Classic Links", "Performance"]
const LOOK_HINTS := [
	"Ultra quality, photographic light, FSR 2. For a strong graphics card.",
	"High quality with photographic light. A good all-rounder.",
	"Photoreal with a film grade, bloom and grain.",
	"Links 2003's own look: flat light and the course's own trees.",
	"Lean and fast for laptops and older computers.",
]
const LOOK_CUSTOM := 5
## The quality each look sets on desktop (GraphicsSettings.apply_look).
const LOOK_QUALITY := [3, 2, 3, 2, 0]
const QUALITIES := ["Low", "Medium", "High", "Ultra"]
const DISPLAY_MODES := ["Window", "Borderless fullscreen", "Exclusive fullscreen"]
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const RENDER_SCALES := [0.5, 0.75, 1.0, 1.25, 1.5]
const UI_SCALES := ["Smaller", "Normal", "Larger", "Largest"]
const PRESENTATIONS := ["Classic Links", "Broadcast", "Tour"]
const SWINGS := ["Three-click meter", "PowerStroke (mouse)"]
const SKILLS := ["Level 1 (forgiving)", "Level 2", "Level 3", "Level 4 (Links 2003's hardest)"]

## The values as the game stores them. look/quality are what the game has
## now; pending_look/pending_quality are the launcher's requests (-1: none).
var look := -1
var quality := 2
var pending_look := -1
var pending_quality := -1
var fullscreen := false
var display_mode := 0  ## the game's DisplayMode: 0 borderless, 1 exclusive
var window_size := Vector2i.ZERO
var vsync := true
var render_scale := 1.0
var ui_scale := 1
var master := 100
var music := 100
var presentation := 1
var swing_method := 1
var swing_help := false
var skill := 3
var launch_monitor := false
var folder := ""


static func load_from(path := Paths.game_settings()) -> RefCounted:
	var c: RefCounted = (load("res://scripts/game_config.gd") as GDScript).new()
	var cfg := ConfigFile.new()
	cfg.load(path)
	c.look = int(cfg.get_value("graphics", "look", -1))
	c.quality = clampi(int(cfg.get_value("graphics", "quality", 2)), 0, 3)
	c.pending_look = int(cfg.get_value("launcher", "look", -1))
	c.pending_quality = int(cfg.get_value("launcher", "quality", -1))
	c.fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
	c.display_mode = clampi(int(cfg.get_value("graphics", "display_mode", 0)), 0, 1)
	c.window_size = Vector2i(int(cfg.get_value("graphics", "window_width", 0)), int(cfg.get_value("graphics", "window_height", 0)))
	c.vsync = bool(cfg.get_value("graphics", "vsync", true))
	c.render_scale = float(cfg.get_value("graphics", "render_scale", 1.0))
	c.ui_scale = clampi(int(cfg.get_value("graphics", "ui_scale", 1)), 0, 3)
	c.master = clampi(int(cfg.get_value("audio", "master", 100)), 0, 100)
	c.music = clampi(int(cfg.get_value("audio", "music", 100)), 0, 100)
	c.presentation = clampi(int(cfg.get_value("game", "presentation", 1)), 0, 2)
	c.swing_method = clampi(int(cfg.get_value("game", "swing_method", 1)), 0, 1)
	c.swing_help = bool(cfg.get_value("game", "swing_help", false))
	c.skill = clampi(int(cfg.get_value("game", "skill", 3)), 0, 3)
	c.launch_monitor = bool(cfg.get_value("game", "launch_monitor", false))
	c.folder = str(cfg.get_value("game", "folder", ""))
	return c


## Writes the options back, keeping everything else in the file.
func save_to(path := Paths.game_settings()) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var cfg := ConfigFile.new()
	cfg.load(path)
	if pending_look >= 0:
		cfg.set_value("launcher", "look", pending_look)
	if pending_quality >= 0:
		cfg.set_value("launcher", "quality", pending_quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "display_mode", display_mode)
	cfg.set_value("graphics", "window_width", window_size.x)
	cfg.set_value("graphics", "window_height", window_size.y)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "ui_scale", ui_scale)
	cfg.set_value("audio", "master", master)
	cfg.set_value("audio", "music", music)
	cfg.set_value("game", "presentation", presentation)
	cfg.set_value("game", "swing_method", swing_method)
	cfg.set_value("game", "swing_help", swing_help)
	cfg.set_value("game", "skill", skill)
	cfg.set_value("game", "launch_monitor", launch_monitor)
	if not folder.is_empty():
		cfg.set_value("game", "folder", folder)
	return cfg.save(path)


## The look the game will use: a request if there is one, else its own.
func shown_look() -> int:
	return pending_look if pending_look >= 0 else look


func shown_quality() -> int:
	if pending_quality >= 0:
		return pending_quality
	if pending_look >= 0 and pending_look < LOOK_QUALITY.size():
		return LOOK_QUALITY[pending_look]
	return quality


## Picks a look preset; the quality follows it unless changed afterwards.
func choose_look(i: int) -> void:
	pending_look = i
	pending_quality = -1


## Picks a quality; the game then calls the look Custom if it differs.
func choose_quality(q: int) -> void:
	pending_quality = q


## Display as one choice: 0 window, 1 borderless, 2 exclusive.
func display_choice() -> int:
	return 0 if not fullscreen else 1 + display_mode


func set_display_choice(i: int) -> void:
	fullscreen = i > 0
	if i > 0:
		display_mode = i - 1
