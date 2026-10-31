class_name PostProcess
extends CanvasLayer
## The ReShade-style look effects (sharpening, colour grading, vignette,
## film grain) as one full-screen pass over the 3D view, below the HUD.
## Hidden when every effect is off, so it costs nothing then. Bloom, SSAO and
## depth of field come from the renderer instead (Scenery, GolfRound).

const SHADER := preload("res://shaders/post_process.gdshader")

## Per Grade: exposure, contrast, saturation, white balance, shadow colour.
const GRADES := [
	[1.0, 1.0, 1.0, Color(1, 1, 1), Color(1, 1, 1)],
	[1.0, 1.08, 1.18, Color(1, 1, 1), Color(1, 1, 1)],
	[1.02, 1.04, 1.06, Color(1.05, 1.0, 0.92), Color(1.0, 0.96, 0.92)],
	[1.0, 1.03, 0.97, Color(0.94, 0.99, 1.06), Color(0.94, 0.98, 1.04)],
	[0.98, 1.1, 0.9, Color(1.03, 1.0, 0.95), Color(0.9, 0.98, 1.06)],
]

var _rect: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	name = "PostProcess"
	# Above the 3D view, below the HUD (CanvasLayers default to layer 1).
	layer = -1
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func apply(s: GraphicsSettings) -> void:
	var g: Array = GRADES[s.grade]
	_mat.set_shader_parameter("sharpen", GraphicsSettings.SHARPEN_LEVELS[s.sharpen])
	_mat.set_shader_parameter("exposure", g[0])
	_mat.set_shader_parameter("contrast", g[1])
	# Under ACES the sky fill light on Forward+ greys the greens a little,
	# while Compatibility (flat colour fill) comes out lurid: even them out.
	var photo := s.lighting == GraphicsSettings.Lighting.PHOTOREAL
	var balance := 1.0
	if photo:
		balance = 1.15 if GraphicsSettings.is_forward_plus() else 0.88
	_mat.set_shader_parameter("saturation", g[2] * balance)
	_mat.set_shader_parameter("tint", _vec(g[3]))
	_mat.set_shader_parameter("shadow_tint", _vec(g[4]))
	_mat.set_shader_parameter("vignette", GraphicsSettings.VIGNETTE_LEVELS[s.vignette])
	_mat.set_shader_parameter("grain", GraphicsSettings.GRAIN_LEVELS[s.grain])
	visible = photo or s.sharpen > 0 or s.vignette > 0 or s.grain > 0 or s.grade != GraphicsSettings.Grade.NEUTRAL


static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
