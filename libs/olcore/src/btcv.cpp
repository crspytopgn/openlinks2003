#include "olcore/btcv.hpp"

#include <algorithm>
#include <cstring>
#include <string>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr std::uint8_t kTransparentBlock[16] = {};
// Alpha half of a DXT5 block that decodes to 255 everywhere.
constexpr std::uint8_t kOpaqueAlpha[8] = {0xff, 0, 0, 0, 0, 0, 0, 0};

std::uint16_t le16(const std::uint8_t* p) { return static_cast<std::uint16_t>(p[0] | p[1] << 8); }
std::uint32_t le32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0]) | static_cast<std::uint32_t>(p[1]) << 8 |
         static_cast<std::uint32_t>(p[2]) << 16 | static_cast<std::uint32_t>(p[3]) << 24;
}

int round_to_bits(int v, int max) { return (v * max + 127) / 255; }

void rgb565(std::uint16_t c, std::uint8_t out[3]) {
  int r = c >> 11 & 31, g = c >> 5 & 63, b = c & 31;
  out[0] = static_cast<std::uint8_t>(r << 3 | r >> 2);
  out[1] = static_cast<std::uint8_t>(g << 2 | g >> 4);
  out[2] = static_cast<std::uint8_t>(b << 3 | b >> 2);
}

}  // namespace

bool is_btcv(const std::uint8_t* data, std::size_t size) { return size >= 4 && std::memcmp(data, "BTCV", 4) == 0; }

BtcvHeader read_btcv_header(const std::uint8_t* data, std::size_t size) {
  if (!is_btcv(data, size) || size < 20) throw ReadError("not a BTCV texture");
  BtcvHeader h;
  h.width = le16(data + 4);
  h.height = le16(data + 6);
  h.format = le16(data + 10);
  std::uint32_t count = le32(data + 16);
  if (count > (size - 20) / 16) throw ReadError("BTCV tile table runs past end of data");
  for (std::uint32_t i = 0; i < count; ++i) {
    const std::uint8_t* p = data + 20 + 16 * i;
    BtcvTile t{le16(p), le16(p + 2), le16(p + 4), le16(p + 6), le32(p + 8), le32(p + 12)};
    if (t.size == 0 || t.size % 4 || t.x % 4 || t.y % 4) throw ReadError("BTCV tile has an unaligned size or position");
    if (t.offset > size || t.length > size - t.offset) throw ReadError("BTCV tile runs past end of data");
    h.tiles.push_back(t);
  }
  return h;
}

std::size_t decode_block_runs(const std::uint8_t* data, std::size_t size, std::size_t block_count,
                              std::vector<std::uint8_t>& out) {
  std::size_t pos = 0, done = 0;
  out.reserve(out.size() + block_count * kDxt5BlockBytes);
  while (done < block_count) {
    if (size - pos < 2) throw ReadError("block runs end early");
    unsigned head = le16(data + pos);
    pos += 2;
    std::size_t n = head & 0xfff;
    if (n == 0) n = 0x1000;
    unsigned mode = head >> 12;
    if (n > block_count - done) throw ReadError("block run overflows its image");
    static constexpr std::size_t kStride[5] = {0, 0, 8, 16, 4};
    if (mode < 1 || mode > 4) throw ReadError("unknown block run mode " + std::to_string(mode));
    if (n * kStride[mode] > size - pos) throw ReadError("block run data truncated");
    for (std::size_t i = 0; i < n; ++i) {
      const std::uint8_t* src = data + pos + i * kStride[mode];
      switch (mode) {
        case 1:
          out.insert(out.end(), kTransparentBlock, kTransparentBlock + 16);
          break;
        case 2:
          out.insert(out.end(), kOpaqueAlpha, kOpaqueAlpha + 8);
          out.insert(out.end(), src, src + 8);
          break;
        case 3:
          out.insert(out.end(), src, src + 16);
          break;
        case 4: {
          // Flat colour stored as B, G, R, A. The game rounds it to RGB565 and
          // treats the block as opaque.
          auto c = static_cast<std::uint16_t>(round_to_bits(src[2], 31) << 11 | round_to_bits(src[1], 63) << 5 |
                                              round_to_bits(src[0], 31));
          out.insert(out.end(), kOpaqueAlpha, kOpaqueAlpha + 8);
          const std::uint8_t color[8] = {static_cast<std::uint8_t>(c & 0xff), static_cast<std::uint8_t>(c >> 8), 0, 0, 0, 0,
                                         0, 0};
          out.insert(out.end(), color, color + 8);
          break;
        }
      }
    }
    pos += n * kStride[mode];
    done += n;
  }
  return pos;
}

