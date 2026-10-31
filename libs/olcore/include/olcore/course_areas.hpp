#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>


namespace olcore {

struct LinksSurface;  // olcore/links_ground.hpp

// What a course says about its ground beyond the mesh: the full TerrainTypes
// records (surface physics, hazard and free-drop flags) and the outlines that
// set where each hole's ground ends (out of bounds). See
// docs/formats/crz.md. The GDScript port is game/scripts/course/course_areas.gd;
// change both together.

// One `TerrainTypes` record (version 4, 243 bytes).
struct CrzTerrainType {
  std::uint32_t index = 0;
  // Offsets 0x04 to 0x50: 0x04 LieAngular, 0x08 LieAngularSnap, 0x0C LiePower,
  // 0x10 LiePowerSnap, 0x14 CoefRestitution, 0x18 CoefFriction, 0x1C
  // CoefViscosity, 0x20 Maliability, 0x24 RollingFriction, 0x28
  // RollingThreshold, 0x2C ImpactOffset, 0x30 AngleMiss, 0x34 PowerMiss, 0x38
  // Snap, then six values the game never reads.
  std::array<float, 20> values{};
  std::uint32_t ground_class = 0;  // 0x54
  std::uint32_t category = 0;      // 0x58: the TerrainCategory scripts see
  std::uint32_t flags = 0;         // 0x5C: only bits 0 and 3 are read
  std::string name;                // 0x67, UTF-16
  std::string type_name;           // 0xA7, UTF-16

  float value(std::size_t offset) const { return values[(offset - 4) / 4]; }
  // The game refuses drops here and calls it "In Hazard".
  bool hazard() const { return (flags & 1u) != 0; }
  // Cart paths, concrete, asphalt and walls: "In Free Drop Zone".
  bool free_drop() const { return (flags & 8u) != 0; }
};

std::vector<CrzTerrainType> parse_crz_terrain_types(const std::vector<std::uint8_t>& data);

// How the ball plays off a record (the class defaults come from
// links_surface(int); include olcore/links_ground.hpp to call it). Greens always take the game's green options, as the
// game replaces every green record with them.
LinksSurface links_surface(const CrzTerrainType& t);

// An outline from `Shapes`, `HoleIDShapes`, `OBIDShapes` or `BugIDShapes`: a
// chain of cubic Bezier nodes in course feet (x, y; z is always 0).
struct CourseShape {
  struct Node {
    std::array<double, 2> in, point, out;  // handle in, anchor, handle out
  };
  std::uint32_t id = 0;
  bool closed = false;
  std::array<double, 2> min{}, max{};
  std::uint32_t attributes = 0;
  std::vector<Node> nodes;

  // HoleIDShapes: the hole this outline bounds (1 to 18).
  int hole() const { return static_cast<int>(attributes >> 27); }
  // OBIDShapes: whether this area is out of bounds for hole `number`.
  bool for_hole(int number) const { return number >= 1 && number <= 18 && ((attributes >> (number - 1)) & 1u); }
};

// `Shapes`: a u32 version and three floats, then outlines to the end.
std::vector<CourseShape> parse_shapes(const std::vector<std::uint8_t>& data);
// `HoleIDShapes`, `OBIDShapes`, `BugIDShapes`: a u32 count before the same.
std::vector<CourseShape> parse_id_shapes(const std::vector<std::uint8_t>& data);

using Outline = std::vector<std::array<double, 2>>;

// The polygon the game tests against: every segment cut in eight by halving
// it three times (fewer when the shape has more than 624 segments, so it stays
// under 5,000 points), starting from the last node of a closed shape.
Outline shape_outline(const CourseShape& s);

// Whether (x, y) is inside, by counting edge crossings to the right.
bool outline_contains(const Outline& o, double x, double y);

// Where each hole's ball is in bounds: inside the hole's own outline (if it
// has one) and outside every out-of-bounds area marked for that hole. Course
// feet.
class HoleBounds {
 public:
  HoleBounds() = default;
  HoleBounds(const std::vector<CourseShape>& hole_shapes, const std::vector<CourseShape>& ob_shapes);
  bool in_bounds(int hole_number, double x, double y) const;

 private:
  struct Area {
    std::array<double, 2> min, max;
    Outline outline;
    std::uint32_t mask;  // OB areas: holes it applies to; hole outlines: 1 if set
  };
  static bool inside(const Area& a, double x, double y);
  std::vector<Area> holes_;  // index hole - 1
  std::vector<Area> ob_;
};

}  // namespace olcore
