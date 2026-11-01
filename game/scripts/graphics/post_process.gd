class_name PostProcess
extends CanvasLayer
## The ReShade-style look effects (sharpening, colour grading, vignette,
## film grain) as one full-screen pass over the 3D view, below the HUD.
## Hidden when every effect is off, so it costs nothing then. Bloom, SSAO and
## depth of field come from the renderer instead (Scenery, GolfRound).

const SHADER := preload("res://shaders/post_process.gdshader")

## Per Grade: exposure, contrast, saturation, white balance, shadow colour.
## Neutral with Photoreal lighting uses PHOTO_NEUTRAL instead.
const GRADES := [
	[1.0, 1.0, 1.0, Color(1, 1, 1), Color(1, 1, 1)],
	[1.0, 1.08, 1.18, Color(1, 1, 1), Color(1, 1, 1)],
	[1.02, 1.04, 1.06, Color(1.05, 1.0, 0.92), Color(1.0, 0.96, 0.92)],
	[1.0, 1.03, 0.97, Color(0.94, 0.99, 1.06), Color(0.94, 0.98, 1.04)],
	[0.98, 1.1, 0.9, Color(1.03, 1.0, 0.95), Color(0.9, 0.98, 1.06)],
]

## Neutral grade under Photoreal lighting: AgX keeps highlights natural but
## greys colours and flattens contrast, so a filmic curve (deeper shadows,
## brighter highlights), colour put back, a touch of sun warmth in the
## highlights and sky blue in the shadows, as in camera footage of a sunny
## course.
const PHOTO_NEUTRAL := [1.0, 1.08, 1.12, Color(1.02, 1.0, 0.97), Color(0.95, 0.98, 1.04)]
const PHOTO_CURVE := 0.6

## Heat shimmer at 1080p, in pixels, for a 50 degree lens and a high sun
## (Photoreal only). A long lens magnifies it (RoundCamera.lens_factor).
const SHIMMER_PIXELS := 2.2

## The learned grade (docs/colour-grade.md): a lookup per light and
## renderer, fitted by tools/grade/fit_grade.py. Photoreal only.
const LUT_DIR := "res://grade/"
## How much of the learned grade shows.
const LUT_MIX := 1.0
## Off to see or measure the frame without the learned grade.
var grade_lut := true:
	set(v):
		grade_lut = v
		_mat.set_shader_parameter("lut_mix", LUT_MIX if v and _lut_ready else 0.0)
var _lut_ready := false

var _rect: ColorRect
var _mat: ShaderMaterial
var _shimmer := 0.0


func _init() -> void:
	name = "PostProcess"
	# Above the 3D view and the root canvas, below the HUD (CanvasLayers
	# default to layer 1).
	layer = 0
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func _ready() -> void:
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.offset_left = 0.0
	_rect.offset_top = 0.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0


## The size of the effect's rectangle, which should be the whole screen.
func covered_size() -> Vector2:
	return _rect.size


func apply(s: GraphicsSettings) -> void:
	var photo := s.lighting == GraphicsSettings.Lighting.PHOTOREAL
	var g: Array = PHOTO_NEUTRAL if photo and s.grade == GraphicsSettings.Grade.NEUTRAL else GRADES[s.grade]
	_mat.set_shader_parameter("curve", PHOTO_CURVE if photo else 0.0)
	_mat.set_shader_parameter("sharpen", GraphicsSettings.SHARPEN_LEVELS[s.sharpen])
	_mat.set_shader_parameter("exposure", g[0])
	_mat.set_shader_parameter("contrast", g[1])
	_mat.set_shader_parameter("saturation", g[2])
	_mat.set_shader_parameter("tint", _vec(g[3]))
	_mat.set_shader_parameter("shadow_tint", _vec(g[4]))
	_mat.set_shader_parameter("vignette", GraphicsSettings.VIGNETTE_LEVELS[s.vignette])
	_mat.set_shader_parameter("grain", GraphicsSettings.GRAIN_LEVELS[s.grain])
	var lut := lut_for(s.time_of_day, GraphicsSettings.is_forward_plus()) if photo else null
	_lut_ready = lut != null
	_mat.set_shader_parameter("grade_lut", lut)
	_mat.set_shader_parameter("lut_mix", LUT_MIX if _lut_ready and grade_lut else 0.0)
	_shimmer = SHIMMER_PIXELS if photo else 0.0
	if _shimmer == 0.0:
		_mat.set_shader_parameter("shimmer", 0.0)
	visible = photo or s.sharpen > 0 or s.vignette > 0 or s.grain > 0 or s.grade != GraphicsSettings.Grade.NEUTRAL


static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Each frame: where the level horizon sits on screen and how high the
## camera is, for the heat shimmer, which only shows far out; and how hot
## the day looks from the sun's height (none at dawn, full from about 45
## degrees up).
func update_view(camera: Camera3D, ground_y: float, sun: DirectionalLight3D) -> void:
	if _shimmer == 0.0 or camera == null or not visible:
		return
	var heat := 1.0
	if sun != null:
		var elevation := rad_to_deg(asin(clampf(sun.global_transform.basis.z.y, -1.0, 1.0)))
		heat = smoothstep(8.0, 45.0, elevation)
	var fov := deg_to_rad(camera.fov)
	var fwd := -camera.global_transform.basis.z
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))  # up is positive
	_mat.set_shader_parameter("shimmer", _shimmer * heat * RoundCamera.lens_factor(camera.fov))
	_mat.set_shader_parameter("horizon_y", horizon_screen_y(pitch, fov))
	_mat.set_shader_parameter("fov_radians", fov)
	_mat.set_shader_parameter("eye_height", maxf(camera.global_position.y - ground_y, 0.5))


## Screen y (0 top, 1 bottom) of the level horizon for a camera pitched
## `pitch` radians up, with vertical field of view `fov` radians.
static func horizon_screen_y(pitch: float, fov: float) -> float:
	return 0.5 + 0.5 * tan(pitch) / tan(fov * 0.5)


## The learned grade for a time of day, fitted to that light's renders
## (Forward+ and Compatibility light the course differently, so each has
## its own).
static func lut_for(time_of_day: int, forward_plus: bool) -> Texture2D:
	var light := "afternoon"  # also "Through the round"
	match time_of_day:
		GraphicsSettings.TimeOfDay.MORNING:
			light = "morning"
		GraphicsSettings.TimeOfDay.MIDDAY:
			light = "midday"
		GraphicsSettings.TimeOfDay.GOLDEN:
			light = "golden"
	var path := LUT_DIR + "%s_%s.png" % [light, "forward" if forward_plus else "compat"]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
