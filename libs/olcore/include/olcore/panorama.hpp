#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "olcore/arc0.hpp"
#include "olcore/btcv.hpp"

namespace olcore {

// Panoramic images: the course horizon (`Panorama` in a .CRZ, `PanNN.btc` in
// PANSKY.LIB, tag `nap`) and the cloud skies (`skyNN.btc`, tag `yks`). See
// docs/formats/panorama.md.
enum class PanoramaKind { Horizon, Sky };

struct PanoramaHeader {
  PanoramaKind kind = PanoramaKind::Horizon;
  std::uint32_t width = 0;   // pixels; the image wraps all the way round
  std::uint32_t height = 0;  // pixels
  std::uint32_t columns = 0; // tiles across the first tile row
  std::uint32_t rows = 0;    // tile rows
};

bool is_panorama(const std::uint8_t* data, std::size_t size);
PanoramaHeader read_panorama_header(const std::uint8_t* data, std::size_t size);

// Edge in pixels of each tile row, top to bottom: 256 while at least 256 rows
// are left, then the smallest power of two (at least 4) that covers the rest.
std::vector<int> panorama_row_sizes(std::uint32_t height);

// Decodes a whole panorama to RGBA, rows top to bottom. Throws ReadError on
// malformed input.
RgbaImage decode_panorama(const std::uint8_t* data, std::size_t size);
inline RgbaImage decode_panorama(const std::vector<std::uint8_t>& data) {
  return decode_panorama(data.data(), data.size());
}

// A custom sky from the 1.07 patch (`skies/<name>.sky`): an ARC0 archive of
// square TGA tiles `_s_k_y_1.tga`, `_s_k_y_2.tga`, ... laid out like a sky
// panorama's (rows top to bottom, each row's tiles left to right, one edge
// per row), plus a `sky.prv` preview. The image is as tall as the rows and
// as wide as the narrowest row. Throws ReadError on malformed input.
RgbaImage decode_sky_archive(const Arc0Archive& sky);

}  // namespace olcore
