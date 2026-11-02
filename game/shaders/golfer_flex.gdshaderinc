// Skin and muscle that work through the swing (GolferFlex): the forearms'
// muscles swell and firm up as the grip tightens into the strike, the
// tendons at the wrist and the veins stand out, the inside of a bent elbow
// creases, and the neck's long muscle (the sternocleidomastoid) ropes out
// on the side away from the turn while the skin folds on the side the
// head turns to.
//
// No blend shapes or wrinkle textures: each vertex of the forearms and
// the neck carries where it sits on the limb (GolferFlex.with_mask):
//   UV2.x  t, along the limb: 0 the elbow, 1 the wrist (the neck: 0 its
//          base, 1 under the ear);
//   UV2.y  how much of it is forearm, + left arm, - right arm;
//   COLOR.rg  the angle round the limb as cos, sin (0..1): 0 on the palm
//          side (the front of the throat), + towards the thumb (the
//          golfer's left);
//   COLOR.b  how much of it is neck.
// The muscles, tendons, veins and creases are heights over that (t,
// angle) map, from GolferFlex's bone-driven uniforms. vertex() swells the
// broad muscles (a few millimetres, as a working forearm does), and
// fragment() bends the normal over all of it, with the slopes found
// from three samples.
//
// Use, in vertex() itself (a function may not assign varyings), with
// `skin` 0 where the texture is clothes:
//   flex_v = vec4(UV2.x, UV2.y * skin, COLOR.b * skin, 0.0);
//   flex_cs = COLOR.rg * 2.0 - 1.0;
//   VERTEX += NORMAL * flex_swell(flex_v, flex_cs);
// and in fragment(), before any NORMAL_MAP:
//   vec4 f = flex_fragment(flex_v, flex_cs, NORMAL, VIEW_MATRIX);
//   NORMAL = f.xyz;  // and the albedo times f.w (the creases)

uniform float flex_on = 0.0; // 0 off (until GolferFlex sets it)
uniform float flex_detail = 2.0; // 1 muscles and tendons, 2 and veins and creases
// The forearms' and neck's directions in world space (elbow to wrist,
// neck to head), their lengths in metres and their angle's handedness.
uniform vec3 flex_axis_l = vec3(0.0, -1.0, 0.0);
uniform vec3 flex_axis_r = vec3(0.0, -1.0, 0.0);
uniform vec3 flex_axis_n = vec3(0.0, 1.0, 0.0);
uniform vec3 flex_len = vec3(0.26, 0.26, 0.13);
uniform vec3 flex_sign = vec3(1.0);
uniform float flex_scale = 1.0;
// Per arm (left, right): how hard the hand grips 0..1, how far the elbow
// and the wrist are bent 0..1.
uniform vec2 flex_grip = vec2(0.0);
uniform vec2 flex_elbow = vec2(0.0);
uniform vec2 flex_wrist = vec2(0.0);
// The head's turn against the chest (-1 right .. 1 left) and the neck's effort.
uniform vec2 flex_neck = vec2(0.0);
// How much this person's veins show (lean men most) and their own pattern.
uniform float flex_veins = 1.0;
uniform float flex_seed = 0.0;
// 1 paints the baked map instead (tests/golfer_flex_render.gd "mask").
uniform float flex_debug = 0.0;

varying vec4 flex_v; // t, arm (+l -r), neck, unused
varying vec2 flex_cs; // cos, sin of the angle round the limb

float flex_g(float x, float s) {
	return exp(-x * x / (s * s));
}

// The angle from a to b, -PI..PI.
float flex_d(float a, float b) {
	return mod(a - b + 9.42477796, 6.28318531) - 3.14159265;
}

// 0 outside a..b, rising to 1 in the middle.
float flex_hump(float t, float a, float b) {
	float x = clamp((t - a) / (b - a), 0.0, 1.0);
	return 16.0 * x * x * (1.0 - x) * (1.0 - x);
}

// The forearm's surface height in metres at (t, angle th) for grip g,
// elbow bend e and wrist bend w. fine 0 leaves out the tendons, veins
// and creases (the vertex swell).
float flex_arm(float t, float th, float g, float e, float w, float fine) {
	// The flexors (the inner forearm's bulk, gripping), the brachioradialis
	// on the thumb side near the elbow (gripping, and bending the elbow) and
	// the extensors on the back, firm as the wrist holds its hinge.
	float h = flex_hump(t, 0.02, 0.62) * flex_g(flex_d(th, -0.5), 0.75) * (0.0012 + 0.0034 * g);
	h += flex_hump(t, -0.12, 0.5) * flex_g(flex_d(th, 1.3), 0.5) * (0.0008 + 0.0026 * max(g, 0.7 * e));
	h += flex_hump(t, 0.05, 0.6) * flex_g(flex_d(th, 2.55), 0.6) * (0.0008 + 0.0018 * max(g, w));
	if (fine <= 0.0) {
		return h;
	}
	// Tendons in the lower third: palmaris longus in the middle, the
	// radial and ulnar flexors either side, sharper with the wrist bent.
	float band = smoothstep(0.55, 0.78, t) * (1.0 - smoothstep(0.97, 1.05, t));
	float tendon = flex_g(flex_d(th, -0.1), 0.085) + 0.8 * flex_g(flex_d(th, 0.38), 0.1) + 0.6 * flex_g(flex_d(th, -0.95), 0.12);
	h += band * tendon * 0.0008 * (0.12 + g) * (1.0 + 0.8 * w);
	if (fine < 2.0) {
		return h;
	}
	// Veins: the cephalic up the thumb side, the basilic on the inner
	// edge and the median up the middle, wandering a little, fuller as
	// the effort pumps blood into the arm.
	float s = flex_seed;
	float v1 = flex_g(flex_d(th, 1.0 + 0.16 * sin(t * 8.0 + s)), 0.06) * flex_hump(t, -0.2, 1.1);
	float v2 = flex_g(flex_d(th, -1.15 + 0.13 * sin(t * 6.5 + s * 1.7)), 0.06) * flex_hump(t, 0.0, 1.1);
	float v3 = flex_g(flex_d(th, 0.2 + 0.22 * sin(t * 5.0 + s * 2.3)), 0.055) * flex_hump(t, -0.1, 0.75);
	h += (v1 + v2 + 0.7 * v3) * 0.00045 * flex_veins * (0.35 + 0.65 * g);
	// The inside of the elbow folds as it bends.
	float front = flex_g(flex_d(th, 0.0), 0.9);
	h -= front * e * 0.0007 * (flex_g(t + 0.02, 0.014) + 0.7 * flex_g(t - 0.035, 0.011));
	// Wrist creases on the palm side as the wrist cocks.
	h -= front * w * 0.0004 * (flex_g(t - 0.99, 0.012) + 0.6 * flex_g(t - 1.04, 0.01));
	return h;
}

