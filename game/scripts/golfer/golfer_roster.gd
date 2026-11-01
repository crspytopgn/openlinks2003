class_name GolferRoster
extends RefCounted
## The tour's golfers: sixteen fictional professionals, each with a look of
## their own (PlayerLook) for the free golfer. Computer opponents and the
## career field use them, and any other name gets a stable random look
## (look_for), so a field of any size is varied.
##
## The bodies follow real tour players: men average about 180 cm and the
## women about 168 cm, most are lean and athletic, ages run from early
## twenties to fifties, and the field is international. The clothes are
## tour apparel: a plain polo with tailored trousers in the colour pairs
## the tours wear (navy, white, black, greys and one bright colour), a
## structured cap, white or dark golf shoes and a white glove. Women wear
## trousers here too, as the look pack has no skort yet.
##
## The names are made up; any likeness to a real player is chance.
## The appearance is all this file owns: how each one plays lives with the
## computer golfers (game/scripts/ai/), keyed by the same names.

## [name, country, sex (0 man, 1 woman), age in years, height cm, build,
## muscle, skin tone (PlayerLook.SKIN_TONES), hair style, hair colour
## (PlayerLook.HAIR_COLOURS), eyes, stubble, top, trousers, cap (or "" for
## none), shoes, face sliders].
const PROS := [
	["Callum Reid", "SCO", 0, 29, 183, 0.1, 0.2, "Fair", "short", "Auburn", "blue", 0.35,
		"Navy", "White", "White", "White", {"face_length": 0.3, "jaw": 0.25, "nose_length": 0.2, "brows": -0.2}],
	["Marcus Bell", "USA", 0, 27, 188, 0.0, 0.55, "Dark", "crop", "Black", "brown", 0.2,
		"White", "Black", "Black", "White", {"face_width": 0.15, "cheekbones": 0.4, "jaw": 0.45, "nose_width": 0.5, "lips": 0.45}],
	["Kenji Morita", "JPN", 0, 33, 174, -0.15, 0.0, "Light", "side_part", "Black", "brown", 0.05,
		"Black", "Charcoal", "Black", "Black", {"face_width": 0.25, "face_length": -0.2, "nose_bridge": -0.4, "eye_size": -0.35, "brows": 0.1}],
	["Henrik Lindqvist", "SWE", 0, 46, 191, 0.15, 0.1, "Porcelain", "side_part", "Blonde", "blue", 0.15,
		"Sky blue", "Grey", "Navy", "White", {"face_length": 0.45, "chin": 0.4, "nose_length": 0.35, "cheekbones": 0.3}],
	["Daniel Okafor", "ENG", 0, 31, 185, 0.05, 0.4, "Deep", "bald", "Black", "brown", 0.5,
		"Grey", "Navy", "Navy", "Black", {"face_full": -0.2, "jaw": 0.3, "chin": 0.2, "nose_width": 0.45, "lips": 0.5}],
	["Ryan Cole", "USA", 0, 23, 185, -0.2, 0.25, "Fair", "short", "Blonde", "green", 0.0,
		"Pink", "White", "White", "White", {"face_full": -0.25, "chin": 0.25, "eye_spacing": 0.15, "nose_width": -0.2}],
	["Sanjay Mehta", "IND", 0, 36, 172, 0.25, 0.0, "Brown", "short", "Black", "brown", 0.6,
		"Royal blue", "Black", "", "Black", {"face_full": 0.3, "nose_length": 0.3, "nose_bridge": 0.35, "brows": -0.25, "lips": 0.2}],
	["Tom Brennan", "IRL", 0, 54, 178, 0.55, 0.0, "Fair", "short", "Grey", "blue", 0.25,
		"Green", "Stone", "White", "Black", {"face_width": 0.35, "face_full": 0.45, "jaw": 0.2, "nose_width": 0.3, "ears": 0.3}],
	["Luis Navarro", "MEX", 0, 38, 176, 0.3, 0.2, "Tan", "side_part", "Dark brown", "brown", 0.7,
		"Red", "Black", "Black", "Black", {"face_width": 0.3, "cheekbones": 0.2, "jaw": 0.35, "nose_width": 0.25, "lips": 0.2}],
	["Mateo Ibarra", "ARG", 0, 26, 180, -0.05, 0.3, "Olive", "crop", "Dark brown", "hazel", 0.55,
		"Charcoal", "White", "Charcoal", "White", {"face_length": 0.2, "nose_bridge": 0.45, "nose_length": 0.25, "chin": 0.3}],
	["Seo-yeon Han", "KOR", 1, 24, 165, -0.15, 0.1, "Light", "ponytail", "Black", "brown", 0.0,
		"White", "Navy", "White", "White", {"face_width": 0.2, "face_length": -0.25, "nose_bridge": -0.45, "eye_size": -0.25, "cheekbones": 0.2}],
	["Emma Larsen", "DEN", 1, 28, 173, -0.1, 0.2, "Porcelain", "ponytail", "Blonde", "blue", 0.0,
		"Navy", "White", "Navy", "White", {"face_length": 0.3, "cheekbones": 0.35, "nose_length": 0.15, "lips": -0.1}],
	["Aiko Tanaka", "JPN", 1, 31, 158, -0.1, 0.0, "Light", "bob", "Black", "brown", 0.0,
		"Pink", "White", "", "White", {"face_width": 0.1, "face_length": -0.35, "nose_bridge": -0.4, "eye_size": -0.2, "mouth_width": -0.2}],
	["Grace Mensah", "CAN", 1, 26, 171, 0.0, 0.35, "Brown", "ponytail", "Black", "brown", 0.0,
		"Yellow", "Black", "Black", "White", {"cheekbones": 0.45, "nose_width": 0.4, "lips": 0.5, "jaw": -0.1}],
	["Sofia Ricci", "ITA", 1, 34, 166, 0.05, 0.1, "Olive", "long", "Dark brown", "hazel", 0.0,
		"Black", "Black", "", "Black", {"face_length": 0.2, "nose_bridge": 0.25, "eye_size": 0.2, "lips": 0.3, "brows": 0.15}],
	["Brooke Ashford", "USA", 1, 42, 169, 0.2, 0.15, "Light", "ponytail", "Brown", "green", 0.0,
		"Purple", "Grey", "White", "White", {"face_width": 0.15, "face_full": 0.2, "chin": 0.15, "nose_length": -0.15}],
]

