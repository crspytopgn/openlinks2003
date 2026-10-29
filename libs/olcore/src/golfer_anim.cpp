#include "olcore/golfer_anim.hpp"

#include <cmath>
#include <cstring>
#include <functional>
#include <unordered_map>

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

// Carrera::AnimClip fields.
constexpr std::size_t kClipName = 0x10;
constexpr std::size_t kClipFrameCount = 0x2c;
constexpr std::size_t kClipChannelCount = 0x30;
constexpr std::size_t kClipDynamicCount = 0x34;
constexpr std::size_t kClipChannels = 0x38;
constexpr std::size_t kClipSamples = 0x3c;
constexpr std::size_t kChannelSize = 20;

// Carrera::Transform fields (Joint extends Transform).
constexpr std::size_t kNodeName = 0x10;
constexpr std::size_t kNodeParent = 0x1c;
constexpr std::size_t kNodeTranslate = 280;
constexpr std::size_t kNodeRotate = 292;
constexpr std::size_t kJointOrient = 440;

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

// NUL-terminated string at a stored pointer (a file offset), or "".
std::string string_at(const StoreFile& store, std::uint32_t offset) {
  const StoreAllocation* a = store.at_offset(offset);
  if (!offset || !a) return std::string();
  const auto& d = store.data();
  std::size_t end = offset;
  while (end < a->offset + a->size && d[end] != 0) ++end;
  return std::string(reinterpret_cast<const char*>(d.data() + offset), end - offset);
}

AnimAttribute attribute_for(std::uint32_t field_offset) {
  switch (field_offset) {
    case kNodeTranslate: return AnimAttribute::TranslateX;
    case kNodeTranslate + 4: return AnimAttribute::TranslateY;
    case kNodeTranslate + 8: return AnimAttribute::TranslateZ;
    case kNodeRotate: return AnimAttribute::RotateX;
    case kNodeRotate + 4: return AnimAttribute::RotateY;
    case kNodeRotate + 8: return AnimAttribute::RotateZ;
    default: return AnimAttribute::Unknown;
  }
}

Mat4 identity() { return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}; }

// Rotation matrices in the row-vector convention.
Mat4 rotation_x(float a) {
  float c = std::cos(a), s = std::sin(a);
  return {1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1};
}

Mat4 rotation_y(float a) {
  float c = std::cos(a), s = std::sin(a);
  return {c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1};
}

Mat4 rotation_z(float a) {
  float c = std::cos(a), s = std::sin(a);
  return {c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
}

Mat4 rotation_quat(const std::array<float, 4>& q) {
  float x = q[0], y = q[1], z = q[2], w = q[3];
  return {1 - 2 * (y * y + z * z), 2 * (x * y + z * w),     2 * (x * z - y * w),     0,
          2 * (x * y - z * w),     1 - 2 * (x * x + z * z), 2 * (y * z + x * w),     0,
          2 * (x * z + y * w),     2 * (y * z - x * w),     1 - 2 * (x * x + y * y), 0,
          0,                       0,                       0,                       1};
}

}  // namespace

std::uint32_t name_hash(const std::string& name) {
  std::uint32_t crc = 0xffffffffu;
  for (unsigned char c : name) {
    crc ^= c;
    for (int k = 0; k < 8; ++k) crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
  }
  return ~crc;
}

float AnimClip::value(std::size_t channel, std::size_t frame) const {
  std::size_t index = channel;
  if (frame > 0 && channel < dynamic_count) {
    index = channels.size() + (frame - 1) * dynamic_count + channel;
  }
  return index < samples.size() ? samples[index] * kSampleScale : 0.0f;
}

std::vector<AnimClip> read_anim_clips(const StoreFile& store) {
  const auto& d = store.data();
  std::vector<AnimClip> clips;
  for (const auto& a : store.allocations()) {
    if (store.class_name(a) != "class Carrera::AnimClip" || a.size < kClipSamples + 4) continue;
    std::uint32_t channel_count = u32_at(d, a.offset + kClipChannelCount);
    if (channel_count == 0) continue;
    AnimClip clip;
    clip.name = string_at(store, u32_at(d, a.offset + kClipName));
    clip.frame_count = u32_at(d, a.offset + kClipFrameCount);
    clip.dynamic_count = u32_at(d, a.offset + kClipDynamicCount);
    std::size_t channels = u32_at(d, a.offset + kClipChannels);
    std::size_t samples = u32_at(d, a.offset + kClipSamples);
    if (clip.frame_count == 0 || clip.dynamic_count > channel_count) {
      throw ReadError("clip " + clip.name + " has inconsistent counts");
    }
    std::size_t sample_count = channel_count + (clip.frame_count - 1) * clip.dynamic_count;
    if (channels + channel_count * kChannelSize > d.size() || samples + sample_count * 2 > d.size()) {
      throw ReadError("clip " + clip.name + " tables run past the end of the file");
    }
    for (std::uint32_t i = 0; i < channel_count; ++i) {
      std::size_t rec = channels + i * kChannelSize;
      AnimChannel ch;
      ch.node_hash = u32_at(d, rec + 4);
      ch.attribute = attribute_for(u32_at(d, rec + 8));
      clip.channels.push_back(ch);
    }
    clip.samples.resize(sample_count);
    for (std::size_t i = 0; i < sample_count; ++i) {
      clip.samples[i] = static_cast<std::int16_t>(d[samples + i * 2] | (d[samples + i * 2 + 1] << 8));
    }
    clips.push_back(std::move(clip));
  }
  return clips;
}

