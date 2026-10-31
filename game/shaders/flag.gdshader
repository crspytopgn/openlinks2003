// The pin flag (main.gd _add_flag). The mesh is a flat plane in local x/y,
// its left edge on the pole; this shader swings it round the pole to fly
// downwind, lifts it from hanging limp to standing out as the wind gets
// up, and runs travelling ripples down it that quicken with the wind.
// wind_vector already carries the visual gusts (WindGust), so the flag
// surges and settles with the trees and grass. Works in Forward+ and
// Compatibility.
shader_type spatial;
render_mode cull_disabled;

global uniform vec2 wind_vector; // air velocity over the course, m/s (x, z)
uniform float flag_length = 0.51; // 20 in, the usual tour flag
uniform float flag_height = 0.36; // 14 in
uniform vec4 albedo : source_color = vec4(0.86, 0.07, 0.05, 1.0);

varying float fold;

void vertex() {
	float u = clamp(VERTEX.x / flag_length + 0.5, 0.0, 1.0); // 0 at the pole
	float v = clamp(0.5 - VERTEX.y / flag_height, 0.0, 1.0); // 0 at the top
	float speed = length(wind_vector);
	vec2 dir = speed > 0.05 ? wind_vector / speed : vec2(0.6, 0.8);
	// About 20 mph (9 m/s) holds a flag straight out, 7 mph flies it at
	// about 50 degrees, and a breath of air barely lifts it off the pole.
	float lift = sqrt(clamp(speed / 9.0, 0.0, 1.0));
	float theta = mix(0.15, 1.48, lift); // angle from hanging straight down
	vec3 out_dir = vec3(dir.x * sin(theta), -cos(theta), dir.y * sin(theta));
	vec3 side = vec3(-dir.y, 0.0, dir.x);
	float freq = 1.2 + speed * 0.75;
	float amp = (0.015 + 0.05 * lift) * u;
	float k = 9.0;
	float phase = u * k - TIME * freq * 2.0 + v * 1.6;
	vec3 p = vec3(0.0, -v * flag_height, 0.0) + out_dir * (u * flag_length) + side * (sin(phase) * amp);
	// The free edge sags a little below the top seam in a light wind.
	p.y -= u * u * v * (1.0 - lift) * 0.04;
	VERTEX = p;
	float slope = cos(phase) * k * amp / flag_length;
	NORMAL = normalize(side - out_dir * slope);
	fold = cos(phase);
}

void fragment() {
	// The troughs of each ripple catch a little less light.
	ALBEDO = albedo.rgb * (0.88 + 0.12 * fold);
	ROUGHNESS = 0.85;
	// Thin cloth: the sun shows through it from behind, as on TV.
	BACKLIGHT = albedo.rgb * 0.6;
}
