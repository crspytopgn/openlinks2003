class_name Hud
extends Control
## On-screen text: hole and shot info, messages, controls, and the meter.
## In the Broadcast presentation the TV graphics (BroadcastOverlay) take the
## place of the info text and bars, and messages become captions.

var info: Label
var message: Label
var hint: Label
var meter: SwingMeter
var wind: WindIndicator
var scorecard: ScorecardPanel
var hand_over: HandOverPanel
## With the player's own interface art: one chrome bar per line of `info`.
var art: HudArt
var _bars: Array[InfoBar] = []
## With the player's own interface art: the PowerStroke panel and swing
## gizmo (bottom left), and the wind, elevation and lie windows (top right).
var shot_panel: ShotPanel
var windows: ShotWindows
var overlay: BroadcastOverlay
var broadcast := false

var _message_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info = _label(20)
	info.position = Vector2(16, 12)
	add_child(info)

	message = _label(28)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(message, Control.PRESET_CENTER_TOP, Rect2(-400, 70, 800, 90))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)

	hint = _label(16)
	_place(hint, Control.PRESET_BOTTOM_LEFT, Rect2(16, -34, 900, 26))
	add_child(hint)

	wind = WindIndicator.new()
	_place(wind, Control.PRESET_TOP_RIGHT, Rect2(-106, 12, 90, 112))
	add_child(wind)

	meter = SwingMeter.new()
	_place(meter, Control.PRESET_BOTTOM_RIGHT, Rect2(-240, -240, 220, 220))
	add_child(meter)

	overlay = BroadcastOverlay.new()
	overlay.visible = false
	add_child(overlay)
	move_child(overlay, 0)

	# Under the scorecard, so Tab still shows the card while it is up.
	hand_over = HandOverPanel.new()
	add_child(hand_over)

	scorecard = ScorecardPanel.new()
	scorecard.visible = false
	add_child(scorecard)


## Switches to the original's interface pieces from the player's files.
func use_art(hud_art: HudArt) -> void:
	art = hud_art
	if art == null:
		return
	info.visible = false
	meter.art = art
	var want := meter.wanted_size()
	_place(meter, Control.PRESET_CENTER_BOTTOM, Rect2(-want.x * 0.5, -want.y - 44.0, want.x, want.y))
	meter.queue_redraw()
	shot_panel = ShotPanel.new(art)
	var panel := shot_panel.wanted_size()
	_place(shot_panel, Control.PRESET_BOTTOM_LEFT, Rect2(12, -panel.y - 40.0, panel.x, panel.y))
	add_child(shot_panel)
	move_child(shot_panel, 0)
	windows = ShotWindows.new(art)
	var box := ShotWindows.wanted_size()
	_place(windows, Control.PRESET_TOP_RIGHT, Rect2(-box.x - 12.0, 12, box.x, box.y))
	add_child(windows)
	move_child(windows, 0)
	_show_classic()


## The club, its reach, the aim point's height above the ball and the lie,
## for the original's panels (nothing without the player's art).
func show_shot(club: Club, reach_text: String, rise_m: float, lie_name: String, lie_power: float) -> void:
	if art == null:
		return
	shot_panel.show_club(HudArt.club_kind(club.full_name, club.is_putter), club.full_name, reach_text)
	windows.show_shot(rise_m, lie_name, lie_power)


## The wind, on the arrow or in the original's wind window.
func show_wind(w: Wind, aim_deg: float) -> void:
	wind.show_wind(w, aim_deg)
	if windows != null:
		windows.show_wind(w, aim_deg)


func _show_classic() -> void:
	var classic := art != null and not broadcast
	if shot_panel != null:
		shot_panel.visible = classic
		windows.visible = classic
	wind.visible = windows == null or broadcast


## Switches between the Classic interface and the broadcast graphics.
func set_broadcast(on: bool) -> void:
	broadcast = on
	overlay.visible = on
	info.visible = not on and art == null
	for bar in _bars:
		bar.visible = false
	_show_classic()
	if on:
		message.text = ""
	else:
		overlay.caption("")
	# The wind sits below the LIVE bug, and the hints above the ticker.
	_place(wind, Control.PRESET_TOP_RIGHT, Rect2(-106, 50 if on else 12, 90, 112))
	_place(hint, Control.PRESET_BOTTOM_LEFT, Rect2(16, -62 if on else -34, 900, 26))


func _process(delta: float) -> void:
	if art != null and not broadcast:
		_update_bars()
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""
	# Keep the card centred as its contents change size.
	if scorecard.visible:
		scorecard.position = (size - scorecard.size) * 0.5


## Shows a message; seconds <= 0 keeps it until the next one.
func show_message(text: String, seconds := 0.0) -> void:
	if broadcast:
		overlay.caption(text.replace("\n", "    "), seconds)
		message.text = ""
		_message_time = 0.0
		return
	message.text = text
	_message_time = seconds


## Anchors `c` to a corner or edge, then offsets it by `r` from that anchor.
func _place(c: Control, preset: Control.LayoutPreset, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_bars() -> void:
	var lines := info.text.split("\n", false)
	while _bars.size() < lines.size():
		var bar := InfoBar.new(art)
		bar.position = Vector2(8, 6 + _bars.size() * (bar.size.y - 10.0))
		add_child(bar)
		move_child(bar, 0)
		_bars.append(bar)
	for i in _bars.size():
		_bars[i].visible = i < lines.size()
		if i < lines.size():
			_bars[i].text = lines[i].strip_edges()
