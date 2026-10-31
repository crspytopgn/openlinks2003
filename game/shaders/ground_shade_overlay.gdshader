// The baked ground shade (GroundShade) for ground drawn with a standard
// material (the disc courses' terrain): a next pass over the same mesh,
// lifted 2 cm towards the sky, that darkens the lit colour: black, with
// the shade as alpha (blend_mul darkens everything in Compatibility).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://shaders/ground_shade.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(0.0, 0.02, 0.0);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	// Fogged far ground keeps its colour.
	float shade = mix(ground_shading(world_pos.xz, dist), 1.0, smoothstep(500.0, 1200.0, dist));
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - shade;
}
