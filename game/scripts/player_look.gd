class_name PlayerLook
extends RefCounted
## How a player's golfer looks, made in the player creator (PlayerCreator)
## and saved with their profile (PlayerProfiles): body, height, skin, face,
## hair, eyes, clothes and equipment. FreeGolfer builds the golfer from it
## (with GolferParts); the original game's golfer ignores it.
##
## Body and face sliders run from -1 to 1 (0 is the average) and map to the
## blend shapes in the look pack: slider "x" uses shapes "x_minus" and
## "x_plus". Colours multiply the pack's grey detail textures.

## Face sliders, in the order the creator lists them: [key, label, -1 end, +1 end].
const FACE := [
	["face_width", "Face width", "narrow", "wide"],
	["face_length", "Face length", "short", "long"],
	["face_full", "Cheeks", "lean", "full"],
	["cheekbones", "Cheekbones", "soft", "high"],
	["jaw", "Jaw", "narrow", "wide"],
	["chin", "Chin", "receding", "strong"],
	["chin_height", "Chin height", "short", "tall"],
	["nose_width", "Nose width", "narrow", "wide"],
	["nose_length", "Nose length", "short", "long"],
	["nose_bridge", "Nose bridge", "straight", "hooked"],
	["eye_size", "Eyes", "small", "large"],
	["eye_spacing", "Eye spacing", "close", "wide"],
	["brows", "Brows", "low", "high"],
	["mouth_width", "Mouth", "narrow", "wide"],
	["lips", "Lips", "thin", "full"],
	["ears", "Ears", "small", "large"],
]
## Body sliders: [key, label, -1 end, +1 end] (sex runs 0 to 1).
const BODY := [
	["weight", "Build", "slim", "heavy"],
	["muscle", "Muscle", "slight", "muscular"],
	["age", "Age", "younger", "older"],
]
const HAIR_STYLES := ["short", "crop", "side_part", "ponytail", "bob", "long", "afro", "bald"]
const HAIR_NAMES := ["Short", "Crop", "Side part", "Ponytail", "Bob", "Long", "Afro", "Bald"]
## Hair styles the cap is shaped for; with the others the cap is left off.
const CAP_HAIR := ["short", "crop", "side_part", "ponytail", "bald"]
const OUTFITS := ["polo", "sleeves", "shorts"]
const OUTFIT_NAMES := ["Polo and trousers", "Long sleeves and trousers", "Polo and shorts"]
const EYES := ["brown", "hazel", "green", "blue", "grey"]
const SHAFTS := ["steel", "graphite", "black"]
const HEIGHT_MIN := 150.0
const HEIGHT_MAX := 205.0

## Skin tones, lightest first: [name, colour].
const SKIN_TONES := [
	["Porcelain", Color(1.0, 0.84, 0.75)],
	["Fair", Color(0.95, 0.74, 0.61)],
	["Light", Color(0.9, 0.68, 0.52)],
	["Olive", Color(0.8, 0.6, 0.42)],
	["Tan", Color(0.7, 0.5, 0.34)],
	["Brown", Color(0.56, 0.38, 0.26)],
	["Dark", Color(0.42, 0.28, 0.19)],
	["Deep", Color(0.3, 0.2, 0.14)],
]
const HAIR_COLOURS := [
	["Black", Color(0.1, 0.09, 0.09)],
	["Dark brown", Color(0.22, 0.16, 0.13)],
	["Brown", Color(0.35, 0.28, 0.23)],
	["Auburn", Color(0.55, 0.28, 0.16)],
	["Ginger", Color(0.8, 0.45, 0.22)],
	["Blonde", Color(0.92, 0.74, 0.48)],
	["Grey", Color(0.62, 0.62, 0.62)],
	["White", Color(0.95, 0.95, 0.93)],
]
## Clothes, cap and grip colours.
const CLOTH_COLOURS := [
	["Navy", Color(0.13, 0.24, 0.45)],
	["White", Color(1.0, 1.0, 1.0)],
	["Black", Color(0.12, 0.12, 0.13)],
	["Charcoal", Color(0.3, 0.31, 0.33)],
	["Grey", Color(0.62, 0.63, 0.65)],
	["Stone", Color(0.85, 0.75, 0.59)],
	["Khaki", Color(0.62, 0.55, 0.38)],
	["Red", Color(0.75, 0.1, 0.12)],
	["Pink", Color(1.0, 0.55, 0.7)],
	["Orange", Color(1.0, 0.5, 0.12)],
	["Yellow", Color(1.0, 0.85, 0.25)],
	["Green", Color(0.15, 0.45, 0.25)],
	["Sky blue", Color(0.5, 0.75, 1.0)],
	["Royal blue", Color(0.15, 0.3, 0.85)],
	["Purple", Color(0.4, 0.2, 0.55)],
]
const BALL_COLOURS := [
	["White", Color(1, 1, 1)],
	["Yellow", Color(0.95, 1.0, 0.3)],
	["Orange", Color(1.0, 0.55, 0.15)],
	["Pink", Color(1.0, 0.5, 0.75)],
]

