#include "olcore/links_launch.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace olcore {

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kDeg = kPi / 180.0;
constexpr double kFeetPerMetre = 1.0 / 0.3048;
constexpr double kSingle09 = 0.89999997615814209;  // 0.9 as the game stores it, in single precision
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

namespace {

// Sand: how much sand the club takes, from the meter's contact. Sets the
// speed and spin factors and the loft, which only a thin strike reduces.
void sand_contact(LinksStrike& s, int c, double& speed, double& spin) {
  s.loft_scale = 1;
  if (c >= 0) {
    speed = 0.3 + (15 - c) / 150.0;
    spin = 0.25 + (15 - c) / 12.0;
    return;
  }
  double clean = -c;
  spin = 1.5 - 0.1 * clean;
  if (c >= -5) {
    speed = 0.4 + 0.1 * clean;
  } else {
    speed = 0.9 - 0.065 * (clean - 5);
    s.loft_scale = 1 - 0.09 * (clean - 5);
  }
}

}  // namespace

void links_apply_lie(LinksStrike& s, const LinksSurface& lie, int sand_contact_steps) {
  double spin = 1, speed = 1;
  if (lie.ground_class == kLinksSand) {
    s.face_error = 0;
    sand_contact(s, sand_contact_steps, speed, spin);
  }
  s.spin_scale = spin * lie.lie_spin;
  s.speed_scale = speed * lie.lie_power;
}

int LinksRand::next() {
  state_ = state_ * 214013u + 2531011u;
  return static_cast<int>((state_ >> 16) & 0x7fff);
}

LinksLieSnap links_lie_snap(int ground_class) {
  switch (ground_class) {
    case kLinksRough: return {0.1, 0.03, 1.5, 1.5};
    case kLinksSand: return {0.2, 0.2, 2, 1.9};
    case kLinksPath: return {0.1, 0, 4, 2};
    case kLinksDirt: return {0.1, 0, 3, 1.5};
    case kLinksBushes: return {0.1, 0, 1.5, 1.4};
    case kLinksRocks: return {0.1, 0, 3, 2};
    case kLinksDeepGrass: return {0.1, 0.05, 2, 1.7};
    default: return {0.1, 0, 1, 1};
  }
}

LinksSkill links_skill(int level) {
  switch (std::clamp(level, 0, kLinksSkillCount - 1)) {
    case 0: return {2.0, 225};
    case 1: return {1.5, 180};
    case 2: return {1.5, 180};
    default: return {1.4, 165};
  }
}

int links_meter_contact(double miss, int skill, int meter_width) {
  int x = static_cast<int>(std::clamp(miss, -25.0, 25.0));
  LinksSkill k = links_skill(skill);
  int window = static_cast<int>(meter_width * k.meter_scale);
  int t = static_cast<int>(static_cast<double>(x * k.meter_steps) / window);
  return static_cast<int>(0.2 * t) / 2;
}

