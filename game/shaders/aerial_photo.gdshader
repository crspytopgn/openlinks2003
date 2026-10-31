shader_type spatial;
// The course designer's aerial photo, laid over the ground from above
// (docs/real-courses.md). The photo is north-up: its left edge is the
// course area's high x (+x is west) and its top edge the area's high z.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D photo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 area = vec4(-500.0, -500.0, 1000.0, 1000.0); // x, z, width, depth
uniform float opacity : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2((area.x + area.z - world_pos.x) / area.z, (area.y + area.w - world_pos.z) / area.w);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	ALBEDO = texture(photo, uv).rgb;
	ALPHA = opacity * inside;
}
