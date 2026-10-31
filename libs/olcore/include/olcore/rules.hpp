#pragma once

#include <vector>

#include "olcore/terrain.hpp"

namespace olcore {

// Taking a drop: from water, from an unplayable lie, and free relief from a
// cart path. Links 2003 lets the player drop (one stroke) from water or a
// lie they don't like, gives a free drop on cart paths, and won't let the
// ball be dropped nearer the pin, in a hazard, out of bounds or on the
// green; a ball unplayable in a bunker must be dropped in the sand. The
// drop zones themselves follow the Rules of Golf (rules 16, 17 and 19).
// Godot axes and metres; heights are ignored except for the spots returned.
// The GDScript port is game/scripts/rules/drop_rules.gd; change both together.

constexpr double kClubLength = 1.143;   // a 45-inch driver
constexpr double kDropStep = 0.25;      // metres between spots tried
constexpr double kDropMargin = 1.0;     // extra room back on the line, off the hazard edge
constexpr double kMaxBackOnLine = 200;  // furthest back on the line a drop goes
constexpr double kFreeReliefSearch = 30;  // furthest the nearest point of relief can be

enum class DropReason { Water = 0, Unplayable = 1, FreeRelief = 2 };

enum class DropOption {
  StrokeAndDistance = 0,  // play again from where the last shot was played
  BackOnLine = 1,         // any distance back on the line from the pin through the reference
  Lateral = 2,            // within two club lengths of the reference, no nearer the pin
  FreeDrop = 3,           // within a club length of the nearest point of relief
};

enum class DropCheck {
  Ok = 0,
  OutsideZone,
  NearerPin,
  Hazard,
  OutOfBounds,
  Green,
  NotSand,
  StillOnPath,
};

struct DropZone {
  DropOption option = DropOption::StrokeAndDistance;
  Vec3 reference;    // the ball, where it last went into the water, or the nearest point of relief
  Vec3 direction;    // BackOnLine: unit vector (y = 0) away from the pin
  double radius = 0; // Lateral and FreeDrop: relief area around the reference
  bool in_sand = false;  // the drop must stay in the bunker
  bool found = false;    // `spot` is a legal drop
  Vec3 spot;             // the default drop, on the ground
};

// The penalty strokes a drop for this reason costs.
int drop_penalty(DropReason reason);

// The options, in menu order. Lateral relief from water only where it is a
// red (lateral) hazard.
std::vector<DropOption> drop_options(DropReason reason, bool lateral_water);

// Where a ball that finished in water last crossed into it: the path (flight
// and roll samples, in order) is walked back from the end to the last step
// from dry ground into water, and that step is bisected. The first sample if
// the path never leaves the water.
Vec3 water_entry(const std::vector<Vec3>& path, const Terrain& terrain);

// Free relief for a ball at `ball`: the nearest spot off the cart path, no
// nearer the pin, that isn't in a hazard, out of bounds or on the green.
// Returns false if there isn't one within kFreeReliefSearch.
bool nearest_relief(Vec3 ball, Vec3 pin, const Terrain& terrain, Vec3& point);

// The zone for one option and its default spot. `reference` is the ball for
// an unplayable lie, the water entry for water, and the ball for free relief
// (the zone then starts from nearest_relief()). `previous` is where the last
// shot was played from. `in_sand` makes an unplayable drop stay in the bunker.
DropZone drop_zone(DropOption option, Vec3 reference, Vec3 previous, Vec3 pin, bool in_sand,
                   const Terrain& terrain);

// Whether the ball may be dropped at `spot`.
DropCheck check_drop(const DropZone& zone, Vec3 spot, Vec3 pin, const Terrain& terrain);

// The zone a computer golfer (or a player who just confirms) takes: the
// legal drop that leaves the shortest way to the pin, stroke and distance
// if there is none.
std::size_t best_drop(const std::vector<DropZone>& zones, Vec3 pin);

const char* drop_option_name(DropOption option);
const char* drop_check_text(DropCheck check);

}  // namespace olcore
