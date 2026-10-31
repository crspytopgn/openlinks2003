class_name BroadcastOverlay
extends Control
## The Broadcast presentation's on-screen graphics, drawn like a TV golf
## package: a score bug with the hole and the player's round, a shot panel
## (club, distance, lie, wind, elevation), a lower third when a player steps
## up, a shot card after each shot, a hole card with a map before the tee
## shot, a scrolling leaderboard ticker, a LIVE bug, camera tags, captions,
## a REPLAY bug and a wipe between cuts. All of it is drawn here from plain
## shapes and the default font, so it needs no art and no game files.
##
## GolfRound feeds it plain dictionaries; it keeps no game state of its own.

const PANEL := Color(0.04, 0.13, 0.10, 0.86)
const PANEL_DARK := Color(0.02, 0.06, 0.05, 0.9)
const ACCENT := Color(0.98, 0.78, 0.25)
const TEXT := Color(1, 1, 1)
const DIM := Color(0.78, 0.86, 0.82)
const RED := Color(0.86, 0.12, 0.12)
const UNDER := Color(1.0, 0.45, 0.4)  ## scores under par, as on TV
const TICKER_H := 28.0
const LOWER_THIRD_S := 4.5
const SHOT_CARD_S := 6.0
const HOLE_CARD_S := 5.5
const WIPE_S := 0.55
const TICKER_SPEED := 70.0  ## pixels per second

var status := {}
var _font: Font
var _time := 0.0
var _lower := {}
var _lower_t := -1.0
var _card := {}
var _card_t := -1.0
var _hole := {}
var _hole_t := -1.0
var _hole_map: Texture2D
var _caption := ""
var _caption_t := -1.0
var _caption_len := 0.0
var _cam_tag := ""
var _replay := false
var _wipe_t := -1.0
var _wipe_text := ""
var _ticker := ""
var _ticker_x := 0.0
var _aiming := true
var pip: SubViewportContainer
var pip_camera: Camera3D
var _pip_view: SubViewport


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	pip = SubViewportContainer.new()
	pip.stretch = true
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pip.offset_left = -400
	pip.offset_right = -16
	pip.offset_top = 176
	pip.offset_bottom = 392
	pip.visible = false
	add_child(pip)
	_pip_view = SubViewport.new()
	_pip_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	pip.add_child(_pip_view)
	pip_camera = Camera3D.new()
	pip_camera.fov = 40.0
	pip_camera.far = 3000.0
	_pip_view.add_child(pip_camera)


## Shows a second picture (the pin camera on approach shots). The picture
## shares the round's 3D world.
func show_pip(on: bool) -> void:
	if on and _pip_view.world_3d == null:
		_pip_view.world_3d = get_viewport().find_world_3d()
	pip.visible = on
	_pip_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


## The current hole, player and shot. Keys: hole, par, yards, player,
## to_par, thru, stroke, club, to_pin, lie, wind, elevation, ticker (the
## scrolling line), aiming (bool).
func set_status(s: Dictionary) -> void:
	status = s
	_aiming = s.get("aiming", true)
	_ticker = str(s.get("ticker", ""))
	queue_redraw()


func lower_third(name: String, line: String) -> void:
	_lower = {"name": name, "line": line}
	_lower_t = 0.0


## After a shot. Keys: title, carry, roll, total, height, lie, to_pin.
func shot_card(card: Dictionary) -> void:
	_card = card
	_card_t = 0.0


func hide_shot_card() -> void:
	_card_t = -1.0


func hide_lower_third() -> void:
	_lower_t = -1.0


## Before the tee shot: number, par, yards, name, and a map of the hole.
func hole_card(info: Dictionary, map: Texture2D) -> void:
	_hole = info
	_hole_map = map
	_hole_t = 0.0


func caption(text: String, seconds := 4.0) -> void:
	_caption = text
	_caption_t = 0.0 if not text.is_empty() else -1.0
	_caption_len = seconds if seconds > 0.0 else 1.0e9


func set_cam_tag(text: String) -> void:
	if text != _cam_tag:
		_cam_tag = text
		queue_redraw()


func set_replay(on: bool) -> void:
	_replay = on
	if on:
		wipe("REPLAY")


## A diagonal wipe across the screen, to cover a cut.
func wipe(text := "") -> void:
	_wipe_t = 0.0
	_wipe_text = text


func wiping() -> bool:
	return _wipe_t >= 0.0


func _process(delta: float) -> void:
	_time += delta
	for k in ["_lower_t", "_card_t", "_hole_t", "_caption_t", "_wipe_t"]:
		var v: float = get(k)
		if v >= 0.0:
			set(k, v + delta)
	if _lower_t > LOWER_THIRD_S:
		_lower_t = -1.0
	if _card_t > SHOT_CARD_S:
		_card_t = -1.0
	if _hole_t > HOLE_CARD_S:
		_hole_t = -1.0
	if _caption_t > _caption_len:
		_caption_t = -1.0
	if _wipe_t > WIPE_S:
		_wipe_t = -1.0
	_ticker_x -= delta * TICKER_SPEED
	queue_redraw()


