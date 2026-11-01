// olcalibrate: measures how computer golfers' swing errors turn into tour
// statistics, through the physics on flat ground, and prints the calibration
// tables used by libs/olcore/src/opponent.cpp.
//
//   olcalibrate                  standard physics tables, then each skill
//                                level's measured numbers
//   olcalibrate <game exe>       also Links 2003's computer ratings tables and
//                                the levels with the game's physics (the exe
//                                is read, never copied)

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <optional>
#include <string>
#include <vector>

#include "olcore/links_flight.hpp"
#include "olcore/links_launch.hpp"
#include "olcore/opponent.hpp"
#include "olcore/shot.hpp"
#include "olcore/swing.hpp"

using namespace olcore;

namespace {

constexpr double kYd = 1.0936133;
constexpr double kFt = 3.2808399;
constexpr double kHalfFairwayM = 15.0 / kYd;  // a 30-yard fairway
constexpr double kPuttPastM = 0.35;           // as the game's planner
constexpr int kN = 4000;

const FlatTerrain kFairway(Surface::Fairway);
const FlatTerrain kGreen(Surface::Green);

// One way of hitting a shot: the standard physics, the Links physics with
// our swing errors, or the Links physics with the game's own computer misses.
struct Hitter {
  const LinksAero* aero = nullptr;
  const LinksClubTable* clubs = nullptr;
  const LinksGolferRatings* ratings = nullptr;  // classic
  double face_per_accuracy_deg = kLinksFaceDegPerAccuracy;          // Links, our errors
  mutable LinksRand rng{2003};

  double scale(ShotKind kind) const { return clubs != nullptr && ratings == nullptr ? links_error_scale(kind) : 1.0; }

  BallParams params() const {
    BallParams p;
    p.links = aero;
    return p;
  }

