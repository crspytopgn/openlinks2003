#include "olcore/object_library.hpp"

#include "olcore/binary_reader.hpp"
#include "olcore/strings.hpp"

namespace olcore {

namespace {

// Length-prefixed string: u32 length including the terminating NUL.
std::string counted_string(BinaryReader& r) {
  std::uint32_t n = r.u32();
  if (n == 0) return {};
  if (n > r.remaining()) throw ReadError("string runs past end of OBJECT.LIB");
  return r.fixed_string(n);
}

}  // namespace

ObjectLibrary read_object_library(const std::vector<std::uint8_t>& data) {
  BinaryReader r(data);
  ObjectLibrary lib;
  lib.next_id = r.u32();
  std::uint32_t categories = r.u32();
  for (std::uint32_t c = 0; c < categories; ++c) {
    LibraryCategory cat;
    cat.name = counted_string(r);
    std::uint32_t count = r.u32();
    for (std::uint32_t i = 0; i < count; ++i) {
      LibraryObject o;
      o.name = counted_string(r);
      o.path = counted_string(r);
      o.kind = static_cast<LibraryObject::Kind>(r.u32());
      for (float& f : o.params) f = r.f32();
      for (float& f : o.size) f = r.f32();
      for (float& f : o.extra) f = r.f32();
      o.id = r.u32();
      o.top_view = counted_string(r);
      o.collision = r.u32();
      for (float& f : o.shape) f = r.f32();
      cat.objects.push_back(std::move(o));
    }
    lib.categories.push_back(std::move(cat));
  }
  return lib;
}

ObjectLibrary read_object_library_file(const std::string& path) {
  return read_object_library(BinaryReader::from_file(path).data());
}

const LibraryObject* ObjectLibrary::find(std::uint32_t id) const {
  for (const auto& c : categories) {
    for (const auto& o : c.objects) {
      if (o.id == id) return &o;
    }
  }
  return nullptr;
}

const LibraryObject* ObjectLibrary::find(const std::string& name) const {
  for (const auto& c : categories) {
    for (const auto& o : c.objects) {
      if (iequals(o.name, name)) return &o;
    }
  }
  return nullptr;
}

}  // namespace olcore
