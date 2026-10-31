// Whole-tree sway in the wind for the 3D trees and bushes (TreeFactory):
// the trunk and crown lean with the wind and rock slowly with the gusts,
// more the higher up, so a crown moves as one with its branches. Shared by
// the bark and the leaves, so they never come apart. Needs the globals
// wind_vector (air velocity, m/s, x and z) and foliage_sway (0 still).
//
// `v` is the vertex in the tree's own frame; returns the offset to add to
// it, in that frame. Mesh heights are in metres before the instance's
// scale, and bushes (short) barely lean.

vec3 tree_bend(vec3 v, mat4 model, float sway, vec2 wind, float t) {
	if (sway <= 0.0) {
		return vec3(0.0);
	}
	vec3 root = model[3].xyz;
	float phase = dot(root.xz, vec2(0.37, 0.23));
	float speed = min(length(wind), 15.0);
	// The wind in the tree's own frame (turned about y, uniform scale).
	vec3 w = (vec4(wind.x, 0.0, wind.y, 0.0) * model).xyz;
	w /= max(dot(model[0].xyz, model[0].xyz), 0.0001);
	vec3 dir = speed > 0.01 ? w / max(length(w), 0.0001) : vec3(1.0, 0.0, 0.0);
	float h = max(v.y, 0.0) * 0.1;
	float lean = speed * (0.006 + 0.004 * sin(t * 0.45 + phase));
	float rock = (0.025 + speed * 0.004) * (sin(t * 1.3 + phase) * 0.7 + sin(t * 2.9 + phase * 1.9) * 0.3);
	vec3 side = vec3(-dir.z, 0.0, dir.x);
	return (dir * (lean + rock) + side * rock * 0.35 * sin(t * 0.7 + phase)) * h * h * sway;
}
