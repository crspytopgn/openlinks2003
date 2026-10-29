#pragma once

#include <string>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// A club's full-power launch. The values come from published tour-average
// launch monitor data and are stand-ins until the original game's club
// distances are measured. The GDScript port (game/scripts/physics/clubs.gd)
// carries the same table.
struct Club {
  const char* name;
  const char* short_name;
  double ball_speed_mps;
  double launch_deg;
  double backspin_rpm;
  bool putter;
};

const std::vector<Club>& standard_clubs();

// The result of a swing meter.
//   power     0..1, the fraction of a full swing
//   accuracy  -1..1; 0 is a perfect strike, negative is early (pull-hook),
//             positive is late (push-slice)
//   aim_deg   heading of the target line, positive = left of +z
struct SwingInput {
  double power = 1.0;
  double accuracy = 0.0;
  double aim_deg = 0.0;
};

// Launch state for a swing, with the ball at the origin. The lie scales ball
// speed and backspin; the putter ignores it.
BallState launch_from_swing(const Club& club, const SwingInput& in, Surface lie);

}  // namespace olcore
