class_name SoundCaptions
extends RefCounted
## Settings > Captions: bracketed text for the sounds that carry meaning, the
## golfer's spoken reactions and the crowd. The golfer's line is captioned
## by its voice event's name in the player's bank ("Great Shot", "In Water";
## docs/formats/ssf.md#golfer-voices), not word for word.

const CROWD := {
	&"applause": "Applause",
	&"crowd_cheer": "The crowd cheers",
	&"crowd_roar": "The crowd roars",
	&"crowd_groan": "The crowd groans",
	&"crowd_ooh": "The crowd: \"Ooh!\"",
	&"crowd_tee": "Applause round the tee",
}


## "[Golfer: Great Shot]"; `who` names the golfer in a round of several.
static func voice(event_name: String, who := "Golfer") -> String:
	var line := event_name.strip_edges().trim_suffix("!")
	return "" if line.is_empty() else "[%s: %s]" % [who, line]


## "[The crowd cheers]", or empty for a sound that isn't the crowd.
static func crowd(sound: StringName) -> String:
	return "[%s]" % CROWD[sound] if CROWD.has(sound) else ""
