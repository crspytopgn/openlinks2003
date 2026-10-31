// Marks the ball and clubs leave on the course (CourseMarks): divots, pitch
// marks on the green and craters in sand. Each mark is one small quad on
// the ground, its UV running 0..1 along (y) and across (x) the mark; the
// shape is drawn here with a ragged edge that differs from mark to mark.
// Lit like the ground, so the marks sit in the same light and shade.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform int kind = 0; // 0 divot, 1 pitch mark, 2 sand crater

varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	seed = hash(floor(MODEL_MATRIX[3].xz * 50.0));
}

void fragment() {
	// -1..1 across (x) and along (y); +y is the far end, away from the ball.
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float ang = atan(p.y, p.x);
	// A ragged rim: a few lumps whose phase changes from mark to mark.
	float rag = 0.07 * sin(ang * 5.0 + seed * 40.0) + 0.05 * sin(ang * 11.0 + seed * 17.0);
	float r = length(p);
	vec3 col;
	float a;
	if (kind == 0) {
		// A scraped-out divot: bare damp soil, torn grass roots at the far
		// end where the turf came away, lighter dry crumbs over it.
		float edge = 1.0 - smoothstep(0.82 + rag, 1.0 + rag, r);
		float roots = smoothstep(0.35, 0.95, p.y) * (0.5 + 0.5 * sin(p.x * 60.0 + seed * 9.0));
		float crumbs = step(0.86, hash(floor(UV * vec2(18.0, 30.0)) + seed));
		col = mix(vec3(0.20, 0.14, 0.08), vec3(0.30, 0.25, 0.12), roots * 0.6);
		col = mix(col, vec3(0.42, 0.34, 0.22), crumbs * 0.7);
		// Darker in the deepest part of the scrape.
		col *= 0.8 + 0.2 * r;
		a = edge * 0.95;
	} else if (kind == 1) {
		// A pitch mark: a dark, pressed-in dent with a raised, lighter lip
		// on the far side where the ball pushed the turf up.
		float dent = 1.0 - smoothstep(0.55 + rag, 0.75 + rag, r);
		float lip = smoothstep(0.55, 0.75, r) * (1.0 - smoothstep(0.85, 1.0, r)) * smoothstep(-0.2, 0.6, p.y);
		col = mix(vec3(0.11, 0.17, 0.06), vec3(0.34, 0.38, 0.17), lip);
		a = max(dent * 0.6, lip * 0.7);
	} else {
		// A crater in the sand: a shaded bowl with a bright thrown-up rim.
		float bowl = 1.0 - smoothstep(0.6 + rag, 0.8 + rag, r);
		float rim = smoothstep(0.6, 0.8, r) * (1.0 - smoothstep(0.85 + rag, 1.0 + rag, r));
		float shade = 0.75 + 0.25 * p.y; // the near wall catches less light
		col = mix(vec3(0.55, 0.47, 0.33) * shade, vec3(0.86, 0.79, 0.62), rim);
		a = max(bowl * 0.55, rim * 0.5);
	}
	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = 0.95;
}
