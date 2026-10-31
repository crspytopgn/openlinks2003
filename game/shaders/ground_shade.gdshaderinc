// The baked ground shade (GroundShade): sun shadows of trees, bushes,
// rocks and models in R, occlusion at their feet in G, over the rectangle
// ground_shade_rect (x, z, width, depth; width 0 = nothing baked). The
// sun shadow fades out within ground_shade_near of the camera, where the
// full 3D trees cast real-time shadows.
global uniform sampler2D ground_shade;
global uniform vec4 ground_shade_rect;
global uniform float ground_shade_near;

// How much light reaches the ground at world (x, z) `p`, `dist` metres
// from the camera: multiply the albedo by it.
float ground_shading(vec2 p, float dist) {
	if (ground_shade_rect.z <= 0.0) {
		return 1.0;
	}
	vec2 uv = (p - ground_shade_rect.xy) / ground_shade_rect.zw;
	vec2 inside = min(uv, 1.0 - uv);
	float edge = smoothstep(0.0, 0.04, min(inside.x, inside.y));
	if (edge <= 0.0) {
		return 1.0;
	}
	// The map holds sRGB-encoded values.
	vec2 s = pow(texture(ground_shade, uv).rg, vec2(2.2));
	float sun = mix(1.0, s.r, edge * smoothstep(ground_shade_near * 0.8, ground_shade_near, dist));
	return sun * mix(1.0, s.g, edge);
}
