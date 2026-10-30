#include "olcore/scoring.hpp"

#include <algorithm>
#include <cstdlib>
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

int stableford_points(int strokes, int par) {
  if (strokes <= 0) {
    return 0;
  }
  return std::max(0, 2 + par - strokes);
}

int stableford_total(const Scorecard& card) {
  int total = 0;
  for (std::size_t i = 0; i < card.strokes.size(); ++i) {
    total += stableford_points(card.strokes[i], card.pars[i]);
  }
  return total;
}

std::vector<int> best_ball(const std::vector<std::vector<int>>& team_strokes) {
  std::size_t holes = 0;
  for (const auto& card : team_strokes) {
    holes = std::max(holes, card.size());
  }
  std::vector<int> best(holes, 0);
  for (const auto& card : team_strokes) {
    for (std::size_t h = 0; h < card.size(); ++h) {
      if (card[h] > 0 && (best[h] == 0 || card[h] < best[h])) {
        best[h] = card[h];
      }
    }
  }
  return best;
}

SkinsResult skins(const std::vector<std::vector<int>>& strokes) {
  SkinsResult r;
  r.skins.assign(strokes.size(), 0);
  std::size_t holes = strokes.empty() ? 0 : strokes[0].size();
  r.hole_winner.assign(holes, -2);
  int pot = 0;
  for (std::size_t h = 0; h < holes; ++h) {
    int low = 0;
    int winner = -1;
    bool complete = true;
    for (std::size_t p = 0; p < strokes.size(); ++p) {
      int s = h < strokes[p].size() ? strokes[p][h] : 0;
      if (s <= 0) {
        complete = false;
        break;
      }
      if (low == 0 || s < low) {
        low = s;
        winner = static_cast<int>(p);
      } else if (s == low) {
        winner = -1;
      }
    }
    if (!complete) {
      break;
    }
    ++pot;
    r.hole_winner[h] = winner;
    if (winner >= 0) {
      r.skins[static_cast<std::size_t>(winner)] += pot;
      pot = 0;
    }
  }
  r.carried = pot;
  return r;
}

MatchStatus match_status(const std::vector<int>& a, const std::vector<int>& b) {
  MatchStatus m;
  std::size_t holes = std::min(a.size(), b.size());
  std::size_t h = 0;
  for (; h < holes; ++h) {
    if (a[h] <= 0 || b[h] <= 0) {
      break;
    }
    if (a[h] < b[h]) {
      ++m.up;
    } else if (b[h] < a[h]) {
      --m.up;
    }
    ++m.played;
    if (std::abs(m.up) > static_cast<int>(holes - h - 1)) {
      ++h;
      break;
    }
  }
  m.remaining = static_cast<int>(holes) - m.played;
  m.finished = std::abs(m.up) > m.remaining || m.remaining == 0;
  m.dormie = !m.finished && m.up != 0 && std::abs(m.up) == m.remaining;
  return m;
}

std::string match_text(const MatchStatus& status) {
  int lead = std::abs(status.up);
  if (lead == 0) {
    return status.finished ? "Halved" : "All square";
  }
  if (status.finished && status.remaining > 0) {
    return std::to_string(lead) + " & " + std::to_string(status.remaining);
  }
  std::string text = std::to_string(lead) + " up";
  return status.dormie ? text + " (dormie)" : text;
}

}  // namespace olcore
