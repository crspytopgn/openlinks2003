#pragma once

#include <vector>

namespace olcore {

struct LinksAero;

struct Vec3 {
  double x = 0, y = 0, z = 0;
};

inline Vec3 operator+(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vec3 operator-(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline Vec3 operator*(Vec3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
inline double dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
double length(Vec3 v);
Vec3 cross(Vec3 a, Vec3 b);

// Coordinate system matches Godot: +y is up, +z is downrange (away from the
// golfer), +x is to the golfer's left. Units are SI (metres, seconds, rad/s).
struct BallState {
  Vec3 position;
  Vec3 velocity;
  Vec3 spin;  // angular velocity, rad/s
};

// Aerodynamic constants. These are generic real-world golf ball values and
// are placeholders until we measure how the original game's ball behaves.
struct BallParams {
  double mass = 0.04593;           // kg (rules maximum)
  double radius = 0.021335;        // m (rules minimum diameter / 2)
  double air_density = 1.225;      // kg/m^3, sea level
  // Drag coefficient Cd = drag_coefficient + drag_spin_factor * S, where S is
  // the spin ratio r|w|/|v| (Smits and Smith's fit for a dimpled ball), so
  // high-spin irons and wedges lose more speed than a driver.
  double drag_coefficient = 0.24;
  double drag_spin_factor = 0.18;
  double gravity = 9.81;           // m/s^2
  double spin_decay_per_s = 0.04;  // fraction of spin lost per second
  // Velocity of the air, m/s: (0, 0, 5) is a 5 m/s tailwind on a shot hit
  // towards +z. Uniform at every height; drag and lift act on the ball's
  // speed through the air rather than over the ground.
  Vec3 wind;
  // When set, the flight uses the Links 2003 model (links_flight.hpp)
  // instead of the drag and lift fits above.
  const LinksAero* links = nullptr;
};

// Builds a launch state from the numbers a swing produces.
//   speed_mps        ball speed off the face
//   launch_deg       vertical launch angle
//   azimuth_deg      horizontal direction, positive = left of the target line
//   backspin_rpm     backspin (positive keeps the ball up)
//   sidespin_rpm     positive curves the ball left (draw for a right-hander)
BallState make_launch(double speed_mps, double launch_deg, double azimuth_deg, double backspin_rpm,
                      double sidespin_rpm);

// Acceleration on the ball from gravity, drag and Magnus lift, with drag and
// lift worked out from the velocity relative to the wind.
Vec3 acceleration(const BallState& s, const BallParams& p);

// Advances the flight by dt seconds (RK4 on position and velocity, or the
// game's own step when p.links is set).
BallState step_flight(const BallState& s, const BallParams& p, double dt);

struct FlightResult {
  BallState landing;       // state at the moment the ball returns to y = 0
  double carry_m = 0;      // horizontal distance from launch to landing
  double apex_m = 0;       // maximum height
  double flight_time_s = 0;
  std::vector<Vec3> path;  // sampled positions, for drawing the trail
};

// Flies the ball over flat ground until it comes back down to y = 0.
// Bounce and roll are separate (surface-dependent) and not modelled yet.
FlightResult simulate_flight(const BallState& launch, const BallParams& p, double dt = 0.001,
                             int path_every_n_steps = 10);

}  // namespace olcore
