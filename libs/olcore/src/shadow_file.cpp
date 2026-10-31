#include "olcore/shadow_file.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr char kMagic[] = "VER5JDHSHADOW";  // 13 characters and a NUL
constexpr std::size_t kNameOffset = 14;
constexpr std::size_t kNameSize = 256;
constexpr std::uint32_t kMaxShapeSide = 4096;

ShadowShape read_shape(BinaryReader& r) {
  ShadowShape s;
  s.width = r.u32();
  s.height = r.u32();
  if (s.width > kMaxShapeSide || s.height > kMaxShapeSide) throw ReadError("shadow shape is too large");
  s.pixels = r.bytes(std::size_t(s.width) * s.height);
  return s;
}

// `count` u32 list lengths, then the lists of u32 byte offsets into a
// table of 8-byte entries.
ShadowCells read_cells(BinaryReader& r, std::uint32_t count) {
  ShadowCells c;
  c.start.reserve(std::size_t(count) + 1);
  c.start.push_back(0);
  std::size_t total = 0;
  for (std::uint32_t i = 0; i < count; ++i) {
    total += r.u32();
    if (total > r.remaining() / 4) throw ReadError("shadow file is shorter than its cell lists");
    c.start.push_back(std::uint32_t(total));
  }
  c.cells.resize(total);
  for (auto& cell : c.cells) cell = r.u32() / 8;
  return c;
}

}  // namespace

ShadowFile parse_shadow_file(const std::vector<std::uint8_t>& d) {
  if (d.size() < kNameOffset + kNameSize || std::memcmp(d.data(), kMagic, sizeof kMagic) != 0) {
    throw ReadError("not a Links 2003 shadow file");
  }
  ShadowFile f;
  BinaryReader r(d);
  r.seek(kNameOffset);
  f.course = r.fixed_string(kNameSize);
  f.course_size = r.u32();
  f.file_time = r.u32();
  f.file_time |= std::uint64_t(r.u32()) << 32;
  f.stamp = r.u32();
  f.model_count = r.u32();
  f.billboard_type_count = r.u32();
  f.model_placement_count = r.u32();
  f.billboard_count = r.u32();
  if (f.billboard_count > r.remaining() / 8 || f.model_placement_count > r.remaining() / 4) {
    throw ReadError("shadow file is shorter than its counts");
  }
  for (std::uint32_t i = 0; i < f.model_count; ++i) f.object_shapes.push_back(read_shape(r));
  f.placement_cells = read_cells(r, f.model_placement_count);
  f.billboard_light.resize(f.billboard_count);
  for (float& v : f.billboard_light) v = r.f32();
  for (std::uint32_t i = 0; i < f.billboard_type_count; ++i) f.shapes.push_back(read_shape(r));
  f.billboard_cells = read_cells(r, f.billboard_count);
  if (r.remaining() != 0) throw ReadError("shadow file has bytes after its last section");
  return f;
}

}  // namespace olcore