// The neck's height at (t, angle th) for turn `turn` and effort k.
float flex_neck_h(float t, float th, float turn, float k, float fine) {
	float h = 0.0;
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? 1.0 : -1.0;
		// From the top of the breastbone up and round to behind the ear;
		// it stands out on the side away from the way the head turns.
		float path = side * (0.28 + 1.5 * clamp(t, 0.0, 1.0));
		float amp = 0.001 + 0.0032 * max(0.0, -side * turn) + 0.001 * k;
		h += flex_hump(t, -0.08, 1.06) * flex_g(flex_d(th, path), 0.3) * amp;
		if (fine >= 2.0) {
			// The skin bunches on the side the chin turns towards.
			float f = max(0.0, side * turn);
			float folds = flex_g(t - 0.42, 0.03) + flex_g(t - 0.58, 0.028) + 0.7 * flex_g(t - 0.74, 0.026);
			h -= f * 0.0006 * folds * flex_g(flex_d(th, side * 1.35), 0.5);
		}
	}
	return h;
}

// v: flex_v (t, arm, neck), passed in as functions may not use varyings.
float flex_height(vec4 v, float t, float th, float fine) {
	float arm = v.y;
	if (abs(arm) > 0.0) {
		float l = arm > 0.0 ? 1.0 : 0.0;
		return abs(arm) * flex_arm(t, th, mix(flex_grip.y, flex_grip.x, l), mix(flex_elbow.y, flex_elbow.x, l), mix(flex_wrist.y, flex_wrist.x, l), fine);
	}
	return v.z * flex_neck_h(t, th, flex_neck.x, flex_neck.y, fine);
}

// How far the muscles swell the vertex out along its normal, from
// v = flex_v and cs = flex_cs as vertex() set them.
float flex_swell(vec4 v, vec2 cs) {
	if (flex_on <= 0.0 || abs(v.y) + v.z <= 0.0) {
		return 0.0;
	}
	return flex_height(v, v.x, atan(cs.y, cs.x), 0.0) / max(flex_scale, 0.01);
}

// The normal bent over the muscles, tendons, veins and creases (view
// space in, view space out) and, in w, the shade the creases add to the
// albedo.
vec4 flex_fragment(vec4 v, vec2 cs, vec3 normal, mat4 view) {
	vec3 n = normalize(normal);
	float arm = abs(v.y);
	if (flex_on <= 0.0 || arm + v.z <= 0.001) {
		return vec4(n, 1.0);
	}
	float left = v.y > 0.0 ? 1.0 : 0.0;
	vec3 axis_w = arm > 0.0 ? mix(flex_axis_r, flex_axis_l, left) : flex_axis_n;
	float sgn = arm > 0.0 ? mix(flex_sign.y, flex_sign.x, left) : flex_sign.z;
	float len = arm > 0.0 ? mix(flex_len.y, flex_len.x, left) : flex_len.z;
	float t = v.x;
	// The limb's radius there: a forearm narrows to the wrist.
	float radius = (arm > 0.0 ? mix(0.041, 0.028, clamp(t, 0.0, 1.0)) : 0.055) * flex_scale;
	float th = atan(cs.y, cs.x);
	const float STEP = 0.004;
	float h0 = flex_height(v, t, th, flex_detail);
	float dt = (flex_height(v, t + STEP, th, flex_detail) - h0) / STEP;
	float da = (flex_height(v, t, th + STEP * 2.0, flex_detail) - h0) / (STEP * 2.0);
	vec3 axis = normalize((view * vec4(axis_w, 0.0)).xyz);
	vec3 along = axis - n * dot(axis, n);
	float al = length(along);
	if (al < 1e-3) {
		return vec4(n, 1.0);
	}
	along /= al;
	vec3 around = cross(axis, n) * sgn;
	vec3 slope = along * dt / max(len, 0.05) + around * da / radius;
	// The creases' floors take a little less light.
	float shade = 1.0 + clamp(h0, -0.001, 0.0) * 120.0;
	return vec4(normalize(n - slope), shade);
}

// The baked map as colour, for checking it: red the left forearm, green
// the right, blue the neck, banded along the limb every tenth, brightest
// on the front (palm side, throat).
vec3 flex_debug_colour(vec4 v, vec2 cs) {
	float band = 0.6 + 0.4 * step(0.5, fract(v.x * 10.0));
	float front = 0.4 + 0.6 * (cs.x * 0.5 + 0.5);
	return vec3(max(v.y, 0.0), max(-v.y, 0.0), v.z) * band * front + vec3(0.05);
}
