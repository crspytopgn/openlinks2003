// Bark of the 3D trees (TreeFactory). UV is in metres (around, along the
// branch); the free bark photo tiles every 1.5 m. Without it, a plain
// streaky brown. With `bake` on, the plain albedo goes out as emission for
// the impostor atlas.
shader_type spatial;

uniform sampler2D bark_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform bool bake = false;
uniform bool instanced = false; // see tree_leaves.gdshader
uniform vec3 tint : source_color = vec3(0.33, 0.25, 0.19);

global uniform float tree_impostor_distance;

void vertex() {
	if (instanced && distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) > tree_impostor_distance) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec2 uv = UV / 1.5;
	vec3 col;
	if (has_texture) {
		col = texture(bark_color, uv).rgb;
		if (!bake) {
			NORMAL_MAP = texture(bark_normal, uv).rgb;
		}
	} else {
		col = tint * (0.8 + 0.3 * sin(UV.x * 40.0 + sin(UV.y * 3.0) * 2.0));
	}
	if (bake) {
		ALBEDO = vec3(0.0);
		EMISSION = col * 0.8;
	} else {
		ALBEDO = col;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
