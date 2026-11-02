class_name DynamicResolution
extends Node
## Lowers the 3D resolution when frames take too long and raises it again
## when there's room, between half (0.8 in the browser) and the chosen render scale, so the game
## stays smooth on slow machines. The upscaler (FSR where there is one) and
## the sharpening hide most of the difference. Off when the target is 0.

const MIN_SCALE := 0.5
## In the browser the renderer has no upscaler but a plain stretch, so
## below this the golfer and every edge turn to visible stair steps (as on
## an iPad, which rarely holds 60 fps on the browser's one thread).
const WEB_MIN_SCALE := 0.8
const STEP := 0.05
const WINDOW := 0.5  ## seconds of frames averaged per decision

var target_fps := 0
var max_scale := 1.0
var min_scale := MIN_SCALE
var _viewport: Viewport
var _time := 0.0
var _frames := 0
var _calm := 0  ## windows in a row with time to spare


func setup(viewport: Viewport, s: GraphicsSettings) -> void:
	_viewport = viewport
	target_fps = s.target_fps()
	max_scale = s.render_scale
	min_scale = minf(WEB_MIN_SCALE if OS.has_feature("web") else MIN_SCALE, max_scale)
	_viewport.scaling_3d_scale = max_scale
	_time = 0.0
	_frames = 0
	_calm = 0


func _process(delta: float) -> void:
	if _viewport == null or target_fps <= 0:
		return
	_time += delta
	_frames += 1
	if _time < WINDOW:
		return
	var frame := _time / _frames
	_time = 0.0
	_frames = 0
	var budget := 1.0 / target_fps
	var scale := _viewport.scaling_3d_scale
	if frame > budget * 1.15:
		_calm = 0
		scale = maxf(min_scale, scale - STEP)
	elif frame < budget * 1.02:
		# With v-sync on, frames never come in under the budget, so a few
		# calm seconds in a row are the sign there's room again.
		_calm += 1
		if _calm >= 6:
			_calm = 0
			scale = minf(max_scale, scale + STEP)
	_viewport.scaling_3d_scale = scale
