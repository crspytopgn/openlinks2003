shader_type spatial;
// A golf ball's cover: 332 round dimples about 3.9 mm across on a 42.67 mm
// ball, laid out on a spherical Fibonacci lattice (as even as the
// icosahedral patterns real balls use, and its nearest point is found in
// constant time: Keinert et al., "Spherical Fibonacci Mapping", 2015).
// The dimples only bend the normal and darken a little in their floors;
// the mesh stays a plain sphere. They fade out once they are smaller than
// a couple of pixels, where they would only shimmer, and the ball glows a
// little instead so it still reads at TV distances.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float whiteness = 0.86; // a white cover's albedo: bright, short of paper white
uniform vec3 glow : source_color = vec3(0.25); // at a distance only, so the ball still reads
uniform float roughness_value = 0.32;
uniform float dimples = 332.0;
uniform float dimple_radius = 0.092; // radians: about 3.9 mm on the ball
uniform float dimple_slope = 0.7;

varying vec3 local_dir;

const float PHI = 1.61803399;

void vertex() {
	local_dir = VERTEX;
}

// The lattice point nearest p (unit vector) of n.
vec3 nearest_dimple(vec3 p, float n) {
	float phi = min(atan(p.y, p.x), PI);
	float cos_t = p.z;
	float k = max(2.0, floor(log(n * PI * sqrt(5.0) * (1.0 - cos_t * cos_t)) / log(PHI * PHI)));
	float fk = pow(PHI, k) / sqrt(5.0);
	vec2 f = vec2(round(fk), round(fk * PHI));
	vec2 ka = 2.0 * f / n;
	vec2 kb = 2.0 * PI * (fract((f + 1.0) * PHI) - (PHI - 1.0));
	mat2 ib = mat2(vec2(ka.y, -ka.x), vec2(kb.y, -kb.x)) / (ka.y * kb.x - ka.x * kb.y);
	vec2 c = floor(ib * vec2(phi, cos_t - (1.0 - 1.0 / n)));
	float best = 8.0;
	vec3 out_q = p;
	for (int s = 0; s < 4; s++) {
		vec2 uv = vec2(float(s % 2), float(s / 2));
		float i = clamp(dot(f, uv + c), 0.0, n - 1.0);
		float a = 2.0 * PI * fract(i * (PHI - 1.0));
		float ct = 1.0 - (2.0 * i + 1.0) / n;
		float st = sqrt(max(1.0 - ct * ct, 0.0));
		vec3 q = vec3(cos(a) * st, sin(a) * st, ct);
		float d = dot(q - p, q - p);
		if (d < best) {
			best = d;
			out_q = q;
		}
	}
	return out_q;
}

void fragment() {
	vec3 p = normalize(local_dir);
	vec3 c = nearest_dimple(p, dimples);
	float ang = acos(clamp(dot(p, c), -1.0, 1.0));
	// How many pixels a dimple spans: fade them out below about two.
	float px = dimple_radius / max(fwidth(ang) * 1.5, 1e-5);
	float show = smoothstep(1.0, 3.0, px);
	float u = ang / dimple_radius;
	vec3 n = p;
	float floor_shade = 1.0;
	if (u < 1.0) {
		// A spherical dish: the wall leans in towards the middle, most
		// steeply at the rim.
		vec3 towards = normalize(c - p * dot(c, p) + vec3(1e-6));
		float lean = dimple_slope * u * show;
		n = normalize(p + towards * lean);
		floor_shade = 1.0 - 0.22 * (1.0 - u * u) * show;
	}
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = albedo.rgb * whiteness * floor_shade;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.5;
	// Close up the dimples carry it and the glow would flatten them; far
	// off, where they have faded, it keeps the ball bright.
	EMISSION = glow * (1.0 - show);
}
