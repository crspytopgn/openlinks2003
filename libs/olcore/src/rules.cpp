#include "olcore/rules.hpp"

#include <cmath>

namespace olcore {

namespace {

constexpr double kEps = 1e-3;
constexpr double kPi = 3.14159265358979323846;

double flat_distance(Vec3 a, Vec3 b) { return std::hypot(a.x - b.x, a.z - b.z); }

Vec3 on_ground(double x, double z, const Terrain& t) { return {x, t.height(x, z), z}; }

// Unit vector (y = 0) from the pin through `p`; back down the hole if p is
// at the pin.
Vec3 away_from_pin(Vec3 p, Vec3 pin) {
  double dx = p.x - pin.x, dz = p.z - pin.z;
  double len = std::hypot(dx, dz);
  if (len < 1e-6) return {0, 0, -1};
  return {dx / len, 0, dz / len};
}

// The j-th direction tried around `base`: 0, +10, -10, +20, ... +180 degrees.
Vec3 ring_direction(Vec3 base, int j) {
  int k = (j + 1) / 2;
  double a = (j % 2 == 1 ? 1 : -1) * k * 10.0 * kPi / 180.0;
  double c = std::cos(a), s = std::sin(a);
  return {base.x * c + base.z * s, 0, -base.x * s + base.z * c};
}

bool general_area(Surface s) { return s != Surface::Water && s != Surface::OutOfBounds && s != Surface::Green; }

}  // namespace

int drop_penalty(DropReason reason) { return reason == DropReason::FreeRelief ? 0 : 1; }

std::vector<DropOption> drop_options(DropReason reason, bool lateral_water) {
  switch (reason) {
    case DropReason::FreeRelief:
      return {DropOption::FreeDrop};
    case DropReason::Unplayable:
      return {DropOption::BackOnLine, DropOption::Lateral, DropOption::StrokeAndDistance};
    case DropReason::Water:
      break;
  }
  if (lateral_water) return {DropOption::BackOnLine, DropOption::Lateral, DropOption::StrokeAndDistance};
  return {DropOption::BackOnLine, DropOption::StrokeAndDistance};
}

Vec3 water_entry(const std::vector<Vec3>& path, const Terrain& terrain) {
  if (path.empty()) return {};
  auto wet = [&](Vec3 p) { return terrain.surface(p.x, p.z) == Surface::Water; };
  for (std::size_t i = path.size() - 1; i > 0; --i) {
    if (wet(path[i - 1]) || !wet(path[i])) continue;
    Vec3 a = path[i - 1], b = path[i];
    for (int n = 0; n < 30; ++n) {
      Vec3 m = (a + b) * 0.5;
      if (wet(m))
        b = m;
      else
        a = m;
    }
    return on_ground(b.x, b.z, terrain);
  }
  return on_ground(path[0].x, path[0].z, terrain);
}

bool nearest_relief(Vec3 ball, Vec3 pin, const Terrain& terrain, Vec3& point) {
  Vec3 base = away_from_pin(ball, pin);
  double limit = flat_distance(ball, pin) - kEps;
  for (int i = 1; i * kDropStep <= kFreeReliefSearch + 1e-9; ++i) {
    for (int j = 0; j < 36; ++j) {
      Vec3 d = ring_direction(base, j);
      double x = ball.x + d.x * i * kDropStep, z = ball.z + d.z * i * kDropStep;
      if (!general_area(terrain.surface(x, z)) || terrain.free_drop(x, z)) continue;
      if (std::hypot(x - pin.x, z - pin.z) < limit) continue;
      point = on_ground(x, z, terrain);
      return true;
    }
  }
  return false;
}

DropZone drop_zone(DropOption option, Vec3 reference, Vec3 previous, Vec3 pin, bool in_sand,
                   const Terrain& terrain) {
  DropZone z;
  z.option = option;
  z.reference = reference;
  z.direction = away_from_pin(reference, pin);
  z.in_sand = in_sand && option != DropOption::StrokeAndDistance;
  auto legal = [&](double x, double zz) { return check_drop(z, {x, 0, zz}, pin, terrain) == DropCheck::Ok; };
  switch (option) {
    case DropOption::StrokeAndDistance:
      z.reference = previous;
      z.spot = previous;
      z.found = true;
      break;
    case DropOption::BackOnLine:
      for (int k = 0; k * kDropStep <= kMaxBackOnLine + 1e-9; ++k) {
        double d = k * kDropStep;
        Vec3 p = reference + z.direction * d;
        if (!legal(p.x, p.z)) continue;
        Vec3 q = reference + z.direction * (d + kDropMargin);
        if (legal(q.x, q.z)) p = q;
        z.spot = on_ground(p.x, p.z, terrain);
        z.found = true;
        break;
      }
      break;
    case DropOption::Lateral:
    case DropOption::FreeDrop: {
      if (option == DropOption::FreeDrop) {
        z.radius = kClubLength;
        if (!nearest_relief(reference, pin, terrain, z.reference)) break;
        z.direction = away_from_pin(z.reference, pin);
      } else {
        z.radius = 2 * kClubLength;
      }
      // Lateral relief starts a step out: the reference is the ball itself, or
      // the water's edge.
      Vec3 c = z.reference;
      for (int i = option == DropOption::Lateral ? 1 : 0; i * kDropStep <= z.radius + 1e-9 && !z.found; ++i) {
        for (int j = 0; j < (i == 0 ? 1 : 36); ++j) {
          Vec3 d = ring_direction(z.direction, j);
          double x = c.x + d.x * i * kDropStep, zz = c.z + d.z * i * kDropStep;
          if (!legal(x, zz)) continue;
          z.spot = on_ground(x, zz, terrain);
          z.found = true;
          break;
        }
      }
      break;
    }
  }
  return z;
}

DropCheck check_drop(const DropZone& zone, Vec3 spot, Vec3 pin, const Terrain& terrain) {
  if (zone.option == DropOption::StrokeAndDistance)
    return flat_distance(spot, zone.spot) < 0.01 ? DropCheck::Ok : DropCheck::OutsideZone;
  Surface s = terrain.surface(spot.x, spot.z);
  if (s == Surface::OutOfBounds) return DropCheck::OutOfBounds;
  if (s == Surface::Water) return DropCheck::Hazard;
  if (s == Surface::Green) return DropCheck::Green;
  if (zone.in_sand && s != Surface::Sand) return DropCheck::NotSand;
  if (zone.option == DropOption::FreeDrop && terrain.free_drop(spot.x, spot.z)) return DropCheck::StillOnPath;
  Vec3 ref = zone.reference;
  if (zone.option == DropOption::BackOnLine) {
    double dx = spot.x - ref.x, dz = spot.z - ref.z;
    double along = dx * zone.direction.x + dz * zone.direction.z;
    double across = std::fabs(dx * zone.direction.z - dz * zone.direction.x);
    if (along < -kEps || along > kMaxBackOnLine + kDropMargin + kEps || across > kClubLength + kEps)
      return DropCheck::OutsideZone;
  } else if (flat_distance(spot, ref) > zone.radius + kEps) {
    return DropCheck::OutsideZone;
  }
  if (flat_distance(spot, pin) < flat_distance(ref, pin) - kEps) return DropCheck::NearerPin;
  return DropCheck::Ok;
}

std::size_t best_drop(const std::vector<DropZone>& zones, Vec3 pin) {
  std::size_t best = zones.size();
  double best_d = 0;
  for (std::size_t i = 0; i < zones.size(); ++i) {
    if (zones[i].option == DropOption::StrokeAndDistance || !zones[i].found) continue;
    double d = flat_distance(zones[i].spot, pin);
    if (best == zones.size() || d < best_d) {
      best = i;
      best_d = d;
    }
  }
  if (best < zones.size()) return best;
  for (std::size_t i = 0; i < zones.size(); ++i)
    if (zones[i].option == DropOption::StrokeAndDistance) return i;
  return 0;
}

const char* drop_option_name(DropOption option) {
  switch (option) {
    case DropOption::StrokeAndDistance:
      return "Replay from the last spot";
    case DropOption::BackOnLine:
      return "Drop back on the line";
    case DropOption::Lateral:
      return "Drop within two club lengths";
    case DropOption::FreeDrop:
      return "Free drop";
  }
  return "";
}

const char* drop_check_text(DropCheck check) {
  switch (check) {
    case DropCheck::Ok:
      return "";
    case DropCheck::OutsideZone:
      return "Stay inside the drop zone.";
    case DropCheck::NearerPin:
      return "You can't drop nearer the pin.";
    case DropCheck::Hazard:
      return "You can't drop in a hazard.";
    case DropCheck::OutOfBounds:
      return "You can't drop out of bounds.";
    case DropCheck::Green:
      return "You can't drop on the green.";
    case DropCheck::NotSand:
      return "The drop has to stay in the bunker.";
    case DropCheck::StillOnPath:
      return "That's still on the path.";
  }
  return "";
}

}  // namespace olcore
