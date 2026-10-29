// oldump: first-look inspector for unknown original game files.
//
//   oldump <file> [--offset N] [--length N] [--strings]
//   oldump ls <archive.ls|.l3|.tip> [--extract DIR]
//   oldump ssf <bank.ssf> [--extract DIR]
//   oldump store <file.skl|.clp>
//   oldump anim <file.skl|.clp> [--skeleton file.skl]
//   oldump mesh <file.skl> [--obj out.obj] [--clip file.clp] [--frame N]
//
// The first form prints size, a hex/ASCII dump of a window, byte entropy
// (high entropy hints at compression), candidate header fields, and
// optionally printable strings. The others list (and extract) the contents
// of the formats olcore understands. It only reads files the user supplies;
// nothing from the original game ships with this project.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

#include "olcore/binary_reader.hpp"
#include "olcore/carrera_store.hpp"
#include "olcore/golfer_anim.hpp"
#include "olcore/golfer_mesh.hpp"
#include "olcore/ls_archive.hpp"
#include "olcore/ssf.hpp"
#include "olcore/wav.hpp"

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

// Wraps decoded samples in a plain 16-bit PCM WAV header.
std::vector<std::uint8_t> pcm16_wav(const std::vector<std::int16_t>& samples, std::uint16_t channels,
                                    std::uint32_t rate) {
  std::vector<std::uint8_t> out;
  auto put32 = [&](std::uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(static_cast<std::uint8_t>(v >> (8 * i)));
  };
  auto put16 = [&](std::uint16_t v) {
    out.push_back(static_cast<std::uint8_t>(v));
    out.push_back(static_cast<std::uint8_t>(v >> 8));
  };
  auto tag = [&](const char* t) { out.insert(out.end(), t, t + 4); };
  std::uint32_t data_size = static_cast<std::uint32_t>(samples.size() * 2);
  tag("RIFF");
  put32(36 + data_size);
  tag("WAVE");
  tag("fmt ");
  put32(16);
  put16(1);
  put16(channels);
  put32(rate);
  put32(rate * channels * 2);
  put16(static_cast<std::uint16_t>(channels * 2));
  put16(16);
  tag("data");
  put32(data_size);
  for (auto s : samples) put16(static_cast<std::uint16_t>(s));
  return out;
}

void write_file(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes) {
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error("cannot write " + path.string());
  out.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
}

// Value of "--extract DIR" if present.
const char* extract_dir(int argc, char** argv) {
  for (int i = 3; i + 1 < argc; ++i) {
    if (!std::strcmp(argv[i], "--extract")) return argv[i + 1];
  }
  return nullptr;
}

int cmd_ls(const char* path, const char* out_dir) {
  auto archive = olcore::LsArchive::from_file(path);
  std::printf("LSls version 0x%04x, %zu entries\n", archive.version(), archive.entries().size());
  for (const auto& e : archive.entries()) {
    std::printf("%-40s %10u %10u %s\n", e.name.c_str(), e.original_size, e.stored_size, e.compressed ? "lzw" : "stored");
    if (out_dir) {
      std::filesystem::create_directories(out_dir);
      write_file(std::filesystem::path(out_dir) / e.name, archive.read(e));
    }
  }
  return 0;
}

