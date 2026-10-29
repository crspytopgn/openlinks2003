#include "olcore/arc0.hpp"

#include <cstring>

#include "olcore/binary_reader.hpp"
#include "olcore/inflate.hpp"
#include "olcore/strings.hpp"

namespace olcore {

namespace {
constexpr std::size_t kHeaderSize = 16;
constexpr std::size_t kRecordSize = 64;
constexpr std::uint32_t kMethodZlib = 2;
}  // namespace

bool Arc0Archive::sniff(const std::uint8_t* data, std::size_t size) {
  return size >= 4 && std::memcmp(data, "ARC0", 4) == 0;
}

Arc0Archive::Arc0Archive(std::vector<std::uint8_t> data) : data_(std::move(data)) {
  if (!sniff(data_.data(), data_.size()) || data_.size() < kHeaderSize) {
    throw ReadError("not an ARC0 archive");
  }
  BinaryReader r(std::vector<std::uint8_t>(data_.begin(), data_.begin() + kHeaderSize));
  r.skip(4);
  r.u32();  // total file size; not checked, a few third-party files may be padded
  std::uint32_t count = r.u32();
  std::uint32_t dir = r.u32();
  if (dir > data_.size() || count > (data_.size() - dir) / kRecordSize) {
    throw ReadError("ARC0 directory runs past end of file");
  }
  BinaryReader d(std::vector<std::uint8_t>(data_.begin() + dir, data_.begin() + dir + count * kRecordSize));
  entries_.reserve(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    Arc0Entry e;
    d.u32();  // always 0
    e.name = d.fixed_string(32);
    e.offset = d.u32();
    e.packed_size = d.u32();
    e.size = d.u32();
    e.method = d.u32();
    e.checksum = d.u32();
    d.skip(8);
    if (e.offset > data_.size() || e.packed_size > data_.size() - e.offset) {
      throw ReadError("ARC0 entry '" + e.name + "' runs past end of file");
    }
    entries_.push_back(std::move(e));
  }
}

Arc0Archive Arc0Archive::from_file(const std::string& path) {
  return Arc0Archive(BinaryReader::from_file(path).data());
}

std::optional<std::size_t> Arc0Archive::find(const std::string& name) const {
  for (std::size_t i = 0; i < entries_.size(); ++i) {
    if (iequals(entries_[i].name, name)) return i;
  }
  return std::nullopt;
}

std::vector<std::uint8_t> Arc0Archive::read(std::size_t i) const {
  const Arc0Entry& e = entries_.at(i);
  const std::uint8_t* p = data_.data() + e.offset;
  std::vector<std::uint8_t> out;
  if (e.method == kMethodZlib) {
    out = zlib_decompress(p, e.packed_size);
  } else {
    throw ReadError("ARC0 entry '" + e.name + "' uses unknown method " + std::to_string(e.method));
  }
  if (out.size() != e.size) throw ReadError("ARC0 entry '" + e.name + "' has wrong unpacked size");
  if (e.checksum && adler32(out.data(), out.size()) != e.checksum) {
    throw ReadError("ARC0 entry '" + e.name + "' fails its checksum");
  }
  return out;
}

std::vector<std::uint8_t> Arc0Archive::read(const std::string& name) const {
  auto i = find(name);
  if (!i) throw ReadError("ARC0 archive has no entry '" + name + "'");
  return read(*i);
}

}  // namespace olcore
