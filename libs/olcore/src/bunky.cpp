#include "olcore/bunky.hpp"

#include <algorithm>
#include <stdexcept>

namespace olcore {

namespace {

std::uint32_t ld32(const std::uint8_t* b) {
  return std::uint32_t(b[0]) | std::uint32_t(b[1]) << 8 | std::uint32_t(b[2]) << 16 | std::uint32_t(b[3]) << 24;
}
void st32(std::uint8_t* b, std::uint32_t v) {
  b[0] = std::uint8_t(v);
  b[1] = std::uint8_t(v >> 8);
  b[2] = std::uint8_t(v >> 16);
  b[3] = std::uint8_t(v >> 24);
}
std::uint32_t ld16(const std::uint8_t* b) { return std::uint32_t(b[0]) | std::uint32_t(b[1]) << 8; }
void st16(std::uint8_t* b, std::uint32_t v) {
  b[0] = std::uint8_t(v);
  b[1] = std::uint8_t(v >> 8);
}

// The block is four 16-bit halves h0..h3 (little-endian). The cipher works
// on four overlapping 32-bit views of it:
//   front = h1:h0 (bytes 0-3), back = h3:h2 (bytes 4-7),
//   middle = h2:h1 (bytes 2-5), outer = h0:h3 (h0 high, h3 low).
std::uint32_t outer(const std::uint8_t* b) { return ld16(b) << 16 | ld16(b + 6); }
void set_outer(std::uint8_t* b, std::uint32_t v) {
  st16(b, v >> 16);
  st16(b + 6, v & 0xffff);
}

constexpr std::uint32_t kSboxSize = 1022;

}  // namespace

BunkyCipher::BunkyCipher(const BunkyTables& tables, const std::uint8_t* key, std::size_t key_len,
                         unsigned rounds) {
  if (key_len == 0) throw std::invalid_argument("Bunky key must not be empty");
  rounds_ = std::clamp(rounds, 4u, 32u);
  key_len = std::min<std::size_t>(key_len, 7);

  for (unsigned i = 0; i < 32; ++i) {
    std::uint32_t k = 0;
    for (unsigned j = 0; j < 4; ++j) k = k << 8 | key[(4 * i + j) % key_len];
    st32(&state_[4 * i], tables.p[i] ^ k);
  }
  for (unsigned i = 0; i < kSboxSize; ++i) st32(&state_[128 + 4 * i], tables.s[i]);

  // Encrypt both tables in place with the cipher itself.
  chain_encrypt(&state_[0], 32 / 2);
  chain_encrypt(&state_[128], kSboxSize / 2);
}

std::uint32_t BunkyCipher::p(unsigned i) const { return ld32(&state_[4 * (i & 31)]); }
std::uint32_t BunkyCipher::s(std::uint32_t i) const { return ld32(&state_[128 + 4 * (i % kSboxSize)]); }

void BunkyCipher::encrypt_block(std::uint8_t* b) const {
  for (unsigned r = 0; r < rounds_; ++r) {
    st32(b, ld32(b) ^ s(ld32(b + 4) + r) ^ p(r));
    set_outer(b, outer(b) ^ s(ld32(b + 2) + r) ^ p(r + 8));
    st32(b + 2, ld32(b + 2) ^ s(outer(b) + r) ^ p(r + 16));
    st32(b + 4, ld32(b + 4) ^ s(ld32(b) + r) ^ p(r + 24));
  }
}

void BunkyCipher::decrypt_block(std::uint8_t* b) const {
  for (unsigned r = rounds_; r-- > 0;) {
    st32(b + 4, ld32(b + 4) ^ s(ld32(b) + r) ^ p(r + 24));
    st32(b + 2, ld32(b + 2) ^ s(outer(b) + r) ^ p(r + 16));
    set_outer(b, outer(b) ^ s(ld32(b + 2) + r) ^ p(r + 8));
    st32(b, ld32(b) ^ s(ld32(b + 4) + r) ^ p(r));
  }
}

// Propagating CBC: each plaintext block is XORed with the previous plaintext
// and ciphertext blocks before it is encrypted. No IV.
void BunkyCipher::chain_encrypt(std::uint8_t* data, std::size_t blocks) const {
  std::uint32_t prev_plain[2] = {0, 0}, prev_cipher[2] = {0, 0};
  for (std::size_t i = 0; i < blocks; ++i) {
    std::uint8_t* b = data + 8 * i;
    std::uint32_t plain[2] = {ld32(b), ld32(b + 4)};
    if (i > 0) {
      st32(b, plain[0] ^ prev_plain[0] ^ prev_cipher[0]);
      st32(b + 4, plain[1] ^ prev_plain[1] ^ prev_cipher[1]);
    }
    encrypt_block(b);
    prev_plain[0] = plain[0];
    prev_plain[1] = plain[1];
    prev_cipher[0] = ld32(b);
    prev_cipher[1] = ld32(b + 4);
  }
}

void BunkyCipher::bytes_mode(std::uint8_t* data, std::size_t n, bool encrypting) const {
  if (n == 1) {
    data[0] ^= std::uint8_t(s(0) ^ p(0));
    return;
  }
  for (unsigned pass = 0; pass < 32; ++pass) {
    unsigned k = encrypting ? pass : 31 - pass;
    for (std::size_t step = 0; step < n; ++step) {
      std::size_t j = encrypting ? step : n - 1 - step;
      data[j] = std::uint8_t(s(data[(j + 1) % n] + std::uint32_t(j)) ^ data[j] ^ p(k));
    }
  }
}

void BunkyCipher::encrypt(std::uint8_t* data, std::size_t n) const {
  if (n < 8) return bytes_mode(data, n, true);
  // The last 8 bytes are encrypted first, so a length that is not a multiple
  // of 8 is still fully covered; the chain then runs over the whole blocks.
  encrypt_block(data + n - 8);
  if (n > 8) chain_encrypt(data, n / 8);
}

void BunkyCipher::decrypt(std::uint8_t* data, std::size_t n) const {
  if (n < 8) return bytes_mode(data, n, false);
  if (n > 8) {
    std::uint32_t prev_plain[2] = {0, 0}, prev_cipher[2] = {0, 0};
    for (std::size_t i = 0; i < n / 8; ++i) {
      std::uint8_t* b = data + 8 * i;
      std::uint32_t cipher[2] = {ld32(b), ld32(b + 4)};
      decrypt_block(b);
      if (i > 0) {
        st32(b, ld32(b) ^ prev_plain[0] ^ prev_cipher[0]);
        st32(b + 4, ld32(b + 4) ^ prev_plain[1] ^ prev_cipher[1]);
      }
      prev_plain[0] = ld32(b);
      prev_plain[1] = ld32(b + 4);
      prev_cipher[0] = cipher[0];
      prev_cipher[1] = cipher[1];
    }
  }
  decrypt_block(data + n - 8);
}

}  // namespace olcore
