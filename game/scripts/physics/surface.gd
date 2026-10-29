class_name Surface
extends RefCounted
## Ground types and how each one treats the ball. Mirrors olcore::Surface and
## surface_params() in libs/olcore/src/shot.cpp; keep the two in step.

enum Type { TEE, FAIRWAY, FRINGE, GREEN, ROUGH, DEEP_ROUGH, SAND, WATER, OUT_OF_BOUNDS }

const NAMES := [
	"Tee", "Fairway", "Fringe", "Green", "Rough", "Deep rough", "Sand", "Water", "Out of bounds",
]

# restitution scale, friction, softness, rolling resistance, lie power, lie spin
const PARAMS := [
	[1.00, 0.40, 1.0, 0.16, 1.00, 1.00],  # tee
	[1.00, 0.40, 1.0, 0.16, 1.00, 1.00],  # fairway
	[0.90, 0.45, 1.0, 0.10, 0.95, 0.90],  # fringe
	[0.85, 0.45, 1.0, 0.055, 1.00, 1.00],  # green
	[0.60, 0.60, 1.2, 0.30, 0.85, 0.60],  # rough
	[0.40, 0.80, 1.4, 0.50, 0.70, 0.40],  # deep rough
	[0.12, 0.90, 1.6, 0.90, 0.75, 0.70],  # sand
	[0.00, 1.00, 1.0, 1.0, 0.00, 0.00],  # water
	[0.60, 0.60, 1.2, 0.30, 0.85, 0.60],  # out of bounds
]


static func name_of(s: int) -> String:
	return NAMES[s]


static func restitution_scale(s: int) -> float:
	return PARAMS[s][0]


static func friction(s: int) -> float:
	return PARAMS[s][1]


static func softness(s: int) -> float:
	return PARAMS[s][2]


static func rolling_resistance(s: int) -> float:
	return PARAMS[s][3]


static func lie_power(s: int) -> float:
	return PARAMS[s][4]


static func lie_spin(s: int) -> float:
	return PARAMS[s][5]
