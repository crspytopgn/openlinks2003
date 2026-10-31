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
// The putter's club number; it has no row in the club table.
constexpr int kLinksPutter = 19;

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

// The C runtime's rand(), which the game's swing code draws from: a linear
// congruential generator returning 0..32767.
class LinksRand {
 public:
  explicit LinksRand(std::uint32_t seed = 1) : state_(seed) {}
  int next();
  std::uint32_t state() const { return state_; }

 private:
  std::uint32_t state_;
};

// How much a mishit costs from each lie (TerrainTypes LieAngularSnap,
// LiePowerSnap and Snap): spin and ball speed lost per step of the meter's
// miss, and how far a miss is magnified into a pull or push. `miss` (AngleMiss
// and PowerMiss, equal in every record) scales a computer golfer's misses.
struct LinksLieSnap {
  double spin_snap = 0.1;
  double power_snap = 0;
  double snap = 1;
  double miss = 1;
};
LinksLieSnap links_lie_snap(int ground_class);

enum class LinksSwingMethod { PowerStroke, Mouse };

// The skill levels, 0 (easiest) to 3. `meter_scale` widens the PowerStroke
// accuracy window and `meter_steps` is how many accuracy steps it holds.
struct LinksSkill {
  double meter_scale;
  int meter_steps;
};
constexpr int kLinksSkillCount = 4;
LinksSkill links_skill(int level);

// The PowerStroke meter's accuracy in whole steps, `contact`, for a snap that
// lands `miss` meter units past the perfect zone (positive is late). The
// window is clamped at 25 units. `meter_width` is the meter's size in the
// game's units: 150, 192 (the default) or 238.
int links_meter_contact(double miss, int skill, int meter_width = 192);

// One human swing, as it reaches the shot.
struct LinksSwing {
  LinksSwingMethod method = LinksSwingMethod::PowerStroke;
  int skill = 3;          // 0..3, see links_skill
  int contact = 0;        // the meter's accuracy in whole steps (links_meter_contact)
  double full_power = 100;  // power above this is an overswing
  // The mouse swing's own face and path angles (degrees, positive closes the
  // face or swings to the left) and loft multiplier.
  double mouse_face_deg = 0;
  double mouse_path_deg = 0;
  double mouse_loft = 1;
  bool left_handed = false;
  // A ball on the tee peg strikes cleanly whatever the meter says; a
  // PowerStroke swing only wobbles its power and aim a little.
  bool teed_up = false;
};

// What the swing and the lie do to a human player's strike, replacing
// links_apply_lie. A putt (kLinksPutter) only turns the face: the miss is
// worked out as for a full swing but without the overswing, flipped in sign
// and added to the face error, with no power lost, no scatter and no strike
// quality. With PowerStroke a miss of the meter becomes a pull or push
// (aim and path turned apart, so the ball curves), lost power and, on the
// harder levels, a little random scatter; the mouse swing brings its own face
// and path. Either way a miss takes spin and ball speed off according to the
// lie, and sand uses the contact as in links_apply_lie.
void links_apply_swing(LinksStrike& s, const LinksSwing& w, const LinksSurface& lie, LinksRand& rng);

// A computer golfer's steadiness with each kind of shot, 0 to 100 (more is
// steadier; the game keeps these in each golfer's definition). `max_power` is
// the most power, in percent, the golfer swings with; a plan past it is
// forced and misses more. `steady` halves the misses.
struct LinksGolferRatings {
  int tee = 85;          // tee shots
  int woods = 85;        // clubs 0..6 (driver and woods) off the ground
  int long_irons = 85;   // clubs 7..9
  int mid_irons = 85;    // clubs 10..12
  int short_irons = 85;  // clubs 13..15
  int wedges = 85;       // clubs 16..18
  int chips = 85;        // chips
  int max_power = 100;
  bool steady = false;
};

// A computer golfer's planned swing; links_computer_miss adds its mistakes.
// The angles are in degrees.
struct LinksComputerSwing {
  double power = 100;  // percent of a full swing
  double face_deg = 0;
  double path_deg = 0;
};

// The game's computer miss generator: two draws from the golfer's rating for
// the shot give a power miss and a direction miss, both scaled by the lie
// (LinksLieSnap::miss). The direction miss turns the face or the path either
// way and costs half as much power again; the power miss is short or long at
// random, and always short from more than 230 yards. Off the tee both misses
// grow by up to 0.99. Power never drops to zero. `feet_to_hole` is measured
// from the ball.
void links_computer_miss(LinksComputerSwing& w, const LinksGolferRatings& g, int club, bool teed_up, bool chip,
                         int ground_class, double feet_to_hole, LinksRand& rng);

// The putter's own launch. `power` is the putt's strength: the ball leaves
// at power x 2.3436 ft/s along the face (the face error and the face and
// stance settings, added, not subtracted as in a full swing), less the
// cosine of the angle between face and path. It starts with backspin as
// fast as rolling would need, so it skids before it rolls. No lie or slope
// is applied here: links_putt_slope tilts both vectors onto the ground.
constexpr double kLinksPuttSpeed = 2.343600034713745;  // ft/s per unit of putt power
LinksLaunch links_putt(const LinksStrike& s);

// Tilts a putt's velocity or spin from flat ground onto ground with unit
// normal n (z up): about x by atan2(n.y, n.z), then about y by
// -atan2(n.x, n.z).
Vec3 links_putt_slope(Vec3 v, Vec3 n);

// The same launch in olcore's SI frame (see ball_physics.hpp), with the ball
// at the origin. For the putter (kLinksPutter) this is links_putt, with
// on_ground set.
BallState links_launch_state(const LinksClubTable& clubs, const LinksStrike& s);

}  // namespace olcore
