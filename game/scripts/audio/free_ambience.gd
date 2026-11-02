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
## - now and then a bird calls from a tree somewhere round the player, from
##   a point 25 to 90 m off, fainter and duller the further it is, more
##   often in the morning. Where the course is in the world is known, it is
##   one of that region's common birds (REGION_CALLS); otherwise a snatch of
##   the birdsong bed;
## - a far-off road, and in the morning or afternoon now and then a
##   greenkeeper's mower working somewhere out of sight;
## - running water near ponds and creeks.
##
## The mix follows where the camera is (the listener), checked twice a
## second and blended: under the trees the birds and the leaves are louder;
## out on an open fairway both drop away (on a seaside links the wind gets
## louder instead); water rises as the camera nears it. Birdcalls come from
## the hole's own trees round the listener, and seldom where there are none.

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
## Regional birdcalls (tools/audio/free_sounds.json): each file is a run of
## single calls, one per CALL_SLOT seconds, faded in and out, so a call is
## played from the start of a slot to its end.
const CALL_SLOT := 3.0
## Where each region's birds sing, (lat from, lat to, lon from, lon to), and
## the file of their calls: Britain and Ireland (robin, blackbird, wren, wood
## pigeon); the US South-east (cardinal, mockingbird, Carolina wren); the
## Pacific North-west (American robin, song and white-crowned sparrows);
## Australia (magpie, kookaburra). The first box holding a course wins.
const REGION_CALLS := [
	[49.5, 61.0, -11.0, 2.0, "calls_uk"],
	[24.0, 37.0, -95.0, -75.0, "calls_us_se"],
	[42.0, 50.0, -125.0, -116.0, "calls_pnw"],
	[-44.0, -10.0, 112.0, 154.0, "calls_aus"],
]
## A seaside links in Britain and Ireland: skylark, oystercatcher, herring gull.
const LINKS_CALLS := "calls_links"
const TRAFFIC_DB := {Setting.PARKLAND: -31.0, Setting.WOODLAND: -36.0, Setting.SEASIDE: -60.0, Setting.DESERT: -33.0}
const MOWER_DB := -27.0
const MOWER_GAP := Vector2(80.0, 220.0)  ## seconds between passes
const BREEZE_FLOOR_DB := -27.0  ## leaves stir even on a still day
const LISTEN_EVERY := 0.5  ## seconds between checks of the listener's spot
const TREE_RANGE := 40.0  ## trees this close count towards a wooded spot
const TREES_FULL := 18  ## this many in range is as wooded as it gets
const WATER_FULL_M := 12.0  ## water this close plays at WATER_DB
const WATER_HEARD_M := 80.0  ## and further than this is not heard
const WATER_STEP := 8.0  ## metres between samples when looking for water
## Open ground to woods: what the birds and leaves gain or lose (dB).
const OPEN_BIRDS_DB := -9.0
const WOODS_BIRDS_DB := 3.0
const OPEN_LEAVES_DB := -6.0
const WOODS_LEAVES_DB := 2.0
const LINKS_OPEN_WIND_DB := 4.0  ## a seaside links: more wind in the open
const RELEVEL_DB := 0.75  ## smaller changes are not worth a new fade
const WATER_DB := -16.0
const BREEZE_DB := -14.0  ## at WINDY_MPS; quieter in light air
const WINDY_MPS := 8.0
const SILENT_DB := -60.0
const FADE_SECONDS := 2.5

var setting: Setting = Setting.PARKLAND
## GraphicsSettings.TimeOfDay and how far through the round (0 to 1), for
## the "Through the round" setting.
var time_of_day := 0
## Somewhere warm: cicadas in the trees on a hot afternoon (is_warm).
var warm := false
var round_progress := 0.0
## The region's birdcalls (calls_for), or "" for snatches of the bed.
var calls := ""
var _bed: AudioStreamPlayer
var _breeze: AudioStreamPlayer
var _water: AudioStreamPlayer
var _traffic: AudioStreamPlayer
var _insects: AudioStreamPlayer
var _mower: AudioStreamPlayer
var _call: AudioStreamPlayer3D
var _tweens := {}
var _next_call := 3.0
var _next_mower := 40.0
var _hole: HoleData
var _wind := 0.0
var _listen := 0.0
var _levels := {}  ## player -> the level last faded to
## How wooded the listener's spot is (0 open, 1 in the trees) and how near
## water is (0 not heard, 1 right by it).
var woods := 0.5
var water := 0.0


static func create(course: CourseData) -> FreeAmbience:
	var a := FreeAmbience.new()
	a.name = "FreeAmbience"
	var at := location_of(course)
	a.setting = setting_for_place(course.course_name, at)
	a.warm = is_warm(at)
	a.calls = calls_for(at, a.setting)
	return a


