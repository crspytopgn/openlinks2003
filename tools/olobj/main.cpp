// olobj: inspect and convert Course Designer objects from your own Links 2003
// install (or files extracted from your discs).
//
//   olobj library <OBJECT.LIB>                  list the catalog as TSV
//   olobj texture <archive.btx|.top|.lib> <dir> write every BTCV entry as .tga
//   olobj model   <file.xyz> <file.cmf> <dir>   write model.obj, model.mtl and textures
//   olobj verify  <file>...                     decode files, report failures
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

#include "olcore/arc0.hpp"
#include "olcore/binary_reader.hpp"
#include "olcore/btcv.hpp"
#include "olcore/model.hpp"
#include "olcore/object_library.hpp"
#include "olcore/strings.hpp"

namespace fs = std::filesystem;
using namespace olcore;

namespace {

int usage() {
  std::fprintf(stderr,
               "usage: olobj library <OBJECT.LIB>\n"
               "       olobj texture <archive> <outdir>\n"
               "       olobj model <file.xyz> <file.cmf> <outdir>\n"
               "       olobj verify <file>...\n");
  return 2;
}

void write_tga(const fs::path& path, const RgbaImage& img) {
  auto data = encode_tga(img);
  std::ofstream out(path, std::ios::binary);
  out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
}

std::string stem(std::string name) {
  for (char& c : name) {
    if (c == '/' || c == '\\' || c == ':' || c == ' ') c = '_';
  }
  auto dot = name.rfind('.');
  return dot == std::string::npos ? name : name.substr(0, dot);
}

std::string ext_of(const std::string& path) { return to_lower(fs::path(path).extension().string()); }

int cmd_library(const char* path) {
  ObjectLibrary lib = read_object_library_file(path);
  std::printf("category\tid\tkind\tname\tpath\tsize\ttop_view\tcollision\n");
  for (const auto& c : lib.categories) {
    for (const auto& o : c.objects) {
      std::printf("%s\t%u\t%s\t%s\t%s\t%g x %g x %g\t%s\t%u\n", c.name.c_str(), o.id,
                  o.kind == LibraryObject::Kind::Model ? "model" : "billboard", o.name.c_str(), o.path.c_str(),
                  static_cast<double>(o.size[0]), static_cast<double>(o.size[1]), static_cast<double>(o.size[2]),
                  o.top_view.c_str(), o.collision);
    }
  }
  return 0;
}

int cmd_texture(const char* archive, const char* outdir) {
  Arc0Archive a = Arc0Archive::from_file(archive);
  fs::create_directories(outdir);
  for (std::size_t i = 0; i < a.entries().size(); ++i) {
    auto data = a.read(i);
    if (!is_btcv(data.data(), data.size())) continue;
    fs::path out = fs::path(outdir) / (stem(a.entries()[i].name) + ".tga");
    RgbaImage img = decode_btcv(data);
    write_tga(out, img);
    std::printf("%s\t%d x %d\n", out.string().c_str(), img.width, img.height);
  }
  return 0;
}

int cmd_model(const char* xyz, const char* cmf, const char* outdir) {
  Model m = read_model(BinaryReader::from_file(xyz).data());
  auto textures = read_model_textures(Arc0Archive::from_file(cmf).read("Textures"));
  if (textures.size() != m.texture_count) {
    std::fprintf(stderr, "warning: model wants %u textures, %s has %zu\n", m.texture_count, cmf, textures.size());
  }
  fs::create_directories(outdir);
  std::ofstream mtl(fs::path(outdir) / "model.mtl");
  for (std::size_t t = 0; t < textures.size(); ++t) {
    std::string name = "texture" + std::to_string(t) + ".tga";
    write_tga(fs::path(outdir) / name, textures[t].decode());
    mtl << "newmtl t" << t << "\nKd 1 1 1\nmap_Kd " << name << "\n";
  }
  std::ofstream obj(fs::path(outdir) / "model.obj");
  obj << "# converted by olobj; units: inches, +y up\nmtllib model.mtl\n";
  for (const auto& p : m.positions) obj << "v " << p[0] << ' ' << p[1] << ' ' << p[2] << '\n';
  for (const auto& uv : m.uvs) obj << "vt " << uv[0] << ' ' << 1.0f - uv[1] << '\n';
  int current = -1;
  for (const auto& f : m.faces) {
    if (f.texture != current) {
      current = f.texture;
      obj << "usemtl t" << current << '\n';
    }
    obj << 'f';
    for (int k = 0; k < f.count; ++k) obj << ' ' << m.corners[f.first + k] + 1 << '/' << f.first + k + 1;
    obj << '\n';
  }
  std::printf("%zu vertices, %zu faces, %zu textures\n", m.positions.size(), m.faces.size(), textures.size());
  return 0;
}

// Decodes everything in each file the way the viewer would.
int cmd_verify(int argc, char** argv) {
  int failures = 0, textures = 0, models = 0;
  for (int i = 2; i < argc; ++i) {
    std::string ext = ext_of(argv[i]);
    try {
      if (ext == ".xyz") {
        read_model(BinaryReader::from_file(argv[i]).data());
        ++models;
      } else if (ext == ".cmf") {
        for (const auto& t : read_model_textures(Arc0Archive::from_file(argv[i]).read("Textures"))) {
          for (std::size_t l = 0; l < t.levels.size(); ++l) t.decode(l);
          ++textures;
        }
      } else if (ext == ".lib" && fs::path(argv[i]).filename().string().size() == 10 &&
                 iequals(fs::path(argv[i]).filename().string(), "OBJECT.LIB")) {
        read_object_library_file(argv[i]);
      } else {
        Arc0Archive a = Arc0Archive::from_file(argv[i]);
        for (std::size_t k = 0; k < a.entries().size(); ++k) {
          auto data = a.read(k);
          if (is_btcv(data.data(), data.size())) {
            decode_btcv(data);
            ++textures;
          }
        }
      }
    } catch (const std::exception& e) {
      std::fprintf(stderr, "%s: %s\n", argv[i], e.what());
      ++failures;
    }
  }
  std::printf("%d file(s): %d textures, %d models decoded, %d failed\n", argc - 2, textures, models, failures);
  return failures ? 1 : 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return usage();
  std::string cmd = argv[1];
  try {
    if (cmd == "library" && argc == 3) return cmd_library(argv[2]);
    if (cmd == "texture" && argc == 4) return cmd_texture(argv[2], argv[3]);
    if (cmd == "model" && argc == 5) return cmd_model(argv[2], argv[3], argv[4]);
    if (cmd == "verify") return cmd_verify(argc, argv);
  } catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
  }
  return usage();
}
