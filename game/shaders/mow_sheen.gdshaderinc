// Mowing stripes as a real mower makes them. The stripes are not two
// colours of grass: the mower lays the blades one way down a strip and the
// other way down the next. Blades laid away from the eye show their long,
// light sides and read pale; blades laid towards it show their shaded
// undersides and the soil, and read dark. So the stripes are strongest
// looking along the mowing line, swap light for dark when you turn round
// (the tee looking down the hole against the green looking back) and all but
// vanish looking across them. Lower eyes (a long lens from the tee) see more
// of it than a camera looking straight down.
//
// mow_sheen() gives the signed contrast for a band: multiply the old,
// view-independent stripe term by it. `along` is the mowing line in world
// x, z (either sign; it only picks which band is the light one) and
// `from_eye` points from the camera to the ground point.
float mow_sheen(vec2 along, vec3 from_eye) {
	vec3 v = normalize(from_eye);
	float level = length(v.xz); // 1 looking level, 0 straight down
	if (level < 1e-4) {
		return 0.3;
	}
	float facing = dot(v.xz / level, normalize(along));
	// A faint pattern stays even across the stripes (cut height and colour
	// differ a little), and the sheen grows as the view lowers.
	return (0.2 + 1.4 * facing) * mix(0.6, 1.0, level);
}

// The mowing line where stripes are bands of a coordinate `u` interpolated
// over the mesh (for example metres across the hole): the direction in which
// u doesn't change, from its screen-space derivatives. Exact per triangle.
vec2 mow_line_from(float u, vec2 p) {
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float dux = dFdx(u);
	float duy = dFdy(u);
	float det = dpx.x * dpy.y - dpx.y * dpy.x;
	if (abs(det) < 1e-10) {
		return vec2(0.0, 1.0);
	}
	vec2 g = vec2(dux * dpy.y - duy * dpx.y, dpx.x * duy - dux * dpy.x) / det;
	float len = length(g);
	return len > 1e-6 ? vec2(-g.y, g.x) / len : vec2(0.0, 1.0);
}
