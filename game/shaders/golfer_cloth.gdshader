shader_type spatial;
// The free golfer's clothes (GolferCloth): shirt, trousers, shorts and skort
// as a matt fabric with the soft rim fibres catch, plus
// - wind: loose cloth is pushed downwind and ripples, more as the wind
//   gets up (wind_vector carries the gusts, as for the flag);
// - swing lag: sleeves, trouser legs and the shirt trail the body's
//   acceleration and the chest's turn (springs run by GolferCloth);
// - folds: diagonal folds across the shirt as the shoulders turn against
//   the hips, and creases at bent elbows and knees, as shading only.
// COLOR is the mask GolferCloth.with_mask bakes: R looseness, G arm share,
// B leg share, A how far round to the front of the body. UV2 is the
// rest-pose x, y (the rig's left is -x).
// Every offset is a few centimetres at most, and off the arms none uses
// the vertex normal, so the collar, placket and buttons move with the shirt.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_vector; // air velocity over the course, m/s (x, z)

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

// Set each frame by GolferCloth.
uniform float motion = 0.0; // 0 still (Low), 1 moving
uniform float fine = 0.0; // 1 on Ultra: a finer second ripple
uniform vec3 lag_torso = vec3(0.0);
uniform vec3 lag_arm_l = vec3(0.0);
uniform vec3 lag_arm_r = vec3(0.0);
uniform vec3 lag_leg_l = vec3(0.0);
uniform vec3 lag_leg_r = vec3(0.0);
uniform float turn_lag = 0.0; // radians the shirt trails the chest's turn
uniform vec3 spine = vec3(0.0, 1.15, 0.0); // posed, for the turn
uniform vec3 spine_axis = vec3(0.0, 1.0, 0.0);
uniform float twist = 0.0; // -1..1: fold depth and side of the body's twist
uniform vec4 bends = vec4(0.0); // elbow l, elbow r, knee l, knee r (0..1)
// Set once per look: shoulder and elbow rest x, y per side, knee heights,
// and the waist and neck heights.
uniform vec4 joints_l = vec4(-0.2, 1.4, -0.37, 1.21);
uniform vec4 joints_r = vec4(0.2, 1.4, 0.37, 1.21);
uniform vec2 knees = vec2(0.52, 0.52);
uniform vec2 torso_band = vec2(0.95, 1.45);

// Wind and folds
const float PUSH = 0.014; // m downwind at 12 m/s
const float RIPPLE = 0.007; // m of ripple at 12 m/s
const float FOLD_DEPTH = 0.0035; // m

varying vec4 mask;
varying vec2 rest;

void vertex() {
	mask = COLOR;
	rest = UV2;
	float loose = COLOR.r * motion;
	if (loose > 0.0) {
		vec3 w = inverse(mat3(MODEL_MATRIX)) * vec3(wind_vector.x, 0.0, wind_vector.y);
		float speed = length(w);
		vec3 dir = speed > 0.05 ? w / speed : vec3(0.0);
		float s = clamp(speed / 12.0, 0.0, 1.3);
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), dir + vec3(0.0001)));
		// Ripples run downwind and down the cloth, quickening with the wind.
		float phase = (rest.x * dir.x + rest.y * 0.6) * 15.0 - TIME * TAU * (1.6 + 3.2 * s);
		float wobble = 0.6 + 0.4 * sin(phase * 0.53 + rest.x * 11.0 + TIME * 1.7);
		float f1 = sin(phase) * wobble;
		float f2 = sin(phase * 0.71 + rest.y * 7.0 + 1.3);
		float f3 = fine * sin(phase * 2.7 + rest.x * 23.0 - TIME * 9.0);
		vec3 d = dir * (PUSH * s * s + RIPPLE * s * (f1 + 0.3 * f3));
		d += side * (0.5 * RIPPLE * s * f2) + vec3(0.0, 0.25 * RIPPLE * s * f1, 0.0);
		// The swing: arms, legs and torso trail their own springs.
		float arm = COLOR.g;
		float leg = COLOR.b;
		float left = smoothstep(0.02, -0.02, UV2.x);
		float body = clamp(1.0 - arm - leg, 0.0, 1.0);
		vec3 lag = body * lag_torso + arm * mix(lag_arm_r, lag_arm_l, left) + leg * mix(lag_leg_r, lag_leg_l, left);
		vec3 r = VERTEX - spine;
		lag += body * turn_lag * cross(spine_axis, r - spine_axis * dot(r, spine_axis));
		vec3 move = loose * (d + lag);
		// A sleeve may not press into the arm under it: most of any move
		// into the cloth is dropped there. (Only on the arms: the collar,
		// placket and buttons must move exactly as the shirt does, and no
		// skin is left under the shirt or trousers.)
		float inward = min(dot(move, NORMAL), 0.0);
		move -= NORMAL * inward * 0.85 * clamp(arm * 1.5, 0.0, 1.0);
		VERTEX += move;
		// The ripples tilt the shading a little too.
		NORMAL = normalize(NORMAL - loose * s * 0.12 * cos(phase) * dir);
	}
}