void links_apply_swing(LinksStrike& s, const LinksSwing& w, const LinksSurface& lie, LinksRand& rng) {
  const LinksLieSnap ls = links_lie_snap(lie.ground_class);
  const bool sand = lie.ground_class == kLinksSand;
  const int skill = std::clamp(w.skill, 0, kLinksSkillCount - 1);
  s.loft_scale = 1;
  s.spin_scale = lie.lie_spin;
  s.speed_scale = lie.lie_power;

  if (s.club == kLinksPutter) {
    if (w.method == LinksSwingMethod::PowerStroke) {
      if (skill > 0) {
        int miss = w.contact * (skill == 3 ? 6 : skill == 2 ? 5 : 2);
        miss = static_cast<int>(miss * ls.snap);
        if (miss != 0) {
          int sum = rng.next() % 101 + rng.next() % 101 + rng.next() % 101;
          miss = static_cast<int>((sum * 0.001 + 0.35) * miss);
        }
        miss = -std::clamp(miss, -60, 60);
        double turn = ((rng.next() % 25) + 75.0) * 0.01 * miss;
        turn *= skill == 3 ? 0.5 : skill == 2 ? 1 / 1.9 : 2 / 3.0;
        s.face_error += turn * kDeg;
        // The game still draws the power it would lose, then keeps it all.
        if (skill >= 2 && miss != 0) rng.next();
      }
    } else {
      s.face_error = w.mouse_face_deg * kDeg;
      s.path_error = w.mouse_path_deg * kDeg;
    }
    if (sand) s.face_error = 0;
    return;
  }

  if (w.method == LinksSwingMethod::PowerStroke) {
    if (skill > 0) {
      // The miss in steps, magnified by an overswing, the skill level and the
      // lie, then scattered by up to a third either way.
      int miss = w.contact;
      double over = (s.power - w.full_power) * 0.5;
      if (s.power > w.full_power && over > 1) miss = static_cast<int>(over * miss);
      miss *= skill == 3 ? 6 : skill == 2 ? 5 : 2;
      miss = static_cast<int>(miss * ls.snap);
      if (miss != 0) {
        int sum = rng.next() % 101 + rng.next() % 101 + rng.next() % 101;
        miss = static_cast<int>((sum * 0.001 + 0.35) * miss);
      }
      miss = std::clamp(miss, -60, 60);
      // Turning the aim one way and the path the other leaves the face where
      // it was but swings across it: a late miss pushes and slices.
      double turn = ((rng.next() % 25) + 75.0) * 0.01 * miss;
      turn *= skill == 3 ? 0.5 : skill == 2 ? 1 / 1.9 : 2 / 3.0;
      turn *= kDeg;
      s.path_error -= turn;
      if (!sand) s.aim += turn;
      if (skill >= 2) {
        // Lost power for a miss, then a little scatter in power and face.
        double lost = 0;
        if (miss != 0) {
          lost = rng.next() % std::abs(miss) + 1.0;
          if (!(lost < s.power)) lost = s.power - 1;
        }
        s.power -= lost;
        double dp = (rng.next() % 100) * 0.0025;
        double df = (rng.next() % 100) * 0.001 * kDeg;
        s.power += rng.next() % 100 < 50 ? -dp : dp;
        s.face_error += rng.next() % 100 < 50 ? -df : df;
      }
    }
  } else {
    s.face_error = w.mouse_face_deg * kDeg;
    s.path_error = w.mouse_path_deg * kDeg;
    s.loft_scale = w.mouse_loft;
  }
  if (sand) s.face_error = 0;
  if (w.teed_up) {
    if (w.method == LinksSwingMethod::PowerStroke) {
      s.power += (rng.next() % 200 - 100) * 0.01;
      s.aim += (rng.next() % 200 - 100) * 1e-5;
    }
    return;
  }

  // The strike itself: the further off the meter, the more spin and speed
  // the lie takes away, and below a quality limit the ball comes off slower.
  const int c = std::abs(w.contact);
  double quality;
  switch (lie.ground_class) {
    case kLinksGreen: quality = 1; break;
    case kLinksRough: quality = 0.6 - 0.03 * c; break;
    case kLinksSand: quality = 0.4 - 0.03 * c; break;
    case kLinksPath:
    case kLinksDirt:
    case kLinksBushes:
    case kLinksRocks: quality = 0.95 - 0.06 * c; break;
    default: quality = (rng.next() % 200 - 100) * 5e-5 + (kSingle09 - 0.01 * c); break;
  }
  if (lie.ground_class != kLinksGreen) quality = std::max(quality, 0.3);
  // Only the driver, the 3-wood and the two longest irons feel it.
  switch (s.club) {
    case 0: break;
    case 1: quality = 1 - (1 - quality) * 0.5; break;
    case 7: quality = 1 - (1 - quality) * 0.2; break;
    case 8: quality = 1 - (1 - quality) * 0.05; break;
    default: quality = 1; break;
  }
  if (skill == 0) quality = (quality + 1) * 0.5;
  else if (skill == 1) quality = quality * 0.8 + 0.2;
  else if (skill == 2) quality = quality * 0.9 + 0.1;

  // The easier levels forgive the first steps of a miss.
  int steps = c;
  double k = 1;
  if (skill == 0) {
    steps = std::max(c - 2, 0);
    k = 0.6;
  } else if (skill == 1) {
    steps = std::max(c - 1, 0);
    k = 0.8;
  }
  double power_snap = (!sand && w.method == LinksSwingMethod::Mouse) ? 0 : ls.power_snap;
  double speed = std::max(lie.lie_power - power_snap * steps * k, 0.25);
  s.spin_scale = std::max(lie.lie_spin - steps * ls.spin_snap * k, 0.25);
  s.speed_scale = std::min(speed, quality);

  if (sand) {
    s.path_error = 0;
    int contact = w.contact;
    if (w.method == LinksSwingMethod::PowerStroke && w.left_handed) contact = -contact;
    double sp = 1, sn = 1;
    sand_contact(s, contact, sp, sn);
    s.speed_scale = sp * lie.lie_power;
    s.spin_scale = sn * lie.lie_spin;
  }
}