func _draw() -> void:
	if status.is_empty():
		return
	_draw_score_bug()
	_draw_live_bug()
	if _aiming and _hole_t < 0.0:
		_draw_shot_panel()
	if _hole_t >= 0.0:
		_draw_hole_card()
	if _card_t >= 0.0:
		_draw_shot_card()
	if _lower_t >= 0.0:
		_draw_lower_third()
	if _caption_t >= 0.0 and not _caption.is_empty():
		_draw_caption()
	if not _cam_tag.is_empty() and not _replay:
		_tag(Vector2(16.0, size.y - TICKER_H - 44.0), _cam_tag.to_upper(), false)
	if _replay:
		_draw_replay_bug()
	_draw_ticker()
	if _wipe_t >= 0.0:
		_draw_wipe()


# --- Pieces -------------------------------------------------------------------

func _draw_score_bug() -> void:
	var x := 16.0
	var y := 14.0
	# Hole block: big number on the accent colour.
	draw_rect(Rect2(x, y, 64, 64), ACCENT)
	_text(Vector2(x + 32, y + 30), str(status.get("hole", "")), 30, PANEL_DARK, true)
	_text(Vector2(x + 32, y + 54), "PAR %s" % status.get("par", ""), 13, PANEL_DARK, true)
	var w := 300.0
	draw_rect(Rect2(x + 64, y, w, 64), PANEL)
	_text(Vector2(x + 76, y + 24), str(status.get("player", "")).to_upper(), 19, TEXT)
	var to_par := str(status.get("to_par", "E"))
	_text_right(Vector2(x + 64 + w - 12, y + 24), to_par, 22, UNDER if to_par.begins_with("-") else TEXT)
	_text(Vector2(x + 76, y + 50), "%s YDS    THRU %s    SHOT %s" % [status.get("yards", ""), status.get("thru", 0), status.get("stroke", 1)], 13, DIM)


func _draw_live_bug() -> void:
	var r := Rect2(size.x - 186.0, 16.0, 62.0, 24.0)
	draw_rect(r, RED)
	var pulse := 0.6 + 0.4 * sin(_time * 4.0)
	draw_circle(r.position + Vector2(12, 12), 4.0, Color(1, 1, 1, pulse))
	_text(r.position + Vector2(38, 17), "LIVE", 14, TEXT, true)


func _draw_shot_panel() -> void:
	var rows := [
		["CLUB", status.get("club", "")],
		["TO PIN", status.get("to_pin", "")],
		["LIE", status.get("lie", "")],
		["WIND", status.get("wind", "")],
		["ELEV", status.get("elevation", "")],
	]
	var x := 16.0
	var y := 92.0
	var h := 24.0
	draw_rect(Rect2(x, y, 364, h * rows.size() + 10), PANEL)
	draw_rect(Rect2(x, y, 4, h * rows.size() + 10), ACCENT)
	for i in rows.size():
		var ry := y + 22 + i * h
		_text(Vector2(x + 16, ry), rows[i][0], 13, ACCENT)
		_text(Vector2(x + 96, ry), str(rows[i][1]), 16, TEXT)


func _draw_lower_third() -> void:
	var a := _ease_in_out(_lower_t, LOWER_THIRD_S)
	var w := 440.0
	var x := lerpf(-w, 40.0, a)
	var y := size.y - TICKER_H - 86.0
	draw_rect(Rect2(x, y, w, 34), PANEL_DARK)
	draw_rect(Rect2(x, y, 6, 52), ACCENT)
	_text(Vector2(x + 18, y + 25), str(_lower.get("name", "")).to_upper(), 22, TEXT)
	draw_rect(Rect2(x, y + 34, w, 20), Color(ACCENT, 0.92))
	_text(Vector2(x + 18, y + 49), str(_lower.get("line", "")), 13, PANEL_DARK)


func _draw_shot_card() -> void:
	var a := _ease_in_out(_card_t, SHOT_CARD_S)
	var w := 250.0
	var x := lerpf(size.x + 10.0, size.x - w - 16.0, a)
	var y := 176.0 if not pip.visible else 404.0
	var rows := [
		["CARRY", _card.get("carry", "")],
		["ROLL", _card.get("roll", "")],
		["TOTAL", _card.get("total", "")],
		["HEIGHT", _card.get("height", "")],
		["LIE", _card.get("lie", "")],
		["TO PIN", _card.get("to_pin", "")],
	]
	draw_rect(Rect2(x, y, w, 30), ACCENT)
	_text(Vector2(x + 12, y + 21), str(_card.get("title", "SHOT")).to_upper(), 15, PANEL_DARK)
	draw_rect(Rect2(x, y + 30, w, rows.size() * 24 + 8), PANEL)
	for i in rows.size():
		var ry := y + 52 + i * 24
		_text(Vector2(x + 12, ry), rows[i][0], 13, ACCENT)
		_text_right(Vector2(x + w - 12, ry), str(rows[i][1]), 16, TEXT)


