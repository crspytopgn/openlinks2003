class_name LinksGolferAssets
extends GolferAssets
## Golfers from the player's POLYANI folder. Picks the archive named by
## "golfer" in [game] of user://settings.cfg (for example ERIC.L3), or the
## first golfer archive found.

var _archive_path := ""


## Null if no game folder is configured or it has no golfer archives.
static func from_game_folder() -> LinksGolferAssets:
	var wanted := GameFolder.setting("golfer").to_upper()
	var chosen := ""
	for path in GameFolder.list_files("POLYANI"):
		var file := path.get_file().to_upper()
		if file.get_extension() != "L3" or file == "CLUBS.L3":
			continue
		if chosen.is_empty() or file == wanted:
			chosen = path
	if chosen.is_empty():
		return null
	var assets := LinksGolferAssets.new()
	assets._archive_path = chosen
	return assets


func create_golfer() -> GolferRig:
	var golfer := LinksGolfer.load_from(_archive_path)
	if golfer == null:
		push_warning("Could not read golfer %s; using the placeholder" % _archive_path)
		return PlaceholderGolfer.new()
	return golfer