## The file of birdcalls for a course at `at` (lat, lon) of kind
## `p_setting`, or "" when the place isn't known or has no set of its own.
static func calls_for(at: Vector2, p_setting: Setting) -> String:
	if is_nan(at.x):
		return ""
	for box: Array in REGION_CALLS:
		if at.x >= box[0] and at.x <= box[1] and at.y >= box[2] and at.y <= box[3]:
			if box[4] == "calls_uk" and p_setting == Setting.SEASIDE:
				return LINKS_CALLS
			return box[4]
	return ""


## Where in the world a course is, (latitude, longitude) in degrees, when it
## was built from a real place (the course from a map); NAN otherwise.
static func location_of(course: CourseData) -> Vector2:
	return course.location if course != null else Vector2(NAN, NAN)


## Hot dry places, (lat from, lat to, lon from, lon to): the deserts round
## Phoenix, Tucson, Las Vegas and Palm Springs; North Africa and the Gulf;
## inland Australia.
const ARID := [
	[31.0, 37.5, -118.0, -104.0],
	[15.0, 32.0, -17.0, 60.0],
	[-30.0, -19.0, 118.0, 145.0],
]
## Within this latitude summers are hot enough for cicadas in the trees
## (the US South, the Mediterranean, Australia, Japan).
const WARM_LATITUDE := 38.0


## The kind of place from where the course is in the world, when that is
## known, and its name: a name that says seaside wins (a links can be
## anywhere on a coast), then the climate (desert), then far north or south
## woodland, then what the name says.
static func setting_for_place(course_name: String, at: Vector2) -> Setting:
	var by_name := setting_for(course_name)
	if is_nan(at.x) or by_name == Setting.SEASIDE:
		return by_name
	for box: Array in ARID:
		if at.x >= box[0] and at.x <= box[1] and at.y >= box[2] and at.y <= box[3]:
			return Setting.DESERT
	if absf(at.x) >= 55.0:
		return Setting.WOODLAND
	return by_name


## Whether the course is somewhere with cicadas in the summer trees.
static func is_warm(at: Vector2) -> bool:
	return not is_nan(at.x) and absf(at.x) < WARM_LATITUDE


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


func _ready() -> void:
	_bed = _player(BEDS[setting])
	_breeze = _player("amb_breeze")
	_water = _player("amb_water")
	_traffic = _player("amb_traffic")
	_insects = _player("amb_desert")
	_mower = _player("amb_mower", false)
	_call = AudioStreamPlayer3D.new()
	_call.name = "BirdCall"
	_call.unit_size = CALL_UNIT
	_call.volume_db = CALL_DB
	_call.attenuation_filter_cutoff_hz = 3500.0  # the air dulls far calls
	_call.stream = _bed.stream
	if calls != "":
		var own := load("res://assets/sounds/%s.ogg" % calls) as AudioStream
		if own != null:
			if own is AudioStreamOggVorbis:
				(own as AudioStreamOggVorbis).loop = false
			_call.stream = own
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


## Whether the course gets birdcalls: not in the desert (the bed there is
## cicadas), nor over the waves, except on a links with its own shore birds.
static func has_calls(p_setting: Setting, p_calls := "") -> bool:
	return p_setting == Setting.PARKLAND or p_setting == Setting.WOODLAND or p_calls == LINKS_CALLS


## The time of day changed (or the round moved on, for "Through the round").
func set_time(p_time_of_day: int, progress: float) -> void:
	time_of_day = p_time_of_day
	round_progress = progress
	_apply()


## Levels for the listener's spot: {bed, breeze, water} in dB.
static func spot_levels(p_setting: Setting, time: String, wind_mps: float, p_woods: float, p_water: float) -> Dictionary:
	var bed := bed_db(p_setting, time)
	var breeze := breeze_db(wind_mps)
	if p_setting == Setting.SEASIDE:
		breeze += lerpf(LINKS_OPEN_WIND_DB, 0.0, p_woods)
	else:
		breeze += lerpf(OPEN_LEAVES_DB, WOODS_LEAVES_DB, p_woods)
		if p_setting != Setting.DESERT:
			bed += lerpf(OPEN_BIRDS_DB, WOODS_BIRDS_DB, p_woods)
	var wet := SILENT_DB if p_water <= 0.0 else lerpf(SILENT_DB * 0.5, WATER_DB, p_water)
	return {"bed": bed, "breeze": breeze, "water": wet}


## How wooded a spot is from the number of trees within TREE_RANGE.
static func woods_for(count: int) -> float:
	return clampf(float(count) / TREES_FULL, 0.0, 1.0)


## How near water sounds from its distance (INF for none in range).
static func water_for(distance_m: float) -> float:
	return clampf(1.0 - (distance_m - WATER_FULL_M) / (WATER_HEARD_M - WATER_FULL_M), 0.0, 1.0)


