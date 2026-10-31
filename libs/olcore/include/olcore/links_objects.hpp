#pragma once

#include <array>
#include <cstdint>
#include <unordered_map>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/btcv.hpp"

namespace olcore {

// Links 2003's trees and other billboard objects as the ball meets them, in
// the game's frame (see links_ground.hpp: feet, z up). A billboard is a
// flat picture standing on the ground and turned to face the viewer; the
// ball hits it where the picture is opaque. Each object type says which
// part of the picture is solid (a trunk) and how the rest (a canopy) slows
// the ball. See docs/formats/physics.md. The GDScript port is
// game/scripts/physics/links_objects.gd; change both together.

// The opaque parts of a picture. Row 0 is the bottom row for billboards,
// the top row for the textures of 3D objects (as their uvs count).
struct LinksSpriteMask {
  int width = 0, height = 0;
  std::vector<std::uint8_t> alpha;
  std::uint8_t at(int x, int y) const {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    return alpha[std::size_t(y) * std::size_t(width) + std::size_t(x)];
  }
};

// The mask of a decoded picture (rows top to bottom, as decode_btcv gives).
LinksSpriteMask links_sprite_mask(const RgbaImage& image);

// What a type does to the ball: the Course Designer library's `collision`
// and `shape` values, which the course repeats in its `MasterObj` types.
struct LinksObjectType {
  // Bit 0: solid all over (no random turn off it, its own restitution).
  // Bit 1: never solid; the ball can only be slowed by it.
  std::uint32_t collision = 1;
  // 0: restitution off the solid part, and the least speed kept through the
  //    canopy; 1: the chance in ten tenths that the canopy catches the ball;
  // 2 to 5: the solid rectangle (u0, v0, u1, v1) as fractions of the
  //    picture, u across, v up.
  std::array<float, 6> shape{1, 1, 0, 0, 1, 1};
  float aspect = 1;  // picture width / height
  LinksSpriteMask mask;
};

struct LinksBillboard {
  Vec3 base;            // where it is placed, feet
  double height = 0;    // feet; the width is height * aspect
  double anchor_x = 0.5;  // fraction of the width left of the base
  double anchor_z = 0;    // fraction of the height below the base
  int type = 0;
};

// A 3D object's mesh (bridges, walls, buildings) as stored: model units, z
// up, polygons fanned from their first corner (see docs/formats/model.md).
struct LinksMesh {
  struct Face {
    std::uint16_t first = 0, count = 0, texture = 0;
  };
  std::vector<std::array<float, 3>> positions;
  std::vector<std::array<float, 2>> uvs;  // one per corner, v = 0 at the top
  std::vector<std::uint16_t> corners;     // position index per corner
  std::vector<Face> faces;
  // Per texture: the holes of a texture the game marks see-through (rows
  // top first), or an empty mask for a solid one.
  std::vector<LinksSpriteMask> holes;
};

// One placed 3D object: its mesh's points in the game's frame, feet.
struct LinksModel {
  int mesh = 0;
  std::vector<Vec3> points;  // per mesh position
  Vec3 box_min, box_max;
};

// A placement's anchors from its `2DPlant` extra fields (-1 when absent).
double links_anchor_x(std::int32_t extra_byte);
double links_anchor_z(std::int32_t extra_word);

class LinksObjects {
 public:
  std::vector<LinksObjectType> types;
  std::vector<LinksMesh> meshes;

  void add(const LinksBillboard& b);
  const std::vector<LinksBillboard>& billboards() const { return billboards_; }
  // A 3D object: `points` holds its mesh's positions already placed.
  void add_model(LinksModel m);
  const std::vector<LinksModel>& models() const { return models_; }

  struct Hit {
    int object = -1;  // the billboard, or for kind 8 the 3D object
    Vec3 point;   // where the centre's path meets it
    Vec3 normal;  // billboards: horizontal, back towards the viewer; 3D: the face's
    int kind = 0;  // 1 solid, 2 slowed by the canopy, 8 a 3D object's face
    double factor = 0;  // kind 1: restitution; kind 2: speed kept
  };
  // The first billboard the path p -> q goes through, skipping `last` (the
  // one hit before). Billboards turn to face the viewer: `facing` is the
  // horizontal unit vector from them towards the camera (the game uses its
  // view direction; olcore uses the shot's direction, reversed).
  bool hit(Vec3 p, Vec3 q, Vec3 facing, int last, Hit& out) const;
  // One billboard: whether the ray p + t d (d unit) meets it.
  bool hit_one(int index, Vec3 p, Vec3 d, Vec3 facing, Hit& out) const;
  // One 3D object: the nearest face the ray p + t d (d unit) meets within
  // `reach` (any distance when negative), through its see-through holes.
  // Faces seen from behind let it through.
  bool hit_model(int index, Vec3 p, Vec3 d, double reach, Hit& out) const;

 private:
  static constexpr double kCell = 64.0;
  std::vector<LinksBillboard> billboards_;
  std::vector<LinksModel> models_;
  std::unordered_map<std::int64_t, std::vector<int>> cells_;  // billboards
  std::unordered_map<std::int64_t, std::vector<int>> model_cells_;
  static std::int64_t key(std::int64_t cx, std::int64_t cy) { return cx * 1000003 + cy; }
};

}  // namespace olcore
