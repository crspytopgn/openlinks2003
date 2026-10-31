// The photographed cloud sky (FreeAssets.sky) for the Photoreal lighting,
// tinted for the time of day (Scenery): cooler and paler in the morning,
// warm towards evening, with a glow round a low sun. Works in Forward+ and
// Compatibility.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float energy = 0.8;
uniform vec3 tint : source_color = vec3(1.0);
// Warm light round the sun, strongest near the horizon (a low sun).
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float glow = 0.0;
// The horizon's own haze colour, which a low sun warms.
uniform vec3 horizon_tint : source_color = vec3(1.0);

void sky() {
	vec3 c = texture(panorama, SKY_COORDS).rgb * energy;
	float low = 1.0 - smoothstep(0.0, 0.35, abs(EYEDIR.y));
	c *= mix(tint, tint * horizon_tint, low);
	if (glow > 0.0 && LIGHT0_ENABLED) {
		float toward = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float halo = pow(toward, 8.0) * 0.6 + pow(toward, 64.0) * 1.5;
		c += glow_color * glow * halo * (0.4 + 0.6 * low);
	}
	COLOR = c;
}
