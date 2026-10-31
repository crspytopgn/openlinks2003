class_name PlaceholderGolferAssets
extends GolferAssets
## The free MakeHuman golfer, or the primitive figure if its model is missing.


func create_golfer() -> GolferRig:
	return create_golfer_for(null)


func create_golfer_for(look: PlayerLook) -> GolferRig:
	var golfer := FreeGolfer.create(look)
	if golfer != null:
		return golfer
	return PlaceholderGolfer.new()
