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

// --- Handicaps ----------------------------------------------------------
// A simplified World Handicap System. Links courses carry a stroke index per
// hole but no course or slope rating, so par stands in for the course rating
// and every course has the standard slope (113). Handicap indexes and score
// differentials are kept in tenths of a stroke (123 is 12.3), so the C++ and
// GDScript sides round the same way.

constexpr int kNoHandicap = -1000;           // no index yet
constexpr int kMaxHandicapTenths = 540;      // 54.0
constexpr int kMinHandicapTenths = -100;     // +10.0
constexpr std::size_t kHandicapRounds = 20;  // the index uses the most recent 20

// a / b rounded to the nearest whole number, halves away from zero. b > 0.
int div_round(int a, int b);

// The holes in play ranked by difficulty, 1 for the hardest: by the course's
// stroke index (1 to 18), so a nine keeps the order of the 18. Holes without
// one (0) rank after the rest, in hole order.
std::vector<int> stroke_ranks(const std::vector<int>& stroke_index);

// Strokes a playing handicap gets on each hole, from the hole ranks. A
// handicap of 12 over 9 holes gives two strokes on the three hardest and one
// on the rest. A plus handicap (negative) gives strokes back, on the easiest
// holes first.
std::vector<int> handicap_strokes(int handicap, const std::vector<int>& ranks);

// Gross minus the strokes received on each played hole, never below 1 (so a
// net score still marks a played hole); 0 where the hole isn't played.
std::vector<int> net_scores(const std::vector<int>& gross, const std::vector<int>& received);

// Playing handicap for `holes` holes at `allowance_percent` of the index
// (95 for stroke play), rounded to the nearest stroke.
int playing_handicap(int index_tenths, int holes, int allowance_percent);

// Adjusted gross score for handicap purposes: each hole capped at net double
// bogey (par + 2 + strokes received). Without an index, at par + 5.
int adjusted_gross(const Scorecard& card, const std::vector<int>& received, bool has_index);

// Score differential in tenths: adjusted gross minus par, scaled up to 18
// holes for a nine.
int score_differential(int adjusted_gross, int par, int holes);

// How many of the lowest differentials the index averages, with `rounds`
// rounds among the most recent 20 (the WHS table); 0 below three.
std::size_t handicap_rounds_used(std::size_t rounds);

// Handicap index in tenths from score differentials, oldest first: the WHS
// table picks the lowest 1 to 8 of the most recent 20 and adjusts by up to
// -2.0. kNoHandicap with fewer than three rounds. Capped at 54.0.
int handicap_index(const std::vector<int>& differentials);

// "12.3", "+1.4", "0.0"; "-" without an index.
std::string format_handicap(int index_tenths);

}  // namespace olcore
