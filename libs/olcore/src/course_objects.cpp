#include "olcore/course_objects.hpp"

#include <algorithm>
#include <cmath>
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
    // The collision record: a u32 and six floats.
    const std::uint32_t phys = u32_at(data, rec + 0x14);
    if (phys != 0 && std::size_t(phys) + 28 <= data.size()) {
      t.collision = u32_at(data, phys);
      for (std::size_t i = 0; i < 6; ++i) {
        std::uint32_t v = u32_at(data, phys + 4 + 4 * i);
        std::memcpy(&t.shape[i], &v, 4);
      }
    }
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

std::vector<CrowdPlacement> parse_crowd_placements(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  if (r.size() < 0x40) throw ReadError("TrnyPlant: too short");
  r.seek(4);
  const std::uint32_t count = r.u32();
  r.seek(0x40);
  std::vector<CrowdPlacement> out;
  out.reserve(count);
  float cx = 0, cy = 0, cz = 0;
  bool have_cell = false;
  while (r.remaining() > 0) {
    const std::uint8_t kind = r.u8();
    if (kind == 0xff) {
      cx = r.f32();
      cy = r.f32();
      cz = r.f32();
      have_cell = true;
      continue;
    }
    if (!have_cell) throw ReadError("TrnyPlant: placement before the first cell");
    CrowdPlacement p;
    p.kind = kind;
    const std::uint32_t word = r.u32();
    p.instance = word & 0x1fffffff;
    if (word & 0x20000000) p.extra_byte = r.u8();
    if (word & 0x40000000) p.extra_word = r.u16();
    const std::uint16_t x = r.u16();
    const std::uint16_t y = r.u16();
    const std::int16_t z = r.i16();
    p.position = {cx + x * kPlacementUnit, cy + y * kPlacementUnit, cz + z * kPlacementUnit};
    out.push_back(p);
  }
  if (out.size() != count) throw ReadError("TrnyPlant: placement count does not match the header");
  return out;
}

std::vector<CourseModel> parse_course_models(const std::vector<std::uint8_t>& data) {
  // Header: u32 size, u32 0x70 (where the meshes start), u32 count. Each
  // mesh is followed by u32 index, u32 id and u32 kind.
  const std::uint32_t start = u32_at(data, 4);
  const std::uint32_t count = u32_at(data, 8);
  if (count > 10000) throw ReadError("MasterObj3D: implausible model count");
  std::vector<CourseModel> out;
  std::size_t p = start;
  for (std::uint32_t k = 0; k < count; ++k) {
    const std::uint32_t size = u32_at(data, p);
    if (size < 0x44 || p + size + 12 > data.size()) throw ReadError("MasterObj3D: model runs past the end");
    CourseModel m;
    m.model = read_model(std::vector<std::uint8_t>(data.begin() + std::ptrdiff_t(p), data.begin() + std::ptrdiff_t(p + size)));
    p += size;
    if (u32_at(data, p) != k) throw ReadError("MasterObj3D: model index out of sequence");
    m.id = u32_at(data, p + 4);
    m.kind = u32_at(data, p + 8);
    p += 12;
    out.push_back(std::move(m));
  }
  return out;
}

std::vector<ModelPlacement> parse_model_placements(const std::vector<std::uint8_t>& data) {
  constexpr std::size_t kRecord = 88;
  if (data.size() % kRecord != 0) throw ReadError("3DPlant: size is not a whole number of records");
  BinaryReader r(data);
  std::vector<ModelPlacement> out(data.size() / kRecord);
  for (auto& p : out) {
    p.instance = r.u32();
    p.model = r.u32();
    for (CourseVec3* v : {&p.position, &p.box_max, &p.box_min}) *v = {r.f32(), r.f32(), r.f32()};
    r.f32();  // always 0.5
    p.z_offset = r.f32();
    for (float& f : p.axis) f = r.f32();
    p.flag = p.axis[2];
    for (float& f : p.scale) f = r.f32();
    p.yaw = r.f32();
    p.pitch = r.f32();
    r.f32();
  }
  return out;
}

ModelTransform model_transform(const ModelPlacement& p) {
  // A turn by yaw about the axis as given (Rodrigues' formula for a unit
  // axis; the game does not normalise it), then the rows made orthonormal.
  const double ax = p.axis[0], ay = p.axis[1], az = p.axis[2];
  const double s = std::sin(double(p.yaw)), c = std::cos(double(p.yaw)), k = 1 - c;
  ModelTransform t;
  auto& r = t.rows;
  r[0] = {ax * ax * k + c, ax * ay * k - az * s, ax * az * k + ay * s};
  r[1] = {ax * ay * k + az * s, ay * ay * k + c, ay * az * k - ax * s};
  r[2] = {ax * az * k - ay * s, ay * az * k + ax * s, az * az * k + c};
  auto dot3 = [](const std::array<double, 3>& a, const std::array<double, 3>& b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  };
  auto normalise = [&](std::array<double, 3>& a) {
    double n = std::sqrt(dot3(a, a));
    if (n != 0) {
      for (double& x : a) x /= n;
    }
  };
  normalise(r[0]);
  double d = dot3(r[1], r[0]);
  for (int i = 0; i < 3; ++i) r[1][i] -= d * r[0][i];
  normalise(r[1]);
  double d0 = dot3(r[2], r[0]), d1 = dot3(r[2], r[1]);
  for (int i = 0; i < 3; ++i) r[2][i] -= d0 * r[0][i] + d1 * r[1][i];
  normalise(r[2]);
  t.origin = p.position;
  return t;
}

