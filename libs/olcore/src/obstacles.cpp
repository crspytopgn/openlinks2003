#include "olcore/obstacles.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace olcore {

namespace {

constexpr double kInf = std::numeric_limits<double>::infinity();
constexpr double kTiny = 1e-12;

// Where the segment p + d t is between lo and hi along one axis, as
// [t0, t1]. False if it never is.
bool slab(double p, double d, double lo, double hi, double& t0, double& t1) {
  if (std::fabs(d) < kTiny) {
    t0 = -kInf;
    t1 = kInf;
    return p >= lo && p <= hi;
  }
  double a = (lo - p) / d, b = (hi - p) / d;
  t0 = std::min(a, b);
  t1 = std::max(a, b);
  return true;
}

}  // namespace

void ObstacleField::add_cylinder(double x, double z, double radius, double y0, double y1, ObstacleKind kind) {
  cylinders_.push_back({x, z, radius, y0, y1, kind});
}

void ObstacleField::add_box(Vec3 centre, const std::array<Vec3, 3>& axes, Vec3 half, ObstacleKind kind) {
  boxes_.push_back({centre, axes, half, kind});
}

void ObstacleField::cell_range(double x0, double z0, double x1, double z1, int& c0, int& r0, int& c1,
                               int& r1) const {
  c0 = std::max(0, int(std::floor((x0 - origin_x_) / kCell)));
  r0 = std::max(0, int(std::floor((z0 - origin_z_) / kCell)));
  c1 = std::min(cols_ - 1, int(std::floor((x1 - origin_x_) / kCell)));
  r1 = std::min(rows_ - 1, int(std::floor((z1 - origin_z_) / kCell)));
}

void ObstacleField::finalize() {
  // Each item's footprint on the ground, as x0, z0, x1, z1.
  std::vector<std::array<double, 4>> extent;
  for (const Cylinder& c : cylinders_) extent.push_back({c.x - c.radius, c.z - c.radius, c.x + c.radius, c.z + c.radius});
  for (const Box& b : boxes_) {
    double rx = 0, rz = 0;
    for (int k = 0; k < 3; ++k) {
      double h = k == 0 ? b.half.x : (k == 1 ? b.half.y : b.half.z);
      rx += std::fabs(b.axes[k].x) * h;
      rz += std::fabs(b.axes[k].z) * h;
    }
    extent.push_back({b.centre.x - rx, b.centre.z - rz, b.centre.x + rx, b.centre.z + rz});
  }
  cols_ = rows_ = 0;
  cell_start_.clear();
  cell_items_.clear();
  if (extent.empty()) return;
  double x0 = kInf, z0 = kInf, x1 = -kInf, z1 = -kInf;
  for (const auto& e : extent) {
    x0 = std::min(x0, e[0]);
    z0 = std::min(z0, e[1]);
    x1 = std::max(x1, e[2]);
    z1 = std::max(z1, e[3]);
  }
  origin_x_ = x0;
  origin_z_ = z0;
  cols_ = int(std::floor((x1 - x0) / kCell)) + 1;
  rows_ = int(std::floor((z1 - z0) / kCell)) + 1;
  auto item = [&](std::size_t i) {
    return i < cylinders_.size() ? std::int32_t(i) : -std::int32_t(i - cylinders_.size()) - 1;
  };
  // Two passes: count per cell, then fill.
  std::vector<std::int32_t> count(std::size_t(cols_) * rows_ + 1, 0);
  for (const auto& e : extent) {
    int c0, r0, c1, r1;
    cell_range(e[0], e[1], e[2], e[3], c0, r0, c1, r1);
    for (int r = r0; r <= r1; ++r)
      for (int c = c0; c <= c1; ++c) ++count[std::size_t(r) * cols_ + c + 1];
  }
  for (std::size_t i = 1; i < count.size(); ++i) count[i] += count[i - 1];
  cell_start_ = count;
  cell_items_.resize(std::size_t(count.back()));
  for (std::size_t i = 0; i < extent.size(); ++i) {
    int c0, r0, c1, r1;
    cell_range(extent[i][0], extent[i][1], extent[i][2], extent[i][3], c0, r0, c1, r1);
    for (int r = r0; r <= r1; ++r)
      for (int c = c0; c <= c1; ++c) cell_items_[std::size_t(count[std::size_t(r) * cols_ + c]++)] = item(i);
  }
}

