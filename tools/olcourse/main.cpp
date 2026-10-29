// olcourse: open Links 2003 courses (.CRZ, also .RNG and .CVT) from your own
// discs or install, and export them for the Godot course viewer.
//
//   olcourse list    --exe <game exe> <course>
//   olcourse info    --exe <game exe> <course>
//   olcourse extract --exe <game exe> <course> <outdir>
//   olcourse export  --exe <game exe> [--lib STDTER_1.LIB] <course> <outdir>
//
// Locked courses need the game executable (LINKSM_1.EXE on CD1, or
// LinksMMIII.exe in an install): the cipher tables and key are read from it.
// `export` writes course.json, terrain.bin and the terrain textures; the
// standard textures (Rough01.tga and so on) come from STDTER_1.LIB on CD1.
// It also writes the course's billboard objects: objects.bin and one sprite
// per object type under textures/objects/.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "olcore/arc0.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/btcv.hpp"
#include "olcore/course.hpp"
#include "olcore/course_objects.hpp"
#include "olcore/crz.hpp"
#include "olcore/strings.hpp"

namespace fs = std::filesystem;
using namespace olcore;

namespace {

int usage() {
  std::fprintf(stderr,
               "usage: olcourse list    --exe <game exe> <course>\n"
               "       olcourse info    --exe <game exe> <course>\n"
               "       olcourse extract --exe <game exe> <course> <outdir>\n"
               "       olcourse export  --exe <game exe> [--lib <STDTER_1.LIB>]... <course> <outdir>\n");
  return 2;
}

std::string safe_name(std::string s) {
  for (char& c : s) {
    if (c == '/' || c == '\\' || c == ':') c = '_';
  }
  return s;
}

void write_file(const fs::path& p, const std::vector<std::uint8_t>& data) {
  std::ofstream f(p, std::ios::binary);
  f.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
  if (!f) throw std::runtime_error("cannot write " + p.string());
}

std::unique_ptr<CrzArchive> open_course(const std::string& course, const std::string& exe) {
  auto data = BinaryReader::from_file(course).data();
  if (data.size() < 16) throw std::runtime_error(course + ": too short");
  std::optional<GameKeys> keys;
  if (!CrzArchive::is_plain(data.data())) {
    if (exe.empty()) throw std::runtime_error(course + " is locked: pass --exe <game executable>");
    keys = find_game_keys(BinaryReader::from_file(exe).data(), data.data());
    if (!keys) throw std::runtime_error("could not find the course key in " + exe);
  }
  return std::make_unique<CrzArchive>(std::move(data), keys ? &*keys : nullptr);
}

// --- Minimal TGA reader, only to compute a texture's average colour ------

std::optional<std::array<float, 3>> tga_average(const std::vector<std::uint8_t>& d) {
  if (d.size() < 18) return std::nullopt;
  unsigned id_len = d[0], cmap = d[1], type = d[2];
  unsigned cmap_first = d[3] | d[4] << 8, cmap_len = d[5] | d[6] << 8, cmap_bits = d[7];
  unsigned w = d[12] | d[13] << 8, h = d[14] | d[15] << 8, bpp = d[16];
  std::size_t pos = 18 + id_len, palette = pos, entry = cmap_bits / 8;
  const bool mapped = type == 1 && cmap == 1 && bpp == 8 && (entry == 3 || entry == 4);
  if (!mapped && (cmap != 0 || (type != 2 && type != 10) || (bpp != 24 && bpp != 32))) return std::nullopt;
  if (w == 0 || h == 0) return std::nullopt;
  if (mapped) pos += std::size_t(cmap_len) * entry;
  std::size_t px = mapped ? 1 : std::size_t(bpp / 8), n = std::size_t(w) * h, done = 0;
  double sum[3] = {0, 0, 0};
  auto add = [&](std::size_t at) {
    if (mapped) {
      if (d[at] < cmap_first) return;
      at = palette + (d[at] - cmap_first) * entry;
      if (at + 3 > d.size()) return;
    }
    sum[0] += d[at + 2];  // stored BGR(A)
    sum[1] += d[at + 1];
    sum[2] += d[at];
  };
  while (done < n) {
    if (type == 2 || type == 1) {
      if (pos + px > d.size()) return std::nullopt;
      add(pos);
      pos += px;
      ++done;
      continue;
    }
    if (pos >= d.size()) return std::nullopt;
    unsigned head = d[pos++], count = (head & 0x7f) + 1;
    if (head & 0x80) {
      if (pos + px > d.size()) return std::nullopt;
      for (unsigned i = 0; i < count && done < n; ++i, ++done) add(pos);
      pos += px;
    } else {
      for (unsigned i = 0; i < count && done < n; ++i, ++done) {
        if (pos + px > d.size()) return std::nullopt;
        add(pos);
        pos += px;
      }
    }
  }
  return std::array<float, 3>{float(sum[0] / n / 255), float(sum[1] / n / 255), float(sum[2] / n / 255)};
}

// --- Export ------------------------------------------------------------------

constexpr double kFeetToMetres = 0.3048;

// Course files use feet with z up. The viewer uses Godot's metres with y up;
// x stays x and the course's y axis becomes -z, which keeps the layout
// unmirrored.
std::array<float, 3> to_godot(const CourseVec3& v) {
  return {float(v.x * kFeetToMetres), float(v.z * kFeetToMetres), float(-v.y * kFeetToMetres)};
}

std::string json_string(const std::string& s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += char(c);
    } else if (c < 0x20) {
      char buf[8];
      std::snprintf(buf, sizeof buf, "\\u%04x", c);
      out += buf;
    } else {
      out += char(c);
    }
  }
  return out + "\"";
}

