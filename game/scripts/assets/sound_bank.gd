class_name SoundBank
extends Node
## Plays game sound events. The audio decoder (WAVs, SOUNDS.LS, .SSF scripts)
## plugs in here: subclass this and register it with AssetProviders.
##
## Events the game uses: &"swing", &"hit", &"putt", &"land", &"cup",
## &"splash", &"applause".


func play(_event: StringName) -> void:
	pass
