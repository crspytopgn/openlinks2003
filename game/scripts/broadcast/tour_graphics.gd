class_name TourGraphics
extends Control
## The Tour presentation's graphics package, drawn over the Broadcast one in
## the style of a modern tour broadcast, with our own look and names:
## - a leaderboard rail down the left: holes to play, every player's place
##   and score, and the player on the shot picked out with a hole strip
##   (the hole, its length, and which shot of par this is);
## - a shot-data bar along the bottom: a wind dial, the club, a range line
##   from the ball to the pin with the club's carry-to-total window, and an
##   expected score for the hole from here;
## - labels for the driving zone (DrivingZone) drawn on the fairway;
## - a putt read panel (PuttRead): distance, slope and aim;
## - a tall hole map down the right with every shot played on the hole.
## Everything is plain shapes and the default font, like BroadcastOverlay.

const BASE := Color(0.07, 0.08, 0.1, 0.92)
const BASE_LIGHT := Color(0.13, 0.15, 0.18, 0.92)
const ACCENT := Color(0.42, 0.86, 0.72)  ## tour mint, kept soft
const HOT := Color(0.95, 0.47, 0.34)
const TEXT := Color(1, 1, 1)
const DIM := Color(0.7, 0.76, 0.8)
const INK := Color(0.04, 0.06, 0.07)
## Panels are frosted glass (FrostedGlass) under a tint this see-through.
const GLASS_TINT := 0.62
## One colour per player for their chip and their shots on the map.
const PLAYER_COLORS := [
	Color(0.25, 0.95, 0.75), Color(1.0, 0.45, 0.35), Color(0.62, 0.5, 1.0), Color(1.0, 0.8, 0.25),
	Color(0.35, 0.7, 1.0), Color(1.0, 0.5, 0.85), Color(0.6, 0.9, 0.3), Color(0.9, 0.9, 0.9),
]
const RAIL_W := 228.0
const ROW_H := 30.0
const BAR_H := 92.0
const MAP_SCALE := 1.9
const METER_W := 250.0  ## room left on the right for the swing meter

var state := {}  ## see set_state
var zone := {}  ## DrivingZone.compute
var putt := {}  ## PuttRead.read
var _map: HoleMap
var _dots: Array = []  ## [world position, player index]
var _ball := Vector3.ZERO
var _show_map := false
var glass: FrostedGlass
var _font: Font
var _bold: FontVariation
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass = FrostedGlass.new()
	add_child(glass)
	_font = GlassTheme.font(600)
	_bold = FontVariation.new()
	_bold.base_font = GlassTheme.font(800)
	_bold.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.12, 1), Vector2.ZERO)  # a sporty lean


## Keys: to_play, round (label), rows (array of {pos, name, to_par, player,
## current}), hole, par, yards, stroke, aiming, putting, club, carry_yd,
## total_yd, to_pin_yd, wind_mph, wind_rel_deg (0 helping, 90 from the
## right), expected (score for the hole from here).
func set_state(s: Dictionary) -> void:
	state = s
	queue_redraw()


## The hole's map and the shots played on it so far.
func set_map(map: HoleMap, dots: Array, ball: Vector3, show: bool) -> void:
	_map = map
	_dots = dots
	_ball = ball
	_show_map = show
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	glass.begin()
	_draw_pieces()
	glass.commit()


## A frosted-glass panel tinted `col`.
func _panel(r: Rect2, col: Color) -> void:
	glass.add(r)
	draw_rect(r, Color(col, col.a * GLASS_TINT))


func _draw_pieces() -> void:
	if state.is_empty():
		return
	_draw_rail()
	var aiming: bool = state.get("aiming", false)
	if aiming and not putt.is_empty():
		_draw_putt_panel()
	elif aiming and not state.get("putting", false):
		_draw_shot_bar()
	if aiming and not zone.is_empty():
		_draw_zone_labels()
	if _show_map and _map != null:
		_draw_map()


# --- Leaderboard rail ---------------------------------------------------------

