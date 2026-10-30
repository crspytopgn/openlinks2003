#pragma once
// Plain image files: reading the game's TGAs and writing PNGs, for tools that
// export textures (tools/oltex). See docs/hd-textures.md.

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include "olcore/btcv.hpp"

namespace olcore {

// Decodes a Truevision TGA: uncompressed or RLE, true colour (16, 24 or 32
// bits), grey or colour-mapped. Rows come out top down whatever the file's
// origin. A 32-bit file whose alpha bytes are all zero is treated as opaque.
// Returns nothing for anything else.
std::optional<RgbaImage> decode_tga(const std::uint8_t* data, std::size_t size);
inline std::optional<RgbaImage> decode_tga(const std::vector<std::uint8_t>& data) {
  return decode_tga(data.data(), data.size());
}

// True if every pixel has alpha 255.
bool is_opaque(const RgbaImage& img);

// A zlib stream (RFC 1950) holding `data`, compressed with LZ77 and the fixed
// Huffman codes. Simple and fast rather than small.
std::vector<std::uint8_t> zlib_compress(const std::uint8_t* data, std::size_t size);

std::uint32_t crc32(const std::uint8_t* data, std::size_t size, std::uint32_t start = 0);

// A PNG of the image: 8-bit RGB when it is fully opaque, otherwise RGBA.
std::vector<std::uint8_t> encode_png(const RgbaImage& img);

// Copies `src` into a new image `pad` pixels larger on each side, filling the
// border by wrapping around (for textures that tile), so an upscaler sees the
// neighbouring texels at the edges. With wrap_y false only the left and right
// borders are added.
RgbaImage pad_wrapped(const RgbaImage& src, int pad, bool wrap_y = true);

// Spreads the colour of visible pixels into fully transparent ones (alpha 0),
// leaving alpha alone, so that filtering or upscaling a sprite does not pull
// black into its edges.
void bleed_transparent(RgbaImage& img, int passes = 8);

}  // namespace olcore
