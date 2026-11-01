// Pond water: animated ripples, a Fresnel blend towards the sky colour,
// sharp sun highlights and a soft, foamy edge. Drawn on a square plane; the
// shader cuts it to a disc (or, with disc off, draws a course's own water
// triangles as they are). Wind roughens the surface. On Forward+ the
// Photoreal lighting adds screen-space reflections of the banks and trees. Avoids the depth and screen textures so it works
// the same in the Compatibility renderer used by the web build.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.03, 0.07, 0.07);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.15, 0.12);
uniform vec3 sky_color : source_color = vec3(0.36, 0.52, 0.68);
uniform vec3 foam_color : source_color = vec3(0.85, 0.90, 0.88);
uniform float ripple_strength = 0.45;
uniform float ripple_speed = 1.0;
uniform float edge_width = 0.07; // as a fraction of the radius
uniform bool disc = true;
// The photographed sky (FreeAssets.sky), reflected by the ripples: real
// clouds in the water instead of one flat sky colour. Below the horizon
// the reflection shows the far banks, dark and green.
uniform sampler2D sky_pano : source_color, filter_linear, repeat_enable;
uniform bool has_pano = false;
uniform float pano_energy = 1.0;
uniform vec3 bank_color : source_color = vec3(0.10, 0.14, 0.08);
global uniform vec2 wind_vector;
global uniform vec3 sky_tint; // the time of day's light (Scenery)

varying vec3 world_pos;
varying float open_water;

float hash21(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Gradient of one travelling wave a * sin(k . p + w t).
vec2 wave(vec2 p, vec2 dir, float freq, float amp, float speed, float t) {
	return dir * freq * amp * cos(dot(dir, p) * freq + t * speed);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// A course's own water carries how far from the bank each vertex is
	// (CrzTerrain): 0 on the bank, 1 in open water (and without the
	// attribute).
	open_water = COLOR.r;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * ripple_speed;
	float breeze = 1.0 + min(length(wind_vector), 12.0) * 0.08;
	vec2 g = vec2(0.0);
	g += wave(p, normalize(vec2(1.0, 0.3)), 0.9, 0.03, 1.3, t);
	g += wave(p, normalize(vec2(-0.4, 1.0)), 1.7, 0.018, 1.9, t);
	g += wave(p, normalize(vec2(0.7, -0.8)), 3.9, 0.012, 2.7, t);
	g += wave(p, normalize(vec2(-1.0, -0.2)), 7.3, 0.006, 3.6, t);
	// Fine wind ripples on top, for sparkle in the sun: drifting noise
	// rather than more sine waves, whose crossings show as a regular
	// diamond pattern.
	vec2 drift = wind_vector * 0.08 * t + vec2(t * 0.11, -t * 0.07);
	vec2 q = p * 2.3 + drift;
	float n0 = noise2(q) + noise2(q * 2.7 - drift * 1.3) * 0.5;
	float nx = noise2(q + vec2(0.15, 0.0)) + noise2((q + vec2(0.15, 0.0)) * 2.7 - drift * 1.3) * 0.5;
	float ny = noise2(q + vec2(0.0, 0.15)) + noise2((q + vec2(0.0, 0.15)) * 2.7 - drift * 1.3) * 0.5;
	g += vec2(nx - n0, ny - n0) * 0.11 * breeze;
	// Gusts roughen patches of the surface (cat's paws) and leave others
	// glassy.
	g *= 0.6 + 0.8 * noise2(p * 0.06 + drift * 0.05);
	// Calmer with distance: ripples finer than a pixel or two average out
	// to a smoother mirror, as in photos, instead of aliasing into bands.
	// So the far half of a pond holds the dark reflection of the trees
	// on its far bank, and only the near water shows the wind.
	float footprint = length(fwidth(p));
	g *= 1.0 / (1.0 + footprint * 6.0);
	vec3 n_world = normalize(vec3(-g.x * ripple_strength * breeze, 1.0, -g.y * ripple_strength * breeze));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float r = disc ? length(UV * 2.0 - 1.0) : 0.0;
	// 0 at the water's edge, 1 out in open water, with a ragged line.
	float wobble = noise2(p * 0.35) * 0.5 + noise2(p * 1.3) * 0.25;
	float open = disc ? clamp((1.0 - r) / (edge_width * 3.0) + (wobble - 0.37) * 0.25, 0.0, 1.0)
		: clamp(open_water * 1.6 - 0.15 + (wobble - 0.37) * 0.35, 0.0, 1.0);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.03 + 0.97 * pow(1.0 - facing, 5.0);
	// Shallow, browner water near the bank where the bottom shows through,
	// deep in the middle.
	vec3 body = mix(deep_color, shallow_color, smoothstep(0.55, 1.0, r));
	body = mix(mix(shallow_color * vec3(1.25, 1.1, 0.8), shallow_color, smoothstep(0.0, 0.25, open)), body, smoothstep(0.15, 0.7, open));
	// Reflection capped: even at a glancing view, real water shows the
	// deep blue of the sky above more than the pale horizon.
	vec3 refl = sky_color;
	float reach = 0.6;
	if (has_pano) {
		vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
		vec3 r_dir = reflect(view_dir, n_world);
		r_dir.y = abs(r_dir.y);
		vec2 uv = vec2(atan(r_dir.x, -r_dir.z) / 6.28318 + 0.5, acos(clamp(r_dir.y, -1.0, 1.0)) / 3.14159);
		refl = texture(sky_pano, uv).rgb * pano_energy * sky_tint;
		// The banks and trees round the water fill the bottom of the
		// reflected sky.
		// A wood on the far bank stands about ten degrees above the
		// water, so a band that high mirrors dark trees, not sky.
		refl = mix(bank_color, refl, smoothstep(0.12, 0.32, r_dir.y));
		// Ponds and creeks sit low among banks and trees, which take
		// some of the sky out of every reflection.
		refl = mix(refl, bank_color, 0.25);
		reach = 0.8;
	}
	// The shallows reflect less: the bank and its grass fill them.
	vec3 col = mix(body, refl, fresnel * reach * mix(0.55, 1.0, smoothstep(0.0, 0.3, open)));

	// Ripples lapping the bank: a thin, broken line of froth that comes
	// and goes, and a darker wet margin right at the edge.
	float lap = 0.06 + 0.03 * sin(TIME * 0.9 + wobble * 9.0);
	float line = 1.0 - smoothstep(0.0, 0.05, abs(open - lap));
	float foam = line * smoothstep(0.35, 0.7, noise2(p * 2.1 + vec2(TIME * 0.15, 0.0))) * 0.6;
	col = mix(col, bank_color * 0.8, (1.0 - smoothstep(0.0, 0.04, open)) * 0.6);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.5);

	ALBEDO = col;
	ROUGHNESS = mix(0.02, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	// A round pond fades into its bank along the ragged shoreline.
	ALPHA = (disc ? smoothstep(0.0, 0.05, open) : 1.0) * mix(0.82, 1.0, fresnel);
}
