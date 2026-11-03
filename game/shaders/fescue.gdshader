// Tall fescue on the hills (FescueField): out-of-play deep rough grown as
// tufts of fine grey-green grass 40 to 75 cm tall with pale seed heads
// standing above it, from the fescue atlas (tools/grass/fescue_atlas.py). Each
// instance is three crossed cards; INSTANCE_CUSTOM.rgb is the ground's
// colour under it (sRGB) and .a picks the tuft and the sway phase. Fades in
// past the near 3D tufts (so a ball in the rough by the camera stays in
// view) and sinks into the ground towards the far edge. Normals point up
// so the tufts take the ground's light. Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 camera_pos;
uniform float near_start = 15.0;
uniform float near_end = 45.0;
uniform float far_start = 120.0;
uniform float far_end = 160.0;
uniform float brightness = 1.0;
global uniform vec2 wind_vector;

#include "res://shaders/ground_shade.gdshaderinc"

varying vec3 base_color;
varying vec2 root_xz;
varying flat float cell;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	root_xz = root.xz;
	float dist = distance(root.xz, camera_pos.xz);
	float grow = smoothstep(near_start, near_end, dist) * (1.0 - smoothstep(far_start, far_end, dist));
	float phase = INSTANCE_CUSTOM.a * 37.7;
	float gust = 0.6 + 0.4 * sin(TIME * 1.3 + phase + dot(root.xz, vec2(0.13, 0.11)));
	float up = 1.0 - UV.y; // 0 at the root, 1 at the top of the card
	vec2 bend = wind_vector * 0.02 * gust + vec2(sin(TIME * 1.7 + phase), cos(TIME * 1.4 + phase)) * 0.03;
	VERTEX.xz += bend * up * up * length(MODEL_MATRIX[1].xyz);
	VERTEX.y = root.y + (VERTEX.y - root.y) * grow;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vec3 c = INSTANCE_CUSTOM.rgb;
	base_color = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	cell = floor(fract(INSTANCE_CUSTOM.a * 4.0) * 4.0);
}

void fragment() {
	vec2 uv = (vec2(mod(cell, 2.0), floor(cell / 2.0)) + clamp(UV, vec2(0.004), vec2(0.996))) * 0.5;
	vec4 t = texture(atlas, uv);
	// Smaller mips thin the blades out under the alpha test: hold them up a
	// little, but not so much that a far tuft closes into a solid blob.
	vec2 texels = vec2(textureSize(atlas, 0)) * 0.5;
	float lod = log2(max(max(length(dFdx(UV) * texels), length(dFdy(UV) * texels)), 1.0));
	if (t.a * (1.0 + lod * 0.07) < 0.5) {
		discard;
	}
	// The blades' own grey-green and straw, pulled towards the ground's
	// colour, so a hillside of fescue sits on its rough rather than pasted
	// on; further off (higher mips) more of the ground's, as the thin
	// blades and the grass between them blur into one.
	float far = clamp(lod / 4.0, 0.0, 1.0);
	vec3 c = mix(t.rgb * 0.85, base_color * 1.05, mix(0.4, 0.65, far)) * vec3(1.04, 1.0, 0.9);
	// Each tuft a little lighter or darker, greener or drier, so a slope is
	// patchy as real long grass is.
	float v = fract(cell * 0.37 + root_xz.x * 0.173 + root_xz.y * 0.291);
	c *= mix(0.8, 1.08, v) * mix(vec3(1.0), vec3(1.05, 1.02, 0.9), step(0.75, v));
	vec3 albedo = min(c * brightness, vec3(0.7));
	ALBEDO = albedo * shade_fill.a * ground_shading(root_xz, length(VERTEX));
	EMISSION = albedo * shade_fill.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
