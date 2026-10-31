class_name DesignerPanel
extends PanelContainer
## The course designer's side panel: file buttons, tools and their options,
## and the hole being edited. CourseDesigner reads the controls and listens
## to the signals.

signal file_action(action: String)  ## new, open, save, import, export, real, play, menu
signal tool_changed(tool: int)
signal surface_changed(surface: int)
signal hole_selected(index: int)
signal hole_action(action: String)  ## add, delete
signal par_changed(par: int)
signal name_changed(text: String)
signal photo_toggled(on: bool)

enum Tool { SELECT, SHAPE, RAISE, LOWER, SMOOTH, FLATTEN, TREES, TEE, PIN, AIM, OBJECTS, PATH }

const TOOL_NAMES := ["Select", "Draw area", "Raise", "Lower", "Smooth", "Flatten", "Trees", "Tee", "Pin", "Aim point", "Objects", "Path"]
const TOOL_HELP := [
	"Click an area to select it, then drag it or its points. Double-click its edge to add a point, right-click a point to remove it, Delete removes the area. Drag the current hole's tees, pin and aim points.",
	"Click to place the outline's points. Click the first point, press Enter or right-click to finish; Esc cancels.",
	"Hold the left button to raise the ground under the brush.",
	"Hold the left button to lower the ground under the brush.",
	"Hold the left button to smooth bumps away.",
	"Hold the left button to level the ground to the height where you started.",
	"Hold the left button to plant trees in the rough. Hold Shift to clear them.",
	"Click to put the chosen tee of the current hole.",
	"Click to put the current hole's pin. Put it on a green.",
	"Click to add an aim point along the hole (where the computer aims and the hole is measured). Right-click one to remove it.",
	"Click to place the chosen object; Shift+click removes the nearest one. With your game files loaded, every object in the game's library is here: trees, bushes, buildings, grandstands and more.",
	"Click to lay a cart path's points; Enter, right-click or a double-click finishes. Tick Bridge to make it a bridge (over water or a gully). Shift+click removes the nearest path.",
]
## Surfaces offered for painting, in menu order.
const PAINTABLE := [
	Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.SAND, Surface.Type.WATER,
	Surface.Type.FRINGE, Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS,
]

var course_name: LineEdit
var credits: Label
var photo: CheckBox
var surface: OptionButton
var brush_size: HSlider
var strength: HSlider
var tree_kind: OptionButton
var tee_slot: OptionButton
var holes: OptionButton
var par: SpinBox
var hole_info: Label
var help: Label
var object_category: OptionButton
var object_list: ItemList
var object_turn: HSlider
var object_random: CheckBox
var object_scale: HSlider
var path_width: HSlider
var path_bridge: CheckBox
var tool: int = Tool.SELECT

var _tool_buttons: Array[Button] = []
var _option_rows := {}  ## name -> Control
var _quiet := false


