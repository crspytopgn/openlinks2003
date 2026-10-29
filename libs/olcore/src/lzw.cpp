#include "olcore/lzw.hpp"

#include <string>
#include <unordered_map>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr int kClear = 256;
constexpr int kEnd = 257;
constexpr int kFirstFree = 258;
constexpr int kMinWidth = 9;
constexpr int kMaxWidth = 13;
constexpr int kMaxCodes = 1 << kMaxWidth;

// Width the decoder uses once next_free codes are in its dictionary.
int width_for(int next_free) {
  int width = kMinWidth;
  while (width < kMaxWidth && next_free >= (1 << width)) {
    ++width;
  }
  return width;
}

}  // namespace

std::vector<std::uint8_t> lzw_decompress(const std::uint8_t* src, std::size_t size, std::size_t max_output,
                                         bool xor5) {
  std::vector<std::uint8_t> out;
  out.reserve(max_output);

  std::vector<std::uint16_t> prefix(kMaxCodes);
  std::vector<std::uint8_t> suffix(kMaxCodes);
  std::vector<std::uint8_t> stack;
  stack.reserve(kMaxCodes);

  const std::size_t total_bits = size * 8;
  std::size_t bit_pos = 0;
  int width = kMinWidth;
  int next_free = kFirstFree;
  int prev = -1;
  std::uint8_t first = 0;

  auto byte_at = [&](std::size_t i) -> std::uint32_t {
    if (i >= size) return 0;
    return xor5 ? static_cast<std::uint32_t>(src[i] ^ 5) : src[i];
  };

  while (out.size() < max_output && bit_pos + static_cast<std::size_t>(width) <= total_bits) {
    std::size_t byte = bit_pos >> 3;
    std::uint32_t window = byte_at(byte) | (byte_at(byte + 1) << 8) | (byte_at(byte + 2) << 16);
    int code = static_cast<int>((window >> (bit_pos & 7)) & ((1u << width) - 1));
    bit_pos += static_cast<std::size_t>(width);

    if (code == kClear) {
      width = kMinWidth;
      next_free = kFirstFree;
      prev = -1;
      continue;
    }
    if (code == kEnd) {
      break;
    }
    if (prev < 0) {
      if (code > 255) {
        throw ReadError("LZW: first code after a clear is not a literal");
      }
      out.push_back(static_cast<std::uint8_t>(code));
      prev = code;
      first = static_cast<std::uint8_t>(code);
      continue;
    }
    if (code > next_free || (code == next_free && next_free >= kMaxCodes)) {
      throw ReadError("LZW: code " + std::to_string(code) + " is not in the dictionary");
    }

    stack.clear();
    int cur = code;
    if (code == next_free) {
      stack.push_back(first);
      cur = prev;
    }
    while (cur >= kFirstFree) {
      stack.push_back(suffix[static_cast<std::size_t>(cur)]);
      cur = prefix[static_cast<std::size_t>(cur)];
    }
    first = static_cast<std::uint8_t>(cur);
    stack.push_back(first);
    for (auto it = stack.rbegin(); it != stack.rend() && out.size() < max_output; ++it) {
      out.push_back(*it);
    }

    if (next_free < kMaxCodes) {
      prefix[static_cast<std::size_t>(next_free)] = static_cast<std::uint16_t>(prev);
      suffix[static_cast<std::size_t>(next_free)] = first;
      ++next_free;
      width = width_for(next_free);
    }
    prev = code;
  }
  return out;
}

std::vector<std::uint8_t> lzw_compress(const std::uint8_t* src, std::size_t size) {
  std::vector<std::uint8_t> out;
  std::uint32_t acc = 0;
  int acc_bits = 0;
  auto emit = [&](int code, int width) {
    acc |= static_cast<std::uint32_t>(code) << acc_bits;
    acc_bits += width;
    while (acc_bits >= 8) {
      out.push_back(static_cast<std::uint8_t>(acc & 0xff));
      acc >>= 8;
      acc_bits -= 8;
    }
  };

  // The decoder adds each entry one code later than the encoder does, so
  // the width of the next code is width_for(next_free - 1).
  std::unordered_map<std::uint32_t, int> dict;
  int next_free = kFirstFree;
  emit(kClear, kMinWidth);
  if (size == 0) {
    emit(kEnd, kMinWidth);
  } else {
    int w = src[0];
    for (std::size_t i = 1; i < size; ++i) {
      std::uint32_t key = (static_cast<std::uint32_t>(w) << 8) | src[i];
      auto found = dict.find(key);
      if (found != dict.end()) {
        w = found->second;
        continue;
      }
      emit(w, width_for(next_free - 1));
      dict.emplace(key, next_free++);
      if (next_free == kMaxCodes) {
        emit(kClear, width_for(next_free - 1));
        dict.clear();
        next_free = kFirstFree;
      }
      w = src[i];
    }
    emit(w, width_for(next_free - 1));
    // No entry was added for the last code, so the decoder is level with us.
    emit(kEnd, width_for(next_free));
  }
  if (acc_bits > 0) {
    out.push_back(static_cast<std::uint8_t>(acc & 0xff));
  }
  return out;
}

}  // namespace olcore
