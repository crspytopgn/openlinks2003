class_name AnalogSwing
extends RefCounted
## Turns a thumbstick or a finger on a touch screen into the mouse movement
## Links 2003's mouse swing reads (LinksMouse), so both swing the club with the
## game's own frames, momentum and errors: nothing about the physics changes.
##
## Both are read as a position, not a speed. Pulling the stick (or the finger)
## back takes the club back: all the way back is a full backswing for a putt
## or chip and about 85% for a full swing, which the mouse also gives before
## the meter's slow zone. Pushing forward swings the club down, and how
## briskly sets the power, as with the mouse: a quick flick from the top hits
## a driver about as hard as the club allows, a slow push much softer. Moving
## sideways during the stroke hooks, slices or misses just as the mouse does.
## How far the movement goes in mouse pixels for a full deflection was tuned
## against libs/olcore's links_mouse.cpp with scripted swings.

## Mouse pixels for a full deflection on a full swing.
const FULL_SWING_PX := 650.0
## Mouse pixels per unit of a club's response for chips and putts, which
## follow the mouse with no momentum: 1000 / response fills the meter.
const SHORT_SWING_PX := 1000.0
## The stick's dead zone, either way on each axis.
const DEADZONE := 0.12
## A pulled stick (past the dead zone) or a finger dragged this share of a
## full deflection back starts the swing.
const START := 0.05
## On the way back the club waits at the top until the stick comes this far
## forward, so the stick's jitter at full stretch (or a finger resting) doesn't
## start the downswing.
const TOP_HOLD := 0.04
## The share of the screen's height a finger travels for a full deflection.
const TOUCH_SPAN := 0.4


## Mouse pixels for a full deflection with this club and shot.
static func reach_px(shot: int, club: int) -> float:
	if shot == LinksMouse.Shot.FULL:
		return FULL_SWING_PX
	var k := LinksMouse.club_response(club) * (0.75 if shot == LinksMouse.Shot.CHIP else 1.0)
	return SHORT_SWING_PX / k


## A stick axis with the dead zone taken out, -1..1.
static func dead_zone(v: float) -> float:
	var a := absf(v)
	if a <= DEADZONE:
		return 0.0
	return signf(v) * minf((a - DEADZONE) / (1.0 - DEADZONE), 1.0)


## A thumbstick's position with the dead zone taken out (+y back, towards
## the player, as the stick reports it).
static func stick(raw: Vector2) -> Vector2:
	return Vector2(dead_zone(raw.x), dead_zone(raw.y))


## A finger's movement since it touched down, as a deflection (+y back,
## down the screen), on a screen `height` pixels high.
static func touch(from: Vector2, at: Vector2, height: float) -> Vector2:
	return (at - from) / maxf(height * TOUCH_SPAN, 1.0)


## Follows one stroke's deflection and hands out the mouse movement for it.
class Tracker:
	var reach := FULL_SWING_PX
	var _last := Vector2.ZERO
	var _peak := 0.0
	var _down := false

	func _init(p_reach: float) -> void:
		reach = p_reach

	## The deflection now; returns the mouse pixels moved since the last call.
	func feed(deflection: Vector2) -> Vector2:
		var d := deflection
		if not _down:
			if d.y >= _peak:
				_peak = d.y
			elif d.y > _peak - TOP_HOLD:
				d.y = _last.y  # waiting at the top
			else:
				_down = true
		var moved := (d - _last) * reach
		_last = d
		return moved

	## Whether the stroke has come forward from the top yet.
	func coming_down() -> bool:
		return _down
