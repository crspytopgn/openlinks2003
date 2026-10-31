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

// The scenery a course asks for, from the end of its `header` entry (after
// the holes). See docs/formats/crz.md#the-header-trailer-sky-and-horizon.
struct CourseScenery {
  // Which cloud sky: skyNN.btc in PANSKY.LIB (1 to 12), or 0 for none set.
  std::uint32_t sky = 0;
  // Which horizon: PanNN.btc in PANSKY.LIB (1 to 13), or 0 for the
  // course's own `Panorama` entry.
  std::uint32_t panorama = 0;
  // Four values the game keeps beside the sky; not decoded. The six disc
  // courses hold an angle in radians (0 to 4.7), 0.1 or 0.15, 25 to 40 and
  // again 0.1 or 0.15.
  float values[4] = {0, 0, 0, 0};
};

// Reads the trailer. Throws ReadError when the entry is too short.
CourseScenery parse_course_scenery(const std::vector<std::uint8_t>& data);

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
  std::uint32_t mapping = 0;   // low 16 bits: index into `Mappings` (see mapping_index())
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
  std::uint32_t mode = 0;              // 0 plain, 3 blended through a mask
  std::uint32_t layer_count = 1;       // 1 plain; 3 blended (mask and two layers)
  std::vector<std::int32_t> textures;  // indices into the texture list
  // Two bits per layer, one for each detail variant that follows the
  // layer's base texture in `textures` (see material_layers()).
  std::uint32_t kind = 0;
};

// `Materials` entry: which textures each terrain material blends.
std::vector<TerrainMaterial> parse_materials(const std::vector<std::uint8_t>& data);

// `TerrainTypes` entry: one 243-byte record per material, mostly physics
// tuning not decoded yet. Returns each record's ground class, the byte that
// says how the ball plays off it: 1 green; 2 fairway, fringe or tee; 3 rough;
// 4 sand; 5 water; 6 path, concrete or asphalt; 7 dirt; 8 bushes; 9 rocks;
// 10 deep or dry grass; 0 seen on a few unnamed records.
std::vector<std::uint8_t> parse_ground_classes(const std::vector<std::uint8_t>& data);

// The parts of a course the viewer needs, read from an open archive.
struct Course {
  std::string name;
  std::vector<Hole> holes;
  Terrain terrain;
  std::vector<TextureDesc> textures;
  std::vector<TerrainMaterial> materials;
  CourseScenery scenery;
};

Course load_course(const CrzArchive& archive);

}  // namespace olcore
