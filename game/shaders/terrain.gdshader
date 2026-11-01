// Ground shading for course terrain. The mesh carries the surface colour per
// vertex (fairway, rough, sand...); this adds large-scale colour variation
// and close-up grain so the ground doesn't look flat-shaded. With the free
// photo textures (FreeAssets) the grain and bumps come from them instead:
// UV2 holds the rough and sand weights per vertex, grass is the rest, and
// each texture is divided by its mean colour so the vertex colour still sets
// the tone. Works in both Forward+ and Compatibility (the web build).
shader_type spatial;
render_mode cull_back;

uniform float variation = 0.16; // large patches of lighter and darker grass
uniform float grain = 0.12; // fine detail near the camera
uniform float grain_fade_start = 15.0;
uniform float grain_fade_end = 70.0;
uniform float bump = 0.35; // strength of the close-up normal detail

#include "res://shaders/ground_shade.gdshaderinc"
#include "res://shaders/mow_sheen.gdshaderinc"

uniform bool textured = false;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : filter_linear_mipmap, repeat_enable;
// Linear mean colour of each albedo texture.
uniform vec3 grass_mean = vec3(0.5);
uniform vec3 rough_mean = vec3(0.5);
uniform vec3 sand_mean = vec3(0.5);
// Height maps of the grass and rough scans (sand has none, to stay inside
// WebGL 2's sixteen textures): near the camera the ground shifts with the
// view (parallax) and its low parts darken, so turf has depth.
uniform sampler2D grass_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_height : filter_linear_mipmap, repeat_enable;
uniform bool has_height = false;
uniform float grass_height_mean = 0.5;
uniform float rough_height_mean = 0.5;
uniform float relief_metres = 0.03;
uniform float cavity = 1.1;
uniform float texture_metres = 2.5; // one tile of the near texture
uniform float texture_strength = 0.85;
// How much of the photo's own colour shows through (at the vertex colour's
// brightness), which tames the flat, saturated surface colours.
uniform float photo_mix = 0.5;

uniform float stripe_metres = 7.0; // width of one mowing stripe
uniform float stripe_strength = 0.07;
// The sand colour the mesh uses (sRGB), to undo its blend into the grass:
// the bunker edge is drawn crisp from the sand weight instead.
uniform vec3 sand_vertex = vec3(0.78, 0.72, 0.55);

// Splat map (designed and real courses, DesignedTerrain): the surface
// raster itself, one Surface.Type per texel (R8), so each surface's edge is
// drawn where it really is instead of blended over a 2 m grid cell. The
// mesh then carries in CUSTOM0 the surface colour it blended per vertex,
// which is swapped for the raster's; the photo tint and mowing stripes in
// the vertex colour stay.
uniform bool has_splat = false;
uniform sampler2D splat_tex : filter_nearest, repeat_disable;
uniform vec2 splat_origin = vec2(0.0); // world x, z of the raster's corner
uniform vec2 splat_size = vec2(1.0); // metres it covers
// By Surface.Type, plus 9 for the first cut of rough beside the fairway.
uniform vec3 surface_colors[10]; // sRGB
uniform vec2 surface_weights[10]; // rough and sand weight
uniform float surface_mown[10]; // 1 where the surface gets mowing stripes
uniform float splat_stripe_metres = 6.0;

varying vec3 world_pos;
varying vec2 weights; // rough, sand
varying vec2 stripes; // across the hole (m), stripe strength
varying vec3 vertex_palette; // the surface colour blended into COLOR (splat map only)

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	weights = UV2;
	stripes = vec2(UV.x, clamp(-UV.y, 0.0, 1.0));
	vertex_palette = has_splat ? CUSTOM0.rgb : vec3(0.0);
}

