#include "olcore/binary_reader.hpp"

#include <cstring>
#include <fstream>
#include <iterator>

namespace olcore {

BinaryReader::BinaryReader(std::vector<std::uint8_t> data) : data_(std::move(data)) {}

BinaryReader BinaryReader::from_file(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    throw ReadError("cannot open " + path);
  }
  std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  return BinaryReader(std::move(data));
}

void BinaryReader::require(std::size_t count) const {
  if (count > remaining()) {
    throw ReadError("read of " + std::to_string(count) + " bytes at offset " + std::to_string(pos_) +
                    " exceeds buffer size " + std::to_string(data_.size()));
  }
}

void BinaryReader::seek(std::size_t pos) {
  if (pos > data_.size()) {
    throw ReadError("seek to " + std::to_string(pos) + " past end " + std::to_string(data_.size()));
  }
  pos_ = pos;
}

void BinaryReader::skip(std::size_t count) {
  require(count);
  pos_ += count;
}

std::uint8_t BinaryReader::u8() {
  require(1);
  return data_[pos_++];
}

std::uint16_t BinaryReader::u16() {
  require(2);
  std::uint16_t v = static_cast<std::uint16_t>(data_[pos_] | (data_[pos_ + 1] << 8));
  pos_ += 2;
  return v;
}

std::uint32_t BinaryReader::u32() {
  require(4);
  std::uint32_t v = static_cast<std::uint32_t>(data_[pos_]) | (static_cast<std::uint32_t>(data_[pos_ + 1]) << 8) |
                    (static_cast<std::uint32_t>(data_[pos_ + 2]) << 16) |
                    (static_cast<std::uint32_t>(data_[pos_ + 3]) << 24);
  pos_ += 4;
  return v;
}

std::int16_t BinaryReader::i16() { return static_cast<std::int16_t>(u16()); }

std::int32_t BinaryReader::i32() { return static_cast<std::int32_t>(u32()); }

float BinaryReader::f32() {
  std::uint32_t bits = u32();
  float f;
  std::memcpy(&f, &bits, sizeof f);
  return f;
}

std::vector<std::uint8_t> BinaryReader::bytes(std::size_t count) {
  require(count);
  std::vector<std::uint8_t> out(data_.begin() + static_cast<std::ptrdiff_t>(pos_),
                                data_.begin() + static_cast<std::ptrdiff_t>(pos_ + count));
  pos_ += count;
  return out;
}

std::string BinaryReader::fixed_string(std::size_t width) {
  require(width);
  const char* start = reinterpret_cast<const char*>(data_.data() + pos_);
  std::size_t len = 0;
  while (len < width && start[len] != '\0') {
    ++len;
  }
  pos_ += width;
  return std::string(start, len);
}

}  // namespace olcore
