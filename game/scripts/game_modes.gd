class_name GameModes
extends RefCounted
## Scoring for the game modes. Mirrors the game-mode functions in
## libs/olcore/src/scoring.cpp; change both together. Hole scores are
## per-hole strokes as on a Scorecard: 0 means not played.

enum Mode { STROKE, MATCH, SKINS, BEST_BALL, STABLEFORD, SCRAMBLE, ALTERNATE_SHOT }

const MODE_NAMES := ["Stroke play", "Match play", "Skins", "Best ball", "Stableford", "Scramble", "Alternate shot"]
const MODE_HELP := [
	"Lowest total wins. 1 to 4 players.",
	"Two players, hole by hole: the lower score wins the hole. The match ends once one player can't be caught.",
	"Every hole is worth a skin, won by the outright lowest score. Ties carry the skin to the next hole. 2 to 4 players.",
	"Two teams. Each hole, the team counts its best score; lowest team total wins. 3 or 4 players.",
	"Points per hole: 2 for par, 1 more for each stroke under, 1 fewer for each over. Most points wins. 1 to 4 players.",
	"Two teams. Everyone on the team hits, the team plays on from the best shot, and every round of shots counts one stroke. Lowest team total wins. 2 to 4 players.",
	"Two teams, one ball each. Partners take turns hitting it and take turns on the tee. Lowest team total wins. 2 to 4 players.",
]


## How much of each handicap counts in `mode`, in percent (the World Handicap
## System's recommended allowances). Game-side only: not in scoring.cpp.
static func allowance_percent(mode: Mode) -> int:
	match mode:
		Mode.MATCH, Mode.SKINS:
			return 100
		Mode.BEST_BALL:
			return 90
		Mode.SCRAMBLE:
			return 25
		Mode.ALTERNATE_SHOT:
			return 50
	return 95


## True if `mode` plays off the lowest handicap: the best player gets no
## strokes and the others get the difference.
static func off_the_low(mode: Mode) -> bool:
	return mode == Mode.MATCH or mode == Mode.SKINS or is_team(mode)


## Two teams play against each other (best ball and the shared-ball modes).
static func is_team(mode: Mode) -> bool:
	return mode == Mode.BEST_BALL or shared_ball(mode)


## Each team plays one ball: scramble and alternate shot. Every member's card
## then carries the team's score.
static func shared_ball(mode: Mode) -> bool:
	return mode == Mode.SCRAMBLE or mode == Mode.ALTERNATE_SHOT


## Players allowed in `mode`: [min, max].
static func player_range(mode: Mode) -> Vector2i:
	match mode:
		Mode.MATCH:
			return Vector2i(2, 2)
		Mode.SKINS:
			return Vector2i(2, 4)
		Mode.BEST_BALL:
			return Vector2i(3, 4)
		Mode.SCRAMBLE, Mode.ALTERNATE_SHOT:
			return Vector2i(2, 4)
	return Vector2i(1, 4)


static func stableford_points(hole_strokes: int, par: int) -> int:
	if hole_strokes <= 0:
		return 0
	return maxi(0, 2 + par - hole_strokes)


static func stableford_total(card: Scorecard) -> int:
	var total := 0
	for i in card.strokes.size():
		total += stableford_points(card.strokes[i], card.pars[i])
	return total


## The team's lowest score on each hole, from the players who have played
## it; 0 where none has.
static func best_ball(team_strokes: Array) -> Array[int]:
	var holes := 0
	for card: Array in team_strokes:
		holes = maxi(holes, card.size())
	var best: Array[int] = []
	best.resize(holes)
	best.fill(0)
	for card: Array in team_strokes:
		for h in card.size():
			if card[h] > 0 and (best[h] == 0 or card[h] < best[h]):
				best[h] = card[h]
	return best


## {skins: per player, hole_winner: per hole (player, -1 tied, -2 not
## complete), carried: skins riding on the next hole}.
static func skins(strokes: Array) -> Dictionary:
	var won: Array[int] = []
	won.resize(strokes.size())
	won.fill(0)
	var holes: int = 0 if strokes.is_empty() else (strokes[0] as Array).size()
	var winners: Array[int] = []
	winners.resize(holes)
	winners.fill(-2)
	var pot := 0
	for h in holes:
		var low := 0
		var winner := -1
		var complete := true
		for p in strokes.size():
			var card: Array = strokes[p]
			var s: int = card[h] if h < card.size() else 0
			if s <= 0:
				complete = false
				break
			if low == 0 or s < low:
				low = s
				winner = p
			elif s == low:
				winner = -1
		if not complete:
			break
		pot += 1
		winners[h] = winner
		if winner >= 0:
			won[winner] += pot
			pot = 0
	return {"skins": won, "hole_winner": winners, "carried": pot}


## Match play from side A's point of view: {up (negative: B is up), played,
## remaining, finished, dormie}.
static func match_status(a: Array[int], b: Array[int]) -> Dictionary:
	var holes := mini(a.size(), b.size())
	var up := 0
	var played := 0
	for h in holes:
		if a[h] <= 0 or b[h] <= 0:
			break
		if a[h] < b[h]:
			up += 1
		elif b[h] < a[h]:
			up -= 1
		played += 1
		if absi(up) > holes - h - 1:
			break
	var remaining := holes - played
	var finished := absi(up) > remaining or remaining == 0
	return {
		"up": up, "played": played, "remaining": remaining, "finished": finished,
		"dormie": not finished and up != 0 and absi(up) == remaining,
	}


## "All square", "2 up", "2 up (dormie)", "3 & 2", "1 up", "Halved".
static func match_text(status: Dictionary) -> String:
	var lead := absi(status.up)
	if lead == 0:
		return "Halved" if status.finished else "All square"
	if status.finished and status.remaining > 0:
		return "%d & %d" % [lead, status.remaining]
	var text := "%d up" % lead
	return text + " (dormie)" if status.dormie else text
