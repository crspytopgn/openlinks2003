#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace olcore {

// `.SHA` course shadow file (one beside each .CRZ). See
// docs/formats/sha.md. The whole file is read.

// What something hides from the light, seen from straight above: 8-bit
// coverage, width x height pixels, rows in order. For a billboard type (a
// tree, a bush) it is 0 = no shadow to 255 = full shadow over a square
// round the trunk; for a 3D object, 0xFE where the object is and 0 where it
// isn't, over the box of the mesh's own x and y (row 0 at its least y).
// Empty for things that cast none (grasses, flowers).
struct ShadowShape {
  std::uint32_t width = 0, height = 0;
  std::vector<std::uint8_t> pixels;
};

// Per caster, a list of cells: indices into a course-wide table of
// `RayEngine` cells the shadow falls on. Caster i's cells are
// cells[start[i] .. start[i + 1]).
struct ShadowCells {
  std::vector<std::uint32_t> start;  // one more than the casters
  std::vector<std::uint32_t> cells;
};

struct ShadowFile {
  std::string course;               // the course file it belongs to, e.g. "geagles.CRZ"
  std::uint32_t course_size = 0;    // that file's size in bytes
  std::uint64_t file_time = 0;      // Windows FILETIME of that course file
  std::uint32_t stamp = 0;          // a Unix time in 2002, probably when this was built
  std::uint32_t model_count = 0;    // 3D object meshes (MasterObj3D)
  std::uint32_t billboard_type_count = 0;    // MasterObj
  std::uint32_t model_placement_count = 0;   // 3DPlant records, drawn or not
  std::uint32_t billboard_count = 0;         // 2DPlant placements
  std::vector<ShadowShape> object_shapes;    // per 3D object mesh
  ShadowCells placement_cells;               // per 3DPlant record
  std::vector<float> billboard_light;        // per 2DPlant placement: 1 = in the open, less under trees
  std::vector<ShadowShape> shapes;           // per billboard type
  ShadowCells billboard_cells;               // per 2DPlant placement
};

ShadowFile parse_shadow_file(const std::vector<std::uint8_t>& data);

}  // namespace olcore
