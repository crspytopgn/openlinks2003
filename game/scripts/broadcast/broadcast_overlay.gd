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
## Panels are rounded glass (Glass, FrostedGlass): over the live blur the
## tint is this see-through; where glass doesn't blur (the web, Low
## quality) it is plain tinted glass, darker, with a light rim.
const GLASS_TINT := 0.55
const FLAT_TINT := 0.92
const R := 14.0  ## corner radius
const ALL := Vector4(R, R, R, R)
const TOP := Vector4(R, R, 0, 0)
const BOTTOM := Vector4(0, 0, R, R)
const LEFT := Vector4(R, 0, 0, R)
const RIGHT := Vector4(0, R, R, 0)
const ACCENT := Color(0.98, 0.78, 0.25)
const TEXT := Color(1, 1, 1)
const DIM := Color(0.78, 0.86, 0.82)
const RED := Color(0.86, 0.12, 0.12)
const UNDER := Color(1.0, 0.45, 0.4)  ## scores under par, as on TV
const TICKER_H := 28.0
const CAPTION_LINE := 24.0
const LOWER_THIRD_S := 4.5
const SHOT_CARD_S := 6.0
const HOLE_CARD_S := 5.5
const HOLE_CARD_FADE := 0.35  # the fade of _ease_in_out
const WIPE_S := 0.55
const SPRING_IN_S := 0.55
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
## The top of the key hints (Hud), for the lower third to keep above.
var hints_top := INF
var _caption_t := -1.0
var _caption_len := 0.0
var _cam_tag := ""
var _replay := false
var _wipe_t := -1.0
var _wipe_text := ""
var _ticker := ""
var _ticker_x := 0.0
var _aiming := true
## The Tour presentation: TourGraphics draws the leaderboard, the shot data
## and the hole map, so the score bug, shot panel, hole card and ticker step
## aside.
var tour := false
var pip: SubViewportContainer
var pip_camera: Camera3D
var _pip_view: SubViewport
var glass: FrostedGlass


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass = FrostedGlass.new()
	add_child(glass)
	_font = GlassTheme.font(600)
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


## Fades the hole card out now, when the player swings before it has gone.
func end_hole_card() -> void:
	if _hole_t >= 0.0 and _hole_t < HOLE_CARD_S - HOLE_CARD_FADE:
		_hole_t = HOLE_CARD_S - HOLE_CARD_FADE


func hole_card_showing() -> bool:
	return _hole_t >= 0.0


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
	glass.begin()
	_draw_pieces()
	glass.commit()


func _draw_pieces() -> void:
	if status.is_empty():
		return
	if not tour:
		_draw_score_bug()
	_draw_live_bug()
	if _aiming and _hole_t < 0.0 and not tour:
		_draw_shot_panel()
	if _hole_t >= 0.0 and not tour:
		_draw_hole_card()
	if _card_t >= 0.0:
		_draw_shot_card()
	if _lower_t >= 0.0 and not tour:
		_draw_lower_third()
	if _caption_t >= 0.0 and not _caption.is_empty():
		_draw_caption()
	if not _cam_tag.is_empty() and not _replay:
		_tag(Vector2(TourGraphics.RAIL_W + 24.0 if tour else 16.0, size.y - TICKER_H - 44.0), _cam_tag.to_upper(), false)
	if _replay:
		_draw_replay_bug()
	if not tour:
		_draw_ticker()
	if _wipe_t >= 0.0:
		_draw_wipe()


# --- Pieces -------------------------------------------------------------------

