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
varying float height_up;
varying float distant; // 0 near, 1 far off, where a tuft is a few pixels
// A far tuft's brightness against a near one's, and the colour a bank of
// long grass reads at a distance (linear; dry olive, as the deep rough's
// photo texture reads on screen): far tufts sit on their ground rather
// than standing out from it. FescueField sets the gain per renderer.
uniform float far_gain = 0.75;
uniform vec3 far_bank = vec3(0.15, 0.17, 0.13);
// FescueField.NORMAL_LEAN.
const float NORMAL_LEAN = 0.01;
// How much wider a tuft grows towards the far edge.
const float SPREAD_FAR = 2.6;
// Metres over which a tuft takes on the far look.
const float DISTANT_START = 25.0;
const float DISTANT_END = 90.0;
varying flat float cell;
varying vec3 ground_normal; // world space, from the card's lean (FescueField.NORMAL_LEAN)

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	root_xz = root.xz;
	float dist = distance(root.xz, camera_pos.xz);
	float grow = smoothstep(near_start, near_end, dist) * (1.0 - smoothstep(far_start, far_end, dist));
	float phase = INSTANCE_CUSTOM.a * 37.7;
	float gust = 0.6 + 0.4 * sin(TIME * 1.3 + phase + dot(root.xz, vec2(0.13, 0.11)));
	float up = 1.0 - UV.y; // 0 at the root, 1 at the top of the card
	height_up = up;
	distant = smoothstep(DISTANT_START, DISTANT_END, dist);
	vec2 bend = wind_vector * 0.02 * gust + vec2(sin(TIME * 1.7 + phase), cos(TIME * 1.4 + phase)) * 0.03;
	VERTEX.xz += bend * up * up * length(MODEL_MATRIX[1].xyz);
	// Further off the tufts spread wider, so they close up into a bank
	// instead of standing apart as clumps with bare ground between them.
	VERTEX.xz = root.xz + (VERTEX.xz - root.xz) * mix(1.0, SPREAD_FAR, smoothstep(near_end, far_start, dist));
	VERTEX.y = root.y + (VERTEX.y - root.y) * grow;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vec2 lean = MODEL_MATRIX[1].xz / max(MODEL_MATRIX[1].y * NORMAL_LEAN, 1e-5);
	ground_normal = vec3(lean.x, sqrt(max(1.0 - dot(lean, lean), 0.0)), lean.y);
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
	if (t.a * (1.0 + lod * 0.04) < 0.5) {
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
	// Far off, where a tuft is a few pixels, it takes the ground's hue and
	// a little under its own brightness, so the bank reads as one soft
	// texture rather than separate bright blobs: from the tee a hillside
	// of fescue read as yellow polka dots on darker ground.
	float luma_c = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 bank = mix(base_color, far_bank, 0.85);
	vec3 hue = bank / max(dot(bank, vec3(0.2126, 0.7152, 0.0722)), 0.001);
	c = mix(c, hue * luma_c * far_gain * mix(0.9, 1.1, v), distant);
	// A bank of long grass is dark inside: the blades shade each other, so
	// only the upper blades and seed heads catch the sun.
	c *= mix(mix(0.6, 1.15, smoothstep(0.0, 0.85, height_up)), mix(0.8, 1.15, height_up), distant);
	vec3 albedo = min(c * brightness, vec3(0.7));
	ALBEDO = albedo * shade_fill.a * ground_shading(root_xz, length(VERTEX));
	EMISSION = albedo * shade_fill.rgb;
	// Lit as the slope under it is lit, so a sunlit or shaded bank keeps
	// its tufts the ground's brightness; near, half way to straight up.
	vec3 n = normalize(mix(vec3(0.0, 1.0, 0.0), ground_normal, mix(0.5, 1.0, distant)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
