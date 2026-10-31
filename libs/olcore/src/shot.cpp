#include "olcore/shot.hpp"

#include <algorithm>
#include <cmath>

#include "olcore/links_ground.hpp"

namespace olcore {

namespace {

double horizontal_distance(Vec3 a, Vec3 b) {
  double dx = a.x - b.x, dz = a.z - b.z;
  return std::sqrt(dx * dx + dz * dz);
}

// Horizontal distance from point c to the segment a-b.
double segment_distance_xz(Vec3 a, Vec3 b, Vec3 c) {
  double abx = b.x - a.x, abz = b.z - a.z;
  double len2 = abx * abx + abz * abz;
  double t = len2 > 0 ? ((c.x - a.x) * abx + (c.z - a.z) * abz) / len2 : 0.0;
  t = std::clamp(t, 0.0, 1.0);
  return horizontal_distance({a.x + abx * t, 0, a.z + abz * t}, c);
}

constexpr double kRadToDeg = 57.29577951308232;
constexpr double kMaxCraterDeg = 30.0;

constexpr double kSolidRestitution = 0.35;  // normal speed kept off a trunk or wall
constexpr double kSolidFriction = 0.75;     // speed along the face kept
constexpr double kCanopyKeep = 0.2;         // speed kept going into leaves
constexpr double kCanopyBounce = 0.05;      // normal speed kept coming back out
constexpr double kObstacleGap = 0.01;       // m; keeps the ball off the face it hit
constexpr double kFlatTop = 0.7;            // normal y above which the ball can rest on a solid

bool is_hazard_stop(Surface s) { return s == Surface::Water || s == Surface::OutOfBounds; }

}  // namespace

const char* surface_name(Surface s) {
  switch (s) {
    case Surface::Tee: return "Tee";
    case Surface::Fairway: return "Fairway";
    case Surface::Fringe: return "Fringe";
    case Surface::Green: return "Green";
    case Surface::Rough: return "Rough";
    case Surface::DeepRough: return "Deep rough";
    case Surface::Sand: return "Sand";
    case Surface::Water: return "Water";
    case Surface::OutOfBounds: return "Out of bounds";
  }
  return "?";
}

SurfaceParams surface_params(Surface s) {
  //        restitution, friction, softness, rolling resistance, lie power, lie spin
  switch (s) {
    case Surface::Tee: return {1.00, 0.40, 1.0, 0.16, 1.00, 1.00};
    case Surface::Fairway: return {1.00, 0.40, 1.0, 0.16, 1.00, 1.00};
    case Surface::Fringe: return {0.90, 0.45, 1.0, 0.10, 0.95, 0.90};
    case Surface::Green: return {0.85, 0.45, 1.0, 0.055, 1.00, 1.00};
    case Surface::Rough: return {0.60, 0.60, 1.2, 0.30, 0.85, 0.60};
    case Surface::DeepRough: return {0.40, 0.80, 1.4, 0.50, 0.70, 0.40};
    case Surface::Sand: return {0.12, 0.90, 1.6, 0.90, 0.75, 0.70};
    case Surface::Water: return {0.00, 1.00, 1.0, 1.0, 0.00, 0.00};
    case Surface::OutOfBounds: return {0.60, 0.60, 1.2, 0.30, 0.85, 0.60};
  }
  return {1, 0.4, 1.0, 0.16, 1, 1};
}

Vec3 Terrain::normal(double x, double z) const {
  const double e = 0.25;
  double dx = height(x + e, z) - height(x - e, z);
  double dz = height(x, z + e) - height(x, z - e);
  Vec3 n{-dx, 2 * e, -dz};
  return n * (1.0 / length(n));
}

const char* outcome_name(ShotOutcome o) {
  switch (o) {
    case ShotOutcome::Rest: return "Rest";
    case ShotOutcome::Holed: return "Holed";
    case ShotOutcome::Water: return "Water";
    case ShotOutcome::OutOfBounds: return "Out of bounds";
    case ShotOutcome::TimedOut: return "Timed out";
  }
  return "?";
}

double turf_restitution(double normal_speed) {
  double v = std::fabs(normal_speed);
  if (v > 20.0) {
    return 0.12;
  }
  return 0.510 - 0.0375 * v + 0.000903 * v * v;
}

void bounce(Vec3& velocity, Vec3& spin, Vec3 n, Surface surface, const BallParams& p) {
  if (dot(velocity, n) >= 0) {
    return;
  }
  SurfaceParams sp = surface_params(surface);

  // The ball dents the turf, so it meets a crater wall that is tilted back
  // towards it. Penner's fit for the tilt grows with impact speed and angle.
  Vec3 along = velocity - n * dot(velocity, n);
  double along_len = length(along);
  double speed = length(velocity);
  if (along_len > 1e-9 && speed > 1e-9) {
    double impact_deg = std::asin(std::min(1.0, -dot(velocity, n) / speed)) * kRadToDeg;
    double tilt_deg = std::min(kMaxCraterDeg, sp.softness * 15.4 * (speed / 18.6) * (impact_deg / 44.4));
    double tilt = tilt_deg / kRadToDeg;
    n = n * std::cos(tilt) - along * (std::sin(tilt) / along_len);
  }

  double vn = dot(velocity, n);
  if (vn >= 0) {
    return;
  }
  double e = turf_restitution(-vn) * sp.restitution_scale;
  double jn = (1 + e) * -vn;  // normal impulse per unit mass

  Vec3 vt = velocity - n * vn;
  // Velocity of the contact point (bottom of the ball) along the ground.
  Vec3 vc = vt + cross(spin, n * -p.radius);
  double vc_len = length(vc);
  if (vc_len > 1e-9) {
    // A solid sphere stops slipping after a tangential impulse of 2/7 m|vc|;
    // friction caps it at mu times the normal impulse.
    double j = std::min(2.0 / 7.0 * vc_len, sp.friction * jn);
    Vec3 dir = vc * (1.0 / vc_len);
    vt = vt - dir * j;
    spin = spin + cross(n, dir) * (2.5 * j / p.radius);
  }
  // Most spin about the normal (sidespin) scrubs off on the turf.
  spin = spin - n * (dot(spin, n) * 0.5);
  velocity = vt + n * (-e * vn);
}

void hit_obstacle(Vec3& velocity, Vec3& spin, const ObstacleHit& hit) {
  double vn = dot(velocity, hit.normal);
  if (vn >= 0) {
    return;
  }
  Vec3 vt = velocity - hit.normal * vn;
  if (hit.kind == ObstacleKind::Solid) {
    velocity = vt * kSolidFriction - hit.normal * (vn * kSolidRestitution);
    spin = spin * 0.5;
  } else {
    velocity = vt * kCanopyKeep - hit.normal * (vn * kCanopyBounce);
    spin = spin * 0.2;
  }
}

ShotResult simulate_shot(const BallState& start, const BallParams& p, const Terrain& terrain,
                         const ShotOptions& opt) {
  if (p.links) {
    return simulate_links_shot(start, p, terrain, opt);
  }
  ShotResult r;
  BallState s = start;
  double t = 0;
  int step = 0;
  bool landed = false;
  r.path.push_back({0, s.position});

  auto finish = [&](ShotOutcome o, Vec3 pos) {
    // A course can limit each hole to an outline; it is judged where the ball
    // stops.
    if (o == ShotOutcome::Rest && !terrain.in_bounds(pos.x, pos.z)) o = ShotOutcome::OutOfBounds;
    r.outcome = o;
    r.rest = pos;
    r.time_s = t;
    r.rest_surface = terrain.surface(pos.x, pos.z);
    if (!landed) {
      r.first_landing = pos;
    }
    r.carry_m = horizontal_distance(start.position, r.first_landing);
    r.total_m = horizontal_distance(start.position, pos);
    if (r.path.empty() || r.path.back().t < t) {
      r.path.push_back({t, pos});
    }
    return r;
  };

  Vec3 n0 = terrain.normal(s.position.x, s.position.z);
  bool rolling = dot(s.velocity, n0) < opt.roll_threshold;
  if (rolling) {
    s.velocity = s.velocity - n0 * dot(s.velocity, n0);
    landed = true;
    r.first_landing = s.position;
  }

  while (t < opt.max_time) {
    if (!rolling) {
      BallState next = step_flight(s, p, opt.dt);
      double h0 = s.position.y - terrain.height(s.position.x, s.position.z);
      double h1 = next.position.y - terrain.height(next.position.x, next.position.z);
      t += opt.dt;
      ++step;
      r.apex_m = std::max(r.apex_m, next.position.y - start.position.y);

      // An obstacle met before the ground. Time keeps the whole step, so a
      // ball wedged between obstacles still runs out of time.
      double ground = h1 <= 0 ? (h0 > 0 ? h0 / (h0 - h1) : 0.0) : 2.0;
      ObstacleHit hit;
      if (terrain.obstacle_hit(s.position, next.position, hit) && hit.fraction < ground) {
        Vec3 pos = s.position + (next.position - s.position) * hit.fraction;
        Vec3 vel = s.velocity + (next.velocity - s.velocity) * hit.fraction;
        Vec3 spin = next.spin;
        hit_obstacle(vel, spin, hit);
        // Just outside a solid, or just inside a canopy, so the same face
        // is not met again.
        pos = pos + hit.normal * (hit.kind == ObstacleKind::Solid ? kObstacleGap : -kObstacleGap);
        ++r.obstacle_hits;
        r.path.push_back({t, pos});
        // Settled on top of something flat enough (a wall, a bridge).
        if (hit.kind == ObstacleKind::Solid && hit.normal.y > kFlatTop && dot(vel, hit.normal) < opt.roll_threshold) {
          if (!landed) {
            landed = true;
            r.first_landing = pos;
          }
          return finish(ShotOutcome::Rest, pos);
        }
        s = BallState{pos, vel, spin};
        continue;
      }

      if (h1 <= 0) {
        // Back up to the moment of contact.
        double frac = h0 > 0 ? h0 / (h0 - h1) : 0.0;
        Vec3 pos = s.position + (next.position - s.position) * frac;
        Vec3 vel = s.velocity + (next.velocity - s.velocity) * frac;
        pos.y = terrain.height(pos.x, pos.z);
        t = t - opt.dt + opt.dt * frac;
        if (!landed) {
          landed = true;
          r.first_landing = pos;
        }
        r.path.push_back({t, pos});

        Surface surf = terrain.surface(pos.x, pos.z);
        if (surf == Surface::Water) {
          return finish(ShotOutcome::Water, pos);
        }
        if (surf == Surface::OutOfBounds) {
          return finish(ShotOutcome::OutOfBounds, pos);
        }
        if (opt.has_cup && horizontal_distance(pos, opt.cup) < opt.cup_radius) {
          return finish(ShotOutcome::Holed, opt.cup);
        }

        Vec3 n = terrain.normal(pos.x, pos.z);
        Vec3 spin = next.spin;
        bounce(vel, spin, n, surf, p);
        ++r.bounces;
        s = BallState{pos, vel, spin};
        double vn = dot(vel, n);
        if (vn < opt.roll_threshold) {
          rolling = true;
          s.velocity = vel - n * vn;
        }
        continue;
      }
      s = next;
    } else {
      Vec3 pos = s.position;
      Vec3 v = s.velocity;
      Vec3 n = terrain.normal(pos.x, pos.z);
      SurfaceParams sp = surface_params(terrain.surface(pos.x, pos.z));

      Vec3 g{0, -p.gravity, 0};
      Vec3 slope = (g - n * dot(g, n)) * (5.0 / 7.0);
      double resist = sp.rolling_resistance * p.gravity * n.y;
      double speed = length(v);
      bool holds = length(slope) <= resist;  // static friction holds the ball
      if (speed < opt.stop_speed && holds) {
        return finish(ShotOutcome::Rest, pos);
      }
      Vec3 a = slope;
      if (speed > 1e-9) {
        a = a - v * (resist / speed);
      }
      Vec3 nv = v + a * opt.dt;
      if (speed > 1e-9 && dot(nv, v) < 0 && holds) {
        return finish(ShotOutcome::Rest, pos);
      }
      Vec3 npos = pos + nv * opt.dt;
      npos.y = terrain.height(npos.x, npos.z);
      Vec3 nn = terrain.normal(npos.x, npos.z);
      nv = nv - nn * dot(nv, nn);
      t += opt.dt;
      ++step;

      // Rolling into a trunk or a wall; leaves do not stop a rolling ball.
      ObstacleHit hit;
      if (terrain.obstacle_hit(pos, npos, hit) && hit.kind == ObstacleKind::Solid) {
        Vec3 hp = pos + (npos - pos) * hit.fraction + hit.normal * kObstacleGap;
        hp.y = terrain.height(hp.x, hp.z);
        hit_obstacle(nv, s.spin, hit);
        Vec3 hn = terrain.normal(hp.x, hp.z);
        s.position = hp;
        s.velocity = nv - hn * dot(nv, hn);
        ++r.obstacle_hits;
        r.path.push_back({t, hp});
        continue;
      }

      if (opt.has_cup && length(nv) < opt.max_holing_speed &&
          segment_distance_xz(pos, npos, opt.cup) < opt.cup_radius) {
        return finish(ShotOutcome::Holed, opt.cup);
      }
      Surface surf = terrain.surface(npos.x, npos.z);
      if (is_hazard_stop(surf)) {
        return finish(surf == Surface::Water ? ShotOutcome::Water : ShotOutcome::OutOfBounds, npos);
      }
      s.position = npos;
      s.velocity = nv;
    }
    if (opt.sample_every > 0 && step % opt.sample_every == 0) {
      r.path.push_back({t, s.position});
    }
  }
  return finish(ShotOutcome::TimedOut, s.position);
}

}  // namespace olcore
