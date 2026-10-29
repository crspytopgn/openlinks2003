#include "olcore/ls_archive.hpp"

#include <cctype>

#include "olcore/binary_reader.hpp"
#include "olcore/lzw.hpp"

namespace olcore {

namespace {

constexpr std::size_t kBlockHeaderSize = 0x37;
constexpr std::size_t kCountOffset = 0x0a;
constexpr std::size_t kCompressedOffset = 0x18;
constexpr std::size_t kOriginalSizeOffset = 0x19;
constexpr std::size_t kStoredSizeOffset = 0x1d;
constexpr std::size_t kXorFlagOffset = 0x36;

std::string upper(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  return s;
}

}  // namespace

bool LsArchive::looks_like(const std::vector<std::uint8_t>& data) {
  return data.size() >= kBlockHeaderSize && data[0] == 'L' && data[1] == 'S' && data[2] == 'l' && data[3] == 's';
}

LsArchive::LsArchive(std::vector<std::uint8_t> data) : data_(std::move(data)) {
  if (!looks_like(data_)) {
    throw ReadError("not an LSls archive");
  }
  BinaryReader r(data_);
  r.seek(4);
  version_ = r.u16();
  std::size_t name_width;
  if (version_ == kVersionShortNames) {
    name_width = 13;
  } else if (version_ == kVersionLongNames) {
    name_width = 64;
  } else {
    throw ReadError("unknown LSls version " + std::to_string(version_));
  }
  std::size_t header_size = r.u16();
  r.seek(kCountOffset);
  std::uint32_t count = r.u32();

  std::size_t slot = name_width + 4;
  r.seek(header_size);
  entries_.reserve(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    r.seek(header_size + i * slot);
    LsEntry e;
    e.name = r.fixed_string(name_width);
    e.header_offset = r.u32();

    if (e.header_offset + kBlockHeaderSize > data_.size()) {
      throw ReadError("entry " + e.name + " header lies outside the archive");
    }
    const std::uint8_t* hp = data_.data() + e.header_offset;
    auto u32_at = [hp](std::size_t off) {
      return static_cast<std::uint32_t>(hp[off]) | (static_cast<std::uint32_t>(hp[off + 1]) << 8) |
             (static_cast<std::uint32_t>(hp[off + 2]) << 16) | (static_cast<std::uint32_t>(hp[off + 3]) << 24);
    };
    std::size_t entry_header_size = static_cast<std::size_t>(hp[6] | (hp[7] << 8));
    e.compressed = hp[kCompressedOffset] == 1;
    e.original_size = u32_at(kOriginalSizeOffset);
    e.stored_size = u32_at(kStoredSizeOffset);
    e.data_offset = e.header_offset + entry_header_size;
    if (e.data_offset + e.stored_size > data_.size()) {
      throw ReadError("entry " + e.name + " data lies outside the archive");
    }
    entries_.push_back(std::move(e));
  }
}

LsArchive LsArchive::from_file(const std::string& path) {
  auto r = BinaryReader::from_file(path);
  return LsArchive(std::vector<std::uint8_t>(r.data()));
}

const LsEntry* LsArchive::find(const std::string& name) const {
  std::string want = upper(name);
  for (const auto& e : entries_) {
    if (upper(e.name) == want) return &e;
  }
  return nullptr;
}

std::vector<std::uint8_t> LsArchive::read(const LsEntry& entry) const {
  const std::uint8_t* src = data_.data() + entry.data_offset;
  if (!entry.compressed) {
    return std::vector<std::uint8_t>(src, src + entry.stored_size);
  }
  bool xor5 = data_[entry.header_offset + kXorFlagOffset] != 0;
  auto out = lzw_decompress(src, entry.stored_size, entry.original_size, xor5);
  if (out.size() != entry.original_size) {
    throw ReadError("entry " + entry.name + " decompressed to " + std::to_string(out.size()) + " bytes, expected " +
                    std::to_string(entry.original_size));
  }
  return out;
}

std::optional<std::vector<std::uint8_t>> LsArchive::read(const std::string& name) const {
  const LsEntry* e = find(name);
  if (!e) return std::nullopt;
  return read(*e);
}

}  // namespace olcore
