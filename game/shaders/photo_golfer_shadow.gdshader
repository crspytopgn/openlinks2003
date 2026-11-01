// The photo golfer's shadow (PhotoGolfer): the same cut-out frame on a card
// turned to face the sun, drawn only into the shadow map, so the filmed
// golfer casts a matching moving shadow on the grass.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sheet : filter_linear_mipmap, repeat_disable;
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	ALPHA = texture(sheet, rect.xy + UV * rect.zw).a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
