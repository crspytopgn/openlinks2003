class_name Club
extends RefCounted
## A club's full-power launch. Mirrors standard_clubs() in
## libs/olcore/src/swing.cpp: tour-average launch monitor data, standing in
## until the original game's club distances are measured.

const MPH_TO_MPS := 0.44704

var full_name: String
var short_name: String
var ball_speed_mps: float
var launch_deg: float
var backspin_rpm: float
var is_putter: bool
## Full-power total distance on flat fairway with the stand-in physics, for
## club selection and the aim marker. tests/run_tests.gd checks these still
## match BallPhysics.
var carry_m: float
var total_m: float


func _init(p_name: String, p_short: String, p_speed: float, p_launch: float, p_spin: float, p_carry: float, p_total: float, p_putter := false) -> void:
	full_name = p_name
	short_name = p_short
	ball_speed_mps = p_speed
	launch_deg = p_launch
	backspin_rpm = p_spin
	carry_m = p_carry
	total_m = p_total
	is_putter = p_putter


static func standard_set() -> Array[Club]:
	var clubs: Array[Club] = [
		Club.new("Driver", "Dr", 167.0 * MPH_TO_MPS, 10.9, 2686.0, 223.6, 264.3),
		Club.new("3 Wood", "3W", 158.0 * MPH_TO_MPS, 9.2, 3655.0, 215.0, 252.0),
		Club.new("5 Wood", "5W", 152.0 * MPH_TO_MPS, 9.4, 4350.0, 211.1, 240.1),
		Club.new("3 Hybrid", "3H", 146.0 * MPH_TO_MPS, 10.2, 4437.0, 203.2, 231.1),
		Club.new("4 Iron", "4i", 137.0 * MPH_TO_MPS, 11.0, 4836.0, 191.1, 216.7),
		Club.new("5 Iron", "5i", 132.0 * MPH_TO_MPS, 12.1, 5361.0, 185.7, 205.5),
		Club.new("6 Iron", "6i", 127.0 * MPH_TO_MPS, 14.1, 6231.0, 177.6, 188.0),
		Club.new("7 Iron", "7i", 120.0 * MPH_TO_MPS, 16.3, 7097.0, 163.6, 168.9),
		Club.new("8 Iron", "8i", 115.0 * MPH_TO_MPS, 18.1, 7998.0, 152.3, 154.4),
		Club.new("9 Iron", "9i", 109.0 * MPH_TO_MPS, 20.4, 8647.0, 140.3, 141.1),
		Club.new("Pitching Wedge", "PW", 102.0 * MPH_TO_MPS, 24.2, 9304.0, 126.3, 126.2),
		Club.new("Sand Wedge", "SW", 88.0 * MPH_TO_MPS, 30.0, 10000.0, 100.9, 100.0),
		Club.new("Lob Wedge", "LW", 76.0 * MPH_TO_MPS, 34.0, 10500.0, 80.3, 79.0),
		Club.new("Putter", "Pt", 6.0, 0.0, 0.0, 0.0, 33.4, true),
	]
	return clubs
