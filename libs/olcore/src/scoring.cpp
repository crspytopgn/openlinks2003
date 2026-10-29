#include "olcore/scoring.hpp"

#include <stdexcept>

namespace olcore {

std::string score_name(int strokes, int par) {
  if (strokes == 1) {
    return "Hole in one";
  }
  switch (strokes - par) {
    case -3: return "Albatross";
    case -2: return "Eagle";
    case -1: return "Birdie";
    case 0: return "Par";
    case 1: return "Bogey";
    case 2: return "Double bogey";
    case 3: return "Triple bogey";
    default: break;
  }
  return format_to_par(strokes - par);
}

Scorecard::Scorecard(std::vector<int> hole_pars) : pars(std::move(hole_pars)), strokes(pars.size(), 0) {}

void Scorecard::record(std::size_t hole, int hole_strokes) {
  if (hole >= strokes.size()) {
    throw std::out_of_range("no such hole");
  }
  strokes[hole] = hole_strokes;
}

int Scorecard::total_strokes() const {
  int total = 0;
  for (int s : strokes) {
    total += s;
  }
  return total;
}

int Scorecard::holes_played() const {
  int n = 0;
  for (int s : strokes) {
    n += s > 0 ? 1 : 0;
  }
  return n;
}

int Scorecard::to_par() const {
  int diff = 0;
  for (std::size_t i = 0; i < strokes.size(); ++i) {
    if (strokes[i] > 0) {
      diff += strokes[i] - pars[i];
    }
  }
  return diff;
}

std::string format_to_par(int to_par) {
  if (to_par == 0) {
    return "E";
  }
  return (to_par > 0 ? "+" : "") + std::to_string(to_par);
}

}  // namespace olcore