## The nearest water within WATER_HEARD_M of `at`, or INF.
static func water_distance(terrain: CourseTerrain, at: Vector3) -> float:
	if terrain == null:
		return INF
	var best := INF
	var n := int(WATER_HEARD_M / WATER_STEP)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var d := Vector2(i, j).length() * WATER_STEP
			if d >= best or d > WATER_HEARD_M:
				continue
			if terrain.surface_at(at.x + i * WATER_STEP, at.z + j * WATER_STEP) == Surface.Type.WATER:
				best = d
	return best


## Trees (the hole's objects) within TREE_RANGE of `at`.
static func trees_near(objects: Array[PlacedObject], at: Vector3) -> int:
	var n := 0
	var r2 := TREE_RANGE * TREE_RANGE
	for o in objects:
		var dx := o.position.x - at.x
		var dz := o.position.z - at.z
		if dx * dx + dz * dz <= r2:
			n += 1
	return n


func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	return _hole.tee if _hole != null else Vector3.ZERO


## Where the listener is: how wooded, how near water.
func _sense() -> void:
	if _hole == null:
		return
	var at := _listener()
	woods = woods_for(trees_near(_hole.objects, at)) if not _hole.objects.is_empty() else 0.5
	water = water_for(water_distance(_hole.terrain, at))


## Fades each layer to its level for the listener's spot.
func _apply() -> void:
	if _bed == null:
		return
	var l := spot_levels(setting, Scenery.time_name(time_of_day, round_progress), _wind, woods, water)
	_relevel(_bed, l.bed)
	_relevel(_breeze, l.breeze)
	_relevel(_water, l.water)
	_relevel(_insects, insects_db(setting, warm, Scenery.time_name(time_of_day, round_progress), woods))


## Cicadas in the trees somewhere warm, under the birds: loudest in the
## midday heat and among the trees. The desert's bed is cicadas already.
static func insects_db(p_setting: Setting, p_warm: bool, time: String, p_woods: float) -> float:
	if not p_warm or p_setting == Setting.DESERT or p_setting == Setting.SEASIDE:
		return SILENT_DB
	return CICADAS_DB[time] - 10.0 + lerpf(-6.0, 0.0, p_woods)


func _relevel(p: AudioStreamPlayer, db: float) -> void:
	var last: float = _levels.get(p, INF)
	if absf(last - db) < RELEVEL_DB:
		return
	_levels[p] = db
	_fade(p, db)


func _process(delta: float) -> void:
	_listen -= delta
	if _listen <= 0.0:
		_listen = LISTEN_EVERY
		_sense()
		_apply()
	var time := Scenery.time_name(time_of_day, round_progress)
	_next_call -= delta
	if _next_call <= 0.0:
		var gap: Vector2 = CALL_GAP[time]
		_next_call = randf_range(gap.x, gap.y)
		# Fewer calls out in the open, where there are few trees to sing in.
		if has_calls(setting, calls) and randf() < 0.25 + 0.75 * woods:
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
	var trees: Array[PlacedObject] = _hole.objects if _hole != null else []
	_call.global_position = call_spot(trees, _listener())
	var length := randf_range(CALL_SECONDS.x, CALL_SECONDS.y)
	var from := randf() * maxf(_call.stream.get_length() - length, 0.0)
	if calls != "" and _call.stream != _bed.stream:
		# A whole call from the region's set, at its own pitch.
		var slots := maxi(int(_call.stream.get_length() / CALL_SLOT), 1)
		from = (randi() % slots) * CALL_SLOT
		length = CALL_SLOT
		_call.pitch_scale = randf_range(0.98, 1.02)
	else:
		_call.pitch_scale = randf_range(0.94, 1.06)
	_call.volume_db = -40.0
	_call.play(from)
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


## Where a bird calls from: up in one of the trees CALL_DISTANCE from the
## listener, or (with none there) somewhere at that distance.
static func call_spot(objects: Array[PlacedObject], listener: Vector3) -> Vector3:
	var near: Array[Vector3] = []
	for o in objects:
		var d := Vector2(o.position.x - listener.x, o.position.z - listener.z).length()
		if d >= CALL_DISTANCE.x and d <= CALL_DISTANCE.y:
			near.append(o.position)
	var h := randf_range(CALL_HEIGHT.x, CALL_HEIGHT.y)
	if not near.is_empty():
		return near[randi() % near.size()] + Vector3.UP * h
	var a := randf() * TAU
	var r := randf_range(CALL_DISTANCE.x, CALL_DISTANCE.y)
	return Vector3(listener.x + cos(a) * r, listener.y + h, listener.z + sin(a) * r)


## A new hole, and the wind (m/s) for the trees.
func start_hole(hole: HoleData, wind_mps: float) -> void:
	_hole = hole
	_listen = 0.0
	set_wind(wind_mps)


func set_wind(wind_mps: float) -> void:
	_wind = wind_mps
	_apply()


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
