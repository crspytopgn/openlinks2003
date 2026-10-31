// Ground of a disc course in the Photoreal and Natural looks (CrzTerrain):
// a free photoscanned ground set (albedo, normal, roughness) per surface instead of the disc's
// 2003 texture, tinted to the course's own colour for that surface, so the
// course keeps its character with real grass, rough and sand detail. The
// photo is sampled at two scales so its repeat is hard to see, fades to
// its mean colour far away (no shimmer), and gets large patches of
// lighter and darker ground. Mown surfaces get mowing stripes. Plus the
// baked ground shade (GroundShade).
//
// A blended material (the course's fairway to rough and bunker edges)
// draws two such layers, the second from the *_b uniforms, faded by the
// course's own edge mask at the mesh's CUSTOM0 coordinates: black is the
// first layer, white the second.
shader_type spatial;

#include "res://shaders/ground_shade.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D roughness_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform bool has_roughness = false;
uniform vec3 photo_mean : source_color = vec3(0.5); // the photo's average colour
uniform vec3 far_color : source_color = vec3(0.3, 0.45, 0.2); // the ground's colour
uniform float tile = 2.5; // metres per repeat
uniform float photo_hue = 0.3; // how much of the photo's own colour shifts show
uniform float detail_gain = 1.0; // how strongly the photo's light and dark show
uniform float variation = 0.14; // large lighter and darker patches
uniform float stripes = 0.0; // mowing stripe contrast (0 = none)
uniform float stripe_width = 9.0;
uniform float stripe_angle = 0.6; // radians from +x
uniform float roughness_value = 0.92;
uniform float normal_strength = 0.6;

uniform bool blended = false;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal_b = false;
uniform sampler2D roughness_tex_b : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform bool has_roughness_b = false;
uniform vec3 photo_mean_b : source_color = vec3(0.5);
uniform vec3 far_color_b : source_color = vec3(0.3, 0.45, 0.2);
uniform float tile_b = 2.5;
uniform float photo_hue_b = 0.3;
uniform float detail_gain_b = 1.0;
uniform float variation_b = 0.14;
uniform float stripes_b = 0.0;
uniform float stripe_width_b = 9.0;
uniform float roughness_value_b = 0.92;

varying vec3 world_pos;
varying vec2 mask_uv;

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

// One photo layer's colour at ground point p, dist metres away.
vec3 layer_color(vec3 raw, vec3 mean, vec3 far, float hue, float gain, float vary, float stripe, float width, vec2 p, float dist) {
	// The photo's detail (mostly its light and dark) on the ground's colour,
	// so its own hue doesn't shift the course's.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	vec3 detail = mix(vec3(dot(raw, LUMA) / max(dot(mean, LUMA), 0.02)), raw / max(mean, vec3(0.02)), hue);
	detail = max(vec3(1.0) + (detail - vec3(1.0)) * gain, vec3(0.0));
	vec3 col = mix(far * detail, far, smoothstep(60.0, 400.0, dist));
	col *= 1.0 + (fbm(p * 0.02) - 0.5) * vary * 2.0 + (value_noise(p * 0.3) - 0.5) * vary * 0.6;
	if (stripe > 0.0) {
		vec2 dir = vec2(cos(stripe_angle), sin(stripe_angle));
		float band = step(0.5, fract(dot(p, dir) / (width * 2.0)));
		col *= 1.0 + (band - 0.5) * stripe;
	}
	return col;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mask_uv = blended ? CUSTOM0.xy : vec2(0.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(30.0, 150.0, dist);
	float near_rough = 1.0 - smoothstep(20.0, 120.0, dist);
	vec2 uv = p / tile;
	vec3 raw = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv * 0.137 + vec2(0.31, 0.71)).rgb, 0.35);
	vec3 col = layer_color(raw, photo_mean, far_color, photo_hue, detail_gain, variation, stripes, stripe_width, p, dist);
	vec3 n = vec3(0.0);
	if (has_normal) {
		n = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv * 0.137 + vec2(0.31, 0.71)).rgb, 0.35) * 2.0 - 1.0;
	}
	float rough = roughness_value;
	if (has_roughness) {
		// The scan's own glossy and matt blades near the camera, centred on
		// the surface's roughness.
		rough += (texture(roughness_tex, uv).g - 0.5) * 0.35 * near_rough;
	}
	if (blended) {
		// The mask runs 0 to 1 across the edge; keep off its border texels.
		float w = texture(mask_tex, vec2(clamp(mask_uv.x, 0.02, 0.98), mask_uv.y)).a;
		vec2 uv_b = p / tile_b;
		vec3 raw_b = mix(texture(albedo_tex_b, uv_b).rgb, texture(albedo_tex_b, uv_b * 0.137 + vec2(0.31, 0.71)).rgb, 0.35);
		vec3 col_b = layer_color(raw_b, photo_mean_b, far_color_b, photo_hue_b, detail_gain_b, variation_b, stripes_b, stripe_width_b, p, dist);
		col = mix(col, col_b, w);
		vec3 n_b = vec3(0.0);
		if (has_normal_b) {
			n_b = mix(texture(normal_tex_b, uv_b).rgb, texture(normal_tex_b, uv_b * 0.137 + vec2(0.31, 0.71)).rgb, 0.35) * 2.0 - 1.0;
		}
		n = mix(n, n_b, w);
		float rough_b = roughness_value_b;
		if (has_roughness_b) {
			rough_b += (texture(roughness_tex_b, uv_b).g - 0.5) * 0.35 * near_rough;
		}
		rough = mix(rough, rough_b, w);
	}
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz * normal_strength * near);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0)) * ground_shading(p, dist);
	// Turf, sand and paths are matt: no sheen from the sun or the sky.
	ROUGHNESS = clamp(rough, 0.9, 1.0);
	SPECULAR = 0.1;
}
