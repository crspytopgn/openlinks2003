// Minimal self-contained test runner so the core library has no dependencies.
#include <algorithm>
#include <cmath>
#include <cstdlib>
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
#include "olcore/panorama.hpp"
#include "olcore/carrera_store.hpp"
#include "olcore/d3f.hpp"
#include "olcore/golfer_anim.hpp"
#include "olcore/golfer_mesh.hpp"
#include "olcore/image.hpp"
#include "olcore/inflate.hpp"
#include "olcore/links_flight.hpp"
#include "olcore/links_ground.hpp"
#include "olcore/links_launch.hpp"
#include "olcore/links_mouse.hpp"
#include "olcore/ls_archive.hpp"
#include "olcore/lzw.hpp"
#include "olcore/model.hpp"
#include "olcore/obstacles.hpp"
#include "olcore/object_library.hpp"
#include "olcore/opponent.hpp"
#include "olcore/rules.hpp"
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

  // Untagged entries (fonts in GRAPHICS.LS, SOUNDS.LS) have junk in the tag
  // and the header size; the data still follows the 0x37-byte header.
  for (std::size_t i = 0; i < 4; ++i) a[first + i] = 0;
  a[first + 6] = 0x41;
  a[first + 7] = 0x44;

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

// A D3F font: header, the six glyph tables, the page list, then pages.
Bytes d3f_font(bool colour) {
  Bytes f(0x55 + 6 * 256, 0);
  f[0] = 'D';
  f[1] = '3';
  f[2] = 'F';
  f[3] = colour ? 0xd4 : 0xb4;
  std::string face = "Arial";
  std::copy(face.begin(), face.end(), f.begin() + 4);
  set32(f, 0x44, static_cast<std::uint32_t>(-11));
  f[0x48] = 1;
  set32(f, 0x49, 700);
  set32(f, 0x4d, 1);
  set32(f, 0x51, 10);
  const int H = 'H';
  f[0x55 + 256 + H] = 2;      // x
  f[0x55 + 512 + H] = 3;      // y
  f[0x55 + 768 + H] = 4;      // width
  f[0x55 + 1024 + H] = 0xff;  // left -1
  f[0x55 + 1280 + H] = 2;     // right
  const std::size_t bpp = colour ? 4 : 1;
  Bytes px(16 * 16 * bpp, 0);
  for (int y = 3; y < 3 + 7; ++y) {  // rows 0 to 6 of the cell: ascent 7
    for (int x = 2; x < 6; ++x) {
      std::size_t p = static_cast<std::size_t>(y * 16 + x) * bpp;
      if (colour) {
        px[p] = 10;
        px[p + 1] = 20;
        px[p + 2] = 30;
        px[p + 3] = 200;
      } else {
        px[p] = 255;
      }
    }
  }
  Bytes packed = lzw_compress(px.data(), px.size() - 40);  // ends early, as some shipped pages do
  std::size_t list = f.size();
  f.resize(list + 4);
  set32(f, list, static_cast<std::uint32_t>(f.size()));
  Bytes head(8, 0);
  set32(head, 0, static_cast<std::uint32_t>(-16));
  set32(head, 4, static_cast<std::uint32_t>(packed.size()));
  f.insert(f.end(), head.begin(), head.end());
  f.insert(f.end(), packed.begin(), packed.end());
  return f;
}

