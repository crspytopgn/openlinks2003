#include "olcore/model.hpp"

#include <map>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

// The .XYZ header lists (count, offset) pairs for each table.
struct Table {
  std::uint32_t count = 0, offset = 0;
};

}  // namespace

Model read_model(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t size = r.u32();
  if (size != data.size()) throw ReadError("XYZ size field does not match the file size");
  r.seek(0x18);
  Table t[5];
  for (Table& x : t) {
    x.count = r.u32();
    x.offset = r.u32();
  }
  r.seek(0x40);
  Model m;
  m.texture_count = r.u32();

  r.seek(t[0].offset);
  m.positions.resize(t[0].count);
  for (auto& p : m.positions) p = {r.f32(), r.f32(), r.f32()};
  r.seek(t[1].offset);
  m.uvs.resize(t[1].count);
  for (auto& uv : m.uvs) uv = {r.f32(), r.f32()};
  r.seek(t[2].offset);
  m.faces.resize(t[2].count);
  for (auto& f : m.faces) {
    f.count = r.u16();
    f.first = r.u16();
    f.flags = r.u16();
    f.texture = r.u16();
    r.u32();  // always 0
  }
  r.seek(t[3].offset);
  m.corners.resize(t[3].count);
  for (auto& c : m.corners) c = r.u16();

  if (m.uvs.size() != m.corners.size()) throw ReadError("XYZ has a different number of uvs and corners");
  for (const auto& f : m.faces) {
    if (f.first + f.count > m.corners.size()) throw ReadError("XYZ face uses corners past the end of the table");
    if (f.texture >= m.texture_count) throw ReadError("XYZ face uses a missing texture");
  }
  for (auto c : m.corners) {
    if (c >= m.positions.size()) throw ReadError("XYZ corner uses a missing vertex");
  }
  return m;
}

RgbaImage ModelTexture::decode(std::size_t level) const {
  const ModelTextureLevel& l = levels.at(level);
  RgbaImage full = decode_dxt5(l.dxt5.data(), (l.width + 3) / 4, (l.height + 3) / 4);
  if (full.width == l.width && full.height == l.height) return full;
  RgbaImage img;
  img.width = l.width;
  img.height = l.height;
  for (int y = 0; y < l.height; ++y) {
    auto row = full.pixels.begin() + static_cast<std::ptrdiff_t>(y) * full.width * 4;
    img.pixels.insert(img.pixels.end(), row, row + l.width * 4);
  }
  return img;
}

std::vector<ModelTexture> read_model_textures(const std::vector<std::uint8_t>& entry, std::size_t levels_per_texture) {
  BinaryReader r(entry);
  r.u32();  // always 0
  std::vector<ModelTexture> out;
  while (r.remaining()) {
    ModelTextureLevel l;
    l.width = static_cast<int>(r.u32());
    l.height = static_cast<int>(r.u32());
    if (l.width <= 0 || l.height <= 0 || l.width > 4096 || l.height > 4096) throw ReadError("CMF texture has a bad size");
    std::size_t blocks = static_cast<std::size_t>((l.width + 3) / 4) * ((l.height + 3) / 4);
    std::size_t used = decode_block_runs(entry.data() + r.tell(), r.remaining(), blocks, l.dxt5);
    r.skip(used);
    if (out.empty() || out.back().levels.size() == levels_per_texture) out.emplace_back();
    out.back().levels.push_back(std::move(l));
  }
  return out;
}

std::vector<ModelSurface> triangulate(const Model& m) {
  std::map<std::uint16_t, ModelSurface> by_texture;
  for (const ModelFace& f : m.faces) {
    if (f.count < 3) continue;
    ModelSurface& s = by_texture[f.texture];
    s.texture = f.texture;
    auto base = static_cast<std::uint32_t>(s.positions.size() / 3);
    for (std::uint16_t k = 0; k < f.count; ++k) {
      const auto& p = m.positions[m.corners[f.first + k]];
      const auto& uv = m.uvs[f.first + k];
      s.positions.insert(s.positions.end(), p.begin(), p.end());
      s.uvs.insert(s.uvs.end(), uv.begin(), uv.end());
    }
    for (std::uint32_t k = 1; k + 1 < f.count; ++k) {
      s.indices.insert(s.indices.end(), {base, base + k, base + k + 1});
    }
  }
  std::vector<ModelSurface> out;
  for (auto& [tex, s] : by_texture) out.push_back(std::move(s));
  return out;
}

}  // namespace olcore
