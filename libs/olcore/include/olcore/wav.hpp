#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace olcore {

// The parts of a RIFF WAVE file a player needs. Effects are 16-bit PCM;
// golfer voices and commentary are Microsoft ADPCM.
struct WavInfo {
  static constexpr std::uint16_t kPcm = 1;
  static constexpr std::uint16_t kMsAdpcm = 2;

  std::uint16_t format_tag = 0;
  std::uint16_t channels = 0;
  std::uint32_t sample_rate = 0;
  std::uint16_t block_align = 0;
  std::uint16_t bits_per_sample = 0;
  std::size_t data_offset = 0;  // offset of the sample data within the buffer
  std::size_t data_size = 0;
  // MS ADPCM only: samples per channel in each block, and the predictor
  // coefficient pairs from the fmt chunk.
  std::uint16_t samples_per_block = 0;
  std::vector<std::int16_t> adpcm_coefficients;  // coef1, coef2, coef1, coef2 ...

  bool is_pcm() const { return format_tag == kPcm; }
};

// Parses the RIFF header and finds the fmt and data chunks. A data chunk
// that claims more bytes than the buffer holds is clamped. Throws ReadError
// if the buffer is not a WAVE file.
WavInfo parse_wav(const std::uint8_t* data, std::size_t size);
inline WavInfo parse_wav(const std::vector<std::uint8_t>& data) { return parse_wav(data.data(), data.size()); }

// Decodes the sample data to interleaved signed 16-bit PCM. Handles 8- and
// 16-bit PCM and Microsoft ADPCM; throws ReadError for anything else.
std::vector<std::int16_t> decode_pcm16(const std::uint8_t* data, std::size_t size, const WavInfo& info);
inline std::vector<std::int16_t> decode_pcm16(const std::vector<std::uint8_t>& data, const WavInfo& info) {
  return decode_pcm16(data.data(), data.size(), info);
}

}  // namespace olcore
