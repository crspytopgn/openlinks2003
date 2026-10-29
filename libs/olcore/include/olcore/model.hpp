#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/btcv.hpp"

namespace olcore {

// A Course Designer 3D object (.XYZ). Units are inches, +y up.
// See docs/formats/model.md.
struct ModelFace {
  std::uint16_t first = 0;    // first corner in Model::corners
  std::uint16_t count = 0;    // corners in this polygon (3 or 4 seen)
  std::uint16_t flags = 0;    // 0, 2 or 3 seen; meaning unknown
  std::uint16_t texture = 0;  // index into the matching .CMF texture set
};

struct Model {
  std::vector<std::array<float, 3>> positions;
  std::vector<std::array<float, 2>> uvs;   // one per corner
  std::vector<std::uint16_t> corners;      // position index per corner
  std::vector<ModelFace> faces;
  std::uint32_t texture_count = 0;
};

Model read_model(const std::vector<std::uint8_t>& data);

// One texture of a .CMF set, with its mip chain (four levels on CD3),
// stored as DXT5 blocks.
struct ModelTextureLevel {
  int width = 0;
  int height = 0;
  std::vector<std::uint8_t> dxt5;
};

struct ModelTexture {
  std::vector<ModelTextureLevel> levels;
  RgbaImage decode(std::size_t level = 0) const;
};

// Reads the unpacked "Textures" entry of a .CMF archive.
std::vector<ModelTexture> read_model_textures(const std::vector<std::uint8_t>& textures_entry,
                                              std::size_t levels_per_texture = 4);

// Triangle list for one texture: positions and uvs are flattened per vertex.
struct ModelSurface {
  std::uint16_t texture = 0;
  std::vector<float> positions;  // x, y, z
  std::vector<float> uvs;        // u, v
  std::vector<std::uint32_t> indices;
};

// Splits a model into one surface per texture and fans its polygons into
// triangles, keeping the original winding.
std::vector<ModelSurface> triangulate(const Model& model);

}  // namespace olcore
