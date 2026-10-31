class_name Commentary
extends RefCounted
## Caption lines for the Broadcast presentation, picked from what a shot did,
## and the crowd reaction that goes with it. The lines are our own.

enum Crowd { NONE, POLITE, CHEER, ROAR, GROAN, OOH }

const HOLED_LONG := ["It's in! What a shot!", "Holed it! The crowd erupts!", "Unbelievable, straight in the cup!"]
const HOLED_PUTT := ["Right in the heart.", "Never in doubt.", "That one dropped nicely."]
const HOLED_BIG_PUTT := ["From way downtown, it drops!", "What a putt! Read it perfectly."]
const LIP := ["Oh, it lips out!", "So close. That was nearly in.", "Just slid by the edge."]
const STIFF := ["That's stiff! Tap-in range.", "Brilliant. Right at the flag.", "What a strike, that's close."]
const GREEN := ["Safely on the green.", "That's found the putting surface.", "Good, solid approach."]
const FAIRWAY_LONG := ["Big drive, splitting the fairway.", "Smashed, right down the middle.", "That's a great position."]
const FAIRWAY := ["In the fairway.", "Nicely played.", "That'll do just fine."]
const ROUGH := ["That's caught the rough.", "A bit wayward, into the long stuff.", "Not ideal, the lie could be tricky."]
const SAND := ["Into the bunker.", "That's found the sand.", "A tough bunker shot coming up."]
const WATER := ["Oh no, that's wet.", "Into the water, a costly mistake.", "Splash. That one's gone."]
const OUT := ["That's out of bounds.", "Way off line, out of bounds."]
const SHORT_PUTT_MISS := ["That will be disappointing.", "Pushed it, that's a missed chance."]
const PUTT := ["Good pace on that one.", "Leaves a tidy one coming back.", "Hit it firmly enough."]


## Picks a line and a crowd reaction. `rest_surface` is where it stopped,
## `to_pin_m` the distance left, `from_m` the distance before the shot.
static func pick(shot: ShotResult, rest_surface: int, putting: bool, to_pin_m: float, from_m: float, rng: RandomNumberGenerator) -> Array:
	match shot.outcome:
		ShotResult.Outcome.HOLED:
			if not putting:
				return [_one(HOLED_LONG, rng), Crowd.ROAR]
			if from_m > 9.0:
				return [_one(HOLED_BIG_PUTT, rng), Crowd.ROAR]
			return [_one(HOLED_PUTT, rng), Crowd.CHEER if from_m > 2.5 else Crowd.POLITE]
		ShotResult.Outcome.WATER:
			return [_one(WATER, rng), Crowd.GROAN]
		ShotResult.Outcome.OUT_OF_BOUNDS:
			return [_one(OUT, rng), Crowd.GROAN]
	if putting:
		if to_pin_m < 0.35:
			return [_one(LIP, rng), Crowd.OOH]
		if from_m < 2.5 and to_pin_m > 0.5:
			return [_one(SHORT_PUTT_MISS, rng), Crowd.GROAN]
		return [_one(PUTT, rng), Crowd.NONE]
	if to_pin_m < 3.0 and from_m > 25.0:
		return [_one(STIFF, rng), Crowd.CHEER]
	match rest_surface:
		Surface.Type.GREEN, Surface.Type.FRINGE:
			return [_one(GREEN, rng), Crowd.POLITE]
		Surface.Type.FAIRWAY, Surface.Type.TEE:
			if shot.carry_m > 230.0:
				return [_one(FAIRWAY_LONG, rng), Crowd.POLITE]
			return [_one(FAIRWAY, rng), Crowd.NONE]
		Surface.Type.SAND:
			return [_one(SAND, rng), Crowd.OOH]
		Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH:
			return [_one(ROUGH, rng), Crowd.NONE]
	return ["", Crowd.NONE]


static func _one(lines: Array, rng: RandomNumberGenerator) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]
