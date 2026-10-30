class_name RoundScoring
extends RefCounted
## Everyone's cards for one round and what they mean in the chosen game mode:
## the status line, the standings and when the round is decided.

var mode: GameModes.Mode = GameModes.Mode.STROKE
var names: Array[String] = []
var teams: Array[int] = []
var cards: Array[Scorecard] = []
## Hole numbers as printed on the card (a back nine starts at 10).
var numbers: Array[int] = []


func _init(setup: RoundSetup, pars: Array[int], hole_numbers: Array[int]) -> void:
	mode = setup.mode
	names = setup.names.duplicate()
	teams = setup.teams.duplicate()
	numbers = hole_numbers.duplicate()
	for _n in names:
		cards.append(Scorecard.new(pars))


func player_count() -> int:
	return names.size()


func strokes_table() -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.strokes)
	return out


func team_members(team: int) -> Array[int]:
	var out: Array[int] = []
	for i in names.size():
		if teams[i] == team:
			out.append(i)
	return out


func team_name(team: int) -> String:
	var members: Array[String] = []
	for i in team_members(team):
		members.append(names[i])
	return " & ".join(members)


## Per-hole best ball for `team`.
func team_scores(team: int) -> Array[int]:
	var table: Array = []
	for i in team_members(team):
		table.append(cards[i].strokes)
	return GameModes.best_ball(table)


func team_card(team: int) -> Scorecard:
	var card := Scorecard.new(cards[0].pars)
	var best := team_scores(team)
	for h in best.size():
		card.record(h, best[h])
	return card


func match_status() -> Dictionary:
	if mode == GameModes.Mode.BEST_BALL:
		return GameModes.match_status(team_scores(0), team_scores(1))
	return GameModes.match_status(cards[0].strokes, cards[1].strokes)


## True once the result can't change: a match that is won early.
func decided() -> bool:
	return mode == GameModes.Mode.MATCH and match_status().finished


## One line for the HUD: who leads and by how much.
func status_text() -> String:
	match mode:
		GameModes.Mode.MATCH:
			var m := match_status()
			var text := GameModes.match_text(m)
			if m.up == 0:
				return "Match: " + text
			return "Match: %s %s" % [names[0] if m.up > 0 else names[1], text]
		GameModes.Mode.SKINS:
			var sk := GameModes.skins(strokes_table())
			var parts: Array[String] = []
			for i in names.size():
				parts.append("%s %d" % [names[i], sk.skins[i]])
			var text := "Skins: " + ", ".join(parts)
			if sk.carried > 0:
				text += "  (%d carried)" % sk.carried
			return text
		GameModes.Mode.BEST_BALL:
			return "Best ball: %s %s, %s %s" % [
				team_name(0), Scorecard.format_to_par(team_card(0).to_par()),
				team_name(1), Scorecard.format_to_par(team_card(1).to_par())]
		GameModes.Mode.STABLEFORD:
			var parts: Array[String] = []
			for i in names.size():
				parts.append("%s %d" % [names[i], GameModes.stableford_total(cards[i])])
			return "Points: " + ", ".join(parts)
	if names.size() == 1:
		return ""
	var parts: Array[String] = []
	for i in names.size():
		parts.append("%s %s" % [names[i], Scorecard.format_to_par(cards[i].to_par())])
	return "Leaders: " + ", ".join(parts)


## What happened on hole `h` in this mode, for the end-of-hole message.
func hole_result(h: int) -> String:
	match mode:
		GameModes.Mode.MATCH:
			var a := cards[0].strokes[h]
			var b := cards[1].strokes[h]
			if a == b:
				return "Hole halved."
			return "%s wins the hole." % (names[0] if a < b else names[1])
		GameModes.Mode.SKINS:
			var sk := GameModes.skins(strokes_table())
			var w: int = sk.hole_winner[h]
			if w >= 0:
				var won := 1
				var k := h - 1
				while k >= 0 and sk.hole_winner[k] == -1:
					won += 1
					k -= 1
				return "%s wins %s." % [names[w], "the skin" if won == 1 else "%d skins" % won]
			if w == -1:
				return "Tied: the skin carries over."
		GameModes.Mode.BEST_BALL:
			var a := team_scores(0)[h]
			var b := team_scores(1)[h]
			if a == b:
				return "Teams tie the hole with %d." % a
			return "%s win the hole, %d to %d." % [team_name(0) if a < b else team_name(1), mini(a, b), maxi(a, b)]
	return ""


## Final standings, best first: [[name, score text], ...].
func standings() -> Array:
	var rows: Array = []
	match mode:
		GameModes.Mode.MATCH:
			var m := match_status()
			var text := GameModes.match_text(m)
			if m.up == 0:
				return [["Match halved", text]]
			var won := 0 if m.up > 0 else 1
			return [[names[won] + " wins", text], [names[1 - won], ""]]
		GameModes.Mode.BEST_BALL:
			for t in 2:
				var card := team_card(t)
				rows.append([team_name(t), card.total_strokes(), "%d (%s)" % [card.total_strokes(), Scorecard.format_to_par(card.to_par())]])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		GameModes.Mode.SKINS:
			var sk := GameModes.skins(strokes_table())
			for i in names.size():
				rows.append([names[i], -sk.skins[i], "%d skin%s" % [sk.skins[i], "" if sk.skins[i] == 1 else "s"]])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		GameModes.Mode.STABLEFORD:
			for i in names.size():
				var pts := GameModes.stableford_total(cards[i])
				rows.append([names[i], -pts, "%d points" % pts])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		_:
			for i in names.size():
				var c := cards[i]
				rows.append([names[i], c.total_strokes(), "%d (%s)" % [c.total_strokes(), Scorecard.format_to_par(c.to_par())]])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
	var out: Array = []
	for r: Array in rows:
		out.append([r[0], r[2]])
	return out


## "Michael wins 3 & 2", "Sam wins with 4 skins", "Tied on 72".
func winner_text() -> String:
	var rows := standings()
	if rows.is_empty():
		return ""
	if mode == GameModes.Mode.MATCH:
		return ("%s %s" % rows[0]).strip_edges()
	if rows.size() == 1:
		return "%s: %s" % rows[0]
	if rows[0][1] == rows[1][1]:
		return "Tied at the top: %s and %s, %s" % [rows[0][0], rows[1][0], rows[0][1]]
	return "%s wins: %s" % rows[0]
