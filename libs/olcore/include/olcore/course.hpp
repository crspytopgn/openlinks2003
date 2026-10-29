#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/crz.hpp"

namespace olcore {

// Parsers for the entries of a course archive. Coordinates are as stored:
// feet, z up, x and y across the ground. See docs/formats/crz.md.

struct CourseVec3 {
  float x = 0, y = 0, z = 0;
};

struct Tee {
  CourseVec3 position;
  float heading = 0;  // radians
  std::uint32_t yards = 0;
  std::uint32_t mask = 0;  // 1, 2, 4, 8, 16: back to forward tees
};

struct Pin {
  CourseVec3 position;
  std::uint32_t group = 0;  // which day's set of pin positions
};

struct Hole {
  std::uint32_t par = 0;
  std::uint32_t handicap = 0;
  std::uint32_t ladies_par = 0;
  std::uint32_t ladies_handicap = 0;
  std::vector<Tee> tees;
  std::vector<Pin> pins;
  std::vector<CourseVec3> aim_path;  // tee, layup points, then green
  CourseVec3 green;
  std::string name;
};

// `header` entry: the holes.
std::vector<Hole> parse_holes(const std::vector<std::uint8_t>& data);

// `english.txt` entry (UTF-16 "Key = Value" lines), returned as UTF-8 pairs.
std::vector<std::pair<std::string, std::string>> parse_course_text(const std::vector<std::uint8_t>& data);

struct TerrainVertex {
  CourseVec3 position;
  float unknown[2] = {0, 0};
  std::uint16_t unknown_a = 0;
  std::uint16_t flags = 0;
};

struct TerrainTriangle {
  std::array<std::uint32_t, 3> v{};
  // Neighbouring triangle across each edge; kNoNeighbour on the border.
  std::array<std::uint32_t, 3> neighbour{};
  std::uint16_t material = 0;  // index into the `Materials` table
  std::uint32_t mapping = 0;   // texture mapping record (not decoded yet)
  std::uint16_t unknown = 0;
};

constexpr std::uint32_t kNoNeighbour = 0xfffff;

struct Terrain {
  std::vector<TerrainVertex> vertices;
  std::vector<TerrainTriangle> triangles;
};

// `vertex` entry: the terrain mesh.
Terrain parse_terrain(const std::vector<std::uint8_t>& data);

struct TextureDesc {
  std::string name;
  std::uint32_t width = 0, height = 0;
};

// `txtrdesc` entry: the terrain texture list.
std::vector<TextureDesc> parse_texture_list(const std::vector<std::uint8_t>& data);

struct TerrainMaterial {
  std::vector<std::int32_t> textures;  // indices into the texture list
  std::uint32_t kind = 0;              // not decoded yet (0, 1 or 3)
};

// `Materials` entry: which textures each terrain material blends.
std::vector<TerrainMaterial> parse_materials(const std::vector<std::uint8_t>& data);

// The parts of a course the viewer needs, read from an open archive.
struct Course {
  std::string name;
  std::vector<Hole> holes;
  Terrain terrain;
  std::vector<TextureDesc> textures;
  std::vector<TerrainMaterial> materials;
};

Course load_course(const CrzArchive& archive);

}  // namespace olcore
