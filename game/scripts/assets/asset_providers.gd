class_name AssetProviders
extends RefCounted
## The one place where decoded original data replaces placeholders. Each
## decoder registers its implementation here at startup; anything left unset
## falls back to the placeholder.

static var course_loaders: Array[CourseLoader] = []
static var object_library: ObjectLibrary
static var golfer_assets: GolferAssets
static var shot_model: ShotModel
## Builds the sound bank node; set it to use decoded audio.
static var sound_bank_factory: Callable


## Later registrations win, so a real decoder takes priority over the
## placeholder course for paths both accept.
static func register_course_loader(loader: CourseLoader) -> void:
	course_loaders.push_front(loader)


static func ensure_defaults() -> void:
	if course_loaders.is_empty():
		course_loaders.append(PlaceholderCourseLoader.new())
	var has_crz := false
	for loader in course_loaders:
		has_crz = has_crz or loader is CrzCourseLoader
	if not has_crz:
		# Real courses (.CRZ / .RNG) from the player's own files.
		course_loaders.push_front(CrzCourseLoader.new())
	if object_library == null:
		object_library = _default_object_library()
	if golfer_assets == null:
		golfer_assets = LinksGolferAssets.from_game_folder()
	if golfer_assets == null:
		golfer_assets = PlaceholderGolferAssets.new()
	if shot_model == null:
		# The game's own ball flight when the player's executable is there.
		shot_model = LinksShotModel.from_game_folder()
	if shot_model == null:
		shot_model = StandardShotModel.new()


## Loads a course with the first loader that accepts the path; an empty path
## gives the placeholder course.
static func load_course(path: String) -> CourseData:
	ensure_defaults()
	for loader in course_loaders:
		if loader.can_load(path):
			var course := loader.load_course(path)
			if course != null:
				return course
	if not path.is_empty():
		push_warning("No loader could read %s; using the placeholder course" % path)
	return PlaceholderCourseLoader.new().load_course("")


static func create_sound_bank() -> SoundBank:
	if sound_bank_factory.is_valid():
		return sound_bank_factory.call()
	var links := LinksSoundBank.from_game_folder()
	if links != null:
		return links
	return PlaceholderSoundBank.new()


## The player's real objects when a game folder is set up, with the
## placeholder trees standing in for anything the folder lacks.
static func _default_object_library() -> ObjectLibrary:
	var placeholder := PlaceholderObjectLibrary.new()
	var folder := GameFolder.configured_path()
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return placeholder
	var real := DecodedObjectLibrary.open(folder)
	if real == null:
		return placeholder
	return ObjectLibraryChain.new(real, placeholder, ObjectLibraryChain.tree_aliases(real))
