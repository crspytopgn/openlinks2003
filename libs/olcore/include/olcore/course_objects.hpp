#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/btcv.hpp"
#include "olcore/course.hpp"
#include "olcore/model.hpp"

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
  // How the ball meets it: the library's `collision` and `shape` values
  // (see LinksObjectType in links_objects.hpp). Solid all over when absent.
  std::uint32_t collision = 1;
  std::array<float, 6> shape{1, 1, 0, 0, 1, 1};
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

// `TrnyPlant` entry: spectators and other people shown in tournaments. The
// same cells as `2DPlant`, but a cell starts with one 0xFF byte and a
// placement has no type table index or height.
struct CrowdPlacement {
  std::uint8_t kind = 0;  // 0 almost always; 1 to 3 rarely
  std::uint32_t instance = 0;
  CourseVec3 position;
  std::int32_t extra_byte = -1;
  std::int32_t extra_word = -1;
};

std::vector<CrowdPlacement> parse_crowd_placements(const std::vector<std::uint8_t>& data);

// --- 3D objects ------------------------------------------------------------

// One mesh of `MasterObj3D`. The mesh uses the .XYZ layout (see model.md),
// but course meshes are z up and are scaled into feet by their placements.
struct CourseModel {
  std::uint32_t id = 0;
  std::uint32_t kind = 0;  // 2 or 6 seen
  Model model;
};

std::vector<CourseModel> parse_course_models(const std::vector<std::uint8_t>& data);

// `3DPlant` entry: one 88-byte record per placement.
struct ModelPlacement {
  std::uint32_t instance = 0;
  std::uint32_t model = 0;  // index into parse_course_models()
  CourseVec3 position;
  CourseVec3 box_max, box_min;  // feet; a point for records that draw nothing
  float z_offset = 0;           // model units, added to z before scaling
  // The axis the model turns about by `yaw`: nearly (0, 0, 1) or (0, 0, -1)
  // for most objects; zero for records that draw nothing.
  std::array<float, 3> axis{0, 0, 0};
  float flag = 0;  // axis[2]: 0 for records that draw nothing
  std::array<float, 3> scale{0, 0, 0};
  float yaw = 0;    // radians about `axis`
  float pitch = 0;  // slope: z rises by pitch * x (fence rails following the ground)
  bool drawn() const { return flag != 0; }
};

std::vector<ModelPlacement> parse_model_placements(const std::vector<std::uint8_t>& data);

// The game's transform for one placement, as rows (a point is a row vector):
// course feet = (x, y, z) * rows + origin, where (x, y, z) is the model
// point after adding z_offset to z, scaling and sloping (z += pitch * x).
// The rows turn by yaw about the axis (made orthonormal). It reproduces the
// stored bounding boxes to a fraction of a millimetre.
struct ModelTransform {
  std::array<std::array<double, 3>, 3> rows{};
  CourseVec3 origin;
};
ModelTransform model_transform(const ModelPlacement& p);

// Model-space point (as stored) to course feet for one placement.
CourseVec3 place_point(const ModelPlacement& p, const std::array<float, 3>& v);
CourseVec3 place_point(const ModelTransform& t, const ModelPlacement& p, const std::array<float, 3>& v);

// `texture3dobj.t3l` entry: for each course model, the `.maq` entry holding
// its textures and, per texture, the index of its largest level in that file.
struct ModelTextureRefs {
  std::vector<std::string> maq;       // per texture (one file per model so far)
  std::vector<std::uint32_t> level;   // per texture
  // Per texture: the level's flags mark it see-through (the sign bit), so a
  // ball passes where its alpha is zero.
  std::vector<bool> see_through;
};

std::vector<ModelTextureRefs> parse_object_textures(const std::vector<std::uint8_t>& data);

// `.maq` entry: 8-bit textures with a 256-colour palette per level.
struct MaqLevel {
  std::uint32_t width = 0, height = 0;
  std::uint32_t palette = 0, pixels = 0;  // offsets in the entry
};

std::vector<MaqLevel> read_maq_levels(const std::vector<std::uint8_t>& data);
RgbaImage decode_maq(const std::vector<std::uint8_t>& data, std::size_t level);

}  // namespace olcore
