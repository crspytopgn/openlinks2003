// The look effects drawn over the 3D view, like a ReShade preset: contrast-
// adaptive sharpening (after AMD's CAS), colour grading, vignette and film
// grain. One full-screen pass that reads the rendered frame, so it works the
// same in Forward+ and in Compatibility (the web build). PostProcess sets
// the uniforms from GraphicsSettings.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float sharpen = 0.0; // 0 to 1
uniform float exposure = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform vec3 tint = vec3(1.0); // white balance
uniform vec3 shadow_tint = vec3(1.0); // colour of the darks, for the film look
uniform float vignette = 0.0;
uniform float grain = 0.0;
uniform float curve = 0.0; // filmic S-curve: deeper shadows, brighter highlights

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (sharpen > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 n = texture(screen_tex, uv + vec2(0.0, -px.y)).rgb;
		vec3 s = texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
		vec3 e = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
		vec3 w = texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb;
		vec3 lo = min(c, min(min(n, s), min(e, w)));
		vec3 hi = max(c, max(max(n, s), max(e, w)));
		// Sharpen less where the neighbourhood already has strong contrast,
		// so edges don't ring.
		vec3 amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-4)), 0.0, 1.0));
		vec3 k = -amp / mix(8.0, 5.0, sharpen);
		c = clamp((c + (n + s + e + w) * k) / (1.0 + 4.0 * k), 0.0, 1.0);
	}
	c *= exposure * tint;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c = mix(c * shadow_tint, c, smoothstep(0.0, 0.5, luma));
	c = (c - 0.5) * contrast + 0.5;
	if (curve > 0.0) {
		// On luminance, so colours keep their hue.
		float l = max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
		float lc = clamp(l, 0.0, 1.0);
		float s_curve = lc * lc * (3.0 - 2.0 * lc);
		c *= mix(l, s_curve, curve) / l;
	}
	vec2 d = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.15, 0.75, dot(d, d) * 2.0);
	c += (hash(FRAGCOORD.xy + fract(TIME) * 913.0) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
