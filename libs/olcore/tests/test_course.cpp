// Tests for the course cipher, archive and parsers. The real cipher tables
// come from the game executable, so these use made-up tables; the expected
// ciphertexts were produced by an independent implementation that matches
// the game's own output on the real tables.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

#include "olcore/binary_reader.hpp"
#include "olcore/bunky.hpp"
#include "olcore/course.hpp"
#include "olcore/course_areas.hpp"
#include "olcore/course_objects.hpp"
#include "olcore/crz.hpp"
#include "olcore/shadow_file.hpp"
#include "olcore/terrain_mapping.hpp"

namespace {

int g_failures = 0;

#define CHECK(cond)                                                 \
  do {                                                              \
    if (!(cond)) {                                                  \
      std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      ++g_failures;                                                 \
    }                                                               \
  } while (0)

using namespace olcore;
using Bytes = std::vector<std::uint8_t>;

// Linear congruential fill, with the pi words the table finder looks for.
BunkyTables test_tables() {
  BunkyTables t;
  std::uint32_t x = 1;
  for (auto& w : t.p) w = x = x * 1664525u + 1013904223u;
  for (auto& w : t.s) w = x = x * 1664525u + 1013904223u;
  t.p[5] = 0x299f31d0;
  t.p[6] = 0x082efa98;
  t.p[7] = 0xec4e6c89;
  return t;
}

std::string hex(const Bytes& b) {
  std::string s;
  char buf[3];
  for (auto c : b) {
    std::snprintf(buf, sizeof buf, "%02x", c);
    s += buf;
  }
  return s;
}

Bytes counting(std::size_t n) {
  Bytes b(n);
  for (std::size_t i = 0; i < n; ++i) b[i] = std::uint8_t(i);
  return b;
}

void put_u32(Bytes& b, std::uint32_t v) {
  for (int i = 0; i < 4; ++i) b.push_back(std::uint8_t(v >> (8 * i)));
}
void put_u16(Bytes& b, std::uint16_t v) {
  b.push_back(std::uint8_t(v));
  b.push_back(std::uint8_t(v >> 8));
}
void put_f32(Bytes& b, float f) {
  std::uint32_t v;
  std::memcpy(&v, &f, 4);
  put_u32(b, v);
}

void test_bunky_known_answers() {
  const BunkyTables t = test_tables();
  struct Case {
    const char* key;
    std::size_t key_len;
    unsigned rounds;
    std::size_t size;
    const char* expected;
  } cases[] = {
      {"OpenLnk!", 7, 4, 40, "1c6f2d9cf1ab7c5a4fd244562a76aa58466aa1fdab90f4ef4a49429b7e579833ab88ff458adeb82e"},
      {"OpenLnk!", 8, 32, 13, "1c52a1e1931db3d85453ff45c9"},
      {"abc", 3, 8, 8, "f93bd2541156ccc9"},
      {"abc", 3, 8, 5, "8ee248073f"},
      {"Z", 1, 4, 1, "02"},
  };
  for (const auto& c : cases) {
    BunkyCipher cipher(t, reinterpret_cast<const std::uint8_t*>(c.key), c.key_len, c.rounds);
    Bytes b = counting(c.size);
    cipher.encrypt(b.data(), b.size());
    CHECK(hex(b) == c.expected);
    cipher.decrypt(b.data(), b.size());
    CHECK(b == counting(c.size));
  }
}

void test_bunky_round_trips_every_length() {
  const BunkyTables t = test_tables();
  const std::uint8_t key[] = {1, 2, 3, 4, 5, 6, 7};
  BunkyCipher cipher(t, key, sizeof key, 4);
  for (std::size_t n = 1; n < 40; ++n) {
    Bytes b = counting(n);
    cipher.encrypt(b.data(), b.size());
    CHECK(b != counting(n));
    cipher.decrypt(b.data(), b.size());
    CHECK(b == counting(n));
  }
}

// Builds a locked archive the way the game lays one out, with a stored
// `copyright` entry that holds the course key and a locked entry using it.
struct Fixture {
  GameKeys keys;
  Bytes exe;
  Bytes archive;
};

Fixture make_fixture(bool plain_header = false) {
  Fixture f;
  f.keys.tables = test_tables();
  const std::uint8_t archive_key[8] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x00};
  std::memcpy(f.keys.archive_key.data(), archive_key, 8);

  // A fake executable: junk, the tables, and the key as two pushes.
  f.exe.assign(100, 0x90);
  for (auto w : f.keys.tables.p) put_u32(f.exe, w);
  for (auto w : f.keys.tables.s) put_u32(f.exe, w);
  f.exe.push_back(0x68);
  f.exe.insert(f.exe.end(), archive_key + 4, archive_key + 8);
  f.exe.push_back(0x68);
  f.exe.insert(f.exe.end(), archive_key, archive_key + 4);
  f.exe.push_back(0xc3);

  const std::uint8_t course_key[8] = {9, 8, 7, 6, 5, 4, 3, 2};
  Bytes copyright(0x34, 0);
  std::memcpy(&copyright[0x2c], course_key, 8);
  const std::string secret = "terrain data";

