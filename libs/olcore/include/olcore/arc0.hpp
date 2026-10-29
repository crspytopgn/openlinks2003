#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace olcore {

// One entry of an ARC0 archive. See docs/formats/arc0.md.
struct Arc0Entry {
  std::string name;
  std::uint32_t offset = 0;
  std::uint32_t packed_size = 0;
  std::uint32_t size = 0;
  std::uint32_t method = 0;    // 2 = zlib; the only value seen so far
  std::uint32_t checksum = 0;  // Adler-32 of the unpacked data, or 0 when not set
};

// Read-only view of an ARC0 archive (.LIB, .BTX, .TOP, .CMF, .sky) held in
// memory. Entry names are matched case-insensitively, as the game does.
class Arc0Archive {
public:
  explicit Arc0Archive(std::vector<std::uint8_t> data);
  static Arc0Archive from_file(const std::string& path);

  // True if the buffer starts with the ARC0 signature.
  static bool sniff(const std::uint8_t* data, std::size_t size);

  const std::vector<Arc0Entry>& entries() const { return entries_; }
  std::optional<std::size_t> find(const std::string& name) const;

  // Unpacks entry i and verifies its size and checksum. Throws on error.
  std::vector<std::uint8_t> read(std::size_t i) const;
  std::vector<std::uint8_t> read(const std::string& name) const;

private:
  std::vector<std::uint8_t> data_;
  std::vector<Arc0Entry> entries_;
};

}  // namespace olcore