CourseVec3 place_point(const ModelTransform& t, const ModelPlacement& p, const std::array<float, 3>& v) {
  const double x = double(p.scale[0]) * v[0];
  const double y = double(p.scale[1]) * v[1];
  const double z = double(p.scale[2]) * (double(v[2]) + p.z_offset) + double(p.pitch) * x;
  const auto& r = t.rows;
  return {float(t.origin.x + x * r[0][0] + y * r[1][0] + z * r[2][0]),
          float(t.origin.y + x * r[0][1] + y * r[1][1] + z * r[2][1]),
          float(t.origin.z + x * r[0][2] + y * r[1][2] + z * r[2][2])};
}

CourseVec3 place_point(const ModelPlacement& p, const std::array<float, 3>& v) {
  return place_point(model_transform(p), p, v);
}

std::vector<ModelTextureRefs> parse_object_textures(const std::vector<std::uint8_t>& data) {
  // Header: u32 size, u32 model count, u32 12; then per model five u32:
  // bytes of level indices, texture count, offsets of the level records
  // (64 bytes: name[32], width, height, ...), the per-texture level lists
  // and a third table not needed here.
  const std::uint32_t count = u32_at(data, 4);
  if (count > 10000) throw ReadError("t3l: implausible model count");
  std::vector<ModelTextureRefs> out(count);
  for (std::uint32_t k = 0; k < count; ++k) {
    const std::size_t rec = 12 + 20 * std::size_t(k);
    const std::uint32_t textures = u32_at(data, rec + 4);
    const std::uint32_t levels = u32_at(data, rec + 8);
    std::size_t list = u32_at(data, rec + 12);
    if (textures > 4096) throw ReadError("t3l: implausible texture count");
    // Only the first level record carries a name: the model's `.maq`. The
    // name fields of the others hold leftover memory.
    if (levels + 32 > data.size()) throw ReadError("t3l: level record out of range");
    auto name = data.begin() + std::ptrdiff_t(levels);
    const std::string maq(name, std::find(name, name + 32, 0));
    for (std::uint32_t t = 0; t < textures; ++t) {
      const std::uint32_t n = u32_at(data, list);
      const std::uint32_t level = n ? u32_at(data, list + 8) : 0;
      out[k].maq.push_back(maq);
      out[k].level.push_back(level);
      const std::size_t flags = levels + 64 * std::size_t(level) + 0x28;
      out[k].see_through.push_back(flags + 4 <= data.size() && (u32_at(data, flags) & 0x80000000u) != 0);
      list += 8 + 4 * std::size_t(n);
    }
  }
  return out;
}

std::vector<MaqLevel> read_maq_levels(const std::vector<std::uint8_t>& data) {
  // Header: u32 size, u32 texture count, u32 level count, u32 16; then
  // 36-byte level records: width, height, bits (8), two more sizes, two
  // zeros, palette offset, pixel offset.
  const std::uint32_t count = u32_at(data, 8);
  const std::uint32_t first = u32_at(data, 12);
  if (count > 4096) throw ReadError("maq: implausible level count");
  std::vector<MaqLevel> out(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    const std::size_t e = first + 36 * std::size_t(i);
    MaqLevel& l = out[i];
    l.width = u32_at(data, e);
    l.height = u32_at(data, e + 4);
    if (u32_at(data, e + 8) != 8) throw ReadError("maq: only 8-bit levels are known");
    l.palette = u32_at(data, e + 28);
    l.pixels = u32_at(data, e + 32);
    if (l.width > 4096 || l.height > 4096 || l.palette + 1024 > data.size() ||
        l.pixels + std::size_t(l.width) * l.height > data.size()) {
      throw ReadError("maq: level out of range");
    }
  }
  return out;
}

RgbaImage decode_maq(const std::vector<std::uint8_t>& data, std::size_t level) {
  auto levels = read_maq_levels(data);
  if (level >= levels.size()) throw ReadError("maq: no such level");
  const MaqLevel& l = levels[level];
  RgbaImage img;
  img.width = int(l.width);
  img.height = int(l.height);
  img.pixels.resize(std::size_t(l.width) * l.height * 4);
  for (std::size_t i = 0; i < std::size_t(l.width) * l.height; ++i) {
    const std::uint8_t* c = data.data() + l.palette + 4 * data[l.pixels + i];  // blue, green, red, alpha
    img.pixels[4 * i] = c[2];
    img.pixels[4 * i + 1] = c[1];
    img.pixels[4 * i + 2] = c[0];
    img.pixels[4 * i + 3] = c[3];
  }
  return img;
}

}  // namespace olcore
