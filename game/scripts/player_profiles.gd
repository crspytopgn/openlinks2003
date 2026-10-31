class_name PlayerProfiles
extends RefCounted
## Player profiles, matched by name: each player's finished rounds and the
## handicap index they give (Handicap). A player with fewer than three rounds
## can set a starting index instead. Saved in user://profiles.cfg, one
## section per player.

## Where the profiles are kept; the tests point this somewhere else.
static var path := "user://profiles.cfg"

## Rounds kept per player; the index only uses the most recent 20.
const KEEP_ROUNDS := 40
## The fewest holes a round needs to count towards a handicap.
const MIN_HOLES := 9

var _cfg := ConfigFile.new()


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
func record_round(player_name: String, card: Scorecard, ranks: Array[int], course_name: String, date: String) -> bool:
	var holes := card.pars.size()
	if holes < MIN_HOLES or card.holes_played() < holes:
		return false
	var index := index_of(player_name)
	var received := Handicap.strokes(Handicap.playing_handicap(index, holes, 100), ranks)
	var adjusted := Handicap.adjusted_gross(card, received, index != Handicap.NONE)
	var par := card.total_par()
	var played := rounds(player_name).duplicate()
	played.append({
		"date": date, "course": course_name, "holes": holes, "gross": card.total_strokes(),
		"adjusted": adjusted, "par": par, "differential": Handicap.score_differential(adjusted, par, holes),
	})
	var s := _section(player_name)
	_cfg.set_value(s, "name", player_name.strip_edges())
	_cfg.set_value(s, "rounds", played.slice(maxi(0, played.size() - KEEP_ROUNDS)))
	return true


func remove(player_name: String) -> void:
	if has_player(player_name):
		_cfg.erase_section(_section(player_name))
