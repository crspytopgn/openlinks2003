#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace olcore {

// `.SHA` course shadow file (one beside each .CRZ). See
// docs/formats/sha.md. Only the header and the tree shadow shapes are read;
// the rest is skipped.

// The shadow a billboard type casts on the ground, seen from above: 8-bit
// coverage (0 = no shadow), width x height pixels, rows in order. Empty for
// types that cast none (grasses, flowers).
struct ShadowShape {
  std::uint32_t width = 0, height = 0;
  std::vector<std::uint8_t> pixels;
};

struct ShadowFile {
  std::string course;               // the course file it belongs to, e.g. "geagles.CRZ"
  std::uint32_t course_size = 0;    // that file's size in bytes
  std::uint32_t model_count = 0;    // 3D object meshes (MasterObj3D)
  std::uint32_t billboard_type_count = 0;    // MasterObj
  std::uint32_t model_placement_count = 0;   // 3DPlant
  std::uint32_t billboard_count = 0;         // 2DPlant
  std::uint32_t light_map_width = 0, light_map_height = 0;
  std::vector<ShadowShape> shapes;  // one per billboard type
};

ShadowFile parse_shadow_file(const std::vector<std::uint8_t>& data);

}  // namespace olcore