func _draw_rail() -> void:
	var rows: Array = state.get("rows", [])
	var y := 0.0
	var top_h := 92.0
	_panel(Rect2(0, 0, RAIL_W, top_h), BASE)
	# Diagonal pinstripes in the header, as on a tour board.
	for i in 14:
		var x := -40.0 + i * 22.0
		draw_line(Vector2(x, top_h), Vector2(x + 50, 0), Color(1, 1, 1, 0.035), 8.0)
	_text(Vector2(16, 22), str(state.get("round", "")).to_upper(), 13, DIM, _font)
	var big := str(state.get("to_play", ""))
	_text(Vector2(14, 82), big, 60, ACCENT, _bold)
	var bw := _bold.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x
	_text(Vector2(22 + bw, 58), "TO", 20, TEXT, _bold)
	_text(Vector2(22 + bw, 80), "PLAY", 20, TEXT, _bold)
	y = top_h
	var last_pos := ""
	for row: Dictionary in rows:
		var current: bool = row.get("current", false)
		var w := RAIL_W + (80.0 if current else 0.0)
		draw_rect(Rect2(0, y, w, ROW_H), ACCENT if current else (BASE if int(row.get("player", 0)) % 2 == 0 else BASE_LIGHT))
		var pos := str(row.get("pos", ""))
		var ink := INK if current else TEXT
		if pos != last_pos or current:
			_text(Vector2(14, y + 21), pos, 17, ink, _bold)
		last_pos = pos
		var chip := Rect2(40, y + 3, ROW_H - 6, ROW_H - 6)
		var pc: Color = PLAYER_COLORS[int(row.get("player", 0)) % PLAYER_COLORS.size()]
		draw_rect(chip, pc if not current else INK)
		var name := str(row.get("name", "")).to_upper()
		_text(chip.get_center() + Vector2(0, 6), name.left(1), 15, INK if not current else pc, _bold, true)
		_text(Vector2(74, y + 21), name if current else _short(name), 16, ink, _bold)
		var to_par := str(row.get("to_par", "E"))
		_text_right(Vector2(w - 14, y + 21), to_par, 18, ink if current or not to_par.begins_with("-") else HOT, _bold)
		y += ROW_H
		if current:
			_draw_hole_strip(y, w)
			y += ROW_H
	_panel(Rect2(0, y, RAIL_W, 6), BASE)


## Under the current player: the hole, its length, and the shot boxes.
func _draw_hole_strip(y: float, w: float) -> void:
	draw_rect(Rect2(0, y, w, ROW_H), INK)
	_text(Vector2(14, y + 22), "HOLE %s" % state.get("hole", ""), 17, TEXT, _bold)
	_text(Vector2(98, y + 21), "%s YDS" % state.get("yards", ""), 12, DIM, _font)
	var par := int(state.get("par", 4))
	var stroke := int(state.get("stroke", 1))
	var boxes := maxi(par, stroke)
	var bx := w - 12.0 - boxes * 22.0
	for i in boxes:
		var r := Rect2(bx + i * 22.0, y + 4, 20, ROW_H - 8)
		var n := i + 1
		if n == stroke:
			draw_rect(r, ACCENT)
		_text(r.get_center() + Vector2(0, 6), str(n), 14, INK if n == stroke else (DIM if n < stroke else TEXT), _bold, true)


# --- Shot data bar ------------------------------------------------------------

