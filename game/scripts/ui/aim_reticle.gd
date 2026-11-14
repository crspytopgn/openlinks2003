class_name AimReticle
extends Control
## The aim point drawn over the picture while a full shot is lined up: a
## thin crosshair where the aim ring lies and the carry to it. Links 2003
## draws its aim cursor over the scene, so the target is never lost; the
## ring on the grass alone vanished behind a crest or into the haze on long
## and blind shots (the tee view of a downhill par 4 showed no target at
## all). Behind a rise it says BLIND, as a caddie would.

const ARM := 9.0
const GAP := 4.0
const LINE := Color(1, 1, 1, 0.9)
const SHADE := Color(0, 0, 0, 0.45)

var _at := Vector2.ZERO
var _label := ""
var _blind := false
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = GlassTheme.font(600)
	visible = false


## Shows the reticle at screen point `at`, with `label` under it; `blind`
## when the ground hides the aim point from the camera.
func show_at(at: Vector2, label: String, blind: bool) -> void:
	if visible and at.is_equal_approx(_at) and label == _label and blind == _blind:
		return
	_at = at
	_label = label
	_blind = blind
	visible = true
	queue_redraw()


func hide_reticle() -> void:
	visible = false


## The label for a carry of `yards`, BLIND when the aim point is out of sight.
static func label_for(yards: int, blind: bool) -> String:
	return ("BLIND  %d YD" if blind else "%d YD") % yards


func _draw() -> void:
	for pass_i in 2:
		var col := SHADE if pass_i == 0 else LINE
		var o := Vector2(1, 1) if pass_i == 0 else Vector2.ZERO
		var c := _at + o
		var w := 2.0
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * GAP, c + d * (GAP + ARM), col, w, true)
		if _blind:
			draw_arc(c, GAP + ARM + 3.0, 0.0, TAU, 32, col, 1.5, true)
	if _label.is_empty():
		return
	var fs := 14
	var tw := _font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := _at + Vector2(-tw * 0.5, GAP + ARM + 20.0)
	draw_string(_font, tp + Vector2(1, 1), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SHADE)
	draw_string(_font, tp, _label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LINE)
