// The sun shadow of a standing spectator (Gallery), drawn on the ground as
// a soft person-shaped patch stretched away from the sun. The crowd casts
// no real shadows (hundreds of skinned people and cards in the shadow maps
// would cost too much, and Compatibility's shadows stop near the camera),
// and without one each person seems pasted on the grass. One MultiMesh of
// flat quads draws them all, in Forward+ and Compatibility.
//
// Per instance: the transform's origin is at the feet and its scale is the
// person's height; INSTANCE_CUSTOM.xy is the ground's slope there (rise per
// metre along x and z) so the shadow lies on the slope.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, world_vertex_coords, fog_disabled;

global uniform vec3 sun_travel;
uniform float strength = 0.42;
// Longest shadow per metre of height, for a low sun.
uniform float max_slant = 2.6;
const float HALF_WIDTH = 0.36;  // metres either side of the line of the shadow

varying vec2 body;  // metres: across the shadow, and up the person's body
varying float height;
varying float slant;

void vertex() {
	vec3 feet = MODEL_MATRIX[3].xyz;
	height = length(MODEL_MATRIX[1].xyz);
	vec3 travel = normalize(sun_travel);
	vec2 along = travel.xz;
	float flat_len = length(along);
	along = flat_len > 0.001 ? along / flat_len : vec2(0.0, 1.0);
	slant = min(flat_len / max(-travel.y, 0.05), max_slant);
	vec2 across = vec2(-along.y, along.x);
	// The quad mesh is 1 x 1 in x and z about its centre: x across, z along.
	vec2 local = (inverse(mat3(MODEL_MATRIX)) * (VERTEX - feet)).xz;
	float s = local.x * 2.0;  // -1 .. 1
	float t = local.y + 0.5;  // 0 at the feet, 1 at the head's end
	// A little behind the feet too, where the shoes' shadow starts.
	float len = height * slant + 0.25;
	vec2 off = across * s * HALF_WIDTH + along * (t * len - 0.12);
	float rise = dot(INSTANCE_CUSTOM.xy, off);
	VERTEX = feet + vec3(off.x, rise + 0.025, off.y);
	body = vec2(s * HALF_WIDTH, (t * len - 0.12) / max(slant, 0.05));
}

// Half the width of a person's outline at `b` metres up a body `h` tall.
float half_width(float b, float h) {
	float k = b / h * 1.75;  // in metres of a 1.75 m person
	if (k < 0.0) return 0.08 + k * 0.6;
	if (k < 0.85) return 0.1 + 0.07 * k;  // legs
	if (k < 1.45) return 0.2 + 0.02 * sin((k - 0.85) * 5.0);  // body and arms
	if (k < 1.53) return 0.07;  // neck
	float d = (k - 1.64) / 0.11;
	return 0.1 * sqrt(max(1.0 - d * d, 0.0));  // head
}

void fragment() {
	float b = body.y;
	float hw = half_width(b, height) * height / 1.75;
	// Soft at the feet, softer towards the head, as the sun's disc blurs
	// a shadow more the further it falls from what casts it.
	float blur = 0.025 + 0.05 * max(b, 0.0) * slant;
	float a = 1.0 - smoothstep(hw - blur, hw + blur, abs(body.x));
	a *= smoothstep(-0.12, -0.02, b) * (1.0 - smoothstep(height * 0.98, height * 1.04, b));
	ALBEDO = vec3(0.0);
	// Paler where it falls far from the feet (the sky fills it in).
	ALPHA = strength * a * mix(1.0, 0.75, clamp(b / height, 0.0, 1.0));
}