func _draw_shot_bar() -> void:
	var x0 := RAIL_W + 24.0
	var x1 := size.x - METER_W
	var y := size.y - BAR_H - 18.0
	_panel(Rect2(x0, y, x1 - x0, BAR_H), BASE)
	draw_rect(Rect2(x0, y - 4, x1 - x0, 4), ACCENT)
	# Title block.
	var x := x0
	_text(Vector2(x + 12, y + 42), "SHOT", 22, ACCENT, _bold)
	_text(Vector2(x + 12, y + 66), "DATA", 22, TEXT, _bold)
	x += 84.0
	# Wind dial.
	var c := Vector2(x + 46, y + BAR_H * 0.5)
	draw_circle(c, 36, INK)
	draw_arc(c, 36, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	for k in 12:
		var a := TAU * k / 12.0
		draw_line(c + Vector2(sin(a), -cos(a)) * 31, c + Vector2(sin(a), -cos(a)) * 35, Color(1, 1, 1, 0.4), 1.5)
	var mph := float(state.get("wind_mph", 0.0))
	if mph >= 0.5:
		# Up the dial is downrange: the arrow points where the wind blows.
		var rel := deg_to_rad(float(state.get("wind_rel_deg", 0.0)))
		var d := Vector2(-sin(rel), -cos(rel))
		var side := Vector2(-d.y, d.x)
		# A tail where it comes from and a head where it goes, on the rim.
		draw_line(c - d * 34, c - d * 25, ACCENT, 3.0)
		var tip := c + d * 34
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 12 + side * 7, tip - d * 12 - side * 7]), ACCENT)
	_text(c + Vector2(0, 2), "%d" % roundi(mph), 22, TEXT, _bold, true)
	_text(c + Vector2(0, 18), "MPH", 10, DIM, _font, true)
	x += 100.0
	# Club.
	draw_rect(Rect2(x, y, 112, BAR_H), ACCENT)
	var club := str(state.get("club", "")).to_upper()
	var words := club.split(" ", false, 1)
	_text(Vector2(x + 10, y + 36), words[0] if words.size() > 0 else "", 22, INK, _bold)
	_text(Vector2(x + 10, y + 60), words[1] if words.size() > 1 else "", 16, INK, _bold)
	_text(Vector2(x + 10, y + 82), "%s YD" % state.get("total_yd", ""), 12, INK, _font)
	x += 112.0
	# Expected score, on the right.
	var exp_w := 128.0
	var rx1 := x1 - exp_w
	_draw_range(Rect2(x + 16, y, rx1 - x - 32, BAR_H))
	var expected := float(state.get("expected", 0.0))
	var par := float(state.get("par", 4))
	var col := ACCENT if expected <= par else (HOT if expected > par + 0.5 else Color(1.0, 0.75, 0.3))
	_panel(Rect2(rx1, y, exp_w, BAR_H), BASE_LIGHT)
	_text(Vector2(rx1 + exp_w * 0.5, y + 56), "%.2f" % expected, 36, col, _bold, true)
	_text(Vector2(rx1 + exp_w * 0.5, y + 78), "EXPECTED SCORE", 11, DIM, _font, true)


