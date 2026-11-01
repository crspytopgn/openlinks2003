class_name AudioSettings
extends RefCounted
## Volumes set in the desktop launcher (launcher/), under [audio] in
## user://settings.cfg: "master" and "music", each 0 to 100. The master
## volume is applied to the Master bus once at startup (it lasts for the
## run); the menu music adds music_db() to its own level.

const PATH := "user://settings.cfg"
const SECTION := "audio"


## The volume `key` as 0 to 1 (1 when unset).
static func level(key: String, path := PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return 1.0
	return clampf(float(cfg.get_value(SECTION, key, 100)) / 100.0, 0.0, 1.0)


## Decibels for a 0 to 1 level, silent at 0.
static func to_db(value: float) -> float:
	return -80.0 if value <= 0.001 else linear_to_db(value)


static func music_db(path := PATH) -> float:
	return to_db(level("music", path))


## Sets the Master bus from the saved master volume.
static func apply(path := PATH) -> void:
	var master := level("master", path)
	AudioServer.set_bus_volume_db(0, to_db(master))
	AudioServer.set_bus_mute(0, master <= 0.001)
