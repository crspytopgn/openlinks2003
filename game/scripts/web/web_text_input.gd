class_name WebTextInput
extends Node
## Typing on phones and tablets in the browser build (game/web/text_input.js).
## iOS only opens its keyboard when a page input is focused during the touch
## itself, and Godot's LineEdits are focused a frame later, so in Safari on an
## iPad or iPhone no text box in the game took typing. This node tells the
## page where the visible LineEdits are; a touch on one puts a real input over
## it, and what is typed comes back here. It covers every LineEdit in the game
## (SpinBoxes too), with nothing to do in the panels themselves.

const SCRIPT_PATH := "res://web/text_input.js"

static var _installed := false

var _api: JavaScriptObject
var _reply_cb: JavaScriptObject
var _fields: Array[LineEdit] = []
var _windows: Array[Window] = []
## Window instance id -> when it was last shown, so the newest is on top.
var _shown_at := {}
var _shown_count := 0
var _last_sent := ""


static func is_supported() -> bool:
	return OS.has_feature("web")


## Adds the node to the tree once (it lives across scene changes).
static func install(tree: SceneTree) -> void:
	if _installed or not is_supported():
		return
	_installed = true
	var node := WebTextInput.new()
	node.name = "WebTextInput"
	tree.root.add_child.call_deferred(node)


func _ready() -> void:
	JavaScriptBridge.eval(FileAccess.get_file_as_string(SCRIPT_PATH), true)
	_api = JavaScriptBridge.get_interface("olText")
	_reply_cb = JavaScriptBridge.create_callback(_on_reply)
	_api.setCallback(_reply_cb)
	get_tree().node_added.connect(_track)
	_scan(get_tree().root)


func _scan(node: Node) -> void:
	_track(node)
	for child in node.get_children(true):
		_scan(child)


func _track(node: Node) -> void:
	if node is LineEdit and not _fields.has(node):
		_fields.append(node)
		node.tree_exiting.connect(func() -> void: _fields.erase(node), CONNECT_ONE_SHOT)
	elif node is Window and not _windows.has(node):
		var w := node as Window
		_windows.append(w)
		_shown_at[w.get_instance_id()] = _shown_count
		w.visibility_changed.connect(func() -> void:
			if w.visible:
				_shown_count += 1
				_shown_at[w.get_instance_id()] = _shown_count)
		w.tree_exiting.connect(func() -> void:
			_windows.erase(w)
			_shown_at.erase(w.get_instance_id()), CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var root := get_tree().root
	var data := {
		"w": root.size.x,
		"h": root.size.y,
		"fields": describe_all(_fields, top_window(_windows, _shown_at)),
	}
	var json := JSON.stringify(data)
	if json != _last_sent:
		_last_sent = json
		_api.setFields(json)


## The window that takes touches: the newest visible exclusive dialog or
## popup, or null if none is open (then every window does).
static func top_window(windows: Array[Window], shown_at: Dictionary) -> Window:
	var best: Window = null
	var best_at := -1
	for w in windows:
		if not is_instance_valid(w) or not w.is_inside_tree() or not w.visible:
			continue
		if w.get_parent() == null:
			continue  # the root
		if not (w.exclusive or w is Popup):
			continue
		var at: int = shown_at.get(w.get_instance_id(), 0)
		if at >= best_at:
			best = w
			best_at = at
	return best


## The fields the page should know about, in drawing order (later on top).
static func describe_all(fields: Array[LineEdit], top: Window) -> Array:
	var out: Array = []
	for le in fields:
		if not is_instance_valid(le) or not le.is_inside_tree():
			continue
		if not le.is_visible_in_tree() or not le.editable:
			continue
		if top != null and le.get_window() != top:
			continue
		out.append(describe(le))
	return out


## One field: its id and its rectangle in the game window's pixels.
static func describe(le: LineEdit) -> Dictionary:
	var xf := le.get_viewport().get_screen_transform() * le.get_global_transform_with_canvas()
	var a := xf * Vector2.ZERO
	var b := xf * le.size
	return {
		"id": le.get_instance_id(),
		"x": roundf(minf(a.x, b.x)),
		"y": roundf(minf(a.y, b.y)),
		"w": roundf(absf(b.x - a.x)),
		"h": roundf(absf(b.y - a.y)),
		"text": le.text,
		"hint": le.placeholder_text,
		"secret": le.secret,
		"max": le.max_length,
		"numeric": le.get_parent() is SpinBox,
	}


func _on_reply(args: Array) -> void:
	var msg: Variant = JSON.parse_string(str(args[0]))
	if msg is Dictionary:
		_apply_later.call_deferred(msg)


func _apply_later(msg: Dictionary) -> void:
	apply(msg)


## Puts what was typed on the page into its LineEdit, with the signals the
## panels listen for.
static func apply(msg: Dictionary) -> void:
	var le := instance_from_id(int(msg.get("id", 0))) as LineEdit
	if le == null or not le.is_inside_tree() or not le.editable:
		return
	var text := str(msg.get("text", ""))
	if le.max_length > 0:
		text = text.left(le.max_length)
	if text != le.text:
		le.text = text
		le.caret_column = text.length()
		le.text_changed.emit(text)
	match str(msg.get("kind", "")):
		"submit":
			le.text_submitted.emit(text)
		"done":
			if le.has_focus():
				le.release_focus()
