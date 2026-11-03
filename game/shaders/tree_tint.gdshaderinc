// Each tree's own leaf colour, from a hash of where it stands, so a wood
// of the same few tree shapes reads as many trees: parkland mixes yellower
// crowns (ash, lime, young oak) with darker, bluer ones (beech, old oak)
// and a few lighter or darker in between. Used by the full trees
// (tree_leaves) and their impostors, so a tree keeps its colour when it
// turns into its impostor.
vec3 crown_tint(vec3 root) {
	vec2 p = fract(root.xz * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	float a = fract((p.x + p.y) * p.x);
	float b = fract((p.x + p.y) * p.y);
	vec3 hue = a < 0.5 ? mix(vec3(1.1, 1.06, 0.78), vec3(1.0), a * 2.0)
		: mix(vec3(1.0), vec3(0.86, 0.96, 1.04), (a - 0.5) * 2.0);
	return hue * mix(0.86, 1.14, b);
}
