class_name Glass
extends RefCounted
## The game's glass look for menus and the HUD, our own take on the
## translucent "liquid glass" of current phone and TV interfaces: rounded
## continuous corners, the picture behind bent and blurred at the edges like
## thick glass, a lit rim along the top edge, and a dark tint so white type
## stays readable over bright sky and grass.
##
## The live blur and refraction need the screen texture every frame, so they
## run only on Forward+ (and Mobile) at Medium quality and up. The web and
## Compatibility builds, and Low quality, draw the same shapes as plain
## tinted glass with a light rim: no extra pass at all.

## The tint over the blurred picture (blur on) or alone (blur off), and how
## much of it shows.
const TINT := Color(0.07, 0.09, 0.1)
const TINT_ALPHA_BLUR := 0.42
const TINT_ALPHA_FLAT := 0.74
const RIM := Color(1, 1, 1, 0.22)
const RADIUS := 22
const SHADOW := Color(0, 0, 0, 0.28)

## Turned off by Low quality (GraphicsSettings.apply_display).
static var allow_blur := true

## One shared shader; each glass shape has its own material for its size.
static var _shader: Shader

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 box_size = vec2(100.0);
uniform float radius = 22.0;
uniform float bevel_px = 16.0;   // how far in from the edge the glass bends
uniform float bend_px = 10.0;    // how far the picture shifts at the very edge
uniform float blur_px = 9.0;
uniform float saturation = 1.2;  // glass keeps colours lively under the tint
uniform float rim_strength = 0.55;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = box_size * 0.5;
	vec2 p = local - half_size;
	float r = min(radius, min(half_size.x, half_size.y));
	float d = box_sdf(p, half_size, r);
	float alpha = clamp(0.5 - d, 0.0, 1.0);
	if (alpha <= 0.0) {
		discard;
	}
	// The outward normal of the edge, from the distance field's slope.
	vec2 e = vec2(1.0, 0.0);
	vec2 n = vec2(box_sdf(p + e.xy, half_size, r) - box_sdf(p - e.xy, half_size, r),
			box_sdf(p + e.yx, half_size, r) - box_sdf(p - e.yx, half_size, r));
	n = length(n) > 0.0001 ? normalize(n) : vec2(0.0, -1.0);
	float inside = clamp(-d / bevel_px, 0.0, 1.0);
	float bend = (1.0 - inside) * (1.0 - inside);
	// Thick glass: towards the rim the picture is pulled in from further out.
	vec2 uv = SCREEN_UV - n * bend * bend_px * SCREEN_PIXEL_SIZE;
	vec3 sum = texture(screen_tex, uv).rgb;
	float count = 1.0;
	for (int k = 0; k < 10; k++) {
		float a = float(k) * 0.6283 + 0.3;
		vec2 dir = vec2(cos(a), sin(a));
		sum += texture(screen_tex, uv + dir * blur_px * 0.5 * SCREEN_PIXEL_SIZE).rgb;
		sum += texture(screen_tex, uv + dir.yx * blur_px * SCREEN_PIXEL_SIZE).rgb;
		count += 2.0;
	}
	vec3 c = sum / count;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	// A lit rim, brightest where it faces the light (above, a little left),
	// and a faint sheen just inside the top edge.
	float rim = 1.0 - smoothstep(0.0, 1.8, -d);
	float facing = 0.35 + 0.65 * max(dot(n, normalize(vec2(-0.45, -1.0))), 0.0);
	c += vec3(rim * facing * rim_strength);
	c += vec3(bend * max(-n.y, 0.0) * 0.08);
	COLOR = vec4(c, alpha);
}
"""


## Whether glass blurs the picture behind it here and now.
static func blurs() -> bool:
	if not allow_blur:
		return false
	return RenderingServer.get_current_rendering_method() != "gl_compatibility" and not OS.has_feature("web")


## The panel's own style: the tint, a light rim and a soft shadow, rounded.
## Over a blur the tint is lighter, so the glass shows through.
static func panel_style(radius := RADIUS, margin := 18.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(TINT, TINT_ALPHA_BLUR if blurs() else TINT_ALPHA_FLAT)
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.set_content_margin_all(margin)
	s.border_color = Color(RIM, 0.0 if blurs() else RIM.a)
	s.set_border_width_all(1)
	s.shadow_color = SHADOW
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	s.anti_aliasing = true
	return s


## Puts `c` on glass: its panel style (for a PanelContainer or Panel) and,
## where glass blurs, the bent and blurred picture behind it.
static func apply(c: Control, radius := RADIUS, margin := 18.0) -> void:
	c.add_theme_stylebox_override("panel", panel_style(radius, margin))
	if blurs():
		backdrop(c, radius)


## The blurred, bent picture behind `c` (drawn behind it and its children,
## sized to it), without a node of its own, so containers don't lay it out.
static func backdrop(c: Control, radius := RADIUS) -> void:
	if c.has_meta(&"glass_backdrop"):
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("radius", float(radius))
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, c.get_canvas_item())
	RenderingServer.canvas_item_set_draw_behind_parent(item, true)
	RenderingServer.canvas_item_set_material(item, mat.get_rid())
	c.set_meta(&"glass_backdrop", [item, mat])
	var redraw := func() -> void:
		RenderingServer.canvas_item_clear(item)
		mat.set_shader_parameter("box_size", c.size)
		RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, c.size), Color.WHITE)
	c.resized.connect(redraw)
	redraw.call()
	# Freed with the control; a control only taken out of the tree keeps it.
	c.tree_exiting.connect(func() -> void:
		if c.is_queued_for_deletion() and c.has_meta(&"glass_backdrop"):
			RenderingServer.free_rid(item)
			c.remove_meta(&"glass_backdrop"))


## A spring for things sliding or popping in: 0 at u = 0, overshooting a
## little past 1, settled at 1 by u = 1.
static func spring(u: float) -> float:
	if u <= 0.0:
		return 0.0
	if u >= 1.0:
		return 1.0
	return 1.0 - exp(-6.0 * u) * cos(9.0 * u) * (1.0 - u * u * u)
