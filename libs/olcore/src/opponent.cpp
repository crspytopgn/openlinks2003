#include "olcore/opponent.hpp"

#include <algorithm>
#include <cmath>
#include <iterator>

namespace olcore {

namespace {

constexpr double kPi = 3.14159265358979323846;

const char* const kLevelNames[kSkillLevelCount] = {"Weekend golfer", "Club golfer", "Scratch golfer", "Tour pro"};

// drive yd, fairways %, approach ft (150 yd), chip ft (20 yd), putts holed
// from 8 ft %, mishits %
const GolferStats kLevelStats[kSkillLevelCount] = {
    {220, 45, 60, 14, 33, 6.0},
    {245, 50, 44, 10, 40, 2.5},
    {270, 56, 33, 7.8, 45, 0.8},
    {300, 60, 27, 6.5, 50, 0.2},
};

// The longest drivers on tour average about this; they swing at full power.
constexpr double kLongestDriveYd = 320.0;

struct Point {
  double x;
  double y;
};

double interpolate(const Point* table, std::size_t n, double x, double slope_past_end) {
  if (x <= table[0].x) {
    return table[0].y;
  }
  for (std::size_t i = 1; i < n; ++i) {
    if (x <= table[i].x) {
      double f = (x - table[i - 1].x) / (table[i].x - table[i - 1].x);
      return table[i - 1].y + f * (table[i].y - table[i - 1].y);
    }
  }
  return table[n - 1].y + (x - table[n - 1].x) * slope_past_end;
}

// Calibration tables, measured with tools/olcalibrate through the standard
// physics on flat ground (see docs/game-shell.md#computer-golfers).
// Fairways hit (%) against the drive's timing error; the aim error is 3.5
// times it and the power error 0.17 times it.
const Point kFairways[] = {{21.6, 0.750}, {22.7, 0.700}, {24.1, 0.650}, {26.0, 0.600}, {28.0, 0.550}, {30.8, 0.500}, {34.0, 0.450}, {37.6, 0.400}, {42.2, 0.350}, {48.5, 0.300}, {56.2, 0.250}, {65.5, 0.200}, {78.2, 0.150}, {94.0, 0.100}};
// Proximity (ft) from 150 yards against the scale of the approach errors
// (power 0.06, timing 0.30, aim 1.8 degrees at 1).
const Point kApproach[] = {{16.8, 0.600}, {21.7, 0.800}, {26.4, 1.000}, {31.2, 1.200}, {35.9, 1.400}, {40.5, 1.600}, {44.9, 1.800}, {49.2, 2.000}, {53.4, 2.200}, {57.5, 2.400}, {61.5, 2.600}, {65.4, 2.800}, {69.2, 3.000}, {73.0, 3.200}, {76.8, 3.400}};
// Proximity (ft) from 20 yards against the scale of the chip errors (power
// 0.07, timing 0.25, aim 2.2 degrees at 1).
const Point kChip[] = {{4.0, 0.600}, {5.3, 0.800}, {6.6, 1.000}, {7.9, 1.200}, {9.2, 1.400}, {10.5, 1.600}, {11.8, 1.800}, {13.1, 2.000}, {14.4, 2.200}, {15.7, 2.400}, {17.0, 2.600}, {18.2, 2.800}, {19.5, 3.000}, {20.7, 3.200}, {22.0, 3.400}};
// Eight-footers holed (%) against the putt's line error (degrees); the pace
// error is 0.025 times it.
const Point kPutt8[] = {{21.2, 3.800}, {22.8, 3.600}, {24.3, 3.400}, {26.4, 3.200}, {28.1, 3.000}, {30.9, 2.800}, {33.8, 2.600}, {36.6, 2.400}, {39.8, 2.200}, {44.0, 2.000}, {49.1, 1.800}, {55.0, 1.600}, {62.4, 1.400}, {70.5, 1.200}};

// Links 2003's computer ratings (links_computer_miss, links_computer_putt_miss)
// against the same numbers, measured with the game's physics: fairways (%),
// approach and chip proximity (ft) and eight-footers holed (%). The game's
// own putting holes every putt inside 5 ft, so a Classic golfer's putting is
// set by its eight-footers alone.
const Point kLinksTee[] = {{2.7, 0}, {3.2, 5}, {3.5, 10}, {3.9, 15}, {5.3, 20}, {6.4, 25}, {8.0, 30}, {9.9, 35}, {10.5, 40}, {12.4, 45}, {16.9, 50}, {21.6, 55}, {29.0, 60}, {37.9, 65}, {50.1, 70}, {68.8, 75}, {86.6, 80}, {98.4, 85}, {100.0, 90}};
const Point kLinksApproach[] = {{0.0, 100}, {1.6, 95}, {4.3, 90}, {7.3, 85}, {10.8, 80}, {12.8, 75}, {14.4, 70}, {18.0, 65}, {18.4, 60}, {20.8, 55}, {22.8, 50}, {24.5, 45}, {26.6, 40}, {28.9, 35}, {31.1, 30}, {37.2, 20}, {40.1, 10}, {41.9, 5}, {44.2, 0}};
const Point kLinksChip[] = {{0.0, 100}, {0.9, 95}, {1.7, 90}, {2.4, 85}, {4.1, 80}, {4.5, 75}, {6.5, 70}, {7.3, 65}, {8.4, 60}, {9.2, 50}, {10.0, 45}, {11.1, 40}, {11.7, 35}, {13.9, 30}, {14.1, 25}, {16.9, 15}, {18.9, 0}};
const Point kLinksPutt8[] = {{41.2, 0}, {42.9, 5}, {46.9, 10}, {50.3, 15}, {53.0, 20}, {55.9, 25}, {63.8, 30}, {69.0, 35}, {72.8, 40}, {79.7, 45}, {83.9, 50}, {89.0, 55}, {92.8, 60}, {96.3, 65}, {99.0, 70}, {100.0, 75}};

// Putts to hole out from a distance in feet.
const Point kGreen[] = {
    {0, 1.0}, {2, 1.01}, {3, 1.04}, {5, 1.23}, {8, 1.50}, {10, 1.61},
    {15, 1.78}, {20, 1.87}, {30, 1.98}, {40, 2.06}, {60, 2.20}, {90, 2.40},
};

// Strokes from the fairway at a distance in yards.
const Point kFairway[] = {
    {0, 1.9},    {10, 2.18},  {20, 2.40},  {40, 2.60},  {60, 2.70},  {100, 2.80},
    {150, 2.98}, {200, 3.19}, {250, 3.45}, {300, 3.71}, {400, 4.08}, {500, 4.50},
};

}  // namespace

GolferStats level_stats(SkillLevel level) {
  return kLevelStats[std::clamp(static_cast<int>(level), 0, kSkillLevelCount - 1)];
}

const char* skill_name(SkillLevel level) {
  return kLevelNames[std::clamp(static_cast<int>(level), 0, kSkillLevelCount - 1)];
}

GolferProfile golfer_profile(const GolferStats& st) {
  GolferProfile g;
  // The table is for the longest drivers; a shorter, slower drive curves
  // less, so it needs a bigger timing error to miss the fairway as often.
  double reach = std::clamp(st.drive_yd / kLongestDriveYd, 0.3, 1.0);
  double drive = interpolate(kFairways, std::size(kFairways), st.fairways_pct, 0.0) / std::pow(reach, 1.7);
  g.shots[0] = {0.17 * drive, drive, 3.5 * drive};
  // The tables leave out mishits; a duffed approach from 150 yards adds
  // about 150 ft to the average.
  double mishit = std::clamp(st.mishit_pct / 100.0, 0.0, 0.5);
  double approach = interpolate(kApproach, std::size(kApproach), std::max(5.0, st.approach_ft - 150.0 * mishit), 0.0);
  g.shots[1] = {0.06 * approach, 0.30 * approach, 1.8 * approach};
  double chip = interpolate(kChip, std::size(kChip), st.chip_ft, 0.0);
  g.shots[2] = {0.07 * chip, 0.25 * chip, 2.2 * chip};
  double line = interpolate(kPutt8, std::size(kPutt8), st.putt8_pct, 0.0);
  g.shots[3] = {0.025 * line, 0.0, line};
  g.mishit_chance = mishit;
  // A drive goes about as the power to the 0.69 with the standard physics,
  // so the power is the distance to the 1.45; with Links 2003's it is close
  // to in proportion.
  g.strength = std::clamp(std::pow(reach, 1.45), 0.2, 1.0);
  g.links_strength = reach;
  auto rating = [](const Point* t, std::size_t n, double x) {
    return static_cast<int>(std::lround(std::clamp(interpolate(t, n, x, 0.0), 0.0, 100.0)));
  };
  g.links.tee = rating(kLinksTee, std::size(kLinksTee), st.fairways_pct);
  int irons = rating(kLinksApproach, std::size(kLinksApproach), st.approach_ft);
  g.links.woods = irons;
  g.links.long_irons = irons;
  g.links.mid_irons = irons;
  g.links.short_irons = irons;
  g.links.wedges = irons;
  g.links.chips = rating(kLinksChip, std::size(kLinksChip), st.chip_ft);
  int putts = rating(kLinksPutt8, std::size(kLinksPutt8), st.putt8_pct);
  g.links.long_putts = putts;
  g.links.short_putts = putts;
  g.links.max_power = static_cast<int>(std::lround(100.0 * g.strength));
  return g;
}

double links_error_scale(ShotKind kind) {
  // Measured with tools/olcalibrate: with these (and a face error of
  // kLinksFaceDegPerAccuracy) Links 2003's physics gives the same numbers.
  static const double kScale[kShotKindCount] = {1.0, 0.9, 1.0, 0.9};
  return kScale[std::clamp(static_cast<int>(kind), 0, kShotKindCount - 1)];
}

ShotKind shot_kind(bool putter, bool teed_up, bool wood, double distance_m) {
  if (putter) {
    return ShotKind::Putt;
  }
  if (distance_m < kChipRangeM) {
    return ShotKind::Chip;
  }
  return teed_up && wood ? ShotKind::Drive : ShotKind::Approach;
}

std::uint32_t OpponentRng::next() {
  std::uint32_t x = state_;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  state_ = x;
  return x;
}

double OpponentRng::uniform() { return static_cast<double>(next() >> 8) / 16777216.0; }

double OpponentRng::normal() {
  double u1 = 1.0 - uniform();  // (0, 1]
  double u2 = uniform();
  return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * kPi * u2);
}

