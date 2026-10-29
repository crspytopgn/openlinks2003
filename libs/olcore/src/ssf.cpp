#include "olcore/ssf.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr std::size_t kFileHeaderSize = 0x1c;
constexpr std::size_t kChunkHeaderSize = 16;
constexpr std::size_t kEventNameChars = 32;
constexpr std::size_t kEventMaxWaves = 50;

void append_utf8(std::string& out, std::uint32_t cp) {
  if (cp < 0x80) {
    out += static_cast<char>(cp);
  } else if (cp < 0x800) {
    out += static_cast<char>(0xc0 | (cp >> 6));
    out += static_cast<char>(0x80 | (cp & 0x3f));
  } else {
    out += static_cast<char>(0xe0 | (cp >> 12));
    out += static_cast<char>(0x80 | ((cp >> 6) & 0x3f));
    out += static_cast<char>(0x80 | (cp & 0x3f));
  }
}

// Reads NUL-terminated UTF-16LE (BMP only, which is all the game uses).
std::string utf16_string(BinaryReader& r, std::size_t max_chars) {
  std::string out;
  for (std::size_t i = 0; i < max_chars && r.remaining() >= 2; ++i) {
    std::uint16_t c = r.u16();
    if (c == 0) break;
    append_utf8(out, c);
  }
  return out;
}

}  // namespace

SsfFile::SsfFile(std::vector<std::uint8_t> data) : data_(std::move(data)) {
  if (data_.size() < kFileHeaderSize || std::memcmp(data_.data(), "SSF\0", 4) != 0) {
    throw ReadError("not an SSF sound bank");
  }
  BinaryReader r(data_);
  r.seek(0x14);
  std::uint32_t event_count = r.u32();
  r.seek(kFileHeaderSize);

  std::vector<std::string> names;
  std::vector<std::uint32_t> starts;
  while (r.remaining() >= kChunkHeaderSize) {
    std::size_t chunk_start = r.tell();
    auto tag = r.bytes(4);
    std::uint32_t size = r.u32();
    r.skip(8);
    std::size_t body = r.tell();
    if (size > r.remaining()) {
      throw ReadError("SSF chunk at " + std::to_string(chunk_start) + " runs past the end of the file");
    }

    if (std::memcmp(tag.data(), "EVE\0", 4) == 0) {
      SsfEvent e;
      r.skip(4);
      e.name = utf16_string(r, kEventNameChars);
      r.seek(body + 0x44);
      e.chance = r.u32();
      e.type = r.u32();
      r.seek(body + 0x58);
      std::uint32_t count = r.u32();
      if (count > kEventMaxWaves) {
        throw ReadError("SSF event " + e.name + " lists too many waves");
      }
      for (std::uint32_t i = 0; i < count; ++i) e.waves.push_back(r.u16());
      events_.push_back(std::move(e));
    } else if (std::memcmp(tag.data(), "WND\0", 4) == 0) {
      while (r.tell() + 2 <= body + size) names.push_back(utf16_string(r, (body + size - r.tell()) / 2));
    } else if (std::memcmp(tag.data(), "WST\0", 4) == 0) {
      for (std::uint32_t i = 0; i < size / 4; ++i) starts.push_back(r.u32());
    } else if (tag[0] == 'W') {
      std::size_t index = static_cast<std::size_t>(tag[1] | (tag[2] << 8));
      if (waves_.size() <= index) waves_.resize(index + 1);
      waves_[index].offset = body;
      waves_[index].size = size;
    }
    r.seek(body + size);
  }
  if (events_.size() != event_count) {
    throw ReadError("SSF header promises " + std::to_string(event_count) + " events, found " +
                    std::to_string(events_.size()));
  }
  for (std::size_t i = 0; i < waves_.size() && i < names.size(); ++i) waves_[i].name = names[i];
}

SsfFile SsfFile::from_file(const std::string& path) {
  auto r = BinaryReader::from_file(path);
  return SsfFile(std::vector<std::uint8_t>(r.data()));
}

const SsfEvent* SsfFile::find_event(const std::string& name) const {
  for (const auto& e : events_) {
    if (e.name == name) return &e;
  }
  return nullptr;
}

const SsfEvent* SsfFile::find_event(std::uint32_t type) const {
  for (const auto& e : events_) {
    if (e.type == type) return &e;
  }
  return nullptr;
}

std::vector<std::uint8_t> SsfFile::wave_data(std::size_t index) const {
  if (index >= waves_.size() || waves_[index].size == 0) {
    throw ReadError("SSF has no wave " + std::to_string(index));
  }
  const auto& w = waves_[index];
  auto begin = data_.begin() + static_cast<std::ptrdiff_t>(w.offset);
  return std::vector<std::uint8_t>(begin, begin + static_cast<std::ptrdiff_t>(w.size));
}

}  // namespace olcore
