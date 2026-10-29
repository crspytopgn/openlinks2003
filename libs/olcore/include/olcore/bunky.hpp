#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace olcore {

// The 64-bit block cipher Links 2003 uses to lock course files. See
// docs/formats/crz.md for how it works. The cipher's two constant tables are
// not part of this project: find_bunky_tables() reads them from the player's
// own copy of the game executable.
struct BunkyTables {
  std::array<std::uint32_t, 32> p{};
  std::array<std::uint32_t, 1022> s{};
};

class BunkyCipher {
public:
  // key_len is clamped to 7 and rounds to [4, 32], as the game does.
  BunkyCipher(const BunkyTables& tables, const std::uint8_t* key, std::size_t key_len, unsigned rounds);

  // In place. Any length works; buffers under 8 bytes use a byte-wise mode.
  void encrypt(std::uint8_t* data, std::size_t size) const;
  void decrypt(std::uint8_t* data, std::size_t size) const;

private:
  // P (32 words) then S (1022 words), kept as one little-endian byte block:
  // the key schedule encrypts the tables in place with themselves, so blocks
  // and lookups must see the same memory.
  std::array<std::uint8_t, 4 * (32 + 1022)> state_{};
  unsigned rounds_ = 8;

  std::uint32_t p(unsigned i) const;
  std::uint32_t s(std::uint32_t i) const;
  void encrypt_block(std::uint8_t* b) const;
  void decrypt_block(std::uint8_t* b) const;
  void chain_encrypt(std::uint8_t* data, std::size_t blocks) const;
  void bytes_mode(std::uint8_t* data, std::size_t size, bool encrypting) const;
};

}  // namespace olcore
