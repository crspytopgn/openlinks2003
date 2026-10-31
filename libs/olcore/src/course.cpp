#include "olcore/course.hpp"

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr std::uint32_t kHeaderVersion = 15;
constexpr std::uint32_t kTerrainVersion = 6;
constexpr std::uint32_t kMaterialsVersion = 4;
constexpr std::uint32_t kTerrainTypesVersion = 4;
constexpr std::size_t kTerrainTypeSize = 243;
constexpr std::size_t kGroundClassOffset = 0x54;
constexpr std::size_t kTeesPerHole = 5;
constexpr std::size_t kPinsPerHole = 18;
constexpr std::size_t kAimPointsPerHole = 5;
constexpr std::size_t kMaterialSlots = 12;

CourseVec3 vec3(BinaryReader& r) {
  CourseVec3 v;
  v.x = r.f32();
  v.y = r.f32();
  v.z = r.f32();
  return v;
}

bool is_zero(const CourseVec3& v) { return v.x == 0 && v.y == 0 && v.z == 0; }

void append_utf8(std::string& out, std::uint32_t c) {
  if (c < 0x80) {
    out += char(c);
  } else if (c < 0x800) {
    out += char(0xc0 | (c >> 6));
    out += char(0x80 | (c & 0x3f));
  } else {
    out += char(0xe0 | (c >> 12));
    out += char(0x80 | ((c >> 6) & 0x3f));
    out += char(0x80 | (c & 0x3f));
  }
}

std::string trim(const std::string& s) {
  std::size_t a = s.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return {};
  std::size_t b = s.find_last_not_of(" \t\r\n");
  return s.substr(a, b - a + 1);
}

}  // namespace

std::vector<Hole> parse_holes(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  r.i32();  // always -1
  std::uint32_t version = r.u32();
  if (version != kHeaderVersion) throw ReadError("course header version " + std::to_string(version) + " is not supported");
  r.skip(10);
  std::uint32_t count = r.u32();
  if (count > 18) throw ReadError("course header has " + std::to_string(count) + " holes");
  std::vector<Hole> holes(count);
  for (Hole& h : holes) {
    h.par = r.u32();
    h.handicap = r.u32();
    h.ladies_par = r.u32();
    h.ladies_handicap = r.u32();
    for (std::size_t i = 0; i < kTeesPerHole; ++i) {
      Tee t;
      t.position = vec3(r);
      t.heading = r.f32();
      t.yards = r.u32();
      t.mask = r.u32();
      if (t.mask != 0) h.tees.push_back(t);
    }
    for (std::size_t i = 0; i < kPinsPerHole; ++i) {
      Pin p;
      p.position = vec3(r);
      p.group = r.u32();
      if (!is_zero(p.position)) h.pins.push_back(p);
    }
    r.u32();  // pin count (always 18)
    r.u32();  // aim point count (always 5)
    for (std::size_t i = 0; i < kAimPointsPerHole; ++i) {
      CourseVec3 v = vec3(r);
      if (!is_zero(v)) h.aim_path.push_back(v);
    }
    h.green = vec3(r);
    r.skip(6);  // flags, not decoded
  }
  return holes;
}

CourseScenery parse_course_scenery(const std::vector<std::uint8_t>& data) {
  constexpr std::size_t kHoleBytes = 16 + kTeesPerHole * 24 + kPinsPerHole * 16 + 8 + kAimPointsPerHole * 12 + 12 + 6;
  constexpr std::uint32_t kOwnPanorama = 0x80000000u;
  BinaryReader r(data);
  r.i32();
  std::uint32_t version = r.u32();
  if (version != kHeaderVersion) throw ReadError("course header version " + std::to_string(version) + " is not supported");
  r.skip(10);
  std::uint32_t count = r.u32();
  if (count > 18) throw ReadError("course header has " + std::to_string(count) + " holes");
  r.skip(count * kHoleBytes);
  std::uint32_t records = r.u32();  // 12 bytes each, not decoded (5 on every disc course)
  if (records > 64) throw ReadError("course header trailer has " + std::to_string(records) + " records");
  r.skip(records * 12);
  r.skip(16);  // four u32 the game lets the player's settings override; zero on the disc courses
  CourseScenery s;
  s.sky = r.u32();
  r.skip(8);
  for (float& v : s.values) v = r.f32();
  r.u32();  // only in header versions above 7
  std::uint32_t pan = r.u32();
  s.panorama = pan == kOwnPanorama || pan > 13 ? 0 : pan;
  if (s.sky > 12) s.sky = 0;
  return s;
}

