// Tests for the converted-course (.CVT) parsers, on made-up entries.
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

#include "olcore/cvt.hpp"

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
void put_utf16(Bytes& b, const std::string& s) {
  for (std::size_t i = 0; i < 32; ++i) put_u16(b, i < s.size() ? std::uint16_t(s[i]) : 0);
}

bool throws(const std::function<void()>& fn) {
  try {
    fn();
  } catch (const std::exception&) {
    return true;
  }
  return false;
}

// A version 5 mesh: a fan of triangles around vertex 0.
Bytes terrain_v5(std::uint32_t vertices, bool wide) {
  Bytes b;
  put_u32(b, 5);
  put_u32(b, vertices);
  for (std::uint32_t i = 0; i < vertices; ++i) {
    for (float c : {float(i), float(i % 7), 100.0f + float(i)}) put_f32(b, c);
    put_u16(b, 0);
    put_u16(b, 0x50);
  }
  const std::uint32_t triangles = vertices - 2;
  put_u32(b, triangles);
  for (std::uint32_t t = 0; t < triangles; ++t) {
    for (int k = 0; k < 3; ++k) put_u32(b, (1u << 30) | 0xfffff);
  }
  for (std::uint32_t t = 0; t < triangles; ++t) {
    put_u16(b, std::uint16_t(t % 3));  // terrain type
    put_u32(b, 0);
    put_u16(b, 0);
    for (std::uint32_t v : {0u, t + 1, t + 2}) {
      if (wide) {
        put_u32(b, v);
      } else {
        put_u16(b, std::uint16_t(v));
      }
    }
  }
  return b;
}

void test_terrain_v5() {
  Terrain t = parse_converted_terrain(terrain_v5(4, false));
  CHECK(t.vertices.size() == 4);
  CHECK(t.vertices[3].position.z == 103);
  CHECK(t.vertices[3].flags == 0x50);
  CHECK(t.triangles.size() == 2);
  CHECK(t.triangles[1].material == 1);
  CHECK(t.triangles[1].v[2] == 3);
  CHECK(t.triangles[0].neighbour[0] == kNoNeighbour);

  Bytes bad = terrain_v5(4, false);
  bad[bad.size() - 2] = 9;  // vertex index out of range
  CHECK(throws([&] { parse_converted_terrain(bad); }));
  bad = terrain_v5(4, false);
  bad[0] = 6;
  CHECK(throws([&] { parse_converted_terrain(bad); }));
}

void test_terrain_v5_wide_indices() {
  // Past 65,535 vertices the triangle indices are 32-bit.
  Terrain t = parse_converted_terrain(terrain_v5(70000, true));
  CHECK(t.triangles.size() == 69998);
  CHECK(t.triangles.back().v[2] == 69999);
}

void test_holes_v14() {
  Bytes b;
  put_u32(b, 14);
  const char name[9] = "Pebble_B";
  b.insert(b.end(), name, name + 9);
  put_u32(b, 1);
  for (std::uint32_t v : {3u, 15u, 3u, 17u}) put_u32(b, v);
  for (int i = 0; i < 5; ++i) {
    for (float c : {float(i), 2.0f, 3.0f, 0.5f}) put_f32(b, c);
    put_u32(b, std::uint32_t(110 - 5 * i));
    put_u32(b, i < 3 ? 1u << i : 0);
  }
  for (int i = 0; i < 18; ++i) {
    for (float c : {i < 6 ? 100.0f : 0.0f, 0.0f, 0.0f}) put_f32(b, c);
    put_u32(b, 0);
  }
  put_u32(b, 6);
  put_u32(b, 2);
  for (int i = 0; i < 5; ++i) {
    for (float c : {i < 2 ? 5.0f : 0.0f, 0.0f, 0.0f}) put_f32(b, c);
  }
  for (float c : {100.0f, 0.0f, 3.0f}) put_f32(b, c);
  b.resize(b.size() + 6 + 136, 0);

  std::string short_name;
  auto holes = parse_converted_holes(b, &short_name);
  CHECK(short_name == "Pebble_B");
  CHECK(holes.size() == 1);
  CHECK(holes[0].par == 3 && holes[0].handicap == 15);
  CHECK(holes[0].tees.size() == 3);
  CHECK(holes[0].tees[2].yards == 100);
  CHECK(holes[0].pins.size() == 6);
  CHECK(holes[0].green.z == 3);

  b[0] = 15;
  CHECK(throws([&] { parse_converted_holes(b); }));
}

void test_terrain_types() {
  Bytes b;
  put_u32(b, 2);
  struct Row {
    const char* name;
    std::int32_t tex[3];
    std::uint8_t rgb[3];
  } rows[] = {{"Fairway", {2, 15, 16}, {0, 0xbf, 0}}, {"Green", {3, -1, -1}, {0x33, 0xff, 0x33}}};
  for (const Row& r : rows) {
    std::size_t start = b.size();
    put_u32(b, 0x00601234);
    for (std::int32_t t : r.tex) put_u32(b, std::uint32_t(t));
    for (int i = 0; i < 14; ++i) put_f32(b, 1.0f);  // physics values
    b.resize(start + 108, 0xcd);
    b.push_back(1);
    b.insert(b.end(), r.rgb, r.rgb + 3);
    CHECK(b.size() - start == 112);
    put_utf16(b, r.name);
    put_utf16(b, "a.tga");
    put_utf16(b, "b.tga");
    put_utf16(b, "c.tga");
    put_utf16(b, r.name);
    CHECK(b.size() - start == 432);
  }
  auto types = parse_terrain_types(b);
  CHECK(types.size() == 2);
  CHECK(types[0].name == "Fairway");
  CHECK(types[0].textures.size() == 3 && types[0].textures[1] == 15);
  CHECK(types[0].map_colour[1] == 0xbf);
  CHECK(types[1].display_name == "Green");
  CHECK(types[1].textures.size() == 1 && types[1].textures[0] == 3);

  b.pop_back();
  CHECK(throws([&] { parse_terrain_types(b); }));
}

void test_titles() {
  CHECK(converted_course_title("PEBBLEBE") == "Pebble Beach Golf Links");
  CHECK(converted_course_title("pebblebe") == "Pebble Beach Golf Links");
  CHECK(converted_course_title("GEAGLES").empty());
}

}  // namespace

int main() {
  std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"terrain_v5", test_terrain_v5},
      {"terrain_v5_wide_indices", test_terrain_v5_wide_indices},
      {"holes_v14", test_holes_v14},
      {"terrain_types", test_terrain_types},
      {"titles", test_titles},
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
