class_name OnlineSettings
extends RefCounted
## Where the online server is (server/README.md). Online play stays hidden
## until there is one: DEFAULT_SERVER once it's deployed, or [online] server
## in user://settings.cfg.

const DEFAULT_SERVER := ""


static func server() -> String:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	var s := str(cfg.get_value("online", "server", DEFAULT_SERVER)).strip_edges()
	return s.trim_suffix("/")


static func available() -> bool:
	return not server().is_empty()


## The WebSocket address of room `code` on `base` (https becomes wss).
static func room_url(base: String, code: String) -> String:
	var ws := base
	if ws.begins_with("https://"):
		ws = "wss://" + ws.substr(8)
	elif ws.begins_with("http://"):
		ws = "ws://" + ws.substr(7)
	return "%s/rooms/%s" % [ws, code]
