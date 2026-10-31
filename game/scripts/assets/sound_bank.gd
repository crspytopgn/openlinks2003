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
## care just play the event. Any event may carry "gain_db", how much
## quieter (negative) it is heard from where the camera stands (heard_from).
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


const SPEED_OF_SOUND := 343.0  ## m/s in air at about 20 C
const NEAR_M := 20.0  ## closer than this a sound plays at its full level
const FAINTEST_DB := -30.0  ## far sounds bottom out here, never silent


## How a sound made `distance_m` from the listener (the camera) is heard:
## "delay_s", the time it takes to arrive, and "gain_db", how much it has
## faded (inverse square, so 6 dB quieter each time the distance doubles).
## A drive landing 250 m away is heard about 0.7 s after it bounces.
static func heard_from(distance_m: float) -> Dictionary:
	var d := maxf(distance_m, 0.0)
	var gain := 0.0
	if d > NEAR_M:
		gain = maxf(-20.0 * log(d / NEAR_M) / log(10.0), FAINTEST_DB)
	return {"delay_s": d / SPEED_OF_SOUND, "gain_db": gain}
