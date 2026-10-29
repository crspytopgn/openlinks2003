#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/course.hpp"
#include "olcore/crz.hpp"

namespace olcore {

// Converted courses (`.CVT`, CD2 `CONVERT/`): the 39 Links LS courses that
// Links 2003 can rebuild. Each is a locked course archive like a `.CRZ`, but
// with older versions of the hole and terrain entries and terrain types in
// place of materials. See docs/formats/cvt.md.

// One `TerrainTypes` record: a surface and the textures that draw it.
struct TerrainType {
  std::string name;                 // "Fairway", "Sand", ...
  std::string display_name;         // usually the same as name
  std::vector<std::int32_t> textures;  // indices into `txtrdesc`: base, then detail variants
  std::array<std::uint8_t, 3> map_colour{};  // RGB used on the overhead map
};

std::vector<TerrainType> parse_terrain_types(const std::vector<std::uint8_t>& data);

// `header` entry, version 14: the course's short name and its holes.
std::vector<Hole> parse_converted_holes(const std::vector<std::uint8_t>& data, std::string* short_name = nullptr);

// `vertex` entry, version 5: like version 6 but with 16-byte vertices.
// Meshes of more than 65,535 vertices use 32-bit triangle indices.
Terrain parse_converted_terrain(const std::vector<std::uint8_t>& data);

// True if the archive is a converted course rather than a Links 2003 one.
bool is_converted_course(const CrzArchive& archive);

// Loads a converted course. Each terrain type becomes one material, so a
// triangle's material index is its terrain type.
Course load_converted_course(const CrzArchive& archive);

// The full course name for a CD2 `.CVT` file stem ("PEBBLEBE"), or an empty
// string. The archives themselves only carry an 8-character short name.
std::string converted_course_title(const std::string& file_stem);

}  // namespace olcore
