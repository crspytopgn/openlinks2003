#include "olcore/links_ground.hpp"
#include "olcore/links_launch.hpp"

#include <algorithm>
#include <cmath>

namespace olcore {

namespace {

using C = LinksConstants;

constexpr double kTwoPi = 6.283185307179586;
constexpr double kFeetPerMetre = LinksFlightConstants::kFeetPerMetre;

// Bounce.
constexpr double kDragKnee = 1700.0;         // below this vt*vn the drag is scaled down
constexpr double kDragKneeSlope = 0.000352941;
constexpr double kDragKneeBase = 0.4;
constexpr double kRollingSlip = 0.2;         // ft/s; slip below this counts as rolling
constexpr double kSlipEpsilon = 0.01;
constexpr double kSpinPerImpulse = 35.7143;  // 2.5 / R
constexpr double kPlugSpeed = 60.0;          // ft/s into the sand
constexpr double kRoughSpread = 0.13;        // rad; random turn of a bounce in rough
constexpr double kRocksSpread = 6.28319;     // rad; any direction off rocks

// Ground step.
constexpr double kAcross = 0.5625;           // slope pull factors across and along the slope
constexpr double kAlong = 0.25;
constexpr double kFastRoll = 30.0;           // ft/s; resistance grows beyond this
constexpr double kFastRollGrowth = 0.2;
constexpr double kSkidSpin = 5.684105;
constexpr double kTwoPiR = 0.439823;         // 2 pi R
constexpr double kSteep = 0.6;               // normal z below this is too steep to hold the ball
constexpr int kLedgeProbes = 12;             // looks up to 1 ft ahead, in 1/12 ft steps
constexpr double kLedgeHeight = 1.0;
constexpr double kLeaveGround = 0.1;         // ft^2; a bigger squared drop takes off
constexpr double kCheckpointTime = 1.0 + 1e-6;
constexpr double kStuckDistance = 0.14;

// Rough: random hops.
constexpr double kHopMinSpeed = 1.5;
constexpr double kHopSpeedKept = 0.9;
constexpr double kHopChance = 0.45;
constexpr double kHopMaxSpeed = 40.0;
constexpr double kHopLow = 0.02;
constexpr double kHopHigh = 0.15;

// Rocks: kicks.
constexpr double kKickMinSpeed = 1.0;
constexpr double kKickStopChance = 0.5;
constexpr double kKickBoost = 5.0;

Vec3 unit_or_zero(Vec3 v) {
  double l = length(v);
  return l > 0 ? v * (1.0 / l) : v;
}

// Everything a step needs besides the ball. The cup's events finish the
// rest of their step through step() again, so the game caps the nesting.
struct StepContext {
  const LinksGround& g;
  const LinksAero& aero;
  Vec3 wind;
  LinksRandom& rng;
  const LinksCup* cup;
  int depth = 0;
};

constexpr int kMaxNesting = 5;

LinksStepInfo step(StepContext& c, LinksBall& b, double dt);
bool enter_cup_from_air(StepContext& c, LinksBall& b, double tau, double dt);
void enter_cup_from_green(StepContext& c, LinksBall& b, const LinksBall& before);
void cup_frame(StepContext& c, LinksBall& b, double dt);
bool hit_flagstick(const StepContext& c, const LinksBall& old, LinksBall& b);

// Straight path p -> q: fraction where the centre first meets the ground,
// or a negative number if it stays above.
double ground_crossing(const LinksGround& g, Vec3 p, Vec3 q) {
  auto f = [&](double t) {
    Vec3 x = p + (q - p) * t;
    return x.z - g.height(x.x, x.y);
  };
  if (f(0) <= 0) {
    return 0;
  }
  constexpr int kSamples = 16;
  double t0 = 0, t1 = -1;
  for (int k = 1; k <= kSamples; ++k) {
    double t = double(k) / kSamples;
    if (f(t) <= 0) {
      t0 = double(k - 1) / kSamples;
      t1 = t;
      break;
    }
  }
  if (t1 < 0) {
    return -1;
  }
  for (int i = 0; i < 50; ++i) {
    double m = 0.5 * (t0 + t1);
    (f(m) <= 0 ? t1 : t0) = m;
  }
  return t1;
}

Vec3 game_acceleration(Vec3 v, Vec3 spin, const LinksAero& aero, Vec3 wind) {
  Vec3 a{0, 0, -C::kGravity};
  Vec3 air = v - wind * LinksFlightConstants::kWindScale;
  double speed = length(air);
  if (speed < 1e-9) {
    return a;
  }
  double rate = length(spin);
  a = a - air * (LinksFlightConstants::kDragScale * aero.drag.at(speed, rate) * speed);
  if (rate > 1e-9) {
    a = a + cross(spin * (1.0 / rate), air) * (LinksFlightConstants::kLiftScale * aero.lift.at(speed, rate) * speed);
  }
  return a;
}

LinksStepInfo flight_step(StepContext& c, LinksBall& b, double dt) {
  const LinksGround& g = c.g;
  LinksStepInfo info;
  Vec3 p = b.position, v = b.velocity, w = b.spin;
  Vec3 v2 = v + game_acceleration(v, w, c.aero, c.wind) * dt;
  Vec3 p2 = p + (v + v2) * (0.5 * dt);
  Vec3 w2 = w * std::pow(LinksFlightConstants::kSpinKeptPerFrame, LinksFlightConstants::kFrameRate * dt);
  // The flagstick can turn the ball before it comes down.
  LinksBall moved = b;
  moved.position = p2;
  moved.velocity = v2;
  moved.spin = w2;
  if (hit_flagstick(c, b, moved)) {
    p2 = moved.position;
    v2 = moved.velocity;
    w2 = moved.spin;
  }
  double s = ground_crossing(g, p, p2);
  if (s < 0) {
    b.position = p2;
    b.velocity = v2;
    b.spin = w2;
    return info;
  }
  // The rest of the step is dropped: the step ends at the contact.
  double tau = links_contact_time(v, v2, s);
  Vec3 hit = p + (p2 - p) * s;
  hit.z = g.height(hit.x, hit.y);
  Vec3 n = g.normal(hit.x, hit.y);
  LinksSurface surf = g.surface(hit.x, hit.y);
  b.velocity = v * (1 - tau) + v2 * tau;
  b.spin = w * (1 - tau) + w2 * tau;
  b.position = hit + n * C::kRadius;
  info.landed = true;
  info.contact = hit;
  info.contact_class = surf.ground_class;
  // Coming down inside the hole's circle: no bounce, the cup takes over.
  if (enter_cup_from_air(c, b, tau, dt)) {
    return info;
  }
  links_impact(b, n, surf);
  return info;
}

void rest(LinksBall& b) {
  b.velocity = {};
  b.spin = {};
  b.mode = LinksMode::Rest;
}

LinksStepInfo ground_step(StepContext& c, LinksBall& b, double dt) {
  const LinksGround& g = c.g;
  LinksRandom& rng = c.rng;
  const LinksBall before = b;
  const Vec3 p = b.position, v0 = b.velocity, w = b.spin;
  Vec3 v = v0;
  const double speed = length(v);
  const Vec3 p1 = p + v * dt;
  const Vec3 n1 = g.normal(p1.x, p1.y);
  const LinksSurface surf = g.surface(p1.x, p1.y);
  const int cls = surf.ground_class;

  // Too steep to hold a ball on grass: look up to a foot ahead for a ledge
  // to drop onto.
  if (n1.z < kSteep && (cls == kLinksGreen || cls == kLinksFairway || cls == kLinksRough || cls == kLinksDeepGrass)) {
    Vec3 ahead = unit_or_zero(Vec3{v.x, v.y, 0});
    for (int i = 1; i <= kLedgeProbes; ++i) {
      Vec3 q = p1 + ahead * (double(i) / kLedgeProbes);
      Vec3 nq = g.normal(q.x, q.y);
      double ground = g.height(q.x, q.y);
      if (nq.z > kSteep && std::fabs(q.z - ground) < kLedgeHeight) {
        b.position = {q.x, q.y, ground};
        return {};
      }
      if (nq.z >= kSteep) {
        break;
      }
    }
  }

  // The pull down the slope, the rolling resistance and, while skidding,
  // friction against the slip of the contact point.
  const double normal_force = C::kGravity;
  double nh = std::hypot(n1.x, n1.y), vh = std::hypot(v.x, v.y);
  double pull;
  if (nh == 0 || vh == 0) {
    pull = 0.5 / n1.z * normal_force;
  } else {
    double c = (n1.x * v.x + n1.y * v.y) / (vh * nh);
    pull = std::sqrt((1 - c * c) * kAcross + c * c * kAlong) / n1.z * normal_force;
  }
  Vec3 slope{n1.x * pull, n1.y * pull, normal_force - C::kGravity};
  double support = length(Vec3{n1.x * pull, n1.y * pull, normal_force});
  double resist = support * surf.roll_resistance;
  if (vh > kFastRoll) {
    resist *= 1 + kFastRollGrowth * (vh - kFastRoll);
  }
  Vec3 friction;
  bool now_rolling = false;
  if (b.mode == LinksMode::Skid) {
    Vec3 slip = v + cross(n1, w) * kTwoPiR;
    double grip = support * surf.skid_friction;
    double slip_speed = length(slip);
    if (grip * dt >= slip_speed) {
      now_rolling = true;
    } else {
      friction = slip * (-grip / slip_speed);
    }
  }
  Vec3 a = slope + friction;
  if (resist * dt >= speed) {
    if (length(a) <= resist) {
      rest(b);
      return {};
    }
    v = {};
  } else if (speed > 0) {
    a = a - v * (resist / speed);
  }
  Vec3 v2 = v + a * dt;
  Vec3 p2 = p + v2 * dt;
  Vec3 n2 = g.normal(p2.x, p2.y);
  double z2 = g.height(p2.x, p2.y) + C::kRadius / n2.z;

  // The ground falls away (or rises) too fast to follow: take off.
  if ((z2 - p.z) * (z2 - p.z) > kLeaveGround) {
    b.mode = LinksMode::Flight;
    b.on_ground_started = false;
    return flight_step(c, b, dt);
  }

  // Keep the speed, along the ground at the new point.
  Vec3 side = cross(n2, v2);
  Vec3 v3 = length(side) > 0 ? cross(unit_or_zero(side), n2) * length(v2) : v2;
  Vec3 w2 = b.mode == LinksMode::Skid ? w + cross(friction, n1) * (surf.spin_grip * dt * kSkidSpin)
                                       : cross(n1, v2) * C::kRevPerFps;
  b.position = {p2.x, p2.y, z2};
  b.velocity = v3;
  b.spin = w2;
  if (now_rolling) {
    b.mode = LinksMode::Roll;
  }

  // Grass makes a ball hop now and then; rocks kick it about.
  bool hop = false;
  Vec3 hop_velocity;
  if (cls == kLinksRough) {
    double r1 = rng.next_fraction();
    double r2 = rng.next_fraction();
    if (speed > kHopMinSpeed) {
      double kept = speed * kHopSpeedKept;
      if (r1 < kHopChance) {
        double height = (kHopHigh - kHopLow) / (kHopMaxSpeed - kHopMinSpeed) * (kept - kHopMinSpeed) * r2;
        if (height >= z2 - p.z) {
          Vec3 target{p1.x, p1.y, z2 + kHopLow + height};
          hop_velocity = unit_or_zero(target - p) * kept;
          hop = true;
        }
      }
    }
  } else if (cls == kLinksRocks) {
    if (speed > kKickMinSpeed) {
      hop_velocity = unit_or_zero(unit_or_zero(v0) * 0.5 + n1 * 0.5) * (speed * surf.restitution);
      hop = true;
    } else if (rng.next_fraction() <= kKickStopChance) {
      rest(b);
      return {};
    } else {
      hop_velocity = v0 + n1 * (speed + speed * kKickBoost * rng.next_fraction());
      hop = true;
    }
  }

  if (!b.on_ground_started) {
    b.on_ground_started = true;
    b.checkpoint_x = p2.x;
    b.checkpoint_y = p2.y;
    b.ground_time = 0;
  } else {
    b.ground_time += dt;
    if (b.ground_time >= kCheckpointTime) {
      if (std::hypot(p2.x - b.checkpoint_x, p2.y - b.checkpoint_y) < kStuckDistance) {
        rest(b);
        return {};
      }
      b.checkpoint_x = p2.x;
      b.checkpoint_y = p2.y;
      b.ground_time = 0;
    }
  }
  hit_flagstick(c, before, b);
  // Rolling across the hole's circle on the green.
  if (cls == kLinksGreen) {
    enter_cup_from_green(c, b, before);
  }
  if (hop) {
    b.velocity = hop_velocity;
    b.position = p + hop_velocity * dt;
    b.mode = LinksMode::Flight;
  }
  return {};
}

// Our frame (SI, y up, x to the golfer's left) to the game's (feet, z up,
// x to the golfer's right): a rotation, so cross products carry over.
Vec3 to_game(Vec3 v) { return Vec3{-v.x, v.z, v.y} * kFeetPerMetre; }
Vec3 from_game(Vec3 v) { return Vec3{-v.x, v.z, v.y} * (1.0 / kFeetPerMetre); }
Vec3 spin_to_game(Vec3 w) { return Vec3{-w.x, w.z, w.y} * (1.0 / kTwoPi); }
Vec3 spin_from_game(Vec3 w) { return Vec3{-w.x, w.z, w.y} * kTwoPi; }

class TerrainGround : public LinksGround {
 public:
  explicit TerrainGround(const Terrain& t) : t_(t) {}
  double height(double x, double y) const override {
    return t_.height(-x / kFeetPerMetre, y / kFeetPerMetre) * kFeetPerMetre;
  }
  Vec3 normal(double x, double y) const override {
    Vec3 n = t_.normal(-x / kFeetPerMetre, y / kFeetPerMetre);
    return {-n.x, n.z, n.y};
  }
  LinksSurface surface(double x, double y) const override {
    const LinksSurface* own = t_.links_surface_at(-x / kFeetPerMetre, y / kFeetPerMetre);
    // The game's green options replace every green record on the course.
    if (own != nullptr && own->ground_class != kLinksGreen) return *own;
    return links_surface(links_ground_class(t_.surface(-x / kFeetPerMetre, y / kFeetPerMetre)));
  }

