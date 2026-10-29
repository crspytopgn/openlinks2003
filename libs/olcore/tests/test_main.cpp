// Minimal self-contained test runner so the core library has no dependencies.
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/scoring.hpp"
#include "olcore/shot.hpp"
#include "olcore/swing.hpp"

namespace {

int g_failures = 0;

#define CHECK(cond)                                                    \
  do {                                                                 \
    if (!(cond)) {                                                     \
      std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
      ++g_failures;                                                    \
    }                                                                  \
  } while (0)

#define CHECK_NEAR(a, b, tol)                                                                     \
  do {                                                                                            \
    double _a = (a), _b = (b);                                                                    \
    if (std::fabs(_a - _b) > (tol)) {                                                             \
      std::printf("  FAIL %s:%d: %s = %f, expected %f +/- %f\n", __FILE__, __LINE__, #a, _a, _b, \
                  static_cast<double>(tol));                                                      \
      ++g_failures;                                                                               \
    }                                                                                             \
  } while (0)

using namespace olcore;

void test_reader_little_endian() {
  BinaryReader r({0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x80, 0x3f, 'L', 'N', 'K', 0, 0, 0});
  CHECK(r.u16() == 0x0201);
  CHECK(r.u16() == 0x0403);
  CHECK_NEAR(r.f32(), 1.0, 0.0);
  CHECK(r.fixed_string(6) == "LNK");
  CHECK(r.remaining() == 0);
}

void test_reader_bounds() {
  BinaryReader r({0x01, 0x02, 0x03});
  bool threw = false;
  try {
    r.u32();
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
  CHECK(r.tell() == 0);  // a failed read must not move the cursor
}

void test_vacuum_matches_projectile_formula() {
  BallParams p;
  p.air_density = 0;  // no drag, no lift
  double v = 50, angle = 30;
  FlightResult r = simulate_flight(make_launch(v, angle, 0, 0, 0), p);
  double rad = angle * 3.14159265358979323846 / 180.0;
  double expected = v * v * std::sin(2 * rad) / p.gravity;
  CHECK_NEAR(r.carry_m, expected, 0.05);
}

void test_backspin_adds_carry() {
  BallParams p;
  FlightResult low = simulate_flight(make_launch(70, 11, 0, 500, 0), p);
  FlightResult high = simulate_flight(make_launch(70, 11, 0, 2700, 0), p);
  CHECK(high.carry_m > low.carry_m);
  CHECK(high.apex_m > low.apex_m);
}

void test_positive_sidespin_curves_left() {
  BallParams p;
  FlightResult r = simulate_flight(make_launch(70, 11, 0, 2700, 800), p);
  CHECK(r.landing.position.x > 1.0);  // +x is left
  FlightResult straight = simulate_flight(make_launch(70, 11, 0, 2700, 0), p);
  CHECK_NEAR(straight.landing.position.x, 0.0, 1e-6);
}

void test_driver_carry_is_plausible() {
  // ~157 mph ball speed, 11 deg launch, 2700 rpm. The placeholder constants
  // carry this ~205 m; the bounds only guard against sign and unit errors
  // until the model is tuned to match the original game.
  BallParams p;
  FlightResult r = simulate_flight(make_launch(70, 11, 0, 2700, 0), p);
  std::printf("  driver: carry %.1f m, apex %.1f m, time %.2f s\n", r.carry_m, r.apex_m, r.flight_time_s);
  CHECK(r.carry_m > 200 && r.carry_m < 300);
  CHECK(r.apex_m > 20 && r.apex_m < 50);
}

// A plane rising by `grade` metres per metre towards +z.
class SlopeTerrain : public Terrain {
 public:
  SlopeTerrain(double grade, Surface s) : grade_(grade), surface_(s) {}
  double height(double, double z) const override { return grade_ * z; }
  Surface surface(double, double) const override { return surface_; }

 private:
  double grade_;
  Surface surface_;
};

const Club& club(const char* short_name) {
  for (const Club& c : standard_clubs()) {
    if (std::string(c.short_name) == short_name) {
      return c;
    }
  }
  std::printf("  no club %s\n", short_name);
  return standard_clubs().front();
}

void test_drive_bounces_and_rolls() {
  BallParams p;
  FlatTerrain ground(Surface::Fairway);
  ShotResult r = simulate_shot(launch_from_swing(club("Dr"), {}, Surface::Tee), p, ground);
  std::printf("  drive: carry %.2f m, total %.2f m, %d bounces, %.2f s\n", r.carry_m, r.total_m, r.bounces,
              r.time_s);
  CHECK(r.outcome == ShotOutcome::Rest);
  CHECK(r.bounces >= 2);
  CHECK(r.total_m > r.carry_m + 10);
  CHECK(r.total_m < r.carry_m + 80);
  CHECK_NEAR(r.rest.y, 0.0, 1e-9);
}

void test_club_distances_decrease() {
  BallParams p;
  FlatTerrain ground(Surface::Fairway);
  double previous = 1e9;
  for (const Club& c : standard_clubs()) {
    if (c.putter) {
      continue;
    }
    ShotResult r = simulate_shot(launch_from_swing(c, {}, Surface::Fairway), p, ground);
    CHECK(r.carry_m < previous);
    previous = r.carry_m;
  }
}

void test_wedge_checks_on_green() {
  BallParams p;
  FlatTerrain green(Surface::Green);
  ShotResult r = simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, green);
  std::printf("  wedge: carry %.2f m, total %.2f m\n", r.carry_m, r.total_m);
  CHECK(std::fabs(r.total_m - r.carry_m) < 6.0);
}

void test_rough_and_sand_cost_distance() {
  BallParams p;
  FlatTerrain ground(Surface::Fairway);
  const Club& c = club("7i");
  double fairway = simulate_shot(launch_from_swing(c, {}, Surface::Fairway), p, ground).carry_m;
  double rough = simulate_shot(launch_from_swing(c, {}, Surface::Rough), p, ground).carry_m;
  double sand = simulate_shot(launch_from_swing(c, {}, Surface::Sand), p, ground).carry_m;
  CHECK(rough < fairway);
  CHECK(sand < rough);
}

void test_swing_accuracy_curves_ball() {
  BallParams p;
  FlatTerrain ground(Surface::Fairway);
  ShotResult hook = simulate_shot(launch_from_swing(club("7i"), {1.0, -0.5, 0.0}, Surface::Fairway), p, ground);
  ShotResult slice = simulate_shot(launch_from_swing(club("7i"), {1.0, 0.5, 0.0}, Surface::Fairway), p, ground);
  CHECK(hook.rest.x > 5);    // early = left
  CHECK(slice.rest.x < -5);  // late = right
  CHECK_NEAR(hook.rest.x, -slice.rest.x, 1e-6);
}

void test_putt_drops_at_holing_speed() {
  BallParams p;
  FlatTerrain green(Surface::Green);
  ShotOptions opt;
  opt.has_cup = true;
  opt.cup = {0, 0, 3};
  ShotResult in = simulate_shot(make_launch(2.0, 0, 0, 0, 0), p, green, opt);
  CHECK(in.outcome == ShotOutcome::Holed);
  CHECK_NEAR(in.rest.z, 3.0, 1e-9);

  ShotResult lip = simulate_shot(make_launch(5.0, 0, 0, 0, 0), p, green, opt);
  CHECK(lip.outcome == ShotOutcome::Rest);  // too fast, runs over the hole
  CHECK(lip.rest.z > 3.0);

  ShotResult wide = simulate_shot(make_launch(2.0, 0, 5, 0, 0), p, green, opt);
  CHECK(wide.outcome == ShotOutcome::Rest);
}

void test_putt_distance_follows_green_speed() {
  // Rolling resistance alone: d = v^2 / (2 c g).
  BallParams p;
  FlatTerrain green(Surface::Green);
  ShotResult r = simulate_shot(make_launch(3.0, 0, 0, 0, 0), p, green);
  double expected = 9.0 / (2 * surface_params(Surface::Green).rolling_resistance * p.gravity);
  CHECK_NEAR(r.total_m, expected, 0.05);
}

void test_ball_rolls_downhill() {
  BallParams p;
  SlopeTerrain hill(0.1, Surface::Green);
  ShotResult r = simulate_shot(BallState{{0, 1.0, 10.0}, {0, 0, 0}, {0, 0, 0}}, p, hill);
  CHECK(r.rest.z < 10.0);  // ran back down the slope
  CHECK(r.outcome == ShotOutcome::TimedOut || r.outcome == ShotOutcome::Rest);

  SlopeTerrain gentle(0.02, Surface::Green);
  ShotResult held = simulate_shot(BallState{{0, 0.2, 10.0}, {0, 0, 0}, {0, 0, 0}}, p, gentle);
  CHECK(held.outcome == ShotOutcome::Rest);
  CHECK_NEAR(held.rest.z, 10.0, 1e-9);
}

void test_water_and_out_of_bounds_stop_the_ball() {
  BallParams p;
  FlatTerrain pond(Surface::Water);
  ShotResult wet = simulate_shot(launch_from_swing(club("7i"), {}, Surface::Fairway), p, pond);
  CHECK(wet.outcome == ShotOutcome::Water);
  CHECK(wet.bounces == 0);
  FlatTerrain ob(Surface::OutOfBounds);
  CHECK(simulate_shot(launch_from_swing(club("7i"), {}, Surface::Fairway), p, ob).outcome ==
        ShotOutcome::OutOfBounds);
}

void test_scorecard() {
  CHECK(score_name(1, 3) == "Hole in one");
  CHECK(score_name(3, 4) == "Birdie");
  CHECK(score_name(4, 4) == "Par");
  CHECK(score_name(2, 5) == "Albatross");
  CHECK(score_name(6, 4) == "Double bogey");
  CHECK(score_name(9, 4) == "+5");
  Scorecard card({4, 3, 5});
  card.record(0, 5);
  card.record(1, 2);
  CHECK(card.total_strokes() == 7);
  CHECK(card.holes_played() == 2);
  CHECK(card.to_par() == 0);
  CHECK(format_to_par(card.to_par()) == "E");
  card.record(2, 7);
  CHECK(format_to_par(card.to_par()) == "+2");
  CHECK(format_to_par(-3) == "-3");
}

}  // namespace

