// Dependency-free deflate decoder written from RFC 1950 and RFC 1951, so
// olcore builds the same way on every platform (and later for wasm) without
// pulling in zlib.
#include "olcore/inflate.hpp"

#include <array>
#include <string>

namespace olcore {

namespace {

constexpr int kMaxBits = 15;
constexpr int kFastBits = 10;  // codes up to this length decode with one table lookup

// Canonical Huffman table. Short codes resolve through `fast`; longer ones fall
// back to the count/symbol walk from RFC 1951 section 3.2.2.
struct Huffman {
  std::array<std::uint16_t, kMaxBits + 1> count{};
  std::array<std::uint16_t, 288> symbol{};
  // entry = symbol << 4 | length, or 0 when the code is longer than kFastBits
  std::array<std::uint16_t, 1 << kFastBits> fast{};

  void build(const std::uint8_t* lengths, int n) {
    count.fill(0);
    fast.fill(0);
    for (int i = 0; i < n; ++i) ++count[lengths[i]];
    count[0] = 0;
    int left = 1;
    for (int len = 1; len <= kMaxBits; ++len) {
      left = (left << 1) - count[len];
      if (left < 0) throw InflateError("over-subscribed Huffman code");
    }
    std::array<std::uint16_t, kMaxBits + 2> offs{};
    for (int len = 1; len <= kMaxBits; ++len) offs[len + 1] = static_cast<std::uint16_t>(offs[len] + count[len]);
    for (int i = 0; i < n; ++i) {
      if (lengths[i]) symbol[offs[lengths[i]]++] = static_cast<std::uint16_t>(i);
    }
    // Fill the fast table. Deflate sends codes MSB first but the bit reader
    // yields LSB first, so index the table by the bit-reversed code.
    int code = 0, idx = 0;
    for (int len = 1; len <= kFastBits; ++len) {
      for (int k = 0; k < count[len]; ++k, ++idx, ++code) {
        int rev = 0;
        for (int b = 0; b < len; ++b) rev |= ((code >> b) & 1) << (len - 1 - b);
        auto entry = static_cast<std::uint16_t>(symbol[idx] << 4 | len);
        for (int fill = rev; fill < (1 << kFastBits); fill += 1 << len) fast[fill] = entry;
      }
      code <<= 1;
    }
  }
};

class Inflater {
public:
  Inflater(const std::uint8_t* data, std::size_t size) : in_(data), size_(size) {}

  std::vector<std::uint8_t> run() {
    bool last = false;
    while (!last) {
      last = bits(1);
      switch (bits(2)) {
        case 0: stored(); break;
        case 1: fixed(); break;
        case 2: dynamic(); break;
        default: throw InflateError("invalid deflate block type");
      }
    }
    return std::move(out_);
  }

  // Bytes of input used so far, counting a partly used byte as used.
  std::size_t consumed() const { return pos_ - static_cast<std::size_t>(nbits_ / 8); }

private:
  void need(int n) {
    while (nbits_ < n) {
      if (pos_ >= size_) throw InflateError("deflate stream truncated");
      buf_ |= static_cast<std::uint64_t>(in_[pos_++]) << nbits_;
      nbits_ += 8;
    }
  }

  // Like need(), but stops quietly at end of input; used by the fast path,
  // which may look ahead past the last code.
  void fill(int n) {
    while (nbits_ < n && pos_ < size_) {
      buf_ |= static_cast<std::uint64_t>(in_[pos_++]) << nbits_;
      nbits_ += 8;
    }
  }

  std::uint32_t bits(int n) {
    need(n);
    auto v = static_cast<std::uint32_t>(buf_ & ((1ull << n) - 1));
    buf_ >>= n;
    nbits_ -= n;
    return v;
  }

