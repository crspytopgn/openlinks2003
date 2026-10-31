class_name FreeSoundBank
extends SoundBank
## Real recorded sounds for playing without the original game files: club
## strikes by club type and lie, the ball landing by surface, the cup, water,
## the crowd, footsteps and the clubs in the bag. All are cut from CC0 and
## CC BY field recordings (game/assets/sounds/CREDITS.md, built by
## tools/audio/build_free_sounds.py). Each event has a few takes; one is
## picked at random and played with a small change of pitch and level, so
## repeats don't sound canned.

const DIR := "res://assets/sounds/"

## Event (or event variant) -> file stem; the takes are <stem>_1, _2, ...
const STEMS := {
	&"hit_driver": "hit_driver",
	&"hit_wood": "hit_wood",
	&"hit_iron": "hit_iron",
	&"hit_wedge": "hit_wedge",
	&"putt": "putt",
	&"lie_rough": "lie_rough",
	&"lie_sand": "lie_sand",
	&"land_grass": "land_grass",
	&"land_green": "land_green",
	&"land_sand": "land_sand",
	&"cup": "cup",
	&"splash": "splash",
	&"applause": "applause",
	&"crowd_tee": "tee",
	&"crowd_cheer": "cheer",
	&"crowd_roar": "roar",
	&"crowd_groan": "groan",
	&"crowd_ooh": "ooh",
	&"footsteps": "footsteps",
	&"club": "club",
}

## Level of each sound in the mix (dB), and how far its pitch may wander.
const VOLUME_DB := {
	&"putt": -4.0, &"lie_rough": -5.0, &"lie_sand": -3.0, &"land_grass": -10.0, &"land_green": -12.0,
	&"land_sand": -9.0, &"cup": -3.0, &"splash": -4.0, &"applause": -6.0, &"crowd_tee": -9.0,
	&"crowd_cheer": -5.0, &"crowd_roar": -3.0, &"crowd_groan": -6.0, &"crowd_ooh": -6.0,
	&"footsteps": -14.0, &"club": -12.0,
}
const PITCH_SPREAD := 0.04
const CROWD_PITCH_SPREAD := 0.02
const MAX_TAKES := 8

var _takes := {}  ## stem -> Array[AudioStream]
var _last := {}  ## stem -> index of the take played last
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## The takes of an event, loaded on first use.
func takes(stem: String) -> Array:
	if _takes.has(stem):
		return _takes[stem]
	var list: Array = []
	for i in range(1, MAX_TAKES + 1):
		var path := "%s%s_%d.ogg" % [DIR, stem, i]
		if not ResourceLoader.exists(path):
			break
		var s := load(path) as AudioStream
		if s != null:
			list.append(s)
	_takes[stem] = list
	return list


func play(event: StringName) -> void:
	play_detail(event, {})


## Details used: "club" (a Club) and "lie" (Surface.Type) for &"hit" and
## &"putt"; "surface" (Surface.Type) and "speed" (m/s) for &"land";
## "power" (0..1) for &"hit".
func play_detail(event: StringName, detail: Dictionary) -> void:
	match event:
		&"hit":
			var club: Club = detail.get("club")
			var kind := SoundBank.club_kind(club) if club != null else &"iron"
			var power := float(detail.get("power", 1.0))
			var lie := int(detail.get("lie", Surface.Type.FAIRWAY))
			var gain := linear_to_db(clampf(0.45 + 0.55 * power, 0.3, 1.0))
			if kind == &"putter":
				_play(&"putt", gain)
				return
			if lie == Surface.Type.SAND:
				# Out of a bunker the sand is most of the sound.
				_play(&"lie_sand", gain)
				_play(StringName("hit_" + kind), gain - 9.0)
				return
			_play(StringName("hit_" + kind), gain)
			if lie == Surface.Type.ROUGH or lie == Surface.Type.DEEP_ROUGH:
				_play(&"lie_rough", gain + (0.0 if lie == Surface.Type.DEEP_ROUGH else -4.0))
		&"putt":
			_play(&"putt", 0.0)
		&"land":
			var surface := int(detail.get("surface", Surface.Type.FAIRWAY))
			var speed := float(detail.get("speed", 20.0))
			var gain := linear_to_db(clampf(speed / 30.0, 0.25, 1.0))
			match surface:
				Surface.Type.SAND:
					_play(&"land_sand", gain)
				Surface.Type.GREEN, Surface.Type.FRINGE:
					_play(&"land_green", gain)
				Surface.Type.WATER:
					pass  # the splash plays when the shot ends
				_:
					_play(&"land_grass", gain)
		_:
			if STEMS.has(event):
				_play(event, 0.0)


## Plays one take of `event` (a key of STEMS), `gain_db` above its level.
func _play(event: StringName, gain_db: float) -> void:
	var stem: String = STEMS.get(event, "")
	var list := takes(stem)
	if list.is_empty():
		return
	var i := _rng.randi_range(0, list.size() - 1)
	if list.size() > 1 and i == int(_last.get(stem, -1)):
		i = (i + 1) % list.size()
	_last[stem] = i
	var p := AudioStreamPlayer.new()
	p.stream = list[i]
	p.volume_db = float(VOLUME_DB.get(event, 0.0)) + gain_db
	var spread := CROWD_PITCH_SPREAD if stem in ["applause", "tee", "cheer", "roar", "groan", "ooh"] else PITCH_SPREAD
	p.pitch_scale = 1.0 + _rng.randf_range(-spread, spread)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
