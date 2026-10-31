#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/links_ground.hpp"

namespace olcore {

// How Links 2003 turns a swing into the ball's launch, as described in
// docs/formats/physics.md. Like links_ground.hpp this works in the game's
// frame and units: x to the golfer's right, y downrange, z up, feet,
// seconds, spin in revolutions per second.
//
// The per-club numbers live in the game's executable and are read from the
// player's copy (find_links_clubs); nothing from the game is built in.

// The game's full set: seven woods (driver first) and twelve irons and
// wedges, ordered by loft within each group. The putter is handled apart.
constexpr int kLinksClubCount = 19;

struct LinksClubTable {
  std::array<double, kLinksClubCount> spin{};           // spin per unit of clubhead speed
  std::array<double, kLinksClubCount> speed{};          // ball ft/s per percent of power
  std::array<double, kLinksClubCount> loft_deg{};       // face loft
  std::array<double, kLinksClubCount> glance{};         // share of speed along the face
  std::array<double, kLinksClubCount> ball_position{};  // degrees of loft per 14 steps of ball position
};

// Finds the club table in a Links 2003 executable. Returns nothing if it is
// not there.
std::optional<LinksClubTable> find_links_clubs(const std::uint8_t* exe, std::size_t size);
std::optional<LinksClubTable> find_links_clubs(const std::vector<std::uint8_t>& exe);

// The shot setup screen's settings, in the game's own steps. 30 is square
// for the face and the stance; the neutral ball position is 2 for the driver
// and 4 for every other club.
struct LinksSetup {
  int ball_position = -1;  // -1: the club's neutral position
  int face = 30;           // above 30 opens the face (ball starts right)
  int stance = 30;         // above 30 opens the stance (path to the right)
};

int links_neutral_ball_position(int club);

struct LinksStrike {
  int club = 0;
  double aim = 0;            // heading, radians, positive to the left of +y
  double power = 100;        // percent of a full swing
  double face_error = 0;     // radians; positive closes the face (ball left)
  double path_error = 0;     // radians; positive swings to the left
  double speed_scale = 1;    // multiplies ball speed
  double spin_scale = 1;     // multiplies spin
  double loft_scale = 1;     // multiplies the club's loft
  LinksSetup setup;
  Vec3 ground_normal{0, 0, 1};  // under the ball; tilts the stance
};

struct LinksLaunch {
  Vec3 velocity;  // ft/s
  Vec3 spin;      // rev/s
};

LinksLaunch links_launch(const LinksClubTable& clubs, const LinksStrike& s);

// What the lie does to a strike. Every lie scales spin and ball speed by its
// lie values (rough and deep grass take most of the spin off). Sand ignores
// the face error and replaces both scales by how much sand the club takes:
// `sand_contact` is the swing meter's miss in whole steps, 0 for the
// standard splash, positive for heavier (fatter) contact, negative for
// cleaner, and below -5 thin, which also takes loft off.
void links_apply_lie(LinksStrike& s, const LinksSurface& lie, int sand_contact = 0);

// The same launch in olcore's SI frame (see ball_physics.hpp), with the ball
// at the origin.
BallState links_launch_state(const LinksClubTable& clubs, const LinksStrike& s);

}  // namespace olcore
