extends SceneTree
## Launcher tests, headless and offline:
##   godot --headless --path launcher -s res://tests/run_tests.gd
## Prints "LAUNCHER TESTS PASSED" when every check holds.

const Paths := preload("res://scripts/paths.gd")
const ReleaseFeed := preload("res://scripts/release_feed.gd")
const Installer := preload("res://scripts/installer.gd")
const DiscImage := preload("res://scripts/disc_image.gd")
const DiscImport := preload("res://scripts/disc_import.gd")
const GameConfig := preload("res://scripts/game_config.gd")

var _failures := 0
var _checks := 0
var _tmp := ""


func _initialize() -> void:
	_tmp = OS.get_cache_dir().path_join("openlinks-launcher-tests-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_tmp)
	OS.set_environment("OL_LAUNCHER_DATA", _tmp.path_join("data"))
	OS.set_environment("OL_GAME_USER_DIR", _tmp.path_join("game_user"))
	_test_release()
	_test_changelog()
	_test_paths()
	_test_disc_image()
	_test_import()
	_test_game_config()
	_test_installer()
	Paths.remove_tree(_tmp)
	if _failures == 0:
		print("LAUNCHER TESTS PASSED (%d checks)" % _checks)
		quit(0)
	else:
		print("LAUNCHER TESTS FAILED: %d of %d checks" % [_failures, _checks])
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: " + what)


func _test_release() -> void:
	var json := {
		"target_commitish": "82a49a2f5c89955e4afdbb2f9066da7c922d9190",
		"name": "Latest build (82a49a2)",
		"published_at": "2026-11-01T13:23:21Z",
		"html_url": "https://github.com/crspytopgn/openlinks2003/releases/tag/latest",
		"assets": [
			{"name": "OpenLinks2003-Linux.tar.gz", "size": 61283934, "browser_download_url": "https://example.invalid/l.tgz", "digest": "sha256:a3733c4b"},
			{"name": "OpenLinks2003-macOS.zip", "size": 93642452, "browser_download_url": "https://example.invalid/m.zip", "digest": "sha256:6cf014b0"},
		],
	}
	var r := ReleaseFeed.parse_release(json, "OpenLinks2003-macOS.zip")
	_check(r.commit == "82a49a2f5c89955e4afdbb2f9066da7c922d9190" and r.size == 93642452, "release: commit and size")
	_check(r.digest == "6cf014b0" and r.url == "https://example.invalid/m.zip", "release: digest without its prefix, and the URL")
	_check(ReleaseFeed.parse_release(json, "OpenLinks2003-Windows.zip").is_empty(), "release: a missing download is empty")
	_check(ReleaseFeed.parse_release(null, "x").is_empty(), "release: no answer is empty")
	var contents := [{"name": "game", "type": "dir", "sha": "g1"}, {"name": "launcher", "type": "dir", "sha": "t1"}]
	_check(ReleaseFeed.launcher_tree(contents) == "t1" and ReleaseFeed.launcher_tree({}) == "", "release: the launcher's tree id on main")
	_check(Paths.game_asset("linux") == "OpenLinks2003-Linux.tar.gz" and Paths.game_asset("windows") == "OpenLinks2003-Windows.zip", "release: asset names")


func _test_changelog() -> void:
	var squash := "Golfer's clubs modelled to real sizes (#164)\n\n* Course props modelled from real photos (#150)\n\nlong text\n\nCo-Authored-By: Claude\n\n* Fairway yardage plates\n\n* Golfer's clubs modelled to real sizes\n\n---------\n\nCo-authored-by: Claude"
	var e := ReleaseFeed.parse_message(squash)
	_check(e.title == "Golfer's clubs modelled to real sizes" and e.pr == 164, "changelog: squash title and PR")
	_check(e.points == PackedStringArray(["Course props modelled from real photos", "Fairway yardage plates"]), "changelog: squashed commits become points, without the title or PR numbers (%s)" % [e.points])
	var plain := ReleaseFeed.parse_message("Refit the colour grade (#154) (#165)\n\nAfternoon, midday and morning lookups,\nrefitted on fresh renders.\n\nSecond paragraph.\n\nClaude-Session: x")
	_check(plain.pr == 165 and plain.title == "Refit the colour grade", "changelog: the squash PR is the last number")
	_check(plain.summary == "Afternoon, midday and morning lookups, refitted on fresh renders.", "changelog: first paragraph as the summary (%s)" % plain.summary)
	var merge := ReleaseFeed.parse_message("Merge pull request #12 from someone/branch\n\nAdd the course viewer")
	_check(merge.pr == 12 and merge.title == "Add the course viewer", "changelog: merge commits use the PR title")
	_check(ReleaseFeed.parse_message("Merge branch 'main' into x").is_empty(), "changelog: merges of main are left out")
	var long := ReleaseFeed.parse_message("T\n\n" + "word ".repeat(100))
	_check(long.summary.length() <= ReleaseFeed.MAX_SUMMARY + 3 and long.summary.ends_with("..."), "changelog: long summaries are cut")
	var commits := [
		{"sha": "ccc", "commit": {"message": "Third (#3)", "committer": {"date": "2026-11-01T12:00:00Z"}}},
		{"sha": "bbb", "commit": {"message": "Second (#2)", "committer": {"date": "2026-10-31T12:00:00Z"}}},
		{"sha": "aaa", "commit": {"message": "First (#1)", "committer": {"date": "2026-10-20T12:00:00Z"}}},
	]
	var entries := ReleaseFeed.parse_commits(commits)
	_check(entries.size() == 3 and entries[0].sha == "ccc" and entries[2].pr == 1, "changelog: entries in order")
	_check(ReleaseFeed.count_new(entries, "bbb") == 1 and ReleaseFeed.count_new(entries, "ccc") == 0, "changelog: changes since the installed build")
	_check(ReleaseFeed.count_new(entries, "zzz") == 3 and ReleaseFeed.count_new(entries, "") == 0, "changelog: unknown builds see everything, none installed sees nothing new")
	var now := Time.get_unix_time_from_datetime_string("2026-11-01T13:00:00Z")
	_check(ReleaseFeed.relative_date("2026-11-01T12:58:00Z", now) == "2 min ago", "date: minutes")
	_check(ReleaseFeed.relative_date("2026-11-01T10:00:00Z", now) == "3 h ago", "date: hours")
	_check(ReleaseFeed.relative_date("2026-10-31T10:00:00Z", now) == "Yesterday", "date: yesterday")
	_check(ReleaseFeed.relative_date("2026-10-12T10:00:00Z", now) == "12 Oct", "date: day and month")


func _test_paths() -> void:
	OS.set_environment("OL_GAME_USER_DIR", "")
	_check(Paths.game_user_dir("linux").ends_with("godot/app_userdata/OpenLinks2003"), "paths: the game's settings folder on Linux")
	_check(Paths.game_user_dir("windows").ends_with("Godot/app_userdata/OpenLinks2003"), "paths: on Windows and macOS")
	OS.set_environment("OL_GAME_USER_DIR", _tmp.path_join("game_user"))
	_check(Paths.size_text(93642452) == "94 MB" and Paths.size_text(1400000000) == "1.4 GB", "paths: sizes")


# ---- A small ISO 9660 image, built here ----------------------------------------

## A directory record for `name` at `lba` with `size` bytes.
static func _record(name: PackedByteArray, lba: int, size: int, dir: bool) -> PackedByteArray:
	var n := name.size()
	var length := 33 + n + (1 if n % 2 == 0 else 0)
	var r := PackedByteArray()
	r.resize(length)
	r[0] = length
	r.encode_u32(2, lba)
	r.encode_u32(10, size)
	r[25] = 2 if dir else 0
	r[32] = n
	for i in n:
		r[33 + i] = name[i]
	return r


static func _sector(data: PackedByteArray) -> PackedByteArray:
	var s := data.duplicate()
	s.resize(2048)
	return s


## A cooked image: label `label`, SETUP.EXE (holding a Setup-style name
## table) at the root, and GAME/ with OBJECT.LIB, COURSES/KAURI_1.CRZ and
## INTRO.WMV.
static func _iso(label: String) -> Dictionary:
	var setup := PackedByteArray([0x4d, 0x5a, 0, 0])
	for pair in [["game\\COURSES\\KAURI_1.CRZ", "Courses\\Kauri Cliffs.crz"], ["game\\OBJECT.LIB", "Object.lib"]]:
		setup.append_array(PackedByteArray([0x50, 0, 0, 0, 40, 0]))
		setup.append_array((pair[0] as String).to_ascii_buffer())
		setup.append(0)
		setup.append_array((pair[1] as String).to_ascii_buffer())
		setup.append(0)
	var object_lib := "OBJECTS".repeat(400).to_ascii_buffer()  # 2800 bytes: two sectors
	var course := "COURSE".to_ascii_buffer()
	var video := "VIDEO".to_ascii_buffer()
	# Sectors: 16 PVD, 17 terminator, 18 root, 19 GAME, 20 COURSES,
	# 21 SETUP.EXE, 22-23 OBJECT.LIB, 24 the course, 25 the video.
	var root := PackedByteArray()
	root.append_array(_record(PackedByteArray([0]), 18, 2048, true))
	root.append_array(_record(PackedByteArray([1]), 18, 2048, true))
	root.append_array(_record("GAME".to_ascii_buffer(), 19, 2048, true))
	root.append_array(_record("SETUP.EXE;1".to_ascii_buffer(), 21, setup.size(), false))
	var game := PackedByteArray()
	game.append_array(_record(PackedByteArray([0]), 19, 2048, true))
	game.append_array(_record(PackedByteArray([1]), 18, 2048, true))
	game.append_array(_record("COURSES".to_ascii_buffer(), 20, 2048, true))
	game.append_array(_record("INTRO.WMV;1".to_ascii_buffer(), 25, video.size(), false))
	game.append_array(_record("OBJECT.LIB;1".to_ascii_buffer(), 22, object_lib.size(), false))
	var courses := PackedByteArray()
	courses.append_array(_record(PackedByteArray([0]), 20, 2048, true))
	courses.append_array(_record(PackedByteArray([1]), 19, 2048, true))
	courses.append_array(_record("KAURI_1.CRZ;1".to_ascii_buffer(), 24, course.size(), false))
	var pvd := PackedByteArray()
	pvd.resize(2048)
	pvd[0] = 1
	for i in 5:
		pvd[1 + i] = "CD001".unicode_at(i)
	pvd[6] = 1
	var lab := label.to_ascii_buffer()
	for i in 32:
		pvd[40 + i] = lab[i] if i < lab.size() else 0x20
	var root_rec := _record(PackedByteArray([0]), 18, 2048, true)
	for i in 34:
		pvd[156 + i] = root_rec[i]
	var term := PackedByteArray([255, 0x43, 0x44, 0x30, 0x30, 0x31, 1])
	var img := PackedByteArray()
	img.resize(16 * 2048)
	img.append_array(pvd)
	img.append_array(_sector(term))
	img.append_array(_sector(root))
	img.append_array(_sector(game))
	img.append_array(_sector(courses))
	img.append_array(_sector(setup))
	var obj := object_lib.duplicate()
	obj.resize(4096)
	img.append_array(obj)
	img.append_array(_sector(course))
	img.append_array(_sector(video))
	return {"image": img, "object_lib": object_lib, "course": course}


## The same image as raw Mode 1 sectors (2352 bytes) after a 150-sector
## pregap, as BlindWrite .b6i images are.
static func _raw(cooked: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(150 * 2352)
	for s in cooked.size() / 2048:
		var sec := PackedByteArray()
		sec.resize(2352)
		sec[15] = 1
		for i in 2048:
			sec[16 + i] = cooked[s * 2048 + i]
		out.append_array(sec)
	return out


static func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _test_disc_image() -> void:
	var made := _iso("2003DISK1")
	var cooked := _tmp.path_join("disc1.iso")
	var raw := _tmp.path_join("disc1.b6i")
	_write(cooked, made.image)
	_write(raw, _raw(made.image))
	for path in [cooked, raw]:
		var d := DiscImage.new()
		_check(d.open(path), "disc image: opens " + path.get_file())
		_check(d.label() == "2003DISK1", "disc image: label of " + path.get_file())
		var files := d.files()
		var by_path := {}
		for f in files:
			by_path[f.path] = f
		_check(by_path.has("/SETUP.EXE") and by_path.has("/GAME/OBJECT.LIB") and by_path.has("/GAME/COURSES/KAURI_1.CRZ"), "disc image: walks the folders of " + path.get_file())
		var lib: Dictionary = by_path.get("/GAME/OBJECT.LIB", {})
		_check(not lib.is_empty() and d.read(lib.lba, lib.size) == made.object_lib, "disc image: reads a file across sectors from " + path.get_file())
		_check(not lib.is_empty() and d.read(lib.lba, 10, 2045) == (made.object_lib as PackedByteArray).slice(2045, 2055), "disc image: reads from an offset across a sector edge")
	_check(d_layout(raw) == [2352, 16, 150], "disc image: raw Mode 1 with a pregap")
	# An image with a header in front, found by scanning.
	var odd := PackedByteArray()
	odd.resize(1000)
	odd.append_array(made.image)
	var odd_path := _tmp.path_join("odd.img")
	_write(odd_path, odd)
	var o := DiscImage.new()
	_check(o.open(odd_path) and o.base == 1000 and o.files().size() == 4, "disc image: finds a volume behind an image header")
	var names := DiscImage.long_names(FileAccess.get_file_as_bytes(_tmp.path_join("disc1.iso")).slice(21 * 2048, 22 * 2048))
	_check(names.get("COURSES/KAURI_1.CRZ", "") == "Courses/Kauri Cliffs.crz" and names.get("OBJECT.LIB", "") == "Object.lib", "disc image: Setup's long names (%s)" % [names])
	_check(DiscImage.is_image("A.B6I") and DiscImage.is_descriptor("a.b6t") and not DiscImage.is_image("a.b6t"), "disc image: image and descriptor names")


func d_layout(path: String) -> Array:
	var d := DiscImage.new()
	d.open(path)
	return [d.sector_size, d.header, d.pregap]


func _test_import() -> void:
	var library := _tmp.path_join("library")
	var p := DiscImport.plan(PackedStringArray([_tmp.path_join("disc1.b6i")]), library)
	var rels := PackedStringArray()
	for e: Dictionary in p.entries:
		rels.append(e.rel)
	rels.sort()
	_check(rels == PackedStringArray(["Courses/Kauri Cliffs.crz", "Object.lib"]), "import: long names, videos left out (%s)" % [rels])
	_check(p.discs == PackedStringArray(["1"]), "import: the disc number from the label")
	var job := DiscImport.new()
	job.copy(p, library)
	var s := job.snapshot()
	_check(s[4] and str(s[3]).is_empty() and s[0] == s[1], "import: copy finishes")
	_check(FileAccess.get_file_as_bytes(library.path_join("Object.lib")).size() == 2800, "import: a copied file is whole")
	_check(DiscImport.folder_kind(library) == "install" and DiscImport.count_courses(library) == 1, "import: the library is a usable game folder")
	_check(DiscImport.copied_discs(library) == PackedStringArray(["1"]), "import: copied discs are remembered")
	# A second disc without SETUP.EXE takes the names saved from the first.
	var made := _iso("2003DISK2")
	var img: PackedByteArray = made.image
	for i in 2048:
		img[21 * 2048 + i] = 0  # a SETUP.EXE with no name table
	_write(_tmp.path_join("disc2.iso"), img)
	var p2 := DiscImport.plan(PackedStringArray([_tmp.path_join("disc2.iso")]), library)
	var rels2 := PackedStringArray()
	for e: Dictionary in p2.entries:
		rels2.append(e.rel)
	_check(rels2.has("Courses/Kauri Cliffs.crz"), "import: later discs use the saved long names")
	var job2 := DiscImport.new()
	job2.copy(p2, library)
	_check(DiscImport.copied_discs(library) == PackedStringArray(["1", "2"]), "import: both discs remembered")
	# A CD (or mounted image) as a folder.
	var cd := _tmp.path_join("cd")
	DirAccess.make_dir_recursive_absolute(cd.path_join("GAME/COURSES"))
	_write(cd.path_join("SETUP.EXE"), FileAccess.get_file_as_bytes(_tmp.path_join("disc1.iso")).slice(21 * 2048, 22 * 2048))
	_write(cd.path_join("GAME/OBJECT.LIB"), "x".to_ascii_buffer())
	_write(cd.path_join("GAME/COURSES/KAURI_1.CRZ"), "y".to_ascii_buffer())
	_check(DiscImport.folder_kind(cd) == "disc", "import: a CD folder is a disc")
	var p3 := DiscImport.plan(PackedStringArray([cd]), _tmp.path_join("library2"))
	var rels3 := PackedStringArray()
	for e: Dictionary in p3.entries:
		rels3.append(e.rel)
	rels3.sort()
	_check(rels3 == PackedStringArray(["Courses/Kauri Cliffs.crz", "Object.lib"]), "import: CD folders get long names too (%s)" % [rels3])
	_check(DiscImport.disc_number("2003DISK3") == "3" and DiscImport.disc_number("Links Disc 2") == "2", "import: disc numbers")
	_check(not DiscImport.wanted("Intro.wmv") and DiscImport.wanted("LINKSM_1.EXE") and not DiscImport.wanted("help.ls"), "import: what is copied")
	var bad := DiscImport.plan(PackedStringArray([_tmp.path_join("nothing.iso")]), library)
	_check((bad.entries as Array).is_empty() and (bad.unreadable as PackedStringArray).size() == 1, "import: unreadable images are reported")


func _test_game_config() -> void:
	var path := _tmp.path_join("settings.cfg")
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "look", 0)
	cfg.set_value("graphics", "quality", 3)
	cfg.set_value("round", "course", "keep me")
	cfg.save(path)
	var c := GameConfig.load_from(path) as GameConfig
	_check(c.shown_look() == 0 and c.shown_quality() == 3, "settings: the game's look and quality")
	c.choose_look(4)
	_check(c.shown_quality() == 0, "settings: a look brings its quality")
	c.choose_quality(2)
	c.set_display_choice(2)
	c.window_size = Vector2i(1920, 1080)
	c.master = 40
	c.swing_method = 0
	c.folder = "/games/links"
	_check(c.save_to(path) == OK, "settings: saved")
	cfg = ConfigFile.new()
	cfg.load(path)
	_check(cfg.get_value("launcher", "look") == 4 and cfg.get_value("launcher", "quality") == 2, "settings: look and quality left for the game")
	_check(cfg.get_value("graphics", "look") == 0, "settings: the game's own look is left alone")
	_check(cfg.get_value("graphics", "fullscreen") == true and cfg.get_value("graphics", "display_mode") == 1, "settings: exclusive fullscreen")
	_check(cfg.get_value("graphics", "window_width") == 1920 and cfg.get_value("audio", "master") == 40, "settings: window size and volume")
	_check(cfg.get_value("game", "folder") == "/games/links" and cfg.get_value("round", "course") == "keep me", "settings: game folder set, other sections kept")
	var again := GameConfig.load_from(path) as GameConfig
	_check(again.display_choice() == 2 and again.shown_look() == 4 and again.shown_quality() == 2 and again.swing_method == 0, "settings: read back")


func _test_installer() -> void:
	var data := Paths.data_dir()
	DirAccess.make_dir_recursive_absolute(data)
	# A zip as the Windows build is published.
	var zip_path := _tmp.path_join("OpenLinks2003-Windows.zip")
	var zp := ZIPPacker.new()
	zp.open(zip_path)
	zp.start_file("OpenLinks2003.exe")
	zp.write_file("MZ fake".to_ascii_buffer())
	zp.close_file()
	zp.close()
	var unpacked := _tmp.path_join("unzipped")
	_check(Installer.unzip(zip_path, unpacked).is_empty() and FileAccess.file_exists(unpacked.path_join("OpenLinks2003.exe")), "installer: Godot's own unzip")
	var release := {"commit": "abc1234def", "published": "2026-11-01T13:00:00Z", "size": 7, "digest": Installer.sha256_file(zip_path)}
	_check(Installer.install(zip_path, release, "windows").is_empty(), "installer: installs a checked download")
	_check(not Paths.game_executable(Paths.game_dir(), "windows").is_empty(), "installer: the game is in place")
	var inst := Installer.installed()
	_check(not OS.has_feature("windows") or inst.get("commit", "") == "abc1234def", "installer: remembers the build")
	# A damaged download is refused and the installed build is kept.
	var zip2 := _tmp.path_join("again.zip")
	DirAccess.copy_absolute(unpacked.path_join("OpenLinks2003.exe"), zip2)
	var why := Installer.install(zip2, {"commit": "new", "digest": "00"}, "windows")
	_check(not why.is_empty() and not Paths.game_executable(Paths.game_dir(), "windows").is_empty(), "installer: a bad checksum keeps the old build")
	if OS.has_feature("linuxbsd"):
		# The Linux build as a .tar.gz, unpacked with tar.
		var src := _tmp.path_join("tarsrc")
		DirAccess.make_dir_recursive_absolute(src)
		_write(src.path_join("OpenLinks2003.x86_64"), "ELF".to_ascii_buffer())
		var tgz := _tmp.path_join("OpenLinks2003-Linux.tar.gz")
		OS.execute("tar", ["-czf", tgz, "-C", src, "."])
		_check(Installer.install(tgz, {"commit": "linux1"}, "linux").is_empty(), "installer: installs a .tar.gz")
		_check(Paths.game_executable(Paths.game_dir(), "linux").ends_with("OpenLinks2003.x86_64"), "installer: the Linux build is in place")
		_check(Installer.installed().get("commit", "") == "linux1", "installer: remembers the Linux build")
		_check(not DirAccess.dir_exists_absolute(Paths.game_root().path_join("previous")) and not DirAccess.dir_exists_absolute(Paths.game_root().path_join("staging")), "installer: cleans up")
