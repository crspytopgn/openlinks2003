// oltex: export the textures of your own Links 2003 files as PNGs, sorted by
// kind, ready for an upscaler, plus the manifest an HD texture pack needs.
//
//   oltex export [--exe <game exe>] <outdir> <folder or file>...
//
// Give it the game folder (an install, the discs' GAME folders, or extracted
// files) and, optionally, the unpacked v1.07 patch. Locked courses (.CRZ,
// .RNG) need the game executable, which is found among the inputs if --exe
// is not given. See docs/hd-textures.md for the layout and how a pack made
// from the upscaled files is loaded by the game.
#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "olcore/arc0.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/btcv.hpp"
#include "olcore/course_objects.hpp"
#include "olcore/crz.hpp"
#include "olcore/image.hpp"
#include "olcore/ls_archive.hpp"
#include "olcore/model.hpp"
#include "olcore/panorama.hpp"
#include "olcore/strings.hpp"

namespace fs = std::filesystem;
using namespace olcore;

namespace {

constexpr int kTerrainPad = 16;  // wrapped border around tiling ground textures
constexpr int kSkyPad = 64;      // wrapped border left and right of a sky

int usage() {
  std::fprintf(stderr, "usage: oltex export [--exe <game exe>] <outdir> <folder or file>...\n");
  return 2;
}

std::vector<std::uint8_t> read_bytes(const fs::path& p) { return BinaryReader::from_file(p.string()).data(); }

std::string stem_of(const std::string& name) {
  auto dot = name.find_last_of('.');
  return dot == std::string::npos ? name : name.substr(0, dot);
}

std::string ext_of(const std::string& name) {
  auto dot = name.find_last_of('.');
  return dot == std::string::npos ? "" : to_lower(name.substr(dot + 1));
}

std::string safe(std::string s) {
  for (char& c : s)
    if (c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') c = '_';
  return s;
}

std::string json_escape(const std::string& s) {
  std::string out;
  for (char c : s) {
    if (c == '"' || c == '\\') out += '\\';
    if (static_cast<unsigned char>(c) < 0x20) continue;
    out += c;
  }
  return out;
}

// One folder per kind, so an upscaler's batch mode can take a whole kind at
// once: "terrain/cabo" + "Sand 1A" is written as terrain/cabo__Sand 1A.
std::string flat_path(const std::string& dir, const std::string& name) {
  auto slash = dir.find('/');
  if (slash == std::string::npos) return dir + "/" + safe(name);
  std::string sub = dir.substr(slash + 1);
  for (std::size_t at = sub.find('/'); at != std::string::npos; at = sub.find('/', at + 2)) sub.replace(at, 1, "__");
  return dir.substr(0, slash) + "/" + safe(sub) + "__" + safe(name);
}

struct Item {
  int width = 0, height = 0;  // before padding
  int pad = 0;
  std::string wrap;  // "", "xy" or "x"
  bool alpha = false;
  std::string source;
};

class Exporter {
public:
  explicit Exporter(fs::path out) : out_(std::move(out)) {}

  // Writes `img` as <dir>/<name>.png. Returns false if that key is taken.
  bool add(const std::string& dir, const std::string& name, RgbaImage img, const std::string& source,
           const std::string& wrap = "") {
    if (img.width <= 0 || img.height <= 0) return false;
    std::string rel = flat_path(dir, name);
    std::string key = to_lower(rel);
    if (items_.count(key)) return false;
    Item it;
    it.width = img.width;
    it.height = img.height;
    it.alpha = !is_opaque(img);
    it.source = source;
    it.wrap = wrap;
    if (it.alpha) bleed_transparent(img);
    if (wrap == "xy") {
      it.pad = kTerrainPad;
      img = pad_wrapped(img, it.pad, true);
    } else if (wrap == "x") {
      it.pad = kSkyPad;
      img = pad_wrapped(img, it.pad, false);
    }
    fs::path p = out_ / (rel + ".png");
    fs::create_directories(p.parent_path());
    write(p, encode_png(img));
    items_[key] = it;
    counts_[dir.substr(0, dir.find('/'))]++;
    return true;
  }

  // Copies a picture the game stores as JPEG; it is not part of the manifest.
  void add_jpeg(const std::string& dir, const std::string& name, const std::vector<std::uint8_t>& data) {
    fs::path p = out_ / (flat_path(dir, name) + ".jpg");
    fs::create_directories(p.parent_path());
    write(p, data);
    counts_[dir.substr(0, dir.find('/'))]++;
  }

  bool has(const std::string& dir, const std::string& name) const { return items_.count(to_lower(flat_path(dir, name))) > 0; }

  void write_manifest() const {
    std::string j = "{\n  \"format\": 1,\n  \"textures\": {\n";
    bool first = true;
    for (const auto& [key, it] : items_) {
      if (!first) j += ",\n";
      first = false;
      j += "    \"" + json_escape(key) + "\": {\"w\": " + std::to_string(it.width) + ", \"h\": " + std::to_string(it.height);
      if (it.pad) j += ", \"pad\": " + std::to_string(it.pad) + ", \"wrap\": \"" + it.wrap + "\"";
      if (it.alpha) j += ", \"alpha\": true";
      j += ", \"source\": \"" + json_escape(it.source) + "\"}";
    }
    j += "\n  }\n}\n";
    write(out_ / "hdpack.json", std::vector<std::uint8_t>(j.begin(), j.end()));
  }

  void report() const {
    for (const auto& [dir, n] : counts_) std::printf("%-10s %6d\n", dir.c_str(), n);
  }

private:
  static void write(const fs::path& p, const std::vector<std::uint8_t>& data) {
    std::ofstream f(p, std::ios::binary);
    f.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    if (!f) throw std::runtime_error("cannot write " + p.string());
  }

  fs::path out_;
  std::map<std::string, Item> items_;
  std::map<std::string, int> counts_;
};

void warn(const fs::path& p, const std::exception& e) { std::fprintf(stderr, "%s: %s\n", p.string().c_str(), e.what()); }

// "Tall Trees100A" -> "Tall Trees100" for billboards stored in sizes A to E.
bool is_smaller_size(const std::string& stem) {
  if (stem.empty()) return false;
  char c = stem.back();
  return c >= 'B' && c <= 'E';
}

// A billboard or spectator sprite: only the largest size (A) is exported,
// since the game makes the smaller ones from it.
void export_sprites(Exporter& ex, const Arc0Archive& arc, const std::string& dir, const std::string& source) {
  for (std::size_t i = 0; i < arc.entries().size(); ++i) {
    const std::string& name = arc.entries()[i].name;
    if (ext_of(name) != "btc" || is_smaller_size(stem_of(name))) continue;
    if (ex.has(dir, stem_of(name))) continue;
    auto data = arc.read(i);
    if (!is_btcv(data.data(), data.size())) continue;
    ex.add(dir, stem_of(name), decode_btcv(data), source);
  }
}

// Assembles sky tiles stored left to right in rows: full 256-pixel rows, then
// one row as tall as the tiles that are left (docs/hd-textures.md).
std::optional<RgbaImage> assemble_sky(const std::vector<RgbaImage>& tiles) {
  if (tiles.empty()) return std::nullopt;
  int width = 0;
  for (const auto& t : tiles) {
    if (t.width != tiles[0].width || t.height != tiles[0].height) break;
    width += t.width;
  }
  // The first row's last tile can carry transparent padding on the right.
  const RgbaImage& last = tiles[static_cast<std::size_t>(width / tiles[0].width) - 1];
  int used = last.width;
  while (used > 0) {
    bool any = false;
    for (int y = 0; y < last.height && !any; ++y) any = last.pixels[(static_cast<std::size_t>(y) * last.width + used - 1) * 4 + 3] != 0;
    if (any) break;
    --used;
  }
  width -= last.width - used;
  int height = 0, x = 0;
  std::vector<std::pair<int, int>> at;  // position of each tile
  int row_h = 0;
  for (const auto& t : tiles) {
    if (x == 0) row_h = t.height;
    at.emplace_back(x, height);
    x += t.width;
    if (x >= width) {
      x = 0;
      height += row_h;
    }
  }
  if (x != 0) height += row_h;
  RgbaImage out;
  out.width = width;
  out.height = height;
  out.pixels.assign(static_cast<std::size_t>(width) * height * 4, 0);
  for (std::size_t i = 0; i < tiles.size(); ++i) {
    const auto& t = tiles[i];
    for (int y = 0; y < t.height && at[i].second + y < height; ++y) {
      int cols = std::min(t.width, width - at[i].first);
      if (cols <= 0) continue;
      std::copy_n(&t.pixels[static_cast<std::size_t>(y) * t.width * 4], static_cast<std::size_t>(cols) * 4,
                  &out.pixels[(static_cast<std::size_t>(at[i].second + y) * width + at[i].first) * 4]);
    }
  }
  return out;
}

// Skies are opaque apart from a couple of edge texels at alpha 205.
RgbaImage make_opaque(RgbaImage img) {
  for (std::size_t i = 3; i < img.pixels.size(); i += 4) img.pixels[i] = 255;
  return img;
}

// A v1.07 patch sky: _s_k_y_1.tga ... as plain TGA tiles.
void export_patch_sky(Exporter& ex, const fs::path& p) {
  Arc0Archive arc(read_bytes(p));
  std::vector<RgbaImage> tiles;
  for (int i = 1;; ++i) {
    auto k = arc.find("_s_k_y_" + std::to_string(i) + ".tga");
    if (!k) break;
    auto img = decode_tga(arc.read(*k));
    if (!img) break;
    tiles.push_back(std::move(*img));
  }
  auto sky = assemble_sky(tiles);
  if (!sky) return;
  ex.add("sky/patch", p.stem().string(), make_opaque(std::move(*sky)), p.filename().string(), "x");
}

void export_course(Exporter& ex, const fs::path& p, const std::vector<std::uint8_t>& exe) {
  auto data = read_bytes(p);
  if (data.size() < 16) return;
  std::optional<GameKeys> keys;
  if (!exe.empty()) keys = find_game_keys(exe, data);
  if (!keys && !CrzArchive::is_plain(data.data())) {
    std::fprintf(stderr, "%s: locked, and no game executable to open it\n", p.string().c_str());
    return;
  }
  CrzArchive crz(std::move(data), keys ? &*keys : nullptr);
  const std::string course = to_lower(p.stem().string()), source = p.filename().string();
  std::map<std::string, std::vector<std::uint8_t>> maqs;
  for (std::size_t i = 0; i < crz.entries().size(); ++i) {
    const std::string& name = crz.entries()[i].name;
    const std::string ext = ext_of(name), stem = stem_of(name);
    const std::string lower = to_lower(stem);
    try {
      if (ext == "tga") {
        auto img = decode_tga(crz.read(i));
        if (!img) continue;
        bool ui = lower == "logo" || (lower.size() == 4 && lower.rfind("tee", 0) == 0);
        if (ui) ex.add("ui/courses/" + course, stem, std::move(*img), source);
        else ex.add("terrain/" + course, stem, std::move(*img), source, "xy");
      } else if (ext == "jpg") {
        ex.add_jpeg("ui/courses/" + course, stem, crz.read(i));
      } else if (ext == "btc") {
        if (is_smaller_size(stem) || ex.has("billboards", stem)) continue;
        auto bytes = crz.read(i);
        if (is_btcv(bytes.data(), bytes.size())) ex.add("billboards", stem, decode_btcv(bytes), source);
      } else if (lower == "panorama" && ext.empty()) {
        auto bytes = crz.read(i);
        if (is_panorama(bytes.data(), bytes.size())) ex.add("horizon", course, decode_panorama(bytes), source, "x");
      } else if (ext == "maq") {
        maqs[name] = crz.read(i);
      }
    } catch (const std::exception& e) {
      std::fprintf(stderr, "%s: %s: %s\n", p.string().c_str(), name.c_str(), e.what());
    }
  }
  // 3D object textures: one per (.maq, level) the course's models use.
  if (auto t3l = crz.find("texture3dobj.t3l")) {
    for (const auto& refs : parse_object_textures(crz.read(*t3l))) {
      for (std::size_t t = 0; t < refs.maq.size() && t < refs.level.size(); ++t) {
        auto m = std::find_if(maqs.begin(), maqs.end(), [&](const auto& kv) { return iequals(kv.first, refs.maq[t]); });
        if (m == maqs.end()) continue;
        std::string name = stem_of(refs.maq[t]) + "_" + std::to_string(refs.level[t]);
        if (ex.has("models/" + course, name)) continue;
        try {
          ex.add("models/" + course, name, decode_maq(m->second, refs.level[t]), source);
        } catch (const std::exception& e) {
          warn(p, e);
        }
      }
    }
  }
}

void export_ls(Exporter& ex, const fs::path& p, const std::string& dir) {
  LsArchive ls = LsArchive::from_file(p.string());
  for (const auto& e : ls.entries()) {
    const std::string ext = ext_of(e.name);
    try {
      if (ext == "tga") {
        if (auto img = decode_tga(ls.read(e))) ex.add(dir, stem_of(e.name), std::move(*img), p.filename().string());
      } else if (ext == "jpg") {
        ex.add_jpeg(dir, stem_of(e.name), ls.read(e));
      }
    } catch (const std::exception& err) {
      std::fprintf(stderr, "%s: %s: %s\n", p.string().c_str(), e.name.c_str(), err.what());
    }
  }
}

int run_export(const std::vector<std::string>& args) {
  std::string exe_path;
  std::vector<std::string> rest;
  for (std::size_t i = 0; i < args.size(); ++i) {
    if (args[i] == "--exe" && i + 1 < args.size()) exe_path = args[++i];
    else rest.push_back(args[i]);
  }
  if (rest.size() < 2) return usage();
  fs::path out = rest[0];
  std::vector<fs::path> files;
  for (std::size_t i = 1; i < rest.size(); ++i) {
    fs::path in = rest[i];
    if (fs::is_regular_file(in)) {
      files.push_back(in);
    } else if (fs::is_directory(in)) {
      for (const auto& e : fs::recursive_directory_iterator(in))
        if (e.is_regular_file()) files.push_back(e.path());
    } else {
      std::fprintf(stderr, "%s: not found\n", in.string().c_str());
      return 1;
    }
  }
  std::sort(files.begin(), files.end());
  if (exe_path.empty()) {
    for (const auto& f : files) {
      std::string n = to_lower(f.filename().string());
      if (n == "linksm_1.exe" || n == "linksmmiii.exe") exe_path = f.string();
    }
  }
  std::vector<std::uint8_t> exe = exe_path.empty() ? std::vector<std::uint8_t>{} : read_bytes(exe_path);

  Exporter ex(out);
  for (const auto& f : files) {
    const std::string name = to_lower(f.filename().string()), ext = ext_of(name), stem = stem_of(name);
    const std::string parent = to_lower(f.parent_path().filename().string());
    try {
      if (name == "stdter_1.lib" || name == "stdterrain.lib") {
        Arc0Archive arc(read_bytes(f));
        for (std::size_t i = 0; i < arc.entries().size(); ++i) {
          const std::string& e = arc.entries()[i].name;
          if (ext_of(e) != "tga") continue;
          if (auto img = decode_tga(arc.read(i))) {
            // Icons and markers do not tile.
            std::string l = to_lower(stem_of(e));
            bool tiles = !(l.size() > 3 && l.compare(l.size() - 3, 3, "icn") == 0) && l != "flag" && l != "tee" && l != "teehighlight";
            ex.add(tiles ? "terrain/standard" : "ui/terrain", stem_of(e), std::move(*img), f.filename().string(), tiles ? "xy" : "");
          }
        }
      } else if (name == "pansky.lib") {
        // Cloud skies (skyNN, tag yks) and horizons (PanNN, tag nap).
        Arc0Archive arc(read_bytes(f));
        for (std::size_t i = 0; i < arc.entries().size(); ++i) {
          const std::string& e = arc.entries()[i].name;
          if (ext_of(e) != "btc") continue;
          auto bytes = arc.read(i);
          if (!is_panorama(bytes.data(), bytes.size())) continue;
          bool sky = read_panorama_header(bytes.data(), bytes.size()).kind == PanoramaKind::Sky;
          RgbaImage img = decode_panorama(bytes);
          ex.add(sky ? "sky" : "horizon", stem_of(e), sky ? make_opaque(std::move(img)) : std::move(img), f.filename().string(), "x");
        }
      } else if (name == "crowds.lib" || name == "trnycrwd.lib") {
        export_sprites(ex, Arc0Archive(read_bytes(f)), "crowds", f.filename().string());
      } else if (ext == "btx") {
        export_sprites(ex, Arc0Archive(read_bytes(f)), "billboards", f.filename().string());
      } else if (ext == "sky") {
        export_patch_sky(ex, f);
      } else if (ext == "crz" || ext == "rng") {
        export_course(ex, f, exe);
      } else if (ext == "l3" && (parent == "polyani" || parent == "clubs")) {
        export_ls(ex, f, (parent == "clubs" ? "golfers/clubs/" : "golfers/") + stem);
      } else if (name == "graphics.ls" || name == "setup.ls" || name == "help.ls") {
        export_ls(ex, f, "ui/" + stem);
      } else if (ext == "tga" && parent == "graphics") {
        if (auto img = decode_tga(read_bytes(f))) ex.add("ui/assets", stem, std::move(*img), f.filename().string());
      } else if (ext == "cmf") {
        Arc0Archive arc(read_bytes(f));
        if (auto k = arc.find("Textures")) {
          auto textures = read_model_textures(arc.read(*k));
          for (std::size_t t = 0; t < textures.size(); ++t)
            ex.add("models/library", stem + "_" + std::to_string(t), textures[t].decode(0), f.filename().string());
        }
      }
    } catch (const std::exception& e) {
      warn(f, e);
    }
  }
  ex.write_manifest();
  ex.report();
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) return usage();
  std::vector<std::string> args(argv + 2, argv + argc);
  try {
    if (std::string(argv[1]) == "export") return run_export(args);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
  }
  return usage();
}
