#include "olcore/links_flight.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace olcore {

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr std::size_t kSpeedCount = 11;
constexpr std::size_t kSpinCount = 14;

std::uint32_t read_u32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
         (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
}

double read_f32(const std::uint8_t* p) {
  std::uint32_t bits = read_u32(p);
  float f;
  std::memcpy(&f, &bits, sizeof f);
  return f;
}

// Index of the grid cell holding x, clamped so that [i, i + 1] is valid.
std::size_t cell(const std::vector<double>& axis, double x) {
  std::size_t i = 0;
  while (i + 2 < axis.size() && x >= axis[i + 1]) {
    ++i;
  }
  return i;
}

bool ascending_from_zero(const std::vector<double>& v) {
  if (v.empty() || v[0] != 0.0) {
    return false;
  }
  for (std::size_t i = 1; i < v.size(); ++i) {
    if (!(v[i] > v[i - 1])) {
      return false;
    }
  }
  return true;
}

// A table in the executable: u32 row count (11), u32 column count (14), the
// speed axis, the spin axis, two axis pointers and a zero word, then the
// rows. See docs/formats/physics.md.
std::optional<CoefficientTable> table_at(const std::uint8_t* p, std::size_t avail) {
  const std::size_t size = 8 + 4 * (kSpeedCount + kSpinCount) + 12 + 4 * kSpeedCount * kSpinCount;
  if (avail < size || read_u32(p) != kSpeedCount || read_u32(p + 4) != kSpinCount) {
    return std::nullopt;
  }
  CoefficientTable t;
  const std::uint8_t* q = p + 8;
  for (std::size_t i = 0; i < kSpeedCount; ++i, q += 4) t.speeds.push_back(read_f32(q));
  for (std::size_t i = 0; i < kSpinCount; ++i, q += 4) t.spins.push_back(read_f32(q));
  if (!ascending_from_zero(t.speeds) || !ascending_from_zero(t.spins)) {
    return std::nullopt;
  }
  q += 12;
  for (std::size_t i = 0; i < kSpeedCount * kSpinCount; ++i, q += 4) {
    double v = read_f32(q);
    if (!std::isfinite(v) || std::fabs(v) > 5.0) {
      return std::nullopt;
    }
    t.values.push_back(v);
  }
  return t;
}

}  // namespace

double CoefficientTable::at(double speed_fps, double spin_rps) const {
  if (speeds.size() < 2 || spins.size() < 2 || values.size() != speeds.size() * spins.size()) {
    return 0.0;
  }
  double s = std::clamp(speed_fps, speeds.front(), speeds.back());
  double w = std::clamp(spin_rps, spins.front(), spins.back());
  std::size_t i = cell(speeds, s);
  std::size_t j = cell(spins, w);
  double fs = (s - speeds[i]) / (speeds[i + 1] - speeds[i]);
  double fw = (w - spins[j]) / (spins[j + 1] - spins[j]);
  auto v = [&](std::size_t r, std::size_t c) { return values[r * spins.size() + c]; };
  double lo = v(i, j) + (v(i + 1, j) - v(i, j)) * fs;
  double hi = v(i, j + 1) + (v(i + 1, j + 1) - v(i, j + 1)) * fs;
  return lo + (hi - lo) * fw;
}

std::optional<LinksAero> find_links_aero(const std::uint8_t* exe, std::size_t size) {
  std::optional<CoefficientTable> drag, lift;
  for (std::size_t off = 0; off + 8 <= size; off += 4) {
    if (read_u32(exe + off) != kSpeedCount) {
      continue;
    }
    std::optional<CoefficientTable> t = table_at(exe + off, size - off);
    if (!t) {
      continue;
    }
    // Drag is positive everywhere; lift is zero without spin.
    bool no_spin_no_lift = true;
    for (std::size_t r = 0; r < kSpeedCount; ++r) {
      no_spin_no_lift = no_spin_no_lift && t->values[r * kSpinCount] == 0.0;
    }
    if (no_spin_no_lift && !lift) {
      lift = std::move(t);
    } else if (!no_spin_no_lift && !drag && *std::min_element(t->values.begin(), t->values.end()) > 0.0) {
      drag = std::move(t);
    }
    if (drag && lift) {
      return LinksAero{std::move(*drag), std::move(*lift)};
    }
  }
  return std::nullopt;
}

std::optional<LinksAero> find_links_aero(const std::vector<std::uint8_t>& exe) {
  return find_links_aero(exe.data(), exe.size());
}

Vec3 links_acceleration(const BallState& s, const LinksAero& aero, Vec3 wind) {
  using C = LinksFlightConstants;
  Vec3 a{0, -C::kGravityFps2 / C::kFeetPerMetre, 0};
  Vec3 air = s.velocity - wind * C::kWindScale;
  double speed = length(air);
  if (speed < 1e-9) {
    return a;
  }
  double speed_fps = speed * C::kFeetPerMetre;
  double spin = length(s.spin);
  double spin_rps = spin / (2 * kPi);

  // In feet: a = -k Cd |v| v. Each factor of velocity converts to metres
  // and back once, leaving k per foot as k * feet-per-metre per metre.
  double drag = C::kDragScale * C::kFeetPerMetre * aero.drag.at(speed_fps, spin_rps) * speed;
  a = a - air * drag;
  if (spin > 1e-9) {
    double lift = C::kLiftScale * C::kFeetPerMetre * aero.lift.at(speed_fps, spin_rps) * speed;
    a = a + cross(s.spin * (1.0 / spin), air) * lift;
  }
  return a;
}

BallState links_step_flight(const BallState& s, const LinksAero& aero, Vec3 wind, double dt) {
  using C = LinksFlightConstants;
  BallState out;
  out.velocity = s.velocity + links_acceleration(s, aero, wind) * dt;
  out.position = s.position + (s.velocity + out.velocity) * (0.5 * dt);
  out.spin = s.spin * std::pow(C::kSpinKeptPerFrame, C::kFrameRate * dt);
  return out;
}

}  // namespace olcore
