class_name SavedRound
extends RefCounted
## The round in progress, saved before every shot and at the end of each
## hole so it can be resumed from the main menu after quitting (or closing the
## game). Kept in user://saved_round.cfg; cleared once the round is over.
##
## What it keeps: the setup, everyone's card, the hole, the honour, whose turn
## it is and where each ball lies. The wind is drawn again on resume.

## Where the round is kept; the tests point this somewhere else.
static var path := "user://saved_round.cfg"


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func clear() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Saves `setup` with the round state: {hole, fresh (the hole hasn't
## started), current, honour, cards: [[strokes per hole], ...], balls:
## [{at, strokes, holed, picked_up}, ...]}.
static func save(setup: RoundSetup, state: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "course_key", setup.course_key)
	cfg.set_value("setup", "course_name", setup.course_name)
	cfg.set_value("setup", "mode", setup.mode)
	cfg.set_value("setup", "holes", setup.holes)
	cfg.set_value("setup", "tees", setup.tees)
	cfg.set_value("setup", "pins", setup.pins)
	cfg.set_value("setup", "pin_seed", setup.pin_seed)
	cfg.set_value("setup", "names", PackedStringArray(setup.names))
	cfg.set_value("setup", "teams", PackedInt32Array(setup.teams))
	cfg.set_value("setup", "computer", PackedInt32Array(setup.computer))
	cfg.set_value("setup", "handicaps", setup.handicaps)
	cfg.set_value("setup", "indexes", PackedInt32Array(setup.indexes))
	cfg.set_value("setup", "career", setup.career)
	cfg.set_value("setup", "saved_at", Time.get_datetime_string_from_system(false, true))
	for key: String in state:
		cfg.set_value("round", key, state[key])
	cfg.save(path)


## The saved setup (course_path left empty: the caller finds the course from
## course_key), or null if there is no saved round or it can't be read.
static func load_setup() -> RoundSetup:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("round"):
		return null
	var s := RoundSetup.new()
	s.course_key = cfg.get_value("setup", "course_key", "")
	s.course_name = cfg.get_value("setup", "course_name", "")
	s.mode = clampi(cfg.get_value("setup", "mode", 0), 0, GameModes.MODE_NAMES.size() - 1) as GameModes.Mode
	s.holes = clampi(cfg.get_value("setup", "holes", 0), 0, RoundSetup.HOLES_NAMES.size() - 1) as RoundSetup.Holes
	s.tees = clampi(cfg.get_value("setup", "tees", 0), 0, RoundSetup.TEES_NAMES.size() - 1) as RoundSetup.Tees
	s.handicaps = cfg.get_value("setup", "handicaps", false) == true
	s.career = str(cfg.get_value("setup", "career", ""))
	s.pins = clampi(int(cfg.get_value("setup", "pins", 0)), 0, RoundSetup.PINS_NAMES.size() - 1)
	s.pin_seed = int(cfg.get_value("setup", "pin_seed", 0))
	var saved_names: PackedStringArray = cfg.get_value("setup", "names", PackedStringArray())
	if saved_names.is_empty() or saved_names.size() > RoundSetup.MAX_PLAYERS:
		return null
	s.names.clear()
	for n in saved_names:
		s.names.append(n)
	s.teams.clear()
	for t in cfg.get_value("setup", "teams", PackedInt32Array()) as PackedInt32Array:
		s.teams.append(t)
	for i in cfg.get_value("setup", "indexes", PackedInt32Array()) as PackedInt32Array:
		s.indexes.append(i)
	while s.teams.size() < s.names.size():
		s.teams.append(s.teams.size() % 2)
	s.computer.clear()
	var saved_computer: PackedInt32Array = cfg.get_value("setup", "computer", PackedInt32Array())
	for i in s.names.size():
		s.computer.append(clampi(saved_computer[i], RoundSetup.HUMAN, OpponentSkill.LEVEL_NAMES.size() - 1) if i < saved_computer.size() else RoundSetup.HUMAN)
	return s


## The saved round state (see save), or {} if there is none.
static func load_state() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("round"):
		return {}
	var out := {}
	for key in cfg.get_section_keys("round"):
		out[key] = cfg.get_value("round", key)
	return out


## "Pebble Beach, hole 7, Ann & Bob" for the Resume button.
static func describe() -> String:
	var s := load_setup()
	var state := load_state()
	if s == null or state.is_empty():
		return ""
	var where := s.course_name if not s.course_name.is_empty() else "Placeholder Nine"
	var number := int(state.get("number", int(state.get("hole", 0)) + 1))
	return "%s, hole %d, %s" % [where, number, " & ".join(s.names)]
