#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "olcore/ball_physics.hpp"

namespace olcore {

// Things on a course the ball can hit: tree trunks, canopies, buildings and
// fences. Godot axes and metres, like the rest of the physics. The GDScript
// port is game/scripts/physics/obstacle_field.gd; change both together.

enum class ObstacleKind {
  Solid = 0,   // trunks, walls: the ball bounces off
  Canopy = 1,  // leaves: the ball loses most of its speed and drops
};

struct ObstacleHit {
  double fraction = 0;  // where along the segment the ball enters, 0 to 1
  Vec3 normal;          // outward unit normal of the face it enters through
  ObstacleKind kind = ObstacleKind::Solid;
};

class ObstacleField {
 public:
  // An upright cylinder: centre (x, z), radius, from y0 up to y1.
  void add_cylinder(double x, double z, double radius, double y0, double y1, ObstacleKind kind);
  // A box: centre, three orthonormal axes and the half size along each.
  void add_box(Vec3 centre, const std::array<Vec3, 3>& axes, Vec3 half, ObstacleKind kind);
  // Builds the lookup grid. Call after adding everything.
  void finalize();

  // The first obstacle the segment from -> to enters from outside, if any.
  // A segment that starts inside an obstacle does not hit it.
  bool segment_hit(Vec3 from, Vec3 to, ObstacleHit& hit) const;

  std::size_t size() const { return cylinders_.size() + boxes_.size(); }

  static constexpr double kCell = 10.0;  // metres per side of a grid cell

 private:
  struct Cylinder {
    double x, z, radius, y0, y1;
    ObstacleKind kind;
  };
  struct Box {
    Vec3 centre;
    std::array<Vec3, 3> axes;
    Vec3 half;
    ObstacleKind kind;
  };
  bool hit_cylinder(const Cylinder& c, Vec3 from, Vec3 d, ObstacleHit& hit) const;
  bool hit_box(const Box& b, Vec3 from, Vec3 d, ObstacleHit& hit) const;
  void cell_range(double x0, double z0, double x1, double z1, int& c0, int& r0, int& c1, int& r1) const;

  std::vector<Cylinder> cylinders_;
  std::vector<Box> boxes_;
  // Grid over x, z: items of cell (c, r) are cell_items_[cell_start_[i] ..
  // cell_start_[i + 1]) with i = r * cols_ + c. An item k >= 0 is a
  // cylinder; k < 0 is box -k - 1.
  double origin_x_ = 0, origin_z_ = 0;
  int cols_ = 0, rows_ = 0;
  std::vector<std::int32_t> cell_start_, cell_items_;
};

}  // namespace olcore
