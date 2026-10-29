// Minimal self-contained test runner so the core library has no dependencies.
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/carrera_store.hpp"
#include "olcore/ls_archive.hpp"
#include "olcore/lzw.hpp"
#include "olcore/ssf.hpp"
#include "olcore/wav.hpp"
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

// Little helpers for building synthetic files. Tests never use original
// game data (docs/clean-room.md).
using Bytes = std::vector<std::uint8_t>;

void put16(Bytes& b, std::uint32_t v) {
  b.push_back(static_cast<std::uint8_t>(v));
  b.push_back(static_cast<std::uint8_t>(v >> 8));
}

void put32(Bytes& b, std::uint32_t v) {
  for (int i = 0; i < 4; ++i) b.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
}

void put_str(Bytes& b, const std::string& s) { b.insert(b.end(), s.begin(), s.end()); }

void set32(Bytes& b, std::size_t at, std::uint32_t v) {
  for (int i = 0; i < 4; ++i) b[at + static_cast<std::size_t>(i)] = static_cast<std::uint8_t>(v >> (8 * i));
}

Bytes text(const std::string& s) { return Bytes(s.begin(), s.end()); }

Bytes pcm16_wav(const std::vector<std::int16_t>& samples) {
  Bytes b;
  put_str(b, "RIFF");
  put32(b, static_cast<std::uint32_t>(36 + samples.size() * 2));
  put_str(b, "WAVEfmt ");
  put32(b, 16);
  put16(b, 1);
  put16(b, 1);
  put32(b, 22050);
  put32(b, 44100);
  put16(b, 2);
  put16(b, 16);
  put_str(b, "data");
  put32(b, static_cast<std::uint32_t>(samples.size() * 2));
  for (auto v : samples) put16(b, static_cast<std::uint16_t>(v));
  return b;
}

void test_lzw_round_trip() {
  // Short, repetitive (exercises the KwKwK case), and long enough to fill
  // the dictionary and force a clear.
  std::vector<Bytes> inputs = {Bytes{}, text("A"), text("ABABABABABABAB"), Bytes(5000, 0x00)};
  Bytes noisy;
  std::uint32_t x = 12345;
  for (int i = 0; i < 200000; ++i) {
    x = x * 1103515245u + 12345u;
    noisy.push_back(static_cast<std::uint8_t>((x >> 16) % 23));
  }
  inputs.push_back(noisy);
  for (const auto& in : inputs) {
    Bytes packed = lzw_compress(in.data(), in.size());
    Bytes out = lzw_decompress(packed.data(), packed.size(), in.size() + 10);
    CHECK(out == in);
  }
}

void test_lzw_known_stream() {
  // Clear, 'R', 'I', then code 258 ("RI"), end; 9-bit codes LSB first.
  Bytes packed;
  std::uint64_t acc = 0;
  int bits = 0;
  for (int code : {256, int{'R'}, int{'I'}, 258, 257}) {
    acc |= static_cast<std::uint64_t>(code) << bits;
    bits += 9;
  }
  for (int i = 0; i < (bits + 7) / 8; ++i) packed.push_back(static_cast<std::uint8_t>(acc >> (8 * i)));
  CHECK(lzw_decompress(packed.data(), packed.size(), 100) == text("RIRI"));
  Bytes xored = packed;
  for (auto& b : xored) b ^= 5;
  CHECK(lzw_decompress(xored.data(), xored.size(), 100, true) == text("RIRI"));
}

// Builds a block header as described in docs/formats/ls-archive.md.
Bytes ls_block_header(const std::string& name, bool compressed, std::uint32_t original, std::uint32_t stored) {
  Bytes h(0x37, 0);
  h[0] = 'L';
  h[1] = 'S';
  h[2] = 'l';
  h[3] = 's';
  h[4] = 0x0b;
  h[5] = 0x02;
  h[6] = 0x37;
  h[0x18] = compressed ? 1 : 0;
  set32(h, 0x19, original);
  set32(h, 0x1d, stored);
  h[0x29] = static_cast<std::uint8_t>(name.size());
  for (std::size_t i = 0; i < name.size() && i < 12; ++i) h[0x2a + i] = static_cast<std::uint8_t>(name[i]);
  return h;
}

