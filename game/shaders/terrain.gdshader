// Ground shading for course terrain. The mesh carries the surface colour per
// vertex (fairway, rough, sand...); this adds large-scale colour variation
// and close-up grain so the ground doesn't look flat-shaded. Works in both
// Forward+ and Compatibility (the web build).
shader_type spatial;
render_mode cull_back;

uniform float variation = 0.16; // large patches of lighter and darker grass
uniform float grain = 0.12; // fine detail near the camera
uniform float grain_fade_start = 15.0;
uniform float grain_fade_end = 70.0;
uniform float bump = 0.35; // strength of the close-up normal detail

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
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float patches = fbm(p * 0.035) - 0.5;
	float close_up = 1.0 - smoothstep(grain_fade_start, grain_fade_end, length(VERTEX));
	float fine = (value_noise(p * 2.7) - 0.5) + 0.5 * (value_noise(p * 7.3) - 0.5);

	vec3 col = COLOR.rgb * (1.0 + patches * variation * 2.0 + fine * grain * close_up);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;

	// Close-up bumpiness from the slope of the fine noise.
	float e = 0.15;
	float hx = value_noise((p + vec2(e, 0.0)) * 2.7) - value_noise((p - vec2(e, 0.0)) * 2.7);
	float hz = value_noise((p + vec2(0.0, e)) * 2.7) - value_noise((p - vec2(0.0, e)) * 2.7);
	vec3 tilt = (VIEW_MATRIX * vec4(-hx, 0.0, -hz, 0.0)).xyz;
	NORMAL = normalize(NORMAL + tilt * bump * close_up);
}