std::string json_vec(const std::array<float, 3>& v) {
  char buf[96];
  std::snprintf(buf, sizeof buf, "[%.3f, %.3f, %.3f]", v[0], v[1], v[2]);
  return buf;
}

template <typename T>
void put(std::vector<std::uint8_t>& out, T v) {
  std::uint8_t b[sizeof(T)];
  std::memcpy(b, &v, sizeof(T));  // all supported platforms are little-endian
  out.insert(out.end(), b, b + sizeof(T));
}

// terrain.bin: "OLTR", u32 version (1), u32 surface count, then per surface
// u32 material, u32 vertex count, u32 index count, f32 positions[3n],
// f32 normals[3n], u32 indices. Positions are already in viewer space and
// triangles are wound clockwise seen from above (Godot's front face).
std::vector<std::uint8_t> build_terrain_bin(const Terrain& t) {
  const std::size_t nv = t.vertices.size();
  std::vector<std::array<float, 3>> pos(nv);
  for (std::size_t i = 0; i < nv; ++i) pos[i] = to_godot(t.vertices[i].position);

  std::vector<std::array<std::uint32_t, 3>> tris;
  tris.reserve(t.triangles.size());
  std::vector<std::array<double, 3>> normal(nv, {0, 0, 0});
  for (const auto& tri : t.triangles) {
    std::array<std::uint32_t, 3> v = tri.v;
    auto& a = pos[v[0]];
    auto& b = pos[v[1]];
    auto& c = pos[v[2]];
    double e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]};
    double e2[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
    double n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
    // Clockwise seen from above means the right-handed normal points down.
    if (n[1] > 0) {
      std::swap(v[1], v[2]);
      for (double& x : n) x = -x;
    }
    for (std::uint32_t k : v) {
      for (int i = 0; i < 3; ++i) normal[k][i] -= n[i];  // accumulate the upward normal
    }
    tris.push_back(v);
  }

  std::map<std::uint16_t, std::vector<std::size_t>> by_material;
  for (std::size_t i = 0; i < t.triangles.size(); ++i) by_material[t.triangles[i].material].push_back(i);

  std::vector<std::uint8_t> out = {'O', 'L', 'T', 'R'};
  put<std::uint32_t>(out, 1);
  put<std::uint32_t>(out, std::uint32_t(by_material.size()));
  std::vector<std::int64_t> remap(nv, -1);
  for (auto& [material, list] : by_material) {
    std::vector<std::uint32_t> used, indices;
    for (std::size_t ti : list) {
      for (std::uint32_t k : tris[ti]) {
        if (remap[k] < 0) {
          remap[k] = std::int64_t(used.size());
          used.push_back(k);
        }
        indices.push_back(std::uint32_t(remap[k]));
      }
    }
    put<std::uint32_t>(out, material);
    put<std::uint32_t>(out, std::uint32_t(used.size()));
    put<std::uint32_t>(out, std::uint32_t(indices.size()));
    for (std::uint32_t k : used) {
      for (float f : pos[k]) put<float>(out, f);
    }
    for (std::uint32_t k : used) {
      auto& n = normal[k];
      double len = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
      for (int i = 0; i < 3; ++i) put<float>(out, float(len > 0 ? n[i] / len : (i == 1 ? 1 : 0)));
    }
    for (std::uint32_t i : indices) put<std::uint32_t>(out, i);
    for (std::uint32_t k : used) remap[k] = -1;
  }
  return out;
}

// objects.bin: "OLOB", u32 version (1), u32 type count, then per type (in
// the order of course.json's "billboards"): u32 count, then count records of
// f32 x, y, z (Godot metres, the base of the billboard) and f32 height.
struct BillboardExport {
  std::string json;  // ",\n  \"billboards\": [...]" for course.json, or empty
  std::size_t placements = 0;
};

