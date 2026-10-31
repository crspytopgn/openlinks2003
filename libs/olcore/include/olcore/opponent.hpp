#pragma once

#include <cstdint>

#include "olcore/swing.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// Computer opponents. A computer golfer plans a shot through the same physics
// as the player (the game shell searches clubs, aims and power with its
// ShotModel), then swings it with the mistakes of its skill level: the error
// is in the swing inputs (power, timing, aim), never in the ball physics, so
// the computer plays by the same rules as everyone else.
//
// The skill numbers are our own, set so the levels score roughly like the
// golfers they are named after (see docs/game-shell.md). The GDScript port is
// game/scripts/ai/opponent_skill.gd; keep the two in step.

enum class SkillLevel { Beginner = 0, Club, Scratch, Tour };
constexpr int kSkillLevelCount = 4;

struct SkillProfile {
  const char* name;
  double power_sd;         // full swings: power error, fraction of the swing
  double accuracy_sd;      // full swings: timing error on the -1..1 scale
  double aim_sd_deg;       // full swings: lining up
  double putt_power_sd;    // putts: pace error, fraction of the planned speed
  double putt_aim_sd_deg;  // putts: read and line error
  double mishit_chance;    // chance a full swing is a duff or a top
  double strength;         // the most power it swings with (the meter's 0..1)
  bool course_management;  // weighs the risk of a miss when choosing a shot
};

const SkillProfile& skill_profile(SkillLevel level);
const char* skill_name(SkillLevel level);

// Small deterministic generator (xorshift32), so a seeded round plays the same
// in C++ and GDScript.
class OpponentRng {
 public:
  explicit OpponentRng(std::uint32_t seed = 1) : state_(seed != 0 ? seed : 0x9e3779b9u) {}
  std::uint32_t next();
  double uniform();  // [0, 1), 24 bits
  double normal();   // standard normal (Box-Muller, one value per call)

 private:
  std::uint32_t state_;
};

// The swing a computer golfer actually makes when it means to make `planned`.
// Draws exactly three normals and, for a full swing, one uniform (two more
// on a mishit), in that order.
SwingInput execute_swing(const SwingInput& planned, bool putter, const SkillProfile& skill, OpponentRng& rng);

// Average strokes a good player takes to hole out from `distance_m` with the
// ball on `lie`; how the computer scores where a shot ends up. Rounded from
// published tour "strokes gained" baselines. Water and out of bounds aren't
// lies; callers add their penalties.
double expected_strokes(double distance_m, Surface lie);

}  // namespace olcore