RgbaImage decode_dxt5(const std::uint8_t* blocks, int blocks_wide, int blocks_high) {
  RgbaImage img;
  img.width = blocks_wide * 4;
  img.height = blocks_high * 4;
  img.pixels.assign(static_cast<std::size_t>(img.width) * img.height * 4, 0);
  for (int by = 0; by < blocks_high; ++by) {
    for (int bx = 0; bx < blocks_wide; ++bx) {
      const std::uint8_t* b = blocks + (static_cast<std::size_t>(by) * blocks_wide + bx) * kDxt5BlockBytes;
      int a[8] = {b[0], b[1]};
      if (a[0] > a[1]) {
        for (int i = 1; i < 7; ++i) a[i + 1] = ((7 - i) * a[0] + i * a[1]) / 7;
      } else {
        for (int i = 1; i < 5; ++i) a[i + 1] = ((5 - i) * a[0] + i * a[1]) / 5;
        a[6] = 0;
        a[7] = 255;
      }
      std::uint64_t abits = 0;
      for (int i = 0; i < 6; ++i) abits |= static_cast<std::uint64_t>(b[2 + i]) << (8 * i);
      std::uint8_t c[4][3];
      rgb565(le16(b + 8), c[0]);
      rgb565(le16(b + 10), c[1]);
      for (int k = 0; k < 3; ++k) {
        c[2][k] = static_cast<std::uint8_t>((2 * c[0][k] + c[1][k]) / 3);
        c[3][k] = static_cast<std::uint8_t>((c[0][k] + 2 * c[1][k]) / 3);
      }
      std::uint32_t cbits = le32(b + 12);
      for (int i = 0; i < 16; ++i) {
        int px = bx * 4 + (i & 3), py = by * 4 + (i >> 2);
        std::uint8_t* o = &img.pixels[(static_cast<std::size_t>(py) * img.width + px) * 4];
        const std::uint8_t* col = c[cbits >> (2 * i) & 3];
        o[0] = col[0];
        o[1] = col[1];
        o[2] = col[2];
        o[3] = static_cast<std::uint8_t>(a[abits >> (3 * i) & 7]);
      }
    }
  }
  return img;
}

std::vector<std::uint8_t> btcv_to_dxt5(const std::uint8_t* data, std::size_t size, BtcvHeader* header_out) {
  BtcvHeader h = read_btcv_header(data, size);
  const int bw = (h.width + 3) / 4, bh = (h.height + 3) / 4;
  std::vector<std::uint8_t> canvas(static_cast<std::size_t>(bw) * bh * kDxt5BlockBytes, 0);
  std::vector<std::uint8_t> tile;
  for (const BtcvTile& t : h.tiles) {
    const int tb = t.size / 4;
    tile.clear();
    decode_block_runs(data + t.offset, t.length, static_cast<std::size_t>(tb) * tb, tile);
    // Tile positions count from the bottom left; canvas rows run top down.
    const int top = bh - t.y / 4 - tb, left = t.x / 4;
    for (int r = 0; r < tb; ++r) {
      int row = top + r;
      if (row < 0 || row >= bh) continue;
      int cols = std::min(tb, bw - left);
      if (cols <= 0) continue;
      std::memcpy(&canvas[(static_cast<std::size_t>(row) * bw + left) * kDxt5BlockBytes],
                  &tile[static_cast<std::size_t>(r) * tb * kDxt5BlockBytes], static_cast<std::size_t>(cols) * kDxt5BlockBytes);
    }
  }
  if (header_out) *header_out = std::move(h);
  return canvas;
}

RgbaImage decode_btcv(const std::uint8_t* data, std::size_t size) {
  BtcvHeader h;
  auto canvas = btcv_to_dxt5(data, size, &h);
  const int bw = (h.width + 3) / 4, bh = (h.height + 3) / 4;
  RgbaImage full = decode_dxt5(canvas.data(), bw, bh);
  RgbaImage img;
  img.width = h.width;
  img.height = h.height;
  img.pixels.resize(static_cast<std::size_t>(h.width) * h.height * 4);
  const int skip = full.height - h.height;  // padding rows sit at the top
  for (int y = 0; y < h.height; ++y) {
    std::memcpy(&img.pixels[static_cast<std::size_t>(y) * h.width * 4],
                &full.pixels[static_cast<std::size_t>(y + skip) * full.width * 4], static_cast<std::size_t>(h.width) * 4);
  }
  return img;
}

std::vector<std::uint8_t> encode_tga(const RgbaImage& img) {
  std::vector<std::uint8_t> out(18, 0);
  out[2] = 2;
  out[12] = static_cast<std::uint8_t>(img.width & 0xff);
  out[13] = static_cast<std::uint8_t>(img.width >> 8);
  out[14] = static_cast<std::uint8_t>(img.height & 0xff);
  out[15] = static_cast<std::uint8_t>(img.height >> 8);
  out[16] = 32;
  out[17] = 0x28;  // 8 alpha bits, top-left origin
  out.insert(out.end(), img.pixels.begin(), img.pixels.end());
  for (std::size_t i = 18; i + 3 < out.size(); i += 4) std::swap(out[i], out[i + 2]);  // RGBA -> BGRA
  return out;
}

}  // namespace olcore