  // Club i of the standard set (0 = driver; the last is the putter).
  ShotResult hit(int club, SwingInput in, Surface lie, double to_hole_m, const ShotOptions& opt,
                 const Terrain& t) const {
    const Club& c = standard_clubs()[static_cast<std::size_t>(club)];
    if (clubs == nullptr) {
      return simulate_shot(launch_from_swing(c, in, lie), params(), t, opt);
    }
    LinksStrike s;
    s.aim = in.aim_deg * 3.14159265358979 / 180.0;
    if (c.putter) {
      s.club = kLinksPutter;
      s.power = 25.0 * std::clamp(in.power, 0.0, 1.0);
      if (ratings != nullptr) {
        LinksComputerSwing w;
        w.power = s.power;
        links_computer_putt_miss(w, *ratings, links_ground_class(lie), to_hole_m * kFt, rng);
        s.power = w.power;
        s.path_error = w.path_deg * 3.14159265358979 / 180.0;
      }
      return simulate_shot(links_launch_state(*clubs, s), params(), t, opt);
    }
    // Standard club i as the game numbers it (LinksLaunch.CLUB_INDEX).
    static const int kIndex[] = {0, 1, 3, 4, 10, 11, 12, 13, 14, 15, 16, 17, 18};
    s.club = kIndex[club];
    static const double kMax[] = {112, 108, 106, 104, 102, 100, 98, 98, 96, 94, 92, 90, 88, 86, 84, 82, 80, 80, 80};
    double rating = kMax[s.club];
    double share = std::clamp(in.power, 0.0, 1.0);
    s.power = rating * share;
    LinksSurface ls = links_surface(links_ground_class(lie));
    if (ratings != nullptr) {
      LinksComputerSwing w;
      w.power = 100.0 * share;
      links_computer_miss(w, *ratings, s.club, lie == Surface::Tee, false, ls.ground_class, to_hole_m * kFt, rng);
      s.power = w.power * rating / 100.0;
      s.face_error = w.face_deg * 3.14159265358979 / 180.0;
      s.path_error = w.path_deg * 3.14159265358979 / 180.0;
    } else {
      s.face_error = -face_per_accuracy_deg * 3.14159265358979 / 180.0 * std::clamp(in.accuracy, -1.0, 1.0);
    }
    links_apply_lie(s, ls);
    return simulate_shot(links_launch_state(*clubs, s), params(), t, opt);
  }
};

int putter() { return static_cast<int>(standard_clubs().size()) - 1; }

double carry_total(const Hitter& h, int club, double power, Surface lie) {
  return h.hit(club, {power, 0, 0}, lie, 0, {}, kFairway).total_m;
}

// The power that sends `club` `d` metres.
double plan_power(const Hitter& h, int club, double d, Surface lie) {
  double lo = 0.02, hi = 1.0;
  for (int i = 0; i < 40; ++i) {
    double m = 0.5 * (lo + hi);
    (carry_total(h, club, m, lie) < d ? lo : hi) = m;
  }
  return 0.5 * (lo + hi);
}

struct Drive {
  double fairways_pct;
  double yards;
};

Drive drive(const Hitter& h, const GolferProfile& g) {
  OpponentRng rng(11);
  int in = 0;
  double sum = 0;
  for (int i = 0; i < kN; ++i) {
    SwingInput s = execute_shot({h.clubs != nullptr ? g.links_strength : g.strength, 0, 0}, ShotKind::Drive, g, h.scale(ShotKind::Drive), rng);
    ShotResult r = h.hit(0, s, Surface::Tee, 400, {}, kFairway);
    if (std::fabs(r.rest.x) < kHalfFairwayM) ++in;
    sum += r.rest.z;
  }
  return {100.0 * in / kN, sum / kN * kYd};
}

// Average distance from the hole (ft) after a shot from `yards` in the fairway.
double approach(const Hitter& h, const GolferProfile& g, double yards) {
  double d = yards / kYd;
  int club = 0;
  for (int i = putter() - 1; i >= 0; --i) {
    if (carry_total(h, i, 1.0, Surface::Fairway) >= d) {
      club = i;
      break;
    }
  }
  double power = plan_power(h, club, d, Surface::Fairway);
  ShotKind kind = shot_kind(false, false, false, d);
  OpponentRng rng(23);
  double sum = 0;
  int n = kN / 2;
  for (int i = 0; i < n; ++i) {
    SwingInput s = execute_shot({power, 0, 0}, kind, g, h.scale(kind), rng);
    ShotResult r = h.hit(club, s, Surface::Fairway, d, {}, kFairway);
    sum += std::hypot(r.rest.x, r.rest.z - d);
  }
  return sum / n * kFt;
}

double putt_power(const Hitter& h, double d) {
  double lo = 0.005, hi = 1.0;
  for (int i = 0; i < 40; ++i) {
    double m = 0.5 * (lo + hi);
    Hitter perfect = h;
    perfect.ratings = nullptr;
    (perfect.hit(putter(), {m, 0, 0}, Surface::Green, d, {}, kGreen).total_m < d + kPuttPastM ? lo : hi) = m;
  }
  return 0.5 * (lo + hi);
}

// Share of putts holed from `feet` on a flat green.
double holed(const Hitter& h, const GolferProfile& g, double feet) {
  double d = feet / kFt;
  ShotOptions opt;
  opt.has_cup = true;
  opt.cup = {0, 0, d};
  double power = putt_power(h, d);
  OpponentRng rng(37);
  int in = 0;
  int n = kN / 2;
  for (int i = 0; i < n; ++i) {
    SwingInput s = execute_shot({power, 0, 0}, ShotKind::Putt, g, h.scale(ShotKind::Putt), rng);
    if (h.hit(putter(), s, Surface::Green, d, opt, kGreen).outcome == ShotOutcome::Holed) ++in;
  }
  return 100.0 * in / n;
}

// A profile with the given raw errors and no mishits.
GolferProfile raw(double drive, double approach_scale, double chip_scale, double line) {
  GolferProfile g;
  g.shots[0] = {0.17 * drive, drive, 3.5 * drive};
  g.shots[1] = {0.06 * approach_scale, 0.30 * approach_scale, 1.8 * approach_scale};
  g.shots[2] = {0.07 * chip_scale, 0.25 * chip_scale, 2.2 * chip_scale};
  g.shots[3] = {0.025 * line, 0.0, line};
  g.mishit_chance = 0;
  g.strength = 1;
  g.links_strength = 1;
  return g;
}

void print_table(const char* name, std::vector<std::pair<double, double>> rows) {
  std::sort(rows.begin(), rows.end());
  std::printf("%s =", name);
  for (auto& [x, y] : rows) std::printf(" {%.1f, %.3f},", x, y);
  std::printf("\n");
}

void report_levels(const Hitter& h, const char* physics) {
  std::printf("\n%s physics, by level (fairways, drive, approach 100/150/200 yd, chip 20 yd, putts 3/8/20 ft):\n",
              physics);
  for (int l = 0; l < kSkillLevelCount; ++l) {
    GolferStats st = level_stats(static_cast<SkillLevel>(l));
    GolferProfile g = golfer_profile(st);
    Hitter lh = h;
    if (h.ratings != nullptr) {
      // The game's own misses only.
      lh.ratings = &g.links;
      for (auto& e : g.shots) e = {};
      g.mishit_chance = 0;
    }
    Drive dr = drive(lh, g);
    std::printf("  %-15s %4.0f%% %4.0f yd | %4.1f %4.1f %4.1f ft | chip %4.1f ft | %3.0f%% %3.0f%% %3.0f%%   (want %.0f%%, %.0f ft, %.1f ft, %.0f%%)\n",
                skill_name(static_cast<SkillLevel>(l)), dr.fairways_pct, dr.yards, approach(lh, g, 100),
                approach(lh, g, 150), approach(lh, g, 200), approach(lh, g, 20), holed(lh, g, 3), holed(lh, g, 8),
                holed(lh, g, 20), st.fairways_pct, st.approach_ft, st.chip_ft, st.putt8_pct);
  }
}

}  // namespace

