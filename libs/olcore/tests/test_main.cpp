// Minimal self-contained test runner so the core library has no dependencies.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "olcore/arc0.hpp"
#include "olcore/ball_physics.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/inflate.hpp"

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


// zlib streams below were made with a stock zlib so the decoder is checked
// against an independent encoder; none of this is game data.
void test_inflate_fixed_block() {
  const std::vector<std::uint8_t> z = {0x78, 0xda, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0x40, 0xa2,
                                       0x14, 0x72, 0x32, 0xf3, 0xb2, 0x8b, 0x01, 0x74, 0x39, 0x09, 0x16};
  std::size_t used = 0;
  auto out = zlib_decompress(z, &used);
  CHECK(std::string(out.begin(), out.end()) == "hello, hello, hello links");
  CHECK(used == z.size());
}

void test_inflate_dynamic_block() {
  const std::vector<std::uint8_t> z = {
      0x78, 0xda, 0x75, 0xd4, 0x4b, 0x0a, 0xc2, 0x40, 0x10, 0x84, 0xe1, 0xab, 0xe4, 0x08, 0xe9, 0xee, 0x79, 0xe2, 0x69,
      0x14, 0xe2, 0x03, 0x41, 0x21, 0x20, 0xe2, 0xed, 0x75, 0xd1, 0x83, 0x50, 0x5d, 0xb3, 0xca, 0xa6, 0x08, 0x1f, 0xfd,
      0x87, 0x9c, 0x8f, 0xb7, 0xfd, 0x7d, 0xfc, 0x2c, 0xeb, 0x72, 0xd9, 0xb7, 0xed, 0xf1, 0x7b, 0xee, 0xcf, 0xd7, 0xe5,
      0xfa, 0x7b, 0x9e, 0x5e, 0x8f, 0xfb, 0xb6, 0x1f, 0x96, 0xb3, 0x2f, 0xc4, 0x17, 0xd5, 0x17, 0x16, 0x16, 0xea, 0x0b,
      0xf1, 0x85, 0x84, 0x85, 0xf9, 0xa2, 0xf9, 0x22, 0x85, 0x45, 0xf2, 0x85, 0xfa, 0x42, 0xc3, 0x22, 0xfb, 0xa2, 0x4f,
      0xa5, 0xc5, 0x17, 0x36, 0x95, 0xd6, 0x21, 0x5d, 0xa7, 0xd4, 0xe6, 0x93, 0x34, 0xa5, 0xf6, 0xf1, 0x12, 0x99, 0x5a,
      0x65, 0x9c, 0x35, 0xcf, 0xcf, 0x3a, 0xee, 0x2a, 0x3a, 0xe5, 0xca, 0xb8, 0x6c, 0x99, 0x72, 0xc5, 0x20, 0x60, 0xf4,
      0x4a, 0x82, 0x82, 0xc4, 0x9b, 0x21, 0x21, 0xf1, 0x16, 0x68, 0x48, 0xb8, 0x15, 0x22, 0x12, 0x6e, 0x83, 0x8a, 0x84,
      0xdb, 0x21, 0x63, 0xe4, 0xea, 0x8a, 0x1d, 0xa3, 0x57, 0x05, 0x42, 0x92, 0xef, 0x56, 0xb1, 0x64, 0x04, 0xab, 0x41,
      0xc9, 0x08, 0xd6, 0x84, 0x25, 0x89, 0x38, 0x43, 0x49, 0x02, 0x2e, 0x50, 0x92, 0x80, 0x2b, 0x94, 0x24, 0xde, 0x06,
      0x25, 0x89, 0xb7, 0x43, 0xc9, 0xc8, 0xb5, 0x15, 0x4a, 0x46, 0xae, 0x09, 0x94, 0x8c, 0x5c, 0x53, 0x28, 0x49, 0x7e,
      0x0c, 0x86, 0x25, 0xa3, 0xd7, 0x12, 0x94, 0x24, 0xde, 0x8c, 0x25, 0x09, 0xb8, 0x40, 0x49, 0x02, 0xae, 0x58, 0x92,
      0x88, 0x1b, 0x94, 0x24, 0xe0, 0x0e, 0x25, 0xff, 0xe0, 0x2f, 0x2d, 0x53, 0xcf, 0x71};
  std::string expected;
  char line[64];
  for (int i = 0; i < 40; ++i) {
    std::snprintf(line, sizeof line, "fairway %d green %d rough %d bunker; ", i, i * 7 % 13, i * 3 % 5);
    expected += line;
  }
  // A second stream right behind the first must not be swallowed.
  std::vector<std::uint8_t> two = z;
  two.insert(two.end(), z.begin(), z.end());
  std::size_t used = 0;
  auto out = zlib_decompress(two, &used);
  CHECK(std::string(out.begin(), out.end()) == expected);
  CHECK(used == z.size());
  auto second = zlib_decompress(two.data() + used, two.size() - used);
  CHECK(second == out);
}

