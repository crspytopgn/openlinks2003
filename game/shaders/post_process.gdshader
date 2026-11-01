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
// Heat shimmer: on a warm day the air over the course boils, and a long
// lens looking down the hole shows it as a rippling wobble on the far
// fairway, the green and the tree line, never on the ground at your feet.
// The 3D view's depth isn't readable here in Compatibility, so distance is
// worked out from the row's angle below the level horizon and the
// camera's height over the ground (flat ground assumed).
uniform float shimmer = 0.0; // displacement in pixels at 1080p, 0 = off
uniform float horizon_y = 0.5; // screen y (0 top, 1 bottom) of the level horizon
uniform float fov_radians = 0.7; // the camera's vertical field of view
uniform float eye_height = 2.0; // metres above the ground
// The learned grade (tools/grade/fit_grade.py): a 32x32x32 colour lookup
// fitted so the sky, turf, trees and sand of our renders land on the
// colours measured in real golf photos. Laid out as 32 slices of 32x32
// side by side (1024x32): red across a slice, green down, blue by slice.
uniform sampler2D grade_lut : filter_linear, repeat_disable;
uniform float lut_mix = 0.0; // 0 = off

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 lut_lookup(vec3 c) {
	const float N = 32.0;
	c = clamp(c, 0.0, 1.0);
	float b = c.b * (N - 1.0);
	float b0 = floor(b);
	float b1 = min(b0 + 1.0, N - 1.0);
	vec2 at = vec2((c.r * (N - 1.0) + 0.5) / (N * N), (c.g * (N - 1.0) + 0.5) / N);
	vec3 lo = texture(grade_lut, at + vec2(b0 / N, 0.0)).rgb;
	vec3 hi = texture(grade_lut, at + vec2(b1 / N, 0.0)).rgb;
	return mix(lo, hi, b - b0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (shimmer > 0.0) {
		float below = (uv.y - horizon_y) * fov_radians; // radians below level
		float dist = below > 0.0 ? eye_height / tan(max(below, 1e-4)) : 1e4;
		// From about 120 m out, and a few degrees up into the trees and
		// hills; the sky above is smooth, so nothing shows there anyway.
		float heat = smoothstep(120.0, 450.0, dist) * (1.0 - smoothstep(0.02, 0.07, -below));
		if (heat > 0.0) {
			// Cells of about 12 by 5 pixels at 1080p (the air lies in thin
			// layers) rising slowly, as hot air does.
			float scale = 1080.0 * SCREEN_PIXEL_SIZE.y;
			vec2 q = FRAGCOORD.xy * scale / vec2(12.0, 5.0) + vec2(TIME * 0.7, TIME * 3.0);
			vec2 wobble = vec2(value_noise(q), value_noise(q * 1.7 + vec2(41.0, 17.0))) - 0.5;
			uv += wobble * vec2(1.0, 0.5) * shimmer * heat * SCREEN_PIXEL_SIZE / scale;
		}
	}
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
	if (lut_mix > 0.0) {
		c = mix(c, lut_lookup(c), lut_mix);
	}
	vec2 d = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.15, 0.75, dot(d, d) * 2.0);
	c += (hash(FRAGCOORD.xy + fract(TIME) * 913.0) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
