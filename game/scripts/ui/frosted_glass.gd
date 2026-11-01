class_name FrostedGlass
extends ColorRect
## Glass behind a Control's panels (the HUD's side of Glass): the picture
## under each rounded panel bent at its edges, blurred, with a lit rim. The
## owner lists its panel rects (in its own coordinates) while it draws:
## begin(), add() for each, then commit().
##
## A child with show_behind_parent, so it draws under its owner's panels but
## over the 3D picture it blurs. One pass of a fixed tap pattern on the
## screen texture; pixels outside every panel are discarded. Only where
## Glass.blurs(): elsewhere (the web, Compatibility, Low quality) it stays
## hidden and the owner draws plain tinted glass.

const MAX_PANELS := 24

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 rects[24];
uniform vec4 radii[24];  // top-left, top-right, bottom-right, bottom-left
uniform float alphas[24];
uniform int count = 0;
uniform float blur_px = 8.0;
uniform float bevel_px = 12.0;
uniform float bend_px = 7.0;
uniform float saturation = 1.2;
uniform float rim_strength = 0.5;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

// Signed distance to a box with its own radius at each corner.
float box_sdf(vec2 p, vec2 half_size, vec4 r4) {
	float r = p.x < 0.0 ? (p.y < 0.0 ? r4.x : r4.w) : (p.y < 0.0 ? r4.y : r4.z);
	r = min(r, min(half_size.x, half_size.y));
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float rect_sdf(vec2 at, int i) {
	vec4 r = rects[i];
	vec2 half_size = r.zw * 0.5;
	return box_sdf(at - r.xy - half_size, half_size, radii[i]);
}

void fragment() {
	int best = -1;
	float d = 1e6;
	for (int i = 0; i < count; i++) {
		float di = rect_sdf(local, i);
		if (di < d) {
			d = di;
			best = i;
		}
	}
	float alpha = best >= 0 ? clamp(0.5 - d, 0.0, 1.0) * alphas[best] : 0.0;
	if (alpha <= 0.0) {
		discard;
	}
	vec2 e = vec2(1.0, 0.0);
	vec2 n = vec2(rect_sdf(local + e.xy, best) - rect_sdf(local - e.xy, best),
			rect_sdf(local + e.yx, best) - rect_sdf(local - e.yx, best));
	n = length(n) > 0.0001 ? normalize(n) : vec2(0.0, -1.0);
	float inside = clamp(-d / bevel_px, 0.0, 1.0);
	float bend = (1.0 - inside) * (1.0 - inside);
	vec2 uv = SCREEN_UV - n * bend * bend_px * SCREEN_PIXEL_SIZE;
	vec3 sum = texture(screen_tex, uv).rgb;
	float k_count = 1.0;
	for (int k = 0; k < 10; k++) {
		float a = float(k) * 0.6283 + 0.3;
		vec2 dir = vec2(cos(a), sin(a));
		sum += texture(screen_tex, uv + dir * blur_px * 0.5 * SCREEN_PIXEL_SIZE).rgb;
		sum += texture(screen_tex, uv + dir.yx * blur_px * SCREEN_PIXEL_SIZE).rgb;
		k_count += 2.0;
	}
	vec3 c = sum / k_count;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	float rim = 1.0 - smoothstep(0.0, 1.6, -d);
	float facing = 0.35 + 0.65 * max(dot(n, normalize(vec2(-0.45, -1.0))), 0.0);
	c += vec3(rim * facing * rim_strength);
	c += vec3(bend * max(-n.y, 0.0) * 0.06);
	COLOR = vec4(c, alpha);
}
"""

static var _shader: Shader

var _rects := PackedVector4Array()
var _alphas := PackedFloat32Array()
var _radii := PackedVector4Array()


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
	_radii.clear()


## A panel at `r`, in the owner's coordinates, at `alpha` (for fades), with
## `corners` the radius of each corner (top-left, top-right, bottom-right,
## bottom-left).
func add(r: Rect2, alpha := 1.0, corners := Vector4.ZERO) -> void:
	if _rects.size() >= MAX_PANELS or alpha <= 0.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	_rects.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_alphas.append(clampf(alpha, 0.0, 1.0))
	_radii.append(corners)


func panel_count() -> int:
	return _rects.size()


## Hands the panels to the shader.
func commit() -> void:
	var rects := _rects.duplicate()
	var alphas := _alphas.duplicate()
	var radii := _radii.duplicate()
	rects.resize(MAX_PANELS)
	alphas.resize(MAX_PANELS)
	radii.resize(MAX_PANELS)
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("rects", rects)
	mat.set_shader_parameter("alphas", alphas)
	mat.set_shader_parameter("radii", radii)
	mat.set_shader_parameter("count", _rects.size())
	visible = not _rects.is_empty() and Glass.blurs()
