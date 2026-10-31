class_name RoundSetup
extends RefCounted
## What the setup menu chose for a round: course, tees, holes, game mode,
## players (each a person or a computer golfer) and whether handicaps count.
## The last setup is saved under [round] in user://settings.cfg.

enum Holes { ALL, FRONT_NINE, BACK_NINE }
enum Tees { BACK, MIDDLE, FORWARD }

const HOLES_NAMES := ["All holes", "Front nine", "Back nine"]
const TEES_NAMES := ["Back tees", "Middle tees", "Forward tees"]
const MAX_PLAYERS := 4
const DEFAULT_NAMES := ["Player 1", "Player 2", "Player 3", "Player 4"]
const HUMAN := -1

## Course file; empty plays the placeholder course.
var course_path := ""
var mode: GameModes.Mode = GameModes.Mode.STROKE
var holes: Holes = Holes.ALL
var tees: Tees = Tees.BACK
var names: Array[String] = ["Player 1"]
## Best ball: the team (0 or 1) of each player.
var teams: Array[int] = [0]
## Who plays each seat: HUMAN, or a computer golfer's OpponentSkill.Level.
var computer: Array[int] = [HUMAN]
## Play off handicaps: everyone's net scores decide the game.
var handicaps := false
## Each player's handicap index in tenths (Handicap.NONE plays off scratch),
## from their profile. Not saved with the setup.
var indexes: Array[int] = []


static func single(path: String) -> RoundSetup:
	var s := RoundSetup.new()
	s.course_path = path
	return s


func player_count() -> int:
	return names.size()


## The computer golfer's level for player `i`, or HUMAN.
func computer_level(i: int) -> int:
	return computer[i] if i < computer.size() else HUMAN


func is_computer(i: int) -> bool:
	return computer_level(i) != HUMAN


## True when nobody at the keyboard is playing, so the round runs itself.
func all_computer() -> bool:
	for i in player_count():
		if not is_computer(i):
			return false
	return true
func index_of(player: int) -> int:
	return indexes[player] if player < indexes.size() else Handicap.NONE


## Why this setup can't be played, or "" if it can.
func problem() -> String:
	var r := GameModes.player_range(mode)
	var n := player_count()
	if n < r.x or n > r.y:
		if r.x == r.y:
			return "%s needs exactly %d players." % [GameModes.MODE_NAMES[mode], r.x]
		return "%s needs %d to %d players." % [GameModes.MODE_NAMES[mode], r.x, r.y]
	if GameModes.is_team(mode) and (not teams.has(0) or not teams.has(1)):
		return "%s needs players on both teams." % GameModes.MODE_NAMES[mode]
	return ""


## The holes of a `count`-hole course to play, as indices.
func hole_indices(count: int) -> Array[int]:
	var first := 0
	var last := count
	if count > 9:
		if holes == Holes.FRONT_NINE:
			last = 9
		elif holes == Holes.BACK_NINE:
			first = 9
	var out: Array[int] = []
	for i in range(first, last):
		out.append(i)
	return out


## Which of `count` tee boxes (back to forward) this setup plays from.
func tee_index(count: int) -> int:
	if count <= 1:
		return 0
	match tees:
		Tees.FORWARD:
			return count - 1
		Tees.MIDDLE:
			return count / 2
	return 0


func save(path := GameFolder.SETTINGS_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("round", "mode", mode)
	cfg.set_value("round", "holes", holes)
	cfg.set_value("round", "tees", tees)
	cfg.set_value("round", "names", PackedStringArray(names))
	cfg.set_value("round", "teams", PackedInt32Array(teams))
	cfg.set_value("round", "computer", PackedInt32Array(computer))
	cfg.set_value("round", "handicaps", handicaps)
	cfg.save(path)


## The last saved setup (without the course), or the defaults.
static func load_saved(path := GameFolder.SETTINGS_PATH) -> RoundSetup:
	var s := RoundSetup.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.mode = clampi(cfg.get_value("round", "mode", 0), 0, GameModes.MODE_NAMES.size() - 1) as GameModes.Mode
	s.holes = clampi(cfg.get_value("round", "holes", 0), 0, HOLES_NAMES.size() - 1) as Holes
	s.tees = clampi(cfg.get_value("round", "tees", 0), 0, TEES_NAMES.size() - 1) as Tees
	s.handicaps = cfg.get_value("round", "handicaps", false) == true
	var saved_names: PackedStringArray = cfg.get_value("round", "names", PackedStringArray())
	var saved_teams: PackedInt32Array = cfg.get_value("round", "teams", PackedInt32Array())
	var saved_computer: PackedInt32Array = cfg.get_value("round", "computer", PackedInt32Array())
	if saved_names.size() >= 1 and saved_names.size() <= MAX_PLAYERS:
		s.names.clear()
		s.teams.clear()
		s.computer.clear()
		for i in saved_names.size():
			s.names.append(saved_names[i] if not saved_names[i].strip_edges().is_empty() else DEFAULT_NAMES[i])
			s.teams.append(clampi(saved_teams[i], 0, 1) if i < saved_teams.size() else i % 2)
			s.computer.append(clampi(saved_computer[i], HUMAN, OpponentSkill.LEVEL_NAMES.size() - 1) if i < saved_computer.size() else HUMAN)
	return s
