// Far 3D trees (TreeFactory): one quad that turns about the vertical to
// face the camera and shows the baked view of the tree nearest the
// camera's direction. The atlas has a row per tree variant and FRAMES
// views per row, frame k seen from azimuth k * 360 / frames in the tree's
// own frame. Lit with a rounded normal so it shades like the crown of the
// full tree.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform float rows = 1.0;
uniform float row = 0.0;

global uniform vec2 wind_vector;
global uniform float foliage_sway;

varying float frame;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 to_camera = (vec4(INV_VIEW_MATRIX[3].xyz - root, 0.0) * MODEL_MATRIX).xyz;
	float azimuth = atan(to_camera.x, to_camera.z);
	frame = mod(round(azimuth / (6.2831853 / frames)), frames);
	if (foliage_sway > 0.0) {
		float phase = dot(root.xz, vec2(0.37, 0.23));
		float speed = min(length(wind_vector), 15.0);
		float gust = sin(TIME * 0.9 + phase) * 0.6 + sin(TIME * 2.1 + phase * 1.7) * 0.4;
		VERTEX.x += (0.004 + speed * 0.0015) * gust * foliage_sway * VERTEX.y * VERTEX.y;
	}
	// Turn about the vertical to face the camera, keeping the scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(s, 0.0, 0.0, 0.0),
		vec4(0.0, s, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = vec2((frame + clamp(UV.x, 0.002, 0.998)) / frames, (row + clamp(UV.y, 0.002, 0.998)) / rows);
	vec4 c = texture(atlas, uv);
	// discard rather than ALPHA, which makes the Compatibility glow flare
	// (see tree_leaves.gdshader).
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	BACKLIGHT = c.rgb * 0.4;
	ROUGHNESS = 0.85;
	NORMAL = normalize(vec3((UV.x - 0.5) * 1.4, (0.5 - UV.y) * 1.0 + 0.4, 1.0));
}