std::vector<std::pair<std::string, std::string>> parse_course_text(const std::vector<std::uint8_t>& data) {
  std::string text;
  std::size_t i = 0;
  if (data.size() >= 2 && data[0] == 0xff && data[1] == 0xfe) i = 2;
  for (; i + 1 < data.size(); i += 2) {
    std::uint32_t c = std::uint32_t(data[i]) | std::uint32_t(data[i + 1]) << 8;
    if (c == 0) break;
    append_utf8(text, c);
  }
  std::vector<std::pair<std::string, std::string>> out;
  std::size_t start = 0;
  while (start < text.size()) {
    std::size_t end = text.find('\n', start);
    if (end == std::string::npos) end = text.size();
    std::string line = text.substr(start, end - start);
    std::size_t eq = line.find('=');
    if (eq != std::string::npos) out.emplace_back(trim(line.substr(0, eq)), trim(line.substr(eq + 1)));
    start = end + 1;
  }
  return out;
}

Terrain parse_terrain(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kTerrainVersion) throw ReadError("terrain version " + std::to_string(version) + " is not supported");
  Terrain t;
  std::uint32_t nv = r.u32();
  if (nv > r.remaining() / 24) throw ReadError("terrain vertex count runs past end of entry");
  t.vertices.resize(nv);
  for (TerrainVertex& v : t.vertices) {
    v.position = vec3(r);
    v.unknown[0] = r.f32();
    v.unknown[1] = r.f32();
    v.unknown_a = r.u16();
    v.flags = r.u16();
  }
  std::uint32_t nt = r.u32();
  if (nt > r.remaining() / 26) throw ReadError("terrain triangle count runs past end of entry");
  t.triangles.resize(nt);
  // Two arrays: all the neighbour triples, then all the triangle records.
  for (TerrainTriangle& tri : t.triangles) {
    for (auto& n : tri.neighbour) {
      std::uint32_t raw = r.u32();
      // Bits 26-27 give the edge of the neighbour that is shared; bit 30
      // marks a border edge. The low 20 bits are the triangle index.
      n = (raw >> 30) & 1 ? kNoNeighbour : (raw & 0xfffff);
    }
  }
  // Vertex indices are u16, or u32 once there are too many vertices for that.
  const bool wide = nv > 0xffff;
  if (nt > r.remaining() / (wide ? 20 : 14)) throw ReadError("terrain triangles run past end of entry");
  for (TerrainTriangle& tri : t.triangles) {
    tri.material = r.u16();
    tri.mapping = r.u32();
    tri.unknown = r.u16();
    for (auto& v : tri.v) {
      v = wide ? r.u32() : r.u16();
      if (v >= nv) throw ReadError("terrain triangle refers to a missing vertex");
    }
  }
  if (r.remaining() != 0) throw ReadError("terrain entry has unexpected trailing data");
  return t;
}

std::vector<TextureDesc> parse_texture_list(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t count = r.u32();
  if (count > r.remaining() / 64) throw ReadError("texture list runs past end of entry");
  std::vector<TextureDesc> out(count);
  for (TextureDesc& t : out) {
    t.name = r.fixed_string(32);
    t.width = r.u32();
    t.height = r.u32();
    r.skip(24);
  }
  return out;
}

std::vector<TerrainMaterial> parse_materials(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kMaterialsVersion) throw ReadError("materials version " + std::to_string(version) + " is not supported");
  std::uint32_t count = r.u32();
  if (count > r.remaining() / 64) throw ReadError("materials table runs past end of entry");
  std::vector<TerrainMaterial> out(count);
  for (TerrainMaterial& m : out) {
    m.mode = r.u32();
    m.layer_count = r.u32();
    for (std::size_t i = 0; i < kMaterialSlots; ++i) {
      std::int32_t tex = r.i32();
      if (tex >= 0) m.textures.push_back(tex);
    }
    m.kind = r.u32();
    r.u32();  // always 0
  }
  return out;
}

std::vector<std::uint8_t> parse_ground_classes(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kTerrainTypesVersion) {
    throw ReadError("terrain types version " + std::to_string(version) + " is not supported");
  }
  std::uint32_t count = r.u32();
  if (count > r.remaining() / kTerrainTypeSize) throw ReadError("terrain types run past end of entry");
  std::vector<std::uint8_t> out(count);
  for (std::uint32_t i = 0; i < count; ++i) out[i] = data[8 + i * kTerrainTypeSize + kGroundClassOffset];
  return out;
}

Course load_course(const CrzArchive& archive) {
  Course c;
  const auto header = archive.read("header");
  c.holes = parse_holes(header);
  try {
    c.scenery = parse_course_scenery(header);
  } catch (const ReadError&) {
    // An older or shorter header: keep the defaults.
  }
  for (auto& [key, value] : parse_course_text(archive.read("english.txt"))) {
    if (key == "CourseName") c.name = value;
    for (std::size_t i = 0; i < c.holes.size(); ++i) {
      if (key == "HoleName" + std::to_string(i + 1)) c.holes[i].name = value;
    }
  }
  c.terrain = parse_terrain(archive.read("vertex"));
  c.textures = parse_texture_list(archive.read("txtrdesc"));
  c.materials = parse_materials(archive.read("Materials"));
  return c;
}

}  // namespace olcore