Skeleton read_skeleton(const StoreFile& store) {
  const auto& d = store.data();
  struct Raw {
    SkeletonNode node;
    std::uint32_t parent_offset;
    std::size_t offset;
  };
  std::vector<Raw> raw;
  for (const auto& a : store.allocations()) {
    std::string cls = store.class_name(a);
    bool joint = cls == "class Carrera::Joint";
    if (!joint && cls != "class Carrera::Transform" && cls != "class Carrera::TransformEx") continue;
    if (a.size < (joint ? kJointOrient + 16 : kNodeRotate + 12)) throw ReadError("transform object too small");
    Raw r;
    r.offset = a.offset;
    r.node.name = store.string(a.name);
    r.node.name_hash = name_hash(r.node.name);
    r.node.is_joint = joint;
    for (int i = 0; i < 3; ++i) {
      r.node.translate[static_cast<std::size_t>(i)] = f32_at(d, a.offset + kNodeTranslate + 4 * static_cast<std::size_t>(i));
      r.node.rotate[static_cast<std::size_t>(i)] = f32_at(d, a.offset + kNodeRotate + 4 * static_cast<std::size_t>(i));
    }
    if (joint) {
      for (std::size_t i = 0; i < 4; ++i) r.node.orient[i] = f32_at(d, a.offset + kJointOrient + 4 * i);
    }
    r.parent_offset = u32_at(d, a.offset + kNodeParent);
    raw.push_back(std::move(r));
  }

  // Order parents before children.
  std::unordered_map<std::size_t, std::size_t> by_offset;
  for (std::size_t i = 0; i < raw.size(); ++i) by_offset[raw[i].offset] = i;
  std::vector<int> new_index(raw.size(), -1);
  Skeleton sk;
  std::function<int(std::size_t, int)> place = [&](std::size_t i, int depth) -> int {
    if (new_index[i] >= 0) return new_index[i];
    if (depth > 1000) throw ReadError("cycle in the transform hierarchy");
    int parent = -1;
    auto p = by_offset.find(raw[i].parent_offset);
    if (raw[i].parent_offset && p != by_offset.end()) parent = place(p->second, depth + 1);
    SkeletonNode node = raw[i].node;
    node.parent = parent;
    new_index[i] = static_cast<int>(sk.nodes.size());
    sk.nodes.push_back(std::move(node));
    return new_index[i];
  };
  for (std::size_t i = 0; i < raw.size(); ++i) place(i, 0);
  return sk;
}

int Skeleton::find(std::uint32_t hash) const {
  for (std::size_t i = 0; i < nodes.size(); ++i) {
    if (nodes[i].name_hash == hash) return static_cast<int>(i);
  }
  return -1;
}

Mat4 multiply(const Mat4& a, const Mat4& b) {
  Mat4 r{};
  for (int i = 0; i < 4; ++i) {
    for (int j = 0; j < 4; ++j) {
      float s = 0;
      for (int k = 0; k < 4; ++k) s += a[static_cast<std::size_t>(i * 4 + k)] * b[static_cast<std::size_t>(k * 4 + j)];
      r[static_cast<std::size_t>(i * 4 + j)] = s;
    }
  }
  return r;
}

Mat4 Skeleton::local_matrix(const SkeletonNode& node, const std::array<float, 3>& rotate,
                            const std::array<float, 3>& translate) {
  Mat4 m = multiply(multiply(rotation_x(rotate[0]), rotation_y(rotate[1])), rotation_z(rotate[2]));
  if (node.is_joint) m = multiply(m, rotation_quat(node.orient));
  m[12] = translate[0];
  m[13] = translate[1];
  m[14] = translate[2];
  return m;
}

std::vector<Mat4> Skeleton::pose(const AnimClip* clip, std::size_t frame) const {
  std::vector<std::array<float, 3>> rot(nodes.size()), tr(nodes.size());
  for (std::size_t i = 0; i < nodes.size(); ++i) {
    rot[i] = nodes[i].rotate;
    tr[i] = nodes[i].translate;
  }
  if (clip) {
    if (frame >= clip->frame_count) frame = clip->frame_count - 1;
    std::unordered_map<std::uint32_t, std::size_t> index;
    for (std::size_t i = 0; i < nodes.size(); ++i) index.emplace(nodes[i].name_hash, i);
    for (std::size_t c = 0; c < clip->channels.size(); ++c) {
      const auto& ch = clip->channels[c];
      auto it = index.find(ch.node_hash);
      if (it == index.end() || ch.attribute == AnimAttribute::Unknown) continue;
      int a = static_cast<int>(ch.attribute);
      float v = clip->value(c, frame);
      if (a < 3) {
        tr[it->second][static_cast<std::size_t>(a)] = v;
      } else {
        rot[it->second][static_cast<std::size_t>(a - 3)] = v;
      }
    }
  }
  std::vector<Mat4> world(nodes.size(), identity());
  for (std::size_t i = 0; i < nodes.size(); ++i) {
    Mat4 local = local_matrix(nodes[i], rot[i], tr[i]);
    world[i] = nodes[i].parent >= 0 ? multiply(local, world[static_cast<std::size_t>(nodes[i].parent)]) : local;
  }
  return world;
}

}  // namespace olcore
