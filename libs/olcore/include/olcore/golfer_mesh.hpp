#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/carrera_store.hpp"
#include "olcore/golfer_anim.hpp"

namespace olcore {

// A Carrera::Shader: colour and texture of one mesh part.
struct MeshMaterial {
  std::string name;
  std::array<float, 4> diffuse{1.0f, 1.0f, 1.0f, 1.0f};
  std::string texture;  // file name in the same archive ("L_A01_face.tga"), or ""
};

// A Carrera::Shape: one triangle strip drawn with one material. Strip
// indices are relative to first_vertex; repeated indices stitch strips.
struct MeshPart {
  std::size_t first_vertex = 0;
  std::size_t last_vertex = 0;  // inclusive
  std::size_t triangle_count = 0;  // non-degenerate triangles in the strip
  std::vector<std::uint16_t> strip;
  MeshMaterial material;

  // The strip as a triangle list of absolute vertex indices, degenerate
  // triangles dropped and every other triangle flipped so that all keep the
  // strip's winding.
  std::vector<std::uint32_t> triangles() const;
};

// Up to four joints per vertex; joint indices point into
// GolferMesh::skin_joints, unused slots have weight 0.
struct SkinInfluence {
  std::array<std::uint8_t, 4> joint{};
  std::array<float, 4> weight{};
};

// A Carrera::Mesh from a .SKL (docs/formats/carrera-store.md). Positions are
// feet in the model's bind space, which for a golfer is its skeleton's rest
// pose; club meshes are in their own frame with the grip at the origin.
struct GolferMesh {
  std::string name;
  std::string transform;  // the transform that carries the mesh
  std::vector<std::array<float, 3>> positions;
  std::vector<std::array<float, 3>> normals;
  std::vector<std::array<float, 2>> uvs;  // v grows upwards (OpenGL style)
  std::vector<MeshPart> parts;

  // Skin (empty for rigid meshes such as clubs).
  std::vector<std::string> skin_joints;
  std::vector<Mat4> inverse_bind;  // per skin joint: bind-space to joint-space
  std::vector<SkinInfluence> influences;  // per vertex

  bool skinned() const { return !influences.empty(); }
};

// Every mesh in the store. Throws ReadError if a buffer doesn't fit.
std::vector<GolferMesh> read_meshes(const StoreFile& store);

// Skinned positions for a posed skeleton: `world` comes from
// Skeleton::pose(). Joints the skeleton lacks keep their bind pose.
std::vector<std::array<float, 3>> skin_positions(const GolferMesh& mesh, const Skeleton& skeleton,
                                                 const std::vector<Mat4>& world);

}  // namespace olcore