## Ball on the left, pin on the right, yards along the bottom, the club's
## carry-to-total window shaded, and where the shot gets to.
func _draw_range(r: Rect2) -> void:
	var to_pin := float(state.get("to_pin_yd", 0))
	var carry := float(state.get("carry_yd", 0))
	var total := float(state.get("total_yd", 0))
	var span := maxf(maxf(to_pin, total) * 1.06, 20.0)
	var lx := r.position.x + 22.0
	var rx := r.end.x - 34.0
	var line_y := r.position.y + 50.0
	var at := func(yd: float) -> float: return lerpf(lx, rx, clampf(yd / span, 0.0, 1.0))
	# Ticks.
	var step := 10.0 if span < 80.0 else (25.0 if span < 160.0 else (50.0 if span < 300.0 else 100.0))
	var t := step
	while t < span:
		var tx: float = at.call(t)
		draw_line(Vector2(tx, r.position.y + 18), Vector2(tx, r.end.y - 6), Color(1, 1, 1, 0.08), 1.0)
		_text(Vector2(tx, r.end.y - 8), "%d" % roundi(t), 10, DIM, _font, true)
		t += step
	# The club's window.
	var wx0: float = at.call(carry)
	var wx1: float = at.call(total)
	if wx1 - wx0 > 1.0:
		draw_rect(Rect2(wx0, r.position.y + 18, wx1 - wx0, r.size.y - 32), Color(ACCENT, 0.22))
		draw_rect(Rect2(wx0, r.position.y + 18, wx1 - wx0, 3), ACCENT)
	# Labels either side of the window when it is narrow.
	var apart := wx1 - wx0 > 50.0
	if apart:
		_text(Vector2(wx0, r.position.y + 14), "CARRY", 11, ACCENT, _bold, true)
		_text(Vector2(wx1, r.position.y + 14), "TOTAL", 11, HOT, _bold, true)
	else:
		_text_right(Vector2(wx0 - 2, r.position.y + 14), "CARRY", 11, ACCENT, _bold)
		_text(Vector2(wx1 + 2, r.position.y + 14), "TOTAL", 11, HOT, _bold)
	# Ball to where the shot gets to, then on to the pin.
	var reach := minf(total, to_pin) if to_pin > 0.0 else total
	var gx: float = at.call(reach)
	draw_line(Vector2(lx, line_y), Vector2(gx, line_y), TEXT, 3.0)
	draw_circle(Vector2(lx, line_y), 7.0, TEXT)
	draw_arc(Vector2(gx, line_y), 9.0, 0, TAU, 24, ACCENT, 3.0)
	draw_circle(Vector2(gx, line_y), 3.5, ACCENT)
	_pill(Vector2((lx + gx) * 0.5, line_y), "%d YD" % roundi(reach))
	var px: float = at.call(to_pin)
	if to_pin - reach > 1.0:
		var dx := gx + 12.0
		while dx < px - 4.0:
			draw_line(Vector2(dx, line_y), Vector2(minf(dx + 6.0, px - 4.0), line_y), Color(1, 1, 1, 0.7), 2.0)
			dx += 11.0
		_pill(Vector2((gx + px) * 0.5, line_y), "%d YD" % roundi(to_pin - reach))
	# The flag.
	draw_line(Vector2(px, line_y + 16), Vector2(px, line_y - 26), TEXT, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(px, line_y - 26), Vector2(px + 26, line_y - 20), Vector2(px, line_y - 12)]), ACCENT)
	_text(Vector2(px + 10, line_y - 15), str(state.get("hole", "")), 10, INK, _bold, true)
	_text(Vector2(r.position.x, r.position.y + 14), "PAR %s" % state.get("par", ""), 12, TEXT, _bold)


func _pill(c: Vector2, text: String) -> void:
	var fs := 13
	var w := _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
	var r := Rect2(c.x - w * 0.5, c.y - 11, w, 22)
	draw_rect(r, TEXT)
	_text(Vector2(c.x, c.y + 5), text, fs, INK, _bold, true)


# --- Driving zone, putt read, map ---------------------------------------------

func _draw_zone_labels() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var anchors: Array = zone.get("anchors", [])
	var keys := ["left", "hit", "right"]
	var words := ["MISS LEFT", "FAIRWAY", "MISS RIGHT"]
	for i in mini(anchors.size(), 3):
		var p: Vector3 = anchors[i]
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p) + Vector2(0, -40)
		var w := 112.0
		var r := Rect2(s.x - w * 0.5, s.y - 46, w, 50)
		if r.position.x < RAIL_W + 90.0:
			r.position.x = RAIL_W + 90.0 + i * 4.0
		_panel(r, BASE)
		var score := float(zone.get("score_" + keys[i], 0.0))
		_text(Vector2(r.get_center().x, r.position.y + 30), "%.2f" % score, 26, ACCENT if i == 1 else HOT, _bold, true)
		var pct := roundi(float(zone.get(keys[i], 0.0)) * 100.0)
		_text(Vector2(r.get_center().x, r.position.y + 45), "%d%% %s" % [pct, words[i]], 11, TEXT, _font, true)