func _ready() -> void:
	MenuStyle.panel(self)
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	box.add_child(MenuStyle.heading("Course designer", 24))
	course_name = LineEdit.new()
	course_name.placeholder_text = "Course name"
	course_name.max_length = 40
	course_name.text_changed.connect(func(t: String) -> void:
		if not _quiet:
			name_changed.emit(t))
	box.add_child(course_name)
	credits = Label.new()
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_theme_font_size_override("font_size", 11)
	credits.modulate = Color(1, 1, 1, 0.6)
	credits.visible = false
	box.add_child(credits)
	photo = CheckBox.new()
	photo.text = "Show the aerial photo"
	photo.tooltip_text = "Lay the real course's aerial photo over the ground, to check and trace the areas against it."
	photo.visible = false
	photo.toggled.connect(func(on: bool) -> void:
		if not _quiet:
			photo_toggled.emit(on))
	box.add_child(photo)
	box.add_child(_button_row([["New", "new"], ["Open", "open"], ["Save", "save"]]))
	box.add_child(_button_row([["Import", "import"], ["Export", "export"]]))
	var real := MenuStyle.button("Real course...")
	real.tooltip_text = "Build a real golf course from open map and lidar data: type the club's name."
	real.pressed.connect(func() -> void: file_action.emit("real"))
	box.add_child(real)
	var play := MenuStyle.button("Play this course")
	play.pressed.connect(func() -> void: file_action.emit("play"))
	box.add_child(play)

	box.add_child(_section("Tools"))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(select_tool.bind(i))
		grid.add_child(b)
		_tool_buttons.append(b)

	surface = OptionButton.new()
	for s: int in PAINTABLE:
		surface.add_item(Surface.name_of(s), s)
	surface.item_selected.connect(func(i: int) -> void:
		if not _quiet:
			surface_changed.emit(surface.get_item_id(i)))
	_option(box, "surface", "Surface", surface)
	brush_size = _slider(4.0, 80.0, 18.0)
	_option(box, "size", "Brush size", brush_size)
	strength = _slider(0.1, 1.0, 0.5)
	strength.step = 0.05
	_option(box, "strength", "Strength", strength)
	tree_kind = OptionButton.new()
	for n in DesignedCourse.TREE_NAMES:
		tree_kind.add_item(n)
	tree_kind.add_item("Mixed")
	tree_kind.select(DesignedCourse.TREE_NAMES.size())
	_option(box, "trees", "Trees", tree_kind)
	tee_slot = OptionButton.new()
	for n in DesignedHole.TEE_NAMES:
		tee_slot.add_item(n)
	_option(box, "tee", "Tee", tee_slot)
	_build_objects(box)
	path_width = _slider(CoursePath.MIN_WIDTH, CoursePath.MAX_WIDTH, 2.5)
	path_width.step = 0.5
	_option(box, "path_width", "Width", path_width)
	path_bridge = CheckBox.new()
	path_bridge.text = "Bridge"
	box.add_child(path_bridge)
	_option_rows["bridge"] = path_bridge
	help = Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(260, 0)
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(help)

	box.add_child(_section("Hole"))
	var row := HBoxContainer.new()
	holes = OptionButton.new()
	holes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holes.item_selected.connect(func(i: int) -> void:
		if not _quiet:
			hole_selected.emit(i))
	row.add_child(holes)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(func() -> void: hole_action.emit("add"))
	row.add_child(add)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func() -> void: hole_action.emit("delete"))
	row.add_child(del)
	box.add_child(row)
	var fly := Button.new()
	fly.text = "Fly over the hole"
	fly.pressed.connect(func() -> void: hole_action.emit("flyover"))
	box.add_child(fly)
	par = SpinBox.new()
	par.min_value = 3
	par.max_value = 6
	par.value_changed.connect(func(v: float) -> void:
		if not _quiet:
			par_changed.emit(int(v)))
	_option(box, "par", "Par", par)
	hole_info = Label.new()
	hole_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hole_info.add_theme_font_size_override("font_size", 14)
	box.add_child(hole_info)

	var keys := Label.new()
	keys.text = "Right drag: turn   Middle or Shift+right drag: pan   Wheel: zoom   WASD: move   Q/E: turn   T: top view   Ctrl+Z / Ctrl+Y: undo / redo"
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_font_size_override("font_size", 12)
	keys.modulate = Color(1, 1, 1, 0.6)
	box.add_child(keys)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.pressed.connect(func() -> void: file_action.emit("menu"))
	box.add_child(menu)
	select_tool(Tool.SELECT)


func select_tool(t: int) -> void:
	tool = t
	_tool_buttons[t].button_pressed = true
	help.text = TOOL_HELP[t]
	var brush := t in [Tool.RAISE, Tool.LOWER, Tool.SMOOTH, Tool.FLATTEN, Tool.TREES]
	_option_rows["surface"].visible = t in [Tool.SHAPE, Tool.SELECT]
	_option_rows["size"].visible = brush
	_option_rows["strength"].visible = brush
	_option_rows["trees"].visible = t == Tool.TREES
	_option_rows["tee"].visible = t == Tool.TEE
	for key in ["category", "objects", "turn", "random", "scale"]:
		_option_rows[key].visible = t == Tool.OBJECTS
	_option_rows["path_width"].visible = t == Tool.PATH
	_option_rows["bridge"].visible = t == Tool.PATH
	tool_changed.emit(t)


