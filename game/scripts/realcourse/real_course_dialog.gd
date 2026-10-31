class_name RealCourseDialog
extends ConfirmationDialog
## The course designer's "Real course" window: type a club's name, pick the
## right place from the matches, and RealCourseFetcher builds it from
## OpenStreetMap and open elevation data.

signal status(text: String)
signal built(course: DesignedCourse, summary: Dictionary)

var fetcher: RealCourseFetcher
var query: LineEdit
var results: ItemList
var note: Label
var _places: Array = []


func _ready() -> void:
	title = "Build a real course"
	ok_button_text = "Build course"
	get_ok_button().disabled = true
	fetcher = RealCourseFetcher.new()
	add_child(fetcher)
	fetcher.found.connect(_on_found)
	fetcher.progress.connect(func(t: String) -> void: status.emit(t))
	fetcher.failed.connect(func(t: String) -> void: status.emit(t))
	fetcher.built.connect(func(c: DesignedCourse, s: Dictionary) -> void: built.emit(c, s))

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 340)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var intro := Label.new()
	intro.text = "Type a golf club or course anywhere in the world. Its holes, greens, bunkers and water come from OpenStreetMap; its ground from national lidar where it is open (England, the Netherlands, France, the US), else open elevation data; and its trees from the lidar or the country's aerial photos."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	var row := HBoxContainer.new()
	box.add_child(row)
	query = LineEdit.new()
	query.placeholder_text = "e.g. St Andrews Old Course, Pebble Beach Golf Links"
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_submitted.connect(func(_t: String) -> void: _search())
	row.add_child(query)
	var find := Button.new()
	find.text = "Search"
	find.pressed.connect(_search)
	row.add_child(find)
	results = ItemList.new()
	results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results.item_selected.connect(func(_i: int) -> void: get_ok_button().disabled = fetcher.busy)
	results.item_activated.connect(func(_i: int) -> void:
		hide()
		_on_build())
	box.add_child(results)
	note = Label.new()
	note.text = "Map data (c) OpenStreetMap contributors (ODbL). Courses are only as complete as their map: check the holes in the designer after building."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(note)
	confirmed.connect(_on_build)


func open() -> void:
	popup_centered()
	query.grab_focus()


func _search() -> void:
	var q := query.text.strip_edges()
	if q.length() < 3 or fetcher.busy:
		return
	results.clear()
	_places.clear()
	get_ok_button().disabled = true
	results.add_item("Searching...")
	results.set_item_disabled(0, true)
	fetcher.search(q)


func _on_found(found: Array) -> void:
	results.clear()
	_places = found
	for p: Dictionary in found:
		results.add_item(("[golf course]  " if p["golf"] else "") + str(p["label"]))
	if found.is_empty():
		results.add_item("Nothing found. Try the club's full name and its town.")
		results.set_item_disabled(0, true)
	elif found[0]["golf"]:
		results.select(0)
		get_ok_button().disabled = false


func _on_build() -> void:
	var picked := results.get_selected_items()
	if picked.is_empty() or picked[0] >= _places.size() or fetcher.busy:
		return
	fetcher.build(_places[picked[0]])
