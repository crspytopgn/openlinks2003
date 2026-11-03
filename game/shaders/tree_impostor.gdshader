// Far 3D trees (TreeFactory): one quad that turns about the vertical to
// face the camera and shows the baked view of the tree nearest the
// camera's direction. The atlas has a row per tree variant and FRAMES
// views per row, frame k seen from azimuth k * 360 / frames in the tree's
// own frame. A second, half-size atlas holds the same views' normals
// (TreeFactory bakes both), so an impostor takes the sun clump by clump,
// pad by pad, as the full tree does: sunlit tops and sides, shaded
// undersides and hollows. Lit with the leaves' soft foliage light.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
// Baked as colour like the atlas, so read back through the same sRGB curve.
uniform sampler2D normals : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_normals = false;
uniform float frames = 8.0;
uniform float rows = 1.0;
uniform float row = 0.0;
// Drawn in a MultiMesh of a course's trees: the row comes from the
// instance's custom data, and inside tree_impostor_distance from the
// camera the instance collapses, as the full tree shows there, unless the
// custom data's green marks a tree that is only ever an impostor.
uniform bool instanced = false;
// Sky light through the leaves, as in tree_leaves.gdshader (the atlas holds
// plain albedo, so it is added here).
uniform float transmit = 0.0;
const vec3 TRANSMIT_TINT = vec3(0.7, 1.1, 0.6);

global uniform vec2 wind_vector;
global uniform float foliage_sway;
global uniform float tree_impostor_distance;

varying float frame;
varying vec3 tint;
// The billboard's axes in view space, to turn the baked normals.
varying vec3 axis_x;
varying vec3 axis_y;
varying vec3 axis_z;

#include "res://shaders/tree_tint.gdshaderinc"
varying float atlas_row;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	tint = crown_tint(root);
	vec3 to_camera = (vec4(INV_VIEW_MATRIX[3].xyz - root, 0.0) * MODEL_MATRIX).xyz;
	float azimuth = atan(to_camera.x, to_camera.z);
	frame = mod(round(azimuth / (6.2831853 / frames)), frames);
	atlas_row = instanced ? floor(INSTANCE_CUSTOM.r * rows) : row;
	if (instanced && INSTANCE_CUSTOM.g < 0.5 && distance(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < tree_impostor_distance) {
		VERTEX = vec3(0.0);
	}
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
	axis_x = normalize(MODELVIEW_MATRIX[0].xyz);
	axis_y = normalize(MODELVIEW_MATRIX[1].xyz);
	axis_z = normalize(MODELVIEW_MATRIX[2].xyz);
}

void fragment() {
	vec2 uv = vec2((frame + clamp(UV.x, 0.002, 0.998)) / frames, (atlas_row + clamp(UV.y, 0.002, 0.998)) / rows);
	vec4 c = texture(atlas, uv);
	// discard rather than ALPHA, which makes the Compatibility glow flare
	// (see tree_leaves.gdshader).
	if (c.a < 0.5) {
		discard;
	}
	// The tree's own leaf colour; the trunk at the bottom is left alone.
	c.rgb *= mix(vec3(1.0), tint, smoothstep(0.75, 0.55, UV.y));
	// Aerial perspective: far tree lines lose colour and lift towards the
	// sky's blue, layer behind layer, so the distance reads as depth.
	float far = smoothstep(60.0, 350.0, length(VERTEX)) * 0.6;
	vec3 haze = vec3(dot(c.rgb, vec3(0.3, 0.59, 0.11))) * vec3(0.85, 0.97, 1.15) + vec3(0.03, 0.05, 0.08);
	// The crown shades its own trunk and the ground under it: the lower
	// part of a tree (and the floor of a wood) reads dark, as in photos.
	c.rgb *= mix(0.45, 1.0, smoothstep(0.08, 0.45, 1.0 - UV.y));
	c.rgb = mix(c.rgb, haze, far);
	ALBEDO = c.rgb;
	EMISSION = c.rgb * transmit * TRANSMIT_TINT * (1.0 - far);
	BACKLIGHT = c.rgb * 0.4;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	vec3 n = normalize(vec3((UV.x - 0.5) * 1.4, (0.5 - UV.y) * 1.0 + 0.4, 1.0));
	if (has_normals) {
		vec3 baked = texture(normals, uv).rgb * 2.0 - 1.0;
		// Gaps the half-size atlas blurs into the edge come out short:
		// fall back to the rounded normal there.
		n = normalize(mix(n, baked, smoothstep(0.3, 0.7, length(baked))));
	}
	NORMAL = normalize(axis_x * n.x + axis_y * n.y + axis_z * n.z);
}

// The leaves' soft foliage light (tree_leaves.gdshader), so a tree keeps
// its light when it turns into its impostor.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.5) / 1.5, 0.0, 1.0);
	float through = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 2.0) * 0.7 + clamp(-ndl, 0.0, 1.0) * 0.25;
	vec3 glow = vec3(0.95, 1.05, 0.85);
	DIFFUSE_LIGHT += (wrap + through * glow) * ATTENUATION * LIGHT_COLOR / PI;
}
