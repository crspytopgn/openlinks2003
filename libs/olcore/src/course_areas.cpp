#include "olcore/course_areas.hpp"

#include <algorithm>

#include "olcore/binary_reader.hpp"
#include "olcore/links_ground.hpp"

namespace olcore {

namespace {

constexpr std::uint32_t kTerrainTypesVersion = 4;
constexpr std::size_t kTerrainTypeSize = 243;
constexpr std::size_t kNameOffset = 0x67;
constexpr std::size_t kTypeNameOffset = 0xa7;
constexpr std::size_t kNameBytes = 0x40;
constexpr std::uint32_t kShapesVersion = 1;
constexpr std::size_t kShapeHeader = 37;
constexpr std::size_t kNodeSize = 36;
// The game tessellates into a buffer of 5,000 points.
constexpr int kOutlinePoints = 5000;
constexpr int kMaxDepth = 2;

// A NUL-terminated UTF-16 name in a fixed field, as UTF-8.
std::string utf16_name(const std::vector<std::uint8_t>& d, std::size_t o) {
  std::string out;
  for (std::size_t i = 0; i + 1 < kNameBytes; i += 2) {
    std::uint32_t c = d[o + i] | d[o + i + 1] << 8;
    if (c == 0) break;
    if (c < 0x80) {
      out += static_cast<char>(c);
    } else if (c < 0x800) {
      out += static_cast<char>(0xc0 | (c >> 6));
      out += static_cast<char>(0x80 | (c & 0x3f));
    } else {
      out += static_cast<char>(0xe0 | (c >> 12));
      out += static_cast<char>(0x80 | ((c >> 6) & 0x3f));
      out += static_cast<char>(0x80 | (c & 0x3f));
    }
  }
  return out;
}

std::vector<CourseShape> read_shapes(BinaryReader& r) {
  std::vector<CourseShape> out;
  while (r.remaining() >= kShapeHeader) {
    CourseShape s;
    s.id = r.u32();
    std::uint32_t count = r.u32();
    s.closed = r.u8() != 0;
    s.min = {r.f32(), r.f32()};
    r.f32();
    s.max = {r.f32(), r.f32()};
    r.f32();
    s.attributes = r.u32();
    if (count > r.remaining() / kNodeSize) throw ReadError("shape runs past end of entry");
    s.nodes.resize(count);
    for (CourseShape::Node& n : s.nodes) {
      for (auto* p : {&n.in, &n.point, &n.out}) {
        (*p)[0] = r.f32();
        (*p)[1] = r.f32();
        r.f32();  // height, unused for outlines
      }
    }
    out.push_back(std::move(s));
  }
  return out;
}

using P = std::array<double, 2>;
P mid(P a, P b) { return {(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5}; }

// The game's subdivision: split the segment a -> b in half (de Casteljau),
// emit the left half's points, the middle, then the right half's.
void subdivide(const CourseShape::Node& a, const CourseShape::Node& b, int depth, Outline& out) {
  P handles = mid(a.out, b.in);
  CourseShape::Node l = a, r = b;
  l.out = mid(a.point, a.out);
  r.in = mid(b.point, b.in);
  CourseShape::Node m;
  m.in = mid(l.out, handles);
  m.out = mid(handles, r.in);
  m.point = mid(m.in, m.out);
  if (depth != 0) subdivide(l, m, depth - 1, out);
  out.push_back(m.point);
  if (depth != 0) subdivide(m, r, depth - 1, out);
}

}  // namespace

std::vector<CrzTerrainType> parse_crz_terrain_types(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kTerrainTypesVersion) {
    throw ReadError("terrain types version " + std::to_string(version) + " is not supported");
  }
  std::uint32_t count = r.u32();
  if (count > r.remaining() / kTerrainTypeSize) throw ReadError("terrain types run past end of entry");
  std::vector<CrzTerrainType> out(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    std::size_t o = 8 + i * kTerrainTypeSize;
    r.seek(o);
    CrzTerrainType& t = out[i];
    t.index = r.u32();
    for (float& v : t.values) v = r.f32();
    t.ground_class = r.u32();
    t.category = r.u32();
    t.flags = r.u32();
    t.name = utf16_name(data, o + kNameOffset);
    t.type_name = utf16_name(data, o + kTypeNameOffset);
  }
  return out;
}

LinksSurface links_surface(const CrzTerrainType& t) {
  int c = static_cast<int>(t.ground_class);
  if (c < kLinksGreen || c > kLinksDeepGrass) return links_surface(kLinksRough);
  if (c == kLinksGreen) return links_surface(kLinksGreen);
  LinksSurface s;
  s.ground_class = c;
  s.restitution = t.value(0x14);
  s.impact_friction = t.value(0x18);
  s.skid_friction = t.value(0x1c);
  s.impact_drag = t.value(0x20);
  s.roll_resistance = t.value(0x24);
  s.stop_speed = t.value(0x28);
  s.spin_grip = t.value(0x2c);
  s.lie_spin = t.value(0x04);
  s.lie_power = t.value(0x0c);
  return s;
}

std::vector<CourseShape> parse_shapes(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kShapesVersion) throw ReadError("shapes version " + std::to_string(version) + " is not supported");
  r.skip(12);
  return read_shapes(r);
}

