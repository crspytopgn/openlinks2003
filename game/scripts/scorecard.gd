class_name Scorecard
extends RefCounted
## Stroke-play card. Mirrors olcore::Scorecard in libs/olcore/src/scoring.cpp.
## A hole with 0 strokes has not been played yet.

const SCORE_NAMES := {
	-3: "Albatross",
	-2: "Eagle",
	-1: "Birdie",
	0: "Par",
	1: "Bogey",
	2: "Double bogey",
	3: "Triple bogey",
}

var pars: Array[int] = []
var strokes: Array[int] = []


func _init(hole_pars: Array[int]) -> void:
	pars = hole_pars.duplicate()
	strokes.resize(pars.size())
	strokes.fill(0)


func record(hole: int, hole_strokes: int) -> void:
	strokes[hole] = hole_strokes


func total_strokes() -> int:
	var total := 0
	for s in strokes:
		total += s
	return total


func total_par() -> int:
	var total := 0
	for p in pars:
		total += p
	return total


func holes_played() -> int:
	var n := 0
	for s in strokes:
		if s > 0:
			n += 1
	return n


## Strokes relative to par over the holes played so far.
func to_par() -> int:
	var diff := 0
	for i in strokes.size():
		if strokes[i] > 0:
			diff += strokes[i] - pars[i]
	return diff


static func score_name(hole_strokes: int, par: int) -> String:
	if hole_strokes == 1:
		return "Hole in one"
	var diff := hole_strokes - par
	if SCORE_NAMES.has(diff):
		return SCORE_NAMES[diff]
	return format_to_par(hole_strokes - par)


## "E", "+3", "-2".
static func format_to_par(diff: int) -> String:
	if diff == 0:
		return "E"
	return ("+%d" % diff) if diff > 0 else str(diff)
