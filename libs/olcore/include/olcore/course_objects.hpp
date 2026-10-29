#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "olcore/course.hpp"

namespace olcore {

// Billboard objects placed on a course: the `MasterObj` type table and the
// `2DPlant` placement stream. Units are as stored: feet, z up.
// See docs/formats/course-objects.md.

struct BillboardType {
  std::string name;  // base name, e.g. "Tall Trees212"; sprites are <name>A.btc to <name>E.btc
  std::string sprite;  // the largest sprite, e.g. "Tall Trees212A.btc"
  std::uint32_t width = 0, height = 0;  // pixels of the largest sprite
  float aspect = 1;                     // width / height
  std::uint32_t id = 0;                 // object id, as in the Course Designer library
};

// `MasterObj` entry: one type per placement `type` index.
std::vector<BillboardType> parse_billboard_types(const std::vector<std::uint8_t>& data);

struct BillboardPlacement {
  std::uint16_t type = 0;  // index into parse_billboard_types()
  std::uint32_t instance = 0;
  CourseVec3 position;     // base of the billboard
  float height = 0;        // feet
  // Optional fields whose meaning is not known yet; -1 when absent.
  std::int32_t extra_byte = -1;
  std::int32_t extra_word = -1;
};

constexpr float kCellFeet = 64.0f;
constexpr float kPlacementUnit = 1.0f / 16.0f;  // feet per stored step

// `2DPlant` entry (magic "2JBO").
std::vector<BillboardPlacement> parse_billboard_placements(const std::vector<std::uint8_t>& data);

}  // namespace olcore
