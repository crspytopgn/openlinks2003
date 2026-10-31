#pragma once

#include "olcore/ball_physics.hpp"
#include "olcore/obstacles.hpp"

namespace olcore {

struct LinksSurface;

// Ground types a ball can come to rest on. The order is shared with the
// GDScript port (game/scripts/physics/surface.gd); keep them in step.
enum class Surface {
  Tee = 0,
  Fairway,
  Fringe,
  Green,
  Rough,
  DeepRough,
  Sand,
  Water,
  OutOfBounds,
};

const char* surface_name(Surface s);

// How a surface treats the ball. Generic real-world values; placeholders
// until they are tuned against the original game.
struct SurfaceParams {
  double restitution_scale;   // multiplies the turf restitution curve
  double friction;            // Coulomb friction during a bounce
  double softness;            // scales how far the ball dents the turf
  double rolling_resistance;  // rolling deceleration as a fraction of g
  double lie_power;           // ball-speed multiplier when hitting from here
  double lie_spin;            // backspin multiplier when hitting from here
};

SurfaceParams surface_params(Surface s);

// What the shot simulation needs to know about the ground. Course loaders
// implement this; FlatTerrain is enough for tests.
class Terrain {
 public:
  virtual ~Terrain() = default;
  virtual double height(double x, double z) const = 0;
  virtual Surface surface(double x, double z) const = 0;
  // Unit surface normal. The default takes central differences of height().
  virtual Vec3 normal(double x, double z) const;
  // Ground the rules give free relief from (cart paths). None by default.
  virtual bool free_drop(double, double) const { return false; }
  // Ground the rules treat as a hazard (no drops there) besides water.
  virtual bool hazard(double, double) const { return false; }
  // Whether a ball at rest here is in bounds for the hole being played. A
  // course can limit each hole to an outline; Surface::OutOfBounds is ground
  // that is off the course altogether.
  virtual bool in_bounds(double, double) const { return true; }
  // The course's own bounce and roll values here, or null to use the class
  // defaults for surface().
  virtual const LinksSurface* links_surface_at(double, double) const { return nullptr; }
  // The first obstacle (tree, wall) the ball meets moving from -> to. The
  // default looks in `obstacles`, if set.
  virtual bool obstacle_hit(Vec3 from, Vec3 to, ObstacleHit& hit) const {
    return obstacles != nullptr && obstacles->segment_hit(from, to, hit);
  }

  const ObstacleField* obstacles = nullptr;
};

class FlatTerrain : public Terrain {
 public:
  explicit FlatTerrain(Surface s = Surface::Fairway, double h = 0.0) : surface_(s), height_(h) {}
  double height(double, double) const override { return height_; }
  Surface surface(double, double) const override { return surface_; }
  Vec3 normal(double, double) const override { return {0, 1, 0}; }

 private:
  Surface surface_;
  double height_;
};

}  // namespace olcore
