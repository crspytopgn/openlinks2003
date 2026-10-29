#include "olcore/cvt.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"
#include "olcore/strings.hpp"

namespace olcore {

namespace {

constexpr std::uint32_t kConvertedHeaderVersion = 14;
constexpr std::uint32_t kConvertedTerrainVersion = 5;
constexpr std::size_t kShortNameSize = 9;
constexpr std::size_t kTerrainTypeSize = 432;
constexpr std::size_t kTerrainTypeTextures = 3;
constexpr std::size_t kNameChars = 32;  // UTF-16 fields of 64 bytes

// Version 15 (Links 2003) puts an i32 -1, the version and 10 zero bytes
// before the hole count; version 14 puts the version and a 9-byte name.
// Everything after the hole count is the same.
constexpr std::size_t kV15Preamble = 4 + 4 + 10;
constexpr std::size_t kV14Preamble = 4 + kShortNameSize;

std::string utf16_field(BinaryReader& r) {
  std::string out;
  bool ended = false;
  for (std::size_t i = 0; i < kNameChars; ++i) {
    std::uint16_t c = r.u16();
    if (c == 0) ended = true;
    if (ended) continue;
    out += c < 0x80 ? char(c) : '?';  // names are plain ASCII
  }
  return out;
}

}  // namespace

std::vector<TerrainType> parse_terrain_types(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t count = r.u32();
  if (count > r.remaining() / kTerrainTypeSize) throw ReadError("terrain type table runs past end of entry");
  std::vector<TerrainType> out(count);
  for (TerrainType& t : out) {
    std::size_t start = r.tell();
    r.u32();  // a pointer left over from the tool that wrote the file
    for (std::size_t i = 0; i < kTerrainTypeTextures; ++i) {
      std::int32_t tex = r.i32();
      if (tex >= 0) t.textures.push_back(tex);
    }
    r.seek(start + 108);
    r.u8();  // always 1
    for (auto& c : t.map_colour) c = r.u8();
    t.name = utf16_field(r);
    r.skip(3 * 2 * kNameChars);  // the three texture names, also in `txtrdesc`
    t.display_name = utf16_field(r);
    r.seek(start + kTerrainTypeSize);
  }
  return out;
}

std::vector<Hole> parse_converted_holes(const std::vector<std::uint8_t>& data, std::string* short_name) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kConvertedHeaderVersion) {
    throw ReadError("converted course header version " + std::to_string(version) + " is not supported");
  }
  std::string name = r.fixed_string(kShortNameSize);
  if (short_name) *short_name = name;
  // Rewrite the preamble as version 15 and let the Links 2003 parser read
  // the holes.
  std::vector<std::uint8_t> v15(kV15Preamble, 0);
  const std::int32_t marker = -1;
  const std::uint32_t v = 15;
  std::memcpy(&v15[0], &marker, 4);
  std::memcpy(&v15[4], &v, 4);
  v15.insert(v15.end(), data.begin() + kV14Preamble, data.end());
  return parse_holes(v15);
}

Terrain parse_converted_terrain(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kConvertedTerrainVersion) {
    throw ReadError("converted terrain version " + std::to_string(version) + " is not supported");
  }
  Terrain t;
  std::uint32_t nv = r.u32();
  if (nv > r.remaining() / 16) throw ReadError("terrain vertex count runs past end of entry");
  t.vertices.resize(nv);
  for (TerrainVertex& v : t.vertices) {
    v.position.x = r.f32();
    v.position.y = r.f32();
    v.position.z = r.f32();
    v.unknown_a = r.u16();
    v.flags = r.u16();
  }
  const bool wide = nv > 0xffff;
  const std::size_t record = 12 + (wide ? 20 : 14);
  std::uint32_t nt = r.u32();
  if (nt > r.remaining() / record) throw ReadError("terrain triangle count runs past end of entry");
  t.triangles.resize(nt);
  for (TerrainTriangle& tri : t.triangles) {
    for (auto& n : tri.neighbour) {
      std::uint32_t raw = r.u32();
      n = (raw >> 30) & 1 ? kNoNeighbour : (raw & 0xfffff);
    }
  }
  for (TerrainTriangle& tri : t.triangles) {
    tri.material = r.u16();
    tri.mapping = r.u32();
    tri.unknown = r.u16();
    for (auto& v : tri.v) {
      v = wide ? r.u32() : r.u16();
      if (v >= nv) throw ReadError("terrain triangle refers to a missing vertex");
    }
  }
  return t;
}

