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
## The course as the menu lists it (its path in the player's files; empty for
## the placeholder), and its display name. A saved round finds its course by
## the key.
var course_key := ""
var course_name := ""
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
## The round seed (every random draw in the round), or 0 for a new one. An
## online round plays the host's.
var round_seed := 0
## Wind strength (Wind.Level) for this round, or -1 for the player's setting.
var wind_level := -1
## The practice range: one person hits from the tee as often as they like,
## the ball comes back, and a launch monitor shows each shot. No scores.
## Not saved with the setup.
var practice := false
## A friend's round (from their result code) whose course, tees and wind
## this round plays. Not saved with the setup.
var challenge: RoundRecord = null
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
## Player `player`'s index; a computer golfer plays off its level's.
func index_of(player: int) -> int:
	if is_computer(player):
		return computer_index(computer_level(player))
	return indexes[player] if player < indexes.size() else Handicap.NONE


## The handicap index (tenths) each computer level plays off: roughly what
## its scores come to on a par-72 course. Game-side only.
static func computer_index(level: int) -> int:
	const INDEX := [240, 120, 0, -40]
	return INDEX[clampi(level, 0, INDEX.size() - 1)]


## Why this setup can't be played, or "" if it can.
func problem() -> String:
	if practice:
		if player_count() != 1 or is_computer(0):
			return "The practice range is for one person: set Players to 1 player, Human."
		if challenge != null:
			return "A friend's round can't be played on the practice range."
		return ""
	var r := GameModes.player_range(mode)
	var n := player_count()
	if n < r.x or n > r.y:
		if r.x == r.y:
			return "%s needs exactly %d players." % [GameModes.MODE_NAMES[mode], r.x]
		return "%s needs %d to %d players." % [GameModes.MODE_NAMES[mode], r.x, r.y]
	if GameModes.is_team(mode) and (not teams.has(0) or not teams.has(1)):
		return "%s needs players on both teams." % GameModes.MODE_NAMES[mode]
	# Names key the scorecard and each player's record, so they must differ.
	var seen := {}
	for name in names:
		var key := name.strip_edges().to_lower()
		if seen.has(key):
			return "Two players are called %s. Give each player their own name." % name.strip_edges()
		seen[key] = true
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