SwingInput execute_shot(const SwingInput& planned, ShotKind kind, const GolferProfile& golfer, double error_scale,
                        OpponentRng& rng) {
  SwingInput out = planned;
  const ShotError& e = golfer.shots[std::clamp(static_cast<int>(kind), 0, kShotKindCount - 1)];
  double k = std::max(0.0, error_scale);
  if (kind == ShotKind::Putt) {
    double pace = rng.normal();
    double line = rng.normal();
    rng.normal();  // keeps the draws the same as a full swing's
    out.power = std::clamp(planned.power * (1.0 + pace * e.power_sd * k), 0.0, 1.0);
    out.aim_deg = planned.aim_deg + line * e.aim_sd_deg * k;
    return out;
  }
  double power = rng.normal();
  double timing = rng.normal();
  double aim = rng.normal();
  out.power = planned.power * (1.0 + power * e.power_sd * k);
  out.accuracy = planned.accuracy + timing * e.accuracy_sd * k;
  out.aim_deg = planned.aim_deg + aim * e.aim_sd_deg * k;
  if (rng.uniform() < golfer.mishit_chance * std::min(k, 2.0)) {
    // A duff or a top: well short, and often off line.
    out.power *= 0.35 + 0.35 * rng.uniform();
    out.accuracy += (rng.uniform() - 0.5) * 1.2;
  }
  out.power = std::clamp(out.power, 0.0, 1.0);
  out.accuracy = std::clamp(out.accuracy, -1.0, 1.0);
  return out;
}

double expected_strokes(double distance_m, Surface lie) {
  constexpr double kYardsPerMetre = 1.0936133;
  constexpr double kFeetPerMetre = 3.2808399;
  double green = interpolate(kGreen, std::size(kGreen), distance_m * kFeetPerMetre, 0.004);
  double fairway = interpolate(kFairway, std::size(kFairway), distance_m * kYardsPerMetre, 0.0045);
  switch (lie) {
    case Surface::Green:
      return green;
    case Surface::Fringe:
      return std::min(green + 0.1, fairway);
    case Surface::Rough:
      return fairway + 0.2;
    case Surface::DeepRough:
      return fairway + 0.45;
    case Surface::Sand:
      return fairway + 0.35;
    default:
      return fairway;
  }
}

}  // namespace olcore
