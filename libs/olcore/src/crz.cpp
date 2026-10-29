#include "olcore/crz.hpp"

#include <algorithm>
#include <cstring>
#include <map>

#include "olcore/binary_reader.hpp"
#include "olcore/inflate.hpp"
#include "olcore/strings.hpp"

namespace olcore {

namespace {

constexpr std::size_t kHeaderSize = 16;
constexpr std::size_t kRecordSize = 64;
constexpr std::uint32_t kMethodStored = 0;
constexpr std::uint32_t kMethodZlib = 2;

// The archive header and directory use 32 rounds; locked entries use 4.
constexpr unsigned kDirectoryRounds = 32;
constexpr unsigned kEntryRounds = 4;
constexpr std::size_t kKeyLength = 7;

// The `copyright` entry carries the key for the course's other locked
// entries at this offset.
constexpr const char* kCopyrightEntry = "copyright";
constexpr std::size_t kCourseKeyOffset = 0x2c;

// Words 5 to 7 of the P table are hexadecimal digits of pi (as in many
// ciphers of the era), which makes the table easy to find.
constexpr std::uint32_t kPiAnchor[3] = {0x299f31d0, 0x082efa98, 0xec4e6c89};
constexpr std::size_t kAnchorWord = 5;
constexpr std::size_t kSTableGap = 128;  // S follows P directly

std::uint32_t ld32(const std::uint8_t* b) {
  return std::uint32_t(b[0]) | std::uint32_t(b[1]) << 8 | std::uint32_t(b[2]) << 16 | std::uint32_t(b[3]) << 24;
}

bool valid_header(const std::uint8_t* h, std::size_t file_size) {
  if (std::memcmp(h, "ARC0", 4) != 0) return false;
  std::uint32_t count = ld32(h + 8), dir = ld32(h + 12);
  if (file_size == 0) return true;
  return ld32(h + 4) == file_size && dir <= file_size && count <= (file_size - dir) / kRecordSize;
}

}  // namespace

std::optional<BunkyTables> find_bunky_tables(const std::vector<std::uint8_t>& exe) {
  std::uint8_t anchor[12];
  for (int i = 0; i < 3; ++i) {
    for (int b = 0; b < 4; ++b) anchor[4 * i + b] = std::uint8_t(kPiAnchor[i] >> (8 * b));
  }
  const std::size_t need = 4 * 32 + 4 * 1022;
  for (std::size_t at = 4 * kAnchorWord; at + sizeof anchor <= exe.size(); ++at) {
    if (std::memcmp(&exe[at], anchor, sizeof anchor) != 0) continue;
    std::size_t start = at - 4 * kAnchorWord;
    if (start + need > exe.size()) break;
    BunkyTables t;
    for (std::size_t i = 0; i < 32; ++i) t.p[i] = ld32(&exe[start + 4 * i]);
    for (std::size_t i = 0; i < 1022; ++i) t.s[i] = ld32(&exe[start + kSTableGap + 4 * i]);
    return t;
  }
  return std::nullopt;
}

// Tries every candidate key in the executable and returns the first that
// `accept` likes.
template <typename Accept>
std::optional<GameKeys> search_keys(const std::vector<std::uint8_t>& exe, Accept accept) {
  auto tables = find_bunky_tables(exe);
  if (!tables) return std::nullopt;
  // The game passes the 64-bit key to its archive reader as two pushed
  // 32-bit immediates (high word first), so every such pair is a candidate.
  // The game opens archives from many places, so the real key is pushed far
  // more often than any other pair; trying the most frequent pairs first
  // usually finds it at once.
  std::map<std::uint64_t, std::size_t> counts;
  std::vector<std::uint64_t> order;
  for (std::size_t i = 0; i + 10 <= exe.size(); ++i) {
    if (exe[i] != 0x68 || exe[i + 5] != 0x68) continue;
    std::uint64_t pair = std::uint64_t(ld32(&exe[i + 6])) | std::uint64_t(ld32(&exe[i + 1])) << 32;
    if (counts[pair]++ == 0) order.push_back(pair);
  }
  std::stable_sort(order.begin(), order.end(),
                   [&](std::uint64_t a, std::uint64_t b) { return counts[a] > counts[b]; });
  for (std::uint64_t pair : order) {
    GameKeys k;
    k.tables = *tables;
    for (int b = 0; b < 8; ++b) k.archive_key[b] = std::uint8_t(pair >> (8 * b));
    if (accept(k)) return k;
  }
  return std::nullopt;
}

std::optional<GameKeys> find_game_keys(const std::vector<std::uint8_t>& exe, const std::uint8_t* header) {
  return search_keys(exe, [&](const GameKeys& k) {
    std::uint8_t h[kHeaderSize];
    std::memcpy(h, header, kHeaderSize);
    BunkyCipher(k.tables, k.archive_key.data(), k.archive_key.size(), kDirectoryRounds).decrypt(h, kHeaderSize);
    return valid_header(h, 0);
  });
}

std::optional<GameKeys> find_game_keys(const std::vector<std::uint8_t>& exe, const std::vector<std::uint8_t>& archive) {
  if (archive.size() < kHeaderSize) return std::nullopt;
  if (!CrzArchive::is_plain(archive.data())) return find_game_keys(exe, archive.data());
  if (!valid_header(archive.data(), archive.size())) return std::nullopt;
  const std::size_t dir = ld32(archive.data() + 12);
  if (ld32(archive.data() + 8) == 0) return std::nullopt;
  return search_keys(exe, [&](const GameKeys& k) {
    std::uint8_t rec[kRecordSize];
    std::memcpy(rec, &archive[dir], kRecordSize);
    BunkyCipher(k.tables, k.archive_key.data(), k.archive_key.size(), kDirectoryRounds).decrypt(rec, kRecordSize);
    if (ld32(rec) != 0 || rec[4] == 0) return false;
    // A printable, NUL-terminated name that points inside the file.
    std::size_t len = 0;
    while (len < 32 && rec[4 + len] != 0) {
      if (rec[4 + len] < 0x20 || rec[4 + len] > 0x7e) return false;
      ++len;
    }
    if (len == 32) return false;
    const std::uint32_t offset = ld32(rec + 36), packed = ld32(rec + 40);
    return offset <= archive.size() && packed <= archive.size() - offset;
  });
}

bool CrzArchive::is_plain(const std::uint8_t* header) { return std::memcmp(header, "ARC0", 4) == 0; }

std::vector<CrzEntry> CrzArchive::parse_directory(const std::vector<std::uint8_t>& d, std::uint32_t count) const {
  BinaryReader r(d);
  std::vector<CrzEntry> out;
  out.reserve(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    CrzEntry e;
    if (r.u32() != 0) throw ReadError("course directory is unreadable");
    e.name = r.fixed_string(32);
    e.offset = r.u32();
    e.packed_size = r.u32();
    e.size = r.u32();
    e.method = r.u32();
    e.checksum = r.u32();
    e.locked = (r.u32() & 1) != 0;
    r.u32();  // always 0
    if (e.offset > data_.size() || e.packed_size > data_.size() - e.offset) {
      throw ReadError("course entry '" + e.name + "' runs past end of file");
    }
    out.push_back(std::move(e));
  }
  return out;
}

CrzArchive::CrzArchive(std::vector<std::uint8_t> data, const GameKeys* keys) : data_(std::move(data)) {
  if (data_.size() < kHeaderSize) throw ReadError("course archive is too short");
  if (keys) {
    tables_ = keys->tables;
    archive_key_ = keys->archive_key;
  }
  std::uint8_t h[kHeaderSize];
  std::memcpy(h, data_.data(), kHeaderSize);
  const bool locked = !is_plain(h);
  if (locked) {
    if (!keys) throw ReadError("course archive is locked and no game keys were given");
    BunkyCipher(*tables_, archive_key_.data(), archive_key_.size(), kDirectoryRounds).decrypt(h, kHeaderSize);
  }
  if (!valid_header(h, data_.size())) throw ReadError("not a course archive, or the wrong key");

  std::uint32_t count = ld32(h + 8), dir = ld32(h + 12);
  std::vector<std::uint8_t> d(data_.begin() + dir, data_.begin() + dir + std::size_t(count) * kRecordSize);
  if (locked) {
    BunkyCipher(*tables_, archive_key_.data(), archive_key_.size(), kDirectoryRounds).decrypt(d.data(), d.size());
    entries_ = parse_directory(d, count);
  } else {
    // Some converted courses have a plain header but a locked directory.
    try {
      entries_ = parse_directory(d, count);
    } catch (const ReadError&) {
      if (!keys) throw;
      BunkyCipher(*tables_, archive_key_.data(), archive_key_.size(), kDirectoryRounds).decrypt(d.data(), d.size());
      entries_ = parse_directory(d, count);
    }
  }

  if (auto c = find(kCopyrightEntry)) {
    if (!entries_[*c].locked || tables_) {
      auto bytes = unpack(entries_[*c], &archive_key_);
      if (bytes.size() >= kCourseKeyOffset + 8) {
        std::array<std::uint8_t, 8> k{};
        std::memcpy(k.data(), &bytes[kCourseKeyOffset], 8);
        course_key_ = k;
      }
    }
  }
}

CrzArchive CrzArchive::from_file(const std::string& path, const GameKeys* keys) {
  return CrzArchive(BinaryReader::from_file(path).data(), keys);
}

std::optional<std::size_t> CrzArchive::find(const std::string& name) const {
  for (std::size_t i = 0; i < entries_.size(); ++i) {
    if (iequals(entries_[i].name, name)) return i;
  }
  return std::nullopt;
}

std::vector<std::uint8_t> CrzArchive::unpack(const CrzEntry& e, const std::array<std::uint8_t, 8>* key) const {
  std::vector<std::uint8_t> packed(data_.begin() + e.offset, data_.begin() + e.offset + e.packed_size);
  if (e.locked) {
    if (!tables_ || !key) throw ReadError("course entry '" + e.name + "' is locked and no key is available");
    BunkyCipher(*tables_, key->data(), kKeyLength, kEntryRounds).decrypt(packed.data(), packed.size());
  }
  std::vector<std::uint8_t> out;
  if (e.method == kMethodZlib) {
    out = zlib_decompress(packed);
  } else if (e.method == kMethodStored) {
    out = std::move(packed);
  } else {
    throw ReadError("course entry '" + e.name + "' uses unknown method " + std::to_string(e.method));
  }
  if (out.size() != e.size) throw ReadError("course entry '" + e.name + "' has wrong unpacked size");
  if (e.checksum && adler32(out.data(), out.size()) != e.checksum) {
    throw ReadError("course entry '" + e.name + "' fails its checksum");
  }
  return out;
}

std::vector<std::uint8_t> CrzArchive::read(std::size_t i) const {
  const CrzEntry& e = entries_.at(i);
  const bool is_copyright = iequals(e.name, kCopyrightEntry);
  const std::array<std::uint8_t, 8>* key = is_copyright ? &archive_key_ : (course_key_ ? &*course_key_ : nullptr);
  return unpack(e, key);
}

std::vector<std::uint8_t> CrzArchive::read(const std::string& name) const {
  auto i = find(name);
  if (!i) throw ReadError("course archive has no entry '" + name + "'");
  return read(*i);
}

}  // namespace olcore
