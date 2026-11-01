// Crowd cards (Gallery): the spectators further from the cameras, past the
// 3D people. Each is one camera-facing quad (turning about the vertical
// only, so people stay upright) that draws a standing person in silhouette:
// head and hair or cap, shirt and arms, trousers and legs. The shirt
// colour is the MultiMesh instance colour; INSTANCE_CUSTOM carries the
// trousers (rgb) and the skin tone (a, dark to light). Hundreds of them are
// one draw call. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;

uniform vec3 light_dir = vec3(0.4, 0.8, 0.3);

varying vec3 shirt;
varying vec4 custom;
varying float side;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = vec3(cam.x - origin.x, 0.0, cam.z - origin.z);
	to_cam = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 world = origin + right * VERTEX.x * height + vec3(0.0, VERTEX.y * height, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
	shirt = COLOR.rgb;
	custom = INSTANCE_CUSTOM;
	// Which way the light falls across the figure, for a little modelling.
	side = dot(normalize(vec3(light_dir.x, 0.0, light_dir.z)), right);
}

float box(vec2 p, vec2 c, vec2 h, float r) {
	vec2 d = abs(p - c) - h + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	// x 0..1 across, y 0 at the feet to 1 at the top of the head.
	vec2 p = vec2(UV.x, 1.0 - UV.y);
	vec3 skin = mix(vec3(0.32, 0.2, 0.13), vec3(0.93, 0.74, 0.62), custom.a);
	float head = length((p - vec2(0.5, 0.925)) * vec2(1.0, 1.25)) - 0.075;
	float neck = box(p, vec2(0.5, 0.835), vec2(0.035, 0.03), 0.0);
	float torso = box(p, vec2(0.5, 0.67), vec2(0.15, 0.15), 0.05);
	float arm_l = box(p, vec2(0.31, 0.62), vec2(0.045, 0.17), 0.04);
	float arm_r = box(p, vec2(0.69, 0.62), vec2(0.045, 0.17), 0.04);
	float leg_l = box(p, vec2(0.43, 0.26), vec2(0.06, 0.26), 0.02);
	float leg_r = box(p, vec2(0.57, 0.26), vec2(0.06, 0.26), 0.02);
	float hips = box(p, vec2(0.5, 0.5), vec2(0.13, 0.04), 0.02);
	float body = min(min(min(torso, arm_l), min(arm_r, hips)), min(leg_l, leg_r));
	float shape = min(min(head, neck), body);
	if (shape > 0.0) {
		discard;
	}
	vec3 col = shirt;
	if (min(leg_l, min(leg_r, hips)) <= 0.0 && p.y < 0.53) {
		col = custom.rgb;
	}
	if (p.y < 0.035) {
		col = vec3(0.12);  // shoes
	}
	if (head <= 0.0 || neck <= 0.0) {
		col = skin;
		if (p.y > 0.955) {
			col = custom.a > 0.55 ? vec3(0.25, 0.18, 0.12) : vec3(0.08, 0.07, 0.06);
		}
	}
	if ((arm_l <= 0.0 || arm_r <= 0.0) && p.y < 0.5) {
		col = skin;  // hands below the sleeves
	}
	// Round the figure a little: lighter on the lit side, darker at the edges.
	float across = (p.x - 0.5) * 2.0;
	float lit = 0.85 + 0.2 * side * across - 0.15 * across * across;
	ALBEDO = col * clamp(lit, 0.6, 1.1);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
