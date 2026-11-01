#pragma once

#include <cstdint>

#include "olcore/links_launch.hpp"
#include "olcore/swing.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// Computer opponents. A computer golfer plans a shot through the same physics
// as the player (the game shell searches clubs, aims and power with its
// ShotModel), then swings it with its own mistakes: the error is in the
// swing inputs (power, timing, aim), never in the ball physics, so the
// computer plays by the same rules as everyone else.
//
// How big the mistakes are comes from real-world numbers (GolferStats): how
// far and how straight the golfer drives, how close approaches and chips
// finish, how many eight-footers drop. golfer_profile turns those into swing
// errors, calibrated on flat ground through the physics so that a golfer
// with the PGA Tour's average numbers drives, approaches, chips and putts
// like the average tour pro (tests: opponent_matches_tour_numbers). The
// GDScript port is game/scripts/ai/opponent_skill.gd; keep the two in step.

enum class SkillLevel { Beginner = 0, Club, Scratch, Tour };
constexpr int kSkillLevelCount = 4;

// The kinds of shot a golfer is rated on.
enum class ShotKind { Drive = 0, Approach, Chip, Putt };
constexpr int kShotKindCount = 4;

// Inside this distance (metres) a full swing that isn't a putt is a chip or
// pitch, rated by chip_ft.
constexpr double kChipRangeM = 45.0;

// How a golfer plays, in the numbers tour statistics use. The PGA Tour's
// averages (ShotLink, 2015 to 2024 seasons) are in brackets.
struct GolferStats {
  double drive_yd = 300;      // average drive, yards [about 300]
  double fairways_pct = 60;   // tee shots that finish in a 30-yard fairway [60]
  double approach_ft = 27;    // average distance from the hole after an
                              // approach from 150 yards in the fairway, feet [27]
  double chip_ft = 6.5;       // the same after a chip from 20 yards [6.5]
  double putt8_pct = 50;      // putts holed from 8 feet [50]
  double mishit_pct = 0.2;    // full swings duffed or topped
};

// One kind of shot's swing errors (standard deviations).
struct ShotError {
  double power_sd = 0;     // power, as a fraction of the planned power
  double accuracy_sd = 0;  // timing on the -1..1 scale (curve); unused on putts
  double aim_sd_deg = 0;   // lining up, or a putt's line
};

struct GolferProfile {
  ShotError shots[kShotKindCount];  // by ShotKind
  double mishit_chance = 0;          // chance a full swing is a duff or a top
  double strength = 1;               // the most power it swings with (the meter's 0..1)
  double links_strength = 1;         // the same with Links 2003's physics
  // The same golfer for Links 2003's own computer miss generators (Classic
  // computer golfers): each rating is the one that gives the golfer's own
  // fairways, approaches, chips and eight-footers with the game's physics.
  LinksGolferRatings links;
};

// The numbers behind the four skill levels: amateurs of about 18 and 9
// handicap (Broadie, "Every Shot Counts", and Arccos amateur data), a
// scratch golfer and the average tour pro.
GolferStats level_stats(SkillLevel level);
const char* skill_name(SkillLevel level);

// Swing errors (and Links ratings) for a golfer with these numbers.
GolferProfile golfer_profile(const GolferStats& stats);

// With Links 2003's physics a computer golfer's timing error turns the face
// by this many degrees at +/-1 (LinksShotModel.COMPUTER_FACE_ERROR_DEG), and
// each kind of error is scaled by links_error_scale, so that the same golfer
// hits the same numbers as with the standard physics.
constexpr double kLinksFaceDegPerAccuracy = 4.5;
double links_error_scale(ShotKind kind);

// The shot a swing counts as: a putt; a chip inside kChipRangeM; a drive
// with a wood from the tee; anything else is an approach.
ShotKind shot_kind(bool putter, bool teed_up, bool wood, double distance_m);

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

// The swing a computer golfer actually makes when it means to make
// `planned`. `error_scale` multiplies every error (form and pressure; 1 is
// the golfer's usual). Draws exactly three normals and, for a full swing, one
// uniform (two more on a mishit), in that order.
SwingInput execute_shot(const SwingInput& planned, ShotKind kind, const GolferProfile& golfer, double error_scale,
                        OpponentRng& rng);

// Average strokes a good player takes to hole out from `distance_m` with the
// ball on `lie`; how the computer scores where a shot ends up. Rounded from
// published tour "strokes gained" baselines. Water and out of bounds aren't
// lies; callers add their penalties.
double expected_strokes(double distance_m, Surface lie);

}  // namespace olcore
