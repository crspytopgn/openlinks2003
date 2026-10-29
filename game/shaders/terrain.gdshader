// Ground shading for course terrain. The mesh carries the surface colour per
// vertex (fairway, rough, sand...); this adds large-scale colour variation
// and close-up grain so the ground doesn't look flat-shaded. With the free
// photo textures (FreeAssets) the grain and bumps come from them instead:
// UV2 holds the rough and sand weights per vertex, grass is the rest, and
// each texture is divided by its mean colour so the vertex colour still sets
// the tone. Works in both Forward+ and Compatibility (the web build).
shader_type spatial;
render_mode cull_back;

uniform float variation = 0.16; // large patches of lighter and darker grass
uniform float grain = 0.12; // fine detail near the camera
uniform float grain_fade_start = 15.0;
uniform float grain_fade_end = 70.0;
uniform float bump = 0.35; // strength of the close-up normal detail

uniform bool textured = false;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : filter_linear_mipmap, repeat_enable;
// Linear mean colour of each albedo texture.
uniform vec3 grass_mean = vec3(0.5);
uniform vec3 rough_mean = vec3(0.5);
uniform vec3 sand_mean = vec3(0.5);
uniform float texture_metres = 2.5; // one tile of the near texture
uniform float texture_strength = 0.85;
// How much of the photo's own colour shows through (at the vertex colour's
// brightness), which tames the flat, saturated surface colours.
uniform float photo_mix = 0.5;

varying vec3 world_pos;
varying vec2 weights; // rough, sand

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
	weights = UV2;
}

// A texture sampled at two scales, so its repeat is hard to see.
vec4 two_scale(sampler2D tex, vec2 uv) {
	return mix(texture(tex, uv), texture(tex, uv * 0.137 + vec2(0.31, 0.71)), 0.35);
}

void fragment() {
	vec2 p = world_pos.xz;
	float patches = fbm(p * 0.035) - 0.5;
	float close_up = 1.0 - smoothstep(grain_fade_start, grain_fade_end, length(VERTEX));
	float fine = (value_noise(p * 2.7) - 0.5) + 0.5 * (value_noise(p * 7.3) - 0.5);

	// The mesh colours are authored in sRGB; lighting works in linear.
	vec3 c = COLOR.rgb;
	vec3 base = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	vec3 col = base * (1.0 + patches * variation * 2.0);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;

	if (textured) {
		vec2 uv = p / texture_metres;
		float w_sand = clamp(weights.y, 0.0, 1.0);
		float w_rough = clamp(weights.x, 0.0, 1.0) * (1.0 - w_sand);
		float w_grass = 1.0 - w_sand - w_rough;
		vec3 g = two_scale(grass_albedo, uv).rgb;
		vec3 r = two_scale(rough_albedo, uv).rgb;
		vec3 s = two_scale(sand_albedo, uv).rgb;
		vec3 detail = w_grass * g / max(grass_mean, vec3(0.02)) + w_rough * r / max(rough_mean, vec3(0.02))
			+ w_sand * s / max(sand_mean, vec3(0.02));
		vec3 photo = w_grass * g + w_rough * r + w_sand * s;
		vec3 photo_mean = w_grass * grass_mean + w_rough * rough_mean + w_sand * sand_mean;
		const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
		vec3 photo_toned = photo * dot(col, LUMA) / max(dot(photo_mean, LUMA), 0.02);
		// Far away the texture only adds noise and shows its repeat.
		float strength = texture_strength * mix(0.35, 1.0, 1.0 - smoothstep(40.0, 250.0, length(VERTEX)));
		col = mix(col * mix(vec3(1.0), detail, strength), photo_toned, photo_mix * strength);
		vec3 n = w_grass * two_scale(grass_normal, uv).rgb + w_rough * two_scale(rough_normal, uv).rgb
			+ w_sand * two_scale(sand_normal, uv).rgb;
		n = n * 2.0 - 1.0;
		// The textures lie flat on the ground: u along +x, v along +z.
		vec3 tilt = (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz;
		NORMAL = normalize(NORMAL + tilt * strength);
	} else {
		col *= 1.0 + fine * grain * close_up;
		// Close-up bumpiness from the slope of the fine noise.
		float e = 0.15;
		float hx = value_noise((p + vec2(e, 0.0)) * 2.7) - value_noise((p - vec2(e, 0.0)) * 2.7);
		float hz = value_noise((p + vec2(0.0, e)) * 2.7) - value_noise((p - vec2(0.0, e)) * 2.7);
		vec3 tilt = (VIEW_MATRIX * vec4(-hx, 0.0, -hz, 0.0)).xyz;
		NORMAL = normalize(NORMAL + tilt * bump * close_up);
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