void links_computer_miss(LinksComputerSwing& w, const LinksGolferRatings& g, int club, bool teed_up, bool chip,
                         int ground_class, double feet_to_hole, LinksRand& rng) {
  // The game works in single precision; every stored value is rounded to it.
  auto f32 = [](double x) { return static_cast<double>(static_cast<float>(x)); };
  // Half the sum of two draws below `n` plus n / `bias` (0 when n is 0).
  auto draw = [&rng](int n, int bias) {
    if (n == 0) return 0;
    int a = rng.next() % n;
    int b = rng.next() % n;
    return (a + b + n / bias) / 2;
  };
  auto coin = [&rng] { return rng.next() % 100 < 50; };
  // A plan past the golfer's power costs it steadiness, point for point.
  int forced = w.power > g.max_power ? static_cast<int>(w.power) - g.max_power : 0;
  int line = 0;
  int length = 0;
  if (teed_up) {
    line = draw(100 - (g.tee - forced), 6);
    length = draw(100 - g.tee, 8);
  } else if (chip) {
    line = draw(100 - g.chips, 8);
    length = draw(100 - g.chips, 8);
  } else {
    int r = club < 0 || club > 18 ? 0
            : club <= 6           ? g.woods
            : club <= 9           ? g.long_irons
            : club <= 12          ? g.mid_irons
            : club <= 15          ? g.short_irons
                                  : g.wedges;
    line = draw(100 - (r - 2 * forced), 8);
    length = draw(100 - r, 8);
  }
  const double lie = f32(links_lie_snap(ground_class).miss);
  double power_miss = f32(f32(length * lie) * 0.125);
  double turn = f32(f32(f32(line * 0.5) * lie) * 0.125);
  turn = std::min(turn, g.steady ? 5.0 : 10.0);

  // The direction miss turns the face or the path, either way.
  if (coin()) {
    w.face_deg = coin() ? f32(w.face_deg + turn) : f32(w.face_deg - turn);
  } else {
    w.path_deg = coin() ? f32(w.path_deg + turn) : f32(w.path_deg - turn);
  }
  if (teed_up) {
    // The game means a random sign here but always adds.
    double grow = (rng.next() % 100) * 0.01;
    rng.next();
    power_miss = f32(grow + power_miss);
    grow = (rng.next() % 100) * 0.01;
    rng.next();
    turn = f32(grow + turn);
  }
  if (g.steady) {
    turn = f32(turn * 0.5);
    power_miss = f32(power_miss * 0.5);
  }

  // A miss that would take all the power is backed off, step by step.
  auto keep_positive = [](double power, double step, double k) {
    while (power <= 0) {
      step *= k;
      power += step;
    }
    return power;
  };
  double power = w.power;
  int yards = static_cast<int>(feet_to_hole) / 3;
  if (yards > 230 || coin()) {
    power = f32(power - power_miss);
    if (power <= 0) power = f32(keep_positive(power, power_miss, f32(0.75)));
  } else {
    power = f32(power_miss + power);  // a positive plan stays positive
  }
  if (turn != 0) {
    power = f32(power - f32(turn * 0.5));
    if (power <= 0) power = f32(keep_positive(power, turn, f32(0.4)));
  }
  w.power = power;
}

LinksLaunch links_putt(const LinksStrike& s) {
  double a = s.face_error + (s.setup.face - 30 + s.setup.stance - 30) * kDeg;
  double b = s.path_error + (s.setup.stance - 30) * kDeg;
  Vec3 d{std::sin(a), std::cos(a), 0};
  double speed = std::cos(a - b) * s.power * kLinksPuttSpeed;
  LinksLaunch out;
  out.velocity = turn_z(d * speed, s.aim);
  out.spin = turn_z(Vec3{std::abs(speed) * 2.273642507507853, 0, 0}, s.aim);
  return out;
}

Vec3 links_putt_slope(Vec3 v, Vec3 n) {
  double a = std::atan2(n.y, n.z);
  double c = std::cos(a), sn = std::sin(a);
  double x = v.x, y = v.y * c - v.z * sn, z = v.z * c + v.y * sn;
  double b = -std::atan2(n.x, n.z);
  c = std::cos(b);
  sn = std::sin(b);
  return {z * sn + x * c, y, z * c - x * sn};
}

BallState links_launch_state(const LinksClubTable& clubs, const LinksStrike& s) {
  LinksLaunch l = s.club == kLinksPutter ? links_putt(s) : links_launch(clubs, s);
  BallState b;
  b.on_ground = s.club == kLinksPutter;
  b.velocity = Vec3{-l.velocity.x, l.velocity.z, l.velocity.y} * (1.0 / kFeetPerMetre);
  b.spin = Vec3{-l.spin.x, l.spin.z, l.spin.y} * (2 * kPi);
  return b;
}

}  // namespace olcore