int cmd_ssf(const char* path, const char* out_dir) {
  auto bank = olcore::SsfFile::from_file(path);
  std::printf("%zu events, %zu waves\n\nevents (type, chance, waves):\n", bank.events().size(), bank.waves().size());
  for (const auto& e : bank.events()) {
    std::printf("  %3u %3u%%  %-34s", e.type, e.chance, e.name.c_str());
    for (auto w : e.waves) std::printf(" %u", w);
    std::printf("\n");
  }
  std::printf("\nwaves:\n");
  for (std::size_t i = 0; i < bank.waves().size(); ++i) {
    const auto& w = bank.waves()[i];
    if (!w.size) continue;
    auto bytes = bank.wave_data(i);
    auto info = olcore::parse_wav(bytes);
    auto samples = olcore::decode_pcm16(bytes, info);
    std::printf("  %3zu %-24s %s %u Hz %s %.2f s\n", i, w.name.c_str(), info.is_pcm() ? "PCM  " : "ADPCM",
                info.sample_rate, info.channels == 1 ? "mono" : "stereo",
                static_cast<double>(samples.size()) / info.channels / info.sample_rate);
    if (out_dir) {
      std::filesystem::create_directories(out_dir);
      // Written as plain PCM so any player can open them.
      std::string name = w.name.empty() ? "wave" + std::to_string(i) + ".wav" : std::to_string(i) + "_" + w.name;
      write_file(std::filesystem::path(out_dir) / name, pcm16_wav(samples, info.channels, info.sample_rate));
    }
  }
  return 0;
}

int cmd_store(const char* path) {
  auto r = olcore::BinaryReader::from_file(path);
  olcore::StoreFile store(std::vector<std::uint8_t>(r.data()));
  std::printf("classes:\n");
  for (const auto& c : store.classes()) std::printf("  %-36s %zu bytes\n", c.name.c_str(), c.instance_size);
  std::printf("\nallocations (offset, size, class, name, tag):\n");
  for (const auto& a : store.allocations()) {
    std::printf("  0x%06zx %8zu  %-28s %-28s %s\n", a.offset, a.size, store.class_name(a).c_str(),
                store.string(a.name).c_str(), store.string(a.tag).c_str());
  }
  return 0;
}

int cmd_anim(const char* path, const char* skeleton_path) {
  auto r = olcore::BinaryReader::from_file(path);
  olcore::StoreFile store(std::vector<std::uint8_t>(r.data()));
  olcore::Skeleton skeleton;
  if (skeleton_path) {
    auto s = olcore::BinaryReader::from_file(skeleton_path);
    skeleton = olcore::read_skeleton(olcore::StoreFile(std::vector<std::uint8_t>(s.data())));
  } else {
    skeleton = olcore::read_skeleton(store);
  }
  if (!skeleton.nodes.empty()) {
    std::printf("skeleton: %zu nodes\n", skeleton.nodes.size());
    auto world = skeleton.pose(nullptr, 0);
    for (std::size_t i = 0; i < skeleton.nodes.size(); ++i) {
      const auto& n = skeleton.nodes[i];
      std::printf("  %-28s parent %-28s %s rest at (%.3f, %.3f, %.3f) ft\n", n.name.c_str(),
                  n.parent >= 0 ? skeleton.nodes[static_cast<std::size_t>(n.parent)].name.c_str() : "-",
                  n.is_joint ? "joint" : "     ", world[i][12], world[i][13], world[i][14]);
    }
  }
  for (const auto& clip : olcore::read_anim_clips(store)) {
    std::size_t matched = 0;
    for (const auto& ch : clip.channels) matched += skeleton.find(ch.node_hash) >= 0;
    std::printf("clip %s: %u frames (%.2f s), %zu channels, %zu animated", clip.name.c_str(), clip.frame_count,
                clip.frame_count / olcore::AnimClip::kFramesPerSecond, clip.channels.size(), clip.dynamic_count);
    if (!skeleton.nodes.empty()) std::printf(", %zu bound to skeleton nodes", matched);
    std::printf("\n");
  }
  return 0;
}