func _draw_score_bug() -> void:
	var x := 16.0
	var y := 14.0
	# Hole block: big number on the accent colour.
	_fill(Rect2(x, y, 64, 64), ACCENT, LEFT)
	_text(Vector2(x + 32, y + 30), str(status.get("hole", "")), 30, PANEL_DARK, true)
	_text(Vector2(x + 32, y + 54), "PAR %s" % status.get("par", ""), 13, PANEL_DARK, true)
	var w := 300.0
	_panel(Rect2(x + 64, y, w, 64), PANEL, 1.0, RIGHT)
	_text(Vector2(x + 76, y + 24), str(status.get("player", "")).to_upper(), 19, TEXT)
	var to_par := str(status.get("to_par", "E"))
	_text_right(Vector2(x + 64 + w - 12, y + 24), to_par, 22, UNDER if to_par.begins_with("-") else TEXT)
	_text(Vector2(x + 76, y + 50), "%s YDS    THRU %s    SHOT %s" % [status.get("yards", ""), status.get("thru", 0), status.get("stroke", 1)], 13, DIM)


func _draw_live_bug() -> void:
	var r := Rect2(size.x - 186.0, 16.0, 62.0, 24.0)
	_fill(r, RED, Vector4.ONE * 12.0)
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
	_panel(Rect2(x, y, 364, h * rows.size() + 10), PANEL)
	_fill(Rect2(x + 6, y + 10, 4, h * rows.size() - 10), ACCENT, Vector4.ONE * 2.0)
	for i in rows.size():
		var ry := y + 22 + i * h
		_text(Vector2(x + 16, ry), rows[i][0], 13, ACCENT)
		_text(Vector2(x + 96, ry), str(rows[i][1]), 16, TEXT)
	if status.has("lie_type"):
		_draw_lie_tile(Rect2(x + 364 + 8, y, 104, h * rows.size() + 10), int(status.lie_type), float(status.get("lie_power", 1.0)))


