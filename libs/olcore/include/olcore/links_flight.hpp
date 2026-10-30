#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include "olcore/ball_physics.hpp"

namespace olcore {

// The ball flight model of Links 2003, as described in
// docs/formats/physics.md. The game works in feet and revolutions per
// second; these functions take and return SI units like the rest of olcore.
//
// The drag and lift coefficient tables live in the game's executable and are
// read from the player's copy (find_links_aero); nothing from the game is
// built into olcore.

// A coefficient looked up by air speed (ft/s) and spin (rev/s), bilinear
// between grid points and clamped to the edges of the grid.
struct CoefficientTable {
  std::vector<double> speeds;  // ft/s, ascending
  std::vector<double> spins;   // rev/s, ascending
  std::vector<double> values;  // speeds.size() rows of spins.size() values

  double at(double speed_fps, double spin_rps) const;
};

struct LinksAero {
  CoefficientTable drag;
  CoefficientTable lift;
};

// Finds the two coefficient tables in a Links 2003 executable (version 1.0
// or the 1.07 patch). Returns nothing if they are not there.
std::optional<LinksAero> find_links_aero(const std::uint8_t* exe, std::size_t size);
std::optional<LinksAero> find_links_aero(const std::vector<std::uint8_t>& exe);

// Scalar constants of the model, in the game's units.
struct LinksFlightConstants {
  static constexpr double kFeetPerMetre = 1.0 / 0.3048;
  static constexpr double kGravityFps2 = 32.152;
  static constexpr double kDragScale = 0.004735;  // per foot
  static constexpr double kLiftScale = 0.0057443;  // per foot
  static constexpr double kSpinKeptPerFrame = 0.9994;
  static constexpr double kFrameRate = 60.0;
  // The game blows the air at this fraction of the wind it is given.
  static constexpr double kWindScale = 0.5;
};

// Acceleration on the ball (m/s^2): gravity, drag along the velocity through
// the air and lift along spin-axis x velocity, with both coefficients from
// the tables. `wind` is the velocity of the wind before kWindScale.
Vec3 links_acceleration(const BallState& s, const LinksAero& aero, Vec3 wind);

// One step the way the game takes it: velocity from the acceleration at the
// start of the step, position from the average of the old and new
// velocities, and the spin kept at 0.9994 per 1/60 s.
BallState links_step_flight(const BallState& s, const LinksAero& aero, Vec3 wind, double dt);

}  // namespace olcore
