class_name PlayerCreator
extends Control
## The player creator: a player's golfer (PlayerLook) with a live 3D
## preview (GolferPreview). Tabs for the body (sex, height, build, muscle,
## age, skin, eyes), the face (sixteen shape sliders, or a photo: see
## FaceFromPhoto), hair, clothes and equipment. Saving stores the look with
## the player's profile (PlayerProfiles), so their rounds and stats stay
## together and every round shows their golfer.

signal closed(player_name: String)

const SWATCH := Vector2(30, 30)
const SHOE_COLOURS := [
	["White", Color(1, 1, 1)], ["Black", Color(0.12, 0.12, 0.13)], ["Brown", Color(0.45, 0.3, 0.2)],
	["Grey", Color(0.6, 0.6, 0.62)], ["Navy", Color(0.13, 0.2, 0.4)],
]
const HEAD_COLOURS := [
	["Black", Color(0.06, 0.06, 0.07)], ["Silver", Color(0.7, 0.71, 0.73)], ["White", Color(0.92, 0.92, 0.92)],
	["Blue", Color(0.12, 0.25, 0.6)], ["Red", Color(0.6, 0.08, 0.08)], ["Gold", Color(0.75, 0.6, 0.25)],
]

var look := PlayerLook.new()
var _original_name := ""
var _profiles := PlayerProfiles.new()
var _preview: GolferPreview
var _name: LineEdit
var _message: Label
var _tabs: TabContainer
## Controls to refresh when the look changes as a whole (randomise, reset,
## a photo): look field -> setter Callable taking the look.
var _refreshers: Array[Callable] = []
var _cap_note: Label
var _photo: FaceFromPhoto


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var bg := ColorRect.new()
	bg.color = MenuStyle.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	row.add_child(left)
	_preview = GolferPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(300, 300)
	left.add_child(_preview)
	var views := HBoxContainer.new()
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	views.add_theme_constant_override("separation", 10)
	left.add_child(views)
	var body_view := MenuStyle.button("Whole body")
	body_view.pressed.connect(func() -> void: _preview.set_face_view(false))
	views.add_child(body_view)
	var face_view := MenuStyle.button("Face")
	face_view.pressed.connect(func() -> void: _preview.set_face_view(true))
	views.add_child(face_view)
	var swing := MenuStyle.button("Swing")
	swing.pressed.connect(func() -> void: _preview.swing())
	views.add_child(swing)
	var drag := Label.new()
	drag.text = "Drag to turn the golfer round."
	drag.modulate = Color(1, 1, 1, 0.6)
	drag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(drag)

	var panel := PanelContainer.new()
	MenuStyle.panel(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(MenuStyle.heading("Player creator", 28))
	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size = Vector2(70, 0)
	name_row.add_child(name_label)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.max_length = 24
	_name.placeholder_text = "Your name, as you enter it for a round"
	name_row.add_child(_name)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_build_body_tab()
	_build_face_tab()
	_build_photo_tab()
	_build_hair_tab()
	_build_clothes_tab()
	_build_equipment_tab()
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", MenuStyle.WARNING)
	box.add_child(_message)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var random := MenuStyle.button("Randomise")
	random.pressed.connect(func() -> void: _set_look(PlayerLook.random(randi())))
	buttons.add_child(random)
	var reset := MenuStyle.button("Reset")
	reset.pressed.connect(func() -> void: _set_look(PlayerLook.new()))
	buttons.add_child(reset)
	var cancel := MenuStyle.button("Cancel")
	cancel.pressed.connect(self.cancel)
	buttons.add_child(cancel)
	var save := MenuStyle.button("Save player")
	save.pressed.connect(_save)
	buttons.add_child(save)


## Opens the creator on `player_name`'s golfer, or a new player if empty.
func open(player_name: String) -> void:
	_profiles = PlayerProfiles.load_saved()
	_original_name = player_name
	_name.text = player_name
	var saved := _profiles.look_of(player_name) if not player_name.is_empty() else null
	_message.text = ""
	visible = true
	_set_look(saved if saved != null else PlayerLook.new())
	if not _preview.show_look(look):
		_message.text = "The golfer model is missing from this build, so there is nothing to preview."
	_name.grab_focus.call_deferred()


func close() -> void:
	visible = false
	_photo.clear()


func _set_look(l: PlayerLook) -> void:
	look = l
	for refresh in _refreshers:
		refresh.call()
	_changed()


func _changed() -> void:
	if _cap_note != null:
		_cap_note.visible = look.cap and not look.wears_cap()
	_preview.show_look(look)


func _save() -> void:
	var player_name := _name.text.strip_edges()
	if player_name.is_empty():
		_message.text = "Give the player a name: rounds find their golfer by it."
		return
	_profiles = PlayerProfiles.load_saved()
	if not _original_name.is_empty() and _original_name.strip_edges().to_lower() != player_name.to_lower():
		if _profiles.has_player(player_name):
			_message.text = "There's already a player called %s." % player_name
			return
		_profiles.rename(_original_name, player_name)
	_profiles.set_look(player_name, look)
	_profiles.save()
	close()
	closed.emit(player_name)


func cancel() -> void:
	close()
	closed.emit(_original_name)


# ---- tabs -------------------------------------------------------------


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _build_body_tab() -> void:
	var box := _tab("Body")
	_slider_row(box, "Body", "male", "female", 0.0, 1.0,
		func() -> float: return look.sex, func(v: float) -> void: look.sex = v)
	var height_label := Label.new()
	_slider_row(box, "Height", "", "", PlayerLook.HEIGHT_MIN, PlayerLook.HEIGHT_MAX,
		func() -> float: return look.height_cm,
		func(v: float) -> void:
			look.height_cm = v
			height_label.text = _height_text(v),
		1.0, height_label)
	for entry: Array in PlayerLook.BODY:
		var key: String = entry[0]
		_slider_row(box, entry[1], entry[2], entry[3], -1.0, 1.0,
			func() -> float: return float(look.get(key)), func(v: float) -> void: look.set(key, v))
	_heading(box, "Skin")
	_swatches(box, PlayerLook.SKIN_TONES, func() -> Color: return look.skin, func(c: Color) -> void: look.skin = c)
	_heading(box, "Eyes")
	_choices(box, PlayerLook.EYES, PlayerLook.EYES.map(func(e: String) -> String: return e.capitalize()),
		func() -> String: return look.eyes, func(v: String) -> void: look.eyes = v)


func _build_face_tab() -> void:
	var box := _tab("Face")
	var note := Label.new()
	note.text = "Shape the face, or start from a photo on the Photo tab."
	note.modulate = Color(1, 1, 1, 0.7)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	for entry: Array in PlayerLook.FACE:
		var key: String = entry[0]
		_slider_row(box, entry[1], entry[2], entry[3], -1.0, 1.0,
			func() -> float: return look.face_value(key), func(v: float) -> void: look.face[key] = v)
	var reset := MenuStyle.button("Average face")
	reset.pressed.connect(func() -> void:
		look.face.clear()
		_set_look(look))
	box.add_child(reset)


func _build_photo_tab() -> void:
	var box := _tab("Photo")
	_photo = FaceFromPhoto.new()
	_photo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo.fitted.connect(func(face: Dictionary, skin: Color, hair: Color) -> void:
		for key: String in face:
			look.face[key] = face[key]
		if skin.a > 0.0:
			look.skin = skin
		if hair.a > 0.0:
			look.hair_colour = hair
		_set_look(look))
	box.add_child(_photo)


func _build_hair_tab() -> void:
	var box := _tab("Hair")
	_heading(box, "Style")
	_choices(box, PlayerLook.HAIR_STYLES, PlayerLook.HAIR_NAMES,
		func() -> String: return look.hair, func(v: String) -> void: look.hair = v)
	_heading(box, "Colour")
	_swatches(box, PlayerLook.HAIR_COLOURS, func() -> Color: return look.hair_colour,
		func(c: Color) -> void: look.hair_colour = c)


func _build_clothes_tab() -> void:
	var box := _tab("Clothes")
	_heading(box, "Outfit")
	_choices(box, PlayerLook.OUTFITS, PlayerLook.OUTFIT_NAMES,
		func() -> String: return look.outfit, func(v: String) -> void: look.outfit = v)
	_heading(box, "Shirt")
	_swatches(box, PlayerLook.CLOTH_COLOURS, func() -> Color: return look.top, func(c: Color) -> void: look.top = c)
	_heading(box, "Trousers or shorts")
	_swatches(box, PlayerLook.CLOTH_COLOURS, func() -> Color: return look.bottom, func(c: Color) -> void: look.bottom = c)
	_heading(box, "Shoes")
	_swatches(box, SHOE_COLOURS, func() -> Color: return look.shoes, func(c: Color) -> void: look.shoes = c)
	var cap := CheckBox.new()
	cap.text = "Cap"
	cap.toggled.connect(func(on: bool) -> void:
		look.cap = on
		_changed())
	_refreshers.append(func() -> void: cap.set_pressed_no_signal(look.cap))
	box.add_child(cap)
	_cap_note = Label.new()
	_cap_note.text = "The cap is left off with this hair style."
	_cap_note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_cap_note)
	_swatches(box, PlayerLook.CLOTH_COLOURS, func() -> Color: return look.cap_colour,
		func(c: Color) -> void: look.cap_colour = c)


