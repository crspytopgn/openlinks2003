class_name PlayerProfiles
extends RefCounted
## Player profiles, matched by name: each player's finished rounds and the
## handicap index they give (Handicap), plus career stats (fairways, greens
## in regulation, putts). A player with fewer than three rounds can set a
## starting index instead. Each player's golfer (PlayerLook, from the player
## creator) is kept too. Saved in user://profiles.cfg, one section per
## player.

## Where the profiles are kept; the tests point this somewhere else.
static var path := "user://profiles.cfg"

## Rounds kept per player; the index only uses the most recent 20.
const KEEP_ROUNDS := 40
## The fewest holes a round needs to count towards a handicap.
const MIN_HOLES := 9

## A round's stats, counted hole by hole in the round: holes, fairways hit
## out of fairway_holes (par 4s and 5s), greens in regulation, putts.
const STATS := ["holes", "fairways", "fairway_holes", "gir", "putts"]

var _cfg := ConfigFile.new()


static func empty_stats() -> Dictionary:
	var out := {}
	for key: String in STATS:
		out[key] = 0
	return out


static func load_saved() -> PlayerProfiles:
	var p := PlayerProfiles.new()
	p._cfg.load(path)
	return p


func save() -> void:
	_cfg.save(path)


static func _section(player_name: String) -> String:
	return "player " + player_name.strip_edges().to_lower().uri_encode()


func has_player(player_name: String) -> bool:
	return _cfg.has_section(_section(player_name))


## Every saved player's name, in the order they were added.
func names() -> Array[String]:
	var out: Array[String] = []
	for s in _cfg.get_sections():
		if s.begins_with("player "):
			out.append(_cfg.get_value(s, "name", ""))
	return out


## Finished rounds, oldest first: [{date, course, holes, gross, adjusted,
## par, differential}, ...]. Differentials are in tenths.
func rounds(player_name: String) -> Array:
	return _cfg.get_value(_section(player_name), "rounds", [])


func differentials(player_name: String) -> Array[int]:
	var out: Array[int] = []
	for r: Dictionary in rounds(player_name):
		out.append(int(r.get("differential", 0)))
	return out


## True once the player's own rounds set the index (three or more).
func has_record(player_name: String) -> bool:
	return Handicap.index(differentials(player_name)) != Handicap.NONE


## The index from the player's rounds, or their starting index until they
## have three, or Handicap.NONE.
func index_of(player_name: String) -> int:
	var from_rounds := Handicap.index(differentials(player_name))
	if from_rounds != Handicap.NONE:
		return from_rounds
	return int(_cfg.get_value(_section(player_name), "start_index", Handicap.NONE))


## Sets the index a new player starts from (Handicap.NONE clears it).
func set_start_index(player_name: String, tenths: int) -> void:
	var s := _section(player_name)
	_cfg.set_value(s, "name", player_name.strip_edges())
	_cfg.set_value(s, "start_index", tenths)


## Adds a finished round to the player's record. `ranks` are the hole ranks
## (Handicap.stroke_ranks) and `date` is "YYYY-MM-DD". Returns false, and
## records nothing, if the round is too short or not finished.
func record_round(player_name: String, card: Scorecard, ranks: Array[int], course_name: String, date: String, stats := {}) -> bool:
	var holes := card.pars.size()
	if holes < MIN_HOLES or card.holes_played() < holes:
		return false
	var index := index_of(player_name)
	var received := Handicap.strokes(Handicap.playing_handicap(index, holes, 100), ranks)
	var adjusted := Handicap.adjusted_gross(card, received, index != Handicap.NONE)
	var par := card.total_par()
	var played := rounds(player_name).duplicate()
	var entry := {
		"date": date, "course": course_name, "holes": holes, "gross": card.total_strokes(),
		"adjusted": adjusted, "par": par, "differential": Handicap.score_differential(adjusted, par, holes),
	}
	var with_stats := int(stats.get("holes", 0)) == holes
	if with_stats:
		for key: String in STATS:
			entry[key] = int(stats.get(key, 0))
	played.append(entry)
	# Career totals keep counting after old rounds drop off the list.
	var c := career(player_name)
	c.rounds += 1
	c.holes += holes
	c.strokes += card.total_strokes()
	c.par += par
	if with_stats:
		c.stat_holes += holes
		for key: String in ["fairways", "fairway_holes", "gir", "putts"]:
			c[key] += int(stats.get(key, 0))
	var s := _section(player_name)
	_cfg.set_value(s, "name", player_name.strip_edges())
	_cfg.set_value(s, "rounds", played.slice(maxi(0, played.size() - KEEP_ROUNDS)))
	_cfg.set_value(s, "career", c)
	return true


## Career totals: {rounds, holes, strokes, par, stat_holes (holes with
## stats), fairways, fairway_holes, gir, putts}.
func career(player_name: String) -> Dictionary:
	var out := {"rounds": 0, "holes": 0, "strokes": 0, "par": 0, "stat_holes": 0,
		"fairways": 0, "fairway_holes": 0, "gir": 0, "putts": 0}
	var s := _section(player_name)
	if not _cfg.has_section_key(s, "career"):
		# Profiles from before career stats: start from the rounds on record.
		for r: Dictionary in rounds(player_name):
			out.rounds += 1
			out.holes += int(r.get("holes", 0))
			out.strokes += int(r.get("gross", 0))
			out.par += int(r.get("par", 0))
		return out
	var saved: Dictionary = _cfg.get_value(s, "career", {})
	for key: String in out:
		out[key] = int(saved.get(key, 0))
	return out


## "Average 84.3 per 18   Fairways 52%   Greens 33%   Putts 31.5 per 18", or
## "" before the first round.
static func career_text(c: Dictionary) -> String:
	if int(c.rounds) == 0 or int(c.holes) == 0:
		return ""
	var parts: Array[String] = ["Average %.1f per 18" % (18.0 * c.strokes / c.holes)]
	if int(c.fairway_holes) > 0:
		parts.append("Fairways %d%%" % roundi(100.0 * c.fairways / c.fairway_holes))
	if int(c.stat_holes) > 0:
		parts.append("Greens %d%%" % roundi(100.0 * c.gir / c.stat_holes))
		parts.append("Putts %.1f per 18" % (18.0 * c.putts / c.stat_holes))
	return "   ".join(parts)


## The player's golfer from the player creator, or null if they haven't
## made one.
func look_of(player_name: String) -> PlayerLook:
	var saved: Variant = _cfg.get_value(_section(player_name), "look", null)
	return PlayerLook.from_dict(saved) if saved is Dictionary else null


## Saves the player's golfer; adds the player if they are new.
func set_look(player_name: String, look: PlayerLook) -> void:
	var s := _section(player_name)
	_cfg.set_value(s, "name", player_name.strip_edges())
	_cfg.set_value(s, "look", look.to_dict())


## Renames a player, keeping their rounds, stats and golfer. False if the
## new name is empty or taken.
func rename(old_name: String, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or not has_player(old_name):
		return false
	if _section(new_name) == _section(old_name):
		_cfg.set_value(_section(old_name), "name", new_name)
		return true
	if has_player(new_name):
		return false
	var from := _section(old_name)
	var to := _section(new_name)
	for key in _cfg.get_section_keys(from):
		_cfg.set_value(to, key, _cfg.get_value(from, key))
	_cfg.set_value(to, "name", new_name)
	_cfg.erase_section(from)
	return true


func remove(player_name: String) -> void:
	if has_player(player_name):
		_cfg.erase_section(_section(player_name))
