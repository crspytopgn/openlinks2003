// olarc: list or unpack ARC0 archives (.LIB, .BTX, .TOP, .CMF, .sky) from
// your own Links 2003 install.
//
//   olarc list    <archive>...
//   olarc extract <archive> <outdir>
//   olarc verify  <archive>...      unpack every entry and check it
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

#include "olcore/arc0.hpp"

namespace fs = std::filesystem;

namespace {

int usage() {
  std::fprintf(stderr,
               "usage: olarc list <archive>...\n"
               "       olarc extract <archive> <outdir>\n"
               "       olarc verify <archive>...\n");
  return 2;
}

// Entry names may contain characters that are awkward in file names.
std::string safe_name(std::string s) {
  for (char& c : s) {
    if (c == '/' || c == '\\' || c == ':') c = '_';
  }
  return s;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return usage();
  std::string cmd = argv[1];
  int failures = 0;
  try {
    if (cmd == "list" || cmd == "verify") {
      for (int i = 2; i < argc; ++i) {
        try {
          auto a = olcore::Arc0Archive::from_file(argv[i]);
          for (std::size_t k = 0; k < a.entries().size(); ++k) {
            const auto& e = a.entries()[k];
            if (cmd == "list") {
              std::printf("%s\t%s\t%u\t%u\n", argv[i], e.name.c_str(), e.size, e.packed_size);
            } else {
              a.read(k);
            }
          }
        } catch (const std::exception& ex) {
          std::fprintf(stderr, "%s: %s\n", argv[i], ex.what());
          ++failures;
        }
      }
      if (cmd == "verify") std::printf("%d archive(s), %d failed\n", argc - 2, failures);
    } else if (cmd == "extract" && argc == 4) {
      auto a = olcore::Arc0Archive::from_file(argv[2]);
      fs::create_directories(argv[3]);
      for (std::size_t k = 0; k < a.entries().size(); ++k) {
        auto data = a.read(k);
        fs::path out = fs::path(argv[3]) / safe_name(a.entries()[k].name);
        std::ofstream(out, std::ios::binary).write(reinterpret_cast<const char*>(data.data()),
                                                   static_cast<std::streamsize>(data.size()));
        std::printf("%s\n", out.string().c_str());
      }
    } else {
      return usage();
    }
  } catch (const std::exception& ex) {
    std::fprintf(stderr, "error: %s\n", ex.what());
    return 1;
  }
  return failures ? 1 : 0;
}