func _build_equipment_tab() -> void:
	var box := _tab("Equipment")
	_heading(box, "Driver head")
	_swatches(box, HEAD_COLOURS, func() -> Color: return look.club_head, func(c: Color) -> void: look.club_head = c)
	_heading(box, "Shafts")
	_choices(box, PlayerLook.SHAFTS, ["Steel", "Graphite", "Black"],
		func() -> String: return look.shaft, func(v: String) -> void: look.shaft = v)
	_heading(box, "Grips")
	_swatches(box, PlayerLook.CLOTH_COLOURS, func() -> Color: return look.grip, func(c: Color) -> void: look.grip = c)
	_heading(box, "Ball")
	_swatches(box, PlayerLook.BALL_COLOURS, func() -> Color: return look.ball, func(c: Color) -> void: look.ball = c)
	var note := Label.new()
	note.text = "The clubs in the bag play as the game's own; their looks are yours."
	note.modulate = Color(1, 1, 1, 0.6)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


# ---- controls ---------------------------------------------------------


func _heading(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MenuStyle.ACCENT)
	l.add_theme_font_size_override("font_size", 17)
	box.add_child(l)


## A labelled slider; `low` and `high` name its ends.
func _slider_row(box: VBoxContainer, label: String, low: String, high: String, from: float, to: float,
		getter: Callable, setter: Callable, step := 0.01, value_label: Label = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	if not low.is_empty():
		var lo := Label.new()
		lo.text = low
		lo.modulate = Color(1, 1, 1, 0.55)
		lo.custom_minimum_size = Vector2(66, 0)
		lo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(lo)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		_changed())
	row.add_child(slider)
	if not high.is_empty():
		var hi := Label.new()
		hi.text = high
		hi.modulate = Color(1, 1, 1, 0.55)
		hi.custom_minimum_size = Vector2(66, 0)
		row.add_child(hi)
	if value_label != null:
		value_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(value_label)
	_refreshers.append(func() -> void:
		slider.set_value_no_signal(float(getter.call()))
		if value_label != null:
			setter.call(float(getter.call())))


