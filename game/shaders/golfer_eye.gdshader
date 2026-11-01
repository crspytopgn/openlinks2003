shader_type spatial;
// The free golfer's eyes (GolferSurface.eye): the look pack's eye texture
// (white, iris and pupil) made to sit in a face the way real eyes do in
// close-up photos: the white is never paper white, the upper lid and lashes
// shade the top of the eyeball, the corners are pinker and darker, and the
// wet surface shows a sharp highlight of the sky.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
// How white the white of the eye is (real ones are off-white).
uniform float sclera = 0.82;
// Shade under the upper lid, and how far down the eyeball it reaches.
uniform float lid_shadow = 0.55;
uniform float corner_tint = 0.5;
uniform float cutoff = 0.5;

varying vec3 eye_normal;

void vertex() {
	eye_normal = NORMAL;
}

void fragment() {
	vec4 t = texture(texture_albedo, UV);
	vec3 c = t.rgb;
	// The pack's eyes carry a clear cornea shell (alpha 0).
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	// The white (bright and grey) dimmed; the iris keeps its colour.
	float white = smoothstep(0.55, 0.85, min(c.r, min(c.g, c.b)));
	c *= mix(1.0, sclera, white);
	vec3 n = normalize(eye_normal);
	// Model space: +y up, the face looks down -z, x to the sides.
	float top = smoothstep(0.05, 0.45, n.y);
	float side = smoothstep(0.35, 0.8, abs(n.x));
	c *= 1.0 - lid_shadow * top;
	c *= mix(vec3(1.0), vec3(0.95, 0.72, 0.68), side * corner_tint * white);
	ALBEDO = c;
	// Wet: a glossy coat over the eye.
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
}
