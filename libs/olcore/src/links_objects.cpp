#include "olcore/links_objects.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace olcore {

namespace {

constexpr double kParallel = 1e-4;          // |facing . path| below this: no hit
constexpr double kTurnRange = 2.09440565;   // radians across a trunk's width (2 pi / 3)
constexpr double kCanopyKept = 0.9;
constexpr double kFlatFace = 1e-5;          // |determinant| below this: the ray runs along the face

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

void LinksObjects::add_model(LinksModel m) {
  if (m.points.empty()) return;
  m.box_min = m.box_max = m.points[0];
  for (const Vec3& v : m.points) {
    m.box_min = {std::min(m.box_min.x, v.x), std::min(m.box_min.y, v.y), std::min(m.box_min.z, v.z)};
    m.box_max = {std::max(m.box_max.x, v.x), std::max(m.box_max.y, v.y), std::max(m.box_max.z, v.z)};
  }
  int index = static_cast<int>(models_.size());
  auto cell = [](double v) { return static_cast<std::int64_t>(std::floor(v / kCell)); };
  for (std::int64_t cx = cell(m.box_min.x); cx <= cell(m.box_max.x); ++cx) {
    for (std::int64_t cy = cell(m.box_min.y); cy <= cell(m.box_max.y); ++cy) model_cells_[key(cx, cy)].push_back(index);
  }
  models_.push_back(std::move(m));
}

namespace {

// Where the ray p + t d enters the box, or a negative number if it misses
// (the game's slab test: a ray, not a segment).
bool ray_meets_box(Vec3 p, Vec3 d, Vec3 lo, Vec3 hi, double& t_near) {
  const double pa[3] = {p.x, p.y, p.z}, da[3] = {d.x, d.y, d.z};
  const double la[3] = {lo.x, lo.y, lo.z}, ha[3] = {hi.x, hi.y, hi.z};
  double t0 = -3.4028234663852886e38, t1 = 3.4028234663852886e38;
  for (int i = 0; i < 3; ++i) {
    if (da[i] == 0) {
      if (pa[i] < la[i] || pa[i] > ha[i]) return false;
      continue;
    }
    double a = (la[i] - pa[i]) / da[i], b = (ha[i] - pa[i]) / da[i];
    if (a > b) std::swap(a, b);
    t0 = std::max(t0, a);
    t1 = std::min(t1, b);
    if (t0 > t1 || t1 < 0) return false;
  }
  t_near = t0;
  return true;
}

}  // namespace

bool LinksObjects::hit_model(int index, Vec3 p, Vec3 d, double reach, Hit& out) const {
  const LinksModel& m = models_[std::size_t(index)];
  if (m.mesh < 0 || m.mesh >= static_cast<int>(meshes.size())) return false;
  const LinksMesh& mesh = meshes[std::size_t(m.mesh)];
  double t_near = 0;
  if (!ray_meets_box(p, d, m.box_min, m.box_max, t_near)) return false;
  if (reach > 0 && !(t_near < reach)) return false;
  double best = -1;
  Vec3 normal;
  for (const LinksMesh::Face& f : mesh.faces) {
    if (f.count < 3 || std::size_t(f.first) + f.count > mesh.corners.size()) continue;
    auto corner = [&](int k) {
      std::size_t v = mesh.corners[std::size_t(f.first) + std::size_t(k)];
      return v < m.points.size() ? m.points[v] : Vec3{};
    };
    const Vec3 a = corner(0);
    for (int k = 1; k + 1 < f.count; ++k) {
      // The fan triangle (corner 0, k + 1, k), Moller and Trumbore's way.
      const Vec3 b = corner(k + 1), c = corner(k);
      const Vec3 e1 = b - a, e2 = c - a;
      const Vec3 pv = cross(d, e2);
      const double det = dot(e1, pv);
      if (det > -kFlatFace && det < kFlatFace) continue;
      if (det < 0) continue;  // the face's back
      const double inv = 1 / det;
      const Vec3 s = p - a;
      const double u = dot(s, pv) * inv;
      if (u < 0 || u > 1) continue;
      const Vec3 qv = cross(s, e1);
      const double v = dot(d, qv) * inv;
      if (v < 0 || u + v > 1) continue;
      const double t = dot(e2, qv) * inv;
      if (t < 0) continue;
      if (reach >= 0 && !(t < reach)) continue;
      if (best >= 0 && !(t < best)) continue;
      // A see-through texture: the texel there must not be clear. The game
      // takes the uvs of corners 0, k and k + 1 of the whole mesh, not of
      // this face.
      if (f.texture < mesh.holes.size() && mesh.holes[f.texture].width > 0) {
        const LinksSpriteMask& tex = mesh.holes[f.texture];
        if (std::size_t(k) + 1 >= mesh.uvs.size()) continue;
        const auto& t0 = mesh.uvs[0];
        const auto& tk = mesh.uvs[std::size_t(k)];
        const auto& tk1 = mesh.uvs[std::size_t(k) + 1];
        const double tu = t0[0] + (tk[0] - t0[0]) * v + (tk1[0] - t0[0]) * u;
        const double tv = t0[1] + (tk[1] - t0[1]) * v + (tk1[1] - t0[1]) * u;
        int x = static_cast<int>(tu * tex.width) % tex.width;
        int y = static_cast<int>(tv * tex.height) % tex.height;
        if (x < 0) x += tex.width;
        if (y < 0) y += tex.height;
        if (tex.at(x, y) == 0) continue;
      }
      best = t;
      normal = cross(e1, e2);
    }
  }
  if (!(best >= 0)) return false;
  double n = length(normal);
  out.object = index;
  out.point = p + d * best;
  out.normal = n > 0 ? normal * (1 / n) : normal;
  out.kind = 8;
  out.factor = 0;
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
  std::vector<int> seen, seen_models;
  for (std::int64_t cx = x0; cx <= x1; ++cx) {
    for (std::int64_t cy = y0; cy <= y1; ++cy) {
      static const std::vector<int> kNone;
      auto it = cells_.find(key(cx, cy));
      for (int i : it == cells_.end() ? kNone : it->second) {
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
      // 3D objects: met face by face, and never skipped as the last one hit.
      auto mit = model_cells_.find(key(cx, cy));
      if (mit == model_cells_.end()) continue;
      for (int i : mit->second) {
        if (std::find(seen_models.begin(), seen_models.end(), i) != seen_models.end()) continue;
        seen_models.push_back(i);
        Hit h;
        if (!hit_model(i, p, dir, len, h)) continue;
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
