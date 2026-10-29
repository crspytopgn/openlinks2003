#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace olcore {

// 8-bit RGBA pixels, rows top to bottom.
struct RgbaImage {
  int width = 0;
  int height = 0;
  std::vector<std::uint8_t> pixels;  // width * height * 4
};

// One tile of a BTCV texture. See docs/formats/btcv.md.
struct BtcvTile {
  std::uint16_t id = 0;
  std::uint16_t size = 0;  // edge in pixels: 64, 128 or 256
  std::uint16_t x = 0;     // left edge, from the left of the image
  std::uint16_t y = 0;     // bottom edge, from the bottom of the image
  std::uint32_t offset = 0;
  std::uint32_t length = 0;
};

struct BtcvHeader {
  std::uint16_t width = 0;
  std::uint16_t height = 0;
  std::uint16_t format = 0;
  std::vector<BtcvTile> tiles;
};

constexpr std::size_t kDxt5BlockBytes = 16;

bool is_btcv(const std::uint8_t* data, std::size_t size);
BtcvHeader read_btcv_header(const std::uint8_t* data, std::size_t size);

// Expands block runs into block_count DXT5 blocks appended to out. Returns the
// number of input bytes used. Throws ReadError on malformed input.
std::size_t decode_block_runs(const std::uint8_t* data, std::size_t size, std::size_t block_count,
                              std::vector<std::uint8_t>& out);

// Decodes DXT5 blocks laid out blocks_wide x blocks_high in raster order.
RgbaImage decode_dxt5(const std::uint8_t* blocks, int blocks_wide, int blocks_high);

// Assembles the tiles of a BTCV texture into one DXT5 canvas of
// ceil(width/4) x ceil(height/4) blocks, rows top to bottom. Blocks not
// covered by a tile are transparent. The bottom rows of the canvas line up
// with the bottom of the image, so when height is not a multiple of four the
// top (4 - height % 4) rows are padding.
std::vector<std::uint8_t> btcv_to_dxt5(const std::uint8_t* data, std::size_t size, BtcvHeader* header = nullptr);

// Decodes a whole BTCV texture to RGBA.
RgbaImage decode_btcv(const std::uint8_t* data, std::size_t size);
inline RgbaImage decode_btcv(const std::vector<std::uint8_t>& data) { return decode_btcv(data.data(), data.size()); }

}  // namespace olcore