var sex := 0.0  ## 0 male, 1 female
var height_cm := 175.0
var weight := 0.0
var muscle := 0.0
var age := 0.0
var face := {}  ## FACE key -> -1..1
var skin := Color(0.95, 0.74, 0.61)
var hair := "short"
var hair_colour := Color(0.35, 0.28, 0.23)
var eyes := "brown"
var outfit := "polo"
var top := Color(0.13, 0.24, 0.45)
var bottom := Color(0.85, 0.75, 0.59)
var shoes := Color(1, 1, 1)
var cap := true  ## a golf cap (most tour players wear one)
## Beard shadow on the jaw, chin and upper lip, 0 clean-shaven to 1 a few
## days' growth (the colour follows the hair).
var stubble := 0.0
var cap_colour := Color(1, 1, 1)
## A white glove on the left hand.
var glove := true
## Equipment: driver head colour, shaft finish, grip colour, ball colour.
var club_head := Color(0.06, 0.06, 0.07)
var shaft := "steel"
var grip := Color(0.05, 0.05, 0.055)
var ball := Color(1, 1, 1)


## The blend shape weights: shape name -> weight.
func shape_weights() -> Dictionary:
	var w := {}
	if sex > 0.0:
		w["female"] = clampf(sex, 0.0, 1.0)
	_pair(w, "thin", "heavy", weight)
	_pair(w, "slight", "muscular", muscle)
	_pair(w, "young", "old", age)
	for key: String in face:
		_pair(w, key + "_minus", key + "_plus", float(face[key]))
	return w


static func _pair(w: Dictionary, minus: String, plus: String, v: float) -> void:
	v = clampf(v, -1.0, 1.0)
	if v < 0.0:
		w[minus] = -v
	elif v > 0.0:
		w[plus] = v


func face_value(key: String) -> float:
	return float(face.get(key, 0.0))


## True when the cap is on and the hair style suits it.
func wears_cap() -> bool:
	return cap and CAP_HAIR.has(hair)


func to_dict() -> Dictionary:
	var f := {}
	for key: String in face:
		if not is_zero_approx(float(face[key])):
			f[key] = snappedf(float(face[key]), 0.001)
	return {
		"sex": snappedf(sex, 0.001), "height_cm": snappedf(height_cm, 0.1), "weight": snappedf(weight, 0.001),
		"muscle": snappedf(muscle, 0.001), "age": snappedf(age, 0.001), "face": f,
		"skin": skin.to_html(false), "hair": hair, "hair_colour": hair_colour.to_html(false), "eyes": eyes,
		"outfit": outfit, "top": top.to_html(false), "bottom": bottom.to_html(false), "shoes": shoes.to_html(false),
		"cap": cap, "cap_colour": cap_colour.to_html(false), "glove": glove, "stubble": snappedf(stubble, 0.001),
		"club_head": club_head.to_html(false), "shaft": shaft, "grip": grip.to_html(false), "ball": ball.to_html(false),
	}


## A look from to_dict()'s output; missing or unknown values keep the defaults.
static func from_dict(d: Dictionary) -> PlayerLook:
	var l := PlayerLook.new()
	l.sex = clampf(float(d.get("sex", l.sex)), 0.0, 1.0)
	l.height_cm = clampf(float(d.get("height_cm", l.height_cm)), HEIGHT_MIN, HEIGHT_MAX)
	l.weight = clampf(float(d.get("weight", 0.0)), -1.0, 1.0)
	l.muscle = clampf(float(d.get("muscle", 0.0)), -1.0, 1.0)
	l.age = clampf(float(d.get("age", 0.0)), -1.0, 1.0)
	var f: Variant = d.get("face", {})
	if f is Dictionary:
		for entry: Array in FACE:
			if (f as Dictionary).has(entry[0]):
				l.face[entry[0]] = clampf(float(f[entry[0]]), -1.0, 1.0)
	l.skin = _colour(d, "skin", l.skin)
	l.hair = _choice(d, "hair", HAIR_STYLES, l.hair)
	l.hair_colour = _colour(d, "hair_colour", l.hair_colour)
	l.eyes = _choice(d, "eyes", EYES, l.eyes)
	l.outfit = _choice(d, "outfit", OUTFITS, l.outfit)
	l.top = _colour(d, "top", l.top)
	l.bottom = _colour(d, "bottom", l.bottom)
	l.shoes = _colour(d, "shoes", l.shoes)
	l.cap = d.get("cap", true) == true
	l.cap_colour = _colour(d, "cap_colour", l.cap_colour)
	l.glove = d.get("glove", true) != false
	l.stubble = clampf(float(d.get("stubble", 0.0)), 0.0, 1.0)
	l.club_head = _colour(d, "club_head", l.club_head)
	l.shaft = _choice(d, "shaft", SHAFTS, l.shaft)
	l.grip = _colour(d, "grip", l.grip)
	l.ball = _colour(d, "ball", l.ball)
	return l


static func _colour(d: Dictionary, key: String, fallback: Color) -> Color:
	var s := str(d.get(key, ""))
	return Color.html(s) if Color.html_is_valid(s) else fallback


