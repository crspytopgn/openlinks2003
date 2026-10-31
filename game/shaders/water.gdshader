// Pond water: animated ripples, a Fresnel blend towards the sky colour,
// sharp sun highlights and a soft, foamy edge. Drawn on a square plane; the
// shader cuts it to a disc (or, with disc off, draws a course's own water
// triangles as they are). Wind roughens the surface. On Forward+ the
// Photoreal lighting adds screen-space reflections of the banks and trees. Avoids the depth and screen textures so it works
// the same in the Compatibility renderer used by the web build.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.11, 0.17);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.33, 0.33);
uniform vec3 sky_color : source_color = vec3(0.36, 0.52, 0.68);
uniform vec3 foam_color : source_color = vec3(0.85, 0.90, 0.88);
uniform float ripple_strength = 0.6;
uniform float ripple_speed = 1.0;
uniform float edge_width = 0.07; // as a fraction of the radius
uniform bool disc = true;
global uniform vec2 wind_vector;

varying vec3 world_pos;

// Gradient of one travelling wave a * sin(k . p + w t).
vec2 wave(vec2 p, vec2 dir, float freq, float amp, float speed, float t) {
	return dir * freq * amp * cos(dot(dir, p) * freq + t * speed);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * ripple_speed;
	float breeze = 1.0 + min(length(wind_vector), 12.0) * 0.08;
	vec2 g = vec2(0.0);
	g += wave(p, normalize(vec2(1.0, 0.3)), 0.9, 0.05, 1.3, t);
	g += wave(p, normalize(vec2(-0.4, 1.0)), 1.7, 0.03, 1.9, t);
	g += wave(p, normalize(vec2(0.7, -0.8)), 3.9, 0.012, 2.7, t);
	g += wave(p, normalize(vec2(-1.0, -0.2)), 7.3, 0.006, 3.6, t);
	// Fine wind ripples on top, for sparkle in the sun.
	g += wave(p, normalize(vec2(0.3, 1.0)), 13.0, 0.003, 5.1, t) * breeze;
	g += wave(p, normalize(vec2(-0.9, 0.5)), 21.0, 0.0018, 6.3, t) * breeze;
	vec3 n_world = normalize(vec3(-g.x * ripple_strength * breeze, 1.0, -g.y * ripple_strength * breeze));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float r = disc ? length(UV * 2.0 - 1.0) : 0.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.03 + 0.97 * pow(1.0 - facing, 5.0);
	vec3 body = mix(deep_color, shallow_color, smoothstep(0.55, 1.0, r));
	// Reflection capped: even at a glancing view, real water shows the
	// deep blue of the sky above more than the pale horizon.
	vec3 col = mix(body, sky_color, fresnel * 0.6);

	float foam = smoothstep(1.0 - edge_width * 2.0, 1.0 - edge_width * 0.5, r);
	foam *= 0.6 + 0.4 * sin(p.x * 3.1 + p.y * 2.3 + TIME * 1.5);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.55);

	ALBEDO = col;
	ROUGHNESS = mix(0.02, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = (1.0 - smoothstep(1.0 - edge_width * 0.5, 1.0, r)) * mix(0.82, 1.0, fresnel);
}
