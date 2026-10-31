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

LinksStepInfo flight_step(LinksBall& b, const LinksGround& g, const LinksAero& aero, Vec3 wind, double dt) {
  LinksStepInfo info;
  Vec3 p = b.position, v = b.velocity, w = b.spin;
  Vec3 v2 = v + game_acceleration(v, w, aero, wind) * dt;
  Vec3 p2 = p + (v + v2) * (0.5 * dt);
  Vec3 w2 = w * std::pow(LinksFlightConstants::kSpinKeptPerFrame, LinksFlightConstants::kFrameRate * dt);
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
  links_impact(b, n, surf);
  info.landed = true;
  info.contact = hit;
  info.contact_class = surf.ground_class;
  return info;
}

void rest(LinksBall& b) {
  b.velocity = {};
  b.spin = {};
  b.mode = LinksMode::Rest;
}

LinksStepInfo ground_step(LinksBall& b, const LinksGround& g, const LinksAero& aero, Vec3 wind, LinksRandom& rng,
                          double dt) {
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
    return flight_step(b, g, aero, wind, dt);
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
    return links_surface(links_ground_class(t_.surface(-x / kFeetPerMetre, y / kFeetPerMetre)));
  }

 private:
  const Terrain& t_;
};

double horizontal_distance(Vec3 a, Vec3 b) { return std::hypot(a.x - b.x, a.z - b.z); }

double segment_distance_xz(Vec3 a, Vec3 b, Vec3 c) {
  double abx = b.x - a.x, abz = b.z - a.z;
  double len2 = abx * abx + abz * abz;
  double t = len2 > 0 ? ((c.x - a.x) * abx + (c.z - a.z) * abz) / len2 : 0.0;
  t = std::clamp(t, 0.0, 1.0);
  return std::hypot(a.x + abx * t - c.x, a.z + abz * t - c.z);
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

LinksStepInfo links_step(LinksBall& b, const LinksGround& ground, const LinksAero& aero, Vec3 wind,
                         LinksRandom& rng, double dt) {
  switch (b.mode) {
    case LinksMode::Flight: return flight_step(b, ground, aero, wind, dt);
    case LinksMode::Skid:
    case LinksMode::Roll: return ground_step(b, ground, aero, wind, rng, dt);
    case LinksMode::Rest: break;
  }
  return {};
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
  LinksRandom rng(LinksRandom::seed_for(b.position.x, b.position.y));
  Vec3 wind = to_game(p.wind);
  auto bottom = [&](const LinksBall& ball) { return from_game(ball.position) - Vec3{0, radius_m, 0}; };
  r.path.push_back({0, start.position});

  auto finish = [&](ShotOutcome o, Vec3 pos) {
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
    LinksStepInfo info = links_step(b, ground, *p.links, wind, rng, dt);
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
      if (opt.has_cup && horizontal_distance(contact, opt.cup) < opt.cup_radius) {
        return finish(ShotOutcome::Holed, opt.cup);
      }
    } else if (!was_flying) {
      if (opt.has_cup && length(from_game(b.velocity)) < opt.max_holing_speed &&
          segment_distance_xz(before, after, opt.cup) < opt.cup_radius) {
        return finish(ShotOutcome::Holed, opt.cup);
      }
      Surface surf = terrain.surface(after.x, after.z);
      if (surf == Surface::Water) {
        return finish(ShotOutcome::Water, after);
      }
      if (surf == Surface::OutOfBounds) {
        return finish(ShotOutcome::OutOfBounds, after);
      }
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
