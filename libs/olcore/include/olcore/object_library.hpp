#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace olcore {

// One object in the Course Designer catalog (OBJECT.LIB). See
// docs/formats/object-library.md for what is known about each field.
struct LibraryObject {
  enum class Kind : std::uint32_t { Billboard = 1, Model = 2 };

  std::string name;  // file name, e.g. "Tall Trees100.btx"
  std::string path;  // relative to the install's Object folder, '\' separated
  Kind kind = Kind::Billboard;
  float params[4] = {};    // first four floats; meaning unclear (see the format notes)
  float size[3] = {};      // billboards: height and width of the largest image in pixels; models: height,
                           // width, depth in inches
  float extra[2] = {};     // last two floats; always 0.5 and 0 on CD3
  std::uint32_t id = 0;    // unique object id, also used by palette sets (.PST)
  std::string top_view;    // e.g. "TopViews\maple18.top", empty if none
  std::uint32_t collision = 0;  // 0 tree (trunk and canopy), 1 solid, 2 none: a guess from the categories
  float shape[6] = {};     // collision shape fractions; see the format notes
};

struct LibraryCategory {
  std::string name;
  std::vector<LibraryObject> objects;
};

struct ObjectLibrary {
  std::uint32_t next_id = 0;  // first u32 of the file; looks like an id or record counter
  std::vector<LibraryCategory> categories;

  const LibraryObject* find(std::uint32_t id) const;
  const LibraryObject* find(const std::string& name) const;  // case-insensitive file name
};

ObjectLibrary read_object_library(const std::vector<std::uint8_t>& data);
ObjectLibrary read_object_library_file(const std::string& path);

}  // namespace olcore
