#include "olcore/links_mouse.hpp"

#include <algorithm>
#include <cmath>

namespace olcore {

namespace {

constexpr double kFrameMs = 16.6668;  // the game's frame, 60 a second
constexpr double kRadToDeg = 57.29578;

// The club's response to the mouse: 1.25 for clubs 0..7, 1.15 for the
// rest, 0.75 for the putter.
double club_response(int club) { return club >= kLinksPutter ? 0.75 : club <= 7 ? 1.25 : 1.15; }

// Power per unit of club speed.
constexpr double kGain[kLinksPutter + 1] = {10.5, 10.5, 10.5, 10.5, 10.0, 9.5, 9.0, 10.5, 9.75, 9.6,
                                            9.35, 9.15, 8.9,  8.9,  8.6,  8.6, 8.0, 8.5,  8.4,  0.75};
// The most power each club gives a mouse swing.
constexpr double kMaxPower[kLinksPutter + 1] = {112, 108, 106, 104, 102, 100, 98, 98, 96, 94,
                                                92,  90,  88,  86,  84,  82,  80, 80, 80, 0};

// The game's wobble: j up to 0.03% (mode 0) or 5% (mode 1), then x(1 + j)
// or x(1 - j) as one draw is below another.
double wobble(double x, int mode, LinksRand& rng) {
  double j = (rng.next() % 100 + 1) * 1e-4 * (mode == 0 ? 0.3 : 5.0);
  int a = rng.next() % 100;
  int b = rng.next() % 100;
  return a < b ? (j + 1) * x : x - j * x;
}

// C's integer division (rounds towards zero), as the game's code does.
int div3(int a) { return a / 3; }

}  // namespace

LinksMouseMeter links_mouse_meter(int screen_width) {
  if (screen_width < 1024) return {278, 75};
  if (screen_width < 1280) return {355, 96};
  return {442, 119};
}

LinksMouseClub::LinksMouseClub(int skill, LinksMouseShot shot, int club, LinksMouseMeter meter)
    : skill_(std::clamp(skill, 0, kLinksSkillCount - 1)),
      shot_(shot),
      club_(std::clamp(club, 0, static_cast<int>(kLinksPutter))),
      meter_(meter) {
  k_ = club_response(club_) * (shot_ == LinksMouseShot::Chip ? 0.75 : 1.0);
  gain_ = kGain[club_];
  max_power_ = kMaxPower[club_];
  if (skill_ == 0) {
    drift_scale_ = 0.02;
  } else if (shot_ == LinksMouseShot::Putt) {
    drift_scale_ = skill_ == 1 ? 0.04 : 0.06;
  } else {
    drift_scale_ = skill_ == 3 ? 0.05 : 0.03;
  }
  top_ = meter_.height - 10;
  slow_ = top_ - 65;
  back_scale_ = 1000.0 / (meter_.height - meter_.ball_line - 1);
  down_scale_ = 640.0 / meter_.height;
  pos_ = meter_.ball_line;
}

double LinksMouseClub::backswing_percent() const {
  double p = std::min((pos_ - meter_.ball_line) * 100 / (top_ - meter_.ball_line), 100.0);
  if (shot_ == LinksMouseShot::Putt) p = (2 + p * 0.01) * p * 0.01 / 3 * 100;
  return p;
}

void LinksMouseClub::step(int dx, int dy, LinksRand& rng) {
  if (done()) return;
  const double reading = backswing_percent();
  int main = dy;
  const double side = -dx;
  straight_ += std::abs(dx);
  // Nothing happens until the mouse comes back.
  if (main < 0 && dir_ == 0) return;
  ++idle_;
  if (main == 0 && dx == 0) {
    // Up to two still frames are skipped; the third counts, three frames long.
    if (idle_ <= 2) return;
  }
  if (dir_ == 0 && main != 0) dir_ = main > 0 ? 1 : -1;
  if (!hold_ && ((dir_ == -1 && main > 0) || (dir_ != -1 && main < 0))) reversed_ = 1;
  if (reversed_ != 0) main = -main;
  s_[3] = s_[2];
  s_[2] = s_[1];
  s_[1] = s_[0];
  s_[0] = Sample{};
  s_[0].dy = s_[0].smooth = s_[0].speed = main;
  if (main != 0 && idle_ > 1) idle_ = 1;
  s_[0].frames = idle_;
  idle_ = 0;
  if (samples_ == 0) {
    samples_ = 1;
    return;
  }
  s_[0].smooth = div3(main + s_[1].smooth * 2);
  s_[0].accel = div3(s_[1].accel * 2 - s_[1].dy + main);
  ++samples_;

  // The speed that drives the club is last frame's, filtered with this one
  // in view: capped at 127, spikes smoothed, a sudden stop carried on.
  if (hold_) s_[1].speed = 127;
  const int prev = s_[1].dy;
  if (prev > 127) {
    over_ = true;
    hold_ = false;
    s_[1].speed = 127;
  }
  if (frame_ > 2 && !over_) {
    const int accel = s_[1].accel;
    if (accel <= 0) low_accel_ = true;
    if (watch_peak_) {
      if (peak_ > main) {
        watch_peak_ = false;
        watch_dip_ = true;
        dip_ = main;
      } else {
        peak_ = main;
      }
    }
    if (watch_dip_) {
      if (dip_ < main) {
        watch_dip_ = false;
        watch_rise_ = true;
      } else {
        dip_ = main;
      }
    }
    if (watch_rise_) {
      if (rise_ >= main) {
        watch_rise_ = false;
        rose_ = true;
      } else {
        rise_frame_ = frame_ + 1;
        rise_ = main;
      }
    }
    if (hold_ && ((rose_ && rise_frame_ == frame_) || (prev + accel > 125 && low_accel_) ||
                  (prev > 110 && accel < 3))) {
      s_[1].speed = div3(prev + s_[2].speed * 2);
      s_[0].speed = div3(main + s_[1].speed * 2);
      hold_ = false;
    }
    if (!hold_ && rounds_ != 0 && (prev > 127 || prev + accel > 110) && phase_ != Phase::Backswing) {
      hold_ = true;
      low_accel_ = false;
      rounds_ = 0;
      s_[1].speed = 127;
    }
  }
  if (reversed_ == 1) {
    dir_ = -dir_;
    reversed_ = 2;
    if (phase_ == Phase::Backswing) {
      rounds_ = 1;
    } else {
      watch_peak_ = true;
      watch_rise_ = false;
      rose_ = false;
      watch_dip_ = false;
      rise_frame_ = 0;
      ++rounds_;
    }
  }
  if (!surge_) {
    if (phase_ != Phase::Backswing && s_[2].speed - s_[1].speed > 50) {
      surge_ = true;
      s_[1].speed = 90;
    }
  } else if (prev == 0 && main == 0) {
    surge_ = false;
  } else {
    // speed * 1.2, truncated as the game's arithmetic does
    const int n = s_[2].speed;
    s_[1].speed = n > 0 ? (6 * n - 1) / 5 : n < 0 ? -((-6 * n - 1) / 5) : 0;
  }

  // The club.
  if (shot_ == LinksMouseShot::Full) {
    double a = s_[1].speed * k_;
    if (reversed_ != 0) a = -a;
    a -= 10 * s_[2].v;
    if (a == 0) a = 1;
    const double w = wobble(a, 0, rng);
    const double dt = s_[1].frames * kFrameMs * 0.001;
    s_[1].v = dt * w + s_[2].v;
    s_[1].pos = s_[2].v * dt + dt * dt * w * 0.5 + s_[2].pos;
    delta_ = (s_[1].pos - s_[2].pos) * 800;
  } else {
    double a = s_[1].speed * k_;
    if (reversed_ != 0) a = -a;
    s_[1].v = wobble(a / (s_[1].frames * kFrameMs), 1, rng);
    s_[1].pos = a;
    delta_ = a;
  }
  if (s_[1].v > 0.2 && moving_ == 0) moving_ = frame_;
  const bool started = moving_ != 0 && moving_ != frame_;
  if (reversed_ == 0 && s_[1].v < 0 && started) {
    s_[1].v = 0;
    s_[1].pos = s_[2].pos;
  }
  if (s_[1].v * last_v_ < 0 && started) {
    // The club turned.
    reversed_ = 3;
    if (phase_ == Phase::Backswing) {
      turned_ = true;
      rounds_ = 1;
    } else if (phase_ == Phase::Downswing) {
      // Turned back before the ball: back to the backswing.
      turned_ = false;
      top_set_ = false;
      phase_ = Phase::Backswing;
    } else {
      phase_ = Phase::Failed;
    }
  }
  if (s_[1].v != 0) last_v_ = s_[1].v;
  if (moving_ != 0) move_club(delta_ / (phase_ == Phase::Backswing ? back_scale_ : down_scale_), side);
  if (!top_set_ && phase_ != Phase::Backswing) {
    // How far back the club went, read as the downswing starts.
    top_set_ = true;
    if (phase_ == Phase::Downswing) backswing_ = reading * 0.01;
  }
  s_[1].drift = drift_;
  if (phase_ == Phase::Impact && !impacted_) {
    impacted_ = true;
    impact(rng);
  }
  ++frame_;
}

void LinksMouseClub::move_club(double delta, double side) {
  if (shot_ != LinksMouseShot::Putt && slow_ < pos_ && delta > 0) {
    // The top of the backswing slows the club.
    delta = (1 - (pos_ - slow_) / 65) * delta * (shot_ == LinksMouseShot::Chip ? 0.3 : 0.25);
  }
  if (phase_ == Phase::Downswing && top_ < pos_ + delta) pos_ = top_;
  pos_ += delta;
  drift_ = std::clamp(drift_scale_ * side + drift_, -50.0, 50.0);
  if (phase_ == Phase::Backswing && turned_) phase_ = Phase::Downswing;
  if (phase_ == Phase::Impact && pos_ <= -120) {
    phase_ = Phase::Failed;
    return;
  }
  if (phase_ == Phase::Downswing && pos_ <= meter_.ball_line && !hit_) {
    phase_ = Phase::Impact;
    hit_ = true;
  }
}

void LinksMouseClub::impact(LinksRand& rng) {
  double speed;
  if (shot_ == LinksMouseShot::Full) {
    speed = (s_[2].v + s_[1].v) * 0.5;
    const double share = std::abs(speed * gain_) / max_power_;
    if (share > 1.2) speed = wobble(max_power_ / gain_, 1, rng) * 1.2;
    if (surge_ && share > 0.9) speed = wobble(max_power_ / gain_, 1, rng) * 0.9;
  } else {
    speed = (s_[3].v + s_[2].v + s_[1].v) / 3;
  }
  stroke_.skill = skill_;
  stroke_.shot = shot_;
  stroke_.club = club_;
  stroke_.speed = speed;
  stroke_.drift = s_[1].drift;
  stroke_.drift_before = s_[3].drift;
  stroke_.down = s_[1].speed;
  stroke_.backswing = backswing_;
  stroke_.straight = straight_;
}

namespace {

constexpr double kPathScale[kLinksSkillCount] = {1, 1.3, 1.7, 2};
constexpr double kPuttFace[kLinksSkillCount] = {0.5, 0.55, 0.6, 0.65};
constexpr double kPuttWindow[kLinksSkillCount] = {0.3, 0.33, 0.36, 0.4};
constexpr double kDriftPowerLoss[kLinksSkillCount] = {120, 120, 80, 80};
constexpr double kBonus[kLinksSkillCount] = {4500, 3000, 2250, 2250};

// Round half away from zero.
int round_away(double x) { return static_cast<int>(x < 0 ? std::ceil(x - 0.5) : std::floor(x + 0.5)); }

}  // namespace

LinksMouseSwing links_mouse_swing(const LinksMouseStroke& m, LinksRand& rng) {
  const int skill = std::clamp(m.skill, 0, kLinksSkillCount - 1);
  const int club = std::clamp(m.club, 0, static_cast<int>(kLinksPutter));
  const double k = club_response(club) * (m.shot == LinksMouseShot::Chip ? 0.75 : 1.0);
  const double gain = kGain[club];
  const double f = m.backswing;
  const double cap = k * 0.8 * 10.5;
  const double speed = std::min(std::abs(m.speed), cap);
  LinksMouseSwing out;
  double x = -m.drift;
  if (skill == 0) {
    if (!(x > -18)) {
      x = -17;
    } else if (x >= 18) {
      x = 17;
    }
  }
  const double t = (m.drift - m.drift_before) * kPathScale[skill];
  double path = t != 0 ? std::atan2(t, static_cast<double>(m.down)) * kRadToDeg : 0;
  if (path > 180) path -= 360;
  path = std::clamp(path, -20.0, 20.0);
  const double stroke_angle = path;
  double face = 0;
  double power;
  double loft;
  if (m.shot == LinksMouseShot::Putt) {
    // The backswing asks for a speed; faster adds a little, slower takes off.
    const double mid = f * 2.5 + 1;
    const double w = 0.5 - kPuttWindow[skill] * f;
    const double e = w / 15;
    double g;
    if (speed > mid + w) {
      g = 1 + e;
    } else if (mid - w <= speed) {
      g = (speed - (mid - w)) / 6 + (1 - e);
    } else {
      g = (1 - e) / (mid - w) * speed;
    }
    loft = g * f;
    power = wobble((f + 2) * f / 3 * 14.6 * g, 1, rng);
    if (std::abs(x) > 18) {
      out.whiff = true;
    } else {
      face = kPuttFace[skill] * path;
    }
    power *= std::abs(1 - std::abs(x / kDriftPowerLoss[skill]));
  } else if (m.shot == LinksMouseShot::Chip) {
    const double want = (cap - 1) * f + 0.1;
    const double g = !(want + 0.2 < speed) && speed < want - 0.2 ? speed / (want - 0.2) : 1.0;
    loft = g * f;
    power = wobble((f + 1) * f * 0.5 * 14.6 * g * 3, 1, rng);
  } else {
    const double fp = std::min(f + 0.05, 1.0);
    const double g = 2 * fp - fp * fp;
    power = wobble(speed * gain * g, 0, rng);
    loft = power / (g * gain * cap) * (f + 0.05);
    const double ax = std::abs(x);
    if (ax > 10) {
      if (ax > 18) {
        out.whiff = true;
      } else {
        face = ax * 0.1 * x;  // hook or slice
      }
    } else {
      path += x;  // pull or push
      face += x * (2 / 3.0);
    }
    power *= std::abs(1 - std::abs(x / kDriftPowerLoss[skill]));
  }
  loft = std::min(loft, 1.0);
  power = std::max(power, 1.0);
  if (power > 145) power = wobble(145, 1, rng);
  face = wobble(face, 1, rng);
  path = wobble(path, 1, rng);
  if (out.whiff) {
    wobble(gain * speed, 1, rng);  // drawn and thrown away, as the game does
    power = 0;
  }
  // A straight stroke earns more power.
  if (std::abs(x) < 1) x = 0;
  const double q = std::clamp(x * -4, -50.0, 50.0);
  const int b = std::clamp(round_away(stroke_angle * -2) + 10, 0, 20);
  out.quality = std::min(static_cast<int>(std::abs(q * 0.2) + std::abs(b - 10) / 2), 15);
  const double bonus = (15.0 - out.quality) * (15.0 - out.quality) / kBonus[skill] + 1;
  loft *= bonus / (225 / kBonus[skill] + 1);
  // Then the swing reaches the shot: the path is eased to two thirds, a
  // putter's face turns the other way, and on the two easier levels a full
  // swing's face and path errors are cut to 40%.
  path *= 0.66667;
  if (m.shot == LinksMouseShot::Putt) face = -face;
  if (m.shot == LinksMouseShot::Full && skill < 2) {
    face *= 0.4;
    path *= 0.4;
  }
  out.power = power * bonus;
  out.face_deg = face;
  out.path_deg = path;
  out.loft = loft;
  return out;
}

}  // namespace olcore
