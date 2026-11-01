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
		"cap": cap, "cap_colour": cap_colour.to_html(false), "glove": glove,
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
## get one from their name.
static func random(seed_value: int) -> PlayerLook:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var l := PlayerLook.new()
	var female := rng.randf() < 0.35
	l.sex = 1.0 if female else 0.0
	l.height_cm = clampf(rng.randfn(165.0 if female else 178.0, 7.0), HEIGHT_MIN, HEIGHT_MAX)
	l.weight = clampf(rng.randfn(0.05, 0.4), -1.0, 1.0)
	l.muscle = clampf(rng.randfn(0.0, 0.35), -1.0, 1.0)
	l.age = clampf(rng.randf_range(-0.9, 0.8), -1.0, 1.0)
	for entry: Array in FACE:
		l.face[entry[0]] = snappedf(clampf(rng.randfn(0.0, 0.35), -1.0, 1.0), 0.01)
	l.skin = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)][1]
	var dark_skin := SKIN_TONES.find(_nearest(SKIN_TONES, l.skin)) >= 5
	var styles := ["ponytail", "bob", "long", "short", "afro"] if female else ["short", "crop", "side_part", "short", "bald", "afro"]
	l.hair = styles[rng.randi_range(0, styles.size() - 1)]
	if l.hair == "afro" and not dark_skin and rng.randf() < 0.8:
		l.hair = "short"
	var colours := 3 if dark_skin else HAIR_COLOURS.size() - 2
	l.hair_colour = HAIR_COLOURS[rng.randi_range(0, colours - 1)][1]
	if l.age > 0.5 and rng.randf() < 0.7:
		l.hair_colour = HAIR_COLOURS[6 + rng.randi_range(0, 1)][1]
	l.eyes = EYES[rng.randi_range(0, 1 if dark_skin else EYES.size() - 1)]
	l.outfit = OUTFITS[rng.randi_range(0, OUTFITS.size() - 1)]
	l.top = CLOTH_COLOURS[rng.randi_range(0, CLOTH_COLOURS.size() - 1)][1]
	var trousers := [0, 2, 3, 4, 5, 6, 1]
	l.bottom = CLOTH_COLOURS[trousers[rng.randi_range(0, trousers.size() - 1)]][1]
	l.shoes = [Color(1, 1, 1), Color(0.12, 0.12, 0.13), Color(0.45, 0.3, 0.2)][rng.randi_range(0, 2)]
	l.cap = rng.randf() < 0.5
	l.cap_colour = CLOTH_COLOURS[rng.randi_range(0, CLOTH_COLOURS.size() - 1)][1]
	l.shaft = SHAFTS[rng.randi_range(0, SHAFTS.size() - 1)]
	return l


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
