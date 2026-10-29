#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace olcore {

// One saved allocation (an object or a raw buffer) in a Carrera store.
struct StoreAllocation {
  std::uint32_t original_address = 0;  // address in the exporting process
  std::size_t offset = 0;              // absolute offset of the bytes in the file
  std::size_t size = 0;
  int class_index = -1;  // into StoreFile::classes(), -1 for raw data
  int name = -1;         // string index of the object's name, -1 if none
  int tag = -1;          // string index describing a raw buffer ("clip samples")
};

struct StoreClass {
  std::string name;  // "class Carrera::AnimClip"
  std::size_t instance_size = 0;
};

// Container reader for the serialized object stores used by golfer models
// (.SKL) and animation clips (.CLP); see docs/formats/carrera-store.md.
// It exposes the allocations, strings and class table; interpreting the
// objects is up to the caller.
class StoreFile {
public:
  // Throws ReadError if the data is not a store or a table is inconsistent.
  explicit StoreFile(std::vector<std::uint8_t> data);

  static bool looks_like(const std::vector<std::uint8_t>& data);

  const std::vector<StoreAllocation>& allocations() const { return allocations_; }
  const std::vector<StoreClass>& classes() const { return classes_; }
  const std::vector<std::string>& strings() const { return strings_; }
  const std::vector<std::uint8_t>& data() const { return data_; }

  const std::string& string(int index) const;
  std::string class_name(const StoreAllocation& a) const;

  // First allocation whose object name, or failing that whose tag, matches.
  const StoreAllocation* find(const std::string& name) const;
  // The allocation that holds a file offset, as stored in pointer fields.
  const StoreAllocation* at_offset(std::size_t offset) const;

private:
  std::vector<std::uint8_t> data_;
  std::vector<StoreAllocation> allocations_;
  std::vector<StoreClass> classes_;
  std::vector<std::string> strings_;
};

}  // namespace olcore
