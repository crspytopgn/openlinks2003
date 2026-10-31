class_name HoleMap
extends RefCounted
## A small top-down map of a hole for the broadcast hole card: the ground
## types sampled from the terrain, turned so the tee is at the bottom and the
## green at the top, with the route, the tee and the pin marked.

const WIDTH := 72
const HEIGHT := 160
const COLORS := {
	Surface.Type.TEE: Color(0.36, 0.62, 0.3),
	Surface.Type.FAIRWAY: Color(0.36, 0.62, 0.3),
	Surface.Type.FRINGE: Color(0.42, 0.7, 0.36),
	Surface.Type.GREEN: Color(0.52, 0.82, 0.44),
	Surface.Type.ROUGH: Color(0.2, 0.4, 0.2),
	Surface.Type.DEEP_ROUGH: Color(0.14, 0.3, 0.15),
	Surface.Type.SAND: Color(0.9, 0.84, 0.62),
	Surface.Type.WATER: Color(0.2, 0.42, 0.75),
	Surface.Type.OUT_OF_BOUNDS: Color(0.08, 0.16, 0.1),
}


var texture: ImageTexture
## The map's frame: world x,z to pixels (to_px).
var _tee := Vector2.ZERO
var _side := Vector2.RIGHT
var _up := Vector2.UP
var _mid := Vector2.ZERO
var _metres_per_px := 1.0


static func make(hole: HoleData) -> ImageTexture:
	return build(hole).texture


## The map and its frame, so shots can be marked on it (to_px).
static func build(hole: HoleData) -> HoleMap:
	var tee := Vector2(hole.tee.x, hole.tee.z)
	var pin := Vector2(hole.pin.x, hole.pin.z)
	var pts: Array[Vector2] = [tee]
	for r in hole.route:
		pts.append(r)
	pts.append(pin)
	var up := (pin - tee).normalized() if tee.distance_to(pin) > 1.0 else Vector2(0, 1)
	var side := Vector2(-up.y, up.x)  ## to the golfer's right (+x is left)
	# Extent of the route in the turned frame, plus a margin.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := _turn(p - tee, side, up)
		lo = lo.min(q)
		hi = hi.max(q)
	var length := hi.y - lo.y + 50.0
	var metres_per_px := maxf(length / HEIGHT, (hi.x - lo.x + 60.0) / WIDTH)
	var mid := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)
	var img := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for py in HEIGHT:
		for px in WIDTH:
			var q := mid + Vector2(px - WIDTH * 0.5, HEIGHT * 0.5 - py) * metres_per_px
			var w := tee + side * q.x + up * q.y
			img.set_pixel(px, py, COLORS.get(hole.terrain.surface_at(w.x, w.y), Color(0.2, 0.4, 0.2)))
	var map := HoleMap.new()
	map._tee = tee
	map._side = side
	map._up = up
	map._mid = mid
	map._metres_per_px = metres_per_px
	for i in range(1, pts.size()):
		_line(img, map.to_px_2d(pts[i - 1]), map.to_px_2d(pts[i]), Color(1, 1, 1, 0.8))
	_dot(img, map.to_px_2d(tee), Color(0.98, 0.78, 0.25))
	_dot(img, map.to_px_2d(pin), Color(0.9, 0.1, 0.1))
	map.texture = ImageTexture.create_from_image(img)
	return map


## Where a world point falls on the map, in map pixels.
func to_px(p: Vector3) -> Vector2:
	return to_px_2d(Vector2(p.x, p.z))


func to_px_2d(p: Vector2) -> Vector2:
	var q := _turn(p - _tee, _side, _up) - _mid
	return Vector2(WIDTH * 0.5 + q.x / _metres_per_px, HEIGHT * 0.5 - q.y / _metres_per_px)


static func _turn(v: Vector2, side: Vector2, up: Vector2) -> Vector2:
	return Vector2(v.dot(side), v.dot(up))


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(1, ceili(a.distance_to(b)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_put(img, int(p.x), int(p.y), col)


static func _dot(img: Image, c: Vector2, col: Color) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx * dx + dy * dy <= 5:
				_put(img, int(c.x) + dx, int(c.y) + dy, col)


static func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)