// The raster's colour and weights at ground point p, blended over a
// fraction of a texel with a ragged, natural line.
void splat_at(vec2 p, out vec3 col, out vec2 w, out float mown) {
	vec2 size = vec2(textureSize(splat_tex, 0));
	// Two independent wobbles, so the edge wanders rather than steps.
	vec2 wobble = vec2(value_noise(p * 1.3), value_noise(p * 1.3 + vec2(41.0, 17.0))) - 0.5
		+ 0.5 * (vec2(value_noise(p * 4.1), value_noise(p * 4.1 + vec2(9.0, 23.0))) - 0.5);
	vec2 q = (p - splat_origin) / splat_size * size - 0.5 + wobble * 1.2;
	vec2 i = floor(q);
	vec2 f = q - i;
	col = vec3(0.0);
	w = vec2(0.0);
	mown = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		ivec2 t = clamp(ivec2(i) + o, ivec2(0), ivec2(size) - 1);
		int s = clamp(int(texelFetch(splat_tex, t, 0).r * 255.0 + 0.5), 0, 9);
		float a = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
		col += surface_colors[s] * a;
		w += surface_weights[s] * a;
		mown += surface_mown[s] * a;
	}

}

// A texture sampled at two scales, so its repeat is hard to see.
vec4 two_scale(sampler2D tex, vec2 uv) {
	return mix(texture(tex, uv), texture(tex, uv * 0.137 + vec2(0.31, 0.71)), 0.35);
}

