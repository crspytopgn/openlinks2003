class_name StandardShotModel
extends ShotModel
## Published real-world golf ball physics (BallPhysics), standing in until the
## model is tuned against the original game.


func launch(club: Club, power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	var s := Swing.launch_from_swing(club, power, accuracy, aim_deg, lie)
	s.position = from
	return s


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind)
