// Minimal self-contained test runner so the core library has no dependencies.
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/binary_reader.hpp"

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
  // carry this ~210 m; the bounds only guard against sign and unit errors
  // until the model is tuned to match the original game.
  BallParams p;
  FlightResult r = simulate_flight(make_launch(70, 11, 0, 2700, 0), p);
  std::printf("  driver: carry %.1f m, apex %.1f m, time %.2f s\n", r.carry_m, r.apex_m, r.flight_time_s);
  CHECK(r.carry_m > 200 && r.carry_m < 300);
  CHECK(r.apex_m > 20 && r.apex_m < 50);
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
