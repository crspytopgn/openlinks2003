class_name LinksSoundBank
extends SoundBank
## Game sounds from the player's own predefined.ssf (docs/formats/ssf.md).
## Events the bank has no sound for fall back to the placeholder sounds.

const EVENTS := {
	&"hit": "Full Swing",
	&"putt": "Putt",
	&"land": "Ball Bounce Fairway",
	&"cup": "Ball-in-cup",
	&"splash": "Splash",
}

var _bank: SsfBank
var _player: AudioStreamPlayer
var _fallback: PlaceholderSoundBank


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
	return sounds


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_fallback = PlaceholderSoundBank.new()
	add_child(_fallback)


func play(event: StringName) -> void:
	var stream: AudioStreamWAV = null
	if EVENTS.has(event):
		stream = _bank.random_stream(EVENTS[event])
	if stream == null:
		_fallback.play(event)
		return
	# One player per event so a landing doesn't cut off the swing.
	var p := _player if event == &"hit" or event == &"putt" else AudioStreamPlayer.new()
	if p != _player:
		add_child(p)
		p.finished.connect(p.queue_free)
	p.stream = stream
	p.play()
