// The hole (main.gd _add_flag), 4.25 in (108 mm) across and 4 in deep.
// The ground can't be cut, so this flat disc on the
// turf traces each pixel's view ray into a real cylinder and paints what it
// meets, as a real cup looks from wherever you stand:
//   - the cut edge of the turf, a few millimetres of dense blades and thatch;
//   - the top inch of soil, sprayed white as at tour events so the hole
//     reads on TV (the Rules' definition of the hole: 108 mm across, at
//     least 101.6 mm deep, any liner sunk at least 25.4 mm below the
//     surface);
//   - the white plastic liner, its rim catching the light, darkening with
//     depth as less sky reaches it;
//   - the bottom: dark, with the liner's drain ring.
// Near the rim the far wall shows deep into the cup; from a low eye only a
// sliver of it, and the near wall hides the rest, exactly as on a green.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float radius = 0.054;
uniform float depth = 0.1016;      // turf surface to the liner's floor
uniform float turf_edge = 0.006;   // blades and thatch at the cut
uniform float painted = 0.0254;    // the sprayed-white soil above the liner
uniform float liner_rim = 0.004;   // the liner's top lip
uniform bool tour_paint = true;    // the white sprayed edge

varying vec3 local_pos;
varying vec3 local_cam;

void vertex() {
	local_pos = VERTEX;
	local_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = local_pos.xz;
	float r = length(p);
	if (r > radius) {
		discard;
	}
	vec3 d = normalize(local_pos - local_cam);
	// Where the ray meets the cup's wall below the surface: the far root
	// of |p + t d.xz| = radius.
	float a = max(dot(d.xz, d.xz), 1e-6);
	float b = dot(p, d.xz);
	float c = dot(p, p) - radius * radius;
	float t = (-b + sqrt(max(b * b - a * c, 0.0))) / a;
	float h = -t * d.y; // depth of the wall hit, metres
	float ang = atan(p.y + t * d.z, p.x + t * d.x);
	vec3 col;
	float light;
	if (d.y > -1e-4 || h > depth) {
		// The floor of the liner: dark, a ring of the drain.
		vec2 f = p - d.xz / min(d.y, -1e-4) * depth;
		float fr = length(f) / radius;
		col = mix(vec3(0.42, 0.42, 0.40), vec3(0.06, 0.06, 0.055), smoothstep(0.25, 0.32, fr) * (1.0 - smoothstep(0.75, 0.8, fr)));
		light = 0.08;
	} else {
		float aa = max(fwidth(h), 1e-4);
		// The cut is not a perfect circle: a slightly ragged top edge.
		float rag = (hash(vec2(floor(ang * 24.0), 3.0)) - 0.5) * 0.0015;
		float in_turf = 1.0 - smoothstep(turf_edge + rag - aa, turf_edge + rag + aa, h);
		float in_paint = 1.0 - smoothstep(painted - aa, painted + aa, h);
		float in_rim = 1.0 - smoothstep(painted + liner_rim - aa, painted + liner_rim + aa, h);
		// Soil with crumbs and roots; the paint is patchy at its foot.
		float crumbs = hash(floor(vec2(ang * 90.0, h * 600.0)));
		vec3 soil = vec3(0.17, 0.12, 0.075) * (0.75 + 0.5 * crumbs);
		float paint_cover = tour_paint ? smoothstep(painted, painted * 0.55, h + (crumbs - 0.5) * 0.002) : 0.0;
		vec3 top = mix(soil, vec3(0.86, 0.86, 0.83), paint_cover);
		vec3 turf = mix(vec3(0.16, 0.24, 0.07), vec3(0.22, 0.17, 0.08), smoothstep(0.0, turf_edge, h)) * (0.8 + 0.4 * crumbs);
		vec3 liner = vec3(0.83, 0.83, 0.80);
		col = mix(liner, vec3(0.95, 0.95, 0.92), in_rim);
		col = mix(col, top, in_paint);
		col = mix(col, turf, in_turf);
		// Less of the sky reaches deeper down: a wall an inch down is in
		// half shade, the floor in deep shade.
		light = mix(0.1, 1.0, exp(-h / 0.022));
	}
	// Turf leaning over the rim softens the very edge.
	light *= mix(1.0, 0.75, smoothstep(0.9, 1.0, r / radius));
	ALBEDO = col * light;
	ROUGHNESS = 0.95;
}
