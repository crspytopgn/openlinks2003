#pragma once

#include <string>
#include <vector>

namespace olcore {

// "Birdie", "Bogey", "Hole in one" and so on.
std::string score_name(int strokes, int par);

// Stroke-play card. A hole with 0 strokes has not been played yet.
struct Scorecard {
  std::vector<int> pars;
  std::vector<int> strokes;

  explicit Scorecard(std::vector<int> hole_pars);
  void record(std::size_t hole, int hole_strokes);
  int total_strokes() const;
  int holes_played() const;
  // Strokes relative to par over the holes played so far.
  int to_par() const;
};

// "E", "+3", "-2".
std::string format_to_par(int to_par);

}  // namespace olcore
