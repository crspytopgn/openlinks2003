shader_type spatial;
// Eyebrows and eyelashes (GolferSurface.fine_hair): the look pack's hair
// card texture with a soft edge rather than a hard cut-out, so they read
// as fine hair at a close-up and fade at a distance as real ones do.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
// The card's alpha that is half covered, and how soft the edge is.
uniform float cutoff = 0.2;
uniform float softness = 2.5;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// Brows: break the card's solid shape into fine hairs (0 for lashes,
// whose cards are drawn as hairs already).
uniform float strands : hint_range(0.0, 1.0) = 0.0;
uniform vec2 strand_scale = vec2(140.0, 9.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec4 t = texture(texture_albedo, UV);
	ALBEDO = t.rgb * albedo.rgb;
	float a = smoothstep(cutoff / softness, cutoff * softness, t.a);
	float hairs = noise(UV * strand_scale) * 0.6 + noise(UV * strand_scale * 2.3 + 7.0) * 0.4;
	a *= mix(1.0, smoothstep(0.25, 0.7, hairs), strands);
	ALPHA = a * opacity;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
