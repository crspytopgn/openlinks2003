// The photo golfer's shadow (PhotoGolfer): the same cut-out frame on a card
// turned to face the sun, drawn only into the shadow map, so the filmed
// golfer casts a matching moving shadow on the grass.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sheet : filter_linear_mipmap, repeat_disable;

void fragment() {
	ALPHA = texture(sheet, UV).a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
