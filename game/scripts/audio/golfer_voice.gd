class_name GolferVoice
extends Node
## The golfer's own spoken reactions from the player's POLYANI/*.SSF voice
## banks (docs/formats/ssf.md#golfer-voices): "Great shot!", "In the
## water", "Too soft", "Birdie" and so on. The game picks the event itself
## from what the shot did (the banks' own condition blocks aren't decoded
## yet) and honours each event's chance, so lines come now and then, as in
## Links 2003. Banks are 5 to 15 MB, so they are read on a worker thread;
## the browser build doesn't load them yet.

const DEFAULT_BANK := "MALE1_1.SSF"
const VOLUME_DB := -2.0

var _path := ""
var _bank: SsfBank
var _task := -1
var _player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


## Null without a game folder or a voice bank. `golfer_archive` is the
## golfer's .L3 file, if the player's golfer is in use; its voice bank shares
## the start of its name (DAVIDT.L3 and DAVIDT_1.SSF).
static func from_game_folder(golfer_archive := "") -> GolferVoice:
	if OS.has_feature("web"):
		return null
	var files := GameFolder.list_files("POLYANI")
	var stem := golfer_archive.get_file().get_basename().to_upper().left(6)
	var chosen := ""
	for path in files:
		var file := path.get_file().to_upper()
		if file.get_extension() != "SSF" or file == "NONE.SSF":
			continue
		if not stem.is_empty() and file.begins_with(stem):
			chosen = path
			break
		if file == DEFAULT_BANK:
			chosen = path
	if chosen.is_empty():
		return null
	var voice := GolferVoice.new()
	voice._path = chosen
	return voice


## Which voice event fits a finished shot, or "" for none. `strokes` counts
## this shot; distances are in metres.
static func event_for(shot: ShotResult, rest_surface: int, putting: bool, from_tee: bool, par: int,
		strokes: int, to_pin_m: float, from_m: float, past_pin: bool) -> String:
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			if strokes == 1:
				return "Hole In One!"
			if not putting:
				return "Chip In" if from_m < 40.0 else "Wood/Iron in Hole"
			if strokes <= par - 2:
				return "Eagle"
			if strokes == par - 1:
				return "Birdie"
			if from_m > 9.0:
				return "Made Long Putt"
			if from_m > 3.0:
				return "Made Medium Putt"
			return "Par" if strokes == par else ""
		ShotResult.Outcome.WATER:
			return "In Water"
		ShotResult.Outcome.OUT_OF_BOUNDS:
			return "OB"
	if putting:
		if to_pin_m < 0.35:
			return "Lip Out"
		if from_m < 2.5:
			return "Missed Short Putt"
		if to_pin_m < 1.0:
			return "Nice Lag"
		if to_pin_m > 1.5:
			return "Putt Too Hard" if past_pin else "Putt Too Soft"
		return "Putt Off-Line"
	if rest_surface == Surface.Type.SAND:
		return "In Sand"
	if to_pin_m < 3.0 and from_m > 25.0:
		return "Great Shot"
	if from_tee and par > 3:
		match rest_surface:
			Surface.Type.FAIRWAY:
				return "Great Tee Shot" if shot.total_m > 230.0 else "Good Tee Shot"
			Surface.Type.ROUGH:
				return "In Rough (playable)"
			Surface.Type.DEEP_ROUGH:
				return "Long and in Trouble" if shot.total_m > 200.0 else "Poor Shot 1"
	match rest_surface:
		Surface.Type.GREEN:
			return "Good Shot" if to_pin_m < 8.0 else "Fair Shot"
		Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH:
			return "Poor Shot 1" if randi() % 2 == 0 else "Poor Shot 2"
	return ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	add_child(_player)
	_rng.randomize()
	if not _path.is_empty():
		_task = WorkerThreadPool.add_task(func() -> void: _bank = SsfBank.load_file(_path))


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Says the event's line, if the bank has loaded and the event's chance comes
## up. Returns true when a line plays.
func say(event_name: String) -> bool:
	if event_name.is_empty() or _player.playing:
		return false
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _bank == null:
		return false
	var e := _bank.find_event(event_name)
	if e.is_empty() or _rng.randi_range(1, 100) > int(e.get("chance", 100)):
		return false
	var stream := _bank.random_stream(event_name)
	if stream == null:
		return false
	_player.stream = stream
	_player.play()
	return true
