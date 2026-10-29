// Tests for the course cipher, archive and parsers. The real cipher tables
// come from the game executable, so these use made-up tables; the expected
// ciphertexts were produced by an independent implementation that matches
// the game's own output on the real tables.
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

#include "olcore/bunky.hpp"
#include "olcore/course.hpp"
#include "olcore/crz.hpp"

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
}

}  // namespace

int main() {
  std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"bunky_known_answers", test_bunky_known_answers},
      {"bunky_round_trips_every_length", test_bunky_round_trips_every_length},
      {"finds_keys_in_executable", test_finds_keys_in_executable},
      {"reads_locked_archive", test_reads_locked_archive},
      {"plain_header_with_locked_directory", test_reads_plain_header_with_locked_directory},
      {"course_text", test_course_text},
      {"terrain", test_terrain},
      {"terrain_wide_indices", test_terrain_wide_indices},
      {"holes", test_holes},
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