func _draw_putt_panel() -> void:
	var w := 300.0
	var h := 128.0
	var r := Rect2(size.x - w - METER_W, size.y - h - 18.0, w, h)
	draw_rect(Rect2(r.position, Vector2(w, 34)), ACCENT)
	_text(r.position + Vector2(14, 25), "THE READ", 20, INK, _bold)
	_panel(Rect2(r.position + Vector2(0, 34), Vector2(w, h - 34)), BASE)
	draw_rect(Rect2(r.position + Vector2(0, h - 4), Vector2(w, 4)), ACCENT)
	var feet := float(putt.get("distance_m", 0.0)) * 3.28084
	var rows := [
		["DISTANCE", "%d'" % roundi(feet) if feet >= 3.0 else "%d\"" % roundi(feet * 12.0)],
		["SLOPE", PuttRead.slope_text(float(putt.get("rise_m", 0.0)), float(putt.get("distance_m", 0.0)))],
		["AIM", PuttRead.aim_text(float(putt.get("aim_off_m", 0.0)))],
	]
	for i in rows.size():
		var ry := r.position.y + 60 + i * 28
		_text_right(Vector2(r.position.x + 118, ry), rows[i][0], 16, TEXT, _bold)
		_text(Vector2(r.position.x + 130, ry), str(rows[i][1]), 18, TEXT, _font)
	# The aim target on the green.
	var cam := get_viewport().get_camera_3d()
	if cam != null and putt.has("aim_point"):
		var p: Vector3 = putt.aim_point
		if not cam.is_position_behind(p):
			var s := cam.unproject_position(p)
			var pulse := 1.0 + 0.1 * sin(_time * 5.0)
			draw_line(s, s + Vector2(0, -34), ACCENT, 3.0)
			var top := s + Vector2(0, -44)
			draw_circle(top, 11.0 * pulse, INK)
			draw_arc(top, 11.0 * pulse, 0, TAU, 24, ACCENT, 3.0)
			draw_circle(top, 4.0, ACCENT)


## Where the hole map is drawn, in this control's coordinates; empty when
## it isn't showing.
func map_rect() -> Rect2:
	if _map == null or not _show_map or not visible:
		return Rect2()
	var ms := Vector2(HoleMap.WIDTH, HoleMap.HEIGHT) * MAP_SCALE
	return Rect2(Vector2(size.x - ms.x - 24.0, 58.0), ms)


## The course spot (world x, z) under a click on the hole map, or null when
## the click isn't on it. `local` is in this control's coordinates.
func map_spot(local: Vector2) -> Variant:
	var r := map_rect()
	if not r.has_point(local):
		return null
	return _map.from_px((local - r.position) / MAP_SCALE)


func _draw_map() -> void:
	var r := map_rect()
	var ms := r.size
	var pos := r.position
	var frame := Rect2(pos - Vector2(8, 8), ms + Vector2(16, 52))
	_panel(frame, Color(BASE, 0.6))
	draw_texture_rect(_map.texture, Rect2(pos, ms), false, Color(1, 1, 1, 0.92))
	draw_rect(Rect2(pos, ms), Color(ACCENT, 0.8), false, 2.0)
	for d: Array in _dots:
		var q := pos + _map.to_px(d[0]) * MAP_SCALE
		draw_circle(q, 5.0, INK)
		draw_circle(q, 3.8, PLAYER_COLORS[int(d[1]) % PLAYER_COLORS.size()])
	var b := pos + _map.to_px(_ball) * MAP_SCALE
	draw_circle(b, 5.5 + sin(_time * 5.0), Color(1, 1, 1, 0.9))
	draw_circle(b, 3.0, INK)
	_text(Vector2(pos.x + 4, pos.y + ms.y + 34), "HOLE", 18, TEXT, _bold)
	_text_right(Vector2(pos.x + ms.x - 4, pos.y + ms.y + 38), str(state.get("hole", "")), 34, ACCENT, _bold)


# --- Helpers ------------------------------------------------------------------

## "J. SMITH" style for the rail.
static func _short(name: String) -> String:
	var parts := name.split(" ", false)
	if parts.size() < 2:
		return name.left(12)
	return ("%s. %s" % [parts[0].left(1), parts[parts.size() - 1]]).left(12)


func _text(at: Vector2, text: String, fs: int, col: Color, font: Font = null, centred := false) -> void:
	var f := font if font != null else _font
	var p := at
	if centred:
		p.x -= f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_right(at: Vector2, text: String, fs: int, col: Color, font: Font = null) -> void:
	var f := font if font != null else _font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(at.x - w, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
