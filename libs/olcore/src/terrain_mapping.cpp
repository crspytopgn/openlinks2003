#include "olcore/terrain_mapping.hpp"

#include <cmath>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr std::uint32_t kMappingsVersion = 5;
constexpr std::size_t kMappingsHeader = 48;
constexpr float kTau = 6.28318530717958647692f;

}  // namespace

std::vector<TextureMapping> parse_mappings(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  std::uint32_t version = r.u32();
  if (version != kMappingsVersion) throw ReadError("mappings version " + std::to_string(version) + " is not supported");
  std::uint32_t count = r.u32();
  if (count > r.remaining() / 12) throw ReadError("mapping count runs past end of entry");
  r.seek(kMappingsHeader);
  std::vector<TextureMapping> out(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    TextureMapping& m = out[i];
    std::uint32_t kind = r.u32();
    r.u32();  // an id (0x8000 + a number); triangles refer to records by position instead
    std::uint32_t name_length = r.u32();
    m.name = r.fixed_string(name_length);
    m.kind = static_cast<MappingKind>(kind);
    switch (m.kind) {
      case MappingKind::kBlend:
        for (auto& l : m.layers) {
          l = r.u32();
          if (l >= count) throw ReadError("blend mapping refers to a missing mapping");
        }
        r.skip(8);  // two more slots, always 0
        break;
      case MappingKind::kPlanar:
      case MappingKind::kCylindrical:
        m.scale_u = r.f32();
        m.scale_v = r.f32();
        for (float& f : m.frame) f = r.f32();
        break;
      case MappingKind::kStrip: {
        m.scale_u = r.f32();
        m.scale_v = r.f32();
        std::uint32_t nt = r.u32();
        if (nt > r.remaining() / 20) throw ReadError("strip triangles run past end of entry");
        m.triangles.resize(nt);
        for (StripTriangle& t : m.triangles) {
          r.u32();  // the triangle's index in an older build of the mesh
          t.triangle = r.u32();
          for (auto& c : t.corner) c = r.u32();
        }
        std::uint32_t nc = r.u32();
        if (nc > r.remaining() / 16) throw ReadError("strip corners run past end of entry");
        m.corners.resize(nc);
        for (StripCorner& c : m.corners) {
          r.u32();  // the vertex's index in an older build of the mesh
          c.vertex = r.u32();
          c.u = r.f32();
          c.v = r.f32();
        }
        for (const StripTriangle& t : m.triangles) {
          for (auto c : t.corner) {
            if (c >= nc) throw ReadError("strip triangle refers to a missing corner");
          }
        }
        break;
      }
      default:
        throw ReadError("unknown mapping kind " + std::to_string(kind));
    }
  }
  if (r.remaining() != 0) throw ReadError("mappings entry has unexpected trailing data");
  return out;
}

std::array<float, 2> mapping_uv(const TextureMapping& m, const CourseVec3& p) {
  const auto& f = m.frame;
  // Solve p - origin = u*a + v*b + w*c for (u, v, w).
  const float a[3] = {f[0], f[1], f[2]}, b[3] = {f[4], f[5], f[6]}, c[3] = {f[8], f[9], f[10]};
  const float d[3] = {p.x - f[12], p.y - f[13], p.z - f[14]};
  auto det3 = [](const float* x, const float* y, const float* z) {
    return x[0] * (y[1] * z[2] - y[2] * z[1]) - y[0] * (x[1] * z[2] - x[2] * z[1]) + z[0] * (x[1] * y[2] - x[2] * y[1]);
  };
  float det = det3(a, b, c);
  if (std::fabs(det) < 1e-12f) return {0, 0};
  float u = det3(d, b, c) / det;
  float v = det3(a, d, c) / det;
  float w = det3(a, b, d) / det;
  if (m.kind == MappingKind::kCylindrical) return {std::atan2(v, u) / kTau * m.scale_u, w * m.scale_v};
  return {u * m.scale_u, v * m.scale_v};
}

MaterialLayers material_layers(const TerrainMaterial& m) {
  MaterialLayers out;
  out.blended = m.mode == 3 && m.layer_count >= 3;
  std::size_t slot = 0;
  for (std::uint32_t layer = 0; slot < m.textures.size(); ++layer) {
    std::int32_t base = m.textures[slot];
    std::uint32_t details = (m.kind >> (2 * layer)) & 3u;
    slot += 1 + (details & 1u) + ((details >> 1) & 1u);
    if (out.blended && layer == 0) {
      out.mask = base;
    } else {
      out.layers.push_back(base);
    }
  }
  return out;
}

}  // namespace olcore