static func _choice(d: Dictionary, key: String, options: Array, fallback: String) -> String:
	var s := str(d.get(key, fallback))
	return s if options.has(s) else fallback


func duplicate_look() -> PlayerLook:
	return from_dict(to_dict())


## A text key that is equal for equal looks.
func key() -> String:
	return JSON.stringify(to_dict(), "", true)


## A plausible random golfer, the same for the same seed: computer golfers
## get one from their name (GolferRoster.look_for). The odds follow real
## golfers: hair and eye colours go with the skin tone (red hair is rare),
## hair greys from the forties, women mostly tie their hair back, and the
## clothes are tour pairings (a polo, neutral trousers, a cap that matches
## one of them or is white).
static func random(seed_value: int) -> PlayerLook:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var l := PlayerLook.new()
	var female := rng.randf() < 0.35
	l.sex = 1.0 if female else 0.0
	l.height_cm = clampf(rng.randfn(168.0 if female else 180.0, 6.5), HEIGHT_MIN, HEIGHT_MAX)
	l.weight = clampf(rng.randfn(0.05, 0.3), -0.8, 0.9)
	l.muscle = clampf(rng.randfn(0.1, 0.3), -0.8, 0.9)
	# 20 to 55 years old, most in their late twenties and thirties.
	var years := clampf(rng.randfn(33.0, 8.0), 20.0, 58.0)
	l.age = GolferRoster.age_slider(years)
	for entry: Array in FACE:
		l.face[entry[0]] = snappedf(clampf(rng.randfn(0.0, 0.3), -1.0, 1.0), 0.01)
	var tone := _pick(rng, [10, 16, 18, 14, 12, 12, 10, 8])
	l.skin = SKIN_TONES[tone][1]
	var hair_odds: Array
	if tone >= 5:
		hair_odds = [85, 15, 0, 0, 0, 0]
	elif tone >= 3:
		hair_odds = [50, 38, 12, 0, 0, 0]
	else:
		hair_odds = [12, 32, 30, 6, 3, 17]
	l.hair_colour = HAIR_COLOURS[_pick(rng, hair_odds)][1]
	if rng.randf() < clampf((years - 40.0) / 20.0, 0.0, 0.85):
		l.hair_colour = HAIR_COLOURS[6 if rng.randf() < 0.8 else 7][1]
	if female:
		l.hair = ["ponytail", "ponytail", "ponytail", "bob", "long"][rng.randi_range(0, 4)]
	elif tone >= 5:
		l.hair = ["crop", "crop", "short", "bald", "afro"][rng.randi_range(0, 4)]
	else:
		l.hair = ["short", "short", "crop", "side_part", "side_part"][rng.randi_range(0, 4)]
		if rng.randf() < clampf((years - 30.0) / 50.0, 0.0, 0.3):
			l.hair = "bald"
	l.eyes = EYES[_pick(rng, [100, 0, 0, 0, 0] if tone >= 5 else ([70, 20, 5, 5, 0] if tone >= 3 else [30, 15, 12, 33, 10]))]
	if not female:
		l.stubble = snappedf(clampf(rng.randfn(0.25, 0.25), 0.0, 0.8), 0.01)
	l.outfit = OUTFITS[_pick(rng, [75, 15, 0 if female else 10])]
	var tops := [0, 1, 1, 2, 3, 4, 7, 8, 10, 11, 12, 13, 14, 9]
	var top := tops[rng.randi_range(0, tops.size() - 1)] as int
	l.top = CLOTH_COLOURS[top][1]
	var trousers := [0, 1, 2, 3, 4, 5, 6]
	var bottom := top
	while bottom == top:
		bottom = trousers[rng.randi_range(0, trousers.size() - 1)]
	l.bottom = CLOTH_COLOURS[bottom][1]
	l.shoes = [Color(1, 1, 1), Color(1, 1, 1), Color(0.12, 0.12, 0.13), Color(0.45, 0.3, 0.2)][rng.randi_range(0, 3)]
	l.cap = rng.randf() < 0.7
	l.cap_colour = CLOTH_COLOURS[[top, bottom, 1, 1][rng.randi_range(0, 3)]][1]
	l.shaft = SHAFTS[_pick(rng, [55, 35, 10])]
	return l


## An index into `odds`, picked with those relative weights.
static func _pick(rng: RandomNumberGenerator, odds: Array) -> int:
	var total := 0.0
	for o: Variant in odds:
		total += float(o)
	var r := rng.randf() * total
	for i in odds.size():
		r -= float(odds[i])
		if r < 0.0:
			return i
	return odds.size() - 1


## The named entry of `options` ([name, colour] pairs) closest to `c`.
static func _nearest(options: Array, c: Color) -> Array:
	var best: Array = options[0]
	var best_d := INF
	for o: Array in options:
		var oc: Color = o[1]
		var d := Vector3(oc.r - c.r, oc.g - c.g, oc.b - c.b).length_squared()
		if d < best_d:
			best_d = d
			best = o
	return best
