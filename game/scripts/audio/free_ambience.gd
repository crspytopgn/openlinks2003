class_name FreeAmbience
extends Node
## Background sound for courses without their own (the free build, the
## legacy courses and the player's designs), from game/assets/sounds/ (see
## CREDITS.md there). Like a real course on TV it is mostly quiet:
##
## - wind in the trees, always a little, rising with the wind;
## - a bed chosen by the kind of course (parkland or woodland birdsong, a
##   seaside with waves and gulls, desert cicadas), kept low, and lowest in
##   the middle of the day: birds sing most at dawn and again towards dusk;
## - now and then a bird calls from a tree somewhere round the player (a
##   snatch of the birdsong, from a point 25 to 90 m off, fainter and duller
##   the further it is), more often in the morning;
## - a far-off road, and in the morning or afternoon now and then a
##   greenkeeper's mower working somewhere out of sight;
## - running water on holes with water near the tee.

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

## The bed's level by time of day (Scenery.time_name). Birdsong is
## loudest at dawn and quietest in the midday heat; cicadas the other way.
const BIRDS_DB := {"morning": -21.0, "midday": -33.0, "afternoon": -30.0, "golden": -25.0}
const CICADAS_DB := {"morning": -26.0, "midday": -15.0, "afternoon": -17.0, "golden": -22.0}
const SEASIDE_DB := -15.0
## Seconds between birdcalls, by time of day.
const CALL_GAP := {"morning": Vector2(5.0, 14.0), "midday": Vector2(22.0, 50.0),
	"afternoon": Vector2(15.0, 38.0), "golden": Vector2(9.0, 24.0)}
const CALL_SECONDS := Vector2(1.2, 3.2)
const CALL_DISTANCE := Vector2(25.0, 90.0)  ## metres from the listener
const CALL_HEIGHT := Vector2(5.0, 14.0)  ## in a tree
const CALL_DB := 4.0  ## at CALL_UNIT metres; fainter further off
const CALL_UNIT := 12.0
const TRAFFIC_DB := {Setting.PARKLAND: -31.0, Setting.WOODLAND: -36.0, Setting.SEASIDE: -60.0, Setting.DESERT: -33.0}
const MOWER_DB := -27.0
const MOWER_GAP := Vector2(80.0, 220.0)  ## seconds between passes
const BREEZE_FLOOR_DB := -27.0  ## leaves stir even on a still day
const WATER_DB := -16.0
const BREEZE_DB := -14.0  ## at WINDY_MPS; quieter in light air
const WINDY_MPS := 8.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.5
const WATER_RANGE_M := 60.0  ## water this close to the tee is heard

var setting: Setting = Setting.PARKLAND
## GraphicsSettings.TimeOfDay and how far through the round (0 to 1), for
## the "Through the round" setting.
var time_of_day := 0
var round_progress := 0.0
var _bed: AudioStreamPlayer
var _breeze: AudioStreamPlayer
var _water: AudioStreamPlayer
var _traffic: AudioStreamPlayer
var _mower: AudioStreamPlayer
var _call: AudioStreamPlayer3D
var _tweens := {}
var _next_call := 3.0
var _next_mower := 40.0


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
	_traffic = _player("amb_traffic")
	_mower = _player("amb_mower", false)
	_call = AudioStreamPlayer3D.new()
	_call.name = "BirdCall"
	_call.unit_size = CALL_UNIT
	_call.volume_db = CALL_DB
	_call.attenuation_filter_cutoff_hz = 3500.0  # the air dulls far calls
	_call.stream = _bed.stream
	add_child(_call)
	_next_call = randf_range(2.0, 6.0)
	_next_mower = randf_range(30.0, MOWER_GAP.y)
	set_time(time_of_day, round_progress)
	_fade(_traffic, TRAFFIC_DB[setting])


## The bed's level for a kind of course at a time of day.
static func bed_db(p_setting: Setting, time: String) -> float:
	match p_setting:
		Setting.SEASIDE:
			return SEASIDE_DB
		Setting.DESERT:
			return CICADAS_DB[time]
	return BIRDS_DB[time]


## Whether the course gets birdcalls: not over the waves, nor in the desert
## (the bed there is cicadas).
static func has_calls(p_setting: Setting) -> bool:
	return p_setting == Setting.PARKLAND or p_setting == Setting.WOODLAND


## The time of day changed (or the round moved on, for "Through the round").
func set_time(p_time_of_day: int, progress: float) -> void:
	time_of_day = p_time_of_day
	round_progress = progress
	if _bed != null:
		_fade(_bed, bed_db(setting, Scenery.time_name(time_of_day, round_progress)))


func _process(delta: float) -> void:
	var time := Scenery.time_name(time_of_day, round_progress)
	_next_call -= delta
	if _next_call <= 0.0:
		var gap: Vector2 = CALL_GAP[time]
		_next_call = randf_range(gap.x, gap.y)
		if has_calls(setting):
			_bird_call()
	_next_mower -= delta
	if _next_mower <= 0.0:
		_next_mower = randf_range(MOWER_GAP.x, MOWER_GAP.y)
		# Greenkeepers mow in the morning, and some in the afternoon; never
		# in the evening light.
		if time != "golden" and setting != Setting.SEASIDE and not _mower.playing and _mower.stream != null:
			_mower.volume_db = MOWER_DB + randf_range(-4.0, 0.0)
			_mower.play()


## A snatch of the birdsong from a tree some way off.
func _bird_call() -> void:
	if _call.stream == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	var centre := cam.global_position if cam != null else Vector3.ZERO
	var a := randf() * TAU
	var d := randf_range(CALL_DISTANCE.x, CALL_DISTANCE.y)
	_call.global_position = Vector3(centre.x + cos(a) * d, centre.y + randf_range(CALL_HEIGHT.x, CALL_HEIGHT.y), centre.z + sin(a) * d)
	var length := randf_range(CALL_SECONDS.x, CALL_SECONDS.y)
	_call.pitch_scale = randf_range(0.94, 1.06)
	_call.volume_db = -40.0
	_call.play(randf() * maxf(_call.stream.get_length() - length, 0.0))
	var old: Tween = _tweens.get(_call)
	if old != null and old.is_valid():
		old.kill()
	var t := create_tween()
	t.tween_property(_call, "volume_db", CALL_DB, 0.25)
	t.tween_interval(maxf(length - 0.8, 0.2))
	t.tween_property(_call, "volume_db", -40.0, 0.55)
	t.tween_callback(_call.stop)
	_tweens[_call] = t


func _player(stem: String, looping := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = stem
	p.volume_db = SILENT_DB
	var stream := load("res://assets/sounds/%s.ogg" % stem) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = looping
	p.stream = stream
	add_child(p)
	return p


## A new hole: water if there is some by the tee, and the wind in the trees
## as strong as the wind (m/s).
func start_hole(hole: HoleData, wind_mps: float) -> void:
	_fade(_water, WATER_DB if water_near_tee(hole) else SILENT_DB)
	set_wind(wind_mps)


func set_wind(wind_mps: float) -> void:
	_fade(_breeze, breeze_db(wind_mps))


## Wind in the trees: a floor of stirring leaves, louder with the wind.
static func breeze_db(wind_mps: float) -> float:
	var k := clampf(wind_mps / WINDY_MPS, 0.0, 1.5)
	return maxf(BREEZE_FLOOR_DB, BREEZE_DB + linear_to_db(maxf(k, 0.01)))


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
