class_name ShotShape
extends RefCounted
## Draw, fade, high and low: the round's simple face on Links 2003's shot
## setup (ball position, club face and stance, LinksLaunch.Setup).
##
## A fade turns the stance (and so the swing path) `curve` degrees left of the
## target and turns the club face back by the same, so the face stays square
## to the target and is open to the path: the ball starts on or just left of
## the target line and curves right. A draw is the reverse. Height moves the
## ball forward in the stance (higher, more spin) or back (lower, less spin),
## one of the game's ball-position steps at a time.
##
## The limits are our own: the game's setup screen limits are not read yet.

const MAX_CURVE := 6
const MAX_HEIGHT := 3

## Degrees of face open to the path: positive fades, negative draws.
var curve := 0
## Ball-position steps forward of the club's neutral spot: positive is higher.
var height := 0


func is_square() -> bool:
	return curve == 0 and height == 0


func reset() -> void:
	curve = 0
	height = 0


func nudge_curve(step: int) -> bool:
	var before := curve
	curve = clampi(curve + step, -MAX_CURVE, MAX_CURVE)
	return curve != before


func nudge_height(step: int) -> bool:
	var before := height
	height = clampi(height + step, -MAX_HEIGHT, MAX_HEIGHT)
	return height != before


## The game's setup for `club_short_name` (a LinksLaunch.CLUB_INDEX key).
## Square is the game's own default (ball position -1, the club's neutral).
func to_setup(club_short_name: String) -> LinksLaunch.Setup:
	var s := LinksLaunch.Setup.new()
	s.stance = 30 - curve
	s.face = 30 + curve
	if height != 0:
		var neutral := LinksLaunch.neutral_ball_position(LinksLaunch.CLUB_INDEX.get(club_short_name, 1))
		s.ball_position = maxi(0, neutral - height)
	return s


## "Draw 2, high 1"; empty when square.
func describe() -> String:
	var parts: Array[String] = []
	if curve != 0:
		parts.append("%s %d" % ["Fade" if curve > 0 else "Draw", absi(curve)])
	if height != 0:
		parts.append("%s %d" % ["high" if height > 0 else "low", absi(height)])
	if parts.is_empty():
		return ""
	var text := ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)
