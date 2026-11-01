// The photo golfer (PhotoGolfer): one frame of a filmed golfer, cut out of
// its background, drawn on a card that turns about the vertical to face the
// camera. `rect` picks the frame out of its sheet (UV offset and size). The
// picture keeps the light it was filmed in, so it is drawn unshaded, scaled
// by `exposure` and warmed or cooled by `tint` to sit in the scene's light.
// The soft cut-out edge blends; the solid inside writes depth so the ball,
// grass and shadows sort against it. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float exposure = 1.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	vec4 c = texture(sheet, rect.xy + UV * rect.zw);
	ALBEDO = c.rgb * exposure * tint;
	ALPHA = c.a;
}
