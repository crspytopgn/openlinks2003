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
// Photoscanned fir sprigs (Poly Haven's fir_tree_01 twig atlas, with its
// alpha map) for the needle cards.
uniform sampler2D twig_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D twig_opacity : filter_linear_mipmap, repeat_disable;
uniform bool has_twig = false;
uniform vec3 twig_tint = vec3(0.62, 0.72, 0.6);
uniform bool needles = false;
uniform bool bake = false;
// Drawn in a MultiMesh of a course's trees: beyond tree_impostor_distance
// from the camera an instance collapses to a point and its impostor shows.
uniform bool instanced = false;
uniform vec2 leaf_grid = vec2(3.0, 2.0); // leaves in the leaf texture
// Leaves across a card: with TreeFactory's cards of 1.4 to 2 m, a leaf
// is 20 to 30 cm.
uniform float leaf_cells = 7.0;
uniform vec3 leaf_tint = vec3(0.54, 0.64, 0.4);
uniform float fill = 0.12; // TreeFactory raises it for Compatibility
// How light the leaves inside the crown are (1 as lit as the outside).
// Forward+ darkens them more: its sky light would otherwise flatten the
// crown into one bright mass, where a real one has deep shade inside.
uniform float inner_shade = 0.58;
uniform vec3 leaf_dark : source_color = vec3(0.16, 0.27, 0.08);
uniform vec3 leaf_light : source_color = vec3(0.36, 0.47, 0.16);
uniform vec3 needle_dark : source_color = vec3(0.07, 0.17, 0.08);
uniform vec3 needle_light : source_color = vec3(0.16, 0.29, 0.12);

global uniform vec2 wind_vector;
global uniform float foliage_sway;
global uniform float tree_impostor_distance;

varying vec4 info;

#include "res://shaders/tree_wind.gdshaderinc"

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
		// The whole tree leans and rocks (as the bark does); each card
		// also flutters on its own, more at the outside of the crown.
		VERTEX += tree_bend(VERTEX, MODEL_MATRIX, foliage_sway, wind_vector, TIME);
		vec3 flutter = vec3(sin(TIME * 2.7 + phase), sin(TIME * 3.1 + phase * 1.3), cos(TIME * 2.3 + phase));
		VERTEX += flutter * (0.02 + speed * 0.006) * COLOR.b * foliage_sway;
	}
}

