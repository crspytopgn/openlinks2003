#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "olcore/bunky.hpp"

namespace olcore {

// What it takes to open a locked course: the cipher tables and the archive
// key. Neither ships with this project; find_game_keys() recovers both from
// the player's own game executable (LINKSM_1.EXE on the CD, LinksMMIII.exe
// once installed).
struct GameKeys {
  BunkyTables tables;
  std::array<std::uint8_t, 8> archive_key{};
};

// Locates the cipher tables in an executable image. Returns nothing if the
// file does not look like a Links 2003 executable.
std::optional<BunkyTables> find_bunky_tables(const std::vector<std::uint8_t>& exe);

// Locates the tables and the archive key. `header` is the first 16 bytes of
// any locked course (.CRZ, .RNG, .CVT); a candidate key is accepted when it
// turns those bytes into a valid ARC0 header.
std::optional<GameKeys> find_game_keys(const std::vector<std::uint8_t>& exe, const std::uint8_t* header);

// One entry of a course archive. See docs/formats/crz.md.
struct CrzEntry {
  std::string name;
  std::uint32_t offset = 0;
  std::uint32_t packed_size = 0;
  std::uint32_t size = 0;
  std::uint32_t method = 0;    // 0 = stored, 2 = zlib
  std::uint32_t checksum = 0;  // Adler-32 of the unpacked data, 0 if not set
  bool locked = false;         // entry data is encrypted before it is unpacked
};

// A course archive (.CRZ, also .RNG and .CVT): an ARC0 archive whose header
// and directory are encrypted, and some of whose entries are too. Plain ARC0
// files open as well. Entry names match case-insensitively.
class CrzArchive {
public:
  CrzArchive(std::vector<std::uint8_t> data, const GameKeys* keys);
  static CrzArchive from_file(const std::string& path, const GameKeys* keys);

  // True if the 16 bytes look like a plain (unlocked) ARC0 header.
  static bool is_plain(const std::uint8_t* header);

  const std::vector<CrzEntry>& entries() const { return entries_; }
  std::optional<std::size_t> find(const std::string& name) const;
  bool has(const std::string& name) const { return find(name).has_value(); }

  // Decrypts if needed, unpacks and checks entry i. Throws on error.
  std::vector<std::uint8_t> read(std::size_t i) const;
  std::vector<std::uint8_t> read(const std::string& name) const;

private:
  std::vector<std::uint8_t> data_;
  std::vector<CrzEntry> entries_;
  std::optional<BunkyTables> tables_;
  std::array<std::uint8_t, 8> archive_key_{};
  std::optional<std::array<std::uint8_t, 8>> course_key_;

  std::vector<std::uint8_t> unpack(const CrzEntry& e, const std::array<std::uint8_t, 8>* key) const;
};

}  // namespace olcore
