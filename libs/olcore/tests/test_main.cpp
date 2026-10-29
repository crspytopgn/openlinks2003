// Minimal self-contained test runner so the core library has no dependencies.
#include <algorithm>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

#include "olcore/arc0.hpp"
#include "olcore/ball_physics.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/btcv.hpp"
#include "olcore/carrera_store.hpp"
#include "olcore/golfer_anim.hpp"
#include "olcore/golfer_mesh.hpp"
#include "olcore/inflate.hpp"
#include "olcore/ls_archive.hpp"
#include "olcore/lzw.hpp"
#include "olcore/model.hpp"
#include "olcore/obstacles.hpp"
#include "olcore/object_library.hpp"
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

void put_u16(std::vector<std::uint8_t>& v, std::uint16_t x) {
  v.push_back(static_cast<std::uint8_t>(x & 0xff));
  v.push_back(static_cast<std::uint8_t>(x >> 8));
}

void put_f32(std::vector<std::uint8_t>& v, float f) {
  std::uint32_t bits;
  std::memcpy(&bits, &f, 4);
  put_u32(v, bits);
}

const std::uint8_t* pixel(const RgbaImage& img, int x, int y) {
  return &img.pixels[(static_cast<std::size_t>(y) * img.width + x) * 4];
}

void test_block_runs_modes() {
  std::vector<std::uint8_t> runs;
  put_u16(runs, 0x1001);  // mode 1: one transparent block
  put_u16(runs, 0x2001);  // mode 2: one opaque DXT1 block, all index 0 = pure red
  put_u16(runs, 0xf800);
  put_u16(runs, 0x0000);
  put_u32(runs, 0);
  put_u16(runs, 0x3001);  // mode 3: full DXT5, alpha 0x80, colour blue
  runs.insert(runs.end(), {0x80, 0x80, 0, 0, 0, 0, 0, 0});
  put_u16(runs, 0x001f);
  put_u16(runs, 0x001f);
  put_u32(runs, 0);
  put_u16(runs, 0x4001);  // mode 4: flat colour B, G, R, A = green
  runs.insert(runs.end(), {0, 255, 0, 255});
  std::vector<std::uint8_t> blocks;
  std::size_t used = decode_block_runs(runs.data(), runs.size(), 4, blocks);
  CHECK(used == runs.size());
  CHECK(blocks.size() == 4 * kDxt5BlockBytes);
  RgbaImage img = decode_dxt5(blocks.data(), 4, 1);
  CHECK(img.width == 16 && img.height == 4);
  CHECK(pixel(img, 1, 1)[3] == 0);
  const std::uint8_t* red = pixel(img, 5, 2);
  CHECK(red[0] == 255 && red[1] == 0 && red[2] == 0 && red[3] == 255);
  const std::uint8_t* blue = pixel(img, 9, 3);
  CHECK(blue[2] == 255 && blue[3] == 0x80);
  const std::uint8_t* green = pixel(img, 14, 0);
  CHECK(green[0] == 0 && green[1] == 255 && green[2] == 0 && green[3] == 255);

  bool threw = false;
  try {
    decode_block_runs(runs.data(), runs.size() - 1, 4, blocks);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
}

void test_btcv_places_tiles_from_bottom() {
  // 70 x 6 image, one 64-pixel tile at x = 0, y = 0 filled with opaque white
  // (mode 4). Its bottom edge sits on the image bottom, so only the tile's
  // last six rows show. Columns 64 to 69 have no tile and stay transparent.
  std::vector<std::uint8_t> d = {'B', 'T', 'C', 'V'};
  put_u16(d, 70);
  put_u16(d, 6);
  put_u16(d, 1);
  put_u16(d, 11);
  put_u32(d, 0);
  put_u32(d, 1);
  std::vector<std::uint8_t> runs;
  put_u16(runs, 0x4000 | 240);  // rows 0-14 white
  for (int i = 0; i < 240; ++i) runs.insert(runs.end(), {255, 255, 255, 255});
  put_u16(runs, 0x4000 | 16);   // row 15 grey
  for (int i = 0; i < 16; ++i) runs.insert(runs.end(), {128, 128, 128, 255});
  put_u16(d, 0);
  put_u16(d, 64);
  put_u16(d, 0);
  put_u16(d, 0);
  put_u32(d, 36);
  put_u32(d, static_cast<std::uint32_t>(runs.size()));
  d.insert(d.end(), runs.begin(), runs.end());
  RgbaImage img = decode_btcv(d);
  CHECK(img.width == 70 && img.height == 6);
  CHECK(pixel(img, 0, 0)[0] == 255 && pixel(img, 0, 0)[3] == 255);  // tile row 58
  CHECK(pixel(img, 10, 5)[0] < 140 && pixel(img, 10, 5)[0] > 120);  // tile row 63, grey
  CHECK(pixel(img, 66, 3)[3] == 0);
}

void test_model_reads_tables() {
  // One textured quad: 4 vertices, 4 corners, 1 face.
  std::vector<std::uint8_t> d(0xa4, 0);
  auto set_u32 = [&](std::size_t at, std::uint32_t x) {
    for (int i = 0; i < 4; ++i) d[at + i] = static_cast<std::uint8_t>(x >> (8 * i));
  };
  const float pos[4][3] = {{0, 0, 0}, {10, 0, 0}, {10, 5, 0}, {0, 5, 0}};
  for (auto& p : pos) {
    for (float f : p) put_f32(d, f);
  }
  const float uv[4][2] = {{0, 1}, {1, 1}, {1, 0}, {0, 0}};
  std::size_t uv_at = d.size();
  for (auto& t : uv) {
    put_f32(d, t[0]);
    put_f32(d, t[1]);
  }
  std::size_t face_at = d.size();
  put_u16(d, 4);
  put_u16(d, 0);
  put_u16(d, 0);
  put_u16(d, 0);
  put_u32(d, 0);
  std::size_t idx_at = d.size();
  for (std::uint16_t i = 0; i < 4; ++i) put_u16(d, i);
  std::size_t mat_at = d.size();
  d.resize(d.size() + 16, 0xcd);
  set_u32(0, static_cast<std::uint32_t>(d.size()));
  set_u32(4, 1);
  set_u32(8, 1);
  const std::uint32_t tables[5][2] = {{4, 0xa4},
                                      {4, static_cast<std::uint32_t>(uv_at)},
                                      {1, static_cast<std::uint32_t>(face_at)},
                                      {4, static_cast<std::uint32_t>(idx_at)},
                                      {1, static_cast<std::uint32_t>(mat_at)}};
  for (int i = 0; i < 5; ++i) {
    set_u32(0x18 + 8 * i, tables[i][0]);
    set_u32(0x1c + 8 * i, tables[i][1]);
  }
  set_u32(0x40, 1);
  Model m = read_model(d);
  CHECK(m.positions.size() == 4);
  CHECK(m.faces.size() == 1 && m.faces[0].count == 4);
  auto surfaces = triangulate(m);
  CHECK(surfaces.size() == 1);
  CHECK(surfaces[0].indices.size() == 6);
  CHECK_NEAR(surfaces[0].positions[3], 10.0, 0.0);
  CHECK_NEAR(surfaces[0].uvs[5], 0.0, 0.0);
}

void test_object_library_parses() {
  auto str = [](std::vector<std::uint8_t>& v, const std::string& s) {
    put_u32(v, static_cast<std::uint32_t>(s.size() + 1));
    v.insert(v.end(), s.begin(), s.end());
    v.push_back(0);
  };
  std::vector<std::uint8_t> d;
  put_u32(d, 99);
  put_u32(d, 1);
  str(d, "Rocks");
  put_u32(d, 1);
  str(d, "Rocks000.btx");
  str(d, "Rocks\\Rocks000.btx");
  put_u32(d, 1);
  const float f[9] = {25, 2, 5, 0, 150, 355, 0, 0.5f, 0};
  for (float x : f) put_f32(d, x);
  put_u32(d, 0x84247be0);
  put_u32(d, 0);  // no top view
  put_u32(d, 1);
  for (int i = 0; i < 6; ++i) put_f32(d, 1);
  ObjectLibrary lib = read_object_library(d);
  CHECK(lib.categories.size() == 1);
  const LibraryObject* o = lib.find(0x84247be0);
  CHECK(o != nullptr);
  if (o) {
    CHECK(o->path == "Rocks\\Rocks000.btx");
    CHECK_NEAR(o->size[0], 150.0, 0.0);
    CHECK(o->top_view.empty());
    CHECK(o->collision == 1);
  }
  CHECK(lib.find("ROCKS000.BTX") == o);
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

void test_obstacle_field_hits() {
  ObstacleField f;
  f.add_cylinder(0, 10, 0.5, 0, 5, ObstacleKind::Solid);
  f.add_box({20, 1, 0}, {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}, {1, 1, 2}, ObstacleKind::Solid);
  f.add_cylinder(-30, 0, 4, 2, 10, ObstacleKind::Canopy);
  f.finalize();
  CHECK(f.size() == 3);
  ObstacleHit h;
  // Into the trunk from the front: enters 0.5 m short of its centre.
  CHECK(f.segment_hit({0, 1, 0}, {0, 1, 20}, h));
  CHECK_NEAR(h.fraction, 9.5 / 20, 1e-9);
  CHECK_NEAR(h.normal.z, -1, 1e-9);
  CHECK(h.kind == ObstacleKind::Solid);
  // Over it, and starting inside it.
  CHECK(!f.segment_hit({0, 6, 0}, {0, 6, 20}, h));
  CHECK(!f.segment_hit({0, 1, 10}, {0, 1, 20}, h));
  // Into the box from the -x side, then down onto its top.
  CHECK(f.segment_hit({15, 1, 0}, {25, 1, 0}, h));
  CHECK_NEAR(h.fraction, 0.4, 1e-9);
  CHECK_NEAR(h.normal.x, -1, 1e-9);
  CHECK(f.segment_hit({20, 4, 0.5}, {20, 1, 0.5}, h));
  CHECK_NEAR(h.fraction, 2.0 / 3.0, 1e-9);
  CHECK_NEAR(h.normal.y, 1, 1e-9);
  // Down through the canopy top; under it misses.
  CHECK(f.segment_hit({-30, 12, 1}, {-30, 8, 1}, h));
  CHECK(h.kind == ObstacleKind::Canopy);
  CHECK_NEAR(h.fraction, 0.5, 1e-9);
  CHECK(!f.segment_hit({-40, 1, 0}, {-20, 1, 0}, h));
}

void test_trees_stop_the_ball() {
  BallParams p;
  ObstacleField trunk;
  trunk.add_cylinder(0, 40, 0.5, -1, 30, ObstacleKind::Solid);
  trunk.finalize();
  FlatTerrain ground(Surface::Fairway);
  ground.obstacles = &trunk;
  ShotResult r = simulate_shot(launch_from_swing(club("Dr"), {}, Surface::Tee), p, ground);
  std::printf("  trunk: rest z %.2f m, total %.2f m, %d hits\n", r.rest.z, r.total_m, r.obstacle_hits);
  CHECK(r.obstacle_hits >= 1);
  CHECK(r.rest.z < 40);
  CHECK(r.outcome == ShotOutcome::Rest);

  ObstacleField canopy;
  canopy.add_cylinder(0, 150, 6, 3, 40, ObstacleKind::Canopy);
  canopy.finalize();
  ground.obstacles = &canopy;
  r = simulate_shot(launch_from_swing(club("Dr"), {}, Surface::Tee), p, ground);
  std::printf("  canopy: carry %.2f m, total %.2f m, %d hits\n", r.carry_m, r.total_m, r.obstacle_hits);
  CHECK(r.obstacle_hits >= 1);
  CHECK(r.carry_m < 165);

  // A putt rolled into a wall comes back.
  ObstacleField wall;
  wall.add_box({0, 0.5, 4}, {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}, {2, 1, 0.1}, ObstacleKind::Solid);
  wall.finalize();
  FlatTerrain green(Surface::Green);
  green.obstacles = &wall;
  r = simulate_shot(make_launch(3.0, 0, 0, 0, 0), p, green);
  std::printf("  wall: rest z %.3f m, %d hits\n", r.rest.z, r.obstacle_hits);
  CHECK(r.obstacle_hits == 1);
  CHECK(r.rest.z < 3.9);

  // A ball dropped onto a wide flat box settles on top of it.
  ObstacleField deck;
  deck.add_box({0, 1, 0}, {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}, {5, 0.5, 5}, ObstacleKind::Solid);
  deck.finalize();
  ground.obstacles = &deck;
  r = simulate_shot({{0, 3, 0}, {0, 1, 0.5}, {}}, p, ground);
  std::printf("  deck: rest y %.3f m, %d hits\n", r.rest.y, r.obstacle_hits);
  CHECK(r.outcome == ShotOutcome::Rest);
  CHECK_NEAR(r.rest.y, 1.5, 0.05);
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

// Builds a store from named objects. Each object's bytes may hold pointers
// to other objects as "index + 1 into objs" placeholders in the slots listed
// in `pointers`; they are patched to file offsets.
struct TestObject {
  Bytes bytes;
  int class_index = -1;
  int name = -1;
  std::vector<std::pair<std::size_t, std::size_t>> pointers;  // (field offset, target object)
};

Bytes build_store(const std::vector<std::string>& strings, const std::vector<std::string>& class_names,
                  const std::vector<TestObject>& objs) {
  Bytes pool, table, classes, header, allocs, ranges, flags = {0};
  std::vector<std::uint32_t> string_index;
  auto add_string = [&](const std::string& str) {
    put32(table, static_cast<std::uint32_t>(str.size() + 1));
    put32(table, static_cast<std::uint32_t>(pool.size()));
    pool.insert(pool.end(), str.begin(), str.end());
    pool.push_back(0);
  };
  for (const auto& str : strings) add_string(str);
  for (std::size_t i = 0; i < class_names.size(); ++i) {
    add_string(class_names[i]);
    put32(classes, static_cast<std::uint32_t>(strings.size() + i));
    for (std::uint32_t v : {0u, 0u, 0u, 0u}) put32(classes, v);
  }
  for (std::uint32_t v : {0x10001u, 0x10u, 4u, 0x10u, 0u, 0xffffffffu}) put32(header, v);
  put32(ranges, 1);
  put32(ranges, 0);
  allocs.resize(objs.size() * 44, 0);
  std::uint32_t string_count = static_cast<std::uint32_t>(strings.size() + class_names.size());

  Bytes f;
  store_section(f, 6, 4, header);
  std::size_t alloc_body = f.size() + 16;
  store_section(f, static_cast<std::uint32_t>(objs.size()), 44, allocs);
  store_section(f, 1, 8, ranges);
  store_section(f, 1, 1, flags);
  store_section(f, string_count, 8, table);
  store_section(f, static_cast<std::uint32_t>(pool.size()), 1, pool);
  store_section(f, static_cast<std::uint32_t>(class_names.size()), 20, classes);

  std::vector<std::size_t> offsets;
  for (const auto& o : objs) {
    offsets.push_back(f.size());
    f.insert(f.end(), o.bytes.begin(), o.bytes.end());
  }
  for (std::size_t i = 0; i < objs.size(); ++i) {
    std::size_t rec = alloc_body + i * 44;
    set32(f, rec + 4, static_cast<std::uint32_t>(offsets[i]));
    set32(f, rec + 8, static_cast<std::uint32_t>(objs[i].bytes.size()));
    set32(f, rec + 12, static_cast<std::uint32_t>(objs[i].class_index));
    set32(f, rec + 16, static_cast<std::uint32_t>(objs[i].name));
    set32(f, rec + 36, 0xffffffffu);
    for (const auto& [field, target] : objs[i].pointers) {
      set32(f, offsets[i] + field, static_cast<std::uint32_t>(offsets[target]));
    }
  }
  return f;
}

void set_f32(Bytes& b, std::size_t at, float v) {
  std::uint32_t bits;
  std::memcpy(&bits, &v, sizeof bits);
  set32(b, at, bits);
}

void test_name_hash_is_crc32() {
  CHECK(name_hash("") == 0);
  CHECK(name_hash("123456789") == 0xcbf43926u);  // the standard CRC-32 check value
}

void test_skeleton_and_clip() {
  // Root (joint, at y = 3 ft) with a child joint Arm one foot along +x and a
  // joint orient of 90 degrees about z; a two-frame clip turns Root about y.
  const float half = std::sqrt(0.5f);
  auto joint = [](float tx, float ty, float tz) {
    Bytes b(504, 0);
    set_f32(b, 280, tx);
    set_f32(b, 284, ty);
    set_f32(b, 288, tz);
    set_f32(b, 452, 1.0f);  // identity orient
    return b;
  };
  TestObject root{joint(0, 3, 0), 0, 0, {}};
  TestObject arm{joint(1, 0, 0), 0, 1, {{0x1c, 1}}};  // parent: object 1, Root
  set_f32(arm.bytes, 448, half);  // orient z
  set_f32(arm.bytes, 452, half);  // orient w

  Bytes clip(352, 0);
  set32(clip, 0x2c, 2);  // frames
  set32(clip, 0x30, 2);  // channels
  set32(clip, 0x34, 1);  // animated
  TestObject clip_obj{clip, 1, 2, {{0x10, 3}, {0x38, 4}, {0x3c, 5}}};
  TestObject clip_name{text("Turn"), -1, -1, {}};
  clip_name.bytes.push_back(0);
  Bytes channels;
  for (std::uint32_t v : {1u, name_hash("Root"), 296u, 0x80000020u, name_hash("RootrotateY")}) put32(channels, v);
  for (std::uint32_t v : {0u, name_hash("Root"), 284u, 0x80000100u, name_hash("ReplaceY")}) put32(channels, v);
  Bytes samples;
  // Frame 0: rotateY 0, translateY 3 ft (constant); frame 1: rotateY pi/2.
  put16(samples, 0);
  put16(samples, 3 * 2048);
  put16(samples, static_cast<std::uint16_t>(std::lround(1.5707963 * 2048)));
  TestObject ch_obj{channels, -1, -1, {}};
  TestObject sm_obj{samples, -1, -1, {}};

  Bytes f = build_store({"Root", "Arm", "Turn"}, {"class Carrera::Joint", "class Carrera::AnimClip"},
                        {arm, root, clip_obj, clip_name, ch_obj, sm_obj});
  StoreFile store(f);
  Skeleton sk = read_skeleton(store);
  CHECK(sk.nodes.size() == 2);
  int r = sk.find("Root"), a = sk.find("Arm");
  CHECK(r == 0 && a == 1);  // parent placed first
  CHECK(a >= 0 && sk.nodes[static_cast<std::size_t>(a)].parent == r);

  auto clips = read_anim_clips(store);
  CHECK(clips.size() == 1);
  if (clips.size() != 1 || r < 0 || a < 0) return;
  CHECK(clips[0].name == "Turn");
  CHECK(clips[0].frame_count == 2 && clips[0].dynamic_count == 1);
  CHECK_NEAR(clips[0].value(1, 1), 3.0, 1e-6);  // constant channel reads frame 0

  auto rest = sk.pose(nullptr, 0);
  CHECK_NEAR(rest[1][12], 1.0, 1e-5);
  CHECK_NEAR(rest[1][13], 3.0, 1e-5);
  // The orient turns Arm's own x axis onto +y.
  CHECK_NEAR(rest[1][1], 1.0, 1e-5);
  auto turned = sk.pose(&clips[0], 1);
  // Root turned 90 degrees about y carries Arm from +x to -z.
  CHECK_NEAR(turned[1][12], 0.0, 1e-3);
  CHECK_NEAR(turned[1][14], -1.0, 1e-3);
  CHECK_NEAR(turned[1][13], 3.0, 1e-5);
}

void test_skinned_mesh() {
  // A four-vertex quad skinned to Root (at y = 3 ft) and Arm (one foot along
  // +x). The skin's joint list has 21 entries so that influence number 21
  // (which stands for entry 20, Arm) exercises the skipped number 19.
  auto joint = [](float tx, float ty) {
    Bytes b(504, 0);
    set_f32(b, 280, tx);
    set_f32(b, 284, ty);
    set_f32(b, 452, 1.0f);
    return b;
  };
  TestObject root{joint(0, 3), 0, 0, {}};
  TestObject arm{joint(1, 0), 0, 1, {{0x1c, 0}}};

  TestObject mesh{Bytes(280, 0), 1, 2, {{0xd4, 3}, {0xe0, 4}, {0xe8, 5}, {0xec, 6}, {0xf0, 7}}};
  set32(mesh.bytes, 0xdc, 1);
  set32(mesh.bytes, 0xe4, 4);
  TestObject skin{Bytes(220, 0), 2, -1, {{0x1c, 8}, {0xa4, 9}, {0xb4, 10}}};
  set32(skin.bytes, 0x20, 21);
  set32(skin.bytes, 0xb0, 4);
  TestObject shape{Bytes(52, 0), 3, -1, {{0x14, 11}, {0x2c, 12}}};
  set32(shape.bytes, 0x18, 5);
  set32(shape.bytes, 0x1c, 2);
  set32(shape.bytes, 0x28, 3);

  Bytes pos, uv, nrm;
  const float quad[4][2] = {{0, 3}, {1, 3}, {1, 4}, {0, 4}};
  for (const auto& q : quad) {
    for (float v : {q[0], q[1], 0.0f}) {
      put32(pos, 0);
      set_f32(pos, pos.size() - 4, v);
    }
    for (float v : {q[0], q[1] - 3}) {
      put32(uv, 0);
      set_f32(uv, uv.size() - 4, v);
    }
    for (float v : {0.0f, 0.0f, 1.0f}) {
      put32(nrm, 0);
      set_f32(nrm, nrm.size() - 4, v);
    }
  }
  TestObject joints{Bytes(21 * 4, 0), -1, -1, {}};
  for (std::size_t j = 0; j < 21; ++j) joints.pointers.push_back({4 * j, j == 20 ? 1 : 0});
  Bytes bind(21 * 64, 0);
  for (std::size_t j = 0; j < 21; ++j) {
    for (std::size_t k : {0, 5, 10, 15}) set_f32(bind, 64 * j + 4 * k, 1.0f);
    set_f32(bind, 64 * j + 48, j == 20 ? -1.0f : 0.0f);  // inverse of the rest translation
    set_f32(bind, 64 * j + 52, -3.0f);
  }
  Bytes pool(4 * 20, 0);
  auto influence = [&](std::size_t v, std::size_t slot, std::uint8_t j, float w) {
    pool[20 * v + slot] = j;
    set_f32(pool, 20 * v + 4 + 4 * slot, w);
  };
  influence(0, 0, 0, 1.0f);
  influence(1, 0, 21, 1.0f);
  influence(2, 0, 21, 0.5f);
  influence(2, 1, 0, 0.5f);
  influence(3, 0, 0, 1.0f);
  Bytes strip;
  for (std::uint32_t i : {0u, 1u, 3u, 2u, 2u}) put16(strip, i);
  TestObject shader{Bytes(108, 0), 4, 3, {{0x58, 13}}};
  set_f32(shader.bytes, 0x14, 0.5f);
  TestObject texture{Bytes(44, 0), 5, -1, {{0x14, 14}}};
  Bytes file = text("face.tga");
  file.push_back(0);

  Bytes f = build_store({"Root", "Arm", "body", "skin"},
                        {"class Carrera::Joint", "class Carrera::Mesh", "class Carrera::SkinCluster",
                         "class Carrera::Shape", "class Carrera::Shader", "class Carrera::Texture"},
                        {root, arm, mesh, skin, shape, TestObject{pos, -1, -1, {}}, TestObject{uv, -1, -1, {}},
                         TestObject{nrm, -1, -1, {}}, joints, TestObject{bind, -1, -1, {}},
                         TestObject{pool, -1, -1, {}}, TestObject{strip, -1, -1, {}}, shader, texture,
                         TestObject{file, -1, -1, {}}});
  StoreFile store(f);
  auto meshes = read_meshes(store);
  CHECK(meshes.size() == 1);
  if (meshes.size() != 1) return;
  const GolferMesh& m = meshes[0];
  CHECK(m.name == "body");
  CHECK(m.positions.size() == 4 && m.uvs.size() == 4 && m.normals.size() == 4);
  CHECK(m.parts.size() == 1);
  CHECK(m.skinned() && m.skin_joints.size() == 21);
  if (m.parts.size() != 1 || !m.skinned() || m.skin_joints.size() != 21) return;
  CHECK(m.skin_joints[0] == "Root" && m.skin_joints[20] == "Arm");
  CHECK(m.influences[1].joint[0] == 20);
  CHECK(m.parts[0].material.texture == "face.tga");
  CHECK(m.parts[0].material.name == "skin");
  CHECK_NEAR(m.parts[0].material.diffuse[0], 0.5, 1e-6);
  CHECK((m.parts[0].triangles() == std::vector<std::uint32_t>{0, 1, 3, 3, 1, 2}));

  Skeleton sk = read_skeleton(store);
  auto world = sk.pose(nullptr, 0);
  auto rest = skin_positions(m, sk, world);
  CHECK_NEAR(rest[2][1], 4.0, 1e-5);  // the bind pose reproduces the mesh
  int a = sk.find("Arm");
  CHECK(a >= 0);
  if (a < 0) return;
  world[static_cast<std::size_t>(a)][13] += 1.0f;  // lift Arm by a foot
  auto lifted = skin_positions(m, sk, world);
  CHECK_NEAR(lifted[0][1], 3.0, 1e-5);
  CHECK_NEAR(lifted[1][1], 4.0, 1e-5);
  CHECK_NEAR(lifted[2][1], 4.5, 1e-5);  // half on Arm, half on Root
  CHECK_NEAR(lifted[2][0], 1.0, 1e-5);
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
      {"block_runs_modes", test_block_runs_modes},
      {"btcv_places_tiles_from_bottom", test_btcv_places_tiles_from_bottom},
      {"model_reads_tables", test_model_reads_tables},
      {"object_library_parses", test_object_library_parses},
      {"lzw_round_trip", test_lzw_round_trip},
      {"lzw_known_stream", test_lzw_known_stream},
      {"ls_archive", test_ls_archive},
      {"wav_pcm", test_wav_pcm},
      {"wav_ms_adpcm", test_wav_ms_adpcm},
      {"ssf", test_ssf},
      {"carrera_store", test_carrera_store},
      {"name_hash_is_crc32", test_name_hash_is_crc32},
      {"skeleton_and_clip", test_skeleton_and_clip},
      {"skinned_mesh", test_skinned_mesh},
      {"drive_bounces_and_rolls", test_drive_bounces_and_rolls},
      {"club_distances_decrease", test_club_distances_decrease},
      {"wedge_checks_on_green", test_wedge_checks_on_green},
      {"rough_and_sand_cost_distance", test_rough_and_sand_cost_distance},
      {"swing_accuracy_curves_ball", test_swing_accuracy_curves_ball},
      {"putt_drops_at_holing_speed", test_putt_drops_at_holing_speed},
      {"putt_distance_follows_green_speed", test_putt_distance_follows_green_speed},
      {"ball_rolls_downhill", test_ball_rolls_downhill},
      {"water_and_out_of_bounds_stop_the_ball", test_water_and_out_of_bounds_stop_the_ball},
      {"obstacle_field_hits", test_obstacle_field_hits},
      {"trees_stop_the_ball", test_trees_stop_the_ball},
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
