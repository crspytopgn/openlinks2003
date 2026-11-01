shader_type spatial;
// The free golfer's hair cards (GolferSurface.hair): the look pack's grey
// strand texture in the hair colour, with more contrast between strands
// and the gaps between them (so it reads as hair, not a painted helmet),
// a soft sheen along the strands, light through thin edges, and
// antialiased card edges where MSAA is on.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.3, 0.25, 0.2, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float contrast = 1.8;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec4 t = texture(texture_albedo, UV);
	float strand = pow(t.r, contrast);
	ALBEDO = albedo.rgb * mix(0.45, 1.2, strand);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ROUGHNESS = roughness + (1.0 - strand) * 0.25;
	SPECULAR = specular * mix(0.5, 1.0, strand);
	RIM = 0.3;
	RIM_TINT = 0.6;
	BACKLIGHT = albedo.rgb * 0.3;
}
