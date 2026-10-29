#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace olcore {

// One sound event (docs/formats/ssf.md).
struct SsfEvent {
  std::string name;  // UTF-8, converted from the stored UTF-16
  std::uint32_t chance = 0;
  std::uint32_t type = 0;  // game event code for effects; 8 or 9 for voice lines
  std::vector<std::uint16_t> waves;
};

struct SsfWave {
  std::string name;          // original file name, may be empty
  std::size_t offset = 0;    // offset of the RIFF data within the SSF buffer
  std::size_t size = 0;
};

// Reader for .SSF sound banks. Keeps the whole file so waves can be
// fetched without copying the bank.
class SsfFile {
public:
  // Throws ReadError if the data is not an SSF bank.
  explicit SsfFile(std::vector<std::uint8_t> data);
  static SsfFile from_file(const std::string& path);

  const std::vector<SsfEvent>& events() const { return events_; }
  const std::vector<SsfWave>& waves() const { return waves_; }

  // First event with this name (case-sensitive), or nullptr.
  const SsfEvent* find_event(const std::string& name) const;
  // First event with this type code, or nullptr.
  const SsfEvent* find_event(std::uint32_t type) const;

  // A complete RIFF WAV file, ready for parse_wav.
  std::vector<std::uint8_t> wave_data(std::size_t index) const;

private:
  std::vector<std::uint8_t> data_;
  std::vector<SsfEvent> events_;
  std::vector<SsfWave> waves_;
};

}  // namespace olcore
