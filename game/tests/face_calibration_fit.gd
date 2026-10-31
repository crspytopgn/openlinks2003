extends SceneTree
## Part of tools/golfer/face_calibration.sh: from the rendered faces' known
## looks (truth.json) and MediaPipe's landmarks for them (landmarks.json),
## measures PlayerFaceFit's OFFSET, GAIN and WEIGHT on the first 3/4 of the
## faces, then checks the fit on the rest. Prints the constants to paste
## into player_face_fit.gd.

const REGULARISE_TRIES := [3e-4, 1e-3, 3e-3, 1e-2, 3e-2]
## Slider sets tried; the best is printed for PlayerFaceFit.FITTED.
const SLIDER_SETS := [
	["face_width", "face_length", "face_full", "jaw", "chin_height", "nose_width", "nose_length", "eye_size", "eye_spacing", "brows", "mouth_width", "lips"],
	["face_width", "face_full", "nose_width", "nose_length", "eye_spacing", "brows", "mouth_width"],
	["face_width", "face_length", "face_full", "nose_width", "nose_length", "eye_spacing", "brows", "mouth_width"],
	["face_full", "nose_width", "nose_length", "eye_spacing", "brows", "mouth_width"],
	["face_width", "face_full", "nose_width", "nose_length", "eye_size", "eye_spacing", "brows", "mouth_width"],
]


func _initialize() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var truth: Array = JSON.parse_string(FileAccess.get_file_as_string(dir + "/truth.json"))
	var marks: Array = JSON.parse_string(FileAccess.get_file_as_string(dir + "/landmarks.json"))
	var info: Dictionary = GolferParts.shared().info.face_fit
	var looks: Array[PlayerLook] = []
	var photos: Array[PackedVector2Array] = []
	var photo_f: Array[PackedFloat32Array] = []
	var model_f: Array[PackedFloat32Array] = []
	for k in truth.size():
		var flat: Array = marks[k]
		if flat.is_empty():
			continue
		var raw := PackedVector2Array()
		for i in flat.size() / 2:
			raw.append(Vector2(flat[2 * i], flat[2 * i + 1]))
		var look := PlayerLook.from_dict(truth[k])
		looks.append(look)
		photos.append(PlayerFaceFit.from_image(PlayerFaceFit.from_mediapipe(raw)))
		photo_f.append(PlayerFaceFit.features(photos[-1]))
		model_f.append(PlayerFaceFit.features(PlayerFaceFit.model_points(info, look.shape_weights())))
	var train := looks.size() * 3 / 4
	var n_feat := PlayerFaceFit.FEATURE_NAMES.size()
	var offset := []
	var gain := []
	var weight := []
	for i in n_feat:
		# Least squares line photo = offset + gain * model over the training faces.
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for k in train:
			var x := model_f[k][i]
			var y := photo_f[k][i]
			sx += x
			sy += y
			sxx += x * x
			sxy += x * y
		var g := (train * sxy - sx * sy) / (train * sxx - sx * sx)
		var c := (sy - g * sx) / train
		var r := 0.0
		for k in train:
			r += pow(photo_f[k][i] - c - g * model_f[k][i], 2)
		var sigma := sqrt(r / (train - 2))
		# A feature MediaPipe barely follows tells little about the face.
		g = maxf(g, 0.05)
		offset.append(c)
		gain.append(g)
		weight.append(g / sigma)
		print("%-14s offset %+.4f gain %.3f scatter %.4f" % [PlayerFaceFit.FEATURE_NAMES[i], c, g, sigma])
	var mean_w := 0.0
	for w: float in weight:
		mean_w += w
	mean_w /= weight.size()
	for i in weight.size():
		weight[i] = weight[i] / mean_w
	var varied: Array = SLIDER_SETS[0]
	var best := {"err": INF}
	var baseline := 0.0
	for sliders: Array in SLIDER_SETS:
		for l: float in REGULARISE_TRIES:
			var cal := {"offset": offset, "gain": gain, "weight": weight, "regularise": l, "sliders": sliders}
			var err := 0.0
			var per_key := {}
			baseline = 0.0
			for k in range(train, looks.size()):
				var fitted := PlayerFaceFit.fit(info, looks[k], photos[k], cal)
				for key: String in varied:
					var e := absf(float(fitted.get(key, 0.0)) - looks[k].face_value(key))
					err += e
					per_key[key] = float(per_key.get(key, 0.0)) + e / (looks.size() - train)
					baseline += absf(looks[k].face_value(key))
			err /= (looks.size() - train) * varied.size()
			baseline /= (looks.size() - train) * varied.size()
			if err < best.err:
				best = {"err": err, "regularise": l, "sliders": sliders, "per_key": per_key}
	print("best: mean slider error %.3f (%.3f leaving them in the middle), regularise %s" % [best.err, baseline, str(best.regularise)])
	for key: String in best.per_key:
		print("  %-12s error %.2f%s" % [key, best.per_key[key], "" if (best.sliders as Array).has(key) else " (not fitted)"])
	print("const FITTED := %s" % JSON.stringify(best.sliders))
	var fmt := func(a: Array) -> String: return "[" + ", ".join(a.map(func(x: float) -> String: return "%.4f" % x)) + "]"
	print("const OFFSET := %s" % fmt.call(offset))
	print("const GAIN := %s" % fmt.call(gain))
	print("const WEIGHT := %s" % fmt.call(weight))
	print("const REGULARISE := %s" % str(best.regularise))
	quit()
