#pragma once

#include <array>

#include "olcore/links_launch.hpp"

namespace olcore {

// Links 2003's PowerStroke mouse swing, as the game runs it (see
// docs/formats/physics.md, "The mouse swing").
//
// Each frame (the game assumes 60 a second) the cursor's movement in whole
// screen pixels drives a club up and down the swing meter. Pulling the mouse
// back (down the screen) takes the club back; pushing it forward swings it
// down, and the club strikes the ball when it comes back down to the ball
// line. On a full swing the club has momentum (it chases the mouse's speed
// and takes a tenth of a second to catch up); on a chip or putt it follows
// the mouse directly. Sideways movement once the club is moving adds up to a
// drift that hooks, slices or misses the ball. LinksMouseClub does the
// frames and links_mouse_swing turns the stroke into the swing.

enum class LinksMouseShot { Full, Chip, Putt };

// The meter's size in screen pixels for a screen `width` pixels wide: the
// game draws it 278, 355 or 442 high (below 1024, below 1280, and wider),
// with the ball line 75, 96 or 119 up from its bottom.
struct LinksMouseMeter {
  int height = 442;
  int ball_line = 119;
};
LinksMouseMeter links_mouse_meter(int screen_width);

// The stroke at the moment the club meets the ball.
struct LinksMouseStroke {
  int skill = 3;
  LinksMouseShot shot = LinksMouseShot::Full;
  int club = 0;               // 0 driver .. 18, kLinksPutter
  double speed = 0;           // the club's speed at the ball
  double drift = 0;           // sideways drift now, positive to the left
  double drift_before = 0;    // the drift two frames earlier
  int down = 1;               // the mouse's downswing speed, pixels a frame
  double backswing = 1;       // how far back the club went, 0..1
  int straight = 0;           // pixels the stroke moved sideways in all
};

class LinksMouseClub {
 public:
  enum class Phase { Backswing, Downswing, Impact, Failed };

  LinksMouseClub(int skill, LinksMouseShot shot, int club, LinksMouseMeter meter = {});

  // One frame: the cursor moved `dx` pixels right and `dy` down.
  void step(int dx, int dy, LinksRand& rng);

  Phase phase() const { return phase_; }
  bool done() const { return phase_ == Phase::Impact || phase_ == Phase::Failed; }
  // The club's height on the meter, in pixels up from the meter's bottom.
  double club_height() const { return pos_; }
  // The meter's reading: how far back the club is, 0..100 (a putt shows its
  // own curve).
  double backswing_percent() const;
  double drift() const { return drift_; }
  const LinksMouseMeter& meter() const { return meter_; }
  // Valid once phase() is Impact.
  const LinksMouseStroke& stroke() const { return stroke_; }

 private:
  struct Sample {
    int dy = 0, smooth = 0, speed = 0, accel = 0;
    double v = 0, pos = 0, drift = 0;
    int frames = 0;
  };
  void move_club(double delta, double side);
  void impact(LinksRand& rng);

  int skill_;
  LinksMouseShot shot_;
  int club_;
  LinksMouseMeter meter_;
  double k_, gain_, max_power_, drift_scale_, top_, slow_, back_scale_, down_scale_;
  Phase phase_ = Phase::Backswing;
  int dir_ = 0, idle_ = 0, moving_ = 0, samples_ = 0, frame_ = 1, rounds_ = 1;
  bool impacted_ = false;
  // The game's filter over the mouse's speed, for jerks and spikes.
  bool hold_ = false, over_ = false, low_accel_ = true, watch_peak_ = true, watch_dip_ = false,
       watch_rise_ = false, rose_ = false, surge_ = false, turned_ = false, hit_ = false;
  int reversed_ = 0;  // 0 not yet, 1 the mouse just turned, 2 turned, 3 the club turned
  int peak_ = 0, rise_ = 0, dip_ = 0, rise_frame_ = 0;
  double last_v_ = 0, delta_ = 0, pos_ = 0, drift_ = 0, top_pos_ = 0, backswing_ = 1;
  bool top_set_ = false;
  int straight_ = 0;
  std::array<Sample, 4> s_{};
  LinksMouseStroke stroke_;
};

// What the stroke makes of the swing (the face and path in degrees, with the
// signs links_apply_swing takes: positive closes the face or swings left).
struct LinksMouseSwing {
  double power = 0;   // percent, or a putt's power for links_putt
  double face_deg = 0;
  double path_deg = 0;
  double loft = 1;    // multiplies the club's loft
  bool whiff = false;
  int quality = 0;    // 0 (perfectly straight) .. 15; the power bonus shrinks with it
};

// Full swing: power is the club's speed times the club's gain (10.5 for the
// driver down to 8.4 for the wedge), less for a short backswing, and the
// stroke's angle is the path. A drift within 10 pulls or pushes (path by the
// drift, face by two thirds of it); 10 to 18 hooks or slices; past 18 the
// club misses. Chips and putts compare the club's speed with the speed the
// backswing asks for. A straight stroke earns up to 5% (easiest) to 10%
// (hardest) more power.
LinksMouseSwing links_mouse_swing(const LinksMouseStroke& m, LinksRand& rng);

}  // namespace olcore