  BunkyCipher entry_cipher(f.keys.tables, archive_key, 7, 4);
  Bytes locked_copyright = copyright;
  entry_cipher.encrypt(locked_copyright.data(), locked_copyright.size());
  Bytes locked_secret(secret.begin(), secret.end());
  BunkyCipher(f.keys.tables, course_key, 7, 4).encrypt(locked_secret.data(), locked_secret.size());

  struct E {
    const char* name;
    Bytes data;
    std::uint32_t size;
    bool locked;
  } entries[] = {
      {"newformat", Bytes{'V', '.', '2', '.', '0', 0}, 6, false},
      {"copyright", locked_copyright, 0x34, true},
      {"vertex", locked_secret, std::uint32_t(secret.size()), true},
  };

  Bytes body(16, 0), dir;
  for (const auto& e : entries) {
    put_u32(dir, 0);
    char name[32] = {};
    std::memcpy(name, e.name, std::strlen(e.name));
    dir.insert(dir.end(), name, name + 32);
    put_u32(dir, std::uint32_t(body.size()));
    put_u32(dir, std::uint32_t(e.data.size()));
    put_u32(dir, e.size);
    put_u32(dir, 0);  // stored
    put_u32(dir, 0);  // no checksum
    put_u32(dir, e.locked ? 1 : 0);
    put_u32(dir, 0);
    body.insert(body.end(), e.data.begin(), e.data.end());
  }
  const std::uint32_t dir_offset = std::uint32_t(body.size());
  BunkyCipher dir_cipher(f.keys.tables, archive_key, 8, 32);
  dir_cipher.encrypt(dir.data(), dir.size());
  body.insert(body.end(), dir.begin(), dir.end());

  Bytes head;
  head.insert(head.end(), {'A', 'R', 'C', '0'});
  put_u32(head, std::uint32_t(body.size()));
  put_u32(head, 3);
  put_u32(head, dir_offset);
  if (!plain_header) dir_cipher.encrypt(head.data(), head.size());
  std::copy(head.begin(), head.end(), body.begin());
  f.archive = body;
  return f;
}

void test_finds_keys_in_executable() {
  Fixture f = make_fixture();
  auto keys = find_game_keys(f.exe, f.archive.data());
  CHECK(keys.has_value());
  if (keys) {
    CHECK(keys->archive_key == f.keys.archive_key);
    CHECK(keys->tables.s == f.keys.tables.s);
  }
  Bytes not_exe(5000, 0);
  CHECK(!find_game_keys(not_exe, f.archive.data()));
}

