class_name RangeGame
extends RefCounted
## The range's target game: a bucket of balls at the target greens, points
## for each ball that lands or finishes on one, more for longer targets and
## double in the bullseye, and the last balls of the bucket count double.
## Our own scoring, in the spirit of the target-range games golf
## entertainment venues play. Pure logic: main.gd feeds it each shot.

const BALLS := 20
## The last this many balls of a bucket score double.
const FINAL_BALLS := 2
## The bullseye: this fraction of a target's radius round its flag.
const BULLSEYE := 0.35
## Points for each target of PracticeGround.TARGETS, nearest first.
const POINTS: Array[int] = [10, 15, 20, 25, 30, 35, 40, 50]

## Target centres (x, z) and radii, nearest first.
var centres: Array[Vector2] = []
var radii: Array[float] = []
var ball := 0  ## balls hit so far
var score := 0
var best := 0  ## the best bucket this session
var last_points := 0
var last_text := ""


## One target per entry of `targets` (x, z, radius).
func _init(targets: Array[Vector3] = []) -> void:
	for t in targets:
		centres.append(Vector2(t.x, t.y))
		radii.append(t.z)


func finished() -> bool:
	return ball >= BALLS


## Starts a new bucket.
func restart() -> void:
	ball = 0
	score = 0
	last_points = 0
	last_text = ""


## What a ball landing at `p` (x, z) is worth: [points, target index or -1,
## bullseye].
func points_at(p: Vector2) -> Array:
	for i in centres.size():
		var d := p.distance_to(centres[i])
		if d <= radii[i]:
			var bull := d <= radii[i] * BULLSEYE
			return [POINTS[mini(i, POINTS.size() - 1)] * (2 if bull else 1), i, bull]
	return [0, -1, false]


## Scores a shot: whichever is worth more of where it first landed and
## where it finished (a ball that pitches on a target and runs off still
## counts, as does one that rolls on). Returns the points.
func add_shot(first_landing: Vector3, rest: Vector3) -> int:
	if finished():
		restart()
	var a := points_at(Vector2(first_landing.x, first_landing.z))
	var b := points_at(Vector2(rest.x, rest.z))
	var hit: Array = a if int(a[0]) >= int(b[0]) else b
	ball += 1
	var final := ball > BALLS - FINAL_BALLS
	last_points = int(hit[0]) * (2 if final else 1)
	score += last_points
	if finished():
		best = maxi(best, score)
	if int(hit[1]) < 0:
		last_text = "Missed the targets"
	else:
		var yards: int = PracticeGround.TARGETS[int(hit[1])][0]
		last_text = "%d yd target%s: %d points%s" % [yards, ", bullseye" if hit[2] else "",
			last_points, " (final ball, double)" if final else ""]
	return last_points


## A line for the panel: the bucket so far.
func status() -> String:
	if ball == 0:
		return "Target game: %d balls. Land on the target greens; the bullseye and the last %d balls score double." % [BALLS, FINAL_BALLS]
	var text := "Ball %d of %d    Score %d" % [ball, BALLS, score]
	if best > 0:
		text += "    Best %d" % best
	if finished():
		text += "\nBucket done! Hit again for a new one."
	return text
