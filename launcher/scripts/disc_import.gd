extends RefCounted
## Gets the player's own Links 2003 files ready for the game, from whatever
## they have: the three disc images, the CDs in a drive (or mounted images),
## or an installed copy.
##
## An installed copy is used where it is. From discs, the GAME folder's
## files are copied into the launcher's library folder under the names
## Setup would give them (from the table in the first disc's SETUP.EXE, kept
## in the library for the other discs), as tools/cdimage/cdimage.py install
## does. Videos, programs and help files are skipped, the same choice as the
## web build (game/web/game_files.js). Nothing leaves the computer.

const DiscImage := preload("res://scripts/disc_image.gd")
const Paths := preload("res://scripts/paths.gd")

const NAMES_FILE := ".openlinks-names.json"
const DISCS_FILE := ".openlinks-discs.json"
const SKIP_EXT := ["wmv", "exe", "dll", "hlp", "cnt", "ini", "inf", "isu", "ico", "idb", "pdb", "sbr"]
const SKIP_NAMES := ["lessons.ls", "help.ls"]
## The course decoder reads its keys from the game's program.
const KEEP := ["linksm_1.exe", "linksmmiii.exe"]

## Progress, read by the UI while the copy runs on a thread.
var total := 0
var done := 0
var current := ""
var error := ""
var finished := false
var discs: PackedStringArray = []
var _mutex := Mutex.new()


static func wanted(rel: String) -> bool:
	var file := rel.get_file().to_lower()
	if KEEP.has(file):
		return true
	return not SKIP_EXT.has(file.get_extension()) and not SKIP_NAMES.has(file)


## What kind of Links 2003 folder `path` is: "install" (an installed or
## extracted copy, used in place), "disc" (a CD or a mounted image: its
## GAME folder is copied), or "" (neither).
static func folder_kind(path: String) -> String:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return ""
	var files := _lower(DirAccess.get_files_at(path))
	var dirs := _lower(DirAccess.get_directories_at(path))
	if files.has("object.lib") or dirs.has("courses") or files.has("linksmmiii.exe"):
		return "install"
	if dirs.has("game"):
		var game := _entry(path, "game", true)
		if _lower(DirAccess.get_directories_at(game)).has("courses"):
			return "disc"
		var inside := _lower(DirAccess.get_files_at(game))
		for f in inside:
			if f.ends_with(".ls") or f.ends_with(".lib") or f.ends_with(".crs") or f.ends_with(".crz"):
				return "disc"
		if files.has("setup.exe"):
			return "disc"
	return ""


## True when `path` holds what the game needs to start a real course.
static func library_ready(path: String) -> bool:
	return folder_kind(path) == "install"


## Courses (.crs/.crz/.cvt) in a Links 2003 folder.
static func count_courses(path: String) -> int:
	var dir := _entry(path, "courses", true)
	if dir.is_empty():
		var game := _entry(path, "game", true)
		if not game.is_empty():
			dir = _entry(game, "courses", true)
	if dir.is_empty():
		return 0
	var n := 0
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["crs", "crz", "cvt"]:
			n += 1
	return n


