shader_type spatial;
// The free golfer's skin (GolferSurface.skin_shader): the look pack's skin
// texture tinted to the player's tone, then varied the way real skin is,
// from the pack's region map (tools/golfer/skin_regions.py):
// - R flush: redder cheeks, nose, ears and knuckles;
// - G beard: stubble (dots in the hair colour) and a shaved man's shadow;
// - B lips: deeper and redder, a little glossier;
// - A shine: an oilier T-zone that catches the sun.
// Pores are a fine tiled normal map. Light scatters under the skin on
// Forward+ (Compatibility ignores it).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, sss_mode_skin;

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
uniform float pore_scale = 40.0;
uniform float pore_strength = 0.35;
uniform float stubble_scale = 110.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.52;
uniform float specular : hint_range(0.0, 1.0) = 0.38;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rim : hint_range(0.0, 1.0) = 0.12;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec3 c = texture(texture_albedo, UV).rgb * albedo.rgb;
	vec4 r = texture(regions, UV);
	// Blood under thin skin: less green and blue, more on lighter skin.
	float light = clamp(dot(albedo.rgb, vec3(0.33)) * 1.4, 0.35, 1.0);
	c *= mix(vec3(1.0), vec3(1.04, 0.84, 0.82), r.r * flush_strength * light);
	c *= mix(vec3(1.0), vec3(0.86, 0.6, 0.6), r.b * lip_strength);
	float beard = r.g;
	c *= mix(vec3(1.0), vec3(0.74, 0.76, 0.8), beard * shave_shadow * light);
	float dots = texture(stubble_dots, UV * stubble_scale).r;
	float hairs = clamp(beard * stubble * (0.9 + dots * 1.5), 0.0, 0.95);
	c = mix(c, beard_colour.rgb, hairs);
	ALBEDO = c;
	ROUGHNESS = clamp(roughness - r.a * 0.16 - r.b * 0.14 + hairs * 0.25, 0.2, 1.0);
	SPECULAR = specular + r.a * 0.08;
	NORMAL_MAP = texture(pores, UV * pore_scale).rgb;
	NORMAL_MAP_DEPTH = pore_strength * (1.0 - r.b) * (1.0 - hairs);
	SSS_STRENGTH = sss_strength;
	RIM = rim;
	RIM_TINT = rim_tint;
}
