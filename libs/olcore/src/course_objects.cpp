#include "olcore/course_objects.hpp"

#include <algorithm>
#include <cstring>
#include <stdexcept>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

std::uint32_t u32_at(const std::vector<std::uint8_t>& d, std::size_t off) {
  if (off + 4 > d.size()) throw ReadError("MasterObj: offset out of range");
  return std::uint32_t(d[off]) | std::uint32_t(d[off + 1]) << 8 | std::uint32_t(d[off + 2]) << 16 |
         std::uint32_t(d[off + 3]) << 24;
}

}  // namespace

std::vector<BillboardType> parse_billboard_types(const std::vector<std::uint8_t>& data) {
  // A saved memory image: offsets inside it are from the start of the entry.
  const std::uint32_t count = u32_at(data, 8);
  const std::uint32_t table = u32_at(data, 12);
  if (count > 100000) throw ReadError("MasterObj: implausible type count");
  std::vector<BillboardType> out;
  out.reserve(count);
  for (std::uint32_t k = 0; k < count; ++k) {
    const std::uint32_t rec = u32_at(data, table + 4 * std::size_t(k));
    BillboardType t;
    t.width = u32_at(data, rec);
    t.height = u32_at(data, rec + 4);
    const std::uint32_t lods = u32_at(data, rec + 8);
    const std::uint32_t lod_list = u32_at(data, rec + 12);
    std::uint32_t bits = u32_at(data, rec + 0x18);
    std::memcpy(&t.aspect, &bits, 4);
    t.id = u32_at(data, rec + 0x34);
    if (lods > 0) {
      // First level: its sprite descriptor, then the sprite's first tile
      // record, which starts with the sprite's file name.
      const std::uint32_t desc = u32_at(data, lod_list + 8);
      const std::uint32_t tiles = u32_at(data, desc + 12);
      if (tiles + 32 > data.size()) throw ReadError("MasterObj: tile record out of range");
      auto name = data.begin() + tiles;
      t.sprite.assign(name, std::find(name, name + 32, 0));
      t.name = t.sprite;
      // "<name>A.btc" -> "<name>"
      if (t.name.size() > 5 && t.name.compare(t.name.size() - 4, 4, ".btc") == 0) t.name.resize(t.name.size() - 5);
    }
    out.push_back(std::move(t));
  }
  return out;
}

std::vector<BillboardPlacement> parse_billboard_placements(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  if (r.size() < 0x40 || std::memcmp(data.data(), "2JBO", 4) != 0) throw ReadError("2DPlant: bad magic");
  r.seek(8);
  const std::uint32_t count = r.u32();
  r.seek(0x40);
  std::vector<BillboardPlacement> out;
  out.reserve(count);
  float cx = 0, cy = 0, cz = 0;
  bool have_cell = false;
  while (r.remaining() > 0) {
    std::uint16_t type = r.u16();
    if (type == 0xffff) {
      // Start of a 64-foot cell: its corner and a base height.
      cx = r.f32();
      cy = r.f32();
      cz = r.f32();
      have_cell = true;
      continue;
    }
    if (!have_cell) throw ReadError("2DPlant: placement before the first cell");
    BillboardPlacement p;
    p.type = type;
    const std::uint32_t word = r.u32();
    p.instance = word & 0x1fffffff;
    if (word & 0x20000000) p.extra_byte = r.u8();
    if (word & 0x40000000) p.extra_word = r.u16();
    const std::uint16_t x = r.u16();
    const std::uint16_t y = r.u16();
    const std::int16_t z = r.i16();
    const std::uint16_t h = r.u16();
    p.position = {cx + x * kPlacementUnit, cy + y * kPlacementUnit, cz + z * kPlacementUnit};
    p.height = h * kPlacementUnit;
    out.push_back(p);
  }
  if (out.size() != count) throw ReadError("2DPlant: placement count does not match the header");
  return out;
}

}  // namespace olcore