func _draw_hole_card() -> void:
	var a := _ease_in_out(_hole_t, HOLE_CARD_S)
	var w := 300.0
	var x := lerpf(-w - 20.0, 16.0, a)
	var y := 92.0
	var map_h := 280.0
	draw_rect(Rect2(x, y, w, 64), PANEL_DARK)
	_text(Vector2(x + 14, y + 28), "HOLE %s" % _hole.get("number", ""), 24, ACCENT)
	_text_right(Vector2(x + w - 14, y + 28), "PAR %s" % _hole.get("par", ""), 20, TEXT)
	_text(Vector2(x + 14, y + 52), "%s YARDS    %s" % [_hole.get("yards", ""), str(_hole.get("name", "")).to_upper()], 13, DIM)
	draw_rect(Rect2(x, y + 64, w, map_h + 16), PANEL)
	if _hole_map != null:
		var ms := _hole_map.get_size()
		var scale := minf((w - 16) / ms.x, map_h / ms.y)
		var draw_size := ms * scale
		draw_texture_rect(_hole_map, Rect2(Vector2(x + (w - draw_size.x) * 0.5, y + 72), draw_size), false)


func _draw_caption() -> void:
	var fs := 18
	var tw := _font.get_string_size(_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 40.0
	var fade := clampf(minf(_caption_t * 4.0, (_caption_len - _caption_t) * 2.0), 0.0, 1.0)
	var r := Rect2((size.x - w) * 0.5, size.y - TICKER_H - 140.0, w, 34)
	draw_rect(r, Color(PANEL_DARK, PANEL_DARK.a * fade))
	_text(r.position + Vector2(w * 0.5, 23), _caption, fs, Color(TEXT, fade), true)


func _draw_replay_bug() -> void:
	var r := Rect2(size.x - 300.0, 16.0, 104.0, 24.0)
	draw_rect(r, ACCENT)
	_text(r.position + Vector2(52, 18), "REPLAY", 15, PANEL_DARK, true)


func _draw_ticker() -> void:
	if _ticker.is_empty():
		return
	var y := size.y - TICKER_H
	draw_rect(Rect2(0, y, size.x, TICKER_H), PANEL_DARK)
	draw_rect(Rect2(0, y, size.x, 2), ACCENT)
	var fs := 14
	var tw := _font.get_string_size(_ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 120.0
	if _ticker_x < -tw:
		_ticker_x += tw
	var x := _ticker_x
	while x < size.x:
		_text(Vector2(x + 16, y + 19), _ticker, fs, TEXT)
		x += tw


func _draw_wipe() -> void:
	# A slanted accent band with a dark trailing band crosses left to right.
	var u := _wipe_t / WIPE_S
	var lean := size.y * 0.35
	var cx := lerpf(-size.x * 0.4 - lean, size.x * 1.4, u)
	var band := size.x * 0.45
	var dark := PackedVector2Array([
		Vector2(cx - band, size.y), Vector2(cx - band + lean, 0), Vector2(cx + lean, 0), Vector2(cx, size.y)])
	draw_colored_polygon(dark, PANEL_DARK)
	var edge := 26.0
	var stripe := PackedVector2Array([
		Vector2(cx, size.y), Vector2(cx + lean, 0), Vector2(cx + lean + edge, 0), Vector2(cx + edge, size.y)])
	draw_colored_polygon(stripe, ACCENT)
	if not _wipe_text.is_empty():
		_text(Vector2(cx - band * 0.5 + lean * 0.5, size.y * 0.5 + 14), _wipe_text, 40, ACCENT, true)


# --- Helpers ------------------------------------------------------------------

func _tag(at: Vector2, text: String, right_align: bool) -> void:
	var fs := 13
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var r := Rect2(at.x - w if right_align else at.x, at.y - 18.0, w, 22.0)
	draw_rect(r, PANEL)
	draw_rect(Rect2(r.position, Vector2(3, r.size.y)), ACCENT)
	_text(r.position + Vector2(11, 16), text, fs, TEXT)


func _text(at: Vector2, text: String, fs: int, col: Color, centred := false) -> void:
	var p := at
	if centred:
		p.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_right(at: Vector2, text: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(at.x - w, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 0 -> 1 over the first 0.35 s, 1 until the last 0.35 s, then back to 0.
static func _ease_in_out(t: float, length: float) -> float:
	var u := clampf(minf(t, length - t) / 0.35, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)
