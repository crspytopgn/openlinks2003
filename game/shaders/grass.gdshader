// 3D grass tufts in the rough (GrassField). Each MultiMesh instance is one
// tuft of thin blades; INSTANCE_CUSTOM.rgb is the ground's colour under it
// (sRGB) and .a a random phase; UV2 per blade: x shade, y dryness (not COLOR: MultiMesh
// instances in Compatibility read it as white). Blades bend with the global wind and shrink
// away towards the edge of the grass radius, so there's no visible line
// where the 3D grass ends. Normals point straight up so the tufts take the
// same light as the ground they stand on. Works in Forward+ and
// Compatibility. No specular_disabled: in Compatibility it drops the sun
// from the blades and leaves them dark.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

global uniform vec2 wind_vector; // air velocity over the course, m/s (x, z)
uniform vec3 camera_pos;
uniform float fade_start = 20.0;
uniform float fade_end = 30.0;
uniform float brightness = 1.0; // GrassField lifts it for Compatibility
// How far blades a few metres out take the turf's tone (1 all the way).
// Forward+ keeps more of their own shading, since its sky fill and GI light
// each blade differently from the ground.
uniform float blend_amount = 1.0;
// Each blade tilts its normal its own way (0 lit flat like the ground).
uniform float blade_relief = 0.0;

#include "res://shaders/ground_shade.gdshaderinc"

varying vec3 base_color;
varying vec2 blade;
varying float height;
varying vec2 root_xz;
varying float blend;

void vertex() {
	// VERTEX and NORMAL are in world space here (world_vertex_coords).
	height = UV.y;
	blade = UV2;
	vec3 root = MODEL_MATRIX[3].xyz;
	root_xz = root.xz;
	float dist = distance(root.xz, camera_pos.xz);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	// From a few metres out, blades take the turf's own tone, so the rough
	// reads as one soft band rather than dark speckle on the ground.
	blend = smoothstep(4.0, fade_start, dist) * blend_amount;
	float phase = INSTANCE_CUSTOM.a * 6.2831;
	float gust = 0.6 + 0.4 * sin(TIME * 1.7 + phase + dot(root.xz, vec2(0.21, 0.17)));
	vec2 bend = wind_vector * 0.012 * gust + vec2(sin(TIME * 2.3 + phase), cos(TIME * 1.9 + phase)) * 0.015;
	VERTEX.xz += bend * height * height * length(MODEL_MATRIX[1].xyz);
	VERTEX.y = root.y + (VERTEX.y - root.y) * fade;
	NORMAL = vec3(0.0, 1.0, 0.0);
	vec3 c = INSTANCE_CUSTOM.rgb;
	base_color = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	// Each blade its own shade, a few dry and straw-coloured; dark down
	// in the tuft, where little light gets in, and sun-bleached at the tips.
	vec3 straw = vec3(dot(base_color, vec3(0.3, 0.6, 0.1))) * vec3(1.25, 1.1, 0.6);
	vec3 c = mix(base_color, straw, blade.y * 0.7) * mix(0.8, 1.15, blade.x);
	// Capped well below white: pale disc rough lifted for Compatibility
	// would otherwise pass the glow threshold and bloom into a white haze.
	vec3 near = c * mix(0.7, 1.22, smoothstep(0.0, 1.0, height)) * vec3(0.97, 1.03, 0.9);
	// Sun-bleached, slightly yellower tips catch the eye on top of the turf.
	near *= mix(vec3(1.0), vec3(1.18, 1.14, 0.9), smoothstep(0.6, 1.0, height) * blade_relief);
	vec3 far = base_color * mix(0.92, 1.05, blade.x);
	ALBEDO = min(mix(near, far, blend) * brightness, vec3(0.6))
		* ground_shading(root_xz, length(VERTEX));
	// Both faces lit like the ground: without this the back faces flip
	// their normal and go dark (Compatibility shows it most).
	float turn = blade.x * 6.2831;
	vec3 n = normalize(vec3(cos(turn) * blade_relief, 1.0, sin(turn) * blade_relief));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