// Lists the meshes of a model; --obj writes them (posed by --clip at
// --frame, else in the bind pose) as a Wavefront OBJ for a model viewer.
int cmd_mesh(const char* path, const char* obj_path, const char* clip_path, std::size_t frame) {
  auto r = olcore::BinaryReader::from_file(path);
  olcore::StoreFile store(std::vector<std::uint8_t>(r.data()));
  olcore::Skeleton skeleton = olcore::read_skeleton(store);
  std::vector<olcore::AnimClip> clips;
  if (clip_path) {
    auto c = olcore::BinaryReader::from_file(clip_path);
    clips = olcore::read_anim_clips(olcore::StoreFile(std::vector<std::uint8_t>(c.data())));
  }
  auto world = skeleton.pose(clips.empty() ? nullptr : &clips[0], frame);
  auto meshes = olcore::read_meshes(store);
  std::ofstream obj;
  if (obj_path) obj.open(obj_path);
  std::size_t base = 1;
  for (const auto& m : meshes) {
    std::printf("mesh %s (on %s): %zu vertices, %zu parts, %s\n", m.name.c_str(), m.transform.c_str(),
                m.positions.size(), m.parts.size(),
                m.skinned() ? ("skinned to " + std::to_string(m.skin_joints.size()) + " joints").c_str() : "rigid");
    for (const auto& p : m.parts) {
      std::printf("  part: vertices %zu-%zu, %zu triangles, material %s, texture %s\n", p.first_vertex,
                  p.last_vertex, p.triangle_count, p.material.name.c_str(),
                  p.material.texture.empty() ? "-" : p.material.texture.c_str());
    }
    if (!obj) continue;
    auto pos = olcore::skin_positions(m, skeleton, world);
    obj << "o " << m.name << "\n";
    for (const auto& v : pos) obj << "v " << v[0] << ' ' << v[1] << ' ' << v[2] << "\n";
    for (const auto& t : m.uvs) obj << "vt " << t[0] << ' ' << t[1] << "\n";
    for (const auto& p : m.parts) {
      obj << "g " << p.material.name << "\n";
      auto tri = p.triangles();
      for (std::size_t i = 0; i + 2 < tri.size(); i += 3) {
        obj << 'f';
        for (std::size_t k = 0; k < 3; ++k) obj << ' ' << base + tri[i + k] << '/' << base + tri[i + k];
        obj << "\n";
      }
    }
    base += pos.size();
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr,
                 "usage: oldump <file> [--offset N] [--length N] [--strings]\n"
                 "       oldump ls <archive> [--extract DIR]\n"
                 "       oldump ssf <bank.ssf> [--extract DIR]\n"
                 "       oldump store <file.skl|file.clp>\n"
                 "       oldump anim <file.skl|file.clp> [--skeleton file.skl]\n"
                 "       oldump mesh <file.skl> [--obj out.obj] [--clip file.clp] [--frame N]\n");
    return 2;
  }
  if (argc >= 3 && (!std::strcmp(argv[1], "ls") || !std::strcmp(argv[1], "ssf") || !std::strcmp(argv[1], "store") ||
                    !std::strcmp(argv[1], "anim") || !std::strcmp(argv[1], "mesh"))) {
    try {
      if (!std::strcmp(argv[1], "ls")) return cmd_ls(argv[2], extract_dir(argc, argv));
      if (!std::strcmp(argv[1], "ssf")) return cmd_ssf(argv[2], extract_dir(argc, argv));
      if (!std::strcmp(argv[1], "anim")) {
        const char* skeleton = nullptr;
        for (int i = 3; i + 1 < argc; ++i) {
          if (!std::strcmp(argv[i], "--skeleton")) skeleton = argv[i + 1];
        }
        return cmd_anim(argv[2], skeleton);
      }
      if (!std::strcmp(argv[1], "mesh")) {
        const char *obj = nullptr, *clip = nullptr;
        std::size_t frame = 0;
        for (int i = 3; i + 1 < argc; ++i) {
          if (!std::strcmp(argv[i], "--obj")) obj = argv[i + 1];
          if (!std::strcmp(argv[i], "--clip")) clip = argv[i + 1];
          if (!std::strcmp(argv[i], "--frame")) frame = std::strtoull(argv[i + 1], nullptr, 0);
        }
        return cmd_mesh(argv[2], obj, clip, frame);
      }
      return cmd_store(argv[2]);
    } catch (const std::exception& e) {
      std::fprintf(stderr, "error: %s\n", e.what());
      return 1;
    }
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