## The lie at a glance, as TV golf shows it: a close-up of the ball as it
## sits (teed up, on short grass, down in the rough, in the sand), drawn
## with shading so it reads as a picture rather than an icon, and the share
## of a full shot's distance it keeps.
func _draw_lie_tile(r: Rect2, lie: int, keep: float) -> void:
	_panel(r, PANEL)
	var pic := Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, r.size.y - 50))
	# Sky-to-shade backdrop, as a long lens close to the ground sees it.
	_gradient(pic, Color(0.22, 0.34, 0.30), Color(0.10, 0.18, 0.14))
	var low := Color(0.18, 0.36, 0.12)
	var high := Color(0.36, 0.60, 0.22)
	var grass_h := 0.0  # blade height over the ball's radius
	var sink := 0.0  # how far the ball sits down, in radii
	var density := 26
	var teed := false
	var sand := false
	match lie:
		Surface.Type.TEE:
			teed = true
			grass_h = 0.3
		Surface.Type.FAIRWAY, Surface.Type.FRINGE:
			grass_h = 0.4
			density = 40
		Surface.Type.GREEN:
			grass_h = 0.18
			density = 48
			high = Color(0.40, 0.66, 0.26)
		Surface.Type.ROUGH:
			grass_h = 1.5
			sink = 0.35
			density = 34
			low = Color(0.14, 0.30, 0.10)
			high = Color(0.40, 0.62, 0.22)
		Surface.Type.DEEP_ROUGH:
			grass_h = 2.2
			sink = 0.5
			density = 40
			low = Color(0.12, 0.25, 0.08)
			high = Color(0.48, 0.60, 0.24)
		Surface.Type.SAND:
			sand = true
			sink = 0.45
		_:
			low = Color(0.15, 0.25, 0.32)
			high = Color(0.28, 0.42, 0.50)
	var base := pic.position.y + pic.size.y * 0.70
	var ground := Rect2(pic.position.x, base, pic.size.x, pic.end.y - base)
	if sand:
		_gradient(ground, Color(0.90, 0.82, 0.62), Color(0.70, 0.60, 0.42))
		for k in 60:  # grain
			var gx := pic.position.x + fmod(float(k) * 0.6180339 * 97.0, pic.size.x)
			var gy := base + fmod(float(k) * 0.4142 * 53.0, ground.size.y)
			draw_circle(Vector2(gx, gy), 0.7, Color(0.55, 0.47, 0.32, 0.5))
	else:
		_gradient(ground, low.lerp(high, 0.35), low)
	var ball_r := pic.size.x * 0.17
	var c := Vector2(pic.position.x + pic.size.x * 0.5, base - ball_r + sink * ball_r * 2.0)
	if teed:
		c.y -= ball_r * 0.85
		var top := c.y + ball_r * 0.85
		var tee := PackedVector2Array([Vector2(c.x - ball_r * 0.45, top), Vector2(c.x + ball_r * 0.45, top),
			Vector2(c.x + 1.2, base + 4.0), Vector2(c.x - 1.2, base + 4.0)])
		draw_colored_polygon(tee, Color(0.93, 0.92, 0.88))
		draw_line(Vector2(c.x + 1.0, top), Vector2(c.x + 0.6, base + 3.0), Color(0.7, 0.68, 0.62), 1.0, true)
	# Back blades, behind the ball.
	if grass_h > 0.0:
		_blades(pic, base, ball_r * grass_h * 0.7, density, low.darkened(0.15), low, 1)
	# The ball: a soft contact shadow, then shaded from the sun's side.
	if not teed:
		_ellipse(Vector2(c.x + ball_r * 0.2, base + 1.0), Vector2(ball_r * 1.25, ball_r * 0.28), Color(0, 0, 0, 0.35))
	var steps := 7
	for k in steps:
		var t := float(k) / float(steps - 1)
		var rr := ball_r * (1.0 - t * 0.78)
		var off := Vector2(-0.32, -0.36) * ball_r * t
		draw_circle(c + off, rr, Color(0.72, 0.74, 0.76).lerp(Color(1, 1, 1), t), true, -1.0, true)
	for k in 9:  # dimples, faint
		var a := float(k) * 2.399
		var d := ball_r * 0.55 * sqrt(float(k + 1) / 9.0)
		draw_circle(c + Vector2(cos(a), sin(a)) * d, ball_r * 0.07, Color(0.6, 0.62, 0.64, 0.25), true, -1.0, true)
	if sand:
		# The sand round the ball, with a little lip where it settled.
		var front := Rect2(pic.position.x, c.y + ball_r * (1.0 - sink * 2.0) + ball_r * 0.9, pic.size.x, 0.0)
		front.size.y = pic.end.y - front.position.y
		if front.size.y > 0.0:
			_gradient(front, Color(0.88, 0.80, 0.60), Color(0.70, 0.60, 0.42))
		_ellipse(Vector2(c.x, front.position.y), Vector2(ball_r * 1.3, ball_r * 0.22), Color(0.95, 0.88, 0.70))
	# Down in long grass, the turf closes over the bottom of the ball, and
	# the front blades rise round it.
	var front_base := base
	if sink > 0.0 and not sand:
		front_base = base + ball_r * 0.2
		_gradient(Rect2(pic.position.x, front_base, pic.size.x, pic.end.y - front_base), low.lerp(high, 0.25), low.darkened(0.1))
	if grass_h > 0.0:
		_blades(pic, front_base, ball_r * grass_h, density, low, high, 2)
	draw_rect(pic, Color(1, 1, 1, 0.12), false, 1.0, true)
	var pct := "%d%%" % roundi(keep * 100.0)
	_text(Vector2(r.position.x + r.size.x * 0.5, r.end.y - 22.0), pct, 18, TEXT if keep >= 0.995 else ACCENT, true)
	_text(Vector2(r.position.x + r.size.x * 0.5, r.end.y - 8.0), "DISTANCE", 9, DIM, true)


