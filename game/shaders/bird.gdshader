// Distant birds crossing the sky (CourseLife). Each bird is a flat "V" of
// two wings in one MultiMesh; the wings flap by bending the vertices by how
// far out along the wing they are, each bird at its own phase
// (INSTANCE_CUSTOM.r) with now and then a glide (wings held still).
// Unshaded dark silhouettes, as birds look against the sky. Works in
// Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, cull_disabled;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float t = TIME * 7.0 + phase;
	// Flap for a few beats, then glide, as small birds do.
	float glide = smoothstep(0.55, 0.75, sin(TIME * 0.6 + phase));
	float flap = sin(t) * (1.0 - glide) + 0.15 * glide;
	float span = abs(VERTEX.x);
	VERTEX.y += flap * span * 0.9;
}

void fragment() {
	ALBEDO = vec3(0.07, 0.07, 0.08);
}
