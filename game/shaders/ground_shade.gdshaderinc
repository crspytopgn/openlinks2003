// The baked ground shade (GroundShade): sun shadows of trees, bushes,
// rocks and models in R, occlusion at their feet in G, over the rectangle
// ground_shade_rect (x, z, width, depth; width 0 = nothing baked). The
// sun shadow fades out within ground_shade_near of the camera, where the
// full 3D trees cast real-time shadows.
global uniform sampler2D ground_shade;
global uniform vec4 ground_shade_rect;
global uniform float ground_shade_near;
// Shadows of passing clouds (0 = off, else how much light they take),
// drifted by cloud_offset metres with the wind.
global uniform float cloud_shadow;
global uniform vec2 cloud_offset;

float cloud_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), u.x), mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// How much light the clouds let through at world (x, z) `p`: broken
// patches a few hundred metres across with soft edges.
float cloud_light(vec2 p) {
	if (cloud_shadow <= 0.0) {
		return 1.0;
	}
	vec2 q = (p - cloud_offset) / 260.0;
	float n = cloud_noise(q) * 0.55 + cloud_noise(q * 2.13 + vec2(3.1, 7.7)) * 0.3 + cloud_noise(q * 4.7 + vec2(9.2, 1.3)) * 0.15;
	return 1.0 - cloud_shadow * smoothstep(0.5, 0.68, n);
}

// How much light reaches the ground at world (x, z) `p`, `dist` metres
// from the camera: multiply the albedo by it.
float ground_shading(vec2 p, float dist) {
	float clouds = cloud_light(p);
	if (ground_shade_rect.z <= 0.0) {
		return clouds;
	}
	vec2 uv = (p - ground_shade_rect.xy) / ground_shade_rect.zw;
	vec2 inside = min(uv, 1.0 - uv);
	float edge = smoothstep(0.0, 0.04, min(inside.x, inside.y));
	if (edge <= 0.0) {
		return clouds;
	}
	// The map holds sRGB-encoded values.
	vec2 s = pow(texture(ground_shade, uv).rg, vec2(2.2));
	float sun = mix(1.0, s.r, edge * smoothstep(ground_shade_near * 0.8, ground_shade_near, dist));
	return clouds * sun * mix(1.0, s.g, edge);
}
