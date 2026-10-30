#include "olcore/image.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>

#include "olcore/inflate.hpp"

namespace olcore {

namespace {

std::uint16_t le16(const std::uint8_t* p) { return static_cast<std::uint16_t>(p[0] | p[1] << 8); }

// Expands a stored pixel of `bytes` bytes (B, G, R[, A] or 16-bit ARGB1555)
// into RGBA.
void expand(const std::uint8_t* p, int bytes, bool grey, std::uint8_t out[4]) {
  if (grey) {
    out[0] = out[1] = out[2] = p[0];
    out[3] = bytes == 2 ? p[1] : 255;
  } else if (bytes == 2) {
    unsigned v = le16(p);
    unsigned r = v >> 10 & 31, g = v >> 5 & 31, b = v & 31;
    out[0] = static_cast<std::uint8_t>(r << 3 | r >> 2);
    out[1] = static_cast<std::uint8_t>(g << 3 | g >> 2);
    out[2] = static_cast<std::uint8_t>(b << 3 | b >> 2);
    out[3] = (v & 0x8000) ? 255 : 0;
  } else {
    out[0] = p[2];
    out[1] = p[1];
    out[2] = p[0];
    out[3] = bytes == 4 ? p[3] : 255;
  }
}

// --- Deflate with fixed Huffman codes ----------------------------------------

class BitWriter {
public:
  explicit BitWriter(std::vector<std::uint8_t>& out) : out_(out) {}
  void bits(std::uint32_t value, int count) {  // least significant bit first
    acc_ |= static_cast<std::uint64_t>(value) << n_;
    n_ += count;
    while (n_ >= 8) {
      out_.push_back(static_cast<std::uint8_t>(acc_));
      acc_ >>= 8;
      n_ -= 8;
    }
  }
  void code(std::uint32_t code, int length) {  // Huffman codes go most significant bit first
    std::uint32_t r = 0;
    for (int i = 0; i < length; ++i) r |= (code >> i & 1) << (length - 1 - i);
    bits(r, length);
  }
  void flush() {
    if (n_ > 0) out_.push_back(static_cast<std::uint8_t>(acc_));
    acc_ = 0;
    n_ = 0;
  }

private:
  std::vector<std::uint8_t>& out_;
  std::uint64_t acc_ = 0;
  int n_ = 0;
};

constexpr int kLengthBase[29] = {3,  4,  5,  6,  7,  8,  9,  10, 11,  13,  15,  17,  19,  23, 27,
                                 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
constexpr int kLengthExtra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
constexpr int kDistBase[30] = {1,   2,   3,   4,   5,   7,    9,    13,   17,   25,   33,   49,   65,    97,    129,
                               193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
constexpr int kDistExtra[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};

void put_symbol(BitWriter& w, int sym) {
  if (sym < 144) w.code(0x30 + sym, 8);
  else if (sym < 256) w.code(0x190 + sym - 144, 9);
  else if (sym < 280) w.code(sym - 256, 7);
  else w.code(0xc0 + sym - 280, 8);
}

void put_match(BitWriter& w, int length, int distance) {
  int l = 28;
  while (kLengthBase[l] > length) --l;
  put_symbol(w, 257 + l);
  w.bits(static_cast<std::uint32_t>(length - kLengthBase[l]), kLengthExtra[l]);
  int d = 29;
  while (kDistBase[d] > distance) --d;
  w.code(static_cast<std::uint32_t>(d), 5);
  w.bits(static_cast<std::uint32_t>(distance - kDistBase[d]), kDistExtra[d]);
}

// Paeth predictor (PNG filter 4).
int paeth(int a, int b, int c) {
  int p = a + b - c, pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

void put_be32(std::vector<std::uint8_t>& v, std::uint32_t x) {
  v.insert(v.end(), {static_cast<std::uint8_t>(x >> 24), static_cast<std::uint8_t>(x >> 16), static_cast<std::uint8_t>(x >> 8),
                     static_cast<std::uint8_t>(x)});
}

void put_chunk(std::vector<std::uint8_t>& out, const char type[4], const std::vector<std::uint8_t>& body) {
  put_be32(out, static_cast<std::uint32_t>(body.size()));
  std::size_t start = out.size();
  out.insert(out.end(), type, type + 4);
  out.insert(out.end(), body.begin(), body.end());
  put_be32(out, crc32(out.data() + start, out.size() - start));
}

}  // namespace

std::optional<RgbaImage> decode_tga(const std::uint8_t* d, std::size_t size) {
  if (size < 18) return std::nullopt;
  const int id_length = d[0], map_type = d[1], type = d[2];
  const int map_first = le16(d + 3), map_length = le16(d + 5), map_bits = d[7];
  const int width = le16(d + 12), height = le16(d + 14), bits = d[16], desc = d[17];
  const bool rle = type >= 9;
  const int kind = type & 7;  // 1 colour-mapped, 2 true colour, 3 grey
  if (width == 0 || height == 0 || (kind != 1 && kind != 2 && kind != 3) || type > 11) return std::nullopt;
  if (kind == 2 && bits != 16 && bits != 15 && bits != 24 && bits != 32) return std::nullopt;
  if ((kind == 1 && bits != 8) || (kind == 3 && bits != 8 && bits != 16)) return std::nullopt;
  std::size_t pos = 18 + static_cast<std::size_t>(id_length);
  std::vector<std::uint8_t> palette;  // RGBA
  if (map_type == 1) {
    const int entry = (map_bits + 7) / 8;
    if (entry < 2 || entry > 4) return std::nullopt;
    std::size_t bytes = static_cast<std::size_t>(map_length) * entry;
    if (pos + bytes > size) return std::nullopt;
    palette.resize(static_cast<std::size_t>(map_first + map_length) * 4, 0);
    for (int i = 0; i < map_length; ++i) expand(d + pos + i * entry, entry, false, &palette[(map_first + i) * 4u]);
    pos += bytes;
  }
  if (kind == 1 && palette.empty()) return std::nullopt;
  const int bpp = (bits + 7) / 8;
  const std::size_t count = static_cast<std::size_t>(width) * height;
  std::vector<std::uint8_t> raw(count * 4);
  auto put = [&](std::size_t i, const std::uint8_t* p) {
    if (kind == 1) {
      std::size_t at = static_cast<std::size_t>(p[0]) * 4;
      if (at + 4 <= palette.size()) std::memcpy(&raw[i * 4], &palette[at], 4);
    } else {
      expand(p, bpp, kind == 3, &raw[i * 4]);
    }
  };
  std::size_t i = 0;
  while (i < count) {
    if (!rle) {
      if (pos + bpp > size) return std::nullopt;
      put(i++, d + pos);
      pos += bpp;
      continue;
    }
    if (pos >= size) return std::nullopt;
    int head = d[pos++], n = (head & 0x7f) + 1;
    if (head & 0x80) {
      if (pos + bpp > size) return std::nullopt;
      for (int k = 0; k < n && i < count; ++k) put(i++, d + pos);
      pos += bpp;
    } else {
      if (pos + static_cast<std::size_t>(n) * bpp > size) return std::nullopt;
      for (int k = 0; k < n && i < count; ++k, pos += bpp) put(i++, d + pos);
    }
  }
  if (kind == 2 && bpp == 4) {
    bool any = false;
    for (std::size_t k = 0; k < count && !any; ++k) any = raw[k * 4 + 3] != 0;
    if (!any)
      for (std::size_t k = 0; k < count; ++k) raw[k * 4 + 3] = 255;
  }
  RgbaImage img;
  img.width = width;
  img.height = height;
  img.pixels.resize(raw.size());
  const bool top_down = desc & 0x20, right_to_left = desc & 0x10;
  for (int y = 0; y < height; ++y) {
    int src_y = top_down ? y : height - 1 - y;
    for (int x = 0; x < width; ++x) {
      int src_x = right_to_left ? width - 1 - x : x;
      std::memcpy(&img.pixels[(static_cast<std::size_t>(y) * width + x) * 4],
                  &raw[(static_cast<std::size_t>(src_y) * width + src_x) * 4], 4);
    }
  }
  return img;
}

bool is_opaque(const RgbaImage& img) {
  for (std::size_t i = 3; i < img.pixels.size(); i += 4)
    if (img.pixels[i] != 255) return false;
  return true;
}

std::vector<std::uint8_t> zlib_compress(const std::uint8_t* data, std::size_t size) {
  std::vector<std::uint8_t> out = {0x78, 0x01};
  BitWriter w(out);
  w.bits(1, 1);  // final block
  w.bits(1, 2);  // fixed Huffman codes
  constexpr int kHashBits = 15, kWindow = 32768, kMaxChain = 32, kMaxMatch = 258;
  std::vector<int> head(1 << kHashBits, -1), prev(kWindow, -1);
  auto hash = [&](std::size_t i) {
    return static_cast<int>(((data[i] << 10) ^ (data[i + 1] << 5) ^ data[i + 2]) & ((1 << kHashBits) - 1));
  };
  auto insert = [&](std::size_t i) {
    if (i + 2 >= size) return;
    int h = hash(i);
    prev[i % kWindow] = head[h];
    head[h] = static_cast<int>(i);
  };
  std::size_t i = 0;
  while (i < size) {
    int best_len = 0, best_dist = 0;
    if (i + 2 < size) {
      int cand = head[hash(i)];
      const int limit = static_cast<int>(std::min<std::size_t>(kMaxMatch, size - i));
      for (int chain = 0; cand >= 0 && chain < kMaxChain; ++chain) {
        int dist = static_cast<int>(i) - cand;
        if (dist > kWindow - 1 || dist <= 0) break;
        if (data[cand + best_len] == data[i + best_len]) {
          int len = 0;
          while (len < limit && data[cand + len] == data[i + len]) ++len;
          if (len > best_len) {
            best_len = len;
            best_dist = dist;
            if (len == limit) break;
          }
        }
        int next = prev[cand % kWindow];
        if (next >= cand) break;
        cand = next;
      }
    }
    if (best_len >= 3) {
      put_match(w, best_len, best_dist);
      for (int k = 0; k < best_len; ++k) insert(i + k);
      i += best_len;
    } else {
      put_symbol(w, data[i]);
      insert(i);
      ++i;
    }
  }
  put_symbol(w, 256);
  w.flush();
  put_be32(out, adler32(data, size));
  return out;
}

std::uint32_t crc32(const std::uint8_t* data, std::size_t size, std::uint32_t start) {
  static const std::array<std::uint32_t, 256> table = [] {
    std::array<std::uint32_t, 256> t{};
    for (std::uint32_t n = 0; n < 256; ++n) {
      std::uint32_t c = n;
      for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
      t[n] = c;
    }
    return t;
  }();
  std::uint32_t c = ~start;
  for (std::size_t i = 0; i < size; ++i) c = table[(c ^ data[i]) & 0xff] ^ (c >> 8);
  return ~c;
}

std::vector<std::uint8_t> encode_png(const RgbaImage& img) {
  const bool alpha = !is_opaque(img);
  const int channels = alpha ? 4 : 3;
  const std::size_t stride = static_cast<std::size_t>(img.width) * channels;
  std::vector<std::uint8_t> rows(static_cast<std::size_t>(img.height) * (stride + 1));
  std::vector<std::uint8_t> line(stride), above(stride, 0), best(stride), trial(stride);
  for (int y = 0; y < img.height; ++y) {
    for (int x = 0; x < img.width; ++x)
      std::memcpy(&line[static_cast<std::size_t>(x) * channels], &img.pixels[(static_cast<std::size_t>(y) * img.width + x) * 4],
                  channels);
    // Pick the filter whose output has the smallest sum of absolute values.
    long best_score = -1;
    int best_filter = 0;
    for (int f = 0; f < 5; ++f) {
      long score = 0;
      for (std::size_t k = 0; k < stride; ++k) {
        int a = k >= static_cast<std::size_t>(channels) ? line[k - channels] : 0;
        int b = above[k];
        int c = k >= static_cast<std::size_t>(channels) ? above[k - channels] : 0;
        int pred = f == 0 ? 0 : f == 1 ? a : f == 2 ? b : f == 3 ? (a + b) / 2 : paeth(a, b, c);
        auto v = static_cast<std::uint8_t>(line[k] - pred);
        trial[k] = v;
        score += v < 128 ? v : 256 - v;
      }
      if (best_score < 0 || score < best_score) {
        best_score = score;
        best_filter = f;
        best.swap(trial);
      }
    }
    std::uint8_t* row = &rows[static_cast<std::size_t>(y) * (stride + 1)];
    row[0] = static_cast<std::uint8_t>(best_filter);
    std::memcpy(row + 1, best.data(), stride);
    above.swap(line);
  }
  std::vector<std::uint8_t> out = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
  std::vector<std::uint8_t> ihdr;
  put_be32(ihdr, static_cast<std::uint32_t>(img.width));
  put_be32(ihdr, static_cast<std::uint32_t>(img.height));
  ihdr.insert(ihdr.end(), {8, static_cast<std::uint8_t>(alpha ? 6 : 2), 0, 0, 0});
  put_chunk(out, "IHDR", ihdr);
  put_chunk(out, "IDAT", zlib_compress(rows.data(), rows.size()));
  put_chunk(out, "IEND", {});
  return out;
}

RgbaImage pad_wrapped(const RgbaImage& src, int pad, bool wrap_y) {
  RgbaImage out;
  const int py = wrap_y ? pad : 0;
  out.width = src.width + 2 * pad;
  out.height = src.height + 2 * py;
  out.pixels.resize(static_cast<std::size_t>(out.width) * out.height * 4);
  auto wrap = [](int v, int n) { return ((v % n) + n) % n; };
  for (int y = 0; y < out.height; ++y) {
    int sy = wrap(y - py, src.height);
    for (int x = 0; x < out.width; ++x) {
      int sx = wrap(x - pad, src.width);
      std::memcpy(&out.pixels[(static_cast<std::size_t>(y) * out.width + x) * 4],
                  &src.pixels[(static_cast<std::size_t>(sy) * src.width + sx) * 4], 4);
    }
  }
  return out;
}

void bleed_transparent(RgbaImage& img, int passes) {
  const int w = img.width, h = img.height;
  std::vector<std::uint8_t> filled(static_cast<std::size_t>(w) * h);
  for (std::size_t i = 0; i < filled.size(); ++i) filled[i] = img.pixels[i * 4 + 3] != 0;
  for (int pass = 0; pass < passes; ++pass) {
    std::vector<std::uint8_t> next = filled;
    bool changed = false;
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        std::size_t i = static_cast<std::size_t>(y) * w + x;
        if (filled[i]) continue;
        int sum[3] = {0, 0, 0}, n = 0;
        for (int dy = -1; dy <= 1; ++dy) {
          for (int dx = -1; dx <= 1; ++dx) {
            int nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            std::size_t j = static_cast<std::size_t>(ny) * w + nx;
            if (!filled[j]) continue;
            for (int c = 0; c < 3; ++c) sum[c] += img.pixels[j * 4 + c];
            ++n;
          }
        }
        if (n == 0) continue;
        for (int c = 0; c < 3; ++c) img.pixels[i * 4 + c] = static_cast<std::uint8_t>(sum[c] / n);
        next[i] = 1;
        changed = true;
      }
    }
    filled.swap(next);
    if (!changed) break;
  }
}

}  // namespace olcore
