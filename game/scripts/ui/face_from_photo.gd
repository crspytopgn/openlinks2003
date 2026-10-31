class_name FaceFromPhoto
extends VBoxContainer
## The player creator's Photo tab: the golfer's face, skin and hair colour
## from a photo of the player (PlayerFaceFit). In the browser the face is
## found automatically (WebFacePhoto); on desktop the player taps a few
## points on it. Either way the points can be dragged to fix them, and the
## photo never leaves the device: it is only held while the tab is open.

## Emitted with the fitted face sliders (PlayerFaceFit.FITTED key -> value)
## and the skin and hair colours (transparent when not taken).
signal fitted(face: Dictionary, skin: Color, hair: Color)

const VIEW_HEIGHT := 340.0
const PHOTO_MAX := 1024

var _web: WebFacePhoto
var _view: PhotoView
var _status: Label
var _use: Button
var _again: Button
var _skin: CheckBox
var _hair: CheckBox
var _dialog: FileDialog


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var note := Label.new()
	note.text = ("Make the golfer's face from a photo of yours: looking straight at the camera, in even light, "
		+ "without glasses if you can. The photo stays on this device. It isn't uploaded or saved.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.75)
	add_child(note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	add_child(buttons)
	var choose := MenuStyle.button("Choose a photo")
	choose.pressed.connect(_choose.bind(false))
	buttons.add_child(choose)
	if WebFacePhoto.is_supported():
		var camera := MenuStyle.button("Take a selfie")
		camera.tooltip_text = "On a phone or tablet this opens the front camera."
		camera.pressed.connect(_choose.bind(true))
		buttons.add_child(camera)
	_view = PhotoView.new()
	_view.custom_minimum_size = Vector2(0, VIEW_HEIGHT)
	_view.points_changed.connect(_on_points_changed)
	# The last tap fits the face straight away.
	_view.placed.connect(func() -> void:
		if _view.points.size() == PlayerFaceFit.POINTS.size():
			_apply())
	add_child(_view)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var options := HFlowContainer.new()
	add_child(options)
	_skin = CheckBox.new()
	_skin.text = "Skin colour from the photo"
	_skin.button_pressed = true
	options.add_child(_skin)
	_hair = CheckBox.new()
	_hair.text = "Hair colour from the photo"
	options.add_child(_hair)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	_use = MenuStyle.button("Use this face")
	_use.disabled = true
	_use.pressed.connect(_apply)
	actions.add_child(_use)
	_again = MenuStyle.button("Tap the points again")
	_again.disabled = true
	_again.pressed.connect(func() -> void:
		_view.set_points(PackedVector2Array())
		_on_points_changed())
	actions.add_child(_again)
	if GolferParts.shared() == null or not GolferParts.shared().info.has("face_fit"):
		choose.disabled = true
		_status.text = "This build's golfer has no face points, so a photo can't be used."
	else:
		_status.text = "Choose a photo to start."


## Drops the photo (when the creator closes).
func clear() -> void:
	_view.set_photo(null)
	_use.disabled = true
	_again.disabled = true
	if _web != null:
		_web.forget()
	_status.text = "Choose a photo to start."


func _choose(camera: bool) -> void:
	if WebFacePhoto.is_supported():
		if _web == null:
			_web = WebFacePhoto.new()
		var img: Image = await _web.pick(camera)
		if img == null:
			if not _web.last_error.is_empty():
				_status.text = "That photo didn't work (%s)." % _web.last_error
			return
		_show(img)
		_status.text = "Looking for your face… (the first time, the face finder downloads, about 4 MB)"
		var marks: PackedVector2Array = await _web.find_face()
		var points := PlayerFaceFit.from_mediapipe(marks)
		if points.is_empty():
			_status.text = ("Couldn't find a face%s. Try a clearer photo, or tap the points yourself: %s"
				% ["" if _web.last_error.is_empty() else " (%s)" % _web.last_error, _next_label()])
			return
		_view.set_points(points)
		_on_points_changed()
		_apply()
		return
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.filters = PackedStringArray(["*.jpg, *.jpeg, *.png, *.webp ; Photos"])
		_dialog.title = "Choose a photo of your face"
		_dialog.file_selected.connect(_load_file)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.7)


func _load_file(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "That file couldn't be read as a photo."
		return
	_show(img)
	_on_points_changed()


func _show(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var longest := maxi(img.get_width(), img.get_height())
	if longest > PHOTO_MAX:
		var s := float(PHOTO_MAX) / longest
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_BILINEAR)
	_view.set_photo(img)
	_view.set_points(PackedVector2Array())


func _next_label() -> String:
	var n := _view.points.size()
	if n >= PlayerFaceFit.POINTS.size():
		return ""
	return "%d of %d: %s." % [n + 1, PlayerFaceFit.POINTS.size(), PlayerFaceFit.POINT_LABELS[n]]


func _on_points_changed() -> void:
	var done := _view.points.size() == PlayerFaceFit.POINTS.size()
	_use.disabled = not done
	_again.disabled = _view.photo == null
	if _view.photo == null:
		return
	if done:
		_status.text = "Drag any point that's off, then Use this face. Scroll to zoom; right-drag to move the photo."
	else:
		_status.text = "Tap %s Scroll to zoom; right-drag to move the photo." % _next_label()


func _apply() -> void:
	var img := _view.photo
	var pts := _view.points
	if img == null or pts.size() != PlayerFaceFit.POINTS.size():
		return
	var creator := _creator_look()
	var face := PlayerFaceFit.fit(GolferParts.shared().info.face_fit, creator, PlayerFaceFit.from_image(pts))
	if face.is_empty():
		_status.text = "Those points don't make a face: check the eyes and mouth."
		return
	var skin := _tint(PlayerFaceFit.skin_colour(img, pts)) if _skin.button_pressed else Color.TRANSPARENT
	var hair := _tint(PlayerFaceFit.hair_colour(img, pts)) if _hair.button_pressed else Color.TRANSPARENT
	fitted.emit(face, skin, hair)
	_status.text = "Done. Fine-tune it on the Face tab, or drag a point and Use this face again."


## A colour seen in the photo as a tint: the golfer's skin and hair
## textures are grey detail averaging detail_mean, multiplied by the tint.
static func _tint(c: Color) -> Color:
	if c.a == 0.0:
		return c
	var mean := float(GolferParts.shared().info.get("detail_mean", 0.85))
	return Color(minf(c.r / mean, 1.0), minf(c.g / mean, 1.0), minf(c.b / mean, 1.0))


## The look being edited, for its body (the fit keeps it).
func _creator_look() -> PlayerLook:
	var node := get_parent()
	while node != null and not node is PlayerCreator:
		node = node.get_parent()
	return (node as PlayerCreator).look if node != null else PlayerLook.new()


## The photo with the face points: tap to place the next point, drag one
## to move it, scroll to zoom and right-drag to pan.
class PhotoView:
	extends Control

	signal points_changed
	## A point was tapped in (not dragged).
	signal placed

	const GRAB := 16.0
	const COLOUR := Color(1.0, 0.85, 0.2)
	const NEXT_COLOUR := Color(0.3, 0.9, 1.0)

	var photo: Image
	var points := PackedVector2Array()
	var _texture: ImageTexture
	var _zoom := 1.0
	var _pan := Vector2.ZERO
	var _dragging := -1
	var _panning := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func set_photo(img: Image) -> void:
		photo = img
		_texture = ImageTexture.create_from_image(img) if img != null else null
		_zoom = 1.0
		_pan = Vector2.ZERO
		points = PackedVector2Array()
		queue_redraw()

	func set_points(p: PackedVector2Array) -> void:
		points = p
		queue_redraw()

	## Photo pixels per view pixel at zoom 1, and the photo's top-left.
	func _fit() -> Array:
		var s := minf(size.x / photo.get_width(), size.y / photo.get_height())
		var origin := (size - Vector2(photo.get_width(), photo.get_height()) * s) * 0.5
		return [s, origin]

	func _to_view(p: Vector2) -> Vector2:
		var f := _fit()
		return (f[1] as Vector2) + _pan + p * float(f[0]) * _zoom

	func _to_photo(v: Vector2) -> Vector2:
		var f := _fit()
		return (v - (f[1] as Vector2) - _pan) / (float(f[0]) * _zoom)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		if photo == null:
			return
		var f := _fit()
		var s := float(f[0]) * _zoom
		draw_texture_rect(_texture, Rect2((f[1] as Vector2) + _pan, Vector2(photo.get_width(), photo.get_height()) * s), false)
		for i in points.size():
			var v := _to_view(points[i])
			draw_circle(v, 4.0, Color(0, 0, 0, 0.6))
			draw_circle(v, 2.5, COLOUR)
		if points.size() < PlayerFaceFit.POINTS.size():
			draw_string(get_theme_default_font(), Vector2(8, size.y - 8), "Next: %d of %d" % [points.size() + 1, PlayerFaceFit.POINTS.size()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, NEXT_COLOUR)

	func _gui_input(event: InputEvent) -> void:
		if photo == null:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var at := _to_photo(mb.position)
					_zoom = clampf(_zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 1.0, 8.0)
					_pan += mb.position - _to_view(at)
					if is_equal_approx(_zoom, 1.0):
						_pan = Vector2.ZERO
					queue_redraw()
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = _nearest(mb.position)
					if _dragging < 0 and points.size() < PlayerFaceFit.POINTS.size():
						points.append(_to_photo(mb.position))
						points_changed.emit()
						placed.emit()
						queue_redraw()
				else:
					if _dragging >= 0:
						points_changed.emit()
					_dragging = -1
				accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _panning:
				_pan += mm.relative
				queue_redraw()
			elif _dragging >= 0:
				points[_dragging] = _to_photo(mm.position)
				queue_redraw()

	func _nearest(v: Vector2) -> int:
		var best := -1
		var best_d := GRAB
		for i in points.size():
			var d := _to_view(points[i]).distance_to(v)
			if d < best_d:
				best_d = d
				best = i
		return best
