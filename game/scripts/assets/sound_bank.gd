class_name SoundBank
extends Node
## Plays game sound events. The audio decoder (WAVs, SOUNDS.LS, .SSF scripts)
## plugs in here: subclass this and register it with AssetProviders.
##
## Events the game uses: &"hit", &"putt", &"land", &"cup", &"splash",
## &"applause", &"footsteps" (the golfer stepping up to the ball), &"club"
## (a club taken from the bag), and the Broadcast presentation's crowd
## reactions &"crowd_cheer", &"crowd_roar", &"crowd_groan", &"crowd_ooh" and
## &"crowd_tee" (applause for a good tee shot).


func play(_event: StringName) -> void:
	pass


## play() with details a bank may use to pick the right sound: "club" (a
## Club), "lie" (the Surface.Type struck from) and "power" (0..1) for &"hit";
## "surface" (Surface.Type) and "speed" (m/s) for &"land". Banks that don't
## care just play the event.
func play_detail(event: StringName, _detail: Dictionary) -> void:
	play(event)


## The kind of club for choosing a strike sound: &"driver", &"wood" (fairway
## woods and hybrids), &"iron", &"wedge" or &"putter".
static func club_kind(club: Club) -> StringName:
	if club.is_putter:
		return &"putter"
	var s := club.short_name
	if s == "Dr":
		return &"driver"
	if (s.length() == 2 and s[0].is_valid_int() and s.ends_with("W")) or s.ends_with("H"):
		return &"wood"
	if s.ends_with("W"):
		return &"wedge"
	return &"iron"
