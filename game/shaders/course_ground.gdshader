// Ground of a disc course in the Photoreal and Natural looks (CrzTerrain):
// a free photographed ground texture per surface instead of the disc's
// 2003 texture, tinted to the course's own colour for that surface, so the
// course keeps its character with real grass, rough and sand detail. The
// photo is sampled at two scales so its repeat is hard to see, fades to
// its mean colour far away (no shimmer), and gets large patches of
// lighter and darker ground. Mown surfaces get mowing stripes. Plus the
// baked ground shade (GroundShade).
shader_type spatial;

#include "res://shaders/ground_shade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform vec3 photo_mean : source_color = vec3(0.5); // the photo's average colour
uniform vec3 far_color : source_color = vec3(0.3, 0.45, 0.2); // the ground's colour
uniform float tile = 2.5; // metres per repeat
uniform float variation = 0.14; // large lighter and darker patches
uniform float stripes = 0.0; // mowing stripe contrast (0 = none)
uniform float stripe_width = 9.0;
uniform float stripe_angle = 0.6; // radians from +x
uniform float roughness_value = 0.92;
uniform float normal_strength = 0.6;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv = p / tile;
	float dist = length(VERTEX);
	vec3 raw = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv * 0.137 + vec2(0.31, 0.71)).rgb, 0.35);
	// The photo's detail (mostly its light and dark) on the ground's colour,
	// so its own hue doesn't shift the course's.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	vec3 detail = mix(vec3(dot(raw, LUMA) / max(dot(photo_mean, LUMA), 0.02)), raw / max(photo_mean, vec3(0.02)), 0.3);
	vec3 photo = far_color * detail;
	vec3 col = mix(photo, far_color, smoothstep(60.0, 400.0, dist));
	col *= 1.0 + (fbm(p * 0.02) - 0.5) * variation * 2.0 + (value_noise(p * 0.3) - 0.5) * variation * 0.6;
	if (stripes > 0.0) {
		vec2 dir = vec2(cos(stripe_angle), sin(stripe_angle));
		float band = step(0.5, fract(dot(p, dir) / (stripe_width * 2.0)));
		col *= 1.0 + (band - 0.5) * stripes;
	}
	if (has_normal) {
		vec3 n = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv * 0.137 + vec2(0.31, 0.71)).rgb, 0.35) * 2.0 - 1.0;
		float near = 1.0 - smoothstep(30.0, 150.0, dist);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz * normal_strength * near);
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0)) * ground_shading(p, dist);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
