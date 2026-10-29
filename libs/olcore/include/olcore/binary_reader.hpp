#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace olcore {

// Thrown when a read runs past the end of the buffer.
class ReadError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

// Little-endian cursor over a byte buffer. The original game targets 32-bit
// x86 Windows, so every multi-byte field is assumed to be little-endian.
class BinaryReader {
public:
  explicit BinaryReader(std::vector<std::uint8_t> data);

  static BinaryReader from_file(const std::string& path);

  std::size_t size() const { return data_.size(); }
  std::size_t tell() const { return pos_; }
  std::size_t remaining() const { return data_.size() - pos_; }
  void seek(std::size_t pos);
  void skip(std::size_t count);

  std::uint8_t u8();
  std::uint16_t u16();
  std::uint32_t u32();
  std::int16_t i16();
  std::int32_t i32();
  float f32();
  std::vector<std::uint8_t> bytes(std::size_t count);
  // Fixed-width, NUL-padded string as found in many 2000s-era file headers.
  std::string fixed_string(std::size_t width);

  const std::vector<std::uint8_t>& data() const { return data_; }

private:
  void require(std::size_t count) const;

  std::vector<std::uint8_t> data_;
  std::size_t pos_ = 0;
};

}  // namespace olcore
