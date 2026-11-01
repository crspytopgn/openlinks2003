class_name ShotRecord
extends RefCounted
## One shot of a recorded round: everything needed to play it again through
## the same ShotModel (the inputs, and the seed-derived draws it used) and what
## it did, so a checker can compare. See docs/online-play.md.

## Who swung (a seat in the setup) and whose ball it was (differs in the
## shared-ball team modes).
var player := 0
var ball := 0
## Index of the hole in the round (not the course's hole number).
var hole := 0
## How many holes the wind had started when this shot was played: the
## checker draws the wind again in the same order.
var holes_started := 0
## Number of this shot in the round, from 0: picks its random draws.
var index := 0
var club := 0
var club_name := ""
var aim_deg := 0.0
var power := 0.0
var accuracy := 0.0
var lie: int = Surface.Type.TEE
var from := Vector3.ZERO
## Swing skill (LinksShotModel) and the computer golfer's settings.
var skill := 3
var computer := false
var cpu_rating := -1
## A Classic computer golfer's ratings for Links 2003's miss generators
## (tee, woods and irons, chips, putts, max power); empty for a realistic
## golfer, whose swing is all in power, accuracy and aim.
var cpu_ratings := PackedInt32Array()
var to_hole_m := 0.0
var wind_level := 0
var wind := Vector3.ZERO
## A Chip (Links 2003's shot type near the green).
var chip := false
## A PowerStroke mouse swing, or null for the meter, and the swing help
## count before it (null without one).
var stroke: LinksMouse.Stroke = null
var help: LinksMouse.Help = null
## Links 2003's shot setup (LinksLaunch.Setup): square unless the person
## shaped the shot (ShotShape).
var ball_position := -1
var face := 30
var stance := 30
## A real swing from a launch monitor (OpenConnect.Launch.to_array):
## played as measured instead of through the swing. Empty otherwise.
var monitor: Array = []
## Taken again as a mulligan: played, but not counted on the card.
var mulligan := false
## What happened.
var rest := Vector3.ZERO
var outcome: int = ShotResult.Outcome.REST


func to_dict() -> Dictionary:
	var d := {
		"player": player, "ball": ball, "hole": hole, "holes_started": holes_started, "index": index,
		"club": club, "club_name": club_name, "aim_deg": aim_deg, "power": power, "accuracy": accuracy,
		"lie": lie, "from": _vec(from), "skill": skill, "computer": computer, "cpu_rating": cpu_rating,
		"to_hole_m": to_hole_m, "chip": chip, "wind_level": wind_level, "wind": _vec(wind),
		"rest": _vec(rest), "outcome": outcome,
	}
	if ball_position >= 0 or face != 30 or stance != 30:
		d["setup"] = [ball_position, face, stance]
	if not monitor.is_empty():
		d["monitor"] = monitor
	if not cpu_ratings.is_empty():
		d["cpu_ratings"] = Array(cpu_ratings)
	if mulligan:
		d["mulligan"] = true
	if stroke != null:
		d["stroke"] = {
			"skill": stroke.skill, "shot": stroke.shot, "club": stroke.club, "speed": stroke.speed,
			"drift": stroke.drift, "drift_before": stroke.drift_before, "down": stroke.down,
			"backswing": stroke.backswing, "straight": stroke.straight,
		}
	if help != null:
		d["help"] = {"enabled": help.enabled, "strokes": help.strokes, "still_strokes": help.still_strokes}
	return d


static func from_dict(d: Dictionary) -> ShotRecord:
	var r := ShotRecord.new()
	r.player = int(d.get("player", 0))
	r.ball = int(d.get("ball", 0))
	r.hole = int(d.get("hole", 0))
	r.holes_started = int(d.get("holes_started", 0))
	r.index = int(d.get("index", 0))
	r.club = int(d.get("club", 0))
	r.club_name = str(d.get("club_name", ""))
	r.aim_deg = float(d.get("aim_deg", 0.0))
	r.power = float(d.get("power", 0.0))
	r.accuracy = float(d.get("accuracy", 0.0))
	r.lie = int(d.get("lie", Surface.Type.TEE))
	r.from = _to_vec(d.get("from", []))
	r.skill = int(d.get("skill", 3))
	r.computer = bool(d.get("computer", false))
	r.cpu_rating = int(d.get("cpu_rating", -1))
	r.cpu_ratings = PackedInt32Array(d.get("cpu_ratings", []))
	r.to_hole_m = float(d.get("to_hole_m", 0.0))
	r.chip = bool(d.get("chip", false))
	r.wind_level = int(d.get("wind_level", 0))
	r.wind = _to_vec(d.get("wind", []))
	r.rest = _to_vec(d.get("rest", []))
	r.outcome = int(d.get("outcome", ShotResult.Outcome.REST))
	var setup: Variant = d.get("setup")
	if setup is Array and (setup as Array).size() == 3:
		r.ball_position = int(setup[0])
		r.face = int(setup[1])
		r.stance = int(setup[2])
	r.mulligan = bool(d.get("mulligan", false))
	var mon: Variant = d.get("monitor")
	if mon is Array and (mon as Array).size() == 5:
		r.monitor = (mon as Array).duplicate()
	var s: Variant = d.get("stroke")
	if s is Dictionary:
		var m := LinksMouse.Stroke.new()
		m.skill = int(s.get("skill", 3))
		m.shot = int(s.get("shot", 0)) as LinksMouse.Shot
		m.club = int(s.get("club", 0))
		m.speed = float(s.get("speed", 0.0))
		m.drift = float(s.get("drift", 0.0))
		m.drift_before = float(s.get("drift_before", 0.0))
		m.down = int(s.get("down", 1))
		m.backswing = float(s.get("backswing", 1.0))
		m.straight = int(s.get("straight", 0))
		r.stroke = m
	var h: Variant = d.get("help")
	if h is Dictionary:
		r.help = LinksMouse.Help.new()
		r.help.enabled = bool(h.get("enabled", false))
		r.help.strokes = int(h.get("strokes", 0))
		r.help.still_strokes = int(h.get("still_strokes", 0))
	return r


## The setup as the shot model takes it.
func setup() -> LinksLaunch.Setup:
	var s := LinksLaunch.Setup.new()
	s.ball_position = ball_position
	s.face = face
	s.stance = stance
	return s


static func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