bool ObstacleField::hit_cylinder(const Cylinder& c, Vec3 from, Vec3 d, ObstacleHit& hit) const {
  double ty0, ty1;
  if (!slab(from.y, d.y, c.y0, c.y1, ty0, ty1)) return false;
  double fx = from.x - c.x, fz = from.z - c.z;
  double a = d.x * d.x + d.z * d.z;
  double cc = fx * fx + fz * fz - c.radius * c.radius;
  double tc0 = -kInf, tc1 = kInf;
  if (a < kTiny) {
    if (cc > 0) return false;
  } else {
    double b = fx * d.x + fz * d.z;
    double disc = b * b - a * cc;
    if (disc < 0) return false;
    double sq = std::sqrt(disc);
    tc0 = (-b - sq) / a;
    tc1 = (-b + sq) / a;
  }
  double t0 = std::max(ty0, tc0), t1 = std::min(ty1, tc1);
  if (t0 > t1 || t0 < 0 || t0 > 1) return false;
  hit.fraction = t0;
  hit.kind = c.kind;
  if (tc0 >= ty0) {
    hit.normal = {(fx + d.x * t0) / c.radius, 0, (fz + d.z * t0) / c.radius};
  } else {
    hit.normal = {0, d.y > 0 ? -1.0 : 1.0, 0};
  }
  return true;
}

bool ObstacleField::hit_box(const Box& b, Vec3 from, Vec3 d, ObstacleHit& hit) const {
  Vec3 rel = from - b.centre;
  const double half[3] = {b.half.x, b.half.y, b.half.z};
  double t0 = -kInf, t1 = kInf;
  int face = -1;
  double face_sign = 1;
  for (int k = 0; k < 3; ++k) {
    double p = dot(rel, b.axes[k]), dk = dot(d, b.axes[k]);
    double a, e;
    if (!slab(p, dk, -half[k], half[k], a, e)) return false;
    if (a > t0) {
      t0 = a;
      face = k;
      face_sign = dk > 0 ? -1.0 : 1.0;
    }
    t1 = std::min(t1, e);
  }
  if (face < 0 || t0 > t1 || t0 < 0 || t0 > 1) return false;
  hit.fraction = t0;
  hit.kind = b.kind;
  hit.normal = b.axes[std::size_t(face)] * face_sign;
  return true;
}

bool ObstacleField::segment_hit(Vec3 from, Vec3 to, ObstacleHit& hit) const {
  if (cols_ == 0) return false;
  Vec3 d = to - from;
  int c0, r0, c1, r1;
  cell_range(std::min(from.x, to.x), std::min(from.z, to.z), std::max(from.x, to.x), std::max(from.z, to.z), c0,
             r0, c1, r1);
  bool found = false;
  ObstacleHit h;
  for (int r = r0; r <= r1; ++r) {
    for (int c = c0; c <= c1; ++c) {
      std::size_t cell = std::size_t(r) * cols_ + c;
      for (std::int32_t i = cell_start_[cell]; i < cell_start_[cell + 1]; ++i) {
        std::int32_t k = cell_items_[std::size_t(i)];
        bool got = k >= 0 ? hit_cylinder(cylinders_[std::size_t(k)], from, d, h)
                          : hit_box(boxes_[std::size_t(-k - 1)], from, d, h);
        if (got && (!found || h.fraction < hit.fraction)) {
          hit = h;
          found = true;
        }
      }
    }
  }
  return found;
}

}  // namespace olcore
