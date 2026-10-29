#include "olcore/golfer_mesh.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

// Carrera::Mesh fields.
constexpr std::size_t kMeshName = 0x10;
constexpr std::size_t kMeshTransform = 0x1c;
constexpr std::size_t kMeshSkin = 0xd4;
constexpr std::size_t kMeshShapeCount = 0xdc;
constexpr std::size_t kMeshShapes = 0xe0;
constexpr std::size_t kMeshVertexCount = 0xe4;
constexpr std::size_t kMeshPositions = 0xe8;
constexpr std::size_t kMeshTexCoords = 0xec;
constexpr std::size_t kMeshNormals = 0xf0;

// Carrera::Shape (52 bytes, stored as an array).
constexpr std::size_t kShapeSize = 52;
constexpr std::size_t kShapeIndices = 0x14;
constexpr std::size_t kShapeIndexCount = 0x18;
constexpr std::size_t kShapeTriangleCount = 0x1c;
constexpr std::size_t kShapeFirstVertex = 0x24;
constexpr std::size_t kShapeLastVertex = 0x28;
constexpr std::size_t kShapeShader = 0x2c;

// Carrera::Shader and Carrera::Texture.
constexpr std::size_t kShaderName = 0x10;
constexpr std::size_t kShaderDiffuse = 0x14;
constexpr std::size_t kShaderTexture = 0x58;
constexpr std::size_t kTextureFile = 0x14;

// Carrera::SkinCluster.
constexpr std::size_t kSkinJoints = 0x1c;
constexpr std::size_t kSkinJointCount = 0x20;
constexpr std::size_t kSkinInverseBind = 0xa4;
constexpr std::size_t kSkinVertexCount = 0xb0;
constexpr std::size_t kSkinInfluences = 0xb4;
constexpr std::size_t kInfluenceSize = 20;
// Influence joint numbers skip this value: numbers above it refer to the
// joint list entry one lower (seen in every golfer mesh shipped).
constexpr std::uint8_t kSkippedInfluence = 19;

constexpr std::uint32_t kNull = 0xffffffffu;

std::uint32_t u32_at(const std::vector<std::uint8_t>& d, std::size_t off) {
  if (off + 4 > d.size()) throw ReadError("store field out of range");
  return static_cast<std::uint32_t>(d[off]) | (static_cast<std::uint32_t>(d[off + 1]) << 8) |
         (static_cast<std::uint32_t>(d[off + 2]) << 16) | (static_cast<std::uint32_t>(d[off + 3]) << 24);
}

float f32_at(const std::vector<std::uint8_t>& d, std::size_t off) {
  std::uint32_t bits = u32_at(d, off);
  float f;
  std::memcpy(&f, &bits, sizeof f);
  return f;
}

bool valid_pointer(const StoreFile& store, std::uint32_t p) {
  return p != 0 && p != kNull && store.at_offset(p) != nullptr;
}

std::string string_at(const StoreFile& store, std::uint32_t offset) {
  if (!valid_pointer(store, offset)) return std::string();
  const StoreAllocation* a = store.at_offset(offset);
  const auto& d = store.data();
  std::size_t end = offset;
  while (end < a->offset + a->size && d[end] != 0) ++end;
  return std::string(reinterpret_cast<const char*>(d.data() + offset), end - offset);
}

std::string object_name(const StoreFile& store, std::uint32_t p) {
  if (!valid_pointer(store, p)) return std::string();
  const StoreAllocation* a = store.at_offset(p);
  return a->name >= 0 ? store.string(a->name) : std::string();
}

void require(const std::vector<std::uint8_t>& d, std::size_t off, std::size_t bytes, const char* what) {
  if (off == 0 || off + bytes > d.size()) throw ReadError(std::string("mesh ") + what + " runs past the end of the file");
}

MeshMaterial read_material(const StoreFile& store, std::uint32_t shader) {
  MeshMaterial m;
  if (!valid_pointer(store, shader)) return m;
  const auto& d = store.data();
  m.name = object_name(store, shader);
  for (std::size_t i = 0; i < 4; ++i) m.diffuse[i] = f32_at(d, shader + kShaderDiffuse + 4 * i);
  std::uint32_t tex = u32_at(d, shader + kShaderTexture);
  if (valid_pointer(store, tex)) m.texture = string_at(store, u32_at(d, tex + kTextureFile));
  return m;
}

void read_skin(const StoreFile& store, std::uint32_t skin, GolferMesh& mesh) {
  const auto& d = store.data();
  std::size_t joint_count = u32_at(d, skin + kSkinJointCount);
  std::size_t vertex_count = u32_at(d, skin + kSkinVertexCount);
  std::size_t joints = u32_at(d, skin + kSkinJoints);
  std::size_t bind = u32_at(d, skin + kSkinInverseBind);
  std::size_t pool = u32_at(d, skin + kSkinInfluences);
  if (vertex_count != mesh.positions.size()) throw ReadError("skin and mesh vertex counts differ");
  require(d, joints, joint_count * 4, "skin joints");
  require(d, bind, joint_count * 64, "inverse bind matrices");
  require(d, pool, vertex_count * kInfluenceSize, "skin influences");
  for (std::size_t j = 0; j < joint_count; ++j) {
    mesh.skin_joints.push_back(object_name(store, u32_at(d, joints + 4 * j)));
    Mat4 m;
    for (std::size_t k = 0; k < 16; ++k) m[k] = f32_at(d, bind + 64 * j + 4 * k);
    mesh.inverse_bind.push_back(m);
  }
  mesh.influences.resize(vertex_count);
  for (std::size_t v = 0; v < vertex_count; ++v) {
    std::size_t rec = pool + v * kInfluenceSize;
    SkinInfluence& inf = mesh.influences[v];
    for (std::size_t k = 0; k < 4; ++k) {
      std::uint8_t j = d[rec + k];
      inf.weight[k] = f32_at(d, rec + 4 + 4 * k);
      if (j > kSkippedInfluence) --j;
      if (inf.weight[k] != 0.0f && j >= joint_count) throw ReadError("skin influence names a missing joint");
      inf.joint[k] = inf.weight[k] != 0.0f ? j : 0;
    }
  }
}

}  // namespace

