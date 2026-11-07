// The green-reading grid's lines (GreenGrid), drawn as thin ribbons with
// soft, anti-aliased edges instead of one-pixel GL lines, which neither
// renderer smooths: those broke into stair steps and dashes, worst on the
// web build without MSAA.
//
// Each line is a strip of quads along the ground. A vertex carries its spot
// on the line (VERTEX), the way the line runs (NORMAL) and which edge it is
// (UV.x, -1 or +1); here the strip is widened across the screen so the line
// keeps `width` metres (painted on the turf) but never thins below about a
// pixel and a quarter, as the old lines' pixel, a touch fainter there. The whole line is
// drawn a little towards the camera (same place on screen, nearer in
// depth) so it rides on the turf instead of dipping into it in dashes.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform, fog_disabled;

// The line's width on the ground, metres.
uniform float width = 0.02;
// UV.y: this line's width as a multiple of `width` (the downhill ticks are wider).
// Never narrower than this on screen (pixels); a line held at it is drawn
// a little fainter.
uniform float min_pixels = 1.25;
// How much nearer the camera to draw the line, as a share of its distance.
uniform float pull = 0.004;

// The flowing dots (UV2.y > 0): UV2.x is how far along its streamline the
// vertex is (0 to 1) plus twice a whole number that sets the dot's phase,
// in sixteenths; UV2.y is how many times a second a dot runs its length.
varying float flow_s;
varying float flow_rate;
varying float flow_phase;
varying float across;
varying float half_px;
varying float coverage;

void vertex() {
	float k = floor(UV2.x * 0.5);
	flow_s = UV2.x - k * 2.0;
	flow_phase = k / 16.0;
	flow_rate = UV2.y;
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 ahead = MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * 0.05, 1.0);
	vec4 clip = PROJECTION_MATRIX * view;
	vec4 clip_b = PROJECTION_MATRIX * ahead;
	vec2 size = VIEWPORT_SIZE;
	vec2 dir = (clip_b.xy / clip_b.w - clip.xy / clip.w) * size;
	dir = length(dir) > 1e-5 ? normalize(dir) : vec2(1.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);
	// The line's width in pixels where it is.
	float px = width * UV.y * PROJECTION_MATRIX[1][1] * size.y * 0.5 / max(clip.w, 1e-4);
	float drawn = max(px, min_pixels);
	coverage = mix(0.8, 1.0, clamp(px / min_pixels, 0.0, 1.0));
	half_px = drawn * 0.5;
	// One pixel more each side for the soft edge.
	float out_px = half_px + 1.0;
	across = UV.x * out_px;
	clip.xy += perp * UV.x * out_px * 2.0 / size * clip.w;
	// Nearer in depth: the same spot on screen, a little in front.
	vec4 pulled = PROJECTION_MATRIX * vec4(view.xyz * (1.0 - pull), 1.0);
	clip.z = pulled.z / pulled.w * clip.w;
	POSITION = clip;
}

void fragment() {
	float edge = clamp(half_px + 0.5 - abs(across), 0.0, 1.0);
	ALBEDO = COLOR.rgb;
	float a = COLOR.a;
	if (flow_rate > 0.0) {
		// A dot running downhill along its streamline, faster where the
		// green is steeper, with a faint trail that thickens downhill so a
		// still frame shows the way too. The streamline fades in and out
		// at its ends so dots don't pop.
		float head = fract(TIME * flow_rate + flow_phase);
		float behind = head - flow_s;
		behind += behind < -0.5 ? 1.0 : 0.0;
		float dot_a = smoothstep(0.0, 0.02, behind + 0.02) * (1.0 - smoothstep(0.03, 0.08, behind));
		float trail = 0.3 * flow_s;
		float ends = smoothstep(0.0, 0.12, flow_s) * smoothstep(1.0, 0.85, flow_s);
		a *= max(dot_a, trail) * ends;
	}
	ALPHA = a * edge * coverage;
}
