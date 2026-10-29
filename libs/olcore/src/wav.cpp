#include "olcore/wav.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

std::uint32_t u32_at(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
         (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
}

std::uint16_t u16_at(const std::uint8_t* p) { return static_cast<std::uint16_t>(p[0] | (p[1] << 8)); }

}  // namespace

WavInfo parse_wav(const std::uint8_t* data, std::size_t size) {
  if (size < 12 || std::memcmp(data, "RIFF", 4) != 0 || std::memcmp(data + 8, "WAVE", 4) != 0) {
    throw ReadError("not a RIFF WAVE file");
  }
  WavInfo info;
  bool have_fmt = false, have_data = false;
  std::size_t pos = 12;
  while (pos + 8 <= size && !(have_fmt && have_data)) {
    const std::uint8_t* chunk = data + pos;
    std::size_t chunk_size = u32_at(chunk + 4);
    std::size_t body = pos + 8;
    if (std::memcmp(chunk, "fmt ", 4) == 0) {
      if (chunk_size < 16 || body + 16 > size) {
        throw ReadError("WAVE fmt chunk too short");
      }
      info.format_tag = u16_at(data + body);
      info.channels = u16_at(data + body + 2);
      info.sample_rate = u32_at(data + body + 4);
      info.block_align = u16_at(data + body + 12);
      info.bits_per_sample = u16_at(data + body + 14);
      if (info.format_tag == WavInfo::kMsAdpcm) {
        // cbSize, samples per block, coefficient count, then the pairs.
        if (chunk_size < 22 || body + 22 > size) throw ReadError("MS ADPCM fmt chunk too short");
        info.samples_per_block = u16_at(data + body + 18);
        std::size_t pairs = u16_at(data + body + 20);
        if (chunk_size < 22 + pairs * 4 || body + 22 + pairs * 4 > size) {
          throw ReadError("MS ADPCM coefficient table truncated");
        }
        for (std::size_t i = 0; i < pairs * 2; ++i) {
          info.adpcm_coefficients.push_back(static_cast<std::int16_t>(u16_at(data + body + 22 + i * 2)));
        }
      }
      have_fmt = true;
    } else if (std::memcmp(chunk, "data", 4) == 0) {
      info.data_offset = body;
      info.data_size = body + chunk_size > size ? size - body : chunk_size;
      have_data = true;
    }
    pos = body + chunk_size + (chunk_size & 1);
  }
  if (!have_fmt || !have_data) {
    throw ReadError("WAVE file without fmt or data chunk");
  }
  if (info.channels == 0) {
    throw ReadError("WAVE file with no channels");
  }
  return info;
}

namespace {

std::int16_t clamp16(int v) {
  return static_cast<std::int16_t>(v < -32768 ? -32768 : (v > 32767 ? 32767 : v));
}

// Microsoft ADPCM: per block and channel a predictor index, a step size and
// two seed samples, then 4-bit codes (high nibble first, channels interleaved).
std::vector<std::int16_t> decode_ms_adpcm(const std::uint8_t* src, std::size_t size, const WavInfo& info) {
  static const int kAdaptation[16] = {230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230};
  const std::size_t ch = info.channels;
  if (ch > 2 || info.block_align < 7 * ch || info.adpcm_coefficients.empty()) {
    throw ReadError("unsupported MS ADPCM layout");
  }
  const std::size_t pairs = info.adpcm_coefficients.size() / 2;
  std::vector<std::int16_t> out;
  for (std::size_t block = 0; block + 7 * ch <= size; block += info.block_align) {
    std::size_t end = block + info.block_align < size ? block + info.block_align : size;
    const std::uint8_t* p = src + block;
    int coef1[2], coef2[2], delta[2], s1[2], s2[2];
    for (std::size_t c = 0; c < ch; ++c) {
      std::size_t pred = p[c] < pairs ? p[c] : 0;
      coef1[c] = info.adpcm_coefficients[pred * 2];
      coef2[c] = info.adpcm_coefficients[pred * 2 + 1];
      delta[c] = static_cast<std::int16_t>(u16_at(p + ch + c * 2));
      s1[c] = static_cast<std::int16_t>(u16_at(p + 3 * ch + c * 2));
      s2[c] = static_cast<std::int16_t>(u16_at(p + 5 * ch + c * 2));
    }
    for (std::size_t c = 0; c < ch; ++c) out.push_back(static_cast<std::int16_t>(s2[c]));
    for (std::size_t c = 0; c < ch; ++c) out.push_back(static_cast<std::int16_t>(s1[c]));
    std::size_t limit = info.samples_per_block ? (info.samples_per_block - 2) * ch : ~std::size_t(0);
    std::size_t produced = 0;
    for (std::size_t i = block + 7 * ch; i < end && produced < limit; ++i) {
      for (int half = 0; half < 2 && produced < limit; ++half) {
        std::size_t c = ch == 2 ? static_cast<std::size_t>(half) : 0;
        int nibble = half == 0 ? src[i] >> 4 : src[i] & 0x0f;
        int signed_nibble = nibble >= 8 ? nibble - 16 : nibble;
        int predicted = (s1[c] * coef1[c] + s2[c] * coef2[c]) / 256;  // truncates, like the Windows codec
        std::int16_t sample = clamp16(predicted + signed_nibble * delta[c]);
        s2[c] = s1[c];
        s1[c] = sample;
        delta[c] = (kAdaptation[nibble] * delta[c]) >> 8;
        if (delta[c] < 16) delta[c] = 16;
        out.push_back(sample);
        ++produced;
      }
    }
  }
  return out;
}

}  // namespace

std::vector<std::int16_t> decode_pcm16(const std::uint8_t* data, std::size_t size, const WavInfo& info) {
  if (info.data_offset + info.data_size > size) {
    throw ReadError("WAVE data chunk outside the buffer");
  }
  const std::uint8_t* src = data + info.data_offset;
  std::vector<std::int16_t> out;
  if (info.format_tag == WavInfo::kPcm && info.bits_per_sample == 16) {
    out.resize(info.data_size / 2);
    for (std::size_t i = 0; i < out.size(); ++i) out[i] = static_cast<std::int16_t>(u16_at(src + i * 2));
  } else if (info.format_tag == WavInfo::kPcm && info.bits_per_sample == 8) {
    out.resize(info.data_size);
    for (std::size_t i = 0; i < out.size(); ++i) out[i] = static_cast<std::int16_t>((src[i] - 128) * 256);
  } else if (info.format_tag == WavInfo::kMsAdpcm) {
    out = decode_ms_adpcm(src, info.data_size, info);
  } else {
    throw ReadError("unsupported WAVE format " + std::to_string(info.format_tag));
  }
  return out;
}

}  // namespace olcore
