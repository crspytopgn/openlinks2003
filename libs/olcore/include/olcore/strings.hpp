#pragma once

#include <string>

namespace olcore {

// ASCII case-insensitive comparison. The game's file names are 8.3 ASCII on
// disc and the executable refers to them in any case.
bool iequals(const std::string& a, const std::string& b);
std::string to_lower(std::string s);

}  // namespace olcore
