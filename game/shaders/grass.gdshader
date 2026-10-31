// 3D grass tufts in the rough (GrassField). Each MultiMesh instance is one
// tuft of thin blades; INSTANCE_CUSTOM.rgb is the ground's colour under it
// (sRGB) and .a a random phase. Blades bend with the global wind and shrink
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

#include "res://shaders/ground_shade.gdshaderinc"

varying vec3 base_color;
varying float height;
varying vec2 root_xz;

void vertex() {
	// VERTEX and NORMAL are in world space here (world_vertex_coords).
	height = UV.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	root_xz = root.xz;
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(root.xz, camera_pos.xz));
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
	// Darker in the tuft, sun-bleached at the tips.
	ALBEDO = base_color * mix(0.8, 1.25, height) * brightness * vec3(0.97, 1.03, 0.9)
		* ground_shading(root_xz, length(VERTEX));
	// Both faces lit like the ground: without this the back faces flip
	// their normal and go dark (Compatibility shows it most).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
