class_name LinksSoundBank
extends SoundBank
## Game sounds from the player's own predefined.ssf (docs/formats/ssf.md).
## Events the bank has no sound for fall back to the free recorded sounds
## (FreeSoundBank).
##
## The crowd reactions (applause, cheers, groans, "oohs") come from the
## tournament bank, TOURNA_1.SSF, when the player's files have it. It is
## large (about 80 MB), so it is read on a worker thread on desktop, and not
## at all in the browser build for now.

const EVENTS := {
	&"hit": "Full Swing",
	&"putt": "Putt",
	&"land": "Ball Bounce Fairway",
	&"cup": "Ball-in-cup",
	&"splash": "Splash",
}

## Crowd events: each picks a random one of these tournament-bank events
## (docs/formats/ssf.md#the-tournament-bank) that has waves.
const CROWD_EVENTS := {
	&"applause": ["Applause Ball On Green", "Courtesy Applause", "Putting Applause"],
	&"crowd_cheer": ["Great Shot lands < 15", "Applause Close Shot", "Approach Shot Close (end <3)"],
	&"crowd_roar": ["Hole Out (>100)", "Chip In", "Pitch In"],
	&"crowd_groan": ["Shot OB or Water", "Bad Drive", "Short Putt Miss"],
	&"crowd_ooh": ["Lip Out >8", "Miss Putt Barely"],
	&"crowd_tee": ["Tee Shot"],
}

var _bank: SsfBank
var _crowd: SsfBank
var _crowd_path := ""
var _crowd_task := -1
var _player: AudioStreamPlayer
var _fallback: FreeSoundBank


## Null if no game folder is configured or it has no readable sound bank.
static func from_game_folder() -> LinksSoundBank:
	var path := GameFolder.find_file(PackedStringArray(["predefined.ssf", "PREDEF_1.SSF"]))
	if path.is_empty():
		return null
	var bank := SsfBank.load_file(path)
	if bank == null:
		push_warning("Could not read sound bank %s" % path)
		return null
	var sounds := LinksSoundBank.new()
	sounds._bank = bank
	if GraphicsSettings.disc_sounds():
		sounds._crowd_path = GameFolder.find_file(PackedStringArray(["tournament.ssf", "TOURNA_1.SSF"]))
	return sounds


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_fallback = FreeSoundBank.new()
	add_child(_fallback)
	if not _crowd_path.is_empty():
		if OS.has_feature("web"):
			_load_crowd()  # single-threaded build
		else:
			_crowd_task = WorkerThreadPool.add_task(_load_crowd)


func _load_crowd() -> void:
	_crowd = SsfBank.load_file(_crowd_path)


func _exit_tree() -> void:
	if _crowd_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_crowd_task)
		_crowd_task = -1


## The tournament bank once it has loaded, else null.
func _crowd_bank() -> SsfBank:
	if _crowd_task >= 0 and WorkerThreadPool.is_task_completed(_crowd_task):
		WorkerThreadPool.wait_for_task_completion(_crowd_task)
		_crowd_task = -1
		if _crowd == null:
			push_warning("Could not read crowd sounds %s" % _crowd_path)
	return _crowd if _crowd_task < 0 else null


func _crowd_stream(event: StringName) -> AudioStreamWAV:
	var bank := _crowd_bank()
	if bank == null or not CROWD_EVENTS.has(event):
		return null
	var names: Array = CROWD_EVENTS[event].duplicate()
	names.shuffle()
	for n: String in names:
		var stream := bank.random_stream(n)
		if stream != null:
			return stream
	return null


func play_detail(event: StringName, detail: Dictionary) -> void:
	if EVENTS.has(event) or CROWD_EVENTS.has(event):
		_play_event(event, float(detail.get("gain_db", 0.0)), detail)
	else:
		_fallback.play_detail(event, detail)


func play(event: StringName) -> void:
	_play_event(event, 0.0, {})


func _play_event(event: StringName, gain_db: float, detail: Dictionary) -> void:
	var stream: AudioStreamWAV = null
	if EVENTS.has(event):
		stream = _bank.random_stream(EVENTS[event])
	elif CROWD_EVENTS.has(event):
		stream = _crowd_stream(event)
	if stream == null:
		_fallback.play_detail(event, detail)
		return
	# One player per event so a landing doesn't cut off the swing.
	var p := _player if event == &"hit" or event == &"putt" else AudioStreamPlayer.new()
	if p != _player:
		add_child(p)
		p.finished.connect(p.queue_free)
	p.stream = stream
	p.volume_db = gain_db
	p.play()
