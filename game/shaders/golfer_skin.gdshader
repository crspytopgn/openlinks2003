shader_type spatial;
// The free golfer's skin (GolferSurface.skin_shader): the look pack's skin
// texture tinted to the player's tone, then varied the way real skin is,
// from the pack's region map (tools/golfer/skin_regions.py):
// - R flush: redder cheeks, nose, ears and knuckles;
// - G beard: stubble (dots in the hair colour) and a shaved man's shadow;
// - B lips: deeper and redder, a little glossier;
// - A shine: an oilier T-zone that catches the sun.
// Pores are a fine tiled normal map. On the face, a real scanned face's
// detail (tools/golfer/face_detail.py) is laid over it: its fine lines,
// creases and pores as a normal map and its uneven colour as a multiplier
// (0.5 is none), over `face_rect` of the body's uvs, at three times the
// body texture's resolution. Light scatters under the skin on Forward+
// (Compatibility ignores it).
// light() wraps the sun round the shadow side, red furthest, as light
// scattered under real skin does, so the shade side of a face stays warm
// instead of turning grey. The sky's fill is warmed the same way: the
// albedo is warmed by `warmth` and the sun's light divided by it again.
render_mode blend_mix, depth_draw_opaque, cull_back, sss_mode_skin;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D regions : hint_default_black, filter_linear_mipmap;
uniform sampler2D pores : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stubble_dots : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 beard_colour : source_color = vec4(0.2, 0.15, 0.12, 1.0);
// 0 clean-shaven (with a faint shadow for men) to 1 a few days' growth.
uniform float stubble : hint_range(0.0, 1.0) = 0.0;
// The blue-grey under a shaved man's skin, 0 for women.
uniform float shave_shadow : hint_range(0.0, 1.0) = 0.0;
uniform float flush_strength : hint_range(0.0, 2.0) = 1.0;
uniform float lip_strength : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D face_albedo : hint_default_white, filter_linear_mipmap;
uniform sampler2D face_normal : hint_normal, filter_linear_mipmap;
// The face detail's place in the body's uvs (min u, min v, max u, max v);
// strengths 0 turn it off.
uniform vec4 face_rect = vec4(2.0, 2.0, 3.0, 3.0);
uniform float face_colour : hint_range(0.0, 2.0) = 0.0;
uniform float face_relief : hint_range(0.0, 3.0) = 0.0;
uniform float pore_scale = 40.0;
uniform float pore_strength = 0.35;
uniform float stubble_scale = 110.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.52;
uniform float specular : hint_range(0.0, 1.0) = 0.38;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim : hint_range(0.0, 1.0) = 0.12;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.6;
// How far each colour wraps past the terminator (red, green, blue).
uniform vec3 wrap = vec3(0.5, 0.24, 0.18);
uniform vec3 warmth = vec3(1.12, 0.96, 0.84);
// Real skin is never one even colour: faint blotches of redness and
// lighter and darker patches, a few millimetres to centimetres across.
uniform float mottle = 0.5;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec3 c = texture(texture_albedo, UV).rgb * albedo.rgb;
	vec4 r = texture(regions, UV);
	vec2 fuv = (UV - face_rect.xy) / (face_rect.zw - face_rect.xy);
	// Sampled everywhere (no branch, so mipmaps stay right at its edge),
	// used on the face's rect only.
	vec2 inside = step(vec2(0.0), fuv) * step(fuv, vec2(1.0));
	float on_face = inside.x * inside.y;
	c *= mix(vec3(1.0), texture(face_albedo, fuv).rgb * 2.0, face_colour * on_face);
	vec2 face_n = (texture(face_normal, fuv).rg * 2.0 - 1.0) * face_relief * on_face;
	// Blood under thin skin: less green and blue, more on lighter skin.
	float light = clamp(dot(albedo.rgb, vec3(0.33)) * 1.4, 0.35, 1.0);
	c *= mix(vec3(1.0), vec3(1.04, 0.84, 0.82), r.r * flush_strength * light);
	c *= mix(vec3(1.0), vec3(0.86, 0.6, 0.6), r.b * lip_strength);
	float blotch = vnoise(UV * 90.0) * 0.6 + vnoise(UV * 260.0) * 0.4;
	float patch = vnoise(UV * 35.0 + 13.0);
	c *= mix(vec3(1.0), vec3(1.05, 0.93, 0.92), smoothstep(0.45, 0.85, blotch) * mottle * light);
	c *= 1.0 + (patch - 0.5) * 0.08 * mottle;
	float beard = r.g;
	c *= mix(vec3(1.0), vec3(0.74, 0.76, 0.8), beard * shave_shadow * light);
	float dots = texture(stubble_dots, UV * stubble_scale).r;
	float hairs = clamp(beard * stubble * (0.9 + dots * 1.5), 0.0, 0.95);
	c = mix(c, beard_colour.rgb, hairs);
	ALBEDO = c * warmth;
	ROUGHNESS = clamp(roughness - r.a * 0.16 - r.b * 0.14 + hairs * 0.25, 0.2, 1.0);
	SPECULAR = specular + r.a * 0.08;
	vec2 p = (texture(pores, UV * pore_scale).rg * 2.0 - 1.0) * pore_strength * (1.0 - r.b);
	vec2 n = (p + face_n) * (1.0 - hairs);
	NORMAL_MAP = normalize(vec3(n, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	SSS_STRENGTH = sss_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 d = clamp((vec3(ndl) + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += d / warmth * ATTENUATION * LIGHT_COLOR / PI;
	// The skin's sheen (GGX, Schlick Fresnel) and a faint rim at grazing light.
	float nl = max(ndl, 0.0);
	float nv = max(dot(NORMAL, VIEW), 1e-3);
	vec3 h = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, h), 0.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float den = nh * nh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * den * den);
	float k = a * 0.5;
	float vis = 0.25 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k));
	float f0 = 0.08 * specular;
	float fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(LIGHT, h), 0.0), 5.0);
	SPECULAR_LIGHT += nl * dist * vis * fres * ATTENUATION * LIGHT_COLOR;
	float r = pow(1.0 - nv, 4.0) * rim * clamp(ndl + 0.3, 0.0, 1.0);
	DIFFUSE_LIGHT += r * mix(vec3(1.0), ALBEDO, rim_tint) / max(ALBEDO, vec3(0.05)) * ATTENUATION * LIGHT_COLOR / PI;
}