std::vector<CourseShape> parse_id_shapes(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t count = r.u32();
  std::uint32_t version = r.u32();
  if (version != kShapesVersion) throw ReadError("shapes version " + std::to_string(version) + " is not supported");
  r.skip(12);
  std::vector<CourseShape> out = read_shapes(r);
  if (out.size() != count) throw ReadError("shape count does not match");
  return out;
}

Outline shape_outline(const CourseShape& s) {
  Outline out;
  int n = static_cast<int>(s.nodes.size());
  if (n == 0) return out;
  // Fewer halvings when the shape has many segments.
  int depth = kMaxDepth;
  int fit = (kOutlinePoints - 1) >> (depth + 1);
  while (fit < n && depth >= 0) {
    --depth;
    fit = (kOutlinePoints - 1) >> (depth + 1);
  }
  if (n > 1) {
    int end = std::min(n, fit);
    const CourseShape::Node* prev = s.closed ? &s.nodes[n - 1] : &s.nodes[0];
    for (int i = s.closed ? 0 : 1; i < end; ++i) {
      out.push_back(prev->point);
      if (depth >= 0) subdivide(*prev, s.nodes[i], depth, out);
      prev = &s.nodes[i];
    }
    out.push_back(prev->point);
  }
  return out;
}

bool outline_contains(const Outline& o, double x, double y) {
  if (o.empty()) return false;
  P v0 = o.back();
  bool y0 = v0[1] >= y;
  bool inside = false;
  for (const P& v1 : o) {
    bool y1 = v1[1] >= y;
    if (y0 != y1) {
      bool x0 = v0[0] >= x, x1 = v1[0] >= x;
      if (x0 == x1) {
        if (x0) inside = !inside;
      } else if (v1[0] - (v1[1] - y) * (v0[0] - v1[0]) / (v0[1] - v1[1]) >= x) {
        inside = !inside;
      }
    }
    y0 = y1;
    v0 = v1;
  }
  return inside;
}

HoleBounds::HoleBounds(const std::vector<CourseShape>& hole_shapes, const std::vector<CourseShape>& ob_shapes) {
  holes_.resize(18);
  for (const CourseShape& s : hole_shapes) {
    int h = s.hole();
    if (h < 1 || h > 18) continue;
    holes_[h - 1] = {s.min, s.max, shape_outline(s), 1};
  }
  for (const CourseShape& s : ob_shapes) ob_.push_back({s.min, s.max, shape_outline(s), s.attributes});
}

bool HoleBounds::inside(const Area& a, double x, double y) {
  if (x < a.min[0] || x > a.max[0] || y < a.min[1] || y > a.max[1]) return false;
  return outline_contains(a.outline, x, y);
}

bool HoleBounds::in_bounds(int hole_number, double x, double y) const {
  if (hole_number < 1 || hole_number > static_cast<int>(holes_.size())) return true;
  const Area& own = holes_[hole_number - 1];
  // A hole with an outline (even one too short to draw) keeps the ball in it.
  if (own.mask != 0 && !inside(own, x, y)) return false;
  for (const Area& a : ob_) {
    if (((a.mask >> (hole_number - 1)) & 1u) && inside(a, x, y)) return false;
  }
  return true;
}

}  // namespace olcore
