#include "olcore/links_objects.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace olcore {

namespace {

constexpr double kParallel = 1e-4;          // |facing . path| below this: no hit
constexpr double kTurnRange = 2.09440565;   // radians across a trunk's width (2 pi / 3)
constexpr double kCanopyKept = 0.9;

// The game draws its "random" choices from the bit pattern of a float.
int float_bits_mod10(double x) {
  float f = static_cast<float>(x);
  std::int32_t bits = 0;
  std::memcpy(&bits, &f, 4);
  return bits % 10;
}

Vec3 rotate_z(Vec3 v, double a) {
  double c = std::cos(a), s = std::sin(a);
  return {v.x * c - v.y * s, v.x * s + v.y * c, v.z};
}

}  // namespace

LinksSpriteMask links_sprite_mask(const RgbaImage& image) {
  LinksSpriteMask m;
  m.width = image.width;
  m.height = image.height;
  m.alpha.resize(std::size_t(m.width) * std::size_t(m.height));
  for (int y = 0; y < m.height; ++y) {
    for (int x = 0; x < m.width; ++x) {
      std::size_t src = (std::size_t(m.height - 1 - y) * std::size_t(m.width) + std::size_t(x)) * 4 + 3;
      m.alpha[std::size_t(y) * std::size_t(m.width) + std::size_t(x)] = image.pixels[src];
    }
  }
  return m;
}

double links_anchor_x(std::int32_t extra_byte) {
  if (extra_byte < 0) return 0.5;
  return 0.5 + static_cast<std::int8_t>(extra_byte) * 0.0078125;
}

double links_anchor_z(std::int32_t extra_word) {
  if (extra_word < 0) return 0;
  return static_cast<std::int16_t>(extra_word) / 256.0;
}

void LinksObjects::add(const LinksBillboard& b) {
  int index = static_cast<int>(billboards_.size());
  billboards_.push_back(b);
  double aspect = b.type >= 0 && b.type < static_cast<int>(types.size()) ? types[std::size_t(b.type)].aspect : 1.0;
  double reach = b.height * aspect;
  auto lo = [&](double v) { return static_cast<std::int64_t>(std::floor((v - reach) / kCell)); };
  auto hi = [&](double v) { return static_cast<std::int64_t>(std::floor((v + reach) / kCell)); };
  for (std::int64_t cx = lo(b.base.x); cx <= hi(b.base.x); ++cx) {
    for (std::int64_t cy = lo(b.base.y); cy <= hi(b.base.y); ++cy) cells_[key(cx, cy)].push_back(index);
  }
}

bool LinksObjects::hit_one(int index, Vec3 p, Vec3 d, Vec3 facing, Hit& out) const {
  const LinksBillboard& b = billboards_[std::size_t(index)];
  if (b.type < 0 || b.type >= static_cast<int>(types.size())) return false;
  const LinksObjectType& type = types[std::size_t(b.type)];
  const Vec3 n = facing;
  double denom = dot(n, d);
  if (!(std::fabs(denom) >= kParallel)) return false;
  double t = (dot(n, b.base) - dot(n, p)) / denom;
  Vec3 h = p + d * t;
  const double tall = b.height, wide = b.height * type.aspect;
  double top = b.base.z + (1 - b.anchor_z) * tall;
  double bottom = b.base.z - b.anchor_z * tall;
  if (h.z > top || h.z < bottom) return false;
  Vec3 side = cross(Vec3{0, 0, 1}, n);
  Vec3 left = b.base - side * (b.anchor_x * wide);
  Vec3 right = b.base + side * ((1 - b.anchor_x) * wide);
  if (h.x < std::min(left.x, right.x) || h.x > std::max(left.x, right.x)) return false;
  if (h.y < std::min(left.y, right.y) || h.y > std::max(left.y, right.y)) return false;
  double u = std::hypot(h.x - left.x, h.y - left.y) / wide;
  double v = (h.z - bottom) / tall;

  // The picture at that point.
  const LinksSpriteMask& mask = type.mask;
  int px = static_cast<int>(u * mask.width), py = static_cast<int>(v * mask.height);
  int alpha = mask.at(px, py);
  if (alpha == 0) return false;

  const auto& s = type.shape;
  bool core = u > s[2] && u < s[4] && v > s[3] && v < s[5];
  out.point = h;
  if (!(type.collision & 2u) && (core || float_bits_mod10(v) == 0)) {
    out.kind = 1;
    out.normal = n;
    if (!(type.collision & 1u)) {
      // Off a trunk the ball turns by where across its width it struck.
      int l = px, r = px;
      while (l >= 0 && mask.at(l, py) != 0) --l;
      while (r < mask.width && mask.at(r, py) != 0) ++r;
      double across = (u * mask.width - l) / double(r - l);
      out.normal = rotate_z(n, (across - 0.5) * kTurnRange);
    }
    out.factor = s[0];
  } else {
    if (!(s[1] * 10.0 > float_bits_mod10(u))) return false;
    out.kind = 2;
    out.normal = n;
    out.factor = (alpha / 255.0 * (1 - s[0]) + s[0]) * kCanopyKept;
  }
  out.object = index;
  return true;
}

bool LinksObjects::hit(Vec3 p, Vec3 q, Vec3 facing, int last, Hit& out) const {
  Vec3 d = q - p;
  double len = length(d);
  if (!(len > 0)) return false;
  Vec3 dir = d * (1 / len);
  const Vec3 n = facing;
  std::int64_t x0 = static_cast<std::int64_t>(std::floor(std::min(p.x, q.x) / kCell));
  std::int64_t x1 = static_cast<std::int64_t>(std::floor(std::max(p.x, q.x) / kCell));
  std::int64_t y0 = static_cast<std::int64_t>(std::floor(std::min(p.y, q.y) / kCell));
  std::int64_t y1 = static_cast<std::int64_t>(std::floor(std::max(p.y, q.y) / kCell));
  bool found = false;
  double best = 0;
  std::vector<int> seen;
  for (std::int64_t cx = x0; cx <= x1; ++cx) {
    for (std::int64_t cy = y0; cy <= y1; ++cy) {
      auto it = cells_.find(key(cx, cy));
      if (it == cells_.end()) continue;
      for (int i : it->second) {
        if (i == last || std::find(seen.begin(), seen.end(), i) != seen.end()) continue;
        seen.push_back(i);
        const Vec3 base = billboards_[std::size_t(i)].base;
        // Only a path that crosses the billboard's plane can hit it.
        if ((dot(p - base, n) > 0) == (dot(q - base, n) > 0)) continue;
        Hit h;
        if (!hit_one(i, p, dir, n, h)) continue;
        double along = length(h.point - p);
        if (!found || along < best) {
          found = true;
          best = along;
          out = h;
        }
      }
    }
  }
  return found;
}

}  // namespace olcore