BillboardExport export_billboards(const CrzArchive& crz, const fs::path& outdir) {
  BillboardExport result;
  auto master = crz.find("MasterObj");
  auto plants = crz.find("2DPlant");
  if (!master || !plants) return result;
  auto types = parse_billboard_types(crz.read(*master));
  auto placements = parse_billboard_placements(crz.read(*plants));

  std::vector<std::vector<const BillboardPlacement*>> by_type(types.size());
  for (const auto& p : placements) {
    if (p.type < types.size()) by_type[p.type].push_back(&p);
  }
  std::vector<std::uint8_t> bin = {'O', 'L', 'O', 'B'};
  put<std::uint32_t>(bin, 1);
  put<std::uint32_t>(bin, std::uint32_t(types.size()));
  fs::create_directories(outdir / "textures" / "objects");
  std::string j = ",\n  \"billboards\": [\n";
  for (std::size_t t = 0; t < types.size(); ++t) {
    std::string file;
    if (auto e = crz.find(types[t].sprite)) {
      try {
        file = "textures/objects/" + safe_name(types[t].name) + ".tga";
        write_file(outdir / file, encode_tga(decode_btcv(crz.read(*e))));
      } catch (const std::exception& ex) {
        std::fprintf(stderr, "warning: %s: %s\n", types[t].sprite.c_str(), ex.what());
        file.clear();
      }
    } else {
      std::fprintf(stderr, "warning: sprite %s not in the course\n", types[t].sprite.c_str());
    }
    put<std::uint32_t>(bin, std::uint32_t(by_type[t].size()));
    for (const BillboardPlacement* p : by_type[t]) {
      for (float f : to_godot(p->position)) put<float>(bin, f);
      put<float>(bin, float(p->height * kFeetToMetres));
    }
    char aspect[32];
    std::snprintf(aspect, sizeof aspect, "%.4f", types[t].aspect);
    j += "    {\"name\": " + json_string(types[t].name) + ", \"texture\": " + json_string(file) +
         ", \"aspect\": " + aspect + ", \"count\": " + std::to_string(by_type[t].size()) + "}";
    j += t + 1 < types.size() ? ",\n" : "\n";
  }
  j += "  ]";
  write_file(outdir / "objects.bin", bin);
  result.json = j;
  result.placements = placements.size();
  return result;
}

