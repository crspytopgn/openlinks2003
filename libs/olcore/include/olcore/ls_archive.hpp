#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace olcore {

// One file inside an LSls archive.
struct LsEntry {
  std::string name;              // as stored in the index (upper case)
  std::size_t header_offset = 0;  // absolute offset of the entry's block header
  std::size_t data_offset = 0;    // absolute offset of the stored bytes
  std::uint32_t stored_size = 0;
  std::uint32_t original_size = 0;
  bool compressed = false;
};

// Reader for the LSls archives behind .LS, .L3 and .TIP files
// (docs/formats/ls-archive.md). Holds the whole archive in memory.
class LsArchive {
public:
  static constexpr std::uint16_t kVersionShortNames = 0x020b;  // .LS, 8.3 names
  static constexpr std::uint16_t kVersionLongNames = 0x020c;   // .L3, up to 63 characters

  // Throws ReadError if the data is not an LSls archive or the index points
  // outside the file.
  explicit LsArchive(std::vector<std::uint8_t> data);
  static LsArchive from_file(const std::string& path);

  static bool looks_like(const std::vector<std::uint8_t>& data);

  std::uint16_t version() const { return version_; }
  const std::vector<LsEntry>& entries() const { return entries_; }

  // Case-insensitive lookup.
  const LsEntry* find(const std::string& name) const;

  // The entry's contents, decompressed if needed.
  std::vector<std::uint8_t> read(const LsEntry& entry) const;
  std::optional<std::vector<std::uint8_t>> read(const std::string& name) const;

private:
  std::vector<std::uint8_t> data_;
  std::uint16_t version_ = 0;
  std::vector<LsEntry> entries_;
};

}  // namespace olcore