void test_d3f() {
  Bytes b = d3f_font(false);
  CHECK(is_d3f(b.data(), b.size()));
  D3fFont f = read_d3f(b);
  CHECK(f.face == "Arial");
  CHECK(f.pixel_height == 11);
  CHECK(f.italic);
  CHECK(f.weight == 700);
  CHECK(f.line_height == 10);
  CHECK(!f.colour);
  CHECK(f.pages.size() == 1 && f.pages[0].width == 16 && f.pages[0].height == 16);
  const D3fGlyph& g = f.glyphs['H'];
  CHECK(g.x == 2 && g.y == 3 && g.width == 4 && g.left == -1 && g.right == 2);
  CHECK(f.glyphs['A'].width == 0);
  CHECK(f.pages[0].pixels[(3 * 16 + 2) * 4 + 3] == 255);
  CHECK(f.pages[0].pixels[(3 * 16 + 2) * 4 + 0] == 255);
  CHECK(f.pages[0].pixels[(2 * 16 + 2) * 4 + 3] == 0);
  CHECK(f.ascent() == 7);

  D3fFont c = read_d3f(d3f_font(true));
  CHECK(c.colour);
  const std::uint8_t* p = &c.pages[0].pixels[(4 * 16 + 3) * 4];
  CHECK(p[0] == 30 && p[1] == 20 && p[2] == 10 && p[3] == 200);  // BGRA to RGBA

  Bytes bad = b;
  set32(bad, 0x55 + 6 * 256, 999999);
  bool threw = false;
  try {
    read_d3f(bad);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
  CHECK(!is_d3f(b.data(), 40));
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

// An ARC0 archive of stored zlib entries.
std::vector<std::uint8_t> make_arc0(const std::vector<std::string>& names, const std::vector<std::string>& bodies) {
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
    put_u32(blob, 0);
    put_u32(blob, 0);
    put_u32(blob, 0);
  }
  std::vector<std::uint8_t> head = {'A', 'R', 'C', '0'};
  put_u32(head, static_cast<std::uint32_t>(blob.size()));
  put_u32(head, static_cast<std::uint32_t>(names.size()));
  put_u32(head, dir);
  std::copy(head.begin(), head.end(), blob.begin());
  return blob;
}

// Uncompressed 32-bit TGA (bottom-up rows) of one colour.
std::string flat_tga(int edge, std::uint8_t r, std::uint8_t g, std::uint8_t b) {
  std::string t(18, '\0');
  t[2] = 2;
  t[12] = static_cast<char>(edge);
  t[14] = static_cast<char>(edge);
  t[16] = 32;
  t[17] = 8;
  for (int i = 0; i < edge * edge; ++i) {
    t.push_back(static_cast<char>(b));
    t.push_back(static_cast<char>(g));
    t.push_back(static_cast<char>(r));
    t.push_back(static_cast<char>(255));
  }
  return t;
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

void test_tga_rle_bottom_up() {
  // 3 x 2, 24-bit RLE, bottom-left origin: bottom row a run of three blue
  // pixels, top row three raw pixels (red, green, white).
  std::vector<std::uint8_t> d(18, 0);
  d[2] = 10;
  d[12] = 3;
  d[14] = 2;
  d[16] = 24;
  d.insert(d.end(), {0x82, 255, 0, 0});                                     // run of 3, B G R
  d.insert(d.end(), {0x02, 0, 0, 255, 0, 255, 0, 255, 255, 255});        // 3 raw
  auto img = decode_tga(d);
  CHECK(img && img->width == 3 && img->height == 2);
  if (!img) return;
  CHECK(pixel(*img, 0, 0)[0] == 255 && pixel(*img, 0, 0)[2] == 0);  // red, top row
  CHECK(pixel(*img, 1, 0)[1] == 255 && pixel(*img, 1, 0)[0] == 0);  // green
  CHECK(pixel(*img, 2, 1)[2] == 255 && pixel(*img, 2, 1)[3] == 255);  // blue, bottom row
  CHECK(!decode_tga(std::vector<std::uint8_t>(10, 0)));
}

std::uint32_t be32(const std::vector<std::uint8_t>& v, std::size_t at) {
  return static_cast<std::uint32_t>(v[at]) << 24 | static_cast<std::uint32_t>(v[at + 1]) << 16 |
         static_cast<std::uint32_t>(v[at + 2]) << 8 | v[at + 3];
}

void test_png_round_trip() {
  RgbaImage img;
  img.width = 37;
  img.height = 11;
  for (int i = 0; i < img.width * img.height; ++i)
    img.pixels.insert(img.pixels.end(), {static_cast<std::uint8_t>(i * 7), static_cast<std::uint8_t>(i / 3), 200,
                                         static_cast<std::uint8_t>(i % 5 ? 255 : 0)});
  auto png = encode_png(img);
  CHECK(png.size() > 33 && png[1] == 'P' && be32(png, 16) == 37 && be32(png, 20) == 11 && png[25] == 6);
  // One IDAT right after IHDR: inflate it and undo the row filters.
  std::uint32_t len = be32(png, 33);
  CHECK(std::memcmp(&png[37], "IDAT", 4) == 0);
  CHECK(crc32(&png[37], len + 4) == be32(png, 41 + len));
  auto rows = zlib_decompress(&png[41], len);
  const std::size_t stride = 37 * 4;
  CHECK(rows.size() == 11 * (stride + 1));
  std::vector<std::uint8_t> prev(stride, 0), out;
  for (int y = 0; y < 11 && rows.size() == 11 * (stride + 1); ++y) {
    const std::uint8_t* r = &rows[y * (stride + 1)];
    std::vector<std::uint8_t> line(stride);
    for (std::size_t k = 0; k < stride; ++k) {
      int a = k >= 4 ? line[k - 4] : 0, b = prev[k], c = k >= 4 ? prev[k - 4] : 0;
      int p = a + b - c, pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
      int pred = r[0] == 0 ? 0 : r[0] == 1 ? a : r[0] == 2 ? b : r[0] == 3 ? (a + b) / 2 : (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
      line[k] = static_cast<std::uint8_t>(r[1 + k] + pred);
    }
    out.insert(out.end(), line.begin(), line.end());
    prev = line;
  }
  // Transparent pixels keep their colour in the file.
  CHECK(out == img.pixels);
  // Long repeats compress.
  std::vector<std::uint8_t> zeros(100000, 0);
  auto z = zlib_compress(zeros.data(), zeros.size());
  CHECK(z.size() < 2000 && zlib_decompress(z) == zeros);
}

void test_pad_and_bleed() {
  RgbaImage img;
  img.width = 2;
  img.height = 2;
  img.pixels = {10, 0, 0, 255, 20, 0, 0, 255, 30, 0, 0, 255, 40, 0, 0, 0};
  RgbaImage p = pad_wrapped(img, 1);
  CHECK(p.width == 4 && p.height == 4);
  CHECK(pixel(p, 0, 0)[0] == 40 && pixel(p, 1, 1)[0] == 10 && pixel(p, 3, 3)[0] == 10);
  RgbaImage q = pad_wrapped(img, 3, false);
  CHECK(q.width == 8 && q.height == 2 && pixel(q, 0, 0)[0] == 20);
  bleed_transparent(img);
  CHECK(pixel(img, 1, 1)[0] == 20 && pixel(img, 1, 1)[3] == 0);  // mean of 10, 20, 30
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

void test_sky_archive() {
  // Two 8-pixel tiles (red, green), then five 4-pixel ones (blue): 16 x 12,
  // the narrowest row's width.
  std::vector<std::string> names, bodies;
  for (int i = 0; i < 7; ++i) {
    names.push_back("_s_k_y_" + std::to_string(i + 1) + ".tga");
    bodies.push_back(i < 2 ? flat_tga(8, i == 0 ? 255 : 0, i == 1 ? 255 : 0, 0) : flat_tga(4, 0, 0, 255));
  }
  names.push_back("sky.prv");
  bodies.push_back("preview");
  RgbaImage img = decode_sky_archive(Arc0Archive(make_arc0(names, bodies)));
  CHECK(img.width == 16 && img.height == 12);
  CHECK(pixel(img, 0, 0)[0] == 255 && pixel(img, 15, 7)[1] == 255);
  CHECK(pixel(img, 15, 11)[2] == 255 && pixel(img, 15, 11)[3] == 255);
  bool threw = false;
  try {
    decode_sky_archive(Arc0Archive(make_arc0({"sky.prv"}, {"preview"})));
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
}

void test_panorama_tiles() {
  // 70 x 260 horizon: one 256 tile row (a single tile, cropped to 70 wide),
  // then a row of 4-pixel tiles (18 across) cropped to the last 4 rows.
  CHECK((panorama_row_sizes(720) == std::vector<int>{256, 256, 256}));
  CHECK((panorama_row_sizes(320) == std::vector<int>{256, 64}));
  CHECK((panorama_row_sizes(260) == std::vector<int>{256, 4}));
  std::vector<std::uint8_t> d = {'n', 'a', 'p', 0};
  put_u32(d, 70);
  put_u32(d, 260);
  put_u32(d, 1);
  put_u32(d, 2);
  std::vector<std::uint8_t> runs;
  put_u16(runs, 0x4000);  // 4096 flat blocks
  for (int i = 0; i < 4096; ++i) runs.insert(runs.end(), {0, 0, 255, 255});  // B, G, R, A: red
  d.insert(d.end(), {'d', 'e', 's', 'u'});
  put_u32(d, static_cast<std::uint32_t>(runs.size()));
  d.insert(d.end(), runs.begin(), runs.end());
  for (int c = 0; c < 18; ++c) {
    if (c == 2) {
      d.insert(d.end(), {'d', 'e', 's', 'u'});
      put_u32(d, 6);
      put_u16(d, 0x4001);
      d.insert(d.end(), {255, 0, 0, 255});  // blue
    } else {
      d.insert(d.end(), {'t', 'p', 'm', 'e'});
    }
  }
  RgbaImage img = decode_panorama(d);
  CHECK(img.width == 70 && img.height == 260);
  CHECK(pixel(img, 69, 255)[0] == 255 && pixel(img, 69, 255)[3] == 255);
  CHECK(pixel(img, 9, 258)[2] == 255 && pixel(img, 9, 258)[3] == 255);
  CHECK(pixel(img, 4, 258)[3] == 0);
  bool threw = false;
  try {
    d.push_back(0);
    decode_panorama(d);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
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

// game/tests/run_tests.gd checks the GDScript port against the same cases.
void test_game_modes() {
  CHECK(stableford_points(4, 4) == 2);
  CHECK(stableford_points(3, 4) == 3);
  CHECK(stableford_points(2, 5) == 5);
  CHECK(stableford_points(6, 4) == 0);
  CHECK(stableford_points(9, 4) == 0);
  CHECK(stableford_points(0, 4) == 0);
  Scorecard card({4, 3, 5});
  card.record(0, 5);
  card.record(1, 2);
  CHECK(stableford_total(card) == 4);

  std::vector<int> bb = best_ball({{5, 3, 0}, {4, 4, 0}});
  CHECK((bb == std::vector<int>{4, 3, 0}));

  // Hole 2 is tied, so hole 3 is worth two skins; hole 4 is tied and carried.
  SkinsResult sk = skins({{4, 3, 4, 5, 0}, {5, 3, 5, 5, 0}, {5, 4, 6, 5, 0}});
  CHECK((sk.skins == std::vector<int>{3, 0, 0}));
  CHECK((sk.hole_winner == std::vector<int>{0, -1, 0, -1, -2}));
  CHECK(sk.carried == 1);
  CHECK(skins({{4, 3}, {3, 0}}).skins[1] == 1);
  CHECK(skins({{4, 3}, {3, 0}}).hole_winner[1] == -2);

  // A wins 1, 2 and 4, halves 3: 3 up with 5 left after 4 of 9.
  std::vector<int> a = {4, 3, 5, 4, 0, 0, 0, 0, 0};
  std::vector<int> b = {5, 4, 5, 5, 0, 0, 0, 0, 0};
  MatchStatus m = match_status(a, b);
  CHECK(m.up == 3 && m.played == 4 && m.remaining == 5 && !m.finished && !m.dormie);
  CHECK(match_text(m) == "3 up");
  a[4] = 4; b[4] = 5;
  m = match_status(a, b);
  CHECK(m.up == 4 && m.remaining == 4 && m.dormie && match_text(m) == "4 up (dormie)");
  a[5] = 3; b[5] = 4;
  m = match_status(a, b);
  CHECK(m.finished && m.played == 6 && m.remaining == 3 && match_text(m) == "5 & 3");
  m = match_status({4, 4, 4}, {4, 3, 5});
  CHECK(m.up == 0 && m.finished && match_text(m) == "Halved");
  m = match_status({4, 4, 3}, {4, 4, 4});
  CHECK(m.up == 1 && m.finished && m.remaining == 0 && match_text(m) == "1 up");
  m = match_status({5, 0}, {4, 0});
  CHECK(m.up == -1 && m.played == 1 && m.dormie && match_text(m) == "1 up (dormie)");
  CHECK(match_text(match_status({0, 0}, {0, 0})) == "All square");
}

// game/tests/run_tests.gd checks the GDScript port against the same cases.
void test_handicaps() {
  CHECK(div_round(95, 10) == 10 && div_round(94, 10) == 9 && div_round(-95, 10) == -10 && div_round(-94, 10) == -9);

  // The back nine of an 18 keeps its order; holes without an index go last.
  CHECK((stroke_ranks({8, 2, 16, 4, 12, 18, 6, 14, 10}) == std::vector<int>{4, 1, 8, 2, 6, 9, 3, 7, 5}));
  CHECK((stroke_ranks({0, 3, 0, 1}) == std::vector<int>{3, 2, 4, 1}));

  std::vector<int> ranks = {3, 1, 2};
  CHECK((handicap_strokes(4, ranks) == std::vector<int>{1, 2, 1}));
  CHECK((handicap_strokes(6, ranks) == std::vector<int>{2, 2, 2}));
  CHECK((handicap_strokes(0, ranks) == std::vector<int>{0, 0, 0}));
  // +1 gives a stroke back on the easiest hole.
  CHECK((handicap_strokes(-1, ranks) == std::vector<int>{-1, 0, 0}));
  CHECK((handicap_strokes(-4, ranks) == std::vector<int>{-2, -1, -1}));

  CHECK((net_scores({5, 3, 0, 2}, {1, 2, 1, 3}) == std::vector<int>{4, 1, 0, 1}));
  CHECK((net_scores({4, 4}, {-1, 0}) == std::vector<int>{5, 4}));

  CHECK(playing_handicap(100, 18, 95) == 10);   // 9.5 rounds up
  CHECK(playing_handicap(184, 18, 100) == 18);  // 18.4
  CHECK(playing_handicap(184, 9, 100) == 9);    // 9.2
  CHECK(playing_handicap(-14, 18, 100) == -1);
  CHECK(playing_handicap(kNoHandicap, 18, 100) == 0);

  Scorecard card({4, 3, 5});
  card.record(0, 9);
  card.record(1, 4);
  card.record(2, 5);
  // Net double bogey: 4 + 2 + 1 caps the 9 at 7.
  CHECK(adjusted_gross(card, {1, 0, 0}, true) == 16);
  CHECK(adjusted_gross(card, {0, 0, 0}, false) == 18);  // par + 5 caps the 9 at 9

  CHECK(score_differential(85, 72, 18) == 130);
  CHECK(score_differential(42, 36, 9) == 120);
  CHECK(score_differential(70, 72, 18) == -20);
  CHECK(score_differential(41, 35, 7) == 154);  // 6 * 18 / 7 = 15.43

  CHECK(handicap_rounds_used(2) == 0 && handicap_rounds_used(6) == 2 && handicap_rounds_used(19) == 7);
  CHECK(handicap_rounds_used(20) == 8 && handicap_rounds_used(40) == 8);
  CHECK(handicap_index({130, 120}) == kNoHandicap);
  CHECK(handicap_index({130, 120, 150}) == 100);       // lowest one, -2.0
  CHECK(handicap_index({130, 120, 150, 140}) == 110);  // -1.0
  CHECK(handicap_index({130, 125, 150, 140, 160, 170}) == 118);  // (12.5 + 13.0) / 2 = 12.75 -> 12.8, -1.0
  std::vector<int> many;
  for (int i = 0; i < 25; ++i) {
    many.push_back(100 + i * 10);  // the oldest five drop out
  }
  // Recent 20 are 15.0 to 34.0; the lowest 8 average 18.5.
  CHECK(handicap_index(many) == 185);
  CHECK(handicap_index({700, 650, 800}) == kMaxHandicapTenths);
  CHECK(handicap_index({-300, -250, -200}) == kMinHandicapTenths);

  CHECK(format_handicap(123) == "12.3");
  CHECK(format_handicap(-14) == "+1.4");
  CHECK(format_handicap(0) == "0.0");
  CHECK(format_handicap(kNoHandicap) == "-");
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

void test_wind_moves_the_ball() {
  FlatTerrain ground(Surface::Fairway);
  BallState launch = launch_from_swing(club("7i"), {}, Surface::Fairway);
  BallParams calm;
  BallParams head;
  head.wind = {0, 0, -8};
  BallParams tail;
  tail.wind = {0, 0, 8};
  BallParams cross;
  cross.wind = {8, 0, 0};  // blowing towards the golfer's left
  ShotResult c = simulate_shot(launch, calm, ground);
  ShotResult h = simulate_shot(launch, head, ground);
  ShotResult t = simulate_shot(launch, tail, ground);
  ShotResult x = simulate_shot(launch, cross, ground);
  std::printf("  7i wind: calm carry %.2f, head carry %.2f, tail carry %.2f, cross carry %.2f drift %.2f m\n",
              c.carry_m, h.carry_m, t.carry_m, x.carry_m, x.first_landing.x);
  CHECK(h.carry_m < c.carry_m - 10);
  CHECK(t.carry_m > c.carry_m + 5);
  // Into the wind hurts more than downwind helps.
  CHECK(c.carry_m - h.carry_m > t.carry_m - c.carry_m);
  CHECK(x.first_landing.x > 5);
  CHECK(x.first_landing.x < 30);
}

// A stand-in for the executable: two coefficient tables in the game's layout
// with made-up values, between filler bytes. Built the same way by
// game/tests/run_tests.gd.
std::vector<std::uint8_t> synthetic_aero_exe() {
  std::vector<std::uint8_t> out(64, 0xCD);
  auto u32 = [&](std::uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
  };
  auto f32 = [&](float f) {
    std::uint32_t bits;
    std::memcpy(&bits, &f, 4);
    u32(bits);
  };
  for (int table = 0; table < 2; ++table) {
    u32(11);
    u32(14);
    for (int r = 0; r < 11; ++r) f32(30.0f * r);
    for (int c = 0; c < 14; ++c) f32(10.0f * c);
    u32(0x00401000);
    u32(0x0040102c);
    u32(0);
    for (int r = 0; r < 11; ++r) {
      for (int c = 0; c < 14; ++c) {
        f32(table == 0 ? 0.2f + 0.01f * r + 0.001f * c : 0.01f * c);
      }
    }
    for (int i = 0; i < 40; ++i) out.push_back(0xCD);
  }
  return out;
}

void test_links_aero_tables() {
  std::optional<LinksAero> aero = find_links_aero(synthetic_aero_exe());
  CHECK(aero.has_value());
  if (!aero) {
    return;
  }
  CHECK_NEAR(aero->drag.at(45, 15), 0.2165, 1e-6);
  CHECK_NEAR(aero->lift.at(45, 15), 0.015, 1e-6);
  CHECK_NEAR(aero->drag.at(-5, 500), 0.2 + 0.013, 1e-6);  // clamped to the grid
  CHECK_NEAR(aero->lift.at(1000, 0), 0.0, 1e-9);
  CHECK(!find_links_aero(std::vector<std::uint8_t>(400, 0)).has_value());
}

void test_links_flight() {
  std::optional<LinksAero> aero = find_links_aero(synthetic_aero_exe());
  if (!aero) {
    CHECK(false);
    return;
  }
  // No spin and no speed: gravity alone, 32.152 ft/s^2.
  BallState still{{0, 10, 0}, {0, 0, 0}, {0, 0, 0}};
  BallState next = links_step_flight(still, *aero, {}, 0.5);
  CHECK_NEAR(next.velocity.y, -32.152 * 0.3048 * 0.5, 1e-9);
  CHECK_NEAR(next.position.y, 10 - 32.152 * 0.3048 * 0.125, 1e-9);
  // Spin keeps 0.9994 of itself every 1/60 s.
  BallState spinning{{0, 10, 0}, {0, 0, 0}, {100, 0, 0}};
  CHECK_NEAR(links_step_flight(spinning, *aero, {}, 1.0).spin.x, 100 * std::pow(0.9994, 60), 1e-9);

  FlatTerrain ground(Surface::Fairway);
  BallParams p;
  p.links = &*aero;
  BallState launch = launch_from_swing(club("7i"), {}, Surface::Fairway);
  ShotResult calm = simulate_shot(launch, p, ground);
  p.wind = {0, 0, -8};
  ShotResult head = simulate_shot(launch, p, ground);
  std::printf("  links 7i: carry %.2f m, apex %.2f m, headwind carry %.2f m\n", calm.carry_m, calm.apex_m,
              head.carry_m);
  CHECK(calm.carry_m > 100 && calm.carry_m < 250);
  CHECK(head.carry_m < calm.carry_m);
}

// The ground in the game's frame for the Links ground tests: a plane, or a
// flat shelf ending in a 3 ft drop at y = 5.
class TestGround : public LinksGround {
 public:
  TestGround(int cls, double gx = 0, double gy = 0, bool cliff = false) : cls_(cls), gx_(gx), gy_(gy), cliff_(cliff) {}
  double height(double x, double y) const override {
    if (cliff_) {
      return y < 5 ? 0 : -3;
    }
    return gx_ * x + gy_ * y;
  }
  Vec3 normal(double, double) const override {
    Vec3 n{-gx_, -gy_, 1};
    return n * (1 / length(n));
  }
  LinksSurface surface(double, double) const override { return links_surface(cls_); }

 private:
  int cls_;
  double gx_, gy_;
  bool cliff_;
};

// No air: the tables are all zero, so flight is gravity alone.
LinksAero still_air() {
  CoefficientTable t{{0, 1}, {0, 1}, {0, 0, 0, 0}};
  return LinksAero{t, t};
}

// Steps until the ball stops; returns the step it stopped on, or -1.
int run_links_ball(LinksBall& b, const LinksGround& g, LinksRandom& rng, int max_steps = 2000) {
  LinksAero air = still_air();
  for (int k = 0; k < max_steps; ++k) {
    links_step(b, g, air, {}, rng);
    if (b.mode == LinksMode::Rest) {
      return k;
    }
  }
  return -1;
}

LinksBall links_ball(Vec3 pos, Vec3 vel, Vec3 spin, LinksMode mode) {
  LinksBall b;
  b.position = pos;
  b.velocity = vel;
  b.spin = spin;
  b.mode = mode;
  if (mode != LinksMode::Flight) {
    b.on_ground_started = true;
    b.checkpoint_x = pos.x;
    b.checkpoint_y = pos.y;
  }
  return b;
}

// The expected numbers below come from running the game's own code (see
// docs/formats/physics.md); the ball stops on the same 1/60 s step.
void test_links_random() {
  LinksRandom rng;
  CHECK(rng.next_u32() == 0x79a8b120u);
  CHECK(rng.state() == 0x65b8545cu);
  CHECK(rng.next_u32() == 0xe8a8769au);
  CHECK(rng.state() == 0x3cbd052fu);
  CHECK(LinksRandom::seed_for(12.7, -3.2) == static_cast<std::uint32_t>(-36));
  CHECK(LinksRandom::seed_for(0.5, 100) == 0x12345678u);
}

void test_links_impact() {
  // Fairway, 45 degrees in at 56.6 ft/s with backspin.
  LinksBall b = links_ball({0, 0, 0.07}, {0, 40, -40}, {100, 0, 0}, LinksMode::Flight);
  links_impact(b, {0, 0, 1}, links_surface(kLinksFairway));
  CHECK_NEAR(b.velocity.y, 16.3559, 1e-3);
  CHECK_NEAR(b.velocity.z, 10.6632, 1e-3);
  CHECK_NEAR(b.spin.x, 62.2534, 1e-3);
  CHECK(b.mode == LinksMode::Flight);
  // Green, steeper with more spin.
  b = links_ball({0, 0, 0.07}, {0, 30, -45}, {150, 0, 0}, LinksMode::Flight);
  links_impact(b, {0, 0, 1}, links_surface(kLinksGreen));
  CHECK_NEAR(b.velocity.y, 9.5844, 1e-3);
  CHECK_NEAR(b.velocity.z, 10.35, 1e-3);
  CHECK_NEAR(b.spin.x, 119.3187, 1e-3);
  // Rough turns the ball by an angle picked from where it lands.
  b = links_ball({12.3, 40.7, 0.07}, {5, 40, -30}, {60, 0, 0}, LinksMode::Flight);
  links_impact(b, {0, 0, 1}, links_surface(kLinksRough));
  CHECK_NEAR(b.velocity.x, 1.3239, 1e-3);
  CHECK_NEAR(b.velocity.y, 21.9725, 1e-3);
  CHECK_NEAR(b.velocity.z, 7.2864, 1e-3);
  CHECK_NEAR(b.spin.y, -2.7779, 1e-3);
  // Water stops it.
  b = links_ball({0, 0, 0.07}, {0, 40, -40}, {100, 0, 0}, LinksMode::Flight);
  links_impact(b, {0, 0, 1}, links_surface(kLinksWater));
  CHECK(b.mode == LinksMode::Rest);

  CHECK_NEAR(links_contact_time({1, 2, -3}, {1, 2, -3.5}, 0.4), 0.4, 1e-12);
  CHECK_NEAR(links_contact_time({0, 2, -3}, {0, 1.5, -3.5}, 0.7), 0.72827, 1e-5);
}

void test_links_green() {
  // Medium and normal are the class defaults; each step of speed moves the
  // rolling resistance one firmness along.
  LinksSurface g = links_green(LinksGreenFirmness::Medium, LinksGreenSpeed::Normal);
  CHECK_NEAR(g.roll_resistance, 0.10538, 1e-6);
  CHECK_NEAR(g.spin_grip, 1.219, 1e-6);
  CHECK_NEAR(links_green(LinksGreenFirmness::Medium, LinksGreenSpeed::Fast).roll_resistance, 0.09, 1e-7);
  CHECK_NEAR(links_green(LinksGreenFirmness::Medium, LinksGreenSpeed::Slow).roll_resistance, 0.12076, 1e-7);
  CHECK_NEAR(links_green(LinksGreenFirmness::Firm, LinksGreenSpeed::Fast).roll_resistance, 0.07462, 1e-7);
  CHECK_NEAR(links_green(LinksGreenFirmness::Soft, LinksGreenSpeed::Slow).roll_resistance, 0.13614, 1e-7);
  LinksSurface firm = links_green(LinksGreenFirmness::Firm, LinksGreenSpeed::Slow);
  CHECK_NEAR(firm.roll_resistance, 0.10538, 1e-6);
  CHECK_NEAR(firm.restitution, 0.25, 1e-7);
  CHECK_NEAR(firm.spin_grip, 1.3, 1e-6);
  CHECK_NEAR(links_green(LinksGreenFirmness::Soft, LinksGreenSpeed::Normal).spin_grip, 0.9, 1e-6);
  CHECK(firm.ground_class == kLinksGreen);
}

void test_links_roll() {
  LinksRandom rng;
  // A fast roll on a flat fairway.
  LinksBall b = links_ball({0, 0, 0.07}, {0, 45, 0}, {-102.3, 0, 0}, LinksMode::Roll);
  CHECK(run_links_ball(b, TestGround(kLinksFairway), rng) == 382);
  CHECK_NEAR(b.position.y, 119.867, 2e-3);
  // Sliding across a sloping green with sidespin.
  b = links_ball({0, 0, 0.07}, {2, 25, 0}, {30, 0, 10}, LinksMode::Skid);
  CHECK(run_links_ball(b, TestGround(kLinksGreen, 0.03, -0.02), rng) == 334);
  CHECK_NEAR(b.position.x, -0.219, 2e-3);
  CHECK_NEAR(b.position.y, 47.457, 2e-3);
  // Off a 3 ft drop: the ball takes off, lands and rolls on.
  b = links_ball({0, 0, 0.07}, {0, 15, 0}, {-34.1, 0, 0}, LinksMode::Roll);
  CHECK(run_links_ball(b, TestGround(kLinksFairway, 0, 0, true), rng) == 155);
  CHECK_NEAR(b.position.y, 19.705, 2e-3);
}

void test_links_landing() {
  LinksRandom rng;
  LinksBall b = links_ball({0, 0, 0.3}, {0, 40, -40}, {100, 0, 0}, LinksMode::Flight);
  CHECK(run_links_ball(b, TestGround(kLinksFairway), rng) == 114);
  CHECK_NEAR(b.position.y, 18.366, 2e-3);
  b = links_ball({0, 0, 0.3}, {0, 40, -40}, {100, 0, 0}, LinksMode::Flight);
  CHECK(run_links_ball(b, TestGround(kLinksSand), rng) == 55);
  CHECK_NEAR(b.position.y, 8.888, 2e-3);
  // Rough makes the ball hop now and then (the game's random numbers from
  // their starting seed).
  b = links_ball({0, 0, 0.07}, {0, 20, 0}, {-45.47, 0, 0}, LinksMode::Roll);
  CHECK(run_links_ball(b, TestGround(kLinksRough), rng) == 138);
  CHECK_NEAR(b.position.x, -2.594, 2e-3);
  CHECK_NEAR(b.position.y, 19.371, 2e-3);
  // Rocks kick it about until a slow ball is stopped.
  LinksRandom rocks(0x65b8545cu);
  b = links_ball({0, 0, 0.07}, {0, 14, 0}, {-31.8, 0, 0}, LinksMode::Roll);
  CHECK(run_links_ball(b, TestGround(kLinksRocks), rocks) == 74);
  CHECK_NEAR(b.position.y, 2.761, 2e-3);
}

void test_links_shot() {
  std::optional<LinksAero> aero = find_links_aero(synthetic_aero_exe());
  if (!aero) {
    CHECK(false);
    return;
  }
  BallParams p;
  p.links = &*aero;
  FlatTerrain fairway(Surface::Fairway);
  ShotResult r = simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, fairway);
  std::printf("  links PW: carry %.2f m, total %.2f m, %d bounces\n", r.carry_m, r.total_m, r.bounces);
  CHECK(r.outcome == ShotOutcome::Rest);
  CHECK(r.bounces >= 1);
  CHECK(r.total_m > r.carry_m);
  CHECK_NEAR(r.rest.y, 0.0, 1e-6);
  // A putt that drops.
  FlatTerrain green(Surface::Green);
  ShotOptions opt;
  opt.has_cup = true;
  opt.cup = {0, 0, 3};
  ShotResult putt = simulate_shot(BallState{{0, 0, 0}, {0, 0, 3.55}, {}}, p, green, opt);
  std::printf("  putt %s at %.3f %.3f %.3f\n", outcome_name(putt.outcome), putt.rest.x, putt.rest.y, putt.rest.z);
  CHECK(putt.outcome == ShotOutcome::Holed);
  FlatTerrain water(Surface::Water);
  CHECK(simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, water).outcome == ShotOutcome::Water);

  // A course's own surface values replace the class defaults (but not on
  // greens, which take the green options), and the hole's bounds are judged
  // where the ball stops: a ball that crosses the line and comes back is in.
  class CourseGround : public FlatTerrain {
   public:
    CourseGround(double limit, Surface s) : FlatTerrain(s), limit_(limit) {
      own_ = links_surface(s == Surface::Green ? kLinksGreen : kLinksFairway);
      own_.roll_resistance *= 2;
    }
    bool in_bounds(double, double z) const override { return z < limit_; }
    const LinksSurface* links_surface_at(double, double) const override { return &own_; }

   private:
    double limit_;
    LinksSurface own_;
  };
  ShotResult slow = simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, CourseGround(1e9, Surface::Fairway));
  CHECK(slow.outcome == ShotOutcome::Rest);
  CHECK(slow.total_m < r.total_m - 0.5);
  CHECK_NEAR(slow.carry_m, r.carry_m, 1e-9);
  CHECK(simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, CourseGround(slow.rest.z - 1, Surface::Fairway))
            .outcome == ShotOutcome::OutOfBounds);
  CHECK(simulate_shot(launch_from_swing(club("PW"), {}, Surface::Fairway), p, CourseGround(slow.rest.z + 1, Surface::Fairway))
            .outcome == ShotOutcome::Rest);
  ShotResult green_own = simulate_shot(BallState{{0, 0, 0}, {0, 0, 3.0}, {}}, p, CourseGround(1e9, Surface::Green));
  ShotResult green_class = simulate_shot(BallState{{0, 0, 0}, {0, 0, 3.0}, {}}, p, green);
  CHECK_NEAR(green_own.total_m, green_class.total_m, 1e-12);
}

// A made-up club table in the layout the game uses: five rows of 19 values
// and a spare zero, behind some unrelated bytes.
std::vector<std::uint8_t> synthetic_club_exe() {
  std::vector<std::uint8_t> out(36, 0x11);
  auto f32 = [&](float v) {
    std::uint32_t bits;
    std::memcpy(&bits, &v, sizeof bits);
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<std::uint8_t>(bits >> (8 * i)));
  };
  for (int i = 0; i < 19; ++i) f32(1.5f + 0.2f * i);
  f32(0);
  for (int i = 0; i < 19; ++i) f32(2.0f + 0.01f * i);
  f32(0);
  for (int i = 0; i < 19; ++i) f32(i < 7 ? 10.0f + 2.0f * i : 14.0f + 4.0f * (i - 7));
  f32(0);
  for (int i = 0; i < 19; ++i) f32(0.05f + 0.01f * i);
  f32(0);
  for (int i = 0; i < 19; ++i) f32(10.0f + 0.5f * i);
  f32(0);
  return out;
}

void check_launch(const LinksClubTable& t, const LinksStrike& s, std::array<double, 6> want) {
  LinksLaunch l = links_launch(t, s);
  double got[6] = {l.velocity.x, l.velocity.y, l.velocity.z, l.spin.x, l.spin.y, l.spin.z};
  for (int i = 0; i < 6; ++i) CHECK_NEAR(got[i], want[i], 2e-4);
}

void test_links_launch() {
  std::optional<LinksClubTable> t = find_links_clubs(synthetic_club_exe());
  CHECK(t.has_value());
  CHECK(!find_links_clubs(std::vector<std::uint8_t>(600, 0)).has_value());
  if (!t) {
    return;
  }
  CHECK_NEAR(t->loft_deg[7], 14.0, 1e-6);
  // A square driver: straight down the line with pure backspin.
  LinksStrike s;
  check_launch(*t, s, {0, 195.679363, 24.503551, 73.860581, 0, 0});
  // Aimed left, ball back, face open, stance closed, a little closed at impact.
  s = LinksStrike{};
  s.club = 12;
  s.aim = 0.4;
  s.power = 85;
  s.face_error = 0.03;
  s.path_error = -0.02;
  s.setup = {6, 33, 27};
  check_launch(*t, s, {-60.178063, 130.934603, 58.414966, 135.705451, 62.62540, -0.570758});
  // On a slope, with the multipliers away from 1.
  s = LinksStrike{};
  s.club = 5;
  s.aim = -1.2;
  s.power = 70;
  s.face_error = -0.05;
  s.path_error = 0.04;
  s.spin_scale = 0.9;
  s.speed_scale = 1.05;
  s.loft_scale = 1.1;
  s.setup = {4, 26, 32};
  s.ground_normal = {0.2, -0.1, std::sqrt(1 - 0.05)};
  check_launch(*t, s, {130.663751, 47.660517, 18.457195, 27.686730, -73.138883, -7.141661});
  // A steep slope is clamped to 30 degrees across and 15 along the line.
  s = LinksStrike{};
  s.club = 18;
  s.aim = 2.5;
  s.power = 60;
  s.setup.ball_position = 1;
  s.ground_normal = {-0.3, 0.25, std::sqrt(1 - 0.09 - 0.0625)};
  check_launch(*t, s, {-24.752554, -31.449690, 48.410392, -62.535463, 46.668793, -1.656532});
  // In olcore's frame (+y up, +z downrange) backspin turns about -x.
  BallState b = links_launch_state(*t, LinksStrike{});
  CHECK_NEAR(b.velocity.z, 195.679363 * 0.3048, 1e-4);
  CHECK_NEAR(b.velocity.y, 24.503551 * 0.3048, 1e-4);
  CHECK_NEAR(b.spin.x, -73.860581 * 2 * 3.14159265358979, 1e-3);
}

void test_links_lie() {
  LinksStrike s;
  s.face_error = 0.05;
  links_apply_lie(s, links_surface(kLinksFairway));
  CHECK_NEAR(s.spin_scale, 1.0, 1e-12);
  CHECK_NEAR(s.speed_scale, 1.0, 1e-12);
  CHECK_NEAR(s.face_error, 0.05, 1e-12);
  links_apply_lie(s, links_surface(kLinksRough));
  CHECK_NEAR(s.spin_scale, 0.406505, 1e-9);
  CHECK_NEAR(s.speed_scale, 0.927315, 1e-9);
  links_apply_lie(s, links_surface(kLinksDeepGrass));
  CHECK_NEAR(s.spin_scale, 0.1992, 1e-9);
  // Sand: the face error goes, and the contact sets speed, spin and loft.
  struct Case {
    int contact;
    double speed, spin, loft;
  };
  for (Case c : {Case{0, 0.4, 1.5, 1}, Case{3, 0.38, 1.25, 1}, Case{10, 0.333333, 0.666667, 1},
                 Case{-3, 0.7, 1.2, 1}, Case{-5, 0.9, 1.0, 1}, Case{-8, 0.705, 0.7, 0.73}}) {
    LinksStrike t;
    t.face_error = 0.05;
    links_apply_lie(t, links_surface(kLinksSand), c.contact);
    CHECK_NEAR(t.face_error, 0.0, 1e-12);
    CHECK_NEAR(t.speed_scale, c.speed, 1e-6);
    CHECK_NEAR(t.spin_scale, c.spin, 1e-6);
    CHECK_NEAR(t.loft_scale, c.loft, 1e-9);
  }
}

// Computer opponents. The printed numbers are checked by the GDScript port
// (game/tests/run_tests.gd, _test_opponent_skill_matches_olcore).
void test_opponent_rng_and_swings() {
  OpponentRng r(2003);
  CHECK(r.next() == 532058734u);
  CHECK(r.next() == 1922934515u);
  OpponentRng q(7);
  double u = q.uniform();
  double g = q.normal();
  std::printf("  rng: uniform %.9f normal %.9f\n", u, g);
  OpponentRng s(42);
  for (int level = 0; level < kSkillLevelCount; ++level) {
    const SkillProfile& skill = skill_profile(static_cast<SkillLevel>(level));
    SwingInput full = execute_swing({0.9, 0.0, 10.0}, false, skill, s);
    SwingInput putt = execute_swing({0.4, 0.0, -5.0}, true, skill, s);
    std::printf("  %s: full %.6f %.6f %.6f, putt %.6f %.6f\n", skill.name, full.power, full.accuracy, full.aim_deg,
                putt.power, putt.aim_deg);
    CHECK(putt.accuracy == 0.0);
  }
}

// Drops. A hole running up +z to a pin at z = 100: a stream across it from
// z = 40 to 60, out of bounds beyond x = 30, a bunker round (10, 80), a cart
// path from x = -12 to -10 and the green within 5 m of the pin. The printed
// spots are checked by the GDScript port (game/tests/run_tests.gd,
// _test_drop_rules_match_olcore).
class RulesTerrain : public Terrain {
 public:
  double height(double x, double z) const override { return 0.01 * x + 0.02 * z; }
  Surface surface(double x, double z) const override {
    if (x > 30) return Surface::OutOfBounds;
    if (std::hypot(x, z - 100) < 5) return Surface::Green;
    if (z >= 40 && z <= 60) return Surface::Water;
    if (std::hypot(x - 10, z - 80) < 4) return Surface::Sand;
    return Surface::Fairway;
  }
  bool free_drop(double x, double) const override { return x > -12 && x < -10; }
};

// A course's hazards and hole bounds count for drops too.
class BoundedRulesTerrain : public RulesTerrain {
 public:
  bool hazard(double x, double z) const override { return std::hypot(x + 5, z - 70) < 3; }
  bool in_bounds(double x, double) const override { return x < 20; }
};

void test_drop_rules_hazards_and_bounds() {
  BoundedRulesTerrain t;
  Vec3 pin{0, 2, 100};
  DropZone side = drop_zone(DropOption::Lateral, {-5, 0, 75}, {0, 0, 0}, pin, false, t);
  CHECK(check_drop(side, {-5, 0, 71}, pin, t) == DropCheck::Hazard);
  CHECK(check_drop(side, {25, 0, 80}, pin, t) == DropCheck::OutOfBounds);
  // Free relief is never found in a hazard or out of bounds.
  DropZone free = drop_zone(DropOption::FreeDrop, {-11, 0, 70}, {0, 0, 0}, pin, false, t);
  CHECK(free.found);
  CHECK(!t.hazard(free.spot.x, free.spot.z) && t.in_bounds(free.spot.x, free.spot.z));
  std::printf("  free relief beside the hazard at %.4f %.4f\n", free.spot.x, free.spot.z);
}

void test_drop_rules() {
  RulesTerrain t;
  Vec3 pin{0, 2, 100};
  CHECK(drop_penalty(DropReason::Water) == 1);
  CHECK(drop_penalty(DropReason::Unplayable) == 1);
  CHECK(drop_penalty(DropReason::FreeRelief) == 0);
  CHECK(drop_options(DropReason::Water, false).size() == 2);
  CHECK(drop_options(DropReason::Water, true).size() == 3);
  CHECK(drop_options(DropReason::FreeRelief, true).size() == 1);

  // A shot from (0, 0) that finishes in the stream at (6, 52).
  std::vector<Vec3> path;
  for (int i = 0; i <= 13; ++i) path.push_back({6.0 * i / 13, 3.0, 52.0 * i / 13});
  Vec3 entry = water_entry(path, t);
  CHECK_NEAR(entry.z, 40.0, 1e-3);
  CHECK_NEAR(entry.x, 6.0 * 40 / 52, 1e-3);
  Vec3 tee{0, 0, 0};
  DropZone back = drop_zone(DropOption::BackOnLine, entry, tee, pin, false, t);
  DropZone side = drop_zone(DropOption::Lateral, entry, tee, pin, false, t);
  DropZone again = drop_zone(DropOption::StrokeAndDistance, entry, tee, pin, false, t);
  CHECK(back.found && side.found && again.found);
  CHECK(check_drop(back, back.spot, pin, t) == DropCheck::Ok);
  CHECK(check_drop(side, side.spot, pin, t) == DropCheck::Ok);
  CHECK(std::hypot(side.spot.x - entry.x, side.spot.z - entry.z) <= 2 * kClubLength + 1e-9);
  CHECK(again.spot.z == 0.0);
  CHECK(best_drop({back, side, again}, pin) == 1);  // the lateral drop is nearer the pin
  CHECK(best_drop({again}, pin) == 0);
  CHECK(check_drop(back, {entry.x, 0, 45}, pin, t) == DropCheck::Hazard);
  CHECK(check_drop(back, {back.spot.x + 2, 0, back.spot.z}, pin, t) == DropCheck::OutsideZone);
  CHECK(check_drop(side, {entry.x, 0, 37.5}, pin, t) == DropCheck::OutsideZone);
  CHECK(check_drop(side, {entry.x - 0.5, 0, entry.z - 0.01}, pin, t) == DropCheck::NearerPin);

  // Unplayable in the bunker: the drop stays in the sand.
  Vec3 sand{10, 0, 80};
  DropZone sand_back = drop_zone(DropOption::BackOnLine, sand, tee, pin, true, t);
  DropZone sand_side = drop_zone(DropOption::Lateral, sand, tee, pin, true, t);
  CHECK(sand_back.found && sand_side.found);
  CHECK(t.surface(sand_back.spot.x, sand_back.spot.z) == Surface::Sand);
  CHECK(check_drop(sand_back, {10, 0, 75.5}, pin, t) == DropCheck::NotSand);
  CHECK(check_drop(sand_back, {35, 0, 80}, pin, t) == DropCheck::OutOfBounds);
  Vec3 near_green{0, 0, 94};
  DropZone green_side = drop_zone(DropOption::Lateral, near_green, tee, pin, false, t);
  CHECK(check_drop(green_side, {0, 0, 95.5}, pin, t) == DropCheck::Green);

  // Free relief from the cart path, away from the pin side.
  Vec3 path_ball{-11, 0, 20};
  DropZone free = drop_zone(DropOption::FreeDrop, path_ball, tee, pin, false, t);
  CHECK(free.found);
  CHECK(!t.free_drop(free.reference.x, free.reference.z));
  CHECK(std::hypot(free.reference.x - pin.x, free.reference.z - pin.z) >=
        std::hypot(path_ball.x - pin.x, path_ball.z - pin.z) - 1e-3);
  CHECK(check_drop(free, path_ball, pin, t) == DropCheck::StillOnPath);
  std::printf("  drops: entry %.4f %.4f %.4f, back %.4f %.4f %.4f, lateral %.4f %.4f, sand %.4f %.4f / %.4f %.4f, free %.4f %.4f / %.4f %.4f\n",
              entry.x, entry.y, entry.z, back.spot.x, back.spot.y, back.spot.z, side.spot.x, side.spot.z,
              sand_back.spot.x, sand_back.spot.z, sand_side.spot.x, sand_side.spot.z, free.reference.x,
              free.reference.z, free.spot.x, free.spot.z);
}

void test_opponent_levels_are_ordered() {
  for (int level = 1; level < kSkillLevelCount; ++level) {
    const SkillProfile& a = skill_profile(static_cast<SkillLevel>(level - 1));
    const SkillProfile& b = skill_profile(static_cast<SkillLevel>(level));
    CHECK(b.power_sd < a.power_sd);
    CHECK(b.accuracy_sd < a.accuracy_sd);
    CHECK(b.putt_aim_sd_deg < a.putt_aim_sd_deg);
    CHECK(b.mishit_chance < a.mishit_chance);
    CHECK(b.strength > a.strength);
  }
  // Through the physics: the better golfer is straighter off the tee and
  // holes more eight-footers.
  BallParams p;
  FlatTerrain fairway(Surface::Fairway);
  FlatTerrain green(Surface::Green);
  ShotOptions opt;
  opt.has_cup = true;
  opt.cup = {0, 0, 2.4};
  double pace = std::sqrt(2.0 * surface_params(Surface::Green).rolling_resistance * 9.81 * 2.8) / club("Pt").ball_speed_mps;
  double spread[2] = {0, 0};
  int holed[2] = {0, 0};
  const SkillLevel levels[2] = {SkillLevel::Beginner, SkillLevel::Tour};
  for (int k = 0; k < 2; ++k) {
    const SkillProfile& skill = skill_profile(levels[k]);
    OpponentRng rng(99);
    for (int i = 0; i < 200; ++i) {
      SwingInput drive = execute_swing({skill.strength, 0, 0}, false, skill, rng);
      spread[k] += std::fabs(simulate_shot(launch_from_swing(club("Dr"), drive, Surface::Tee), p, fairway).rest.x);
      SwingInput putt = execute_swing({pace, 0, 0}, true, skill, rng);
      if (simulate_shot(launch_from_swing(club("Pt"), putt, Surface::Green), p, green, opt).outcome == ShotOutcome::Holed) {
        ++holed[k];
      }
    }
  }
  std::printf("  drive spread %.1f / %.1f m, 8 ft putts %d / %d of 200\n", spread[0] / 200, spread[1] / 200, holed[0],
              holed[1]);
  CHECK(spread[1] < spread[0] * 0.7);
  CHECK(holed[1] > holed[0] + 30);
}

void test_expected_strokes() {
  CHECK_NEAR(expected_strokes(0.0, Surface::Green), 1.0, 1e-9);
  CHECK_NEAR(expected_strokes(8 / 3.2808399, Surface::Green), 1.5, 1e-6);
  CHECK_NEAR(expected_strokes(150 / 1.0936133, Surface::Fairway), 2.98, 1e-6);
  CHECK(expected_strokes(100, Surface::Rough) > expected_strokes(100, Surface::Fairway));
  CHECK(expected_strokes(100, Surface::Sand) > expected_strokes(100, Surface::Rough));
  CHECK(expected_strokes(100, Surface::DeepRough) > expected_strokes(100, Surface::Sand));
  double last = 0;
  for (double d = 0; d < 600; d += 5) {
    double e = expected_strokes(d, Surface::Fairway);
    CHECK(e >= last);
    last = e;
  }
  for (double d : {0.5, 6.0, 30.0, 140.0, 600.0}) {
    std::printf("  expected strokes %.1f m: green %.6f fringe %.6f sand %.6f\n", d, expected_strokes(d, Surface::Green),
                expected_strokes(d, Surface::Fringe), expected_strokes(d, Surface::Sand));
  }
}

void test_links_swing() {
  LinksRand r(1);
  CHECK(r.next() == 41);
  CHECK(r.next() == 18467);
  CHECK(r.next() == 6334);
  // The PowerStroke meter: a snap 16 units past the perfect zone is one step
  // on the middle levels but not on the easiest or the hardest.
  CHECK(links_meter_contact(16, 0) == 0);
  CHECK(links_meter_contact(16, 1) == 1);
  CHECK(links_meter_contact(16, 3) == 0);
  CHECK(links_meter_contact(17, 3) == 1);
  CHECK(links_meter_contact(-30, 3) == -1);
  CHECK(links_meter_contact(10, 2) == 0);

  struct Case {
    int ground_class, club, skill;
    bool mouse;
    int contact;
    double power;
    unsigned seed;
    bool left_handed, teed_up;
    double aim, out_power, face, path, spin, speed, loft;
  };
  // Checked against the game's own code running in an emulator.
  for (const Case& c : {
           Case{kLinksRough, 13, 3, false, -1, 100, 12345, false, false, 0.073820061, 98.9875, 0.011343904,
                0.006179939, 0.306505, 0.897315, 1},
           Case{kLinksFairway, 0, 2, false, 1, 100, 777, false, false, 0.117637011, 98.105, 0.010139626, -0.037637011,
                0.9, 0.902034979, 1},
           Case{kLinksDirt, 7, 1, false, 2, 90, 99, false, false, 0.148869219, 90, 0.01, -0.068869219, 0.92, 0.9728, 1},
           Case{kLinksRough, 11, 3, true, -2, 100, 5, false, false, 0.1, 100, 0.043633231, -0.06981317, 0.25,
                0.927315, 0.95},
           Case{kLinksSand, 17, 3, false, -1, 100, 42, true, false, 0.1, 94.8025, 0, 0, 1.416666667, 0.393333333, 1},
           Case{kLinksFairway, 0, 3, false, 1, 100, 2003, false, true, 0.116496095, 97.3625, 0.011466077,
                -0.036406095, 1, 1, 1},
       }) {
    LinksStrike s;
    s.club = c.club;
    s.power = c.power;
    s.aim = 0.1;
    s.face_error = 0.01;
    s.path_error = -0.02;
    LinksSwing w;
    w.method = c.mouse ? LinksSwingMethod::Mouse : LinksSwingMethod::PowerStroke;
    w.skill = c.skill;
    w.contact = c.contact;
    w.mouse_face_deg = 2.5;
    w.mouse_path_deg = -4;
    w.mouse_loft = 0.95;
    w.left_handed = c.left_handed;
    w.teed_up = c.teed_up;
    LinksRand rng(c.seed);
    links_apply_swing(s, w, links_surface(c.ground_class), rng);
    CHECK_NEAR(s.aim, c.aim, 1e-8);
    CHECK_NEAR(s.power, c.out_power, 1e-6);
    CHECK_NEAR(s.face_error, c.face, 1e-8);
    CHECK_NEAR(s.path_error, c.path, 1e-8);
    CHECK_NEAR(s.spin_scale, c.spin, 1e-8);
    CHECK_NEAR(s.speed_scale, c.speed, 1e-8);
    CHECK_NEAR(s.loft_scale, c.loft, 1e-9);
  }
  // A chip's PowerStroke miss turns it the same way but keeps its power.
  for (int chip = 0; chip < 2; ++chip) {
    LinksStrike full, chipped;
    LinksStrike& s = chip ? chipped : full;
    s.club = 16;
    s.power = 30;
    LinksSwing w;
    w.skill = 3;
    w.contact = 2;
    w.chip = chip == 1;
    LinksRand rng(99);
    links_apply_swing(s, w, links_surface(kLinksFairway), rng);
    if (chip) {
      CHECK(std::abs(s.power - 30) <= 0.25);
    } else {
      CHECK(s.power < 29);
    }
  }
}

void test_links_computer_putt() {
  // Against the game's own routine: long and short putt ratings, steady,
  // feet to the hole, lie, seed, power, then the power and path (radians).
  struct Case {
    int long_putts, short_putts;
    bool steady;
    double feet;
    int lie;
    unsigned seed;
    double power, want_power, want_path;
  };
  const Case cases[] = {
      {80, 90, false, 20.0, kLinksGreen, 12345u, 8.0, 7.75, 0.266666681},
      {95, 95, false, 40.0, kLinksFairway, 777u, 15.0, 15.0375004, 0.0},
      {60, 85, false, 5.0, kLinksGreen, 99u, 3.0, 3.03686643, -0.0166666675},
      {40, 70, true, 10.0, kLinksRough, 2003u, 6.0, 5.66666651, 0.76666671},
      {85, 100, false, 4.5, kLinksGreen, 42u, 2.5, 2.5, 0.0},
      {70, 60, false, 2.6, kLinksGreen, 5u, 1.5, 1.5625, -0.0250000022},
  };
  for (const Case& c : cases) {
    LinksGolferRatings g;
    g.long_putts = c.long_putts;
    g.short_putts = c.short_putts;
    g.steady = c.steady;
    LinksComputerSwing w;
    w.power = c.power;
    w.path_deg = 0;
    LinksRand rng(c.seed);
    links_computer_putt_miss(w, g, c.lie, c.feet, rng);
    CHECK_NEAR(w.power, c.want_power, 1e-5);
    CHECK_NEAR(w.path_deg * 3.14159265358979323846 / 180, c.want_path, 1e-6);
    CHECK_NEAR(w.face_deg, 0, 1e-12);
  }
  // Inside 2 ft nothing changes and nothing is drawn.
  LinksComputerSwing w;
  w.power = 1;
  LinksRand rng(9);
  links_computer_putt_miss(w, LinksGolferRatings{}, kLinksGreen, 1.5, rng);
  CHECK(rng.state() == 9u);
  CHECK_NEAR(w.power, 1, 1e-12);
}

void test_links_mouse_swing() {
  // A steady stroke: `back` frames pulling `pull` pixels down, then pushing
  // `push` pixels up and `across` right each frame until the club meets the
  // ball. The numbers are run_tests.gd's too.
  struct Case {
    int skill;
    LinksMouseShot shot;
    int club, width;
    unsigned seed;
    int back, pull, push, across;
    double speed, drift, drift_before;
    int down;
    double backswing, power, face, path, loft;
    int quality;
  };
  const Case cases[] = {
      {3, LinksMouseShot::Full, 0, 1920, 11u, 20, 12, 90, 0, -4.772966, 0, 0, 90, 0.297828, 31.626182, 0, 0, 0.157841, 0},
      {1, LinksMouseShot::Full, 9, 1100, 5u, 15, 10, 70, 3, -3.412456, -0.45, -0.27, 70, 0.152596, 11.886348, 0.004837,
       -0.117355, 0.071311, 0},
      {2, LinksMouseShot::Putt, kLinksPutter, 1920, 7u, 12, 6, 40, -2, -0.592555, 0.24, 0, 40, 0.034813, 1.0, -0.360105,
       0.398950, 0.033288, 0},
      {0, LinksMouseShot::Chip, 16, 800, 3u, 10, 8, 50, 1, -0.884124, -0.04, 0, 50, 0.064996, 1.522239, 0.000077,
       -0.021463, 0.064996, 0},
      {3, LinksMouseShot::Full, 4, 1920, 9u, 30, 15, 110, -6, -8.128368, 1.8, 1.2, 127, 0.626433, 77.270356, -1.1742,
       -0.825252, 0.517093, 1},
      {2, LinksMouseShot::Full, 12, 1920, 21u, 25, 14, 100, 12, -7.405264, -2.16, -1.44, 127, 0.428111, 46.535126,
       0.244594, -0.477122, 0.355657, 0},
  };
  for (const Case& c : cases) {
    LinksMouseClub club(c.skill, c.shot, c.club, links_mouse_meter(c.width));
    LinksRand rng(c.seed);
    for (int i = 0; i < c.back; ++i) club.step(0, c.pull, rng);
    for (int i = 0; i < 40 && !club.done(); ++i) club.step(c.across, -c.push, rng);
    CHECK(club.phase() == LinksMouseClub::Phase::Impact);
    const LinksMouseStroke& m = club.stroke();
    CHECK_NEAR(m.speed, c.speed, 1e-5);
    CHECK_NEAR(m.drift, c.drift, 1e-5);
    CHECK_NEAR(m.drift_before, c.drift_before, 1e-5);
    CHECK(m.down == c.down);
    CHECK_NEAR(m.backswing, c.backswing, 1e-5);
    LinksMouseSwing w = links_mouse_swing(m, rng);
    CHECK_NEAR(w.power, c.power, 1e-5);
    CHECK_NEAR(w.face_deg, c.face, 1e-5);
    CHECK_NEAR(w.path_deg, c.path, 1e-5);
    CHECK_NEAR(w.loft, c.loft, 1e-5);
    CHECK(!w.whiff);
    CHECK(w.quality == c.quality);
  }
  // Pushing before pulling back does nothing; letting go early never hits.
  LinksMouseClub idle(3, LinksMouseShot::Full, 0);
  LinksRand rng(1);
  for (int i = 0; i < 10; ++i) idle.step(0, -50, rng);
  CHECK(idle.phase() == LinksMouseClub::Phase::Backswing);
  CHECK_NEAR(idle.club_height(), 119, 1e-12);
  // A big sideways drift misses the ball.
  LinksMouseStroke wild;
  wild.drift = -19;
  wild.down = 80;
  wild.speed = 8;
  LinksMouseSwing miss = links_mouse_swing(wild, rng);
  CHECK(miss.whiff);
  CHECK(miss.power == 0);
  CHECK(links_mouse_meter(800).height == 278 && links_mouse_meter(1024).ball_line == 96 &&
        links_mouse_meter(2560).height == 442);
  // An iron's drift past 10 turns the face three times over.
  LinksMouseStroke iron;
  iron.club = 13;
  iron.speed = -6;
  iron.down = 90;
  iron.backswing = 0.8;
  iron.drift = -12;
  iron.drift_before = -12;
  LinksRand rng2(5);
  LinksMouseSwing hooked = links_mouse_swing(iron, rng2);
  CHECK_NEAR(hooked.power, 44.295517, 1e-5);
  CHECK_NEAR(hooked.face_deg, 35.1, 1e-5);
  CHECK_NEAR(hooked.path_deg, 0, 1e-12);
  // Swing help: a player whose strokes never move sideways gets nudged.
  LinksMouseStroke still;
  still.club = 0;
  still.speed = -6;
  still.down = 90;
  still.backswing = 0.8;
  LinksMouseHelp help;
  help.enabled = true;
  help.strokes = 3;
  help.still_strokes = 3;
  LinksRand rng3(42);
  LinksMouseSwing nudged = links_mouse_swing(still, rng3, &help);
  CHECK_NEAR(nudged.help_deg, 3.9, 1e-9);
  CHECK_NEAR(nudged.path_deg, 2.600013, 1e-5);
  CHECK_NEAR(nudged.power, 65.042229, 1e-5);
  CHECK(help.strokes == 4 && help.still_strokes == 4);
}

void test_links_putt() {
  // The putt's miss, checked against the game's own routine (rand seeded 777):
  // only the face turns, by a draw scaled by the skill.
  const int cases[][2] = {{0, 1}, {1, 1}, {2, 1}, {2, -2}, {2, 3}, {3, 1}, {3, -2}, {3, 3}};
  const double face[] = {0, -0.0111701, -0.017637, 0.0440925, -0.070548, -0.0251327, 0.0502655, -0.0753982};
  for (int i = 0; i < 8; ++i) {
    LinksStrike s;
    s.club = kLinksPutter;
    s.power = 10;
    LinksSwing w;
    w.skill = cases[i][0];
    w.contact = cases[i][1];
    LinksRand rng(777);
    links_apply_swing(s, w, links_surface(kLinksGreen), rng);
    CHECK_NEAR(s.face_error, face[i], 1e-6);
    CHECK_NEAR(s.power, 10, 1e-12);
    CHECK_NEAR(s.path_error, 0, 1e-12);
  }
  // The launch, against a reference checked on the game's code.
  LinksStrike s;
  s.club = kLinksPutter;
  s.face_error = 0.02;
  s.path_error = -0.01;
  s.power = 6;
  s.aim = 0.3;
  Vec3 n = Vec3{0.1, -0.2, 0.97} * (1 / std::sqrt(0.01 + 0.04 + 0.97 * 0.97));
  LinksLaunch l = links_putt(s);
  Vec3 v = links_putt_slope(l.velocity, n), w = links_putt_slope(l.spin, n);
  CHECK_NEAR(v.x, -3.584047, 1e-5);
  CHECK_NEAR(v.y, 13.229612, 1e-5);
  CHECK_NEAR(v.z, -3.111701, 1e-5);
  CHECK_NEAR(w.x, 30.563985, 1e-5);
  CHECK_NEAR(w.y, 9.249282, 1e-5);
  CHECK_NEAR(w.z, 1.233750, 1e-5);
  s.face_error = -0.05;
  s.path_error = 0.03;
  s.power = 12;
  s.aim = -1.1;
  s.setup.face = 33;
  s.setup.stance = 27;
  l = links_putt(s);
  CHECK_NEAR(l.velocity.x, 24.385399, 1e-5);
  CHECK_NEAR(l.velocity.y, 13.987945, 1e-5);
  CHECK_NEAR(l.spin.x, 28.992812, 1e-5);
  CHECK_NEAR(l.spin.y, -56.963907, 1e-5);
  // In the shell's frame it starts on the ground; on a flat green it skids,
  // then rolls about 28 ft.
  LinksClubTable clubs{};
  LinksStrike flat;
  flat.club = kLinksPutter;
  flat.power = 10;
  BallState st = links_launch_state(clubs, flat);
  CHECK(st.on_ground);
  CHECK_NEAR(st.velocity.z, 10 * kLinksPuttSpeed * 0.3048, 1e-9);
  LinksBall b = links_ball({0, 0, 0.07}, links_putt(flat).velocity, links_putt(flat).spin, LinksMode::Skid);
  LinksRandom rng;
  CHECK(run_links_ball(b, TestGround(kLinksGreen), rng) > 0);
  CHECK_NEAR(b.position.y, 27.84, 0.05);
}

void test_links_computer_miss() {
  struct Case {
    int rating, max_power;
    bool steady, teed_up;
    int club;
    bool chip;
    int ground_class;
    double power, feet;
    unsigned seed;
    double out_power, face, path;
  };
  // Checked against the game's own code running in an emulator.
  for (const Case& c : {
           Case{80, 100, false, false, 12, false, kLinksFairway, 100, 300, 12345, 101.21875, 0.3125, 0},
           Case{70, 100, false, true, 0, false, kLinksFairway, 100, 1200, 777, 98.5175018, 0, 0.375},
           Case{60, 100, false, false, 3, false, kLinksRough, 100, 600, 99, 103.9375, 0, 1.875},
           Case{95, 90, false, false, 8, false, kLinksSand, 100, 450, 2003, 100.474998, 0.474999994, 0},
           Case{40, 100, true, false, 17, false, kLinksDeepGrass, 60, 120, 5, 56.360939, 0, 3.9312501},
           Case{65, 100, false, false, 14, true, kLinksPath, 30, 90, 42, 23.4375, 0, -1.125},
       }) {
    LinksGolferRatings g{c.rating, c.rating, c.rating, c.rating, c.rating, c.rating, c.rating, c.max_power, c.steady};
    if (c.teed_up) g.tee = 85;
    LinksComputerSwing w;
    w.power = c.power;
    LinksRand rng(c.seed);
    links_computer_miss(w, g, c.club, c.teed_up, c.chip, c.ground_class, c.feet, rng);
    CHECK_NEAR(w.power, c.out_power, 1e-5);
    CHECK_NEAR(w.face_deg, c.face, 1e-7);
    CHECK_NEAR(w.path_deg, c.path, 1e-7);
  }
}

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
      {"panorama_tiles", test_panorama_tiles},
      {"sky_archive", test_sky_archive},
      {"tga_rle_bottom_up", test_tga_rle_bottom_up},
      {"png_round_trip", test_png_round_trip},
      {"pad_and_bleed", test_pad_and_bleed},
      {"model_reads_tables", test_model_reads_tables},
      {"object_library_parses", test_object_library_parses},
      {"lzw_round_trip", test_lzw_round_trip},
      {"lzw_known_stream", test_lzw_known_stream},
      {"ls_archive", test_ls_archive},
      {"d3f", test_d3f},
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
      {"opponent_rng_and_swings", test_opponent_rng_and_swings},
      {"opponent_levels_are_ordered", test_opponent_levels_are_ordered},
      {"drop_rules", test_drop_rules},
      {"drop_rules_hazards_and_bounds", test_drop_rules_hazards_and_bounds},
      {"expected_strokes", test_expected_strokes},
      {"putt_drops_at_holing_speed", test_putt_drops_at_holing_speed},
      {"putt_distance_follows_green_speed", test_putt_distance_follows_green_speed},
      {"ball_rolls_downhill", test_ball_rolls_downhill},
      {"water_and_out_of_bounds_stop_the_ball", test_water_and_out_of_bounds_stop_the_ball},
      {"obstacle_field_hits", test_obstacle_field_hits},
      {"trees_stop_the_ball", test_trees_stop_the_ball},
      {"wind_moves_the_ball", test_wind_moves_the_ball},
      {"links_aero_tables", test_links_aero_tables},
      {"links_flight", test_links_flight},
      {"links_random", test_links_random},
      {"links_impact", test_links_impact},
      {"links_roll", test_links_roll},
      {"links_green", test_links_green},
      {"links_landing", test_links_landing},
      {"links_shot", test_links_shot},
      {"links_launch", test_links_launch},
      {"links_lie", test_links_lie},
      {"links_swing", test_links_swing},
      {"links_computer_miss", test_links_computer_miss},
      {"links_putt", test_links_putt},
      {"links_mouse_swing", test_links_mouse_swing},
      {"links_computer_putt", test_links_computer_putt},
      {"scorecard", test_scorecard},
      {"game_modes", test_game_modes},
      {"handicaps", test_handicaps},
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