void fragment() {
	float cells = needles ? 1.0 : (info.a < 0.5 ? leaf_cells * 3.0 : leaf_cells);
	vec2 g = UV * cells;
	vec2 cell = floor(g);
	float h = hash(cell + info.r * 17.0);
	float h2 = hash(cell.yx + h * 9.1);
	vec3 col;
	float alpha;
	bool core = info.a < 0.5;
	if (core && needles) {
		// Core cards: a solid, shaded mass inside the crown, so the gaps
		// between needles show foliage rather than sky.
		vec2 q = UV - 0.5;
		alpha = length(q) < 0.47 - 0.06 * hash(floor(UV * 6.0) + h) ? 1.0 : 0.0;
		// With the photo sprigs, the shaded inside takes their (darkened) green.
		col = has_twig ? textureLod(twig_color, vec2(0.6, 0.3), 9.0).rgb * twig_tint * (0.42 + 0.12 * h) : needle_dark * (0.55 + 0.2 * h);
	} else if (needles && has_twig) {
		// Sprigs from the photo atlas, two across and three along the card
		// (a sprig 40 to 55 cm long on a pine's cards), each one of four
		// sprigs, tip towards v = 0 as on the branch.
		vec2 grid = vec2(2.0, 3.0);
		vec2 gc = UV * grid;
		vec2 sc = floor(gc);
		vec2 sf = fract(gc);
		float pick = hash(sc + info.r * 11.0);
		// The sprigs' boxes in the 1024 px atlas (x, y, w, h, in pixels).
		vec4 box = pick < 0.25 ? vec4(192.0, 48.0, 256.0, 272.0)
			: pick < 0.5 ? vec4(656.0, 32.0, 304.0, 352.0)
			: pick < 0.75 ? vec4(304.0, 300.0, 368.0, 500.0)
			: vec4(640.0, 448.0, 352.0, 384.0);
		// Overlap the neighbours a little, so the sprigs knit together.
		vec2 q = (sf - 0.5) * vec2(0.85, 0.8) + 0.5;
		bool flip = hash(sc.yx + info.r * 3.1) > 0.5;
		q.x = flip ? 1.0 - q.x : q.x;
		vec2 tuv = (box.xy + q * box.zw) / 1024.0;
		vec2 dx = dFdx(UV) * grid * box.zw / 1024.0;
		vec2 dy = dFdy(UV) * grid * box.zw / 1024.0;
		float o = textureGrad(twig_opacity, tuv, dx, dy).r;
		vec2 texels = vec2(textureSize(twig_opacity, 0));
		float lod = log2(max(max(length(dx * texels), length(dy * texels)), 1.0));
		o *= 1.0 + lod * 0.35;
		alpha = o;
		col = textureGrad(twig_color, tuv, dx, dy).rgb * twig_tint * mix(0.8, 1.1, info.r);
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
		// A clump of leaves: one per cell, nudged off the cell's middle
		// and dropped more often towards the card's rim, so a card reads
		// as a round, ragged spray of leaves, not a square.
		float h3 = hash(cell * 1.7 + info.r * 5.3 + 0.37);
		float rim = length((cell + 0.5) / cells - 0.5) * 2.0;
		// Once a leaf is only a few pixels across, single leaves on their
		// grid read as a dot matrix: grow them into each other (and drop
		// fewer) so a crown further off reads as solid, ragged foliage.
		float per_px = max(length(dFdx(UV)), length(dFdy(UV))) * cells;
		float far = clamp(per_px * 7.0 - 0.6, 0.0, 1.0);
		// Core cards (the crown's shaded middle) are packed full of leaves
		// inside their round outline.
		bool keep = core ? rim < 0.95 - 0.15 * h3 : h3 > smoothstep(0.3, 1.05, rim) * mix(0.95, 0.75, far) + 0.06 * (1.0 - far);
		vec2 jitter = (vec2(h3, fract(h3 * 13.7)) - 0.5) * 0.16;
		vec2 f = fract(g) - 0.5 - jitter;
		float a = h * 6.2831;
		float k = (1.08 + h2 * 0.3) / mix(1.0, 1.7, far);
		mat2 turn = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * k;
		vec2 luv = turn * f + 0.5;
		bool inside = keep && all(greaterThanEqual(luv, vec2(0.0))) && all(lessThanEqual(luv, vec2(1.0)));
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
		// The shaded middle of the crown fills in solid with distance.
		o = core ? max(o, far) : o;
		if (has_texture) {
			// The photo is of single leaves in flat light; in a crown they
			// read darker and greener.
			col = photo * leaf_tint * mix(0.75, 1.1, info.r);
			alpha = inside ? o : 0.0;
		} else {
			vec2 q = (luv - 0.5) * vec2(2.4, 1.8);
			alpha = inside && length(q) < 1.0 ? 1.0 : 0.0;
			col = mix(leaf_dark, leaf_light, h * 0.6 + info.r * 0.4);
		}
		// Each leaf faces its own way, so leaves next to each other catch
		// the light differently; a few are yellower or bluer.
		col *= mix(0.78, 1.12, h3);
		col *= mix(vec3(1.0), h2 > 0.85 ? vec3(1.12, 1.08, 0.75) : vec3(0.92, 1.0, 1.06), step(0.7, fract(h2 * 7.3)));
	}
	// Inner leaves sit in the crown's own shade.
	col *= core ? (needles ? 1.0 : 0.5) : mix(inner_shade, 1.0, info.g * info.g);
	if (bake) {
		ALBEDO = vec3(0.0);
		EMISSION = col;
	} else {
		ALBEDO = col;
		// Light from the sky and through neighbouring leaves, which the
		// renderer's ambient misses (Compatibility has no sky fill), so a
		// crown's shaded side stays green instead of black.
		EMISSION = col * fill;
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
	float wrap = clamp((dot(NORMAL, LIGHT) + 0.5) / 1.5, 0.0, 1.0);
	float through = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0) * 0.35;
	DIFFUSE_LIGHT += (wrap + through) * ATTENUATION * LIGHT_COLOR / PI;
}
