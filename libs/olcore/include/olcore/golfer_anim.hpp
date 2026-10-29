#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "olcore/carrera_store.hpp"

namespace olcore {

// Node and channel names are matched by CRC-32 (the zlib/PNG polynomial) of
// the name, e.g. name_hash("Root") or name_hash("RootrotateX").
std::uint32_t name_hash(const std::string& name);

enum class AnimAttribute { TranslateX, TranslateY, TranslateZ, RotateX, RotateY, RotateZ, Unknown };

struct AnimChannel {
  std::uint32_t node_hash = 0;  // name_hash(node name)
  AnimAttribute attribute = AnimAttribute::Unknown;
};

// One Carrera::AnimClip from a .CLP file (docs/formats/carrera-store.md).
// Values are in feet (translation) and radians (rotation), 30 frames a second.
struct AnimClip {
  static constexpr float kFramesPerSecond = 30.0f;
  static constexpr float kSampleScale = 1.0f / 2048.0f;

  std::string name;
  std::uint32_t frame_count = 0;
  std::size_t dynamic_count = 0;  // channels [0, dynamic_count) change per frame
  std::vector<AnimChannel> channels;
  // Frame 0 for every channel, then frames 1.. for the dynamic channels.
  std::vector<std::int16_t> samples;

  float value(std::size_t channel, std::size_t frame) const;
};

// Every clip in the store that has channels. Throws ReadError if a clip's
// tables don't fit the file.
std::vector<AnimClip> read_anim_clips(const StoreFile& store);

// A joint or transform from a .SKL model.
struct SkeletonNode {
  std::string name;
  std::uint32_t name_hash = 0;
  int parent = -1;  // index into Skeleton::nodes, -1 for a root
  bool is_joint = false;
  std::array<float, 3> translate{};
  std::array<float, 3> rotate{};                    // radians, applied X then Y then Z
  std::array<float, 4> orient{0.0f, 0.0f, 0.0f, 1.0f};  // joint orient quaternion (x, y, z, w)
};

// 4x4 matrix, row-major, row-vector convention (p' = p * M): the translation
// is in elements 12, 13, 14.
using Mat4 = std::array<float, 16>;

struct Skeleton {
  std::vector<SkeletonNode> nodes;  // parents come before their children

  int find(std::uint32_t hash) const;
  int find(const std::string& name) const { return find(name_hash(name)); }

  // local = R(rotate) * R(orient), then translate.
  static Mat4 local_matrix(const SkeletonNode& node, const std::array<float, 3>& rotate,
                           const std::array<float, 3>& translate);

  // World matrices of every node, posed by `clip` at `frame` (rest pose if
  // clip is null). Channels for nodes the skeleton lacks are ignored.
  std::vector<Mat4> pose(const AnimClip* clip, std::size_t frame) const;
};

Skeleton read_skeleton(const StoreFile& store);

Mat4 multiply(const Mat4& a, const Mat4& b);

}  // namespace olcore