// One fold pattern: sharper valleys than crests, as cloth hangs.
float folds(float x) {
	return sin(x) + 0.35 * sin(2.0 * x + 1.0);
}

// Faded out where the pattern gets finer than a couple of pixels, so it
// never shimmers at a distance.
float settle(float x) {
	return 1.0 - smoothstep(0.7, 1.6, fwidth(x));
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	vec3 base = albedo.rgb * tex.rgb;
	float h = 0.0;
	if (abs(twist) + bends.x + bends.y + bends.z + bends.w > 0.001) {
		float arm = mask.g;
		float leg = mask.b;
		float body = clamp(1.0 - arm - leg, 0.0, 1.0);
		// Twist: diagonal folds over the middle of the torso, leaning the
		// way the shoulders have turned.
		float t = (rest.y - torso_band.x) / max(torso_band.y - torso_band.x, 0.1);
		float band = smoothstep(0.05, 0.25, t) * (1.0 - smoothstep(0.65, 0.9, t));
		// A few soft folds of uneven spacing that fade in and out along
		// their length, not a ribbed pattern.
		float ty = rest.y - torso_band.x;
		float across = rest.x * sign(twist) * 0.9 + ty;
		float along_fold = rest.x - sign(twist) * 0.9 * ty;
		float x = (across + 0.025 * sin(along_fold * 21.0 + 0.7) + 0.6 * across * across) * (TAU / 0.11);
		float patchy = smoothstep(-0.7, 0.7, sin(along_fold * 11.0 + across * 5.0 + 1.9));
		// Mostly on the front and sides, where the shirt bunches; across the
		// back it is pulled taut by the turn.
		float front = mask.a;
		h += 1.1 * folds(x) * abs(twist) * body * band * patchy * mix(0.15, 1.0, front) * settle(x);
		// Elbows: rings round the sleeve either side of the joint.
		bool on_left = rest.x < 0.0;
		vec4 j = on_left ? joints_l : joints_r;
		vec2 up_arm = j.zw - j.xy;
		float upper = max(length(up_arm), 0.1);
		float along = dot(rest - j.xy, up_arm / upper);
		float e = along - upper;
		float xe = along * (TAU / 0.032);
		h += folds(xe) * exp(-e * e / 0.004) * (on_left ? bends.x : bends.y) * arm * settle(xe);
		// Knees: creases across the trouser leg at the knee.
		float knee = on_left ? knees.x : knees.y;
		float k = rest.y - knee;
		// Bowed and uneven round the leg, not ruled lines.
		float xk = (rest.y + 0.012 * sin(rest.x * 60.0) + 0.6 * k * k) * (TAU / 0.04);
		h += 0.8 * folds(xk) * exp(-k * k / 0.006) * (on_left ? bends.z : bends.w) * leg * settle(xk);
	}
	// Bump the normal by the fold height (screen-space derivatives, so
	// outside any branch that varies across the surface).
	{
		float hm = h * FOLD_DEPTH;
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec3 n = NORMAL;
		vec3 r1 = cross(dpy, n);
		vec3 r2 = cross(n, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dFdx(hm) * r1 + dFdy(hm) * r2);
		NORMAL = normalize(abs(det) * n - grad);
		// The folds' valleys are a touch darker.
		base *= 1.0 - 0.07 * clamp(-h, 0.0, 1.5);
	}
	ALBEDO = base;
	if (use_normal) {
		NORMAL_MAP = texture(texture_normal, UV).rgb;
	}
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	RIM = 0.25;
	RIM_TINT = 0.7;
}