bool is_converted_course(const CrzArchive& archive) {
  if (!archive.has("header") || archive.has("Materials")) return false;
  auto h = archive.read("header");
  return h.size() >= 4 && h[0] == kConvertedHeaderVersion && h[1] == 0 && h[2] == 0 && h[3] == 0;
}

Course load_converted_course(const CrzArchive& archive) {
  Course c;
  c.holes = parse_converted_holes(archive.read("header"), &c.name);
  for (char& ch : c.name) {
    if (ch == '_') ch = ' ';
  }
  c.terrain = parse_converted_terrain(archive.read("vertex"));
  c.textures = parse_texture_list(archive.read("txtrdesc"));
  for (const TerrainType& t : parse_terrain_types(archive.read("TerrainTypes"))) {
    TerrainMaterial m;
    m.textures = t.textures;
    c.materials.push_back(std::move(m));
  }
  for (const TerrainTriangle& tri : c.terrain.triangles) {
    if (tri.material >= c.materials.size()) throw ReadError("terrain triangle has an unknown terrain type");
  }
  return c;
}

std::string converted_course_title(const std::string& file_stem) {
  // From the converter's read-me on CD2, matched to the archives by their
  // short names and hole layouts.
  static const std::pair<const char*, const char*> kTitles[] = {
      {"BANFF", "Banff Springs"},
      {"BARTON", "Barton Creek (Fazio)"},
      {"BAYHILL", "Bay Hill Club and Lodge"},
      {"BIGHORN", "Bighorn Golf Club"},
      {"BOUNTIFU", "Bountiful Golf Club"},
      {"CASTLEPI", "Castle Pines Golf Club"},
      {"COGHILL", "Cog Hill (Dubsdread)"},
      {"CONGRESS", "Congressional Country Club"},
      {"COVEREDB", "Covered Bridge Golf Club"},
      {"DEVILSIS", "Devils Island"},
      {"DORADOBE", "Dorado Beach (East Course)"},
      {"ENTRADA", "Entrada at Snow Canyon"},
      {"FIRESTON", "Firestone Country Club (South Course)"},
      {"HAPUNA", "Hapuna Golf Course"},
      {"HARBOURT", "Harbour Town"},
      {"INNISBRO", "Innisbrook (Copperhead)"},
      {"KAPABAY", "Kapalua Bay"},
      {"KAPAPLAN", "Kapalua Plantation"},
      {"KAPAVILL", "Kapalua Village"},
      {"LATROBE", "Latrobe Country Club"},
      {"MAUNAKEA", "Mauna Kea"},
      {"OAKLANDH", "Oakland Hills Country Club"},
      {"PEBBLEBE", "Pebble Beach Golf Links"},
      {"PELICANH", "Pelican Hill Golf Club"},
      {"PHOENIX", "Phoenix Country Club"},
      {"PINEHNEW", "Pinehurst No. 2 (2000)"},
      {"PINEHUR2", "Pinehurst No. 2"},
      {"PINEHUR8", "Pinehurst No. 8"},
      {"PINEHURS", "Pinehurst Country Club (No. 8 layout)"},
      {"PRAIRIE", "Prairie Dunes Country Club"},
      {"RIVIERA", "Riviera Country Club"},
      {"SEAISLAN", "Sea Island Golf Club"},
      {"SEA_ISLA", "Sea Island Golf Club (2000)"},
      {"THEBELFR", "The Belfry"},
      {"THREECAN", "Three Canyons"},
      {"TORREYPI", "Torrey Pines (South Course)"},
      {"TROONNOR", "Troon North"},
      {"VALDERRA", "Valderrama Golf Club"},
      {"VALHALLA", "Valhalla Golf Club"},
  };
  for (const auto& [stem, title] : kTitles) {
    if (iequals(stem, file_stem)) return title;
  }
  return {};
}

}  // namespace olcore