## Discs copied into the library so far ("1", "2", "3", or labels).
static func copied_discs(library := Paths.library_dir()) -> PackedStringArray:
	var f := FileAccess.open(library.path_join(DISCS_FILE), FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var data: Variant = JSON.parse_string(f.get_as_text())
	return PackedStringArray(data) if data is Array else PackedStringArray()


## The disc number in a volume label or folder name (2003DISK2 -> "2").
static func disc_number(label: String) -> String:
	var m := RegEx.create_from_string("(?i)dis[ck]\\s*_?(\\d)").search(label)
	return m.get_string(1) if m != null else ""


## Folders where a Links 2003 CD, a mounted image or an installed copy
## might be on this computer: [{path, kind, label}].
static func detect(plat := Paths.platform()) -> Array[Dictionary]:
	var places := PackedStringArray()
	var home := OS.get_environment("USERPROFILE" if plat == "windows" else "HOME")
	var user := OS.get_environment("USER")
	match plat:
		"macos":
			for v in DirAccess.get_directories_at("/Volumes"):
				places.append("/Volumes".path_join(v))
			places.append(home.path_join("Games/Links2003/prefix/drive_c/Program Files (x86)/Microsoft Games/Links 2003"))
			places.append(home.path_join("Games/Links2003/prefix-cx/drive_c/Program Files (x86)/Microsoft Games/Links 2003"))
		"windows":
			for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
				places.append(letter + ":/")
			for pf in ["C:/Program Files (x86)", "C:/Program Files"]:
				places.append(pf.path_join("Microsoft Games/Links 2003"))
		_:
			for root in ["/media/" + user, "/run/media/" + user, "/media", "/mnt"]:
				if DirAccess.dir_exists_absolute(root):
					for v in DirAccess.get_directories_at(root):
						places.append(root.path_join(v))
			places.append(home.path_join(".wine/drive_c/Program Files (x86)/Microsoft Games/Links 2003"))
			places.append(home.path_join(".wine/drive_c/Program Files/Microsoft Games/Links 2003"))
	var found: Array[Dictionary] = []
	for p in places:
		if plat == "windows" and p.length() == 3 and not DirAccess.dir_exists_absolute(p):
			continue
		var kind := folder_kind(p)
		if kind.is_empty():
			continue
		found.append({"path": p, "kind": kind, "label": p.trim_suffix("/").get_file()})
	return found


static func _lower(names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n in names:
		out.append(n.to_lower())
	return out


static func _entry(dir: String, entry: String, want_dir: bool) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for e in (DirAccess.get_directories_at(dir) if want_dir else DirAccess.get_files_at(dir)):
		if e.to_lower() == entry.to_lower():
			return dir.path_join(e)
	return ""


## Lists what to copy from `sources` (disc image files and disc folders):
## {entries: [{rel, size, image (DiscImage) or file (path), lba}], discs,
## names, unreadable: [...], descriptors: n}.
static func plan(sources: PackedStringArray, library := Paths.library_dir()) -> Dictionary:
	var images: Array = []
	var folders: PackedStringArray = []
	var unreadable := PackedStringArray()
	var descriptors := 0
	for s in sources:
		if DirAccess.dir_exists_absolute(s):
			folders.append(s)
		elif DiscImage.is_image(s):
			var d := DiscImage.new()
			if d.open(s):
				images.append(d)
			else:
				unreadable.append(s.get_file())
		elif DiscImage.is_descriptor(s):
			descriptors += 1
		else:
			unreadable.append(s.get_file())

	# Long names: from whichever disc has SETUP.EXE, else from an earlier copy.
	var names := {}
	var listings: Array = []
	for d: Variant in images:
		var list: Array[Dictionary] = d.files()
		listings.append(list)
		for e in list:
			if names.is_empty() and str(e.path).to_upper() == "/SETUP.EXE":
				names = DiscImage.long_names(d.read(e.lba, e.size))
	for f in folders:
		var setup := _entry(f, "setup.exe", false)
		if names.is_empty() and not setup.is_empty():
			names = DiscImage.long_names(FileAccess.get_file_as_bytes(setup))
	if names.is_empty():
		var saved := FileAccess.open(library.path_join(NAMES_FILE), FileAccess.READ)
		if saved != null:
			var data: Variant = JSON.parse_string(saved.get_as_text())
			if data is Dictionary:
				names = data

	var entries: Array[Dictionary] = []
	var discs := PackedStringArray()
	for i in images.size():
		var d: Variant = images[i]
		var n := disc_number(d.label())
		discs.append(n if not n.is_empty() else d.label())
		for e: Dictionary in listings[i]:
			var p := str(e.path)
			if not p.to_upper().begins_with("/GAME/"):
				continue
			var short := p.substr(6)
			var rel := str(names.get(short.to_upper(), short))
			if wanted(rel):
				entries.append({"rel": rel, "size": int(e.size), "image": d, "lba": int(e.lba)})
	for f in folders:
		var game := _entry(f, "game", true)
		if game.is_empty():
			continue
		var n := disc_number(f.trim_suffix("/").get_file())
		discs.append(n if not n.is_empty() else f.trim_suffix("/").get_file())
		for short in _walk_files(game, ""):
			var rel := str(names.get(short.to_upper(), short))
			if wanted(rel):
				var path := game.path_join(short)
				var fa := FileAccess.open(path, FileAccess.READ)
				var size := fa.get_length() if fa != null else 0
				entries.append({"rel": rel, "size": size, "file": path})
	return {"entries": entries, "discs": discs, "names": names, "unreadable": unreadable, "descriptors": descriptors}


static func _walk_files(dir: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir.path_join(prefix)):
		out.append(prefix.path_join(f) if not prefix.is_empty() else f)
	for d in DirAccess.get_directories_at(dir.path_join(prefix)):
		out.append_array(_walk_files(dir, prefix.path_join(d) if not prefix.is_empty() else d))
	return out


## Copies a plan's entries into `library` (run on a thread). Files already
## there at the right size are kept, so a stopped copy picks up where it was.
func copy(p: Dictionary, library := Paths.library_dir()) -> void:
	var entries: Array[Dictionary] = p.entries
	_mutex.lock()
	total = 0
	for e in entries:
		total += int(e.size)
	done = 0
	_mutex.unlock()
	DirAccess.make_dir_recursive_absolute(library)
	for e in entries:
		var dest := library.path_join(str(e.rel))
		_mutex.lock()
		current = str(e.rel).get_file()
		_mutex.unlock()
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var existing := FileAccess.open(dest, FileAccess.READ)
		if existing != null and existing.get_length() == int(e.size):
			existing = null
			_add(int(e.size))
			continue
		existing = null
		var ok := false
		if e.has("image"):
			ok = e.image.copy_to(int(e.lba), int(e.size), dest, _add)
		else:
			ok = _copy_file(str(e.file), dest)
		if not ok:
			_mutex.lock()
			error = "Couldn't copy %s. Is there enough free space?" % str(e.rel)
			finished = true
			_mutex.unlock()
			return
	if not (p.names as Dictionary).is_empty():
		var nf := FileAccess.open(library.path_join(NAMES_FILE), FileAccess.WRITE)
		if nf != null:
			nf.store_string(JSON.stringify(p.names))
	var all := copied_discs(library)
	for d in p.discs:
		if not all.has(d):
			all.append(d)
	all.sort()
	var df := FileAccess.open(library.path_join(DISCS_FILE), FileAccess.WRITE)
	if df != null:
		df.store_string(JSON.stringify(Array(all)))
	_mutex.lock()
	discs = all
	finished = true
	_mutex.unlock()


func _copy_file(src: String, dest: String) -> bool:
	var a := FileAccess.open(src, FileAccess.READ)
	var b := FileAccess.open(dest, FileAccess.WRITE)
	if a == null or b == null:
		return false
	while a.get_position() < a.get_length():
		var chunk := a.get_buffer(1 << 20)
		if chunk.is_empty():
			return false
		b.store_buffer(chunk)
		_add(chunk.size())
	return true


func _add(n: int) -> void:
	_mutex.lock()
	done += n
	_mutex.unlock()


## Stops with `message` (from the thread).
func fail(message: String) -> void:
	_mutex.lock()
	error = message
	finished = true
	_mutex.unlock()


## [done, total, current file, error, finished], read under the lock.
func snapshot() -> Array:
	_mutex.lock()
	var s := [done, total, current, error, finished]
	_mutex.unlock()
	return s
