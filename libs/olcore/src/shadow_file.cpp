#include "olcore/shadow_file.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr char kMagic[] = "VER5JDHSHADOW";  // 13 characters and a NUL
constexpr std::size_t kNameOffset = 14;
constexpr std::size_t kNameSize = 256;
constexpr std::size_t kCountsOffset = 0x11e;
constexpr std::size_t kHeaderSize = 0x136;

std::uint32_t u32_at(const std::vector<std::uint8_t>& d, std::size_t o) {
  return std::uint32_t(d[o]) | std::uint32_t(d[o + 1]) << 8 | std::uint32_t(d[o + 2]) << 16 |
         std::uint32_t(d[o + 3]) << 24;
}

bool shape_size(std::uint32_t w) { return w == 32 || w == 64 || w == 128 || w == 256; }

// Walks up to `limit` shape records from `at`; returns how many are valid.
std::uint32_t walk(const std::vector<std::uint8_t>& d, std::size_t at, std::uint32_t limit) {
  std::uint32_t n = 0;
  while (n < limit && at + 8 <= d.size()) {
    std::uint32_t w = u32_at(d, at), h = u32_at(d, at + 4);
    if (w != h || (w != 0 && !shape_size(w))) break;
    if (at + 8 + std::size_t(w) * h > d.size()) break;
    at += 8 + std::size_t(w) * h;
    ++n;
  }
  return n;
}

}  // namespace

ShadowFile parse_shadow_file(const std::vector<std::uint8_t>& d) {
  if (d.size() < kHeaderSize || std::memcmp(d.data(), kMagic, sizeof kMagic) != 0) {
    throw ReadError("not a Links 2003 shadow file");
  }
  ShadowFile f;
  BinaryReader r(d);
  r.seek(kNameOffset);
  f.course = r.fixed_string(kNameSize);
  f.course_size = r.u32();
  r.seek(kCountsOffset);
  f.model_count = r.u32();
  f.billboard_type_count = r.u32();
  f.model_placement_count = r.u32();
  f.billboard_count = r.u32();
  f.light_map_width = r.u32();
  f.light_map_height = r.u32();
  const std::uint32_t types = f.billboard_type_count;
  // One light map per model, then sections not decoded yet (per-placement
  // lists and one shade value per billboard), then the shapes. Their start
  // isn't stored: it is the first run of `types` valid shape records, where
  // types without a shadow (0 x 0) may come first.
  std::size_t at = kHeaderSize + std::size_t(f.model_count) * f.light_map_width * f.light_map_height;
  if (types == 0 || at > d.size()) throw ReadError("shadow file is shorter than its light maps");
  std::size_t start = d.size();
  for (; at + 8 <= d.size(); at += 4) {
    std::uint32_t w = u32_at(d, at);
    if (!shape_size(w) || u32_at(d, at + 4) != w) continue;
    std::uint32_t run = walk(d, at, types);
    std::size_t empty = types - run;  // 0 x 0 records that must come before
    if (at < kHeaderSize + empty * 8) continue;
    bool zeros = true;
    for (std::size_t i = at - empty * 8; i < at && zeros; ++i) zeros = d[i] == 0;
    if (zeros) {
      start = at - empty * 8;
      break;
    }
  }
  if (start == d.size()) throw ReadError("shadow file has no tree shadow shapes");
  r.seek(start);
  f.shapes.resize(types);
  for (ShadowShape& s : f.shapes) {
    s.width = r.u32();
    s.height = r.u32();
    s.pixels = r.bytes(std::size_t(s.width) * s.height);
  }
  return f;
}

}  // namespace olcore
