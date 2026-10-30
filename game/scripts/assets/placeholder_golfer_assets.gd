class_name PlaceholderGolferAssets
extends GolferAssets
## The free MakeHuman golfer, or the primitive figure if its model is missing.


func create_golfer() -> GolferRig:
	var golfer := FreeGolfer.create()
	if golfer != null:
		return golfer
	return PlaceholderGolfer.new()
