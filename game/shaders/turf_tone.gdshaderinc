// Real turf under the Photoreal light (turf_tone 1, Scenery sets it):
// measured against 50 sunny golf course photos (CIE Lab, 2026-11-01), our
// turf was a stop too dark and a neon yellow-green. Greens (pixels where
// green leads red and blue) are about 30% less saturated
// and nudged towards olive (the brightness comes from the exposure).
// Sand, paths and water are left alone.
global uniform float turf_tone;

vec3 tone_turf(vec3 c) {
	if (turf_tone <= 0.0) {
		return c;
	}
	float green = smoothstep(0.0, 0.04, c.g - max(c.r, c.b));
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 t = mix(vec3(luma), c, 0.72) * vec3(1.05, 1.0, 1.04);
	return mix(c, t, green * turf_tone);
}
