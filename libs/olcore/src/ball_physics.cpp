#include "olcore/ball_physics.hpp"

#include "olcore/links_flight.hpp"

#include <algorithm>
#include <cmath>

namespace olcore {

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kRpmToRadS = 2.0 * kPi / 60.0;

double deg_to_rad(double d) { return d * kPi / 180.0; }

// Lift coefficient as a function of spin ratio S = r|w| / |v|. This fit to
// wind-tunnel data is a common approximation; it rises steeply at low spin
// ratios and flattens out, capped to stay physically sensible.
double lift_coefficient(double spin_ratio) {
  double cl = -0.05 + std::sqrt(0.0025 + 0.36 * spin_ratio);
  return std::clamp(cl, 0.0, 0.35);
}
}  // namespace

double length(Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }

Vec3 cross(Vec3 a, Vec3 b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}

BallState make_launch(double speed_mps, double launch_deg, double azimuth_deg, double backspin_rpm,
                      double sidespin_rpm) {
  double el = deg_to_rad(launch_deg);
  double az = deg_to_rad(azimuth_deg);
  Vec3 dir{std::cos(el) * std::sin(az), std::sin(el), std::cos(el) * std::cos(az)};

  // Backspin: the spin axis points to the golfer's right (forward x up), so
  // w x v points up and the ball climbs.
  Vec3 up{0, 1, 0};
  Vec3 horiz{dir.x, 0, dir.z};
  double hl = length(horiz);
  Vec3 right = hl > 0 ? cross(horiz, up) * (1.0 / hl) : Vec3{-1, 0, 0};

  // Sidespin about the vertical axis: positive spin about +y curves the ball
  // towards +x (left), because (0,w,0) x (0,0,v) = (w v, 0, 0).
  Vec3 spin = right * (backspin_rpm * kRpmToRadS) + up * (sidespin_rpm * kRpmToRadS);

  return BallState{{0, 0, 0}, dir * speed_mps, spin};
}

Vec3 acceleration(const BallState& s, const BallParams& p) {
  Vec3 a{0, -p.gravity, 0};
  Vec3 air = s.velocity - p.wind;  // velocity through the air
  double speed = length(air);
  if (speed < 1e-9) {
    return a;
  }

  double area = kPi * p.radius * p.radius;
  double q = 0.5 * p.air_density * area * speed * speed;  // dynamic pressure x area

  double spin_rate = length(s.spin);
  double spin_ratio = p.radius * spin_rate / speed;

  // Drag opposes motion through the air.
  double cd = p.drag_coefficient + p.drag_spin_factor * spin_ratio;
  a = a + air * (-q * cd / (p.mass * speed));

  // Magnus lift acts along w x v.
  Vec3 wxv = cross(s.spin, air);
  double wxv_len = length(wxv);
  if (wxv_len > 1e-9 && spin_rate > 1e-9) {
    double cl = lift_coefficient(spin_ratio);
    a = a + wxv * (q * cl / (p.mass * wxv_len));
  }
  return a;
}

BallState step_flight(const BallState& s, const BallParams& p, double dt) {
  if (p.links) {
    return links_step_flight(s, *p.links, p.wind, dt);
  }
  auto deriv = [&](const BallState& st) { return acceleration(st, p); };

  BallState k1s = s;
  Vec3 a1 = deriv(k1s);
  Vec3 v1 = s.velocity;

  BallState k2s{s.position + v1 * (dt / 2), s.velocity + a1 * (dt / 2), s.spin};
  Vec3 a2 = deriv(k2s);
  Vec3 v2 = k2s.velocity;

  BallState k3s{s.position + v2 * (dt / 2), s.velocity + a2 * (dt / 2), s.spin};
  Vec3 a3 = deriv(k3s);
  Vec3 v3 = k3s.velocity;

  BallState k4s{s.position + v3 * dt, s.velocity + a3 * dt, s.spin};
  Vec3 a4 = deriv(k4s);
  Vec3 v4 = k4s.velocity;

  BallState out;
  out.position = s.position + (v1 + v2 * 2 + v3 * 2 + v4) * (dt / 6);
  out.velocity = s.velocity + (a1 + a2 * 2 + a3 * 2 + a4) * (dt / 6);
  out.spin = s.spin * std::max(0.0, 1.0 - p.spin_decay_per_s * dt);
  return out;
}

FlightResult simulate_flight(const BallState& launch, const BallParams& p, double dt, int path_every_n_steps) {
  FlightResult r;
  BallState s = launch;
  r.path.push_back(s.position);
  double t = 0;
  int step = 0;
  const double max_time = 30.0;

  while (t < max_time) {
    BallState next = step_flight(s, p, dt);
    t += dt;
    ++step;
    r.apex_m = std::max(r.apex_m, next.position.y);

    if (next.position.y <= 0 && next.velocity.y < 0) {
      // Interpolate to the exact ground crossing.
      double frac = s.position.y / (s.position.y - next.position.y);
      BallState land;
      land.position = s.position + (next.position - s.position) * frac;
      land.velocity = s.velocity + (next.velocity - s.velocity) * frac;
      land.spin = next.spin;
      land.position.y = 0;
      r.landing = land;
      r.flight_time_s = t - dt + dt * frac;
      r.path.push_back(land.position);
      break;
    }
    s = next;
    if (path_every_n_steps > 0 && step % path_every_n_steps == 0) {
      r.path.push_back(s.position);
    }
  }

  if (r.flight_time_s == 0) {
    r.landing = s;
    r.flight_time_s = t;
  }
  Vec3 d = r.landing.position - launch.position;
  r.carry_m = std::sqrt(d.x * d.x + d.z * d.z);
  return r;
}

}  // namespace olcore
