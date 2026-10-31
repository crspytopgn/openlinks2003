class_name MenuSounds
extends Node
## Menu clicks and music from the player's own SOUNDS.LS
## (docs/formats/ls-archive.md): every Button in the scene clicks when
## pressed, and the menu can play the game's menu music on a loop. Silent
## without the game files. Read on a worker thread; not in the browser build
## yet (the archive is 27 MB, most of it music).

const CLICK := "BC_CLICK.WAV"
const MUSIC := "MUSIC1.WAV"
const MUSIC_DB := -10.0
const CLICK_DB := -4.0

var play_music := false
var _path := ""
var _task := -1
var _click: AudioStreamWAV
var _music: AudioStreamWAV
var _click_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer


## Null without SOUNDS.LS in the game folder.
static func from_game_folder(with_music: bool) -> MenuSounds:
	if not GraphicsSettings.disc_sounds():
		return null
	var path := GameFolder.find_file(PackedStringArray(["sounds.ls", "SOUNDS.LS"]))
	if path.is_empty():
		return null
	var m := MenuSounds.new()
	m._path = path
	m.play_music = with_music
	return m


func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.volume_db = CLICK_DB
	add_child(_click_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = MUSIC_DB
	add_child(_music_player)
	if OS.has_feature("web"):
		_load()  # single-threaded build
	else:
		_task = WorkerThreadPool.add_task(_load)
	get_tree().node_added.connect(_hook)
	_hook_all(get_tree().current_scene if get_tree().current_scene != null else get_parent())


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if get_tree().node_added.is_connected(_hook):
		get_tree().node_added.disconnect(_hook)


func _load() -> void:
	var archive := LsArchiveFile.open(_path)
	if archive == null:
		return
	_click = _stream(archive.read(CLICK))
	if play_music:
		_music = _stream(archive.read(MUSIC))
		if _music != null:
			_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music.loop_end = _music.data.size() / (2 * (2 if _music.stereo else 1))


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _music != null:
			_music_player.stream = _music
			_music_player.play()
		set_process(false)


func click() -> void:
	if _click != null:
		_click_player.stream = _click
		_click_player.play()


func _hook_all(n: Node) -> void:
	if n == null:
		return
	_hook(n)
	for c in n.get_children():
		_hook_all(c)


func _hook(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(click):
		(n as BaseButton).pressed.connect(click)


## The WAV starts at its RIFF tag. Readers before the untagged-entry fix
## returned SOUNDS.LS entries with their 0x37-byte block header in front, so
## that offset is still accepted.
static func _stream(entry: PackedByteArray) -> AudioStreamWAV:
	for at in [0, LsArchiveFile.BLOCK_HEADER_SIZE]:
		if entry.size() > at + 12 and entry.slice(at, at + 4).get_string_from_ascii() == "RIFF":
			return SsfBank.wav_to_stream(entry.slice(at))
	return null
