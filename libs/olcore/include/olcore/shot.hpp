#pragma once

#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// A whole shot: flight, bounces and roll over a Terrain until the ball stops,
// drops in the cup, or finds water or out of bounds.
//
// Ground contact uses a standard rigid-sphere impulse model: the normal
// rebound follows a published turf restitution curve (Penner, "The physics of
// golf: the optimum loft of a driver", 2001) scaled per surface, and Coulomb
// friction drives the contact point towards rolling without slipping, which
// is what lets backspin check or spin a ball back. Rolling uses the solid
// sphere result (5/7 g along the slope) plus a rolling-resistance term.

enum class ShotOutcome { Rest, Holed, Water, OutOfBounds, TimedOut };

const char* outcome_name(ShotOutcome o);

struct ShotOptions {
  double dt = 0.004;                 // integration step, seconds
  int sample_every = 4;              // keep every n-th step in the path
  double max_time = 60.0;            // give up after this long
  bool has_cup = false;
  Vec3 cup;                          // cup centre on the green surface
  double cup_radius = 0.054;         // 4.25 in hole
  double max_holing_speed = 1.6;     // faster balls lip out
  double roll_threshold = 0.4;       // normal speed below which bounces stop
  double stop_speed = 0.03;          // rolling speed treated as stopped
};

struct ShotSample {
  double t;
  Vec3 position;
};

struct ShotResult {
  ShotOutcome outcome = ShotOutcome::Rest;
  Vec3 rest;                // final position (cup centre when holed)
  Vec3 first_landing;       // first ground contact
  Surface rest_surface = Surface::Fairway;
  double carry_m = 0;       // horizontal start-to-first-landing distance
  double total_m = 0;       // horizontal start-to-rest distance
  double apex_m = 0;        // highest point above the start
  double time_s = 0;
  int bounces = 0;
  int obstacle_hits = 0;    // trees, walls and the like
  std::vector<ShotSample> path;
};

// Resolves one ground impact in place: v and spin are updated, n is the unit
// surface normal at the contact point.
void bounce(Vec3& velocity, Vec3& spin, Vec3 n, Surface surface, const BallParams& p);

// Resolves the ball meeting an obstacle in place. A solid sends it back
// with some of its speed; a canopy soaks up most of it, so the ball drops.
// Generic values, to be tuned against the original game.
void hit_obstacle(Vec3& velocity, Vec3& spin, const ObstacleHit& hit);

// Restitution of turf for a given normal impact speed (m/s), before the
// per-surface scale.
double turf_restitution(double normal_speed);

// `start.position` is where the ball sits (bottom of the ball, on the
// ground). A start with almost no speed off the ground, such as a putt,
// begins rolling straight away. With p.links set the whole shot uses the
// Links 2003 model instead (simulate_links_shot in links_ground.hpp).
ShotResult simulate_shot(const BallState& start, const BallParams& p, const Terrain& terrain,
                         const ShotOptions& opt = {});

}  // namespace olcore
