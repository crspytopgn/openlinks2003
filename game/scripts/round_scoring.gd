class_name RoundScoring
extends RefCounted
## Everyone's cards for one round and what they mean in the chosen game mode:
## the status line, the standings and when the round is decided. With
## handicaps on, the net scores decide every mode.

var mode: GameModes.Mode = GameModes.Mode.STROKE
var names: Array[String] = []
var teams: Array[int] = []
var cards: Array[Scorecard] = []
## Hole numbers as printed on the card (a back nine starts at 10).
var numbers: Array[int] = []
var handicaps := false
## Each player's index (tenths) and playing handicap for this round.
var indexes: Array[int] = []
var playing: Array[int] = []
## Hole ranks (Handicap.stroke_ranks) and each player's strokes per hole.
var ranks: Array[int] = []
var received: Array = []


## `stroke_index` is the course's stroke index for each hole in play.
func _init(setup: RoundSetup, pars: Array[int], hole_numbers: Array[int], stroke_index: Array[int] = []) -> void:
	mode = setup.mode
	names = setup.names.duplicate()
	teams = setup.teams.duplicate()
	numbers = hole_numbers.duplicate()
	handicaps = setup.handicaps
	var si: Array[int] = []
	for h in pars.size():
		si.append(stroke_index[h] if h < stroke_index.size() else 0)
	ranks = Handicap.stroke_ranks(si)
	for i in names.size():
		cards.append(Scorecard.new(pars))
		indexes.append(setup.index_of(i))
		playing.append(Handicap.playing_handicap(indexes[i], pars.size(), GameModes.allowance_percent(mode)) if handicaps else 0)
	if handicaps and GameModes.off_the_low(mode) and not playing.is_empty():
		var low: int = playing.min()
		for i in playing.size():
			playing[i] -= low
	for i in names.size():
		received.append(Handicap.strokes(playing[i], ranks))


## Per-hole scores that count in the game: net with handicaps, else gross.
func scores(player: int) -> Array[int]:
	if not handicaps:
		return cards[player].strokes
	return Handicap.net_scores(cards[player].strokes, received[player])


## The card that counts in the game: the net card with handicaps.
func scored_card(player: int) -> Scorecard:
	if not handicaps:
		return cards[player]
	var card := Scorecard.new(cards[player].pars)
	var net := scores(player)
	for h in net.size():
		card.record(h, net[h])
	return card


## "Ann" or, with handicaps, "Ann (12)".
func label(player: int) -> String:
	if not handicaps:
		return names[player]
	var p := playing[player]
	return "%s (%s)" % [names[player], ("+%d" % -p) if p < 0 else str(p)]


func player_count() -> int:
	return names.size()


## Everyone's scores that count (net with handicaps).
func strokes_table() -> Array:
	var out: Array = []
	for i in cards.size():
		out.append(scores(i))
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
		table.append(scores(i))
	return GameModes.best_ball(table)


func team_card(team: int) -> Scorecard:
	var card := Scorecard.new(cards[0].pars)
	var best := team_scores(team)
	for h in best.size():
		card.record(h, best[h])
	return card


func match_status() -> Dictionary:
	if GameModes.is_team(mode):
		return GameModes.match_status(team_scores(0), team_scores(1))
	return GameModes.match_status(scores(0), scores(1))


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
		GameModes.Mode.BEST_BALL, GameModes.Mode.SCRAMBLE, GameModes.Mode.ALTERNATE_SHOT:
			return "%s: %s %s, %s %s" % [GameModes.MODE_NAMES[mode],
				team_name(0), Scorecard.format_to_par(team_card(0).to_par()),
				team_name(1), Scorecard.format_to_par(team_card(1).to_par())]
		GameModes.Mode.STABLEFORD:
			var parts: Array[String] = []
			for i in names.size():
				parts.append("%s %d" % [names[i], GameModes.stableford_total(scored_card(i))])
			return "Points: " + ", ".join(parts)
	if names.size() == 1:
		return ""
	var parts: Array[String] = []
	for i in names.size():
		parts.append("%s %s" % [names[i], Scorecard.format_to_par(scored_card(i).to_par())])
	return ("Net: " if handicaps else "Leaders: ") + ", ".join(parts)


## What happened on hole `h` in this mode, for the end-of-hole message.
func hole_result(h: int) -> String:
	match mode:
		GameModes.Mode.MATCH:
			var a := scores(0)[h]
			var b := scores(1)[h]
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
		GameModes.Mode.BEST_BALL, GameModes.Mode.SCRAMBLE, GameModes.Mode.ALTERNATE_SHOT:
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
		GameModes.Mode.BEST_BALL, GameModes.Mode.SCRAMBLE, GameModes.Mode.ALTERNATE_SHOT:
			for t in 2:
				var card := team_card(t)
				rows.append([team_name(t), card.total_strokes(), "%s%d (%s)" % ["net " if handicaps else "", card.total_strokes(), Scorecard.format_to_par(card.to_par())]])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		GameModes.Mode.SKINS:
			var sk := GameModes.skins(strokes_table())
			for i in names.size():
				rows.append([names[i], -sk.skins[i], "%d skin%s" % [sk.skins[i], "" if sk.skins[i] == 1 else "s"]])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		GameModes.Mode.STABLEFORD:
			for i in names.size():
				var pts := GameModes.stableford_total(scored_card(i))
				rows.append([names[i], -pts, "%d points" % pts])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
		_:
			for i in names.size():
				var c := scored_card(i)
				var text := "%d (%s)" % [c.total_strokes(), Scorecard.format_to_par(c.to_par())]
				if handicaps:
					text = "net " + text
				rows.append([names[i], c.total_strokes(), text])
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
		var tied: Array[String] = []
		for r: Array in rows:
			if r[1] == rows[0][1]:
				tied.append(str(r[0]))
		var who := ", ".join(tied.slice(0, tied.size() - 1)) + " and " + tied[-1]
		return "Tied at the top: %s, %s" % [who, rows[0][1]]
	# A team ("Ann & Cy") wins as a plural.
	return "%s %s: %s" % [rows[0][0], "win" if GameModes.is_team(mode) else "wins", rows[0][1]]
