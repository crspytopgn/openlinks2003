class_name DesignerFiles
extends Node
## Moves designed courses in and out of the game: in the browser, a download
## and the browser's file picker; on desktop, the file dialog. Emits imported
## with the file's text.

signal imported(text: String, file_name: String)

var _js_callback: JavaScriptObject


## Offers `text` as a download (browser) or asks where to save it (desktop).
func export_text(text: String, file_name: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, "application/json")
		return
	var dlg := _dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export the course")
	dlg.current_file = file_name
	dlg.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close())


## Asks for a course file; emits imported when one is chosen.
func import_file() -> void:
	if OS.has_feature("web"):
		_js_callback = JavaScriptBridge.create_callback(_on_js_file)
		var window: Variant = JavaScriptBridge.get_interface("window")
		window.olcImported = _js_callback
		JavaScriptBridge.eval("""(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.olc,.json,application/json';
			input.onchange = function () {
				var f = input.files[0];
				if (f) { f.text().then(function (t) { window.olcImported(t, f.name); }); }
			};
			input.click();
		})();""", true)
		return
	var dlg := _dialog(FileDialog.FILE_MODE_OPEN_FILE, "Import a course")
	dlg.file_selected.connect(func(path: String) -> void:
		imported.emit(FileAccess.get_file_as_string(path), path.get_file()))


func _on_js_file(args: Array) -> void:
	if args.size() >= 2:
		imported.emit(str(args[0]), str(args[1]))


func _dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dlg := FileDialog.new()
	dlg.file_mode = mode
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = title
	dlg.filters = PackedStringArray(["*.%s ; OpenLinks course" % DesignedCourse.EXTENSION])
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)
	return dlg
