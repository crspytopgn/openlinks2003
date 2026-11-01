extends RefCounted
## Unpacks a downloaded build and puts it in place of the installed one.
## Called on a worker thread (it reads and writes hundreds of MB).
##
## The archive is checked against GitHub's SHA-256 digest, unpacked into
## game/staging, and only then swapped with game/current, so a failed update
## leaves the old build playable.

const Paths := preload("res://scripts/paths.gd")


## SHA-256 of a file, as lower-case hex.
static func sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


## Unpacks `archive` (.zip or .tar.gz) into `dest`. "" on success, else why not.
static func extract(archive: String, dest: String, plat := Paths.platform()) -> String:
	Paths.remove_tree(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	var out := []
	if archive.ends_with(".tar.gz") or archive.ends_with(".tgz"):
		if OS.execute("tar", ["-xzf", archive, "-C", dest], out, true) == 0:
			return ""
		return "Couldn't unpack the download: " + "".join(out).strip_edges()
	if plat == "macos":
		# ditto keeps the app's permissions and code signature intact.
		if OS.execute("/usr/bin/ditto", ["-x", "-k", archive, dest], out, true) == 0:
			return ""
	elif plat == "windows":
		# Windows 10 and later have bsdtar, which reads zips quickly.
		if OS.execute("tar", ["-xf", archive, "-C", dest], out, true) == 0:
			return ""
	else:
		if OS.execute("unzip", ["-q", "-o", archive, "-d", dest], out, true) == 0:
			return ""
	Paths.remove_tree(dest)
	DirAccess.make_dir_recursive_absolute(dest)
	return unzip(archive, dest)


## Unpacks a zip with Godot's own reader. Programs inside get execute
## permission on macOS and Linux.
static func unzip(archive: String, dest: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		return "The download isn't a zip file."
	for name in zip.get_files():
		if name.contains("..") or name.begins_with("/"):
			continue
		var target := dest.path_join(name)
		if name.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "Couldn't write " + target
		f.store_buffer(zip.read_file(name))
		f.close()
		if name.contains(".app/Contents/MacOS/") or name.ends_with(".x86_64") or name.ends_with(".sh"):
			FileAccess.set_unix_permissions(target, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER
				| FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP | FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER)
	zip.close()
	return ""


## Checks, unpacks and installs `archive` as the build `release` describes
## (ReleaseFeed.parse_release). "" on success, else why not.
static func install(archive: String, release: Dictionary, plat := Paths.platform()) -> String:
	var digest := str(release.get("digest", ""))
	if not digest.is_empty() and sha256_file(archive) != digest.to_lower():
		DirAccess.remove_absolute(archive)
		return "The download was damaged on the way. Try again."
	var root := Paths.game_root()
	var staging := root.path_join("staging")
	var why := extract(archive, staging, plat)
	if not why.is_empty():
		return why
	if Paths.game_executable(staging, plat).is_empty():
		Paths.remove_tree(staging)
		return "The download doesn't contain the game."
	if plat == "macos":
		# Downloaded by the launcher itself, so not quarantined, but an app
		# copied over from elsewhere might be.
		OS.execute("/usr/bin/xattr", ["-dr", "com.apple.quarantine", Paths.find_app(staging)], [], true)
	var current := Paths.game_dir()
	var previous := root.path_join("previous")
	Paths.remove_tree(previous)
	if DirAccess.dir_exists_absolute(current) and DirAccess.rename_absolute(current, previous) != OK:
		Paths.remove_tree(staging)
		return "Couldn't replace the installed game. Is it still running?"
	if DirAccess.rename_absolute(staging, current) != OK:
		DirAccess.rename_absolute(previous, current)
		return "Couldn't put the new build in place."
	Paths.remove_tree(previous)
	DirAccess.remove_absolute(archive)
	write_installed(release)
	return ""


static func write_installed(release: Dictionary) -> void:
	var f := FileAccess.open(Paths.installed_file(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"commit": release.get("commit", ""),
			"published": release.get("published", ""),
			"size": release.get("size", 0),
			"installed_at": Time.get_datetime_string_from_system(true),
		}, "\t"))


## What's installed: {commit, published, ...}, or {} when nothing is.
static func installed() -> Dictionary:
	if Paths.game_executable().is_empty():
		return {}
	var f := FileAccess.open(Paths.installed_file(), FileAccess.READ)
	if f == null:
		return {"commit": ""}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {"commit": ""}