## A row of buttons, one per option; the chosen one is highlighted.
func _choices(box: VBoxContainer, values: Array, labels: Array, getter: Callable, setter: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	var buttons: Array[Button] = []
	var group := ButtonGroup.new()
	for i in values.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 34)
		var value: String = values[i]
		b.pressed.connect(func() -> void:
			setter.call(value)
			_changed())
		flow.add_child(b)
		buttons.append(b)
	_refreshers.append(func() -> void:
		for i in values.size():
			buttons[i].set_pressed_no_signal(values[i] == getter.call()))


## Colour swatches for `colours` ([name, Color] pairs), and a picker for
## any other colour.
func _swatches(box: VBoxContainer, colours: Array, getter: Callable, setter: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	box.add_child(flow)
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(56, SWATCH.y)
	picker.tooltip_text = "Any colour"
	for entry: Array in colours:
		var b := Button.new()
		b.custom_minimum_size = SWATCH
		b.tooltip_text = entry[0]
		var c: Color = entry[1]
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = c
			style.set_corner_radius_all(4)
			style.set_border_width_all(2 if state != "normal" else 1)
			style.border_color = MenuStyle.ACCENT if state != "normal" else Color(0, 0, 0, 0.5)
			b.add_theme_stylebox_override(state, style)
		b.pressed.connect(func() -> void:
			setter.call(c)
			picker.color = c
			_changed())
		flow.add_child(b)
	picker.color_changed.connect(func(c: Color) -> void:
		setter.call(c)
		_changed())
	flow.add_child(picker)
	_refreshers.append(func() -> void: picker.color = getter.call())


static func _height_text(cm: float) -> String:
	var inches := roundi(cm / 2.54)
	return "%d cm (%d ft %d in)" % [roundi(cm), inches / 12, inches % 12]
