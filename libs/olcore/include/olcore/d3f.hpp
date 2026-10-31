#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/btcv.hpp"

namespace olcore {

// Bitmap fonts (.D3F) from GRAPHICS.LS: a Windows font rendered into one or
// more square texture pages. See docs/formats/d3f.md.

// Where one character code (0 to 255, Windows-1252) sits in the pages. A
// glyph with width 0 is not in the font.
struct D3fGlyph {
  std::uint8_t page = 0;
  std::uint8_t x = 0;      // left edge of the cell in the page
  std::uint8_t y = 0;      // top edge; the cell is line_height tall
  std::uint8_t width = 0;  // cell width
  std::int8_t left = 0;    // space before the cell
  std::int8_t right = 0;   // space after it; advance = left + width + right
};

struct D3fFont {
  std::string face;      // e.g. "Arial"
  int pixel_height = 0;  // the em height the font was rendered at
  bool italic = false;
  int weight = 400;      // 400 normal, 700 bold
  int line_height = 0;   // height of every cell
  bool colour = false;   // pages are full colour rather than white with coverage
  std::array<D3fGlyph, 256> glyphs{};
  std::vector<RgbaImage> pages;  // square, rows top to bottom

  // Pixels from the top of a cell to the baseline: the row under the
  // lowest visible pixel of "H" (or of the first capital present).
  int ascent() const;
};

bool is_d3f(const std::uint8_t* data, std::size_t size);

// Throws ReadError on malformed input.
D3fFont read_d3f(const std::uint8_t* data, std::size_t size);
inline D3fFont read_d3f(const std::vector<std::uint8_t>& data) { return read_d3f(data.data(), data.size()); }

}  // namespace olcore
