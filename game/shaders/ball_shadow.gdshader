// The soft contact shadow under the ball (main.gd). A golf ball is too
// small for the sun's shadow maps at any distance, so without this it seems
// to float; with it the ball sits in the grass. `strength` fades it as the
// ball climbs. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float strength = 0.6;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.15, 1.0, r)) * (1.0 - smoothstep(0.15, 1.0, r));
}
