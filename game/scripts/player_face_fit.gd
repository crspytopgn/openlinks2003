class_name PlayerFaceFit
extends RefCounted
## Fits the player creator's face sliders to a photo of a face.
##
## The photo gives 2D positions for a few face landmarks (POINTS): found
## automatically in the browser (game/web/face_photo.js, MediaPipe's Face
## Landmarker, Apache-2.0, run on the player's device) or tapped by the
## player. The same landmarks on the golfer's head, and how each body and
## face shape moves them, are in the look pack's "face_fit" header (written by
## tools/golfer/face_landmarks.py). Both sets are turned into measurements
## that don't depend on the photo's size or tilt (features()), and the
## sliders are fitted to match by regularised least squares (fit()).
##
## Skin and hair colours are read from patches of the photo (skin_colour(),
## hair_colour()). Nothing is uploaded or saved: the photo is only held while
## the player creator is open.

## The landmarks, in the order of the look pack's face_fit.points. "Right"
## and "left" are the person's own (their right eye is on the left of a
## photo).
const POINTS := [
	"r_eye_outer", "r_eye_inner", "l_eye_inner", "l_eye_outer",
	"r_brow", "l_brow",
	"nose_tip", "r_nose_wing", "l_nose_wing",
	"r_mouth", "l_mouth", "upper_lip", "lower_lip",
	"chin", "r_jaw", "l_jaw", "r_cheek", "l_cheek", "r_jaw_low", "l_jaw_low",
]
## What the player is asked to tap for each point.
const POINT_LABELS := [
	"Outer corner of your right eye (on the left of the photo)",
	"Inner corner of your right eye",
	"Inner corner of your left eye",
	"Outer corner of your left eye",
	"Middle of your right eyebrow",
	"Middle of your left eyebrow",
	"Tip of your nose",
	"Right edge of your nose (left in the photo)",
	"Left edge of your nose",
	"Right corner of your mouth (left in the photo)",
	"Left corner of your mouth",
	"Top edge of your upper lip, in the middle",
	"Bottom edge of your lower lip, in the middle",
	"Bottom of your chin",
	"Right edge of your jaw, level with your mouth",
	"Left edge of your jaw, level with your mouth",
	"Right edge of your face, just below your eyes",
	"Left edge of your face, just below your eyes",
	"Right edge of your jaw, a little over halfway from mouth to chin",
	"Left edge of your jaw, a little over halfway from mouth to chin",
]
## MediaPipe Face Landmarker mesh indices for each point (averaged when
## there are several).
const MEDIAPIPE := [
	[33], [133], [362], [263],
	[105, 52], [334, 282],
	[1], [98], [327],
	[61], [291], [0], [17],
	[152], [172], [397], [234], [454], [150], [379],
]
## The sliders fitted. Chin, nose bridge and ears are depth or side-on
## shapes a photo from the front can't measure, so they are left alone.
const FITTED := [
	"face_width", "face_full", "nose_width", "nose_length", "eye_size", "eye_spacing", "brows", "mouth_width",
]
const FEATURE_NAMES := [
	"eye_width", "eye_gap", "brow_height", "nose_length", "nose_width",
	"mouth_width", "mouth_drop", "lip_height", "chin_length", "jaw_width", "cheek_width", "low_jaw_width",
]
## How a photo's measurements relate to the golfer's for the same face:
## photo = OFFSET + GAIN * golfer. The golfer's landmarks are mesh vertices
## and a photo's are where MediaPipe places them, and MediaPipe leans
## towards an average face (it reports about a third of a nose's real
## change in width). WEIGHT is how much each measurement counts in the fit:
## its gain over its scatter. All three are measured by
## tools/golfer/face_calibration.sh from MediaPipe on renders of golfers
## with known faces.
const OFFSET := [0.1324, 0.2670, 0.1158, 0.0889, 0.2595, 0.2061, 0.0862, 0.1562, 0.3758, 0.4079, 0.2364, 0.3230]
const GAIN := [0.5921, 0.4263, 0.7739, 0.8861, 0.3330, 0.6721, 0.9102, 0.5163, 0.2869, 0.6092, 0.8442, 0.5378]
const WEIGHT := [1.2708, 0.5008, 2.3131, 1.2999, 0.5068, 0.6765, 2.4155, 0.3891, 0.1658, 0.5983, 0.9231, 0.9402]
## Pulls the sliders towards the middle; larger trusts the photo less.
const REGULARISE := 0.003
const ITERATIONS := 10
const STEP := 0.02


