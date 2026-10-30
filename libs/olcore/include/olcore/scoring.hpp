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

// --- Game modes ---------------------------------------------------------
// Hole scores are per-hole strokes as on a Scorecard: 0 means not played.

// Stableford points for one hole: 2 for par, one more for each stroke under
// and one fewer for each stroke over, never below 0. An unplayed hole scores 0.
int stableford_points(int strokes, int par);
int stableford_total(const Scorecard& card);

// Best ball (four-ball): the team's lowest score on each hole, from the
// players who have played it; 0 where none has.
std::vector<int> best_ball(const std::vector<std::vector<int>>& team_strokes);

// Skins: each hole is worth one skin, won by the outright lowest score. A tie
// carries the skin over to the next hole. Only holes every player has played
// count, in order, stopping at the first that isn't complete.
struct SkinsResult {
  std::vector<int> skins;        // per player
  std::vector<int> hole_winner;  // per hole: player index, -1 tied, -2 not complete
  int carried = 0;               // skins riding on the next hole
};
SkinsResult skins(const std::vector<std::vector<int>>& strokes);

// Match play between two sides, hole by hole, from side A's point of view.
struct MatchStatus {
  int up = 0;         // holes A is up (negative: B is up)
  int played = 0;     // holes both sides have played, from the first
  int remaining = 0;  // holes left in the round
  bool finished = false;  // decided: the lead is bigger than the holes left, or none left
  bool dormie = false;    // not finished, and the lead equals the holes left
};
MatchStatus match_status(const std::vector<int>& a, const std::vector<int>& b);

// "All square", "2 up", "2 up (dormie)", "3 & 2", "1 up" when won on the last
// hole, "Halved". The caller names the side that leads (the sign of `up`).
std::string match_text(const MatchStatus& status);

}  // namespace olcore
