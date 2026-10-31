#pragma once

#include <cstdint>

#include "olcore/ball_physics.hpp"
#include "olcore/links_flight.hpp"
#include "olcore/links_objects.hpp"
#include "olcore/shot.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// The bounce and roll of Links 2003, as described in docs/formats/physics.md.
// Unlike links_flight.hpp these functions work in the game's own frame and
// units, because the model mixes feet, ft/s and rev/s in its thresholds:
// x to the golfer's right, y downrange, z up, feet, seconds, and spin as a
// vector in revolutions per second. simulate_links_shot converts to and from
// the SI frame of the rest of olcore.

// Ground classes, as stored in a course's TerrainTypes records.
enum LinksGroundClass {
  kLinksGreen = 1,
  kLinksFairway = 2,
  kLinksRough = 3,
  kLinksSand = 4,
  kLinksWater = 5,
  kLinksPath = 6,
  kLinksDirt = 7,
  kLinksBushes = 8,
  kLinksRocks = 9,
  kLinksDeepGrass = 10,
};

// What a ground class does to the ball: offsets 0x14 to 0x2c of a
// TerrainTypes record for the bounce and roll, and 0x04 and 0x0c for the
// strike from that lie.
struct LinksSurface {
  int ground_class = kLinksFairway;
  double restitution = 0;      // normal speed kept by a bounce
  double impact_friction = 0;  // friction during a bounce
  double skid_friction = 0;    // friction while the ball slides
  double impact_drag = 0;      // speed lost along the ground in a bounce
  double roll_resistance = 0;  // rolling resistance
  double stop_speed = 0;       // bounces end below twice this normal speed
  double spin_grip = 0;        // how much spin friction puts on the ball
  double lie_spin = 1;         // spin kept when striking from this lie
  double lie_power = 1;        // ball speed kept when striking from this lie
};

// The values every course checked so far uses for each class.
LinksSurface links_surface(int ground_class);
// The class used for one of our surfaces.
int links_ground_class(Surface s);

// The game's green options. Each firmness is a whole green record (firm
// greens bounce higher and grip spin harder); the speed then sets the rolling
// resistance from the three records' own values. Medium and normal are the
// defaults above.
enum class LinksGreenFirmness { Soft, Medium, Firm };
enum class LinksGreenSpeed { Slow, Normal, Fast };
LinksSurface links_green(LinksGreenFirmness firmness, LinksGreenSpeed speed);
// The ground of every 3D object (class 0): the game's default record.
LinksSurface links_object_surface();

struct LinksConstants {
  static constexpr double kRadius = 0.07;             // ft
  static constexpr double kGravity = 32.152;          // ft/s^2
  static constexpr double kRevPerFps = 2.27364;       // rev/s per ft/s of surface speed
  static constexpr double kFrameDt = 1.0 / 60.0;
};

// The game's ball modes. The cup has four of its own (see physics.md):
// CupAir falling or bouncing inside the hole's circle above the rim, CupRim
// rolling round the rim's edge, CupWall sliding down the wall and CupDrop
// falling inside the cup below the rim. Holed is at rest in the cup.
// OnObject is rolling on a 3D object (a bridge deck), which the game treats
// as rolling on ground of its own (links_object_surface).
enum class LinksMode { Flight, Skid, Roll, Rest, CupAir, CupRim, CupWall, CupDrop, Holed, OnObject };

// Ball state in the game's frame (see above). `position` is the centre.
struct LinksBall {
  Vec3 position;
  Vec3 velocity;
  Vec3 spin;  // rev/s
  LinksMode mode = LinksMode::Flight;
  // The ground checkpoint: every second on the ground the ball must have
  // moved 0.14 ft, or it is stopped.
  bool on_ground_started = false;
  double checkpoint_x = 0, checkpoint_y = 0;
  double ground_time = 0;
  // The flagstick is out: the shot was struck from the green, or the ball
  // has already hit it once.
  bool flagstick_out = false;
  // The billboard it last hit (an index into LinksObjects), or -1.
  int last_object = -1;
  // In OnObject mode: the 3D object it rolls on (LinksObjects::models()).
  int on_object = -1;
};

// The game's random numbers: a 32-bit shift register, seeded at launch from
// the ball's position.
class LinksRandom {
 public:
  explicit LinksRandom(std::uint32_t seed = 0x12345678u) : state_(seed) {}
  // The seed the game uses for a ball struck from (x, y), in feet.
  static std::uint32_t seed_for(double x, double y);
  std::uint32_t next_u32();
  double next_fraction();  // in [0, 1)
  std::uint32_t state() const { return state_; }

 private:
  std::uint32_t state_;
};

// The ground in the game's frame.
class LinksGround {
 public:
  virtual ~LinksGround() = default;
  virtual double height(double x, double y) const = 0;
  virtual Vec3 normal(double x, double y) const = 0;  // unit, z > 0
  virtual LinksSurface surface(double x, double y) const = 0;
};

// Resolves a landing in place. `n` is the ground normal at the contact
// point. Water stops the ball, a hard landing in sand can plug it, and a ball
// that comes off slowly enough starts to skid.
void links_impact(LinksBall& b, Vec3 n, const LinksSurface& s);

// Fraction of a step at which the ball met the ground, given the velocities
// at the start and end of the step and the fraction `s` of the path covered.
double links_contact_time(Vec3 v0, Vec3 v1, double s);

// The hole, in the game's frame. The game models it as a circle of `radius`
// round the pin's base: a rim edge the ball can roll on and a cup below.
struct LinksCup {
  Vec3 pin;                  // base of the flagstick, on the green
  double radius = 0.17708;   // ft: the regulation 4.25 inch hole
};

// The cup radius the game's launch sets from its hole option: 0 for a 4.5
// inch hole, 1 for 4.25 inches (regulation) and 2 for 7 inches.
double links_cup_radius(int option);

// What happened during a step.
struct LinksStepInfo {
  bool landed = false;   // the ball came down onto the ground
  Vec3 contact;          // where (ground level)
  int contact_class = 0;
};

// Advances the ball one step of dt seconds (the game always uses 1/60 s).
// `wind` is in ft/s before the game's 0.5 factor. With a cup, a ball that
// crosses the hole's circle on the green, or lands inside it, plays out the
// game's cup model; it ends in Holed or comes back out. With objects, the
// ball meets trees and other billboards as the game's does; they face
// `facing` (see LinksObjects::hit).
LinksStepInfo links_step(LinksBall& b, const LinksGround& ground, const LinksAero& aero, Vec3 wind,
                         LinksRandom& rng, double dt = LinksConstants::kFrameDt, const LinksCup* cup = nullptr,
                         const LinksObjects* objects = nullptr, Vec3 facing = Vec3{0, -1, 0});

// A whole shot with the Links 2003 flight, bounce, roll, cup and flagstick
// (used by simulate_shot when p.links is set), and the course's billboards
// when opt.links_objects has them. The terrain's own obstacles (walls,
// bridges, and trees without billboards), water and out of bounds use our
// own handling.
ShotResult simulate_links_shot(const BallState& start, const BallParams& p, const Terrain& terrain,
                               const ShotOptions& opt = {});

}  // namespace olcore