void test_reads_locked_archive() {
  Fixture f = make_fixture();
  CrzArchive a(f.archive, &f.keys);
  CHECK(a.entries().size() == 3);
  CHECK(a.entries()[2].locked);
  auto v = a.read("VERTEX");
  CHECK(std::string(v.begin(), v.end()) == "terrain data");
  auto n = a.read("newformat");
  CHECK(std::string(reinterpret_cast<const char*>(n.data())) == "V.2.0");

  bool threw = false;
  try {
    CrzArchive no_keys(f.archive, nullptr);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_reads_plain_header_with_locked_directory() {
  Fixture f = make_fixture(true);
  auto keys = find_game_keys(f.exe, f.archive);
  CHECK(keys.has_value() && keys->archive_key == f.keys.archive_key);
  CrzArchive a(f.archive, &f.keys);
  CHECK(a.entries().size() == 3);
  auto v = a.read("vertex");
  CHECK(std::string(v.begin(), v.end()) == "terrain data");

  bool threw = false;
  try {
    CrzArchive no_keys(f.archive, nullptr);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_terrain_wide_indices() {
  const std::uint32_t nv = 70000;
  Bytes b;
  put_u32(b, 6);
  put_u32(b, nv);
  for (std::uint32_t i = 0; i < nv; ++i) {
    for (int c = 0; c < 5; ++c) put_f32(b, float(i));
    put_u16(b, 0);
    put_u16(b, 0);
  }
  put_u32(b, 1);
  for (int k = 0; k < 3; ++k) put_u32(b, (1u << 30) | 0xfffff);
  put_u16(b, 3);  // material
  put_u32(b, 0);  // mapping
  put_u16(b, 0);
  put_u32(b, 0);
  put_u32(b, 66000);
  put_u32(b, nv - 1);
  Terrain t = parse_terrain(b);
  CHECK(t.triangles.size() == 1);
  CHECK(t.triangles[0].material == 3);
  CHECK(t.triangles[0].v[1] == 66000);
  CHECK(t.triangles[0].v[2] == nv - 1);
}

void test_ground_classes() {
  Bytes b;
  put_u32(b, 4);
  put_u32(b, 2);
  b.resize(8 + 2 * 243, 0xcd);
  b[8 + 0x54] = 3;
  b[8 + 243 + 0x54] = 1;
  auto classes = parse_ground_classes(b);
  CHECK(classes.size() == 2 && classes[0] == 3 && classes[1] == 1);
  b.pop_back();
  bool threw = false;
  try {
    parse_ground_classes(b);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

// A version 4 TerrainTypes entry with one rough record that plays as deep
// grass, flagged as a hazard.
void test_crz_terrain_types() {
  Bytes b;
  put_u32(b, 4);
  put_u32(b, 1);
  b.resize(8 + 243, 0xcd);
  Bytes rec;
  put_u32(rec, 7);
  for (int i = 0; i < 20; ++i) put_f32(rec, 0.25f * i);
  put_u32(rec, 3);           // rough
  put_u32(rec, 14);          // category
  put_u32(rec, 0xcdcdcd41);  // hazard; the upper bytes are never read
  std::copy(rec.begin(), rec.end(), b.begin() + 8);
  const char16_t name[] = u"Mud";
  for (int i = 0; i < 4; ++i) {
    b[8 + 0x67 + 2 * i] = std::uint8_t(name[i] & 0xff);
    b[8 + 0x67 + 2 * i + 1] = std::uint8_t(name[i] >> 8);
  }
  auto types = parse_crz_terrain_types(b);
  CHECK(types.size() == 1);
  const CrzTerrainType& t = types[0];
  CHECK(t.index == 7 && t.ground_class == 3 && t.category == 14);
  CHECK(t.hazard() && !t.free_drop());
  CHECK(t.value(0x14) == 0.25f * 4);
  CHECK(t.value(0x38) == 0.25f * 13);
  CHECK(t.name == "Mud");
  b.pop_back();
  bool threw = false;
  try {
    parse_crz_terrain_types(b);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void put_node(Bytes& b, double x, double y) {
  for (int k = 0; k < 3; ++k) {
    put_f32(b, float(x));
    put_f32(b, float(y));
    put_f32(b, 100.0f);
  }
}

// HoleIDShapes with hole 2's outline (a 100 ft square, straight sides) and
// OBIDShapes with an area out of bounds for holes 2 and 3.
Bytes id_shapes(bool ob) {
  Bytes b;
  put_u32(b, 1);
  put_u32(b, 1);
  for (int i = 0; i < 3; ++i) put_f32(b, 0);
  put_u32(b, 42);
  put_u32(b, 4);
  b.push_back(1);
  double lo = ob ? 40 : 0, hi = ob ? 60 : 100;
  for (double v : {lo, lo, 0.0, hi, hi, 0.0}) put_f32(b, float(v));
  put_u32(b, ob ? 0x6u : (2u << 27) | 0x100000u);
  put_node(b, lo, lo);
  put_node(b, hi, lo);
  put_node(b, hi, hi);
  put_node(b, lo, hi);
  return b;
}

void test_hole_bounds() {
  auto holes = parse_id_shapes(id_shapes(false));
  auto ob = parse_id_shapes(id_shapes(true));
  CHECK(holes.size() == 1 && holes[0].id == 42 && holes[0].closed && holes[0].hole() == 2);
  CHECK(ob[0].for_hole(2) && ob[0].for_hole(3) && !ob[0].for_hole(1));
  Outline o = shape_outline(holes[0]);
  // Starts at the last node; each of the four segments is cut in eight.
  CHECK(o.size() == 4 * 8 + 1);
  CHECK(o.front()[0] == 0 && o.front()[1] == 100);
  CHECK(o[4][0] == 0 && o[4][1] == 50);
  CHECK(outline_contains(o, 10, 10) && !outline_contains(o, -1, 10) && !outline_contains(o, 50, 101));
  HoleBounds hb(holes, ob);
  CHECK(hb.in_bounds(2, 10, 10));
  CHECK(!hb.in_bounds(2, 150, 10));
  CHECK(!hb.in_bounds(2, 50, 50));  // in the out-of-bounds area
  CHECK(hb.in_bounds(1, 150, 10));  // hole 1 has no outline and no area
  CHECK(!hb.in_bounds(3, 50, 50));
  Bytes bad = id_shapes(false);
  bad[0] = 2;
  bool threw = false;
  try {
    parse_id_shapes(bad);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_course_text() {
  const std::u16string text = u"\xfeff" u"CourseName = Test Links\r\nHoleName1 = Caf\u00e9\r\n";
  Bytes b;
  for (char16_t c : text) put_u16(b, std::uint16_t(c));
  auto kv = parse_course_text(b);
  CHECK(kv.size() == 2);
  CHECK(kv[0].first == "CourseName" && kv[0].second == "Test Links");
  CHECK(kv[1].second == "Caf\xc3\xa9");
}

void test_terrain() {
  Bytes b;
  put_u32(b, 6);
  put_u32(b, 3);
  const float pts[3][3] = {{0, 0, 10}, {30, 0, 11}, {0, 30, 12}};
  for (auto& p : pts) {
    for (float c : p) put_f32(b, c);
    put_f32(b, 0);
    put_f32(b, 0);
    put_u16(b, 0);
    put_u16(b, 0);
  }
  put_u32(b, 1);
  put_u32(b, (1u << 30) | 0xfffff);
  put_u32(b, (1u << 30) | 0xfffff);
  put_u32(b, (1u << 30) | 0xfffff);
  put_u16(b, 4);  // material
  put_u32(b, 6);  // mapping
  put_u16(b, 0);
  put_u16(b, 0);
  put_u16(b, 1);
  put_u16(b, 2);
  Terrain t = parse_terrain(b);
  CHECK(t.vertices.size() == 3);
  CHECK(t.vertices[2].position.z == 12);
  CHECK(t.triangles.size() == 1);
  CHECK(t.triangles[0].material == 4);
  CHECK(t.triangles[0].v[2] == 2);
  CHECK(t.triangles[0].neighbour[0] == kNoNeighbour);

  b[b.size() - 2] = 9;  // vertex index out of range
  bool threw = false;
  try {
    parse_terrain(b);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_holes() {
  Bytes b;
  put_u32(b, 0xffffffff);
  put_u32(b, 15);
  b.resize(b.size() + 10, 0);
  put_u32(b, 1);
  for (std::uint32_t v : {4u, 11u, 4u, 8u}) put_u32(b, v);
  for (int i = 0; i < 5; ++i) {
    for (float c : {static_cast<float>(i), 2.0f, 3.0f, 0.5f}) put_f32(b, c);
    put_u32(b, static_cast<std::uint32_t>(400 - 20 * i));
    put_u32(b, i < 4 ? 1u << i : 0);  // fifth tee unused
  }
  for (int i = 0; i < 18; ++i) {
    for (float c : {i < 6 ? 100.0f : 0.0f, 0.0f, 0.0f}) put_f32(b, c);
    put_u32(b, 0);
  }
  put_u32(b, 18);
  put_u32(b, 5);
  for (int i = 0; i < 5; ++i) {
    for (float c : {i < 2 ? 5.0f : 0.0f, 0.0f, 0.0f}) put_f32(b, c);
  }
  for (float c : {100.0f, 0.0f, 3.0f}) put_f32(b, c);
  b.resize(b.size() + 6, 0);

  auto holes = parse_holes(b);
  CHECK(holes.size() == 1);
  CHECK(holes[0].par == 4 && holes[0].handicap == 11);
  CHECK(holes[0].tees.size() == 4);
  CHECK(holes[0].tees[1].yards == 380);
  CHECK(holes[0].pins.size() == 6);
  CHECK(holes[0].aim_path.size() == 2);
  CHECK(holes[0].green.x == 100);

  // No trailer: the scenery can't be read.
  bool threw = false;
  try {
    parse_course_scenery(b);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
  // The trailer as on the disc courses: five 12-byte records, four zero
  // settings, the sky, eight bytes, four values, a u32, the horizon, a u32
  // and 16 bytes.
  put_u32(b, 5);
  b.resize(b.size() + 60 + 16, 0);
  put_u32(b, 7);
  b.resize(b.size() + 8, 0);
  for (float v : {0.785f, 0.15f, 30.0f, 0.15f}) put_f32(b, v);
  put_u32(b, 0);
  put_u32(b, 0x80000000u);
  put_u32(b, 0);
  b.resize(b.size() + 16, 0);
  auto s = parse_course_scenery(b);
  CHECK(s.sky == 7 && s.panorama == 0);
  CHECK(s.values[0] == 0.785f && s.values[2] == 30.0f);
  b[b.size() - 24] = 3;  // PanNN
  b[b.size() - 21] = 0;
  CHECK(parse_course_scenery(b).panorama == 3);
}

void set_u32(Bytes& b, std::size_t off, std::uint32_t v) {
  for (int i = 0; i < 4; ++i) b[off + i] = std::uint8_t(v >> (8 * i));
}

// A MasterObj with two types laid out the way the game saves them: tile
// records with the sprite name, a sprite descriptor pointing back at them,
// a level list, the type record, and the table of type records.
void test_billboard_types() {
  Bytes b(0x80, 0);
  std::vector<std::uint32_t> recs;
  const char* names[] = {"Bushes156A.btc", "Tall Trees212A.btc"};
  for (int k = 0; k < 2; ++k) {
    std::size_t tiles = b.size();
    b.resize(b.size() + 64, 0);
    std::memcpy(b.data() + tiles, names[k], std::strlen(names[k]));
    std::size_t desc = b.size();
    put_u32(b, 200 + k);  // width
    put_u32(b, 150);      // height
    put_u32(b, 1);        // tiles
    put_u32(b, std::uint32_t(tiles));
    put_u32(b, std::uint32_t(tiles + 64));
    std::size_t lods = b.size();
    put_u32(b, 1);
    put_u32(b, 4);
    put_u32(b, std::uint32_t(desc));
    put_u32(b, 0);
    put_u32(b, 0);
    std::size_t rec = b.size();
    recs.push_back(std::uint32_t(rec));
    b.resize(b.size() + 0x40, 0);
    set_u32(b, rec, 200 + k);
    set_u32(b, rec + 4, 150);
    set_u32(b, rec + 8, 1);
    set_u32(b, rec + 12, std::uint32_t(lods));
    float aspect = (200 + k) / 150.0f;
    std::uint32_t bits;
    std::memcpy(&bits, &aspect, 4);
    set_u32(b, rec + 0x18, bits);
    set_u32(b, rec + 0x34, 0x8401e192u + k);
    if (k == 1) {
      // A tree's collision record.
      std::size_t phys = b.size();
      put_u32(b, 0);
      for (float v : {0.7f, 0.92f, 0.626f, 0.0f, 0.831f, 0.332f}) put_f32(b, v);
      set_u32(b, rec + 0x14, std::uint32_t(phys));
    }
  }
  std::size_t table = b.size();
  for (auto r : recs) put_u32(b, r);
  set_u32(b, 0, std::uint32_t(b.size()));
  set_u32(b, 4, 0x80);
  set_u32(b, 8, 2);
  set_u32(b, 12, std::uint32_t(table));

  auto types = parse_billboard_types(b);
  CHECK(types.size() == 2);
  CHECK(types[0].name == "Bushes156");
  CHECK(types[1].name == "Tall Trees212");
  CHECK(types[1].sprite == "Tall Trees212A.btc");
  CHECK(types[1].width == 201 && types[1].height == 150);
  CHECK(std::fabs(types[0].aspect - 200 / 150.0f) < 1e-6f);
  CHECK(types[1].id == 0x8401e193u);
  CHECK(types[0].collision == 1 && types[0].shape[0] == 1.0f);
  CHECK(types[1].collision == 0);
  CHECK(types[1].shape[1] == 0.92f && types[1].shape[5] == 0.332f);
}

void test_billboard_placements() {
  Bytes b = {'2', 'J', 'B', 'O'};
  put_u32(b, 2);
  put_u32(b, 3);
  b.resize(0x40, 0);
  // Cell at (896, -3328), base height 270 ft.
  put_u16(b, 0xffff);
  for (float c : {896.0f, -3328.0f, 270.0f}) put_f32(b, c);
  // Both optional fields.
  put_u16(b, 25);
  put_u32(b, 0x6000116cu);
  b.push_back(2);
  put_u16(b, 6);
  for (std::uint16_t v : {std::uint16_t(343), std::uint16_t(616), std::uint16_t(0xffcc), std::uint16_t(768)}) put_u16(b, v);
  // Only the word.
  put_u16(b, 32);
  put_u32(b, 0x40001172u);
  put_u16(b, 6);
  for (std::uint16_t v : {std::uint16_t(1023), std::uint16_t(0), std::uint16_t(2), std::uint16_t(48)}) put_u16(b, v);
  // Next cell, no optional fields.
  put_u16(b, 0xffff);
  for (float c : {960.0f, -3328.0f, 271.0f}) put_f32(b, c);
  put_u16(b, 64);
  put_u32(b, 0x00002682u);
  for (std::uint16_t v : {std::uint16_t(16), std::uint16_t(32), std::uint16_t(0), std::uint16_t(32)}) put_u16(b, v);

  auto p = parse_billboard_placements(b);
  CHECK(p.size() == 3);
  CHECK(p[0].type == 25 && p[0].instance == 0x116c);
  CHECK(p[0].extra_byte == 2 && p[0].extra_word == 6);
  CHECK(std::fabs(p[0].position.x - (896 + 343 / 16.0f)) < 1e-3f);
  CHECK(std::fabs(p[0].position.y - (-3328 + 616 / 16.0f)) < 1e-3f);
  CHECK(std::fabs(p[0].position.z - (270 - 52 / 16.0f)) < 1e-3f);
  CHECK(p[0].height == 48);
  CHECK(p[1].extra_byte == -1 && p[1].extra_word == 6 && p[1].height == 3);
  CHECK(p[2].type == 64 && p[2].extra_byte == -1 && p[2].extra_word == -1);
  CHECK(p[2].position.x == 961 && p[2].position.y == -3326 && p[2].position.z == 271);

  Bytes truncated(b.begin(), b.end() - 3);
  bool threw = false;
  try {
    parse_billboard_placements(truncated);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

// A one-triangle mesh in the .XYZ layout.
Bytes tiny_xyz() {
  Bytes d(0xa4, 0);
  for (float f : {0.0f, 0.0f, 0.0f, 10.0f, 0.0f, 0.0f, 0.0f, 0.0f, 5.0f}) put_f32(d, f);
  std::size_t uv_at = d.size();
  for (float f : {0.0f, 1.0f, 1.0f, 1.0f, 0.0f, 0.0f}) put_f32(d, f);
  std::size_t face_at = d.size();
  for (std::uint16_t v : {std::uint16_t(3), std::uint16_t(0), std::uint16_t(0), std::uint16_t(0)}) put_u16(d, v);
  put_u32(d, 0);
  std::size_t idx_at = d.size();
  for (std::uint16_t i = 0; i < 3; ++i) put_u16(d, i);
  std::size_t mat_at = d.size();
  d.resize(d.size() + 16, 0xcd);
  set_u32(d, 0, std::uint32_t(d.size()));
  const std::uint32_t tables[5][2] = {{3, 0xa4},
                                      {3, std::uint32_t(uv_at)},
                                      {1, std::uint32_t(face_at)},
                                      {3, std::uint32_t(idx_at)},
                                      {1, std::uint32_t(mat_at)}};
  for (int i = 0; i < 5; ++i) {
    set_u32(d, 0x18 + 8 * i, tables[i][0]);
    set_u32(d, 0x1c + 8 * i, tables[i][1]);
  }
  set_u32(d, 0x40, 1);
  return d;
}

void test_course_models() {
  Bytes b(0x70, 0);
  for (std::uint32_t k = 0; k < 2; ++k) {
    Bytes m = tiny_xyz();
    b.insert(b.end(), m.begin(), m.end());
    put_u32(b, k);
    put_u32(b, 0x8401e363u + k);
    put_u32(b, 2 + 4 * k);
  }
  set_u32(b, 0, std::uint32_t(b.size()));
  set_u32(b, 4, 0x70);
  set_u32(b, 8, 2);
  auto models = parse_course_models(b);
  CHECK(models.size() == 2);
  CHECK(models[1].id == 0x8401e364u && models[1].kind == 6);
  CHECK(models[0].model.positions.size() == 3 && models[0].model.faces.size() == 1);
  set_u32(b, 8, 3);
  bool threw = false;
  try {
    parse_course_models(b);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_model_placements() {
  Bytes b;
  put_u32(b, 7);
  put_u32(b, 1);
  for (float f : {100.0f, 200.0f, 50.0f,  // position
                  0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,  // box
                  0.5f, -10.0f, 0.0f, 0.0f, 1.0f,  // z offset, flag
                  0.5f, 0.5f, 0.25f,  // scale
                  1.5707963f, 0.0f, 0.0f}) {
    put_f32(b, f);
  }
  CHECK(b.size() == 88);
  auto p = parse_model_placements(b);
  CHECK(p.size() == 1);
  CHECK(p[0].instance == 7 && p[0].model == 1 && p[0].drawn());
  CHECK(p[0].z_offset == -10 && p[0].scale[2] == 0.25f);
  // (10, 0, 10): scaled to (5, 0, 0), turned a quarter about z to (0, 5, 0).
  auto q = place_point(p[0], {10, 0, 10});
  CHECK(std::fabs(q.x - 100) < 1e-3f && std::fabs(q.y - 205) < 1e-3f && std::fabs(q.z - 50) < 1e-3f);
  b.push_back(0);
  bool threw = false;
  try {
    parse_model_placements(b);
  } catch (const std::exception&) {
    threw = true;
  }
  CHECK(threw);
}

void test_object_textures_and_maq() {
  // t3l with one model of two textures, two levels each.
  Bytes t;
  put_u32(t, 0);
  put_u32(t, 1);
  put_u32(t, 12);
  std::size_t rec = t.size();
  t.resize(t.size() + 20, 0);
  std::size_t lists = t.size();
  for (std::uint32_t tex = 0; tex < 2; ++tex) {
    put_u32(t, 2);
    put_u32(t, 0);
    put_u32(t, 2 * tex);
    put_u32(t, 2 * tex + 1);
  }
  std::size_t levels = t.size();
  t.resize(t.size() + 4 * 64, 0);
  std::memcpy(t.data() + levels, "Course 3D001.maq", 16);
  std::memcpy(t.data() + levels + 128, "junk", 4);  // later records hold leftovers
  set_u32(t, 0, std::uint32_t(t.size()));
  set_u32(t, rec, 8);
  set_u32(t, rec + 4, 2);
  set_u32(t, rec + 8, std::uint32_t(levels));
  set_u32(t, rec + 12, std::uint32_t(lists));
  auto refs = parse_object_textures(t);
  CHECK(refs.size() == 1);
  CHECK(refs[0].maq.size() == 2 && refs[0].maq[1] == "Course 3D001.maq");
  CHECK(refs[0].level[0] == 0 && refs[0].level[1] == 2);

  // maq with one 2 x 1 level.
  Bytes m;
  put_u32(m, 0);
  put_u32(m, 1);
  put_u32(m, 1);
  put_u32(m, 16);
  for (std::uint32_t v : {2u, 1u, 8u, 2u, 1u, 0u, 0u, 52u, 52u + 1024u}) put_u32(m, v);
  Bytes palette(1024, 0);
  palette[4 * 1] = 10;      // blue
  palette[4 * 1 + 1] = 20;  // green
  palette[4 * 1 + 2] = 30;  // red
  palette[4 * 1 + 3] = 255;
  m.insert(m.end(), palette.begin(), palette.end());
  m.push_back(1);
  m.push_back(0);
  set_u32(m, 0, std::uint32_t(m.size()));
  auto img = decode_maq(m, 0);
  CHECK(img.width == 2 && img.height == 1);
  CHECK(img.pixels[0] == 30 && img.pixels[1] == 20 && img.pixels[2] == 10 && img.pixels[3] == 255);
  CHECK(img.pixels[7] == 0);
}

void test_crowd_placements() {
  Bytes b;
  put_u32(b, 2);
  put_u32(b, 2);
  b.resize(0x40, 0);
  b.push_back(0xff);
  for (float c : {704.0f, -2752.0f, 274.0f}) put_f32(b, c);
  b.push_back(0);
  put_u32(b, 184);
  for (std::uint16_t v : {std::uint16_t(961), std::uint16_t(204), std::uint16_t(16)}) put_u16(b, v);
  b.push_back(2);
  put_u32(b, 0x400017feu);
  put_u16(b, 199);
  for (std::uint16_t v : {std::uint16_t(0), std::uint16_t(32), std::uint16_t(0xfff0)}) put_u16(b, v);
  auto p = parse_crowd_placements(b);
  CHECK(p.size() == 2);
  CHECK(p[0].kind == 0 && p[0].instance == 184 && p[0].extra_word == -1);
  CHECK(std::fabs(p[0].position.x - (704 + 961 / 16.0f)) < 1e-3f && p[0].position.z == 275);
  CHECK(p[1].kind == 2 && p[1].instance == 0x17fe && p[1].extra_word == 199 && p[1].extra_byte == -1);
  CHECK(p[1].position.y == -2750 && p[1].position.z == 273);
}

}  // namespace

void put_name(Bytes& b, const std::string& name) {
  put_u32(b, std::uint32_t(name.size()));
  b.insert(b.end(), name.begin(), name.end());
}

// A `Mappings` entry with one record of each kind. The GDScript port
// (game/tests/course_tests.gd) builds the same bytes.
Bytes test_mappings_entry() {
  Bytes b;
  put_u32(b, 5);
  put_u32(b, 4);
  while (b.size() < 48) b.push_back(0);
  // 0: planar, 12 feet per repeat, rotated 90 degrees, origin (100, 200, 0).
  put_u32(b, 0);
  put_u32(b, 0x8000);
  put_name(b, "Planar");
  put_f32(b, 1);
  put_f32(b, 1);
  for (float f : {0.f, 12.f, 0.f, 0.f, -12.f, 0.f, 0.f, 0.f, 0.f, 0.f, 12.f, 0.f, 100.f, 200.f, 0.f, 1.f}) put_f32(b, f);
  // 1: cylindrical round the z axis, 4 repeats round, 10 feet tall.
  put_u32(b, 1);
  put_u32(b, 0x8001);
  put_name(b, "Pool");
  put_f32(b, 4);
  put_f32(b, 1);
  for (float f : {20.f, 0.f, 0.f, 0.f, 0.f, 20.f, 0.f, 0.f, 0.f, 0.f, 10.f, 0.f, 0.f, 0.f, 0.f, 1.f}) put_f32(b, f);
  // 2: a strip over triangle 7 (vertices 3, 4, 5).
  put_u32(b, 3);
  put_u32(b, 0x8002);
  put_name(b, "Edge path");
  put_f32(b, 1);
  put_f32(b, 12);
  put_u32(b, 1);
  for (std::uint32_t v : {999u, 7u, 2u, 0u, 1u}) put_u32(b, v);
  put_u32(b, 3);
  for (std::uint32_t c = 0; c < 3; ++c) {
    put_u32(b, 999);
    put_u32(b, 3 + c);
    put_f32(b, c == 1 ? 1.f : 0.f);
    put_f32(b, 0.5f * float(c));
  }
  // 3: blend, the strip for the mask, the planar for both layers.
  put_u32(b, 4);
  put_u32(b, 0x8003);
  put_name(b, "Edge multi");
  for (std::uint32_t v : {2u, 0u, 0u, 0u, 0u}) put_u32(b, v);
  return b;
}

void test_mappings() {
  auto m = parse_mappings(test_mappings_entry());
  CHECK(m.size() == 4);
  if (m.size() != 4) return;
  CHECK(m[0].kind == MappingKind::kPlanar && m[0].name == "Planar");
  // origin + 1 * row0 + 2 * row1 = (100 - 24, 200 + 12, 0).
  auto uv = mapping_uv(m[0], {76, 212, 5});
  CHECK(std::fabs(uv[0] - 1) < 1e-5f && std::fabs(uv[1] - 2) < 1e-5f);
  CHECK(m[1].kind == MappingKind::kCylindrical);
  auto cyl = mapping_uv(m[1], {0, 20, 5});  // a quarter round, half way up
  CHECK(std::fabs(cyl[0] - 1) < 1e-5f && std::fabs(cyl[1] - 0.5f) < 1e-5f);
  CHECK(m[2].kind == MappingKind::kStrip && m[2].scale_v == 12);
  CHECK(m[2].triangles.size() == 1 && m[2].triangles[0].triangle == 7);
  CHECK(m[2].triangles[0].corner == (std::array<std::uint32_t, 3>{2, 0, 1}));
  CHECK(m[2].corners.size() == 3 && m[2].corners[1].vertex == 4 && m[2].corners[1].u == 1 &&
        m[2].corners[2].v == 1);
  CHECK(m[3].kind == MappingKind::kBlend && m[3].layers == (std::array<std::uint32_t, 3>{2, 0, 0}));
  Bytes bad = test_mappings_entry();
  bad.push_back(0);
  bool threw = false;
  try {
    parse_mappings(bad);
  } catch (const ReadError&) {
    threw = true;
  }
  CHECK(threw);
  TerrainTriangle t;
  t.mapping = 0x616d0006;
  CHECK(mapping_index(t) == 6);
}

void test_material_layers() {
  TerrainMaterial plain;
  plain.textures = {4, 5, 6};
  plain.kind = 0x3;  // two detail variants of the only layer
  auto p = material_layers(plain);
  CHECK(!p.blended && p.mask == -1 && p.layers == (std::vector<std::int32_t>{4}));
  CHECK(p.details.size() == 1 && p.details[0][0] == 5 && p.details[0][1] == 6);
  plain.textures = {4, 6};
  plain.kind = 0x2;  // only the far variant
  p = material_layers(plain);
  CHECK(p.details.size() == 1 && p.details[0][0] == -1 && p.details[0][1] == 6);
  TerrainMaterial blend;
  blend.mode = 3;
  blend.layer_count = 3;
  // Mask with one detail, layer A with two, layer B with none.
  blend.textures = {10, 11, 20, 21, 22, 30};
  blend.kind = 0x1 | 0xc;
  auto b = material_layers(blend);
  CHECK(b.blended && b.mask == 10 && b.layers == (std::vector<std::int32_t>{20, 30}));
  CHECK(b.details.size() == 2 && b.details[0][0] == 21 && b.details[0][1] == 22 && b.details[1][0] == -1);
}

// A shadow file: 2 light maps of 2 x 2, some undecoded words, then three
// shapes (none, 32 x 32, none) and a tail.
Bytes shadow_file_bytes() {
  Bytes b(0x12e, 0);
  std::memcpy(b.data(), "VER5JDHSHADOW", 14);
  std::memcpy(b.data() + 14, "test.CRZ", 8);
  set_u32(b, 0x10e, 12345);
  set_u32(b, 0x11a, 1028330567);  // stamp
  set_u32(b, 0x11e, 2);  // models
  set_u32(b, 0x122, 3);  // billboard types
  set_u32(b, 0x126, 1);  // model placements
  set_u32(b, 0x12a, 2);  // billboards
  put_u32(b, 2);  // model 0: a 2 x 2 footprint
  put_u32(b, 2);
  for (int i = 0; i < 4; ++i) b.push_back(i == 3 ? 0 : 0xfe);
  put_u32(b, 0);  // model 1: none
  put_u32(b, 0);
  put_u32(b, 2);  // placement 0 touches two cells
  put_u32(b, 8);
  put_u32(b, 16);
  put_f32(b, 1.0f);  // billboard light
  put_f32(b, 0.25f);
  put_u32(b, 0);  // type 0: no shadow
  put_u32(b, 0);
  put_u32(b, 32);  // type 1
  put_u32(b, 32);
  for (int i = 0; i < 32 * 32; ++i) b.push_back(std::uint8_t(i));
  put_u32(b, 0);  // type 2: no shadow
  put_u32(b, 0);
  put_u32(b, 1);  // billboard 0 touches one cell, billboard 1 none
  put_u32(b, 0);
  put_u32(b, 24);
  return b;
}

void test_shadow_file() {
  auto f = parse_shadow_file(shadow_file_bytes());
  CHECK(f.course == "test.CRZ" && f.course_size == 12345 && f.stamp == 1028330567);
  CHECK(f.model_count == 2 && f.billboard_type_count == 3 && f.billboard_count == 2);
  CHECK(f.object_shapes.size() == 2);
  if (f.object_shapes.size() == 2) {
    CHECK(f.object_shapes[0].width == 2 && f.object_shapes[0].pixels[0] == 0xfe && f.object_shapes[0].pixels[3] == 0);
    CHECK(f.object_shapes[1].width == 0 && f.object_shapes[1].pixels.empty());
  }
  CHECK((f.placement_cells.start == std::vector<std::uint32_t>{0, 2}));
  CHECK((f.placement_cells.cells == std::vector<std::uint32_t>{1, 2}));
  CHECK((f.billboard_light == std::vector<float>{1.0f, 0.25f}));
  CHECK(f.shapes.size() == 3);
  if (f.shapes.size() == 3) {
    CHECK(f.shapes[0].width == 0 && f.shapes[0].pixels.empty());
    CHECK(f.shapes[1].width == 32 && f.shapes[1].height == 32 && f.shapes[1].pixels.size() == 1024);
    CHECK(f.shapes[1].pixels[33] == 33);
    CHECK(f.shapes[2].width == 0);
  }
  CHECK((f.billboard_cells.start == std::vector<std::uint32_t>{0, 1, 1}));
  CHECK((f.billboard_cells.cells == std::vector<std::uint32_t>{3}));
  for (int which = 0; which < 3; ++which) {
    Bytes bad = shadow_file_bytes();
    if (which == 0) bad[0] = 'X';
    if (which == 1) bad.pop_back();  // short
    if (which == 2) bad.push_back(0);  // trailing byte
    bool threw = false;
    try {
      parse_shadow_file(bad);
    } catch (const ReadError&) {
      threw = true;
    }
    CHECK(threw);
  }
}

int main() {
  std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"bunky_known_answers", test_bunky_known_answers},
      {"bunky_round_trips_every_length", test_bunky_round_trips_every_length},
      {"finds_keys_in_executable", test_finds_keys_in_executable},
      {"reads_locked_archive", test_reads_locked_archive},
      {"plain_header_with_locked_directory", test_reads_plain_header_with_locked_directory},
      {"ground_classes", test_ground_classes},
      {"crz_terrain_types", test_crz_terrain_types},
      {"hole_bounds", test_hole_bounds},
      {"course_text", test_course_text},
      {"terrain", test_terrain},
      {"terrain_wide_indices", test_terrain_wide_indices},
      {"holes", test_holes},
      {"billboard_types", test_billboard_types},
      {"billboard_placements", test_billboard_placements},
      {"crowd_placements", test_crowd_placements},
      {"course_models", test_course_models},
      {"model_placements", test_model_placements},
      {"object_textures_and_maq", test_object_textures_and_maq},
      {"mappings", test_mappings},
      {"material_layers", test_material_layers},
      {"shadow_file", test_shadow_file},
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
