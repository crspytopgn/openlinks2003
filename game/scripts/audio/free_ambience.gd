class_name FreeAmbience
extends Node
## Background sound for courses without their own (the free build, the
## legacy courses and the player's designs): looping field recordings from
## game/assets/sounds/ (see CREDITS.md there). A bed chosen by the kind of
## course (parkland birdsong, woodland, a seaside with waves and gulls, or
## desert heat and cicadas), wind in the trees that rises with the wind, and
## running water on holes that have water near the tee.

enum Setting { PARKLAND, WOODLAND, SEASIDE, DESERT }

const BEDS := {
	Setting.PARKLAND: "amb_parkland",
	Setting.WOODLAND: "amb_woodland",
	Setting.SEASIDE: "amb_seaside",
	Setting.DESERT: "amb_desert",
}
## Words in a course's name that say what kind of place it is.
const KEYWORDS := {
	Setting.SEASIDE: ["links", "bay", "beach", "ocean", "sea", "coast", "harbour", "harbor", "cliff", "dune",
		"island", "shore", "pebble", "kiawah", "lagoon", "reef", "surf"],
	Setting.DESERT: ["desert", "canyon", "mesa", "arizona", "nevada", "scottsdale", "vegas", "sonoran",
		"cactus", "saguaro"],
	Setting.WOODLAND: ["forest", "wood", "pine", "oak", "timber", "glen", "valley", "lake", "highland",
		"mountain", "ridge", "falls"],
}

const BED_DB := -12.0
const WATER_DB := -16.0
const BREEZE_DB := -14.0  ## at WINDY_MPS; quieter in light air
const WINDY_MPS := 8.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.5
const WATER_RANGE_M := 60.0  ## water this close to the tee is heard

var setting: Setting = Setting.PARKLAND
var _bed: AudioStreamPlayer
var _breeze: AudioStreamPlayer
var _water: AudioStreamPlayer
var _tweens := {}


static func create(course: CourseData) -> FreeAmbience:
	var a := FreeAmbience.new()
	a.name = "FreeAmbience"
	a.setting = setting_for(course.course_name)
	return a


## The kind of place a course is, from its name; parkland when the name
## doesn't say.
static func setting_for(course_name: String) -> Setting:
	var words := course_name.to_lower().replace("-", " ").replace("'", " ").split(" ", false)
	for s: Setting in [Setting.SEASIDE, Setting.DESERT, Setting.WOODLAND]:
		for w in words:
			for k: String in KEYWORDS[s]:
				if w == k or (k.length() > 4 and w.begins_with(k)):
					return s
	return Setting.PARKLAND


## Whether the hole has water within WATER_RANGE_M of the tee.
static func water_near_tee(hole: HoleData) -> bool:
	if hole.terrain == null:
		return false
	var step := 15.0
	var r := WATER_RANGE_M
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if Vector2(x, z).length() <= r and hole.terrain.surface_at(hole.tee.x + x, hole.tee.z + z) == Surface.Type.WATER:
				return true
			z += step
		x += step
	return false


func _ready() -> void:
	_bed = _player(BEDS[setting])
	_breeze = _player("amb_breeze")
	_water = _player("amb_water")
	_fade(_bed, BED_DB)


func _player(stem: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = stem
	p.volume_db = SILENT_DB
	var stream := load("res://assets/sounds/%s.ogg" % stem) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	add_child(p)
	return p


## A new hole: water if there is some by the tee, and the wind in the trees
## as strong as the wind (m/s).
func start_hole(hole: HoleData, wind_mps: float) -> void:
	_fade(_water, WATER_DB if water_near_tee(hole) else SILENT_DB)
	set_wind(wind_mps)


func set_wind(wind_mps: float) -> void:
	var k := clampf(wind_mps / WINDY_MPS, 0.0, 1.5)
	_fade(_breeze, SILENT_DB if k < 0.05 else BREEZE_DB + linear_to_db(maxf(k, 0.05)))


## Fades `p` to `db`, starting it if it is silent and stopping it once it
## has faded out.
func _fade(p: AudioStreamPlayer, db: float) -> void:
	if p.stream == null:
		return
	var old: Tween = _tweens.get(p)
	if old != null and old.is_valid():
		old.kill()
	if db > SILENT_DB and not p.playing:
		p.volume_db = SILENT_DB
		p.play(randf() * p.stream.get_length())
	if not is_inside_tree():
		p.volume_db = db
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", db, FADE_SECONDS)
	if db <= SILENT_DB:
		t.tween_callback(p.stop)
	_tweens[p] = t
