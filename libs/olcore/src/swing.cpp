#include "olcore/swing.hpp"

#include <algorithm>

namespace olcore {

namespace {
constexpr double kMphToMps = 0.44704;
constexpr double kMaxSidespinRpm = 1500.0;  // at accuracy +/-1
constexpr double kMaxPushDeg = 2.5;         // start-line error at accuracy +/-1
constexpr double kMaxPuttPushDeg = 2.0;
}  // namespace

const std::vector<Club>& standard_clubs() {
  // Driver to pitching wedge: tour averages. Wedges and putter: estimates.
  static const std::vector<Club> clubs = {
      {"Driver", "Dr", 167 * kMphToMps, 10.9, 2686, false},
      {"3 Wood", "3W", 158 * kMphToMps, 9.2, 3655, false},
      {"5 Wood", "5W", 152 * kMphToMps, 9.4, 4350, false},
      {"3 Hybrid", "3H", 146 * kMphToMps, 10.2, 4437, false},
      {"4 Iron", "4i", 137 * kMphToMps, 11.0, 4836, false},
      {"5 Iron", "5i", 132 * kMphToMps, 12.1, 5361, false},
      {"6 Iron", "6i", 127 * kMphToMps, 14.1, 6231, false},
      {"7 Iron", "7i", 120 * kMphToMps, 16.3, 7097, false},
      {"8 Iron", "8i", 115 * kMphToMps, 18.1, 7998, false},
      {"9 Iron", "9i", 109 * kMphToMps, 20.4, 8647, false},
      {"Pitching Wedge", "PW", 102 * kMphToMps, 24.2, 9304, false},
      {"Sand Wedge", "SW", 88 * kMphToMps, 30.0, 10000, false},
      {"Lob Wedge", "LW", 76 * kMphToMps, 34.0, 10500, false},
      {"Putter", "Pt", 6.0, 0.0, 0, true},
  };
  return clubs;
}

BallState launch_from_swing(const Club& club, const SwingInput& in, Surface lie) {
  double power = std::clamp(in.power, 0.0, 1.0);
  double accuracy = std::clamp(in.accuracy, -1.0, 1.0);
  if (club.putter) {
    return make_launch(club.ball_speed_mps * power, 0.0, in.aim_deg - accuracy * kMaxPuttPushDeg, 0.0, 0.0);
  }
  SurfaceParams sp = surface_params(lie);
  double speed = club.ball_speed_mps * power * sp.lie_power;
  double backspin = club.backspin_rpm * sp.lie_spin * (0.6 + 0.4 * power);
  return make_launch(speed, club.launch_deg, in.aim_deg - accuracy * kMaxPushDeg, backspin,
                     -accuracy * kMaxSidespinRpm);
}

}  // namespace olcore
