// Leaf cards of the 3D trees (TreeFactory). Each card holds a grid of
// leaves, each turned and picked at random, from the free leaf texture
// (a 3 x 2 set of photographed leaves with an opacity map) or, without it,
// simple leaf shapes; pine cards draw needle sprigs. Mesh normals point out
// from the middle of the crown, so both faces of a card take the crown's
// light. COLOR: r random tint, g how far out in the crown (inner leaves are
// shaded), b how much the card sways. With `bake` on, the plain albedo goes
// out as emission for the impostor atlas.
// No specular_disabled: in Compatibility it drops the sun (see grass).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D leaf_opacity : filter_linear_mipmap, repeat_disable;
uniform bool has_texture = false;
uniform bool needles = false;
uniform bool bake = false;
// Drawn in a MultiMesh of a course's trees: beyond tree_impostor_distance
// from the camera an instance collapses to a point and its impostor shows.
uniform bool instanced = false;
uniform vec2 leaf_grid = vec2(3.0, 2.0); // leaves in the leaf texture
uniform vec3 leaf_dark : source_color = vec3(0.16, 0.27, 0.08);
uniform vec3 leaf_light : source_color = vec3(0.36, 0.47, 0.16);
uniform vec3 needle_dark : source_color = vec3(0.07, 0.17, 0.08);
uniform vec3 needle_light : source_color = vec3(0.16, 0.29, 0.12);

global uniform vec2 wind_vector;
global uniform float foliage_sway;
global uniform float tree_impostor_distance;

varying vec4 info;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	info = COLOR;
	if (instanced && distance(MODEL_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) > tree_impostor_distance) {
		VERTEX = vec3(0.0);
	}
	if (!bake && foliage_sway > 0.0) {
		vec3 root = MODEL_MATRIX[3].xyz;
		float phase = dot(root.xz, vec2(0.37, 0.23)) + COLOR.r * 6.28;
		float speed = min(length(wind_vector), 15.0);
		// The wind in the tree's own frame (turned about y, uniform scale).
		vec3 wind_local = (vec4(wind_vector.x, 0.0, wind_vector.y, 0.0) * MODEL_MATRIX).xyz;
		wind_local /= max(dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz), 0.0001);
		float gust = 0.6 + 0.4 * sin(TIME * 0.9 + phase);
		vec3 flutter = vec3(sin(TIME * 2.7 + phase), sin(TIME * 3.1 + phase * 1.3), cos(TIME * 2.3 + phase));
		VERTEX += (wind_local * 0.012 * gust + flutter * (0.02 + speed * 0.006)) * COLOR.b * foliage_sway;
	}
}

void fragment() {
	float cells = needles ? 1.0 : 4.0;
	vec2 g = UV * cells;
	vec2 cell = floor(g);
	float h = hash(cell + info.r * 17.0);
	float h2 = hash(cell.yx + h * 9.1);
	vec3 col;
	float alpha;
	if (info.a < 0.5) {
		// Core cards: a solid, shaded mass inside the crown, so the gaps
		// between leaves show foliage rather than sky.
		vec2 q = UV - 0.5;
		alpha = length(q) < 0.47 - 0.06 * hash(floor(UV * 6.0) + h) ? 1.0 : 0.0;
		col = (needles ? needle_dark : leaf_dark) * (0.55 + 0.2 * h);
	} else if (needles) {
		// A sprig along v: a stem with needles slanting towards the tip,
		// shortening towards it.
		vec2 p = UV;
		float across = abs(p.x - 0.5) * 2.0;
		float envelope = (1.0 - p.y * 0.55) * 0.95;
		float needle = fract(p.y * 30.0 + across * 2.2 + step(0.5, p.x) * 0.5);
		alpha = (needle < 0.6 && across < envelope) || across < 0.05 ? 1.0 : 0.0;
		col = mix(needle_dark, needle_light, fract(info.r * 7.0 + p.y * 0.6));
	} else {
		vec2 f = fract(g) - 0.5;
		float a = h * 6.2831;
		float k = 0.95 + h2 * 0.2;
		mat2 turn = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * k;
		vec2 luv = turn * f + 0.5;
		bool inside = all(greaterThanEqual(luv, vec2(0.0))) && all(lessThanEqual(luv, vec2(1.0)));
		float idx = floor(h2 * leaf_grid.x * leaf_grid.y);
		vec2 slot = vec2(mod(idx, leaf_grid.x), floor(idx / leaf_grid.x));
		vec2 auv = (slot + clamp(luv, vec2(0.01), vec2(0.99))) / leaf_grid;
		// Gradients from the card's own (continuous) UV: the turned cells
		// jump at their borders, and implicit derivatives there pick wild
		// mip levels, which showed as white sparkles in Compatibility.
		vec2 dx = turn * dFdx(UV) * cells / leaf_grid;
		vec2 dy = turn * dFdy(UV) * cells / leaf_grid;
		vec3 photo = textureGrad(leaf_color, auv, dx, dy).rgb;
		float o = textureGrad(leaf_opacity, auv, dx, dy).r;
		// Smaller mips average the leaf with the gaps around it, so an alpha
		// test eats the leaves away with distance; hold them up.
		vec2 texels = vec2(textureSize(leaf_opacity, 0));
		float lod = log2(max(max(length(dx * texels), length(dy * texels)), 1.0));
		o *= 1.0 + lod * 0.3;
		if (has_texture) {
			// The photo is of single leaves in flat light; in a crown they
			// read darker and greener.
			col = photo * vec3(0.5, 0.62, 0.36) * mix(0.75, 1.1, info.r);
			alpha = inside ? o : 0.0;
		} else {
			vec2 q = (luv - 0.5) * vec2(2.4, 1.8);
			alpha = inside && length(q) < 1.0 ? 1.0 : 0.0;
			col = mix(leaf_dark, leaf_light, h * 0.6 + info.r * 0.4);
		}
	}
	// Inner leaves sit in the crown's own shade.
	col *= mix(0.35, 1.0, info.g * info.g);
	if (bake) {
		ALBEDO = vec3(0.0);
		EMISSION = col;
	} else {
		ALBEDO = col;
	}
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;  // leaves seen from afar: soft, no glints
	// Godot flips the normal on back faces; keep the crown's normal.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}

// Soft foliage light instead of Godot's: wrapped diffuse (a crown is never
// lit hard edge-on) plus light coming through the leaves when the sun is
// behind them, and no specular highlights, which sparkled on the leaf
// edges.
void light() {
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.4) / 1.4, 0.0, 1.0);
	float through = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * 0.35;
	DIFFUSE_LIGHT += (wrap + through) * ATTENUATION * LIGHT_COLOR / PI;
}
