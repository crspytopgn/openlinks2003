// One soft ellipse of the baked ground shade (GroundShade): multiplied
// into a white map, R for the sun shadow and G for occlusion.
// INSTANCE_CUSTOM.rg: how dark each gets at the middle.
shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

varying vec2 dark;

void vertex() {
	dark = INSTANCE_CUSTOM.rg;
}

void fragment() {
	float a = 1.0 - smoothstep(0.3, 1.0, length(UV * 2.0 - 1.0));
	ALBEDO = vec3(1.0 - a * dark.r, 1.0 - a * dark.g, 1.0);
}
