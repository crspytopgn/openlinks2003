// oldump: first-look inspector for unknown original game files.
//
//   oldump <file> [--offset N] [--length N] [--strings]
//
// Prints size, a hex/ASCII dump of a window, byte entropy (high entropy hints
// at compression), candidate header fields, and optionally printable strings.
// It only reads files the user supplies; nothing from the original game ships
// with this project.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "olcore/binary_reader.hpp"

namespace {

void hexdump(const std::vector<std::uint8_t>& d, std::size_t off, std::size_t len) {
  std::size_t end = std::min(d.size(), off + len);
  for (std::size_t row = off; row < end; row += 16) {
    std::printf("%08zx  ", row);
    for (std::size_t i = 0; i < 16; ++i) {
      if (row + i < end) {
        std::printf("%02x ", d[row + i]);
      } else {
        std::printf("   ");
      }
      if (i == 7) std::printf(" ");
    }
    std::printf(" |");
    for (std::size_t i = 0; i < 16 && row + i < end; ++i) {
      unsigned char c = d[row + i];
      std::printf("%c", (c >= 32 && c < 127) ? c : '.');
    }
    std::printf("|\n");
  }
}

double entropy(const std::vector<std::uint8_t>& d) {
  if (d.empty()) return 0;
  std::size_t counts[256] = {};
  for (auto b : d) ++counts[b];
  double h = 0;
  for (auto c : counts) {
    if (!c) continue;
    double p = static_cast<double>(c) / d.size();
    h -= p * std::log2(p);
  }
  return h;
}

void print_strings(const std::vector<std::uint8_t>& d, std::size_t min_len) {
  std::string cur;
  std::size_t start = 0;
  for (std::size_t i = 0; i <= d.size(); ++i) {
    bool printable = i < d.size() && d[i] >= 32 && d[i] < 127;
    if (printable) {
      if (cur.empty()) start = i;
      cur += static_cast<char>(d[i]);
    } else {
      if (cur.size() >= min_len) std::printf("%08zx  %s\n", start, cur.c_str());
      cur.clear();
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: oldump <file> [--offset N] [--length N] [--strings]\n");
    return 2;
  }
  std::size_t offset = 0, length = 256;
  bool strings = false;
  for (int i = 2; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--offset") && i + 1 < argc) {
      offset = std::strtoull(argv[++i], nullptr, 0);
    } else if (!std::strcmp(argv[i], "--length") && i + 1 < argc) {
      length = std::strtoull(argv[++i], nullptr, 0);
    } else if (!std::strcmp(argv[i], "--strings")) {
      strings = true;
    }
  }

  try {
    auto r = olcore::BinaryReader::from_file(argv[1]);
    const auto& d = r.data();
    std::printf("file:    %s\nsize:    %zu bytes\nentropy: %.3f bits/byte%s\n\n", argv[1], d.size(), entropy(d),
                entropy(d) > 7.5 ? "  (likely compressed or encrypted)" : "");

    if (d.size() >= 16) {
      std::printf("header as u32 LE: ");
      for (int i = 0; i < 4; ++i) std::printf("0x%08x ", r.u32());
      std::printf("\n");
      r.seek(0);
      std::printf("header as f32 LE: ");
      for (int i = 0; i < 4; ++i) std::printf("%g ", r.f32());
      std::printf("\n\n");
    }

    hexdump(d, offset, length);
    if (strings) {
      std::printf("\nstrings (len >= 4):\n");
      print_strings(d, 4);
    }
  } catch (const std::exception& e) {
    std::fprintf(stderr, "error: %s\n", e.what());
    return 1;
  }
  return 0;
}