  int decode(const Huffman& h) {
    fill(kFastBits);
    std::uint16_t e = h.fast[buf_ & ((1u << kFastBits) - 1)];
    if (e && (e & 15) <= nbits_) {
      buf_ >>= (e & 15);
      nbits_ -= (e & 15);
      return e >> 4;
    }
    int code = 0, first = 0, index = 0;
    for (int len = 1; len <= kMaxBits; ++len) {
      code |= static_cast<int>(bits(1));
      int count = h.count[len];
      if (code - count < first) return h.symbol[index + (code - first)];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw InflateError("invalid Huffman code");
  }

  void stored() {
    buf_ >>= (nbits_ & 7);
    nbits_ -= (nbits_ & 7);
    std::uint32_t len = bits(16);
    std::uint32_t nlen = bits(16);
    if ((len ^ 0xffffu) != nlen) throw InflateError("stored block length check failed");
    // The bit buffer is byte-aligned here; drain it before copying directly.
    while (len && nbits_) {
      out_.push_back(static_cast<std::uint8_t>(bits(8)));
      --len;
    }
    if (len > size_ - pos_) throw InflateError("deflate stream truncated");
    out_.insert(out_.end(), in_ + pos_, in_ + pos_ + len);
    pos_ += len;
  }

  void codes(const Huffman& lit, const Huffman& dist) {
    static constexpr std::uint16_t kLenBase[29] = {3,  4,  5,  6,  7,  8,  9,  10, 11,  13,  15,  17,  19,  23, 27,
                                                   31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
    static constexpr std::uint8_t kLenExtra[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2,
                                                   2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
    static constexpr std::uint16_t kDistBase[30] = {1,    2,    3,    4,    5,    7,     9,     13,    17,  25,
                                                    33,   49,   65,   97,   129,  193,   257,   385,   513, 769,
                                                    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
    static constexpr std::uint8_t kDistExtra[30] = {0, 0, 0, 0, 1, 1, 2, 2,  3,  3,  4,  4,  5,  5,  6,
                                                    6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};
    for (;;) {
      int sym = decode(lit);
      if (sym < 256) {
        out_.push_back(static_cast<std::uint8_t>(sym));
      } else if (sym == 256) {
        return;
      } else {
        sym -= 257;
        if (sym >= 29) throw InflateError("invalid length symbol");
        std::size_t len = kLenBase[sym] + bits(kLenExtra[sym]);
        int dsym = decode(dist);
        if (dsym >= 30) throw InflateError("invalid distance symbol");
        std::size_t d = kDistBase[dsym] + bits(kDistExtra[dsym]);
        if (d > out_.size()) throw InflateError("distance too far back");
        std::size_t from = out_.size() - d;
        for (std::size_t i = 0; i < len; ++i) out_.push_back(out_[from + i]);
      }
    }
  }

  void fixed() {
    static const auto tables = [] {
      std::pair<Huffman, Huffman> t;
      std::uint8_t lengths[288];
      int i = 0;
      for (; i < 144; ++i) lengths[i] = 8;
      for (; i < 256; ++i) lengths[i] = 9;
      for (; i < 280; ++i) lengths[i] = 7;
      for (; i < 288; ++i) lengths[i] = 8;
      t.first.build(lengths, 288);
      for (i = 0; i < 30; ++i) lengths[i] = 5;
      t.second.build(lengths, 30);
      return t;
    }();
    codes(tables.first, tables.second);
  }

  void dynamic() {
    static constexpr std::uint8_t kOrder[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
    int nlen = static_cast<int>(bits(5)) + 257;
    int ndist = static_cast<int>(bits(5)) + 1;
    int ncode = static_cast<int>(bits(4)) + 4;
    if (nlen > 286 || ndist > 30) throw InflateError("bad dynamic block counts");
    std::uint8_t lengths[320] = {};
    for (int i = 0; i < ncode; ++i) lengths[kOrder[i]] = static_cast<std::uint8_t>(bits(3));
    Huffman lencode;
    lencode.build(lengths, 19);
    int i = 0;
    while (i < nlen + ndist) {
      int sym = decode(lencode);
      if (sym < 16) {
        lengths[i++] = static_cast<std::uint8_t>(sym);
        continue;
      }
      std::uint8_t value = 0;
      int repeat;
      if (sym == 16) {
        if (i == 0) throw InflateError("repeat with no previous length");
        value = lengths[i - 1];
        repeat = 3 + static_cast<int>(bits(2));
      } else if (sym == 17) {
        repeat = 3 + static_cast<int>(bits(3));
      } else {
        repeat = 11 + static_cast<int>(bits(7));
      }
      if (i + repeat > nlen + ndist) throw InflateError("too many code lengths");
      while (repeat--) lengths[i++] = value;
    }
    if (lengths[256] == 0) throw InflateError("no end-of-block code");
    Huffman lit, dist;
    lit.build(lengths, nlen);
    dist.build(lengths + nlen, ndist);
    codes(lit, dist);
  }

  const std::uint8_t* in_;
  std::size_t size_;
  std::size_t pos_ = 0;
  std::uint64_t buf_ = 0;
  int nbits_ = 0;
  std::vector<std::uint8_t> out_;
};

}  // namespace

std::vector<std::uint8_t> inflate_raw(const std::uint8_t* data, std::size_t size, std::size_t* consumed) {
  Inflater inf(data, size);
  auto out = inf.run();
  if (consumed) *consumed = inf.consumed();
  return out;
}

std::vector<std::uint8_t> zlib_decompress(const std::uint8_t* data, std::size_t size, std::size_t* consumed) {
  if (size < 6) throw InflateError("zlib stream too short");
  unsigned cmf = data[0], flg = data[1];
  if ((cmf & 0x0f) != 8 || (cmf >> 4) > 7 || ((cmf << 8) | flg) % 31 != 0) {
    throw InflateError("not a zlib stream");
  }
  if (flg & 0x20) throw InflateError("zlib preset dictionary not supported");
  std::size_t used = 0;
  auto out = inflate_raw(data + 2, size - 2, &used);
  std::size_t trailer = 2 + used;
  if (trailer + 4 > size) throw InflateError("zlib trailer truncated");
  std::uint32_t want = static_cast<std::uint32_t>(data[trailer]) << 24 | static_cast<std::uint32_t>(data[trailer + 1]) << 16 |
                       static_cast<std::uint32_t>(data[trailer + 2]) << 8 | data[trailer + 3];
  if (adler32(out.data(), out.size()) != want) throw InflateError("zlib Adler-32 mismatch");
  if (consumed) *consumed = trailer + 4;
  return out;
}

std::uint32_t adler32(const std::uint8_t* data, std::size_t size, std::uint32_t start) {
  std::uint32_t a = start & 0xffff, b = start >> 16;
  while (size) {
    std::size_t n = size < 5552 ? size : 5552;  // largest run before b can overflow
    size -= n;
    while (n--) {
      a += *data++;
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return b << 16 | a;
}

}  // namespace olcore
