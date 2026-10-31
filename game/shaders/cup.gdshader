// The hole (main.gd _add_flag). The ground can't be cut, so this flat disc
// paints what you'd see looking into a real cup: the cut edge of the turf,
// the white liner on the far wall sitting an inch below the surface, and
// the dark inside. The liner always faces the camera, as in a real hole.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled;

varying vec2 away; // from the camera across the hole, in the disc's x/z

void vertex() {
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	away = length(cam.xz) > 0.0001 ? normalize(-cam.xz) : vec2(0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float far_side = dot(p, away);
	// The far wall shows as a crescent: from the rim down to where the
	// near edge hides it. The liner is its upper part, soil below it.
	float wall = smoothstep(0.15, 0.45, far_side);
	float liner = wall * smoothstep(0.62, 0.72, r) * (1.0 - smoothstep(0.86, 0.9, r));
	float soil = wall * smoothstep(0.86, 0.9, r);
	vec3 col = vec3(0.015, 0.015, 0.012);
	col = mix(col, vec3(0.80, 0.80, 0.77) * (0.55 + 0.45 * far_side), liner);
	col = mix(col, vec3(0.20, 0.15, 0.09), soil);
	// The turf's cut edge all round, a thin lighter ring.
	col = mix(col, vec3(0.25, 0.30, 0.12), smoothstep(0.93, 0.99, r));
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
