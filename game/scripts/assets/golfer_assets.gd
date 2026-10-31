class_name GolferAssets
extends RefCounted
## Makes golfer rigs. The POLYANI/.CLP decoder plugs in here: subclass this
## and register it with AssetProviders.golfer_assets.


func create_golfer() -> GolferRig:
	return GolferRig.new()


## A golfer dressed as the player made them in the player creator. Rigs
## that can't change their look (the original game's golfers) ignore it.
func create_golfer_for(_look: PlayerLook) -> GolferRig:
	return create_golfer()
