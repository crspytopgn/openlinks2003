#include "olcore/opponent.hpp"

#include <algorithm>
#include <cmath>
#include <iterator>

namespace olcore {

namespace {

constexpr double kPi = 3.14159265358979323846;

const SkillProfile kProfiles[kSkillLevelCount] = {
    // name, power sd, accuracy sd, aim sd, putt pace sd, putt aim sd, mishit, strength, management
    {"Weekend golfer", 0.075, 0.60, 2.0, 0.160, 1.90, 0.060, 0.80, false},
    {"Club golfer", 0.055, 0.38, 1.4, 0.110, 1.50, 0.025, 0.88, true},
    {"Scratch golfer", 0.040, 0.26, 1.0, 0.080, 1.25, 0.008, 0.95, true},
    {"Tour pro", 0.030, 0.18, 0.8, 0.060, 1.00, 0.002, 1.00, true},
};

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

const SkillProfile& skill_profile(SkillLevel level) {
  int i = std::clamp(static_cast<int>(level), 0, kSkillLevelCount - 1);
  return kProfiles[i];
}

const char* skill_name(SkillLevel level) { return skill_profile(level).name; }

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

SwingInput execute_swing(const SwingInput& planned, bool putter, const SkillProfile& skill, OpponentRng& rng) {
  SwingInput out = planned;
  if (putter) {
    double pace = rng.normal();
    double line = rng.normal();
    rng.normal();  // keeps the draws the same as a full swing's
    out.power = std::clamp(planned.power * (1.0 + pace * skill.putt_power_sd), 0.0, 1.0);
    out.aim_deg = planned.aim_deg + line * skill.putt_aim_sd_deg;
    return out;
  }
  double power = rng.normal();
  double timing = rng.normal();
  double aim = rng.normal();
  out.power = planned.power * (1.0 + power * skill.power_sd);
  out.accuracy = planned.accuracy + timing * skill.accuracy_sd;
  out.aim_deg = planned.aim_deg + aim * skill.aim_sd_deg;
  if (rng.uniform() < skill.mishit_chance) {
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