int do_export(const CrzArchive& crz, const std::vector<std::string>& libs, const fs::path& outdir) {
  Course course = load_course(crz);
  fs::create_directories(outdir / "textures");

  std::vector<std::unique_ptr<Arc0Archive>> lib_archives;
  for (const auto& l : libs) lib_archives.push_back(std::make_unique<Arc0Archive>(Arc0Archive::from_file(l)));

  // Find each material's base texture in the course, then in the libraries.
  struct Out {
    std::string file;
    std::array<float, 3> colour{0.25f, 0.45f, 0.2f};
  };
  std::map<std::string, Out> exported;
  auto export_texture = [&](const std::string& name) -> Out {
    auto it = exported.find(to_lower(name));
    if (it != exported.end()) return it->second;
    Out o;
    std::vector<std::uint8_t> data;
    if (auto i = crz.find(name)) {
      data = crz.read(*i);
    } else {
      for (auto& lib : lib_archives) {
        if (auto j = lib->find(name)) {
          data = lib->read(*j);
          break;
        }
      }
    }
    if (!data.empty()) {
      o.file = "textures/" + safe_name(name);
      write_file(outdir / o.file, data);
      if (auto avg = tga_average(data)) o.colour = *avg;
    } else {
      std::fprintf(stderr, "warning: texture %s not found (pass --lib STDTER_1.LIB)\n", name.c_str());
    }
    exported[to_lower(name)] = o;
    return o;
  };

  std::string j = "{\n";
  j += "  \"format\": 1,\n";
  j += "  \"name\": " + json_string(course.name) + ",\n";
  j += "  \"units\": \"metres, y up\",\n";
  j += "  \"materials\": [\n";
  for (std::size_t m = 0; m < course.materials.size(); ++m) {
    Out o;
    // Blended materials list a greyscale mask first ("Fairway To Rough
    // Alpha.tga"); the viewer only shows one texture per material for now,
    // so take the first one that is not a mask.
    for (std::int32_t tex : course.materials[m].textures) {
      if (std::size_t(tex) >= course.textures.size()) continue;
      const std::string& name = course.textures[tex].name;
      if (to_lower(name).find("alpha") != std::string::npos) continue;
      o = export_texture(name);
      break;
    }
    char col[96];
    std::snprintf(col, sizeof col, "[%.3f, %.3f, %.3f]", o.colour[0], o.colour[1], o.colour[2]);
    j += "    {\"texture\": " + json_string(o.file) + ", \"colour\": " + col + "}";
    j += m + 1 < course.materials.size() ? ",\n" : "\n";
  }
  j += "  ],\n  \"holes\": [\n";
  for (std::size_t h = 0; h < course.holes.size(); ++h) {
    const Hole& hole = course.holes[h];
    j += "    {\"number\": " + std::to_string(h + 1) + ", \"name\": " + json_string(hole.name) +
         ", \"par\": " + std::to_string(hole.par) + ", \"handicap\": " + std::to_string(hole.handicap) + ",\n";
    j += "     \"tees\": [";
    for (std::size_t i = 0; i < hole.tees.size(); ++i) {
      j += "{\"position\": " + json_vec(to_godot(hole.tees[i].position)) +
           ", \"yards\": " + std::to_string(hole.tees[i].yards) + "}";
      if (i + 1 < hole.tees.size()) j += ", ";
    }
    j += "],\n     \"pins\": [";
    for (std::size_t i = 0; i < hole.pins.size(); ++i) {
      j += "{\"position\": " + json_vec(to_godot(hole.pins[i].position)) +
           ", \"group\": " + std::to_string(hole.pins[i].group) + "}";
      if (i + 1 < hole.pins.size()) j += ", ";
    }
    j += "],\n     \"aim\": [";
    for (std::size_t i = 0; i < hole.aim_path.size(); ++i) {
      j += json_vec(to_godot(hole.aim_path[i]));
      if (i + 1 < hole.aim_path.size()) j += ", ";
    }
    j += "],\n     \"green\": " + json_vec(to_godot(hole.green)) + "}";
    j += h + 1 < course.holes.size() ? ",\n" : "\n";
  }
  j += "  ]";
  BillboardExport billboards = export_billboards(crz, outdir);
  j += billboards.json + "\n}\n";
  write_file(outdir / "course.json", std::vector<std::uint8_t>(j.begin(), j.end()));
  write_file(outdir / "terrain.bin", build_terrain_bin(course.terrain));
  std::printf("%s: %zu holes, %zu vertices, %zu triangles, %zu textures, %zu billboards -> %s\n",
              course.name.c_str(), course.holes.size(), course.terrain.vertices.size(),
              course.terrain.triangles.size(), exported.size(), billboards.placements, outdir.string().c_str());
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return usage();
  std::string cmd = argv[1], exe;
  std::vector<std::string> libs, rest;
  for (int i = 2; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--exe" && i + 1 < argc) {
      exe = argv[++i];
    } else if (a == "--lib" && i + 1 < argc) {
      libs.push_back(argv[++i]);
    } else {
      rest.push_back(a);
    }
  }
  try {
    if ((cmd == "list" || cmd == "info") && rest.size() == 1) {
      auto crz = open_course(rest[0], exe);
      if (cmd == "list") {
        for (const auto& e : crz->entries()) {
          std::printf("%s\t%u\t%u\t%s\n", e.name.c_str(), e.size, e.packed_size, e.locked ? "locked" : "");
        }
        return 0;
      }
      Course c = load_course(*crz);
      std::printf("%s\n%zu entries, terrain %zu vertices / %zu triangles, %zu materials, %zu textures\n",
                  c.name.c_str(), crz->entries().size(), c.terrain.vertices.size(), c.terrain.triangles.size(),
                  c.materials.size(), c.textures.size());
      for (std::size_t h = 0; h < c.holes.size(); ++h) {
        const Hole& hole = c.holes[h];
        std::printf("%2zu  par %u  hcp %2u  %4u yd  %s\n", h + 1, hole.par, hole.handicap,
                    hole.tees.empty() ? 0u : hole.tees[0].yards, hole.name.c_str());
      }
      return 0;
    }
    if (cmd == "extract" && rest.size() == 2) {
      auto crz = open_course(rest[0], exe);
      fs::create_directories(rest[1]);
      for (std::size_t k = 0; k < crz->entries().size(); ++k) {
        write_file(fs::path(rest[1]) / safe_name(crz->entries()[k].name), crz->read(k));
      }
      std::printf("%zu entries -> %s\n", crz->entries().size(), rest[1].c_str());
      return 0;
    }
    if (cmd == "export" && rest.size() == 2) {
      auto crz = open_course(rest[0], exe);
      return do_export(*crz, libs, rest[1]);
    }
  } catch (const std::exception& ex) {
    std::fprintf(stderr, "error: %s\n", ex.what());
    return 1;
  }
  return usage();
}
