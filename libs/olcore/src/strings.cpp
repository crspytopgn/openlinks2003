#include "olcore/strings.hpp"

namespace olcore {

namespace {
char lower(char c) { return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c; }
}  // namespace

bool iequals(const std::string& a, const std::string& b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); ++i) {
    if (lower(a[i]) != lower(b[i])) return false;
  }
  return true;
}

std::string to_lower(std::string s) {
  for (char& c : s) c = lower(c);
  return s;
}

}  // namespace olcore
