class_name Handicap
extends RefCounted
## Handicaps: a simplified World Handicap System. Mirrors the handicap
## functions in libs/olcore/src/scoring.cpp; change both together.
##
## Links courses carry a stroke index per hole but no course or slope rating,
## so par stands in for the course rating and every course has the standard
## slope (113). Indexes and differentials are in tenths of a stroke (123 is
## 12.3), so both sides round the same way.

const NONE := -1000
const MAX_TENTHS := 540
const MIN_TENTHS := -100
const ROUNDS := 20


## a / b rounded to the nearest whole number, halves away from zero. b > 0.
static func div_round(a: int, b: int) -> int:
	if a >= 0:
		return (a + b / 2) / b
	return -((-a + b / 2) / b)


## The holes in play ranked by difficulty, 1 for the hardest: by the course's
## stroke index, so a nine keeps the order of the 18. Holes without one (0)
## rank after the rest, in hole order.
static func stroke_ranks(stroke_index: Array[int]) -> Array[int]:
	var order: Array[int] = []
	for i in stroke_index.size():
		order.append(i)
	var key := func(i: int) -> int: return stroke_index[i] if stroke_index[i] > 0 else 1000
	# Insertion sort: stable, and the lists are at most 18 long.
	for i in range(1, order.size()):
		var v := order[i]
		var j := i - 1
		while j >= 0 and key.call(order[j]) > key.call(v):
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = v
	var ranks: Array[int] = []
	ranks.resize(stroke_index.size())
	for r in order.size():
		ranks[order[r]] = r + 1
	return ranks


## Strokes a playing handicap gets on each hole, from the hole ranks. A plus
## handicap (negative) gives strokes back, on the easiest holes first.
static func strokes(handicap: int, ranks: Array[int]) -> Array[int]:
	var n := ranks.size()
	var out: Array[int] = []
	out.resize(n)
	out.fill(0)
	if n == 0:
		return out
	var h := absi(handicap)
	for i in n:
		if handicap >= 0:
			out[i] = h / n + (1 if ranks[i] <= h % n else 0)
		else:
			out[i] = -(h / n + (1 if ranks[i] > n - h % n else 0))
	return out


## Gross minus the strokes received on each played hole, never below 1; 0
## where the hole isn't played.
static func net_scores(gross: Array[int], received: Array[int]) -> Array[int]:
	var out: Array[int] = []
	out.resize(gross.size())
	out.fill(0)
	for i in gross.size():
		if gross[i] > 0:
			var r: int = received[i] if i < received.size() else 0
			out[i] = maxi(1, gross[i] - r)
	return out


## Playing handicap for `holes` holes at `allowance_percent` of the index.
static func playing_handicap(index_tenths: int, holes: int, allowance_percent: int) -> int:
	if index_tenths == NONE:
		return 0
	return div_round(index_tenths * holes * allowance_percent, 18 * 100 * 10)


## Each hole capped at net double bogey (par + 2 + strokes received);
## without an index, at par + 5.
static func adjusted_gross(card: Scorecard, received: Array[int], has_index: bool) -> int:
	var total := 0
	for i in card.strokes.size():
		var r: int = received[i] if i < received.size() else 0
		var cap: int = card.pars[i] + 2 + r if has_index else card.pars[i] + 5
		total += mini(card.strokes[i], cap)
	return total


## Score differential in tenths, scaled up to 18 holes for a nine.
static func score_differential(adjusted: int, par: int, holes: int) -> int:
	if holes <= 0:
		return 0
	return div_round((adjusted - par) * 10 * 18, holes)


## Handicap index in tenths from differentials, oldest first: the WHS table
## picks the lowest 1 to 8 of the most recent 20 and adjusts by up to -2.0.
## NONE with fewer than three rounds.
static func index(differentials: Array[int]) -> int:
	var recent: Array[int] = differentials.slice(maxi(0, differentials.size() - ROUNDS))
	var n := recent.size()
	if n < 3:
		return NONE
	var use := 8
	var adjust := 0
	if n == 3:
		use = 1
		adjust = -20
	elif n == 4:
		use = 1
		adjust = -10
	elif n == 5:
		use = 1
	elif n == 6:
		use = 2
		adjust = -10
	elif n <= 8:
		use = 2
	elif n <= 11:
		use = 3
	elif n <= 14:
		use = 4
	elif n <= 16:
		use = 5
	elif n <= 18:
		use = 6
	elif n == 19:
		use = 7
	recent.sort()
	var sum := 0
	for i in use:
		sum += recent[i]
	return clampi(div_round(sum, use) + adjust, MIN_TENTHS, MAX_TENTHS)


## "12.3", "+1.4", "0.0"; "-" without an index.
static func format(index_tenths: int) -> String:
	if index_tenths == NONE:
		return "-"
	var a := absi(index_tenths)
	return "%s%d.%d" % ["+" if index_tenths < 0 else "", a / 10, a % 10]


## Parses "12.3" or "+1.4" (a plus handicap) into tenths; NONE if empty or
## not a number.
static func parse(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty() or t == "-":
		return NONE
	var plus := t.begins_with("+")
	if plus:
		t = t.substr(1)
	if not t.is_valid_float():
		return NONE
	var tenths := roundi(t.to_float() * 10.0)
	return clampi(-tenths if plus else tenths, MIN_TENTHS, MAX_TENTHS)
