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
## Start of a result code (RoundRecord.to_code).
const CODE_PREFIX := "OLR1-"

var version := VERSION
var round_seed := 0
## "standard" (StandardShotModel) or "links" (LinksShotModel, needs the exe).
var model := "standard"
var course_key := ""
var course_name := ""
## The course file's name, to find it among a friend's courses ("" for the
## placeholder course).
var course_file := ""
## SHA-256 of the course file, so a checker knows it has the same course.
var course_hash := ""
var mode := 0
var holes := 0
var tees := 0
## RoundSetup.pins.
var pins := 0
var names: Array[String] = []
var computer: Array[int] = []
var wind_level := 0
## The greens the round played (LinksGround.GreenFirmness, GreenSpeed).
var green_firmness := LinksGround.GreenFirmness.MEDIUM
var green_speed := LinksGround.GreenSpeed.NORMAL
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
	r.course_file = setup.course_path.get_file()
	r.mode = setup.mode
	r.holes = setup.holes
	r.tees = setup.tees
	r.pins = setup.pins
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
		"course_name": course_name, "course_file": course_file, "course_hash": course_hash, "mode": mode, "holes": holes,
		"tees": tees, "names": names, "computer": computer, "wind_level": wind_level,
		"green_firmness": green_firmness, "green_speed": green_speed, "resumed": resumed, "started_at": started_at, "shots": list, "drops": drops,
		"cards": cards, "finished": finished, "pins": pins,
	}


static func from_dict(d: Dictionary) -> RoundRecord:
	var r := RoundRecord.new()
	r.version = int(d.get("version", 0))
	r.round_seed = int(d.get("seed", 0))
	r.model = str(d.get("model", "standard"))
	r.course_key = str(d.get("course_key", ""))
	r.course_name = str(d.get("course_name", ""))
	r.course_hash = str(d.get("course_hash", ""))
	r.course_file = str(d.get("course_file", ""))
	r.mode = int(d.get("mode", 0))
	r.holes = int(d.get("holes", 0))
	r.tees = int(d.get("tees", 0))
	r.pins = int(d.get("pins", 0))
	for n: Variant in d.get("names", []):
		r.names.append(str(n))
	for c: Variant in d.get("computer", []):
		r.computer.append(int(c))
	r.wind_level = int(d.get("wind_level", 0))
	r.green_firmness = clampi(int(d.get("green_firmness", LinksGround.GreenFirmness.MEDIUM)), 0, 2)
	r.green_speed = clampi(int(d.get("green_speed", LinksGround.GreenSpeed.NORMAL)), 0, 2)
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


## The round as text to send to a friend: CODE_PREFIX, then the record as
## gzipped JSON in URL-safe base64. A friend's game can check it
## (RoundReplay.check) and play the same course, tees and wind.
func to_code() -> String:
	var packed := to_json().to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return CODE_PREFIX + Marshalls.raw_to_base64(packed).replace("+", "-").replace("/", "_").replace("=", "")


## The round in a code from to_code, or null if it isn't one. Spaces and line
## breaks (from chat apps) are ignored.
static func from_code(code: String) -> RoundRecord:
	var t := code.strip_edges().replace(" ", "").replace("\n", "").replace("\r", "")
	if not t.begins_with(CODE_PREFIX):
		return null
	t = t.substr(CODE_PREFIX.length()).replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	var packed := Marshalls.base64_to_raw(t)
	if packed.is_empty():
		return null
	var raw := packed.decompress_dynamic(4 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	return from_json(raw.get_string_from_utf8())


## Each player's name and gross total, for showing a friend's round.
func summary() -> String:
	var parts: Array[String] = []
	for i in mini(names.size(), cards.size()):
		var total := 0
		for v: Variant in cards[i]:
			total += int(v)
		parts.append("%s %d" % [names[i], total])
	return ", ".join(parts)


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
