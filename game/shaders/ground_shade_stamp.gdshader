// One stamp of the baked ground shade (GroundShade): multiplied into a
// white map, R for the sun shadow and G for occlusion. A soft ellipse, or
// the course's own shadow shape for the tree type (from its .SHA file).
// INSTANCE_CUSTOM.rg: how dark each gets at the middle; .b: the shape's
// cell in the `shapes` atlas plus one (0 = ellipse).
shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D shapes : filter_linear_mipmap;
uniform vec2 shape_grid = vec2(1.0); // cells across and down the atlas

varying vec2 dark;
varying float cell;

void vertex() {
	dark = INSTANCE_CUSTOM.rg;
	cell = INSTANCE_CUSTOM.b - 1.0;
}

void fragment() {
	float a = 1.0 - smoothstep(0.3, 1.0, length(UV * 2.0 - 1.0));
	if (cell > -0.5) {
		float c = floor(cell + 0.5);
		vec2 at = vec2(mod(c, shape_grid.x), floor(c / shape_grid.x));
		// Keep half a texel off the cell's border so neighbours don't bleed.
		vec2 inside = clamp(UV, vec2(0.01), vec2(0.99));
		a = texture(shapes, (at + inside) / shape_grid).r;
	}
	ALBEDO = vec3(1.0 - a * dark.r, 1.0 - a * dark.g, 1.0);
}
