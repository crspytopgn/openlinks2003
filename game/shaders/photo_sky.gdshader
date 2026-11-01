// The photographed cloud sky (FreeAssets.sky) for the Photoreal lighting,
// tinted for the time of day (Scenery): cooler and paler in the morning,
// warm towards evening, with a glow round a low sun. Works in Forward+ and
// Compatibility.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform float energy = 0.8;
uniform vec3 tint : source_color = vec3(1.0);
// Warm light round the sun, strongest near the horizon (a low sun).
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float glow = 0.0;
// The horizon's own haze colour, which a low sun warms.
uniform vec3 horizon_tint : source_color = vec3(1.0);
// Saturation of the sky above the horizon band (1 as photographed).
// Forward+ raises it: its tone map and haze leave the photo's blue pale
// and milky (Lab b -14 against -26 in reference tee shots).
uniform float sky_depth = 1.0;
// The photo's own sun moved to where the game's sun is (Scenery reads it
// from the photo: FreeAssets.sky_sun). The panorama turns so the two
// bearings agree, and the sky between the horizon and the zenith is
// stretched a little so the heights agree too: the clouds the photo shows
// lit from one side are then lit from the side the shadows fall from.
// Whatever height is left over, the photo's sun is dimmed to a glow and
// the game's sun drawn as the disc. Off (`align_sun` false) the panorama
// shows as Godot maps it.
uniform bool align_sun = false;
uniform float photo_sun_u = 0.5; // the photo's sun: across (0 to 1)
uniform float photo_sun_elevation = 0.8; // and its height, radians
uniform float sun_u = 0.5; // the game's sun, in the same mapping
uniform float sun_elevation = 0.8; // radians, after the stretch's limit

void sky() {
	vec2 coords = SKY_COORDS;
	float dim_photo_sun = 1.0;
	if (align_sun) {
		float e = asin(clamp(EYEDIR.y, -1.0, 1.0));
		// Heights: the game's sun height maps to the photo's, the horizon
		// and the zenith stay put.
		float pe = e;
		if (e > 0.0) {
			pe = e < sun_elevation
				? e * photo_sun_elevation / sun_elevation
				: photo_sun_elevation + (e - sun_elevation) * (PI * 0.5 - photo_sun_elevation) / (PI * 0.5 - sun_elevation);
		}
		float u = atan(EYEDIR.x, -EYEDIR.z) / (2.0 * PI) + 0.5;
		coords = vec2(fract(u - sun_u + photo_sun_u), 0.5 - pe / PI);
		// The photo's sun is far brighter than the disc should be once
		// the game's light no longer comes from exactly there.
		float du = abs(fract(coords.x - photo_sun_u + 0.5) - 0.5) * 2.0 * PI * cos(photo_sun_elevation);
		float dv = (0.5 - coords.y) * PI - photo_sun_elevation;
		dim_photo_sun = smoothstep(0.012, 0.05, length(vec2(du, dv)));
	}
	vec3 c = texture(panorama, coords).rgb;
	if (align_sun) {
		c = mix(min(c, vec3(4.0)), c, dim_photo_sun);
	}
	c *= energy;
	float low = 1.0 - smoothstep(0.0, 0.35, abs(EYEDIR.y));
	c *= mix(tint, tint * horizon_tint, low);
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = max(mix(vec3(luma), c, mix(sky_depth, 1.0, low)), vec3(0.0));
	if (glow > 0.0 && LIGHT0_ENABLED) {
		float toward = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float halo = pow(toward, 8.0) * 0.6 + pow(toward, 64.0) * 1.5;
		c += glow_color * glow * halo * (0.4 + 0.6 * low);
	}
	if (align_sun && LIGHT0_ENABLED) {
		// The game's own sun disc, about a degree across.
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		c += LIGHT0_COLOR * LIGHT0_ENERGY * 40.0 * smoothstep(0.99995, 0.99998, d);
	}
	COLOR = c;
}