 private:
  const Terrain& t_;
};

double horizontal_distance(Vec3 a, Vec3 b) { return std::hypot(a.x - b.x, a.z - b.z); }

// ---------------------------------------------------------------------------
// The cup. Positions here are relative to the pin's base, in the game's
// frame. The game runs the cup in sub-steps of 1/1200 s and in four modes;
// each finds the earliest event in its sub-step, moves the ball to it, and
// plays the rest of the sub-step through the normal step again. See
// docs/formats/physics.md.

constexpr float kCupSubStep = 0.000833333354f;  // 1/1200 s, as the game stores it
constexpr double kCupEdge = 0.0007;              // ft added to the radius for "in the hole"
constexpr double kNoEvent = 2.0;                 // event times are fractions of the sub-step
constexpr double kBisectStop = 0.000244140625;   // 1/4096
constexpr double kRestOfStep = 0.05;             // shorter remainders are dropped
constexpr double kRimBounce = 0.5;               // normal speed kept off the rim's edge
constexpr double kWallBounce = 0.3;              // ... off the cup's wall
constexpr double kStickSpeed = 0.2;              // ft/s; slower hits stay on the rim or wall
constexpr double kCupDepth = 1.0;                // ft; the ball is holed when its centre is this deep
constexpr double kPoleRadius = 1.0 / 24;          // ft
constexpr double kPoleTop = 8.0;                  // ft above the pin's base
constexpr double kPoleBottom = 0.5;               // ft below it
constexpr double kPoleBounce = 0.3;               // speed kept off the flagstick
constexpr double kPoleSpin = 0.09;                // spin kept
constexpr double kCupTop = 0.071;                // ft; above this the ball is out of the cup
const Vec3 kGravityVector{0, 0, -C::kGravity};

bool in_cup_mode(LinksMode m) {
  return m == LinksMode::CupAir || m == LinksMode::CupRim || m == LinksMode::CupWall || m == LinksMode::CupDrop;
}

// The game's state blend: position by the fraction s of the path, velocity
// and spin by the matching fraction of time.
LinksBall blend(const LinksBall& a, const LinksBall& b, double s, double& tau) {
  s = std::clamp(s, 0.0, 1.0);
  LinksBall out = b;
  out.position = a.position * (1 - s) + b.position * s;
  tau = links_contact_time(a.velocity, b.velocity, s);
  out.velocity = a.velocity * (1 - tau) + b.velocity * tau;
  out.spin = a.spin * (1 - tau) + b.spin * tau;
  return out;
}

// Where the path p + d t (0 < t < 1) first crosses the circle of radius r
// round the origin, across the ground.
bool circle_crossing(Vec3 p, Vec3 d, double r, double& t) {
  double a = d.x * d.x + d.y * d.y;
  double b = 2 * (d.x * p.x + d.y * p.y);
  double k = p.x * p.x + p.y * p.y - r * r;
  double disc = b * b - 4 * k * a;
  if (!(disc > 0)) return false;
  double root = std::sqrt(disc);
  double t1 = (-b - root) / (a + a), t2 = (root - b) / (a + a);
  if (t1 > 0 && t1 < 1) {
    t = t1;
    return true;
  }
  if (t2 > 0 && t2 < 1) {
    t = t2;
    return true;
  }
  return false;
}

Vec3 flat_unit(Vec3 p) {
  double r = std::hypot(p.x, p.y);
  return r != 0 ? Vec3{p.x / r, p.y / r, 0} : Vec3{p.x, p.y, 0};
}

// The game turns a velocity from the level onto a slope with normal n when
// the ball enters or leaves the cup on sloping ground.
Vec3 level_to_slope(Vec3 v, Vec3 n) {
  Vec3 a = unit_or_zero(Vec3{n.y, -n.x, 0});
  Vec3 b = unit_or_zero(cross(a, n));
  double along = a.x * v.x + a.y * v.y;
  double across = a.y * v.x - a.x * v.y;
  return a * along + n * v.z + b * across;
}

// Whether the ball, centre p, overlaps the rim's edge (a circle of radius R
// at the green's level).
bool touches_rim(Vec3 p, double radius) { return std::hypot(radius - std::hypot(p.x, p.y), p.z) < C::kRadius; }

// Whether a ball rolling on the rim's edge comes off it: the edge would have
// to pull on it to keep it there.
bool leaves_rim(const LinksBall& b, double dt, double radius) {
  double r = std::hypot(b.position.x, b.position.y);
  Vec3 u{b.position.x / r, b.position.y / r, 0};
  Vec3 n = unit_or_zero(Vec3{u.x * (r - radius), u.y * (r - radius), b.position.z});
  return -dot(n, kGravityVector) < dot(n, b.velocity) / dt;
}

// The ball's height above the green at a point near the cup, relative to
// the pin's base, and the green's normal there.
double green_height(const StepContext& c, Vec3 rel, Vec3& n) {
  Vec3 w = rel + c.cup->pin;
  n = c.g.normal(w.x, w.y);
  return c.g.height(w.x, w.y) - c.cup->pin.z;
}

// Plays the rest of a sub-step after an event through the normal step.
void finish_substep(StepContext& c, LinksBall& b, double tau, double dt) {
  double rest_of = 1 - tau;
  if (!(rest_of > kRestOfStep)) return;
  b.position = b.position + c.cup->pin;
  step(c, b, rest_of * dt);
  b.position = b.position - c.cup->pin;
}

// Halves towards the time the test starts to hold, as the game does.
template <typename Test>
double bisect(Test holds) {
  double f = 0.5, step_size = 0.25;
  for (;;) {
    f += holds(f) ? -step_size : step_size;
    step_size *= 0.5;
    if (!(step_size > kBisectStop)) return f;
  }
}

// Rolling round the rim's edge (the game's sub-mode 0x40).
void cup_rim(StepContext& c, LinksBall& b, double dt) {
  const double radius = c.cup->radius;
  const LinksBall old = b;
  Vec3 p = b.position, v = b.velocity;
  double r = std::hypot(p.x, p.y);
  Vec3 along{-p.y / r, p.x / r, 0};
  Vec3 n = unit_or_zero(p - flat_unit(p) * radius);
  Vec3 pivot = cross(along, n);
  Vec3 a = pivot * dot(pivot, kGravityVector) + n * (dot(n, v) * (-1 / dt));
  Vec3 v1 = v + a * dt;
  Vec3 p1 = p + v1 * dt;
  Vec3 edge = flat_unit(p1) * radius;
  Vec3 n1 = unit_or_zero(p1 - edge);
  LinksBall next = b;
  next.position = edge + n1 * C::kRadius;
  next.velocity = v1;
  next.spin = cross(v1, n1 * -C::kRevPerFps);

  // The earliest of: back out over the edge onto the green, coming off the
  // edge into the hole, or dropping below the green's level.
  double t_out = kNoEvent;
  if (std::hypot(next.position.x, next.position.y) > radius + kCupEdge) {
    double t = 0;
    t_out = circle_crossing(p, next.position - p, radius + kCupEdge, t) ? t : 0.0;
  }
  double t_off = kNoEvent;
  if (leaves_rim(next, dt, radius)) {
    t_off = bisect([&](double f) {
      double tau = 0;
      LinksBall m = blend(old, next, f, tau);
      return leaves_rim(m, (1 - tau) * dt, radius);
    });
  }
  double t_down = next.position.z < 0 ? -p.z / (next.position.z - p.z) : kNoEvent;
  int event = -1;
  double t = kNoEvent;
  if (t_out < t) event = 0, t = t_out;
  if (t_off < t) event = 1, t = t_off;
  if (t_down < t) event = 2, t = t_down;

  double tau = 0;
  switch (event) {
    case 0: {  // back onto the green, on the circle
      LinksBall m = blend(old, next, t, tau);
      Vec3 u = flat_unit(m.position);
      Vec3 gn;
      double h = green_height(c, m.position, gn);
      m.position = Vec3{u.x * radius, u.y * radius, h + C::kRadius / gn.z};
      if (gn.z != 1) m.velocity = level_to_slope(m.velocity, gn);
      m.mode = LinksMode::Roll;
      m.on_ground_started = false;
      b = m;
      break;
    }
    case 1:  // off the edge, falling into the hole
      b = blend(old, next, t, tau);
      b.mode = LinksMode::CupAir;
      break;
    case 2: {  // over the edge: slides down the wall
      LinksBall m = blend(old, next, t, tau);
      Vec3 u = flat_unit(m.position);
      Vec3 tangent{-u.y, u.x, 0};
      double vt = dot(tangent, m.velocity);
      m.position = Vec3{u.x * radius, u.y * radius, 0};
      m.velocity = Vec3{tangent.x * vt, tangent.y * vt, m.velocity.z};
      m.mode = LinksMode::CupWall;
      b = m;
      break;
    }
    default:
      b = next;
      return;
  }
  finish_substep(c, b, tau, dt);
}

// Falling or bouncing in the air inside the hole's circle (sub-mode 0x20).
void cup_air(StepContext& c, LinksBall& b, double dt) {
  const double radius = c.cup->radius;
  const LinksBall old = b;
  Vec3 p = b.position;
  LinksBall next = b;
  next.velocity = b.velocity + kGravityVector * dt;
  next.position = p + next.velocity * dt;
  Vec3 p1 = next.position;

  // The earliest of: hitting the rim's edge, rising out of the cup, or
  // dropping below the green's level.
  double t_rim = kNoEvent;
  if (touches_rim(p1, radius)) {
    t_rim = bisect([&](double f) { return touches_rim(p * (1 - f) + p1 * f, radius); });
  }
  double t_up = p1.z > kCupTop ? (C::kRadius - p.z) / (p1.z - p.z) : kNoEvent;
  double t_down = p1.z < 0 ? -p.z / (p1.z - p.z) : kNoEvent;
  int event = -1;
  double t = kNoEvent;
  if (t_rim < t) event = 0, t = t_rim;
  if (t_up < t) event = 1, t = t_up;
  if (t_down < t) event = 2, t = t_down;

  double tau = 0;
  switch (event) {
    case 0: {  // hits the rim's edge
      LinksBall m = blend(old, next, t, tau);
      Vec3 u = flat_unit(m.position);
      Vec3 edge = u * radius;
      Vec3 n = unit_or_zero(m.position - edge);
      Vec3 tangent{-u.y, u.x, 0};
      Vec3 pivot = unit_or_zero(Vec3{u.x * n.z, u.y * n.z, -u.y * n.y - u.x * n.x});
      Vec3 v = m.velocity;
      double vn = dot(v, n);
      Vec3 out = unit_or_zero(Vec3{n.x, n.y, 0});
      m.position = edge + out * C::kRadius;
      Vec3 kept = pivot * dot(v, pivot) + tangent * dot(v, tangent);
      if (-vn < kStickSpeed) {
        m.velocity = kept;
        m.mode = LinksMode::CupRim;
      } else {
        m.velocity = kept + n * (-kRimBounce * vn);
      }
      b = m;
      break;
    }
    case 1: {  // up and out of the cup, back to the normal flight
      LinksBall m = blend(old, next, t, tau);
      Vec3 gn;
      double h = green_height(c, m.position, gn);
      m.position.z = h + C::kRadius / gn.z;
      if (gn.z != 1) m.velocity = level_to_slope(m.velocity, gn);
      m.mode = LinksMode::Flight;
      b = m;
      break;
    }
    case 2:  // into the cup
      b = blend(old, next, t, tau);
      b.mode = LinksMode::CupDrop;
      break;
    default:
      b = next;
      break;
  }
  if (event >= 0) finish_substep(c, b, tau, dt);
  // The flagstick stands in the middle of the cup.
  LinksBall from = old, to = b;
  from.position = from.position + c.cup->pin;
  to.position = to.position + c.cup->pin;
  if (hit_flagstick(c, from, to)) {
    b = to;
    b.position = b.position - c.cup->pin;
  }
}

void holed(LinksBall& b) {
  b.velocity = {};
  b.spin = {};
  b.mode = LinksMode::Holed;
}

// Sliding down the cup's wall (sub-mode 0x60): held on the circle, keeping
// only its speed round it, and falling.
void cup_wall(LinksBall& b, double dt, double radius) {
  Vec3 u = flat_unit(b.position);
  double vt = u.x * b.velocity.y - u.y * b.velocity.x;
  b.velocity = Vec3{-u.y * vt, u.x * vt, b.velocity.z} + kGravityVector * dt;
  b.position = Vec3{radius * u.x, radius * u.y, b.position.z} + b.velocity * dt;
  if (b.position.z < -kCupDepth) holed(b);
}

// Falling inside the cup (sub-mode 0x80), bouncing off its wall.
void cup_drop(LinksBall& b, double dt, double radius) {
  b.velocity = b.velocity + kGravityVector * dt;
  b.position = b.position + b.velocity * dt;
  if (b.position.z < -kCupDepth) {
    holed(b);
    return;
  }
  double r = std::hypot(b.position.x, b.position.y);
  if (!(r > radius)) return;
  Vec3 u{b.position.x / r, b.position.y / r, 0};
  Vec3 n = u * -1.0;
  Vec3 v = b.velocity;
  double vn = dot(n, v);
  double vt = u.x * v.y - u.y * v.x;
  b.position = Vec3{radius * u.x, radius * u.y, b.position.z};
  if (-vn < kStickSpeed) {
    b.velocity = Vec3{-u.y * vt, u.x * vt, v.z};
    b.mode = LinksMode::CupWall;
  } else {
    b.velocity = Vec3{-u.y * vt, u.x * vt, 0} + n * (-kWallBounce * vn) + Vec3{0, 0, v.z};
  }
}

// One frame (or the rest of one) in the cup, in sub-steps.
void cup_frame(StepContext& c, LinksBall& b, double dt) {
  b.position = b.position - c.cup->pin;
  float remaining = static_cast<float>(dt);
  auto sub = [&](double h) {
    switch (b.mode) {
      case LinksMode::CupAir: cup_air(c, b, h); break;
      case LinksMode::CupRim: cup_rim(c, b, h); break;
      case LinksMode::CupWall: cup_wall(b, h, c.cup->radius); break;
      case LinksMode::CupDrop: cup_drop(b, h, c.cup->radius); break;
      default: break;
    }
  };
  while (remaining >= kCupSubStep && in_cup_mode(b.mode)) {
    sub(kCupSubStep);
    remaining = remaining - kCupSubStep;
  }
  if (remaining > 0 && in_cup_mode(b.mode)) {
    sub(remaining);
  }
  b.position = b.position + c.cup->pin;
}

bool enter_cup_from_air(StepContext& c, LinksBall& b, double tau, double dt) {
  if (c.cup == nullptr) return false;
  Vec3 rel = b.position - c.cup->pin;
  if (!(std::hypot(rel.x, rel.y) <= c.cup->radius + kCupEdge)) return false;
  b.mode = LinksMode::CupAir;
  Vec3 n = c.g.normal(c.cup->pin.x, c.cup->pin.y);
  if (n.z != 1) b.velocity = level_to_slope(b.velocity, n);
  step(c, b, (1 - tau) * dt);
  return true;
}

void enter_cup_from_green(StepContext& c, LinksBall& b, const LinksBall& before) {
  if (c.cup == nullptr || b.mode == LinksMode::Rest) return;
  double t = 0;
  if (!circle_crossing(before.position - c.cup->pin, b.position - before.position, c.cup->radius, t)) return;
  double tau = 0;
  LinksBall m = blend(before, b, t, tau);
  m.mode = LinksMode::CupRim;
  Vec3 n = c.g.normal(c.cup->pin.x, c.cup->pin.y);
  if (n.z != 1) m.velocity = level_to_slope(m.velocity, n);
  b = m;
}

// The flagstick: a pole of radius 0.5 in (1/24 ft) on the pin. Unless it is
// out (the shot was struck from the green), the first time the ball's centre
// crosses it, anywhere from 0.5 ft below the pin's base to 8 ft above, the
// ball is put at the crossing and sent off it with 0.3 of its speed, mirrored
// about the line from the pole, and 0.09 of its spin. It can only be hit once.
bool hit_flagstick(const StepContext& c, const LinksBall& old, LinksBall& b) {
  if (c.cup == nullptr || b.flagstick_out) return false;
  const Vec3 pin = c.cup->pin;
  if (pin.z + kPoleTop < std::min(old.position.z, b.position.z)) return false;
  if (pin.z - kPoleBottom > std::max(old.position.z, b.position.z)) return false;
  double t = 0;
  if (!circle_crossing(old.position - pin, b.position - old.position, kPoleRadius, t)) return false;
  double tau = 0;
  LinksBall m = blend(old, b, t, tau);
  Vec3 d = unit_or_zero(Vec3{m.position.x - pin.x, m.position.y - pin.y, 0});
  m.velocity = (m.velocity - d * (2 * dot(m.velocity, d))) * kPoleBounce;
  m.spin = m.spin * kPoleSpin;
  m.mode = b.mode;
  m.flagstick_out = true;
  b = m;
  return true;
}

// The game caps how deeply steps nest; past that a ball near the hole is
// set down just outside it.
void nesting_overflow(StepContext& c, LinksBall& b) {
  if (c.cup == nullptr) return;
  Vec3 rel = b.position - c.cup->pin;
  double r = std::hypot(rel.x, rel.y);
  if (!(r < c.cup->radius * 1.05)) return;
  Vec3 u = r != 0 ? Vec3{rel.x / r, rel.y / r, 0} : Vec3{1, 0, 0};
  Vec3 w = c.cup->pin + u * (c.cup->radius * 1.06);
  Vec3 n = c.g.normal(w.x, w.y);
  b.position = Vec3{w.x, w.y, c.g.height(w.x, w.y) + C::kRadius / n.z};
  rest(b);
}

LinksStepInfo step(StepContext& c, LinksBall& b, double dt) {
  LinksStepInfo info;
  if (b.mode == LinksMode::Rest || b.mode == LinksMode::Holed) return info;
  if (++c.depth > kMaxNesting) {
    nesting_overflow(c, b);
  } else {
    switch (b.mode) {
      case LinksMode::Flight: info = flight_step(c, b, dt); break;
      case LinksMode::Skid:
      case LinksMode::Roll: info = ground_step(c, b, dt); break;
      default:
        if (c.cup != nullptr) {
          cup_frame(c, b, dt);
        } else {
          rest(b);
        }
        break;
    }
  }
  --c.depth;
  return info;
}

}  // namespace

LinksSurface links_surface(int ground_class) {
  //        class, restitution, impact friction, skid friction, impact drag, roll, stop, spin grip
  //        (and for rough and deep grass: lie spin, lie power)
  switch (ground_class) {
    case kLinksGreen: return {kLinksGreen, 0.23, 0.08, 0.383486, 0.496454, 0.10538, 0.5, 1.219};
    case kLinksFairway: return {kLinksFairway, 0.266579, 0.1308, 0.132528, 0.441, 0.18, 0.5, 1.00211};
    case kLinksRough: return {kLinksRough, 0.242881, 0.087621, 0.104659, 0.522788, 0.604758, 1.0, 2.0, 0.406505, 0.927315};
    case kLinksSand: return {kLinksSand, 0.2025, 0.05, 0.0714, 0.644842, 0.897139, 0.5, 4.0};
    case kLinksWater: return {kLinksWater, 0.3, 0.35, 0.00288, 0.1, 2.0, 2.0, 0.1};
    case kLinksPath: return {kLinksPath, 0.75303, 0.45738, 0.45, 0.07597, 0.068172, 2.0, 1.46647};
    case kLinksDirt: return {kLinksDirt, 0.388524, 0.121495, 0.108, 0.307136, 0.195622, 0.467325, 4.80256};
    case kLinksBushes: return {kLinksBushes, 0.404543, 0.209029, 0.203495, 0.19674, 0.2555, 0.5, 3.05625};
    case kLinksRocks: return {kLinksRocks, 0.5022, 0.196532, 0.162792, 0.140846, 0.124317, 2.0, 1.15583};
    case kLinksDeepGrass:
      return {kLinksDeepGrass, 0.24384, 0.07, 0.100116, 0.561193, 0.608475, 0.5, 3.0, 0.1992, 0.836732};
    default: return links_surface(kLinksFairway);
  }
}

LinksSurface links_green(LinksGreenFirmness firmness, LinksGreenSpeed speed) {
  // Rolling resistance of the soft, medium and firm records.
  const double soft = 0.120760001;
  const double medium = 0.105379999;
  const double firm = 0.0900000036;
  // Each step of speed moves the resistance one record along (past the ends,
  // by the same step again).
  auto f32 = [](double x) { return static_cast<double>(static_cast<float>(x)); };
  const double ladder[5] = {f32(2 * soft - medium), soft, medium, firm, f32(2 * firm - medium)};
  int step = firmness == LinksGreenFirmness::Soft ? 1 : firmness == LinksGreenFirmness::Medium ? 2 : 3;
  step += speed == LinksGreenSpeed::Slow ? -1 : speed == LinksGreenSpeed::Fast ? 1 : 0;
  LinksSurface g = links_surface(kLinksGreen);
  switch (firmness) {
    case LinksGreenFirmness::Soft:
      g = {kLinksGreen, 0.209999993, 0.0900000036, 0.314999998, 0.549284995, soft, 0.5, 0.899999976};
      break;
    case LinksGreenFirmness::Medium:
      break;
    case LinksGreenFirmness::Firm:
      g = {kLinksGreen, 0.25, 0.100000001, 0.202500001, 0.461228013, firm, 0.5, 1.29999995};
      break;
  }
  g.roll_resistance = ladder[step];
  return g;
}

int links_ground_class(Surface s) {
  switch (s) {
    case Surface::Tee:
    case Surface::Fairway:
    case Surface::Fringe: return kLinksFairway;
    case Surface::Green: return kLinksGreen;
    case Surface::Rough:
    case Surface::OutOfBounds: return kLinksRough;
    case Surface::DeepRough: return kLinksDeepGrass;
    case Surface::Sand: return kLinksSand;
    case Surface::Water: return kLinksWater;
  }
  return kLinksFairway;
}

std::uint32_t LinksRandom::seed_for(double x, double y) {
  // Both truncated to whole feet and multiplied with 32-bit wrap-around.
  auto whole = [](double f) { return static_cast<std::uint32_t>(static_cast<std::int32_t>(f)); };
  std::uint32_t seed = whole(y) * whole(x);
  return seed != 0 ? seed : 0x12345678u;
}

std::uint32_t LinksRandom::next_u32() {
  std::uint32_t s = state_, out = 0;
  for (int i = 0; i < 32; ++i) {
    std::uint32_t x = (s << 1) ^ s;
    x = (x << 1) ^ s;
    x = (x << 2) ^ s;
    x = (x << 2) ^ s;
    x = (x << 25) ^ s;
    s = (x & 0x80000000u) | (s >> 1);
    out = (out << 1) | (s & 1u);
  }
  state_ = s;
  return out << 1;
}

double LinksRandom::next_fraction() {
  // The game keeps the fraction as a float.
  return static_cast<float>(next_u32() * (1.0 / 4294967296.0));
}

void links_impact(LinksBall& b, Vec3 n, const LinksSurface& s) {
  Vec3 v = b.velocity, w = b.spin;
  if (s.ground_class == kLinksWater) {
    rest(b);
    return;
  }
  if (s.ground_class == kLinksSand && std::fabs(dot(n, v)) > kPlugSpeed) {
    // Plugs one landing in four, picked by where it lands.
    int k = static_cast<int>((b.position.y + b.position.x + b.position.z) * 12);
    if (k % 4 == 0) {
      rest(b);
      return;
    }
  }
  Vec3 side = cross(n, v);
  side = length(side) > 0 ? side * (1.0 / length(side)) : Vec3{1, 0, 0};
  Vec3 fwd = cross(side, n);
  double vt = std::hypot(dot(fwd, v), dot(side, v));
  double vn = std::fabs(dot(n, v));
  double w0 = dot(side, w) * kTwoPi;

  double x = vt * vn;
  double drag = std::sqrt(x) * s.impact_drag;
  if (x < kDragKnee) {
    drag *= x * kDragKneeSlope + kDragKneeBase;
  }
  drag = std::min(drag, vt);

  double rw = w0 * C::kRadius;
  double slip = vt - rw;
  double k = s.restitution + 1;
  double vt2, spin;
  if (std::fabs(slip) < kRollingSlip) {
    vt2 = vt - drag;
    spin = vt2 * C::kRevPerFps;
  } else {
    double dv = -k * s.impact_friction * vn - drag;
    double dw = k * s.spin_grip * s.impact_friction * vn * kSpinPerImpulse;
    if (rw > vt) {
      dv = -dv;
      dw = -dw;
    }
    double v1 = vt + dv, w1 = w0 + dw;
    if ((slip > 0) == (v1 - w1 * C::kRadius > 0)) {
      vt2 = v1;
      spin = w1 / kTwoPi;
    } else {
      // Friction would reverse the slip: stop at rolling instead.
      double d = dv - C::kRadius * dw;
      vt2 = std::fabs(d) < kSlipEpsilon ? v1 : (-drag - dv) * slip / d - drag + vt;
      spin = vt2 * C::kRevPerFps;
    }
  }
  double vn2 = vn * s.restitution;

  double along = vt2, across = 0;
  if (s.ground_class == kLinksRough || s.ground_class == kLinksRocks) {
    // A turn picked by where the ball lands.
    double f = double((static_cast<int>(b.position.y) & 0xfff) + (static_cast<int>(b.position.x) & 0xfff)) / 8190.0;
    double angle = s.ground_class == kLinksRough ? kRoughSpread * f - kRoughSpread * 0.5 : kRocksSpread * f;
    along = std::cos(angle) * vt2;
    across = -std::sin(angle) * vt2;
  }
  Vec3 out = fwd * along + side * across + n * vn2;
  b.spin = side * spin;
  if (dot(out, n) <= 2 * s.stop_speed) {
    out = fwd * along + side * across;
    b.mode = LinksMode::Skid;
    b.on_ground_started = false;
  }
  b.velocity = out;
}

double links_contact_time(Vec3 v0, Vec3 v1, double s) {
  auto mask = [](Vec3 v) { return (v.x != 0 ? 1 : 0) | (v.y != 0 ? 2 : 0) | (v.z != 0 ? 4 : 0); };
  int m0 = mask(v0), m1 = mask(v1), m = m0 & m1;
  if (m == 0) {
    if (m0 == 0) {
      return m1 == 0 ? s : 1.0;
    }
    return m1 != 0 ? s : 0.0;
  }
  // The velocity changes linearly over the step: solve for the time at
  // which the distance covered reaches s, using one component.
  double a = (m & 1) ? v0.x / v1.x : (m & 4) ? v0.z / v1.z : v0.y / v1.y;
  if (std::fabs(std::fabs(a) - 1) < 1e-4) {
    return s;
  }
  double disc = (1 - a) * s * 4 + a * a;
  double root = disc > 0 ? std::sqrt(disc) : 0.0;
  double t1 = (root - a) / (2 * (1 - a));
  double t2 = (a + root) / (2 * (1 - a));
  return (t1 >= 0 && t1 <= 1) ? t1 : t2;
}

double links_cup_radius(int option) {
  switch (option) {
    case 0: return 0.1875;
    case 2: return 0.29167;
    default: return 0.17708;
  }
}

LinksStepInfo links_step(LinksBall& b, const LinksGround& ground, const LinksAero& aero, Vec3 wind,
                         LinksRandom& rng, double dt, const LinksCup* cup) {
  StepContext c{ground, aero, wind, rng, cup};
  return step(c, b, dt);
}

ShotResult simulate_links_shot(const BallState& start, const BallParams& p, const Terrain& terrain,
                               const ShotOptions& opt) {
  const double dt = C::kFrameDt;
  const double radius_m = C::kRadius / kFeetPerMetre;
  TerrainGround ground(terrain);
  ShotResult r;
  bool landed = false;
  double t = 0;
  int step = 0;

  // The game starts a full shot in flight with its centre one radius up.
  LinksBall b;
  b.position = to_game(start.position) + Vec3{0, 0, C::kRadius};
  b.velocity = to_game(start.velocity);
  b.spin = spin_to_game(start.spin);
  if (start.on_ground) {
    // A putt starts skidding on the ground, its centre one radius above the
    // slope, with its velocity and spin tilted onto it.
    Vec3 n = ground.normal(b.position.x, b.position.y);
    b.velocity = links_putt_slope(b.velocity, n);
    b.spin = links_putt_slope(b.spin, n);
    b.position.z = ground.height(b.position.x, b.position.y) + C::kRadius / n.z;
    b.mode = LinksMode::Skid;
    landed = true;
    r.first_landing = start.position;
  }
  // The game takes the flagstick out for a shot from the green.
  b.flagstick_out = ground.surface(b.position.x, b.position.y).ground_class == kLinksGreen;
  LinksRandom rng(LinksRandom::seed_for(b.position.x, b.position.y));
  Vec3 wind = to_game(p.wind);
  LinksCup cup;
  cup.pin = to_game(opt.cup);
  cup.radius = opt.cup_radius * kFeetPerMetre;
  auto bottom = [&](const LinksBall& ball) { return from_game(ball.position) - Vec3{0, radius_m, 0}; };
  r.path.push_back({0, start.position});

  auto finish = [&](ShotOutcome o, Vec3 pos) {
    // The game judges the hole's bounds where the ball stops.
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

  while (t < opt.max_time) {
    Vec3 before = bottom(b);
    BallState before_si{before, from_game(b.velocity), spin_from_game(b.spin)};
    bool was_flying = b.mode == LinksMode::Flight;
    LinksStepInfo info = links_step(b, ground, *p.links, wind, rng, dt, opt.has_cup ? &cup : nullptr);
    t += dt;
    ++step;
    Vec3 after = bottom(b);
    r.apex_m = std::max(r.apex_m, after.y - start.position.y);

    // Trees and walls: our own handling, as in simulate_shot.
    ObstacleHit hit;
    if (terrain.obstacle_hit(before, after, hit) && (was_flying || hit.kind == ObstacleKind::Solid)) {
      Vec3 pos = before + (after - before) * hit.fraction;
      Vec3 vel = before_si.velocity;
      Vec3 spin = before_si.spin;
      hit_obstacle(vel, spin, hit);
      pos = pos + hit.normal * (hit.kind == ObstacleKind::Solid ? 0.01 : -0.01);
      ++r.obstacle_hits;
      r.path.push_back({t, pos});
      b.position = to_game(pos) + Vec3{0, 0, C::kRadius};
      b.velocity = to_game(vel);
      b.spin = spin_to_game(spin);
      b.mode = LinksMode::Flight;
      continue;
    }

    if (info.landed) {
      Vec3 contact = from_game(info.contact);
      if (!landed) {
        landed = true;
        r.first_landing = contact;
      }
      ++r.bounces;
      r.path.push_back({t, contact});
      Surface surf = terrain.surface(contact.x, contact.z);
      if (surf == Surface::Water) {
        return finish(ShotOutcome::Water, contact);
      }
      if (surf == Surface::OutOfBounds) {
        return finish(ShotOutcome::OutOfBounds, contact);
      }
    } else if (!was_flying) {
      Surface surf = terrain.surface(after.x, after.z);
      if (surf == Surface::Water) {
        return finish(ShotOutcome::Water, after);
      }
      if (surf == Surface::OutOfBounds) {
        return finish(ShotOutcome::OutOfBounds, after);
      }
    }
    if (b.mode == LinksMode::Holed) {
      return finish(ShotOutcome::Holed, opt.cup);
    }
    if (b.mode == LinksMode::Rest) {
      return finish(ShotOutcome::Rest, after);
    }
    if (opt.sample_every > 0 && step % opt.sample_every == 0) {
      r.path.push_back({t, after});
    }
  }
  return finish(ShotOutcome::TimedOut, bottom(b));
}

}  // namespace olcore
