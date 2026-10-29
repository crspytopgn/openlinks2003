#include "olcore/carrera_store.hpp"

#include "olcore/binary_reader.hpp"

namespace olcore {

namespace {

constexpr std::uint32_t kSectionMagic = 0xdeadbeef;
constexpr int kSectionCount = 7;
// Sections whose element count times element size isn't the whole story are
// followed by up to three bytes of padding.
constexpr std::size_t kMaxPadding = 3;

struct Section {
  std::uint32_t count = 0;
  std::uint32_t element_size = 0;
  std::size_t body = 0;
};

enum SectionId { kHeader, kAllocations, kRanges, kFlags, kStringTable, kStringPool, kClasses };

}  // namespace

bool StoreFile::looks_like(const std::vector<std::uint8_t>& data) {
  return data.size() >= 16 && data[0] == 0xef && data[1] == 0xbe && data[2] == 0xad && data[3] == 0xde;
}

StoreFile::StoreFile(std::vector<std::uint8_t> data) : data_(std::move(data)) {
  if (!looks_like(data_)) {
    throw ReadError("not a Carrera store");
  }
  BinaryReader r(data_);
  Section sec[kSectionCount];
  for (int i = 0; i < kSectionCount; ++i) {
    std::size_t start = r.tell();
    std::size_t pad = 0;
    while (true) {
      r.seek(start + pad);
      if (r.remaining() >= 4 && r.u32() == kSectionMagic) break;
      if (++pad > kMaxPadding) throw ReadError("store section " + std::to_string(i) + " not found");
    }
    sec[i].count = r.u32();
    r.skip(4);  // version
    sec[i].element_size = r.u32();
    sec[i].body = r.tell();
    std::size_t bytes = static_cast<std::size_t>(sec[i].count) * sec[i].element_size;
    if (bytes > r.remaining()) throw ReadError("store section " + std::to_string(i) + " runs past the end");
    r.skip(bytes);
  }
  if (sec[kAllocations].element_size != 44 || sec[kStringTable].element_size != 8 ||
      sec[kClasses].element_size != 20) {
    throw ReadError("unexpected store table layout");
  }

  for (std::uint32_t i = 0; i < sec[kStringTable].count; ++i) {
    r.seek(sec[kStringTable].body + i * 8);
    std::uint32_t length = r.u32();
    std::uint32_t offset = r.u32();
    if (length == 0 || offset + length > sec[kStringPool].count) throw ReadError("store string out of range");
    const char* s = reinterpret_cast<const char*>(data_.data() + sec[kStringPool].body + offset);
    strings_.emplace_back(s, length - 1);  // length includes the NUL
  }

  for (std::uint32_t i = 0; i < sec[kClasses].count; ++i) {
    r.seek(sec[kClasses].body + i * 20);
    StoreClass c;
    c.name = string(r.i32());
    c.instance_size = r.u32();
    classes_.push_back(std::move(c));
  }

  for (std::uint32_t i = 0; i < sec[kAllocations].count; ++i) {
    r.seek(sec[kAllocations].body + i * 44);
    StoreAllocation a;
    a.original_address = r.u32();
    a.offset = r.u32();
    a.size = r.u32();
    a.class_index = r.i32();
    a.name = r.i32();
    r.skip(16);
    a.tag = r.i32();
    if (a.offset + a.size > data_.size()) throw ReadError("store allocation " + std::to_string(i) + " out of range");
    if (a.class_index >= static_cast<int>(classes_.size()) || a.name >= static_cast<int>(strings_.size()) ||
        a.tag >= static_cast<int>(strings_.size())) {
      throw ReadError("store allocation " + std::to_string(i) + " has a bad index");
    }
    allocations_.push_back(a);
  }
}

const std::string& StoreFile::string(int index) const {
  static const std::string empty;
  if (index < 0 || index >= static_cast<int>(strings_.size())) return empty;
  return strings_[static_cast<std::size_t>(index)];
}

std::string StoreFile::class_name(const StoreAllocation& a) const {
  return a.class_index < 0 ? std::string() : classes_[static_cast<std::size_t>(a.class_index)].name;
}

const StoreAllocation* StoreFile::find(const std::string& name) const {
  for (const auto& a : allocations_) {
    if (a.name >= 0 && string(a.name) == name) return &a;
  }
  for (const auto& a : allocations_) {
    if (a.tag >= 0 && string(a.tag) == name) return &a;
  }
  return nullptr;
}

const StoreAllocation* StoreFile::at_offset(std::size_t offset) const {
  for (const auto& a : allocations_) {
    if (offset >= a.offset && offset < a.offset + (a.size ? a.size : 1)) return &a;
  }
  return nullptr;
}

}  // namespace olcore