void test_inflate_rejects_corruption() {
  std::vector<std::uint8_t> z = {0x78, 0xda, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0xc8, 0x40, 0xa2,
                                 0x14, 0x72, 0x32, 0xf3, 0xb2, 0x8b, 0x01, 0x74, 0x39, 0x09, 0x17};
  bool threw = false;
  try {
    zlib_decompress(z);
  } catch (const InflateError&) {
    threw = true;
  }
  CHECK(threw);
}

// zlib stream with one stored block, built by hand.
std::vector<std::uint8_t> stored_zlib(const std::string& s) {
  std::vector<std::uint8_t> z = {0x78, 0x01, 0x01};
  auto n = static_cast<std::uint16_t>(s.size());
  z.push_back(static_cast<std::uint8_t>(n & 0xff));
  z.push_back(static_cast<std::uint8_t>(n >> 8));
  z.push_back(static_cast<std::uint8_t>(~n & 0xff));
  z.push_back(static_cast<std::uint8_t>((~n >> 8) & 0xff));
  z.insert(z.end(), s.begin(), s.end());
  std::uint32_t a = adler32(reinterpret_cast<const std::uint8_t*>(s.data()), s.size());
  for (int sh = 24; sh >= 0; sh -= 8) z.push_back(static_cast<std::uint8_t>(a >> sh));
  return z;
}

void put_u32(std::vector<std::uint8_t>& v, std::uint32_t x) {
  for (int i = 0; i < 4; ++i) v.push_back(static_cast<std::uint8_t>(x >> (8 * i)));
}

void test_arc0_reads_entries() {
  const std::vector<std::string> names = {"Sample A.btc", "MasterObj"};
  const std::vector<std::string> bodies = {"first entry", "second"};
  std::vector<std::uint8_t> blob(16, 0);
  std::vector<std::uint32_t> offs, sizes;
  for (auto& b : bodies) {
    auto z = stored_zlib(b);
    offs.push_back(static_cast<std::uint32_t>(blob.size()));
    sizes.push_back(static_cast<std::uint32_t>(z.size()));
    blob.insert(blob.end(), z.begin(), z.end());
  }
  auto dir = static_cast<std::uint32_t>(blob.size());
  for (std::size_t i = 0; i < names.size(); ++i) {
    put_u32(blob, 0);
    std::string n = names[i];
    n.resize(32, '\0');
    blob.insert(blob.end(), n.begin(), n.end());
    put_u32(blob, offs[i]);
    put_u32(blob, sizes[i]);
    put_u32(blob, static_cast<std::uint32_t>(bodies[i].size()));
    put_u32(blob, 2);
    put_u32(blob, i == 0 ? adler32(reinterpret_cast<const std::uint8_t*>(bodies[i].data()), bodies[i].size()) : 0);
    put_u32(blob, 0);
    put_u32(blob, 0);
  }
  std::vector<std::uint8_t> head = {'A', 'R', 'C', '0'};
  put_u32(head, static_cast<std::uint32_t>(blob.size()));
  put_u32(head, static_cast<std::uint32_t>(names.size()));
  put_u32(head, dir);
  std::copy(head.begin(), head.end(), blob.begin());

  Arc0Archive a(blob);
  CHECK(a.entries().size() == 2);
  CHECK(a.entries()[0].name == "Sample A.btc");
  auto e = a.read("masterobj");
  CHECK(std::string(e.begin(), e.end()) == "second");
  e = a.read(0);
  CHECK(std::string(e.begin(), e.end()) == "first entry");
  CHECK(!a.find("missing"));
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
      {"inflate_fixed_block", test_inflate_fixed_block},
      {"inflate_dynamic_block", test_inflate_dynamic_block},
      {"inflate_rejects_corruption", test_inflate_rejects_corruption},
      {"arc0_reads_entries", test_arc0_reads_entries},
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
