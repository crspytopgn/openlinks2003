#include "olcore/links_launch.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace olcore {

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kDeg = kPi / 180.0;
constexpr double kFeetPerMetre = 1.0 / 0.3048;
constexpr std::size_t kRowBytes = 4 * (kLinksClubCount + 1);  // each row has a spare zero
constexpr std::size_t kTableBytes = 5 * kRowBytes;

double read_f32(const std::uint8_t* p) {
  std::uint32_t bits = static_cast<std::uint32_t>(p[0]) | (static_cast<std::uint32_t>(p[1]) << 8) |
                       (static_cast<std::uint32_t>(p[2]) << 16) | (static_cast<std::uint32_t>(p[3]) << 24);
  float f;
  std::memcpy(&f, &bits, sizeof f);
  return f;
}

bool all_within(const std::array<double, kLinksClubCount>& v, double lo, double hi) {
  return std::all_of(v.begin(), v.end(), [&](double x) { return x >= lo && x <= hi; });
}

bool rising(const std::array<double, kLinksClubCount>& v, int from, int to) {
  for (int i = from + 1; i < to; ++i) {
    if (!(v[i] > v[i - 1])) return false;
  }
  return true;
}

// Rotation about z by a, taking +y towards -x.
Vec3 turn_z(Vec3 v, double a) {
  double c = std::cos(a), s = std::sin(a);
  return {v.x * c - v.y * s, v.x * s + v.y * c, v.z};
}

// Rotation about x by a, taking +y towards +z.
Vec3 turn_x(Vec3 v, double a) {
  double c = std::cos(a), s = std::sin(a);
  return {v.x, v.y * c - v.z * s, v.y * s + v.z * c};
}

}  // namespace

std::optional<LinksClubTable> find_links_clubs(const std::uint8_t* exe, std::size_t size) {
  for (std::size_t off = 0; off + kTableBytes <= size; off += 4) {
    const std::uint8_t* p = exe + off;
    // Cheap test first: the driver's speed factor.
    double first = read_f32(p + kRowBytes);
    if (first < 1 || first > 5) continue;
    // The spare entry after each of the first four rows is zero.
    bool spares = true;
    for (int r = 0; r < 4 && spares; ++r) spares = read_f32(p + r * kRowBytes + 4 * kLinksClubCount) == 0.0;
    if (!spares) continue;
    LinksClubTable t;
    std::array<double, kLinksClubCount>* rows[5] = {&t.spin, &t.speed, &t.loft_deg, &t.glance, &t.ball_position};
    for (int r = 0; r < 5; ++r) {
      for (int i = 0; i < kLinksClubCount; ++i) (*rows[r])[i] = read_f32(p + r * kRowBytes + 4 * i);
    }
    if (all_within(t.spin, 0.5, 20) && all_within(t.speed, 1, 5) && all_within(t.loft_deg, 5, 80) &&
        all_within(t.glance, 0, 1) && all_within(t.ball_position, 1, 40) && rising(t.loft_deg, 0, 7) &&
        rising(t.loft_deg, 7, kLinksClubCount)) {
      return t;
    }
  }
  return std::nullopt;
}

std::optional<LinksClubTable> find_links_clubs(const std::vector<std::uint8_t>& exe) {
  return find_links_clubs(exe.data(), exe.size());
}

int links_neutral_ball_position(int club) { return club == 0 ? 2 : 4; }

LinksLaunch links_launch(const LinksClubTable& clubs, const LinksStrike& s) {
  int c = std::clamp(s.club, 0, kLinksClubCount - 1);
  int ball_position = s.setup.ball_position < 0 ? links_neutral_ball_position(c) : s.setup.ball_position;
  // Moving the ball back in the stance takes loft off, forward adds it.
  double loft = (s.loft_scale * clubs.loft_deg[c] +
                 (links_neutral_ball_position(c) - ball_position) * clubs.ball_position[c] / 14.0) *
                kDeg;

  // The slope under the ball, measured along and across the aim line. A side
  // slope turns the face a tenth of its angle; an up or down slope tilts the
  // whole swing.
  Vec3 n = turn_z(s.ground_normal, -s.aim);
  double across = std::clamp(std::atan2(n.x, n.z) / kDeg, -30.0, 30.0);
  double along = std::clamp(std::atan2(n.y, n.z) / kDeg, -15.0, 15.0);

  // Face normal and swing path in the aim frame. The stance setting turns
  // both; the face setting turns the face alone.
  double path = (s.setup.stance - 30) * kDeg - s.path_error;
  double face = (s.setup.face - 30 + s.setup.stance - 30) * kDeg - s.face_error;
  Vec3 f{std::cos(loft) * std::sin(face), std::cos(loft) * std::cos(face), std::sin(loft)};
  f = turn_x(turn_z(f, -0.1 * across * kDeg), -along * kDeg);
  Vec3 p = turn_x(Vec3{std::sin(path), std::cos(path), 0}, -along * kDeg);

  // The ball leaves along the face normal, with a little of the path left
  // over along the face; spin comes from the glancing part of the blow.
  double square = dot(f, p);
  Vec3 g = p - f * square;
  double gl = length(g);
  g = gl > 0 ? g * (1.0 / gl) : Vec3{};
  double speed = s.speed_scale * clubs.speed[c] * s.power;
  LinksLaunch out;
  out.velocity = (f * square + g * (square * clubs.glance[c])) * speed;
  out.spin = cross(g, f) * (speed * s.spin_scale * clubs.spin[c] * 0.25 * square);
  out.velocity = turn_z(out.velocity, s.aim);
  out.spin = turn_z(out.spin, s.aim);
  return out;
}

BallState links_launch_state(const LinksClubTable& clubs, const LinksStrike& s) {
  LinksLaunch l = links_launch(clubs, s);
  BallState b;
  b.velocity = Vec3{-l.velocity.x, l.velocity.z, l.velocity.y} * (1.0 / kFeetPerMetre);
  b.spin = Vec3{-l.spin.x, l.spin.z, l.spin.y} * (2 * kPi);
  return b;
}

}  // namespace olcore
