// Soft shading where the golfer's own body crowds the light out: the shirt
// under and between the arms, the inside of the arms, between the legs,
// the armpits and under the chin. A real body is never lit evenly all
// over, and without this the free golfer looks like a cut-out painted in
// flat colours, the early-2000s game look, above all on Compatibility,
// which has no screen-space ambient occlusion at all.
//
// Each limb and the trunk is a capsule (GolferCloth.occluders sets them
// every frame from the posed skeleton, in world space). A capsule the
// surface faces, close by, blocks some of its sky: about (cos angle) times
// (radius / distance)^1.5 of it, between the share a sphere covers
// (power 2) and a long cylinder's (power 1).
// A surface on the capsule's own limb faces away from it, so a limb never
// darkens itself. On the shaded side it takes ambient light (AO); some of
// the sun as well (contact_share), as limbs pressed together shade each
// other there more than the sun's shadow map can resolve.

const int OCCLUDERS = 11;
uniform vec4 occ_a[11]; // xyz one end, w radius
uniform vec4 occ_b[11]; // xyz the other end
uniform float occ_strength = 0.0; // 0 off (until GolferCloth sets it)
uniform float contact_share = 0.7;

varying vec3 occ_pos;
varying vec3 occ_normal;

// Set at the end of vertex() (a function may not assign varyings):
//   occ_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   occ_normal = mat3(MODEL_MATRIX) * NORMAL;

// 1 fully open to the sky, less where the body closes it in, at world
// position `p` facing `n`: body_occlusion(occ_pos, occ_normal).
float body_occlusion(vec3 p, vec3 normal) {
	if (occ_strength <= 0.0) {
		return 1.0;
	}
	vec3 n = normalize(normal);
	float open = 1.0;
	for (int i = 0; i < OCCLUDERS; i++) {
		vec3 a = occ_a[i].xyz;
		float r = occ_a[i].w;
		vec3 ab = occ_b[i].xyz - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		vec3 d = a + ab * t - p;
		float l = max(length(d), 1e-4);
		float facing = clamp(dot(n, d) / l, 0.0, 1.0);
		open *= 1.0 - facing * pow(min(r / l, 1.0), 1.5) * occ_strength;
	}
	return clamp(open, 0.3, 1.0);
}
