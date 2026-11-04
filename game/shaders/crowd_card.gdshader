// Crowd cards (Gallery): the spectators further from the cameras, past the
// 3D people. Each is one camera-facing quad (turning about the vertical
// only, so people stay upright) that draws a standing person in silhouette:
// head and hair or cap, shirt and arms (hanging or folded), trousers or
// shorts and legs. The shirt
// colour is the MultiMesh instance colour; INSTANCE_CUSTOM carries the
// trousers (rgb) and the skin tone (a, dark to light). Hundreds of them are
// one draw call. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;

uniform vec3 light_dir = vec3(0.4, 0.8, 0.3);
// Baked people (CrowdImpostors): a row per view direction, a column per
// person. Without the atlas the cards draw the silhouette below.
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_atlas = false;
uniform float people = 12.0;
uniform float frames = 8.0;
// The share of the person drawn, from the top of the head down: 1 for
// someone standing, about half for someone seated in a grandstand (head to
// hips; the row in front hides the rest). The card's origin is then at the
// lowest point drawn.
uniform float cut = 1.0;
// Daylight on people in Compatibility (shaders/golfer_occlusion.gdshaderinc):
// x undoes Photoreal's exposure lift on the albedo, y its fill-light lift.
// The 3D people take it, and the cards stood among them must too, or the
// front rows read pale and glowing next to them. (1, 1, 0) elsewhere.
global uniform vec3 people_light;

varying vec3 shirt;
varying vec4 custom;
varying float side;
// Per-person picks (cap, folded arms, shorts, long hair, cap colour, grey
// hair), worked out once per instance so every pixel agrees.
varying flat vec4 picks;
varying flat vec2 picks2;
varying flat float person;
varying flat float frame;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = vec3(cam.x - origin.x, 0.0, cam.z - origin.z);
	to_cam = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec2 quad = VERTEX.xy * vec2(1.0, cut);
	if (has_atlas) {
		// The atlas cell is 1 m by 2 m for a 1.8 m person, wider and a
		// little taller than the silhouette's card (0.62 m wide).
		quad *= vec2(1.0 / 0.62, 2.0 / 1.8);
	}
	vec3 world = origin + right * quad.x * height + vec3(0.0, quad.y * height, 0.0);
	// Which side of the person the camera is on, in their own frame (they
	// face their -z): picks the baked view.
	vec3 ax = normalize(MODEL_MATRIX[0].xyz);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	float azimuth = atan(dot(to_cam, ax), dot(to_cam, az));
	frame = mod(round(azimuth / (6.2831853 / frames)), frames);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Facing the camera and tipped up to the sky: a card is flat, so lit
	// by its facing alone it goes black whenever the sun is behind the
	// person, where a real person still catches light on the head and
	// shoulders and from the sky.
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam + vec3(0.0, 1.2, 0.0), 0.0)).xyz);
	shirt = COLOR.rgb;
	custom = INSTANCE_CUSTOM;
	// Which way the light falls across the figure, for a little modelling.
	side = dot(normalize(vec3(light_dir.x, 0.0, light_dir.z)), right);
	float seed = float(INSTANCE_ID) * 1.618 + 0.5;
	picks = vec4(hash(seed), hash(seed + 1.0), hash(seed + 2.0), hash(seed + 3.0));
	picks2 = vec2(hash(seed + 4.0), hash(seed + 5.0));
	person = floor(hash(seed + 6.0) * people);
}

