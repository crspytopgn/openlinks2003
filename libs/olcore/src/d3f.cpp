#include "olcore/d3f.hpp"

#include <algorithm>
#include <cstdlib>
#include <cstring>

#include "olcore/binary_reader.hpp"
#include "olcore/lzw.hpp"

namespace olcore {

namespace {

constexpr std::uint8_t kCoverage = 0xb4;  // 8 bits a pixel: glyph coverage
constexpr std::uint8_t kColour = 0xd4;    // 32 bits a pixel: BGRA
constexpr std::size_t kFaceOffset = 0x04;
constexpr std::size_t kFaceSize = 0x40;
constexpr std::size_t kHeightOffset = 0x44;
constexpr std::size_t kItalicOffset = 0x48;
constexpr std::size_t kWeightOffset = 0x49;
constexpr std::size_t kPagesOffset = 0x4d;
constexpr std::size_t kLineOffset = 0x51;
constexpr std::size_t kTablesOffset = 0x55;  // page, x, y, width, left, right: 256 bytes each
constexpr std::size_t kPageListOffset = kTablesOffset + 6 * 256;
constexpr int kMaxPages = 64;

std::int32_t i32_at(const std::uint8_t* p) {
  return static_cast<std::int32_t>(static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
                                   (static_cast<std::uint32_t>(p[2]) << 16) |
                                   (static_cast<std::uint32_t>(p[3]) << 24));
}

}  // namespace

bool is_d3f(const std::uint8_t* data, std::size_t size) {
  return size > kPageListOffset && data[0] == 'D' && data[1] == '3' && data[2] == 'F' &&
         (data[3] == kCoverage || data[3] == kColour);
}

int D3fFont::ascent() const {
  for (unsigned char c : std::string("HIEFTLA")) {
    const D3fGlyph& g = glyphs[c];
    if (g.width == 0 || g.page >= pages.size()) continue;
    const RgbaImage& img = pages[g.page];
    for (int row = line_height - 1; row >= 0; --row) {
      int y = g.y + row;
      if (y >= img.height) continue;
      for (int x = g.x; x < g.x + g.width && x < img.width; ++x) {
        if (img.pixels[(static_cast<std::size_t>(y) * img.width + x) * 4 + 3] > 64) return row + 1;
      }
    }
  }
  return (line_height * 4 + 2) / 5;
}

D3fFont read_d3f(const std::uint8_t* data, std::size_t size) {
  if (!is_d3f(data, size)) throw ReadError("not a D3F font");
  D3fFont f;
  f.colour = data[3] == kColour;
  const char* face = reinterpret_cast<const char*>(data + kFaceOffset);
  f.face.assign(face, strnlen(face, kFaceSize));
  f.pixel_height = std::abs(i32_at(data + kHeightOffset));
  f.italic = data[kItalicOffset] != 0;
  f.weight = i32_at(data + kWeightOffset);
  const int page_count = i32_at(data + kPagesOffset);
  f.line_height = i32_at(data + kLineOffset);
  if (page_count < 1 || page_count > kMaxPages || f.line_height < 1 || f.line_height > 255) {
    throw ReadError("D3F header out of range");
  }
  if (kPageListOffset + static_cast<std::size_t>(page_count) * 4 > size) throw ReadError("D3F page list truncated");
  for (int c = 0; c < 256; ++c) {
    D3fGlyph& g = f.glyphs[c];
    g.page = data[kTablesOffset + c];
    g.x = data[kTablesOffset + 256 + c];
    g.y = data[kTablesOffset + 512 + c];
    g.width = data[kTablesOffset + 768 + c];
    g.left = static_cast<std::int8_t>(data[kTablesOffset + 1024 + c]);
    g.right = static_cast<std::int8_t>(data[kTablesOffset + 1280 + c]);
  }
  const std::size_t bpp = f.colour ? 4 : 1;
  for (int i = 0; i < page_count; ++i) {
    const std::int32_t at = i32_at(data + kPageListOffset + static_cast<std::size_t>(i) * 4);
    if (at < 0 || static_cast<std::size_t>(at) + 8 > size) throw ReadError("D3F page offset out of range");
    const int side = std::abs(i32_at(data + at));
    const std::int32_t packed = i32_at(data + at + 4);
    if (side < 1 || side > 1024 || packed < 0 || static_cast<std::size_t>(at) + 8 + static_cast<std::size_t>(packed) > size) {
      throw ReadError("D3F page out of range");
    }
    const std::size_t count = static_cast<std::size_t>(side) * static_cast<std::size_t>(side);
    // Streams may end early; the rest of the page is empty.
    std::vector<std::uint8_t> px = lzw_decompress(data + at + 8, static_cast<std::size_t>(packed), count * bpp);
    px.resize(count * bpp, 0);
    RgbaImage img;
    img.width = side;
    img.height = side;
    img.pixels.resize(count * 4);
    for (std::size_t p = 0; p < count; ++p) {
      std::uint8_t* o = &img.pixels[p * 4];
      if (f.colour) {
        o[0] = px[p * 4 + 2];
        o[1] = px[p * 4 + 1];
        o[2] = px[p * 4 + 0];
        o[3] = px[p * 4 + 3];
      } else {
        o[0] = o[1] = o[2] = 255;
        o[3] = px[p];
      }
    }
    f.pages.push_back(std::move(img));
  }
  return f;
}

}  // namespace olcore