## The id of the object picked in the Objects list.
func chosen_object() -> String:
	var picked := object_list.get_selected_items()
	var i := picked[0] if not picked.is_empty() else 0
	return str(object_list.get_item_metadata(i)) if i < object_list.item_count else DesignerObjects.BUILT_IN[0][0]


func chosen_surface() -> int:
	return surface.get_selected_id()


## Shows `s` in the surface menu without reporting a change.
func show_surface(s: int) -> void:
	_quiet = true
	surface.select(surface.get_item_index(s))
	_quiet = false


func show_course_name(text: String) -> void:
	_quiet = true
	course_name.text = text
	_quiet = false


## The data credits a real course keeps (empty hides them).
## Offers the aerial photo toggle when the course has a photo.
func show_photo_option(available: bool, on: bool) -> void:
	_quiet = true
	photo.visible = available
	photo.button_pressed = on
	_quiet = false


func show_credits(text: String) -> void:
	credits.text = text
	credits.visible = not text.is_empty()


## Fills the hole list and shows hole `current`.
func show_holes(course: DesignedCourse, current: int) -> void:
	_quiet = true
	holes.clear()
	for i in course.holes.size():
		holes.add_item("Hole %d" % (i + 1))
	if current >= 0 and current < course.holes.size():
		holes.select(current)
		var h := course.holes[current]
		par.value = h.par
		var yards := roundi(h.length_m() * 1.0936)
		var text := "%d yards from the back tee." % yards
		if h.tees.is_empty():
			text = "No tee yet: use the Tee tool."
		elif h.par != DesignedHole.par_for_length(h.length_m()):
			text += " That length usually plays as a par %d." % DesignedHole.par_for_length(h.length_m())
		hole_info.text = text
	else:
		hole_info.text = "No holes yet: press Add."
	_quiet = false


func _build_objects(box: VBoxContainer) -> void:
	var cats := DesignerObjects.categories()
	object_category = OptionButton.new()
	for c: Dictionary in cats:
		object_category.add_item(str(c.name))
	object_category.item_selected.connect(func(i: int) -> void: _fill_objects(cats[i].items))
	_option(box, "category", "Group", object_category)
	object_list = ItemList.new()
	object_list.custom_minimum_size = Vector2(0, 150)
	box.add_child(object_list)
	_option_rows["objects"] = object_list
	_fill_objects(cats[0].items)
	object_turn = _slider(0.0, 355.0, 0.0)
	object_turn.step = 5.0
	_option(box, "turn", "Turn", object_turn)
	object_random = CheckBox.new()
	object_random.text = "Random turn and size"
	object_random.button_pressed = true
	box.add_child(object_random)
	_option_rows["random"] = object_random
	object_scale = _slider(0.5, 2.0, 1.0)
	object_scale.step = 0.05
	_option(box, "scale", "Size", object_scale)


func _fill_objects(items: Array) -> void:
	object_list.clear()
	for item: Array in items:
		object_list.add_item(str(item[1]))
		object_list.set_item_metadata(object_list.item_count - 1, item[0])
	if object_list.item_count > 0:
		object_list.select(0)


func _section(text: String) -> Label:
	var l := MenuStyle.heading(text, 18)
	return l


func _button_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for item: Array in items:
		var b := Button.new()
		b.text = item[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		var action: String = item[1]
		b.pressed.connect(func() -> void: file_action.emit(action))
		row.add_child(b)
	return row


func _slider(lo: float, hi: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0
	s.value = value
	s.custom_minimum_size = Vector2(150, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _option(box: VBoxContainer, key: String, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	box.add_child(row)
	_option_rows[key] = row
