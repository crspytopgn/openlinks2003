// Bark of the 3D trees (TreeFactory). UV is in metres (around, along the
// branch); the free bark photo tiles every 1.5 m. Without it, a plain
// streaky brown. With `bake` on, the plain albedo goes out as emission for
// the impostor atlas. The trunk and branches lean and rock with the wind
// (tree_wind.gdshaderinc), exactly as the leaves do.
shader_type spatial;

uniform sampler2D bark_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
// A photoscanned tree (ScannedTree): UV is the scan's own, and COLOR.r
// picks the branch texture over the trunk's.
uniform bool scanned = false;
uniform sampler2D branch_color : source_color, filter_linear_mipmap, repeat_enable;
uniform bool bake = false;
uniform bool bake_normal = false; // see tree_leaves.gdshader
uniform bool instanced = false; // see tree_leaves.gdshader
uniform vec3 tint : source_color = vec3(0.33, 0.25, 0.19);
// Where the bark goes into the crown's shade (metres up the tree), and a
// tint taken on higher up the stem (a pine's orange upper bark).
uniform float shade_from = 1.8;
uniform float shade_to = 4.5;
uniform vec3 upper_tint = vec3(1.0);
uniform float upper_from = 100.0;
uniform float upper_to = 101.0;

global uniform float tree_impostor_distance;
// Scanned trees in a MultiMesh draw in bands (TreeFactory.LITE_DISTANCE):
// 0 every distance up to the impostors, 1 the full mesh up to
// tree_lite_distance, 2 the lite mesh from there to the impostors.
global uniform float tree_lite_distance;
uniform int band = 0;
global uniform vec2 wind_vector;
global uniform float foliage_sway;

#include "res://shaders/tree_wind.gdshaderinc"

// How far up the tree (metres, the tree's own frame): limbs and the trunk
// inside the crown sit in the leaves' shade, so they read darker than the
// sunlit lower trunk, rather than as pale poles among the leaves.
varying float up;
varying float branch;

void vertex() {
	up = VERTEX.y;
	branch = scanned ? COLOR.r : 0.0;
	float cam_d = distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	if (instanced && (cam_d > tree_impostor_distance || (band == 1 && cam_d > tree_lite_distance) || (band == 2 && cam_d < tree_lite_distance))) {
		VERTEX = vec3(0.0);
	} else if (!bake) {
		VERTEX += tree_bend(VERTEX, MODEL_MATRIX, foliage_sway, wind_vector, TIME);
	}
}

void fragment() {
	vec2 uv = scanned ? UV : UV / 1.5;
	vec3 col;
	if (scanned && branch > 0.5) {
		col = texture(branch_color, uv).rgb;
	} else if (has_texture) {
		col = texture(bark_color, uv).rgb;
		if (!bake) {
			NORMAL_MAP = texture(bark_normal, uv).rgb;
		}
	} else {
		col = tint * (0.8 + 0.3 * sin(UV.x * 40.0 + sin(UV.y * 3.0) * 2.0));
	}
	col *= mix(vec3(1.0), upper_tint, smoothstep(upper_from, upper_to, up));
	col *= mix(1.0, 0.5, smoothstep(shade_from, shade_to, up));
	if (bake_normal) {
		ALBEDO = vec3(0.0);
		EMISSION = normalize(NORMAL) * 0.5 + 0.5;
	} else if (bake) {
		ALBEDO = vec3(0.0);
		EMISSION = col * 0.8;
	} else {
		ALBEDO = col;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