void fragment() {
	vec2 p = world_pos.xz;
	// Derivatives in uniform control flow, before any branch.
	vec2 hole_mow_line = mow_line_from(stripes.x, p);
	vec3 from_eye = world_pos - CAMERA_POSITION_WORLD;
	float patches = fbm(p * 0.035) - 0.5;
	float close_up = 1.0 - smoothstep(grain_fade_start, grain_fade_end, length(VERTEX));
	float fine = (value_noise(p * 2.7) - 0.5) + 0.5 * (value_noise(p * 7.3) - 0.5);

	// The bunker's edge: the vertex sand weight blends over a whole grid
	// cell, so sharpen it to a trimmed, slightly ragged line, take the sand
	// colour back out of the grass beside it, and shade a lip of turf
	// where the bank drops into the bunker.
	float wy = clamp(weights.y, 0.0, 1.0);
	float edge_noise = value_noise(p * 1.7) - 0.5;
	float sand = smoothstep(0.42, 0.5, wy + edge_noise * 0.12);
	vec3 c = COLOR.rgb;
	float w_rough_in = weights.x;
	vec2 sq = (p - splat_origin) / splat_size;
	if (has_splat && all(greaterThanEqual(sq, vec2(0.0))) && all(lessThanEqual(sq, vec2(1.0)))) {
		vec3 crisp;
		vec2 w;
		float mown;
		splat_at(p, crisp, w, mown);
		c = max(c + crisp - vertex_palette, vec3(0.0));
		sand = w.y;
		w_rough_in = w.x;
		// Mowing stripes cut with the surface, alternately lighter and darker.
		float u = (p.x + p.y * 0.15) / splat_stripe_metres;
		float aa = max(fwidth(u), 0.001);
		float band = smoothstep(-aa, aa, sin(u * 3.14159));
		c *= 1.0 + (band - 0.5) * 0.09 * mown * mow_sheen(vec2(-0.15, 1.0), from_eye);
	} else if (wy > 0.0 && wy < 0.97) {
		vec3 turf = (c - sand_vertex * wy) / (1.0 - wy);
		c = mix(turf, sand_vertex, sand);
	}
	float lip = smoothstep(0.02, 0.4, wy) * (1.0 - sand);
	// The mesh colours are authored in sRGB; lighting works in linear.
	vec3 base = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	vec3 col = base * (1.0 + patches * variation * 2.0);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;

	if (textured) {
		vec2 uv = p / texture_metres;
		float w_sand = sand;
		float w_rough = clamp(w_rough_in, 0.0, 1.0) * (1.0 - w_sand);
		float w_grass = 1.0 - w_sand - w_rough;
		float dist = length(VERTEX);
		float shade_relief = 1.0;
		if (has_height && dist < 110.0) {
			vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
			float turf = w_grass + w_rough;
			float h = w_grass * (texture(grass_height, uv).r - grass_height_mean) + w_rough * (texture(rough_height, uv).r - rough_height_mean);
			float near_relief = 1.0 - smoothstep(10.0, 35.0, dist);
			// One parallax step: blades and clumps stand up near the camera.
			uv -= view.xz / max(view.y, 0.3) * (relief_metres / texture_metres) * h * near_relief;
			h = w_grass * (texture(grass_height, uv).r - grass_height_mean) + w_rough * (texture(rough_height, uv).r - rough_height_mean);
			shade_relief = mix(1.0, clamp(1.0 + h * 2.0 * cavity, 0.3, 1.4), turf * (1.0 - smoothstep(25.0, 110.0, dist)));
		}
		vec3 g = two_scale(grass_albedo, uv).rgb;
		vec3 r = two_scale(rough_albedo, uv).rgb;
		vec3 s = two_scale(sand_albedo, uv).rgb;
		vec3 detail = w_grass * g / max(grass_mean, vec3(0.02)) + w_rough * r / max(rough_mean, vec3(0.02))
			+ w_sand * s / max(sand_mean, vec3(0.02));
		vec3 photo = w_grass * g + w_rough * r + w_sand * s;
		vec3 photo_mean = w_grass * grass_mean + w_rough * rough_mean + w_sand * sand_mean;
		const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
		vec3 photo_toned = photo * dot(col, LUMA) / max(dot(photo_mean, LUMA), 0.02);
		// Far away the texture only adds noise and shows its repeat.
		float strength = texture_strength * mix(0.35, 1.0, 1.0 - smoothstep(40.0, 250.0, length(VERTEX)));
		col = mix(col * mix(vec3(1.0), detail, strength), photo_toned, photo_mix * strength);
		col *= shade_relief;
		vec3 n = w_grass * two_scale(grass_normal, uv).rgb + w_rough * two_scale(rough_normal, uv).rgb
			+ w_sand * two_scale(sand_normal, uv).rgb;
		n = n * 2.0 - 1.0;
		// The textures lie flat on the ground: u along +x, v along +z.
		vec3 tilt = (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz;
		NORMAL = normalize(NORMAL + tilt * strength);
	} else {
		col *= 1.0 + fine * grain * close_up;
		// Close-up bumpiness from the slope of the fine noise.
		float e = 0.15;
		float hx = value_noise((p + vec2(e, 0.0)) * 2.7) - value_noise((p - vec2(e, 0.0)) * 2.7);
		float hz = value_noise((p + vec2(0.0, e)) * 2.7) - value_noise((p - vec2(0.0, e)) * 2.7);
		vec3 tilt = (VIEW_MATRIX * vec4(-hx, 0.0, -hz, 0.0)).xyz;
		NORMAL = normalize(NORMAL + tilt * bump * close_up);
	}
	// Mowing stripes along the hole, crisp-edged, alternately lighter and
	// darker, as the mower lays the grass one way and then the other; which
	// is the light one, and how strongly, depends on where you look from.
	float stripe_aa = max(fwidth(stripes.x / stripe_metres), 0.001);
	if (stripes.y > 0.0) {
		float u = stripes.x / stripe_metres;
		float band = smoothstep(-stripe_aa, stripe_aa, sin(u * 3.14159) * 0.35);
		col *= 1.0 + (band * 2.0 - 1.0) * stripe_strength * stripes.y * mow_sheen(hole_mow_line, from_eye);
	}
	col *= 1.0 - 0.35 * lip;
	// Sand is darker and damp where it meets the turf (the bank sheds
	// water and shade into it), and a touch less bright overall, so a
	// bunker reads as a hollow, not a white decal.
	float damp = sand * (1.0 - smoothstep(0.55, 0.98, sand + edge_noise * 0.2));
	col *= mix(1.0, 0.9 - 0.22 * damp, sand);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0)) * ground_shading(p, length(VERTEX));
}
