class_name GolferAssets
extends RefCounted
## Makes golfer rigs. The POLYANI/.CLP decoder plugs in here: subclass this
## and register it with AssetProviders.golfer_assets.


func create_golfer() -> GolferRig:
	return GolferRig.new()
