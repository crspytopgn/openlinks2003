extends RefCounted
## Where the launcher keeps things, and where the game keeps its settings.
##
## The game is installed under the launcher's own data folder:
##   user://game/current   the installed build (as unpacked from the release)
##   user://game/installed.json   which build that is
##   user://downloads/     a download in progress
##   user://links2003/     Links 2003 files copied from the player's discs
## The game's settings are in Godot's default user folder for a project
## named OpenLinks2003 (it sets no custom user folder), which is where its
## user://settings.cfg resolves.

const GAME_NAME := "OpenLinks2003"
const REPO := "crspytopgn/openlinks2003"
const RELEASES_PAGE := "https://github.com/crspytopgn/openlinks2003/releases/tag/latest"
const PROJECT_PAGE := "https://github.com/crspytopgn/openlinks2003"
const WEB_BUILD := "https://crspytopgn.github.io/openlinks2003/"


## "macos", "windows" or "linux".
static func platform() -> String:
	if OS.has_feature("macos"):
		return "macos"
	if OS.has_feature("windows"):
		return "windows"
	return "linux"


## The release download for this platform (see the release job in ci.yml).
static func game_asset(plat := platform()) -> String:
	match plat:
		"macos":
			return "OpenLinks2003-macOS.zip"
		"windows":
			return "OpenLinks2003-Windows.zip"
	return "OpenLinks2003-Linux.tar.gz"


static func launcher_asset(plat := platform()) -> String:
	match plat:
		"macos":
			return "OpenLinks2003-Launcher-macOS.zip"
		"windows":
			return "OpenLinks2003-Launcher-Windows.zip"
	return "OpenLinks2003-Launcher-Linux.tar.gz"


static func data_dir() -> String:
	var override := OS.get_environment("OL_LAUNCHER_DATA")
	if not override.is_empty():
		return override
	return ProjectSettings.globalize_path("user://")


static func game_root() -> String:
	return data_dir().path_join("game")


static func game_dir() -> String:
	return game_root().path_join("current")


static func installed_file() -> String:
	return game_root().path_join("installed.json")


static func downloads_dir() -> String:
	return data_dir().path_join("downloads")


static func cache_dir() -> String:
	return data_dir().path_join("cache")


static func library_dir() -> String:
	return data_dir().path_join("links2003")


static func launcher_config() -> String:
	return data_dir().path_join("launcher.cfg")


## The game's user:// folder: Godot's app_userdata/<project name> under the
## system's data folder (lower-case "godot" on Linux).
static func game_user_dir(plat := platform()) -> String:
	var override := OS.get_environment("OL_GAME_USER_DIR")
	if not override.is_empty():
		return override
	var godot := "godot" if plat == "linux" else "Godot"
	return OS.get_data_dir().path_join(godot).path_join("app_userdata").path_join(GAME_NAME)


static func game_settings() -> String:
	return game_user_dir().path_join("settings.cfg")


## The game's program inside an unpacked build, or "" when it isn't there.
static func game_executable(dir := game_dir(), plat := platform()) -> String:
	match plat:
		"windows":
			var exe := dir.path_join(GAME_NAME + ".exe")
			return exe if FileAccess.file_exists(exe) else ""
		"macos":
			var app := find_app(dir)
			if app.is_empty():
				return ""
			var macos := app.path_join("Contents/MacOS")
			for f in DirAccess.get_files_at(macos):
				return macos.path_join(f)
			return ""
	var bin := dir.path_join(GAME_NAME + ".x86_64")
	return bin if FileAccess.file_exists(bin) else ""


## The first .app bundle in `dir`.
static func find_app(dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for d in DirAccess.get_directories_at(dir):
		if d.ends_with(".app"):
			return dir.path_join(d)
	return ""


## Deletes a folder and everything in it. Links are removed, not followed.
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		var sub := path.path_join(d)
		if dir.is_link(d):
			DirAccess.remove_absolute(sub)
		else:
			remove_tree(sub)
	DirAccess.remove_absolute(path)


## A byte count as "94 MB", "1.4 GB" or "640 KB".
static func size_text(bytes: int) -> String:
	if bytes >= 1000 * 1000 * 1000:
		return "%.1f GB" % (bytes / 1.0e9)
	if bytes >= 1000 * 1000:
		return "%d MB" % roundi(bytes / 1.0e6)
	return "%d KB" % maxi(1, roundi(bytes / 1.0e3))
