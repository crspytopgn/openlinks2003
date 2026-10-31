class_name GeoFrame
extends RefCounted
## Turns latitude and longitude into course metres around a centre point,
## and back. The course's +z is north and +x is west (the game's +x is the
## golfer's left when facing +z). Over a few kilometres a local tangent
## plane is accurate to centimetres, so no map projection library is needed.

const EARTH_RADIUS := 6371008.8  ## mean radius, metres

var lat0 := 0.0
var lon0 := 0.0
var _m_per_deg_lat := 0.0
var _m_per_deg_lon := 0.0


func _init(p_lat := 0.0, p_lon := 0.0) -> void:
	lat0 = p_lat
	lon0 = p_lon
	# WGS84 metres per degree at this latitude (series form).
	var phi := deg_to_rad(lat0)
	_m_per_deg_lat = 111132.954 - 559.822 * cos(2.0 * phi) + 1.175 * cos(4.0 * phi)
	_m_per_deg_lon = 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi) + 0.118 * cos(5.0 * phi)


## (x, z) on the course for a latitude and longitude.
func to_local(lat: float, lon: float) -> Vector2:
	return Vector2(-(lon - lon0) * _m_per_deg_lon, (lat - lat0) * _m_per_deg_lat)


## Latitude of a course point. (Kept as a 64-bit float: a Vector2 is
## 32-bit, which would round latitudes to tens of centimetres.)
func lat_of(p: Vector2) -> float:
	return lat0 + p.y / _m_per_deg_lat


## Longitude of a course point.
func lon_of(p: Vector2) -> float:
	return lon0 - p.x / _m_per_deg_lon
