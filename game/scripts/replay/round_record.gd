class_name RoundRecord
extends RefCounted
## A whole round as its inputs: the setup, the round seed every random draw
## comes from, and each shot and drop. RoundReplay plays it again to check it.
## Finished rounds are kept in user://replays/. See docs/online-play.md.

const VERSION := 1
## Where finished rounds go; the tests point this somewhere else.
static var folder := "user://replays"
## How many finished rounds to keep.
const KEEP := 50

## Salts for shot_seed, one per random source in a shot.
const SALT_MOUSE := 1
const SALT_MODEL := 2

var version := VERSION
var round_seed := 0
## "standard" (StandardShotModel) or "links" (LinksShotModel, needs the exe).
var model := "standard"
var course_key := ""
var course_name := ""
## SHA-256 of the course file, so a checker knows it has the same course.
var course_hash := ""
var mode := 0
var holes := 0
var tees := 0
var names: Array[String] = []
var computer: Array[int] = []
var wind_level := 0
## Set when the round was carried on from a SavedRound: the wind before the
## resume can't be drawn again, so it can't be checked.
var resumed := false
var started_at := ""
var shots: Array[ShotRecord] = []
## Drops: {ball, hole, reason, penalty, spot: [x, y, z]}.
var drops: Array[Dictionary] = []
## Each player's strokes per hole when the round ended.
var cards: Array = []
var finished := false


## A 32-bit seed for random source `salt` in shot `shot` of the round seeded
## with `p_seed`: shots can be replayed one at a time, in any order.
static func shot_seed(p_seed: int, shot: int, salt: int) -> int:
	var h := (p_seed ^ (shot * 0x9E3779B1) ^ (salt * 0x85EBCA77)) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x7FEB352D) & 0xffffffff
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xffffffff
	h = h ^ (h >> 16)
	return h | 1


static func begin(setup: RoundSetup, p_seed: int, model_name: String, level: int) -> RoundRecord:
	var r := RoundRecord.new()
	r.round_seed = p_seed
	r.model = model_name
	r.course_key = setup.course_key
	r.course_name = setup.course_name
	r.course_hash = file_hash(setup.course_path)
	r.mode = setup.mode
	r.holes = setup.holes
	r.tees = setup.tees
	r.names = setup.names.duplicate()
	r.computer = setup.computer.duplicate()
	r.wind_level = level
	r.started_at = Time.get_datetime_string_from_system(true, false)
	return r


static func file_hash(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


func shots_on(ball: int, hole: int) -> Array[ShotRecord]:
	var out: Array[ShotRecord] = []
	for s in shots:
		if s.ball == ball and s.hole == hole:
			out.append(s)
	return out


func to_dict() -> Dictionary:
	var list: Array = []
	for s in shots:
		list.append(s.to_dict())
	return {
		"version": version, "seed": round_seed, "model": model, "course_key": course_key,
		"course_name": course_name, "course_hash": course_hash, "mode": mode, "holes": holes,
		"tees": tees, "names": names, "computer": computer, "wind_level": wind_level,
		"resumed": resumed, "started_at": started_at, "shots": list, "drops": drops,
		"cards": cards, "finished": finished,
	}


static func from_dict(d: Dictionary) -> RoundRecord:
	var r := RoundRecord.new()
	r.version = int(d.get("version", 0))
	r.round_seed = int(d.get("seed", 0))
	r.model = str(d.get("model", "standard"))
	r.course_key = str(d.get("course_key", ""))
	r.course_name = str(d.get("course_name", ""))
	r.course_hash = str(d.get("course_hash", ""))
	r.mode = int(d.get("mode", 0))
	r.holes = int(d.get("holes", 0))
	r.tees = int(d.get("tees", 0))
	for n: Variant in d.get("names", []):
		r.names.append(str(n))
	for c: Variant in d.get("computer", []):
		r.computer.append(int(c))
	r.wind_level = int(d.get("wind_level", 0))
	r.resumed = bool(d.get("resumed", false))
	r.started_at = str(d.get("started_at", ""))
	for s: Variant in d.get("shots", []):
		if s is Dictionary:
			r.shots.append(ShotRecord.from_dict(s))
	for x: Variant in d.get("drops", []):
		if x is Dictionary:
			r.drops.append(x)
	for c: Variant in d.get("cards", []):
		var card: Array[int] = []
		for v: Variant in c:
			card.append(int(v))
		r.cards.append(card)
	r.finished = bool(d.get("finished", false))
	return r


func to_json() -> String:
	return JSON.stringify(to_dict(), "", false, true)


static func from_json(text: String) -> RoundRecord:
	var d: Variant = JSON.parse_string(text)
	return from_dict(d) if d is Dictionary else null


## Writes the round to the replays folder and keeps the newest KEEP; returns
## the file's path, or "" if it couldn't be written.
func save() -> String:
	var dir := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := started_at.replace(":", "").replace("-", "")
	var path := "%s/%s-%08x.json" % [folder, stamp, round_seed & 0xffffffff]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_json())
	f.close()
	var files := Array(DirAccess.get_files_at(dir)).filter(func(n: String) -> bool: return n.ends_with(".json"))
	files.sort()
	while files.size() > KEEP:
		DirAccess.remove_absolute(dir + "/" + str(files.pop_front()))
	return path


static func load_file(path: String) -> RoundRecord:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))
