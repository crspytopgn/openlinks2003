#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace olcore {

// Thrown on a malformed or truncated deflate/zlib stream.
class InflateError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

// Decompresses a raw deflate stream (RFC 1951). If consumed is non-null it
// receives the number of input bytes the stream used, rounded up to a whole
// byte, so callers can walk streams stored back to back.
std::vector<std::uint8_t> inflate_raw(const std::uint8_t* data, std::size_t size, std::size_t* consumed = nullptr);

// Decompresses a zlib stream (RFC 1950: 2-byte header, deflate data, Adler-32
// trailer) and checks the trailer. consumed includes header and trailer.
std::vector<std::uint8_t> zlib_decompress(const std::uint8_t* data, std::size_t size,
                                          std::size_t* consumed = nullptr);

inline std::vector<std::uint8_t> zlib_decompress(const std::vector<std::uint8_t>& data,
                                                 std::size_t* consumed = nullptr) {
  return zlib_decompress(data.data(), data.size(), consumed);
}

std::uint32_t adler32(const std::uint8_t* data, std::size_t size, std::uint32_t start = 1);

}  // namespace olcore
