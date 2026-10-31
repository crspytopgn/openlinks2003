#include "olcore/panorama.hpp"

#include <algorithm>
#include <cstring>
#include <string>

#include "olcore/binary_reader.hpp"
#include "olcore/image.hpp"

namespace olcore {

namespace {

std::uint32_t le32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0]) | static_cast<std::uint32_t>(p[1]) << 8 |
         static_cast<std::uint32_t>(p[2]) << 16 | static_cast<std::uint32_t>(p[3]) << 24;
}

constexpr std::size_t kHeaderBytes = 20;

}  // namespace

bool is_panorama(const std::uint8_t* data, std::size_t size) {
  return size >= kHeaderBytes && (std::memcmp(data, "nap\0", 4) == 0 || std::memcmp(data, "yks\0", 4) == 0);
}

PanoramaHeader read_panorama_header(const std::uint8_t* data, std::size_t size) {
  if (!is_panorama(data, size)) throw ReadError("not a panorama");
  PanoramaHeader h;
  h.kind = data[0] == 'n' ? PanoramaKind::Horizon : PanoramaKind::Sky;
  h.width = le32(data + 4);
  h.height = le32(data + 8);
  h.columns = le32(data + 12);
  h.rows = le32(data + 16);
  if (h.width == 0 || h.height == 0 || h.width > 32768 || h.height > 8192) throw ReadError("bad panorama size");
  if (panorama_row_sizes(h.height).size() != h.rows) throw ReadError("panorama tile rows don't match its height");
  return h;
}

std::vector<int> panorama_row_sizes(std::uint32_t height) {
  std::vector<int> sizes;
  std::uint32_t left = height;
  while (left > 0) {
    int s = 256;
    if (left < 256) {
      s = 4;
      while (static_cast<std::uint32_t>(s) < left) s *= 2;
    }
    sizes.push_back(s);
    left -= std::min<std::uint32_t>(left, static_cast<std::uint32_t>(s));
  }
  return sizes;
}

RgbaImage decode_panorama(const std::uint8_t* data, std::size_t size) {
  const PanoramaHeader h = read_panorama_header(data, size);
  const auto sizes = panorama_row_sizes(h.height);
  RgbaImage img;
  img.width = static_cast<int>(h.width);
  img.height = static_cast<int>(h.height);
  img.pixels.assign(static_cast<std::size_t>(img.width) * img.height * 4, 0);
  std::size_t pos = kHeaderBytes;
  int top = 0;
  std::vector<std::uint8_t> blocks;
  for (int edge : sizes) {
    const int across = (img.width + edge - 1) / edge;
    for (int c = 0; c < across; ++c) {
      if (pos + 4 > size) throw ReadError("panorama ends early");
      if (std::memcmp(data + pos, "tpme", 4) == 0) {  // "empt": nothing drawn here
        pos += 4;
        continue;
      }
      if (std::memcmp(data + pos, "desu", 4) != 0 || pos + 8 > size) throw ReadError("bad panorama tile tag");
      const std::uint32_t length = le32(data + pos + 4);
      pos += 8;
      if (length > size - pos) throw ReadError("panorama tile past the end");
      blocks.clear();
      const std::size_t used = decode_block_runs(data + pos, length, static_cast<std::size_t>(edge / 4) * (edge / 4), blocks);
      if (used != length) throw ReadError("panorama tile runs don't fill the tile");
      pos += length;
      const RgbaImage tile = decode_dxt5(blocks.data(), edge / 4, edge / 4);
      // The last tile row is cropped at the bottom, the last column on the right.
      const int cols = std::min(edge, img.width - c * edge);
      for (int y = 0; y < edge && top + y < img.height; ++y) {
        std::memcpy(&img.pixels[(static_cast<std::size_t>(top + y) * img.width + static_cast<std::size_t>(c) * edge) * 4],
                    &tile.pixels[static_cast<std::size_t>(y) * edge * 4], static_cast<std::size_t>(cols) * 4);
      }
    }
    top += edge;
  }
  if (pos != size) throw ReadError("trailing bytes after the panorama");
  return img;
}

RgbaImage decode_sky_archive(const Arc0Archive& sky) {
  std::vector<RgbaImage> tiles;
  for (std::size_t n = 1;; ++n) {
    const std::string name = "_s_k_y_" + std::to_string(n) + ".tga";
    if (!sky.find(name)) break;
    auto tile = decode_tga(sky.read(name));
    if (!tile || tile->width != tile->height || tile->width < 4) throw ReadError("bad sky tile " + name);
    tiles.push_back(std::move(*tile));
  }
  if (tiles.empty()) throw ReadError("no sky tiles");
  // Rows: runs of tiles with the same edge.
  struct Row {
    std::size_t first, count;
    int edge;
  };
  std::vector<Row> rows;
  for (std::size_t i = 0; i < tiles.size(); ++i) {
    if (rows.empty() || rows.back().edge != tiles[i].width) rows.push_back({i, 0, tiles[i].width});
    ++rows.back().count;
  }
  int width = 0, height = 0;
  for (const Row& r : rows) {
    const int w = static_cast<int>(r.count) * r.edge;
    width = width == 0 ? w : std::min(width, w);
    height += r.edge;
  }
  RgbaImage out;
  out.width = width;
  out.height = height;
  out.pixels.assign(std::size_t(width) * height * 4, 0);
  int top = 0;
  for (const Row& r : rows) {
    for (std::size_t c = 0; c < r.count; ++c) {
      const RgbaImage& t = tiles[r.first + c];
      const int x0 = static_cast<int>(c) * r.edge;
      const int span = std::min(r.edge, width - x0);
      for (int y = 0; y < r.edge && span > 0; ++y) {
        std::memcpy(&out.pixels[(std::size_t(top + y) * width + x0) * 4], &t.pixels[std::size_t(y) * t.width * 4],
                    std::size_t(span) * 4);
      }
    }
    top += r.edge;
  }
  return out;
}

}  // namespace olcore