int main() {
  std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"reader_little_endian", test_reader_little_endian},
      {"reader_bounds", test_reader_bounds},
      {"vacuum_matches_projectile_formula", test_vacuum_matches_projectile_formula},
      {"backspin_adds_carry", test_backspin_adds_carry},
      {"positive_sidespin_curves_left", test_positive_sidespin_curves_left},
      {"driver_carry_is_plausible", test_driver_carry_is_plausible},
      {"drive_bounces_and_rolls", test_drive_bounces_and_rolls},
      {"club_distances_decrease", test_club_distances_decrease},
      {"wedge_checks_on_green", test_wedge_checks_on_green},
      {"rough_and_sand_cost_distance", test_rough_and_sand_cost_distance},
      {"swing_accuracy_curves_ball", test_swing_accuracy_curves_ball},
      {"putt_drops_at_holing_speed", test_putt_drops_at_holing_speed},
      {"putt_distance_follows_green_speed", test_putt_distance_follows_green_speed},
      {"ball_rolls_downhill", test_ball_rolls_downhill},
      {"water_and_out_of_bounds_stop_the_ball", test_water_and_out_of_bounds_stop_the_ball},
      {"scorecard", test_scorecard},
  };
  for (auto& [name, fn] : tests) {
    std::printf("%s\n", name.c_str());
    fn();
  }
  if (g_failures) {
    std::printf("%d check(s) failed\n", g_failures);
    return 1;
  }
  std::printf("all tests passed\n");
  return 0;
}