## The face sliders above are written small; at that size every face came
## out alike next to photos of a real field, so they are scaled up.
const FACE_SCALE := 1.7
## Added to each woman's face: the average differences between women's and
## men's faces in photos (a softer, narrower jaw and smaller chin, higher
## brows, larger eyes, a narrower nose, fuller lips), which the body's
## "female" shape alone leaves too square, worst under a cap.
const FEMININE := {
	"jaw": -0.45, "chin": -0.3, "chin_height": -0.2, "brows": 0.3, "eye_size": 0.25,
	"nose_width": -0.3, "nose_length": -0.15, "lips": 0.3, "face_width": -0.15, "cheekbones": 0.2,
}

static var _golfers: Array[Dictionary] = []


## Every roster golfer: {name, country, age, look}, in the order above.
static func golfers() -> Array[Dictionary]:
	if _golfers.is_empty():
		for row: Array in PROS:
			_golfers.append({"name": row[0], "country": row[1], "age": row[3], "look": _make(row)})
	return _golfers


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for g in golfers():
		out.append(g["name"])
	return out


## The roster golfer called `golfer_name` (any case), or {}.
static func find(golfer_name: String) -> Dictionary:
	var key := golfer_name.strip_edges().to_lower()
	for g in golfers():
		if str(g["name"]).to_lower() == key:
			return g
	return {}


## The look for a golfer called `golfer_name`: the roster's if they are on
## it, otherwise a random one that is always the same for the name.
static func look_for(golfer_name: String) -> PlayerLook:
	var g := find(golfer_name)
	if not g.is_empty():
		return (g["look"] as PlayerLook).duplicate_look()
	return PlayerLook.random(golfer_name.strip_edges().to_lower().hash())


## The age slider for an age in years: the look pack's average body is 25,
## and its "old" shape is 90.
static func age_slider(years: float) -> float:
	if years >= 25.0:
		return clampf((years - 25.0) / 65.0, 0.0, 1.0)
	return clampf((years - 25.0) / 24.0, -1.0, 0.0)


static func _make(row: Array) -> PlayerLook:
	var l := PlayerLook.new()
	l.sex = float(row[2])
	l.age = age_slider(float(row[3]))
	l.height_cm = float(row[4])
	l.weight = float(row[5])
	l.muscle = float(row[6])
	l.skin = _named(PlayerLook.SKIN_TONES, row[7], l.skin)
	l.hair = row[8]
	l.hair_colour = _named(PlayerLook.HAIR_COLOURS, row[9], l.hair_colour)
	l.eyes = row[10]
	l.stubble = float(row[11])
	l.outfit = "polo"
	l.top = _named(PlayerLook.CLOTH_COLOURS, row[12], l.top)
	l.bottom = _named(PlayerLook.CLOTH_COLOURS, row[13], l.bottom)
	l.cap = str(row[14]) != ""
	if l.cap:
		l.cap_colour = _named(PlayerLook.CLOTH_COLOURS, row[14], l.cap_colour)
	l.shoes = _named(PlayerLook.CLOTH_COLOURS, row[15], l.shoes)
	var f: Dictionary = row[16]
	for entry: Array in PlayerLook.FACE:
		var key: String = entry[0]
		var v := float(f.get(key, 0.0)) * FACE_SCALE
		if l.sex >= 0.5:
			v += float(FEMININE.get(key, 0.0))
		l.face[key] = clampf(v, -1.0, 1.0)
	# Tour bags and clubs: mostly black heads, graphite in the woods.
	l.shaft = "graphite" if hash(row[0]) % 3 == 0 else "steel"
	return l


static func _named(options: Array, option_name: String, fallback: Color) -> Color:
	for o: Array in options:
		if o[0] == option_name:
			return o[1]
	push_warning("GolferRoster: no colour called " + option_name)
	return fallback
