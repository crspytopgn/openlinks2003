class_name FrostedGlass
extends ColorRect
## Frosted glass behind a Control's panels: the picture under each panel,
## blurred and dimmed a little, as the panels of current TV golf graphics
## and PGA Tour 2K25 are. The owner lists its panel rects (in its own
## coordinates) while it draws: begin(), add() for each, then commit().
##
## A child with show_behind_parent, so it draws under its owner's panels but
## over the 3D picture it blurs. One pass of a fixed tap pattern on the
## screen texture, so it works the same on Forward+ and Compatibility (which
## has no screen mipmaps); pixels outside every panel are discarded at once.

const MAX_PANELS := 24

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 rects[24];
uniform float alphas[24];
uniform int count = 0;
uniform float radius_px = 7.0;
uniform float dim = 0.82;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float a = 0.0;
	for (int i = 0; i < count; i++) {
		vec4 r = rects[i];
		if (local.x >= r.x && local.y >= r.y && local.x < r.x + r.z && local.y < r.y + r.w) {
			a = max(a, alphas[i]);
		}
	}
	if (a <= 0.0) {
		discard;
	}
	// Two rings of taps round the pixel: a soft blur in one pass.
	vec3 sum = texture(screen_tex, SCREEN_UV).rgb;
	float n = 1.0;
	for (int k = 0; k < 12; k++) {
		float ang = float(k) * 0.5236;
		vec2 dir = vec2(cos(ang), sin(ang));
		sum += texture(screen_tex, SCREEN_UV + dir * radius_px * 0.5 * SCREEN_PIXEL_SIZE).rgb;
		sum += texture(screen_tex, SCREEN_UV + dir.yx * radius_px * SCREEN_PIXEL_SIZE).rgb;
		n += 2.0;
	}
	vec3 c = sum / n;
	// A touch less colour and light, so white type reads on any background.
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, 0.75) * dim;
	COLOR = vec4(c, a);
}
"""

static var _shader: Shader

var _rects := PackedVector4Array()
var _alphas := PackedFloat32Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	color = Color.WHITE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	material = mat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Forgets the panels of the last frame.
func begin() -> void:
	_rects.clear()
	_alphas.clear()


## A panel at `r`, in the owner's coordinates, at `alpha` (for fades).
func add(r: Rect2, alpha := 1.0) -> void:
	if _rects.size() >= MAX_PANELS or alpha <= 0.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	_rects.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_alphas.append(clampf(alpha, 0.0, 1.0))


func panel_count() -> int:
	return _rects.size()


## Hands the panels to the shader.
func commit() -> void:
	var rects := _rects.duplicate()
	var alphas := _alphas.duplicate()
	rects.resize(MAX_PANELS)
	alphas.resize(MAX_PANELS)
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("rects", rects)
	mat.set_shader_parameter("alphas", alphas)
	mat.set_shader_parameter("count", _rects.size())
	visible = not _rects.is_empty()