std::vector<std::uint32_t> MeshPart::triangles() const {
  std::vector<std::uint32_t> out;
  for (std::size_t k = 0; k + 2 < strip.size(); ++k) {
    std::uint32_t a = strip[k], b = strip[k + 1], c = strip[k + 2];
    if (a == b || b == c || a == c) continue;
    if (k % 2) std::swap(a, b);
    for (std::uint32_t i : {a, b, c}) out.push_back(static_cast<std::uint32_t>(first_vertex) + i);
  }
  return out;
}

std::vector<GolferMesh> read_meshes(const StoreFile& store) {
  const auto& d = store.data();
  std::vector<GolferMesh> meshes;
  for (const auto& a : store.allocations()) {
    if (store.class_name(a) != "class Carrera::Mesh" || a.size < kMeshNormals + 4) continue;
    GolferMesh mesh;
    mesh.name = a.name >= 0 ? store.string(a.name) : std::string();
    mesh.transform = object_name(store, u32_at(d, a.offset + kMeshTransform));
    std::size_t nv = u32_at(d, a.offset + kMeshVertexCount);
    std::size_t pos = u32_at(d, a.offset + kMeshPositions);
    std::size_t uv = u32_at(d, a.offset + kMeshTexCoords);
    std::size_t nrm = u32_at(d, a.offset + kMeshNormals);
    require(d, pos, nv * 12, "positions");
    require(d, uv, nv * 8, "texture coordinates");
    require(d, nrm, nv * 12, "normals");
    mesh.positions.resize(nv);
    mesh.normals.resize(nv);
    mesh.uvs.resize(nv);
    for (std::size_t v = 0; v < nv; ++v) {
      for (std::size_t k = 0; k < 3; ++k) {
        mesh.positions[v][k] = f32_at(d, pos + 12 * v + 4 * k);
        mesh.normals[v][k] = f32_at(d, nrm + 12 * v + 4 * k);
      }
      for (std::size_t k = 0; k < 2; ++k) mesh.uvs[v][k] = f32_at(d, uv + 8 * v + 4 * k);
    }

    std::size_t shape_count = u32_at(d, a.offset + kMeshShapeCount);
    std::size_t shapes = u32_at(d, a.offset + kMeshShapes);
    require(d, shapes, shape_count * kShapeSize, "shapes");
    for (std::size_t s = 0; s < shape_count; ++s) {
      std::size_t rec = shapes + s * kShapeSize;
      MeshPart part;
      part.first_vertex = u32_at(d, rec + kShapeFirstVertex);
      part.last_vertex = u32_at(d, rec + kShapeLastVertex);
      part.triangle_count = u32_at(d, rec + kShapeTriangleCount);
      std::size_t count = u32_at(d, rec + kShapeIndexCount);
      std::size_t idx = u32_at(d, rec + kShapeIndices);
      require(d, idx, count * 2, "strip");
      part.strip.resize(count);
      for (std::size_t i = 0; i < count; ++i) {
        part.strip[i] = static_cast<std::uint16_t>(d[idx + 2 * i] | (d[idx + 2 * i + 1] << 8));
        if (part.first_vertex + part.strip[i] >= nv) throw ReadError("strip index past the vertex buffer");
      }
      part.material = read_material(store, u32_at(d, rec + kShapeShader));
      mesh.parts.push_back(std::move(part));
    }

    std::uint32_t skin = u32_at(d, a.offset + kMeshSkin);
    if (valid_pointer(store, skin)) read_skin(store, skin, mesh);
    meshes.push_back(std::move(mesh));
  }
  return meshes;
}

std::vector<std::array<float, 3>> skin_positions(const GolferMesh& mesh, const Skeleton& skeleton,
                                                 const std::vector<Mat4>& world) {
  if (!mesh.skinned()) return mesh.positions;
  std::vector<Mat4> palette;
  for (std::size_t j = 0; j < mesh.skin_joints.size(); ++j) {
    int n = skeleton.find(mesh.skin_joints[j]);
    if (n < 0 || static_cast<std::size_t>(n) >= world.size()) {
      palette.push_back({1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1});
    } else {
      palette.push_back(multiply(mesh.inverse_bind[j], world[static_cast<std::size_t>(n)]));
    }
  }
  std::vector<std::array<float, 3>> out(mesh.positions.size(), {0.0f, 0.0f, 0.0f});
  for (std::size_t v = 0; v < mesh.positions.size(); ++v) {
    const auto& p = mesh.positions[v];
    const SkinInfluence& inf = mesh.influences[v];
    for (std::size_t k = 0; k < 4; ++k) {
      float w = inf.weight[k];
      if (w == 0.0f) continue;
      const Mat4& m = palette[inf.joint[k]];
      for (std::size_t c = 0; c < 3; ++c) {
        out[v][c] += w * (p[0] * m[c] + p[1] * m[4 + c] + p[2] * m[8 + c] + m[12 + c]);
      }
    }
  }
  return out;
}

}  // namespace olcore
