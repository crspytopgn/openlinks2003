#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/course.hpp"

namespace olcore {

// `Mappings` entry: how each terrain triangle lays its textures on the
// ground, and how blended materials fade one texture into another. See
// "Mappings" in docs/formats/crz.md.

enum class MappingKind : std::uint32_t {
  kPlanar = 0,       // a texture frame projected along its third axis
  kCylindrical = 1,  // wrapped round the frame's third axis (rock walls, pools)
  kStrip = 3,        // per-corner coordinates: cart paths and blended edges
  kBlend = 4,        // a strip for the mask plus one planar mapping per layer
};

// One corner of a strip mapping: u runs across the strip (0 on one side, 1
// on the other) and v along it, in texture repeats.
struct StripCorner {
  std::uint32_t vertex = 0;  // index into the terrain vertices
  float u = 0, v = 0;
};

struct StripTriangle {
  std::uint32_t triangle = 0;              // index into the terrain triangles
  std::array<std::uint32_t, 3> corner{};   // indices into `corners`
};

struct TextureMapping {
  MappingKind kind = MappingKind::kPlanar;
  std::string name;
  float scale_u = 1, scale_v = 1;
  // Planar and cylindrical: rows are the frame's u, v and w axes (feet per
  // repeat) and its origin, so a point is origin + u*row0 + v*row1 + w*row2.
  std::array<float, 16> frame{};
  // Strip.
  std::vector<StripTriangle> triangles;
  std::vector<StripCorner> corners;
  // Blend: the strip mapping of the mask, then the mapping of each layer.
  std::array<std::uint32_t, 3> layers{};
};

std::vector<TextureMapping> parse_mappings(const std::vector<std::uint8_t>& data);

// Texture coordinates of course point `p` (feet, z up) under a planar or
// cylindrical mapping.
std::array<float, 2> mapping_uv(const TextureMapping& m, const CourseVec3& p);

// The index of the mapping a terrain triangle uses: the low 16 bits of its
// mapping field (the high half is something else).
inline std::uint32_t mapping_index(const TerrainTriangle& t) { return t.mapping & 0xffff; }

// A terrain material as texture layers. A plain material has one layer; a
// blended one has a mask (black for the first layer, white for the second)
// and two layers. Each layer is a base texture followed by up to two detail
// variants of it, which are skipped here.
struct MaterialLayers {
  bool blended = false;
  std::int32_t mask = -1;  // texture index, or -1
  std::vector<std::int32_t> layers;  // base texture index per layer
};

MaterialLayers material_layers(const TerrainMaterial& m);

}  // namespace olcore
