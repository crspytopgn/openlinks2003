class_name PlayersPanel
extends PanelContainer
## The "Players" page: every saved profile (PlayerProfiles) with its handicap
## index and rounds. Picking a player shows their career stats (scoring
## average, fairways, greens in regulation, putts) and lists their recent
## rounds; Delete asks once more, then removes the profile.

signal back_pressed

## Rounds listed for the picked player, newest first.
const SHOWN_ROUNDS := 20

var _profiles := PlayerProfiles.new()
var _list: VBoxContainer
var _detail_title: Label
var _detail: VBoxContainer
var _empty: Label
var _back: Button
var _picked := ""
var _confirm := ""  ## the player whose Delete was pressed once


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(700, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Players", 30))
	var help := Label.new()
	help.text = "Every finished round of nine holes or more is kept here. Three rounds give a handicap index."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(help)
	_empty = Label.new()
	_empty.text = "No players yet. Play a round and it shows up here."
	box.add_child(_empty)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 170)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 18)
	_detail_title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	box.add_child(_detail_title)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(0, 170)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_back = MenuStyle.button("Back")
	_back.pressed.connect(back_pressed.emit)
	buttons.add_child(_back)
	visible = false


func open() -> void:
	_profiles = PlayerProfiles.load_saved()
	_confirm = ""
	var players := _profiles.names()
	if not players.has(_picked):
		_picked = players[0] if not players.is_empty() else ""
	_fill()
	visible = true
	_back.grab_focus.call_deferred()


func close() -> void:
	visible = false


## One line per player: name, index, rounds, last played, Delete.
func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	var players := _profiles.names()
	_empty.visible = players.is_empty()
	for player in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name_button := Button.new()
		name_button.text = player
		name_button.flat = player != _picked
		name_button.custom_minimum_size = Vector2(200, 34)
		name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_button.pressed.connect(_pick.bind(player))
		row.add_child(name_button)
		var played := _profiles.rounds(player)
		var index := _profiles.index_of(player)
		var index_text := "Index " + Handicap.format(index)
		if index != Handicap.NONE and not _profiles.has_record(player):
			index_text += " (start)"
		row.add_child(_label(index_text, 160))
		row.add_child(_label("%d round%s" % [played.size(), "" if played.size() == 1 else "s"], 100))
		row.add_child(_label(str(played.back().get("date", "")) if not played.is_empty() else "", 110))
		var delete := Button.new()
		delete.text = "Sure? Delete" if _confirm == player else "Delete"
		delete.pressed.connect(_on_delete.bind(player))
		row.add_child(delete)
		_list.add_child(row)
	_fill_detail()


## The picked player's recent rounds, newest first.
func _fill_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()
	_detail_title.visible = not _picked.is_empty()
	if _picked.is_empty():
		return
	var played := _profiles.rounds(_picked)
	_detail_title.text = "%s: recent rounds" % _picked if not played.is_empty() else "%s: no rounds yet" % _picked
	var career := PlayerProfiles.career_text(_profiles.career(_picked))
	if not career.is_empty():
		var c := _label("Career (%d rounds): %s" % [_profiles.career(_picked).rounds, career], 0)
		c.add_theme_color_override("font_color", MenuStyle.ACCENT)
		_detail.add_child(c)
	var used := _used_rounds(played)
	for k in mini(played.size(), SHOWN_ROUNDS):
		var i := played.size() - 1 - k
		var r: Dictionary = played[i]
		var gross := int(r.get("gross", 0))
		var par := int(r.get("par", 0))
		var line := "%s   %s   %d holes   %d (%s)   differential %s" % [
			r.get("date", ""), r.get("course", ""), int(r.get("holes", 0)), gross,
			Scorecard.format_to_par(gross - par), _signed(int(r.get("differential", 0)))]
		if r.has("putts"):
			line += "   FW %d/%d   GIR %d   Putts %d" % [int(r.fairways), int(r.fairway_holes), int(r.gir), int(r.putts)]
		if used.has(i):
			line += "   *"
		_detail.add_child(_label(line, 0))
	if not used.is_empty():
		var note := _label("* counts towards the index", 0)
		note.modulate = Color(1, 1, 1, 0.6)
		_detail.add_child(note)


## Indices in `played` of the differentials the index uses: the lowest of the
## most recent 20, as many as Handicap.index takes.
func _used_rounds(played: Array) -> Array[int]:
	var first := maxi(0, played.size() - Handicap.ROUNDS)
	var recent: Array[int] = []
	for i in range(first, played.size()):
		recent.append(i)
	recent.sort_custom(_lower_differential.bind(played))
	return recent.slice(0, Handicap.rounds_used(recent.size()))


func _lower_differential(a: int, b: int, played: Array) -> bool:
	var da := int((played[a] as Dictionary).get("differential", 0))
	var db := int((played[b] as Dictionary).get("differential", 0))
	return da < db or (da == db and a < b)


## Tenths as "12.3" or "-2.0".
static func _signed(tenths: int) -> String:
	var a := absi(tenths)
	return "%s%d.%d" % ["-" if tenths < 0 else "", a / 10, a % 10]


func _pick(player: String) -> void:
	_picked = player
	_confirm = ""
	_fill()


func _on_delete(player: String) -> void:
	if _confirm != player:
		_confirm = player
		_fill()
		return
	_profiles.remove(player)
	_profiles.save()
	_confirm = ""
	if _picked == player:
		var players := _profiles.names()
		_picked = players[0] if not players.is_empty() else ""
	_fill()


func _label(text: String, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(660, 0)
	return l
