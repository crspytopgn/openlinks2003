#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace olcore {

// Decodes the variable-width LZW used by compressed LSls archive entries
// (docs/formats/ls-archive.md): codes packed LSB first, 9 to 13 bits wide,
// 256 = clear, 257 = end, new codes from 258. Stops at the end code, at the
// end of the input, or after max_output bytes. If xor5 is set, every input
// byte is XORed with 5 first. Throws ReadError on a code that cannot occur
// in a valid stream.
std::vector<std::uint8_t> lzw_decompress(const std::uint8_t* src, std::size_t size, std::size_t max_output,
                                         bool xor5 = false);

// Encoder for the same format. The original tools never need it; it exists
// so tests can build archives without shipping original data.
std::vector<std::uint8_t> lzw_compress(const std::uint8_t* src, std::size_t size);

}  // namespace olcore
