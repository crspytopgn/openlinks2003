extends PanelContainer
## Frosted glass behind a panel: the picture under it blurred, lifted a
## little and tinted, inside a rounded corner, with a bright rim that catches
## the light along the top edge. One pass over the screen texture, so it
## works the same in the Compatibility renderer (no screen mipmaps).

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 rect_size = vec2(100.0);
uniform float radius = 26.0;
uniform float blur_px = 22.0;
uniform vec4 tint : source_color = vec4(0.16, 0.17, 0.18, 0.42);
uniform float rim = 0.5;
uniform float lift = 0.04;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float rounded(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - (half_size - vec2(r));
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	float d = rounded(local - half_size, half_size, radius);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	if (inside <= 0.0) {
		discard;
	}
	vec3 c = vec3(0.0);
	float w = 0.0;
	vec2 step_uv = SCREEN_PIXEL_SIZE * blur_px / 3.0;
	for (int i = -3; i <= 3; i++) {
		for (int j = -3; j <= 3; j++) {
			vec2 o = vec2(float(i), float(j));
			float k = exp(-dot(o, o) * 0.18);
			c += texture(screen_tex, SCREEN_UV + o * step_uv).rgb * k;
			w += k;
		}
	}
	c /= w;
	c = mix(c, tint.rgb, tint.a) + vec3(lift);
	// A soft sheen down from the top, and the rim: bright along the top
	// edge, faint round the sides and bottom.
	float y = local.y / max(rect_size.y, 1.0);
	c += vec3(0.04) * smoothstep(0.2, 0.0, y);
	float edge = clamp(1.0 - abs(d + 0.8) / 1.1, 0.0, 1.0);
	float light = mix(0.25, 1.0, smoothstep(0.5, 0.0, y));
	c += vec3(rim * light) * edge;
	COLOR = vec4(c, inside);
}
"""

var radius := 26.0:
	set(v):
		radius = v
		_update()
var tint := Color(0.16, 0.17, 0.18, 0.42):
	set(v):
		tint = v
		_update()
var _mat: ShaderMaterial


func _init(corner := 26.0, margin := 22.0) -> void:
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	radius = corner
	var s := StyleBoxEmpty.new()
	s.set_content_margin_all(margin)
	add_theme_stylebox_override("panel", s)
	resized.connect(_update)
	_update()


func _update() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", minf(radius, minf(size.x, size.y) * 0.5))
	_mat.set_shader_parameter("tint", tint)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