float box(vec2 p, vec2 c, vec2 h, float r) {
	vec2 d = abs(p - c) - h + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	if (has_atlas) {
		vec2 uv = vec2((person + clamp(UV.x, 0.01, 0.99)) / people, (frame + clamp(UV.y * cut, 0.005, 0.995)) / frames);
		vec4 c = texture(atlas, uv);
		// The bake's background is clear black, so a smaller mip level
		// holds each person's colour times how much of the texel they
		// cover: divide that back out, or far people fade to black blobs,
		// and keep a texel half covered or more so they don't thin away.
		if (c.a < 0.4) {
			discard;
		}
		c.rgb = min(c.rgb / c.a, vec3(1.0));
		// Baked under soft daylight; the scene's light adds a little side
		// shade on top, as for the silhouettes.
		float across = (UV.x - 0.5) * 2.0;
		// The lift makes up for the bake's soft light in Forward+; in
		// Compatibility at Photoreal (people_light.x below 1) the scene's
		// lifted exposure already does, and lifting again made the cards
		// in the front rows glow next to the 3D people.
		float lift = people_light.x < 0.99 ? 1.0 : 1.25;
		ALBEDO = c.rgb * clamp(lift + 0.15 * side * across, lift - 0.15, lift + 0.15) * people_light.x;
		AO = people_light.y;
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
	} else {
	// x 0..1 across, y 0 at the feet to 1 at the top of the head.
	vec2 p = vec2(UV.x, 1.0 - UV.y * cut);
	vec3 skin = mix(vec3(0.32, 0.2, 0.13), vec3(0.93, 0.74, 0.62), custom.a);
	// Per-person variety from the instance data, in the shares seen in tour
	// gallery photos: about half in a cap or visor, a third with their arms
	// folded, a quarter in shorts, a quarter with longer hair.
	bool cap = picks.x < 0.5;
	bool folded = picks.y < 0.33;
	bool shorts = picks.z < 0.25;
	bool long_hair = !cap && picks.w < 0.35;
	vec3 cap_col = picks2.x < 0.5 ? vec3(0.92) : (picks2.x < 0.75 ? vec3(0.1, 0.13, 0.25) : shirt * 0.8);
	vec3 hair_col = custom.a > 0.55 ? vec3(0.3, 0.21, 0.13) : vec3(0.08, 0.07, 0.06);
	if (picks2.y < 0.25) {
		hair_col = vec3(0.55, 0.53, 0.5);  // grey
	}

	float head = length((p - vec2(0.5, 0.925)) * vec2(1.0, 1.2)) - 0.08;
	float neck = box(p, vec2(0.5, 0.835), vec2(0.035, 0.03), 0.0);
	float torso = box(p, vec2(0.5, 0.67), vec2(0.15, 0.15), 0.05);
	// Arms hang to mid-thigh, or (folded) stop at the elbow with the
	// forearms across the chest.
	float arm_len = folded ? 0.09 : 0.17;
	float arm_y = folded ? 0.71 : 0.62;
	float arm_l = box(p, vec2(0.31, arm_y), vec2(0.045, arm_len), 0.04);
	float arm_r = box(p, vec2(0.69, arm_y), vec2(0.045, arm_len), 0.04);
	float fore = folded ? box(p, vec2(0.5, 0.645), vec2(0.2, 0.028), 0.025) : 1.0;
	float leg_l = box(p, vec2(0.432, 0.26), vec2(0.062, 0.26), 0.02);
	float leg_r = box(p, vec2(0.568, 0.26), vec2(0.062, 0.26), 0.02);
	float hips = box(p, vec2(0.5, 0.5), vec2(0.13, 0.04), 0.02);
	float brim = cap ? box(p, vec2(0.5, 0.932), vec2(0.088, 0.009), 0.006) : 1.0;
	float hair = long_hair ? box(p, vec2(0.5, 0.88), vec2(0.085, 0.055), 0.03) : 1.0;
	float body = min(min(min(torso, arm_l), min(arm_r, hips)), min(min(leg_l, leg_r), fore));
	float shape = min(min(min(head, neck), body), min(brim, hair));
	if (shape > 0.0) {
		discard;
	}
	vec3 col = shirt;
	bool legs = min(leg_l, min(leg_r, hips)) <= 0.0 && p.y < 0.53;
	if (legs) {
		col = custom.rgb;
		if (shorts && p.y < 0.33) {
			col = skin;  // bare legs below the shorts
		}
	}
	if (p.y < 0.035) {
		col = shorts ? vec3(0.85) : vec3(0.12);  // trainers with shorts, else dark shoes
	}
	if (hair <= 0.0 && head > 0.0) {
		col = hair_col;
	}
	if (head <= 0.0 || neck <= 0.0) {
		col = skin;
		if (p.y > 0.955 || (long_hair && p.y > 0.935)) {
			col = hair_col;
		}
		if (cap && p.y > 0.935) {
			col = cap_col;
		}
		// Shade under the brim, over the eyes.
		if (cap && p.y > 0.905 && p.y < 0.925) {
			col *= 0.72;
		}
	}
	if (brim <= 0.0) {
		col = cap_col * 0.9;
	}
	if (folded) {
		if (fore <= 0.0 && abs(p.x - 0.5) < 0.17) {
			col = skin * 0.95;  // forearms across the chest
		}
	} else if ((arm_l <= 0.0 || arm_r <= 0.0) && p.y < 0.5) {
		col = skin;  // hands below the sleeves
	}
	// Round the figure a little: lighter on the lit side, darker at the
	// edges, and the legs a touch darker towards the ground, as skylight
	// falls off under the body.
	float across = (p.x - 0.5) * 2.0;
	float lit = 0.85 + 0.2 * side * across - 0.15 * across * across;
	lit *= mix(0.78, 1.0, smoothstep(0.0, 0.5, p.y));
	ALBEDO = col * clamp(lit, 0.5, 1.1) * people_light.x;
	AO = people_light.y;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	}
}