## Photo pixel positions (x right, y down) to the face frame (y up).
static func from_image(pixels: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pixels:
		out.append(Vector2(p.x, -p.y))
	return out


## The POINTS from a MediaPipe result: every mesh landmark, in pixels.
static func from_mediapipe(landmarks: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for ids: Array in MEDIAPIPE:
		var sum := Vector2.ZERO
		for i: int in ids:
			if i >= landmarks.size():
				return PackedVector2Array()
			sum += landmarks[i]
		out.append(sum / ids.size())
	return out


## The face's measurements from its landmarks (face frame): turned so the
## eyes are level and scaled by the face's size (the geometric mean of the
## eyes' outer span and the drop from eyes to mouth, so neither the eyes nor
## the mouth alone set the scale).
static func features(points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if points.size() != POINTS.size():
		return out
	var r_eye := (points[0] + points[1]) * 0.5
	var l_eye := (points[2] + points[3]) * 0.5
	var span := points[0].distance_to(points[3])
	if span < 1e-6:
		return out
	var centre := (r_eye + l_eye) * 0.5
	var angle := (l_eye - r_eye).angle()
	var drop := absf(((points[9] + points[10]) * 0.5 - centre).rotated(-angle).y)
	var size := sqrt(span * drop)
	if size < 1e-6:
		return out
	var p := PackedVector2Array()
	for q in points:
		p.append((q - centre).rotated(-angle) / size)
	var eye_y := (p[0].y + p[1].y + p[2].y + p[3].y) * 0.25
	var mouth_y := (p[9].y + p[10].y) * 0.5
	out.append(((p[3].x - p[2].x) + (p[1].x - p[0].x)) * 0.5)
	out.append(p[2].x - p[1].x)
	out.append((p[4].y + p[5].y) * 0.5 - eye_y)
	out.append(eye_y - p[6].y)
	out.append(p[8].x - p[7].x)
	out.append(p[10].x - p[9].x)
	out.append(eye_y - mouth_y)
	out.append(p[11].y - p[12].y)
	out.append(mouth_y - p[13].y)
	out.append(p[15].x - p[14].x)
	out.append(p[17].x - p[16].x)
	out.append(p[19].x - p[18].x)
	return out


## The golfer's landmarks (face frame, metres) with these shape weights.
static func model_points(face_fit: Dictionary, weights: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for b: Array in face_fit.base:
		out.append(Vector2(b[0], b[1]))
	var shapes: Dictionary = face_fit.shapes
	for shape: String in weights:
		var w := float(weights[shape])
		if is_zero_approx(w) or not shapes.has(shape):
			continue
		var d: Array = shapes[shape]
		for i in out.size():
			out[i] += Vector2(d[i][0], d[i][1]) * w
	return out


## The face slider values (FITTED key -> -1..1) that make `look`'s golfer
## match a photo's landmarks (face frame). `look`'s body (sex, build, age)
## is kept; its face sliders are replaced. `calibration` replaces OFFSET,
## GAIN and WEIGHT (keys "offset", "gain", "weight", "regularise"). Empty if
## the pack has no face_fit or the points are unusable.
static func fit(face_fit: Dictionary, look: PlayerLook, photo: PackedVector2Array, calibration := {}) -> Dictionary:
	var target := features(photo)
	if target.is_empty() or not face_fit.has("base"):
		return {}
	var offset: Array = calibration.get("offset", OFFSET)
	var gain: Array = calibration.get("gain", GAIN)
	var weight: Array = calibration.get("weight", WEIGHT)
	var regularise := float(calibration.get("regularise", REGULARISE))
	var sliders: Array = calibration.get("sliders", FITTED)
	for i in target.size():
		target[i] = (target[i] - float(offset[i])) / float(gain[i])
	var trial := look.duplicate_look()
	for key: String in sliders:
		trial.face[key] = 0.0
	var w := PackedFloat32Array()
	w.resize(sliders.size())
	var n := sliders.size()
	var m := target.size()
	var sq := PackedFloat32Array()
	for i in m:
		sq.append(float(weight[i]) * float(weight[i]))
	for _iteration in ITERATIONS:
		var f := _features_at(face_fit, trial, sliders, w)
		var jac: Array[PackedFloat32Array] = []
		for k in n:
			var h := STEP
			if absf(w[k]) < 1e-3:
				# At the middle the shape changes from the "minus" to the
				# "plus" target: use the mean slope of the two.
				var up := w.duplicate()
				up[k] = h
				var down := w.duplicate()
				down[k] = -h
				var fu := _features_at(face_fit, trial, sliders, up)
				var fd := _features_at(face_fit, trial, sliders, down)
				var col := PackedFloat32Array()
				for i in m:
					col.append((fu[i] - fd[i]) / (2.0 * h))
				jac.append(col)
			else:
				h = STEP * signf(w[k])
				if absf(w[k] + h) > 1.0:
					h = -h
				var moved := w.duplicate()
				moved[k] += h
				var fm := _features_at(face_fit, trial, sliders, moved)
				var col := PackedFloat32Array()
				for i in m:
					col.append((fm[i] - f[i]) / h)
				jac.append(col)
		# (J'WJ + lambda I) delta = J'W(target - f) - lambda w
		var a: Array[PackedFloat64Array] = []
		var rhs := PackedFloat64Array()
		for r in n:
			var row := PackedFloat64Array()
			row.resize(n)
			for c in n:
				var s := 0.0
				for i in m:
					s += jac[r][i] * jac[c][i] * sq[i]
				row[c] = s + (regularise if r == c else 0.0)
			a.append(row)
			var b := -regularise * w[r]
			for i in m:
				b += jac[r][i] * (target[i] - f[i]) * sq[i]
			rhs.append(b)
		var delta := _solve(a, rhs)
		if delta.is_empty():
			break
		var biggest := 0.0
		for k in n:
			var next := clampf(w[k] + delta[k], -1.0, 1.0)
			biggest = maxf(biggest, absf(next - w[k]))
			w[k] = next
		if biggest < 1e-3:
			break
	var out := {}
	for k in n:
		out[sliders[k]] = snappedf(w[k], 0.01)
	return out


static func _features_at(face_fit: Dictionary, look: PlayerLook, sliders: Array, w: PackedFloat32Array) -> PackedFloat32Array:
	for k in sliders.size():
		look.face[sliders[k]] = w[k]
	return features(model_points(face_fit, look.shape_weights()))


## Solves a x = b (Gaussian elimination with partial pivoting); empty if
## singular.
static func _solve(a: Array[PackedFloat64Array], b: PackedFloat64Array) -> PackedFloat64Array:
	var n := b.size()
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(a[r][col]) > absf(a[pivot][col]):
				pivot = r
		if absf(a[pivot][col]) < 1e-12:
			return PackedFloat64Array()
		if pivot != col:
			var t := a[col]
			a[col] = a[pivot]
			a[pivot] = t
			var tb := b[col]
			b[col] = b[pivot]
			b[pivot] = tb
		for r in range(col + 1, n):
			var factor := a[r][col] / a[col][col]
			if factor == 0.0:
				continue
			var row := a[r]
			for c in range(col, n):
				row[c] -= factor * a[col][c]
			a[r] = row
			b[r] -= factor * b[col]
	var x := PackedFloat64Array()
	x.resize(n)
	for r in range(n - 1, -1, -1):
		var s := b[r]
		for c in range(r + 1, n):
			s -= a[r][c] * x[c]
		x[r] = s / a[r][r]
	return x


## The skin colour: the middle colour of patches on both cheeks and the
## forehead. `pixels` are the POINTS in photo pixels.
static func skin_colour(image: Image, pixels: PackedVector2Array) -> Color:
	var span := pixels[0].distance_to(pixels[3])
	var brows := (pixels[4] + pixels[5]) * 0.5
	var spots := [
		pixels[7].lerp(pixels[16], 0.5),
		pixels[8].lerp(pixels[17], 0.5),
		brows + (brows - pixels[6]).normalized() * span * 0.22,
	]
	var samples: Array[Color] = []
	for spot: Vector2 in spots:
		samples.append_array(_patch(image, spot, maxi(2, int(span * 0.05))))
	return _middle(samples)


## The hair colour from above the forehead, or transparent if that's off
## the photo.
static func hair_colour(image: Image, pixels: PackedVector2Array) -> Color:
	var span := pixels[0].distance_to(pixels[3])
	var brows := (pixels[4] + pixels[5]) * 0.5
	var up := (brows - pixels[13]).normalized()
	var spot := brows + up * span * 0.85
	var samples := _patch(image, spot, maxi(2, int(span * 0.06)))
	if samples.size() < 4:
		return Color.TRANSPARENT
	return _middle(samples)


static func _patch(image: Image, centre: Vector2, radius: int) -> Array[Color]:
	var out: Array[Color] = []
	var step := maxi(1, radius / 4)
	for y in range(int(centre.y) - radius, int(centre.y) + radius + 1, step):
		for x in range(int(centre.x) - radius, int(centre.x) + radius + 1, step):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				out.append(image.get_pixel(x, y))
	return out


## Per-channel median.
static func _middle(colours: Array[Color]) -> Color:
	if colours.is_empty():
		return Color.TRANSPARENT
	var channels: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for c in colours:
		channels[0].append(c.r)
		channels[1].append(c.g)
		channels[2].append(c.b)
	var out := Color(0, 0, 0)
	for i in 3:
		channels[i].sort()
		out[i] = channels[i][channels[i].size() / 2]
	return out
