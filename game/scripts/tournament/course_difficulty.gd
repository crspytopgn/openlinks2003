class_name CourseDifficulty
extends RefCounted
## How a course really plays for computer golfers, learned from their real
## rounds. The simulated field scores from tour odds (Tournament.HOLE_ODDS),
## but a course's real difficulty under our physics can differ: each time a
## computer golfer in the person's group finishes a real round, the strokes
## it took beyond what the simulation expected for it are kept per course,
## and the rest of the field plays that much harder (or easier) there.
##
## The shift is per 18 holes and shrinks towards 0 until a few rounds are in,
## so one wild round moves it only a little.

const PRIOR_ROUNDS := 3.0  ## rounds' worth of "no shift" it starts from
const MAX_ROUND_DELTA := 12.0  ## one round can't move it more than this
const MAX_SHIFT := 8.0

static var path := "user://course_difficulty.cfg"


## Strokes per 18 holes the field should add on `course_key`.
static func shift(course_key: String) -> float:
	var row := _row(course_key)
	return clampf(row[0] / (row[1] + PRIOR_ROUNDS), -MAX_SHIFT, MAX_SHIFT)


## The real rounds behind shift(course_key).
static func rounds(course_key: String) -> int:
	return int(_row(course_key)[1])


## Adds one computer golfer's real round on `course_key`: `delta_18` is its
## strokes beyond the simulation's expectation, per 18 holes.
static func add(course_key: String, delta_18: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var row := _row(course_key, cfg)
	row[0] += clampf(delta_18, -MAX_ROUND_DELTA, MAX_ROUND_DELTA)
	row[1] += 1.0
	cfg.set_value("courses", _key(course_key), row)
	cfg.save(path)


static func remove() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _row(course_key: String, cfg: ConfigFile = null) -> PackedFloat64Array:
	if cfg == null:
		cfg = ConfigFile.new()
		cfg.load(path)
	var v: Variant = cfg.get_value("courses", _key(course_key), null)
	if v is PackedFloat64Array and (v as PackedFloat64Array).size() == 2:
		return (v as PackedFloat64Array).duplicate()
	if v is Array and (v as Array).size() == 2:
		return PackedFloat64Array([float(v[0]), float(v[1])])
	return PackedFloat64Array([0.0, 0.0])


## ConfigFile keys must be plain words.
static func _key(course_key: String) -> String:
	return "c" + course_key.md5_text()