void test_ls_archive() {
  Bytes plain = text("stored entry");
  Bytes big;
  for (int i = 0; i < 300; ++i) put_str(big, "golf ");
  Bytes packed = lzw_compress(big.data(), big.size());

  const std::uint32_t capacity = 2 + 64;
  Bytes a = ls_block_header("~INDEX~", false, 64 * 17, capacity * 17);
  set32(a, 0x0a, 2);
  a[0x16] = static_cast<std::uint8_t>(capacity);
  std::size_t index = a.size();
  a.resize(index + capacity * 17, 0);
  std::size_t first = a.size();
  Bytes h1 = ls_block_header("PLAIN.TXT", false, static_cast<std::uint32_t>(plain.size()),
                             static_cast<std::uint32_t>(plain.size()));
  a.insert(a.end(), h1.begin(), h1.end());
  a.insert(a.end(), plain.begin(), plain.end());
  std::size_t second = a.size();
  Bytes h2 = ls_block_header("PACKED.TXT", true, static_cast<std::uint32_t>(big.size()),
                             static_cast<std::uint32_t>(packed.size()));
  a.insert(a.end(), h2.begin(), h2.end());
  a.insert(a.end(), packed.begin(), packed.end());
  std::string n1 = "PLAIN.TXT", n2 = "PACKED.TXT";
  std::copy(n1.begin(), n1.end(), a.begin() + static_cast<std::ptrdiff_t>(index));
  set32(a, index + 13, static_cast<std::uint32_t>(first));
  std::copy(n2.begin(), n2.end(), a.begin() + static_cast<std::ptrdiff_t>(index + 17));
  set32(a, index + 17 + 13, static_cast<std::uint32_t>(second));

  CHECK(LsArchive::looks_like(a));
  LsArchive archive(a);
  CHECK(archive.version() == LsArchive::kVersionShortNames);
  CHECK(archive.entries().size() == 2);
  CHECK(archive.read("plain.txt").value_or(Bytes{}) == plain);
  CHECK(archive.read("PACKED.TXT").value_or(Bytes{}) == big);
  CHECK(archive.entries()[1].compressed);
  CHECK(!archive.read("missing.txt").has_value());

  Bytes truncated(a.begin(), a.begin() + static_cast<std::ptrdiff_t>(second + 10));
  bool threw = false;
  try {
    LsArchive bad(truncated);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
}

void test_wav_pcm() {
  Bytes w = pcm16_wav({0, 1000, -1000, 32767});
  WavInfo info = parse_wav(w);
  CHECK(info.is_pcm());
  CHECK(info.channels == 1);
  CHECK(info.sample_rate == 22050);
  CHECK(info.data_offset == 44);
  auto s = decode_pcm16(w, info);
  CHECK(s.size() == 4);
  CHECK(s[2] == -1000);
  CHECK(s[3] == 32767);
}

void test_wav_ms_adpcm() {
  // One mono block: predictor 0 (coefficients 256, 0), step 16, seeds
  // sample1 = 100, sample2 = 50, then codes 1 and 0 in one byte.
  Bytes w;
  put_str(w, "RIFF");
  put32(w, 0);
  put_str(w, "WAVEfmt ");
  put32(w, 22 + 4);
  put16(w, 2);
  put16(w, 1);
  put32(w, 44100);
  put32(w, 0);
  put16(w, 8);
  put16(w, 4);
  put16(w, 6);  // cbSize
  put16(w, 4);  // samples per block
  put16(w, 1);  // one coefficient pair
  put16(w, 256);
  put16(w, 0);
  put_str(w, "data");
  put32(w, 8);
  w.push_back(0);
  put16(w, 16);
  put16(w, 100);
  put16(w, 50);
  w.push_back(0x10);
  WavInfo info = parse_wav(w);
  CHECK(info.format_tag == WavInfo::kMsAdpcm);
  CHECK(info.samples_per_block == 4);
  auto s = decode_pcm16(w, info);
  // 50 and 100 come out first; then 100 + 1 * 16 = 116, and code 0 repeats it.
  CHECK(s.size() == 4);
  CHECK(s.size() == 4 && s[0] == 50 && s[1] == 100 && s[2] == 116 && s[3] == 116);
}

void put_utf16(Bytes& b, const std::string& s, std::size_t chars) {
  for (std::size_t i = 0; i < chars; ++i) put16(b, i < s.size() ? static_cast<std::uint8_t>(s[i]) : 0);
}

void ssf_chunk(Bytes& b, const char tag[4], const Bytes& body) {
  b.insert(b.end(), tag, tag + 4);
  put32(b, static_cast<std::uint32_t>(body.size()));
  put32(b, 8);
  put32(b, 0);
  b.insert(b.end(), body.begin(), body.end());
}

void test_ssf() {
  Bytes f;
  put_str(f, std::string("SSF\0", 4));
  for (std::uint32_t v : {12u, 8u, 0u, 0u, 1u, 1u}) put32(f, v);

  Bytes eve;
  put32(eve, 1);
  put_utf16(eve, "Splash", 32);
  put32(eve, 100);  // chance
  put32(eve, 7);    // type
  put32(eve, 0);
  put32(eve, 0);
  put32(eve, 0);
  put32(eve, 1);  // one wave
  put16(eve, 0);
  eve.resize(0x124, 0);
  ssf_chunk(f, "EVE", eve);

  Bytes wnd;
  put_utf16(wnd, "SPLASH.WAV", 11);
  ssf_chunk(f, "WND", wnd);
  Bytes wav = pcm16_wav({1, 2, 3});
  Bytes wst;
  put32(wst, static_cast<std::uint32_t>(f.size() + 16 + 4));
  ssf_chunk(f, "WST", wst);
  const char wave_tag[4] = {'W', 0, 0, 0};
  ssf_chunk(f, wave_tag, wav);

  SsfFile bank(f);
  CHECK(bank.events().size() == 1);
  const SsfEvent* e = bank.find_event("Splash");
  CHECK(e != nullptr);
  CHECK(e && e->type == 7 && e->chance == 100 && e->waves.size() == 1);
  CHECK(bank.find_event(7u) == e);
  CHECK(bank.waves().size() == 1);
  CHECK(bank.waves()[0].name == "SPLASH.WAV");
  CHECK(bank.wave_data(0) == wav);
}

void store_section(Bytes& b, std::uint32_t count, std::uint32_t element_size, const Bytes& body) {
  put32(b, 0xdeadbeef);
  put32(b, count);
  put32(b, 0x100);
  put32(b, element_size);
  b.insert(b.end(), body.begin(), body.end());
}

void test_carrera_store() {
  // Two strings, one class, two allocations (an object and a raw buffer).
  const char kPool[] = "clip\0class Carrera::AnimClip";
  Bytes pool(kPool, kPool + sizeof kPool);  // both strings with their NULs
  Bytes header, allocs, ranges, flags = {0}, table, classes;
  for (std::uint32_t v : {0x10001u, 0x10u, 4u, 0x10u, 0u, 0xffffffffu}) put32(header, v);
  put32(table, 5);
  put32(table, 0);
  put32(table, 24);
  put32(table, 5);
  put32(classes, 1);
  put32(classes, 8);
  put32(classes, 0);
  put32(classes, 0);
  put32(classes, 0x1234);
  put32(ranges, 1);
  put32(ranges, 0);

  // Allocation records are patched once the heap offset is known.
  auto alloc = [&](std::uint32_t off, std::uint32_t size, std::int32_t cls, std::int32_t name, std::int32_t tag) {
    for (std::int32_t v : {0x02950000, static_cast<std::int32_t>(off), static_cast<std::int32_t>(size), cls, name, 0, 1,
                           0, -1, tag, 4}) {
      put32(allocs, static_cast<std::uint32_t>(v));
    }
  };
  alloc(0, 8, 0, 0, -1);
  alloc(0, 4, -1, -1, 0);

  Bytes f;
  store_section(f, 6, 4, header);
  std::size_t alloc_body = f.size() + 16;
  store_section(f, 2, 44, allocs);
  store_section(f, 1, 8, ranges);
  store_section(f, 1, 1, flags);
  f.push_back(0);  // padding, as seen after byte sections
  store_section(f, 2, 8, table);
  store_section(f, static_cast<std::uint32_t>(pool.size()), 1, pool);
  store_section(f, 1, 20, classes);
  std::size_t heap = f.size();
  set32(f, alloc_body + 4, static_cast<std::uint32_t>(heap));
  set32(f, alloc_body + 44 + 4, static_cast<std::uint32_t>(heap + 8));
  f.resize(heap + 12, 0xab);

  CHECK(StoreFile::looks_like(f));
  StoreFile store(f);
  CHECK(store.strings().size() == 2);
  CHECK(store.classes().size() == 1);
  CHECK(store.classes()[0].name == "class Carrera::AnimClip");
  CHECK(store.allocations().size() == 2);
  const StoreAllocation* clip = store.find("clip");
  CHECK(clip && clip->offset == heap && store.class_name(*clip) == "class Carrera::AnimClip");
  CHECK(store.at_offset(heap + 9) == &store.allocations()[1]);
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
      {"lzw_round_trip", test_lzw_round_trip},
      {"lzw_known_stream", test_lzw_known_stream},
      {"ls_archive", test_ls_archive},
      {"wav_pcm", test_wav_pcm},
      {"wav_ms_adpcm", test_wav_ms_adpcm},
      {"ssf", test_ssf},
      {"carrera_store", test_carrera_store},
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