int main(int argc, char** argv) {
  Hitter standard;
  std::vector<std::pair<double, double>> fw, ap, ch, pt;
  for (double a = 0.10; a < 0.80; a += 0.05) fw.push_back({drive(standard, raw(a, 1, 1, 1)).fairways_pct, a});
  for (double s = 0.6; s < 3.5; s += 0.2) ap.push_back({approach(standard, raw(0.2, s, 1, 1), 150), s});
  for (double s = 0.6; s < 3.5; s += 0.2) ch.push_back({approach(standard, raw(0.2, 1, s, 1), 20), s});
  for (double l = 1.2; l < 4.0; l += 0.2) pt.push_back({holed(standard, raw(0.2, 1, 1, l), 8), l});
  print_table("kFairways", fw);
  print_table("kApproach", ap);
  print_table("kChip", ch);
  print_table("kPutt8", pt);
  report_levels(standard, "Standard");
  if (argc < 2) return 0;

  std::ifstream f(argv[1], std::ios::binary);
  std::vector<std::uint8_t> exe((std::istreambuf_iterator<char>(f)), {});
  std::optional<LinksAero> aero = find_links_aero(exe);
  std::optional<LinksClubTable> clubs = find_links_clubs(exe);
  if (!aero || !clubs) {
    std::fprintf(stderr, "no Links 2003 physics tables in %s\n", argv[1]);
    return 1;
  }
  Hitter links;
  links.aero = &*aero;
  links.clubs = &*clubs;
  report_levels(links, "Links (our errors)");

  std::vector<std::pair<double, double>> lt, la, lc, lp;
  GolferProfile none = raw(0.2, 1, 1, 1);
  for (int r = 0; r <= 100; r += 5) {
    LinksGolferRatings g;
    g.tee = g.woods = g.long_irons = g.mid_irons = g.short_irons = g.wedges = g.chips = g.long_putts = g.short_putts = r;
    Hitter classic = links;
    classic.ratings = &g;
    GolferProfile perfect = none;
    for (auto& e : perfect.shots) e = {};
    lt.push_back({drive(classic, perfect).fairways_pct, r});
    la.push_back({approach(classic, perfect, 150), r});
    lc.push_back({approach(classic, perfect, 20), r});
    lp.push_back({holed(classic, perfect, 8), r});
  }
  print_table("kLinksTee", lt);
  print_table("kLinksApproach", la);
  print_table("kLinksChip", lc);
  print_table("kLinksPutt8", lp);
  Hitter classic = links;
  LinksGolferRatings dummy;
  classic.ratings = &dummy;  // replaced per level
  report_levels(classic, "Links (the game's own computer misses)");
  return 0;
}
