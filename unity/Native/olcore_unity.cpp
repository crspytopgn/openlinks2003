// C interface over libs/olcore for the Unity trial (unity/README.md). Unity
// calls it through P/Invoke (OlCore.cs): a shared library on desktop, and
// compiled from source into the Web build. Engine-independent like olcore.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <vector>

#include "olcore/links_flight.hpp"
#include "olcore/shot.hpp"
#include "olcore/swing.hpp"

#if defined(_WIN32)
#define OL_API extern "C" __declspec(dllexport)
#else
#define OL_API extern "C" __attribute__((visibility("default")))
#endif

namespace {

using namespace olcore;

// The course as two grids: heights (row by row, z then x) and the surface
// raster (Surface codes), each with its own origin and cell size.
class GridTerrain : public Terrain {
 public:
  std::vector<float> h;
  int cols = 0, rows = 0;
  double x0 = 0, z0 = 0, cell = 1;
  std::vector<std::uint8_t> s;
  int scols = 0, srows = 0;
  double sx0 = 0, sz0 = 0, scell = 1;

  double height(double x, double z) const override {
    if (cols < 2 || rows < 2) return 0.0;
    double fx = std::clamp((x - x0) / cell, 0.0, cols - 1.000001);
    double fz = std::clamp((z - z0) / cell, 0.0, rows - 1.000001);
    int c = static_cast<int>(fx), r = static_cast<int>(fz);
    double tx = fx - c, tz = fz - r;
    const float* a = &h[static_cast<std::size_t>(r) * cols + c];
    double top = a[0] + (a[1] - a[0]) * tx;
    double bot = a[cols] + (a[cols + 1] - a[cols]) * tx;
    return top + (bot - top) * tz;
  }
  Surface surface(double x, double z) const override {
    int c = static_cast<int>(std::floor((x - sx0) / scell));
    int r = static_cast<int>(std::floor((z - sz0) / scell));
    if (c < 0 || r < 0 || c >= scols || r >= srows) return Surface::OutOfBounds;
    return static_cast<Surface>(std::min<int>(s[static_cast<std::size_t>(r) * scols + c], 8));
  }
  bool in_bounds(double x, double z) const override { return surface(x, z) != Surface::OutOfBounds; }
};

GridTerrain g_terrain;
std::optional<LinksAero> g_aero;

Vec3 rotate_y(Vec3 v, double a) {
  double c = std::cos(a), s = std::sin(a);
  return {v.x * c + v.z * s, v.y, -v.x * s + v.z * c};
}

}  // namespace

OL_API int ol_version() { return 1; }

OL_API void ol_set_heights(const float* heights, int cols, int rows, double x0, double z0, double cell) {
  g_terrain.h.assign(heights, heights + static_cast<std::size_t>(cols) * rows);
  g_terrain.cols = cols;
  g_terrain.rows = rows;
  g_terrain.x0 = x0;
  g_terrain.z0 = z0;
  g_terrain.cell = cell;
}

OL_API void ol_set_surfaces(const std::uint8_t* codes, int cols, int rows, double x0, double z0, double cell) {
  g_terrain.s.assign(codes, codes + static_cast<std::size_t>(cols) * rows);
  g_terrain.scols = cols;
  g_terrain.srows = rows;
  g_terrain.sx0 = x0;
  g_terrain.sz0 = z0;
  g_terrain.scell = cell;
}

OL_API double ol_height(double x, double z) { return g_terrain.height(x, z); }
OL_API int ol_surface(double x, double z) { return static_cast<int>(g_terrain.surface(x, z)); }

// The player's own Links 2003 executable: turns on the game's ball flight.
// Returns 1 when its tables were found.
OL_API int ol_load_links_exe(const std::uint8_t* bytes, int size) {
  g_aero = find_links_aero(bytes, static_cast<std::size_t>(size));
  return g_aero ? 1 : 0;
}

// One full shot from `from` (bottom of the ball) with a standard club (index
// into standard_clubs, 0 = driver), heading in radians from +z towards +x.
// Writes up to max_samples (x, y, z, t) to path and, to info:
// rest xyz, first landing xyz, carry, total, apex, time, outcome, bounces,
// rest surface. Returns the number of path samples.
OL_API int ol_shot(int club, double power, double accuracy, double aim_deg, double fx, double fy, double fz,
                   double heading, double wind_x, double wind_z, int has_cup, double cx, double cy, double cz,
                   double* path, int max_samples, double* info) {
  const auto& clubs = standard_clubs();
  const Club& c = clubs[static_cast<std::size_t>(std::clamp(club, 0, static_cast<int>(clubs.size()) - 1))];
  SwingInput in;
  in.power = power;
  in.accuracy = accuracy;
  in.aim_deg = aim_deg;
  BallState b = launch_from_swing(c, in, g_terrain.surface(fx, fz));
  b.position = {fx, fy, fz};
  b.velocity = rotate_y(b.velocity, heading);
  b.spin = rotate_y(b.spin, heading);
  BallParams p;
  p.wind = {wind_x, 0.0, wind_z};
  if (g_aero) p.links = &*g_aero;
  ShotOptions opt;
  opt.has_cup = has_cup != 0;
  opt.cup = {cx, cy, cz};
  ShotResult r = simulate_shot(b, p, g_terrain, opt);
  int n = std::min(static_cast<int>(r.path.size()), max_samples);
  // Thin the path evenly when it is longer than the buffer.
  for (int i = 0; i < n; ++i) {
    std::size_t k = r.path.size() <= static_cast<std::size_t>(max_samples)
                        ? static_cast<std::size_t>(i)
                        : static_cast<std::size_t>(i) * (r.path.size() - 1) / (n - 1);
    path[i * 4 + 0] = r.path[k].position.x;
    path[i * 4 + 1] = r.path[k].position.y;
    path[i * 4 + 2] = r.path[k].position.z;
    path[i * 4 + 3] = r.path[k].t;
  }
  double out[] = {r.rest.x, r.rest.y, r.rest.z, r.first_landing.x, r.first_landing.y, r.first_landing.z,
                  r.carry_m, r.total_m, r.apex_m, r.time_s, static_cast<double>(r.outcome),
                  static_cast<double>(r.bounces), static_cast<double>(r.rest_surface)};
  std::copy(std::begin(out), std::end(out), info);
  return n;
}