## A vertical gradient filling `r`.
func _gradient(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _ellipse(at: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(at + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)


## Tapered grass blades along `base`, `tall` at most, coloured from `root`
## to `tip`; `row` varies the pattern between the back and front rows.
func _blades(pic: Rect2, base: float, tall: float, count: int, root: Color, tip: Color, row: int) -> void:
	for i in count:
		var h := fmod(float(i * 7 + row * 13) * 0.6180339, 1.0)
		var x := pic.position.x + (float(i) + h) / float(count) * pic.size.x
		var height := tall * (0.55 + 0.6 * fmod(h * 3.7 + 0.31 * row, 1.0))
		height = minf(height, base - pic.position.y - 2.0)
		var lean := (fmod(h * 5.3, 1.0) - 0.5) * height * 0.5
		var w := 1.3 + 1.2 * fmod(h * 2.1, 1.0)
		var shade := 0.75 + 0.25 * fmod(h * 9.1, 1.0)
		var pts := PackedVector2Array([Vector2(x - w, base + 2.0), Vector2(x + w, base + 2.0),
			Vector2(x + lean * 0.6 + w * 0.4, base - height * 0.6), Vector2(x + lean, base - height)])
		draw_polygon(pts, PackedColorArray([root, root, root.lerp(tip, 0.7).darkened(1.0 - shade), tip.darkened(1.0 - shade)]))



func _draw_lower_third() -> void:
	var a := _slide(_lower_t, LOWER_THIRD_S)
	var w := 440.0
	var x := lerpf(-w, 40.0, a)
	# Clear of the key hints that run just above the ticker, however many
	# lines they wrap onto (Hud sets hints_top).
	var y := minf(size.y - TICKER_H - 100.0, hints_top - 60.0)
	_panel(Rect2(x, y, w, 34), PANEL_DARK, 1.0, TOP)
	_fill(Rect2(x + 7, y + 8, 4, 18), ACCENT, Vector4.ONE * 2.0)
	_text(Vector2(x + 18, y + 25), str(_lower.get("name", "")).to_upper(), 22, TEXT)
	_fill(Rect2(x, y + 34, w, 20), Color(ACCENT, 0.92), BOTTOM)
	_text(Vector2(x + 18, y + 49), str(_lower.get("line", "")), 13, PANEL_DARK)


func _draw_shot_card() -> void:
	var a := _slide(_card_t, SHOT_CARD_S)
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
	_fill(Rect2(x, y, w, 30), ACCENT, TOP)
	_text(Vector2(x + 12, y + 21), str(_card.get("title", "SHOT")).to_upper(), 15, PANEL_DARK)
	_panel(Rect2(x, y + 30, w, rows.size() * 24 + 8), PANEL, 1.0, BOTTOM)
	for i in rows.size():
		var ry := y + 52 + i * 24
		_text(Vector2(x + 12, ry), rows[i][0], 13, ACCENT)
		_text_right(Vector2(x + w - 12, ry), str(rows[i][1]), 16, TEXT)


func _draw_hole_card() -> void:
	var a := _slide(_hole_t, HOLE_CARD_S)
	var w := 300.0
	var x := lerpf(-w - 20.0, 16.0, a)
	var y := 92.0
	var map_h := 280.0
	_panel(Rect2(x, y, w, 64), PANEL_DARK, 1.0, TOP)
	_text(Vector2(x + 14, y + 28), "HOLE %s" % _hole.get("number", ""), 24, ACCENT)
	_text_right(Vector2(x + w - 14, y + 28), "PAR %s" % _hole.get("par", ""), 20, TEXT)
	_text(Vector2(x + 14, y + 52), "%s YARDS    %s" % [_hole.get("yards", ""), str(_hole.get("name", "")).to_upper()], 13, DIM)
	_panel(Rect2(x, y + 64, w, map_h + 16), PANEL, 1.0, BOTTOM)
	if _hole_map != null:
		var ms := _hole_map.get_size()
		var scale := minf((w - 16) / ms.x, map_h / ms.y)
		var draw_size := ms * scale
		draw_texture_rect(_hole_map, Rect2(Vector2(x + (w - draw_size.x) * 0.5, y + 72), draw_size), false)


## One line is centred in its box; several (drop options) are stacked
## left-aligned, and the box grows upwards from the same bottom edge.
const CAPTION_BOTTOM := 190.0


func _draw_caption() -> void:
	var fs := 18
	var lines := _caption.split("\n")
	var tw := 0.0
	for line in lines:
		tw = maxf(tw, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var w := tw + 40.0
	var h := caption_height(lines.size())
	var fade := clampf(minf(_caption_t * 4.0, (_caption_len - _caption_t) * 2.0), 0.0, 1.0)
	# Above the swing meter in the bottom right corner (its top is 178 px
	# up), so a long caption never runs underneath it.
	var r := Rect2((size.x - w) * 0.5, size.y - CAPTION_BOTTOM - h, w, h)
	_panel(r, PANEL_DARK, fade, Vector4.ONE * minf(17.0, h * 0.5))
	if lines.size() == 1:
		_text(r.position + Vector2(w * 0.5, 23), _caption, fs, Color(TEXT, fade), true)
		return
	for i in lines.size():
		_text(r.position + Vector2(20, 23 + i * CAPTION_LINE), lines[i], fs, Color(TEXT, fade))


## The top edge of the caption box on screen, or INF while none shows (the
## scorecard keeps clear of it).
func caption_top() -> float:
	if _caption_t < 0.0 or _caption.is_empty():
		return INF
	return size.y - CAPTION_BOTTOM - caption_height(_caption.split("\n").size())


static func caption_height(line_count: int) -> float:
	return 34.0 + CAPTION_LINE * maxf(line_count - 1, 0)


func _draw_replay_bug() -> void:
	var r := Rect2(size.x - 300.0, 16.0, 104.0, 24.0)
	_fill(r, ACCENT, Vector4.ONE * 12.0)
	_text(r.position + Vector2(52, 18), "REPLAY", 15, PANEL_DARK, true)


func _draw_ticker() -> void:
	if _ticker.is_empty():
		return
	var y := size.y - TICKER_H
	_panel(Rect2(0, y, size.x, TICKER_H), PANEL_DARK, 1.0, Vector4.ZERO)
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

## A glass panel tinted `col`, faded by `alpha`, with `corners` rounded
## (top-left, top-right, bottom-right, bottom-left).
func _panel(r: Rect2, col: Color, alpha := 1.0, corners := ALL) -> void:
	glass.add(r, alpha, corners)
	var blur := Glass.blurs()
	var sb := _box(Color(col, col.a * (GLASS_TINT if blur else FLAT_TINT) * alpha), corners)
	if not blur:
		sb.border_color = Color(Glass.RIM, Glass.RIM.a * alpha)
		sb.border_width_top = 1
	draw_style_box(sb, r)


## A solid rounded shape (the accent blocks).
func _fill(r: Rect2, col: Color, corners := ALL) -> void:
	draw_style_box(_box(col, corners), r)


static func _box(col: Color, corners: Vector4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(corners.x)
	sb.corner_radius_top_right = int(corners.y)
	sb.corner_radius_bottom_right = int(corners.z)
	sb.corner_radius_bottom_left = int(corners.w)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	return sb

func _tag(at: Vector2, text: String, right_align: bool) -> void:
	var fs := 13
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var r := Rect2(at.x - w if right_align else at.x, at.y - 18.0, w, 22.0)
	_panel(r, PANEL, 1.0, Vector4.ONE * 11.0)
	_fill(Rect2(r.position + Vector2(5, 6), Vector2(3, r.size.y - 12)), ACCENT, Vector4.ONE * 1.5)
	_text(r.position + Vector2(11, 16), text, fs, TEXT)


func _text(at: Vector2, text: String, fs: int, col: Color, centred := false) -> void:
	var p := at
	if centred:
		p.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_right(at: Vector2, text: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(at.x - w, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A panel sliding in and out over `length` seconds: in on a spring (a
## touch past its place and back, Glass.spring), out on a smooth ease.
static func _slide(t: float, length: float) -> float:
	if t < SPRING_IN_S and t < length * 0.5:
		return Glass.spring(t / SPRING_IN_S)
	return _ease_in_out(t, length) if t > length * 0.5 else 1.0


## 0 -> 1 over the first 0.35 s, 1 until the last 0.35 s, then back to 0.
static func _ease_in_out(t: float, length: float) -> float:
	var u := clampf(minf(t, length - t) / HOLE_CARD_FADE, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)
