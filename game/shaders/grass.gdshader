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
// Below 1 greys the blades towards their own luminance: the Compatibility
// lift above also lifts the colour, which read as acid yellow-green.
uniform float saturation = 1.0;
// How far blades a few metres out take the turf's tone (1 all the way).
// Forward+ keeps more of their own shading, since its sky fill and GI light
// each blade differently from the ground.
uniform float blend_amount = 1.0;
// Each blade tilts its normal its own way (0 lit flat like the ground).
uniform float blade_relief = 0.0;
// Brightness of the blade tips against the roots (1 = none). The mown fur
// (GrassField.mown_material) lifts its tips so the sunlit tops of a fresh
// cut read over the darker turf texture below them.
uniform float tip_light = 1.0;

#include "res://shaders/ground_shade.gdshaderinc"
#include "res://shaders/turf_tone.gdshaderinc"

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
	// Each blade its own shade, a few dry and straw-coloured. Real rough
	// is darkest down in the tuft, where the blades shade each other, and
	// its tips are a deeper, cooler green than the mown turf beside it
	// (they're older leaf, and seen edge-on): a dense, dark fur that
	// blends into the ground rather than bright tips stuck on top of it.
	vec3 straw = vec3(dot(base_color, vec3(0.3, 0.6, 0.1))) * vec3(1.2, 1.08, 0.7);
	vec3 c = mix(base_color, straw, blade.y * 0.45) * mix(0.82, 1.12, blade.x);
	float root = smoothstep(0.0, 0.55, height);
	float tip = smoothstep(0.6, 1.0, height);
	vec3 near = c * mix(0.72, 1.05, root) * mix(vec3(1.0), vec3(0.94, 0.97, 0.97), tip);
	// Forward+ lights each blade on its own: there the tips catch a
	// little sun (blade_relief) instead.
	near *= mix(vec3(1.0), vec3(1.1, 1.1, 1.0), tip * blade_relief);
	near *= mix(1.0, tip_light, smoothstep(0.3, 1.0, height));
	vec3 far = base_color * mix(0.88, 1.0, blade.x) * mix(0.8, 1.0, root);
	// Toned like the turf under it (turf_tone), or the blades stand out.
	vec3 turf = tone_turf(mix(near, far, blend));
	turf = mix(vec3(dot(turf, vec3(0.2126, 0.7152, 0.0722))), turf, saturation);
	// Capped well below white: pale disc rough lifted for Compatibility
	// would otherwise pass the glow threshold and bloom into a white haze.
	vec3 albedo = min(turf * brightness, vec3(0.6));
	ALBEDO = albedo * shade_fill.a * ground_shading(root_xz, length(VERTEX));
	EMISSION = albedo * shade_fill.rgb;
	// Both faces lit like the ground: without this the back faces flip
	// their normal and go dark (Compatibility shows it most).
	float turn = blade.x * 6.2831;
	vec3 n = normalize(vec3(cos(turn) * blade_relief, 1.0, sin(turn) * blade_relief));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
