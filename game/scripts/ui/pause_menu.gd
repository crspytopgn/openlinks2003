class_name PauseMenu
extends PanelContainer
## The in-round menu behind Esc: resume, scorecard, settings, restart, or back
## to the main menu.

signal resume_pressed
signal scorecard_pressed
signal settings_pressed
signal restart_pressed
signal menu_pressed

var _first: Button


func _ready() -> void:
	MenuStyle.panel(self)
	set_anchors_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(300, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Paused"))
	_first = _button(box, "Resume", resume_pressed)
	_button(box, "Scorecard", scorecard_pressed)
	_button(box, "Settings", settings_pressed)
	_button(box, "Restart round", restart_pressed)
	_button(box, "Quit to main menu", menu_pressed)
	visible = false


func _process(_delta: float) -> void:
	if visible:
		position = (get_viewport_rect().size - size) * 0.5


func open() -> void:
	visible = true
	SceneFade.pop_in(self)
	_first.grab_focus()


func close() -> void:
	visible = false


func _button(box: VBoxContainer, text: String, sig: Signal) -> Button:
	var b := MenuStyle.button(text)
	b.pressed.connect(sig.emit)
	box.add_child(b)
	return b
