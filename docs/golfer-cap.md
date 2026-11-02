# Golfer caps

How the realistic people (Microsoft Rocketbox, `tools/golfer/rocketbox.py`)
wear a cap. The Custom (MakeHuman) golfer keeps the cap from
`tools/golfer/cap.py`.

## What a real tour cap measures

Structured, mid-profile six-panel caps (the kind tour players wear), from
the makers' spec sheets (SanMar / Sport-Tek STC17, New Era NE1100, Port
Authority C911):

| Measure | Value |
| --- | --- |
| Crown height (button to brim seam, along the front) | 6 3/8 to 6 5/8 in (16.2 to 16.8 cm) |
| Bill length (seam to edge, centre front) | 2 3/4 in (7.0 cm) |
| Front panels' width along the bottom | 7 1/2 in (19 cm) |

How it sits, from photos of players (including the CC0 range footage used
for the photo golfer):

- the brim seam is about a finger's width (1.5 to 2 cm) above the
  eyebrows, so the bill shades the eyes without hiding them face on;
- the band runs above the ears and drops round the back to the back of
  the skull, above the nape;
- the stiffened front panels stand up off the forehead, and the crown is
  a dome a little bigger than the head, so the button sits above the
  skull rather than on it;
- the bill is pre-curved: its sides bend down well below its middle;
- a ponytail comes out under the back; hair under the crown is pressed
  flat.

## How it is built

`tools/golfer/person_cap.py` builds each person's own cap on their head
(rocketbox.py calls it; run on its own it refits the people in a pack):

1. Landmarks from the head mesh: the nose tip (front-most midline point),
   the nasion a nose length (4.7 cm) above it, the eyebrows 1.2 cm
   above that and the brim seam 1.8 cm above the eyebrows.
2. The skull: an ellipsoid fitted to the head above the eyebrows, with
   anything more than 1.5 cm outside it (ears, a bun) left out.
3. The crown: rays from the middle of the band to the skull, 4.5 mm out
   for the cloth and flattened hair; hair piled more than 8.5 cm above the
   seam is pressed down; then the structured front (up to 1.8 cm off the
   forehead), a fuller top and a dome over the band.
4. The bill (`cap.shell` with a bend): 7 cm long, 11 degrees down, its
   sides bent down towards their ends.
5. The head gets a `cap_press` blend shape that moves anything that would
   poke through the crown (a bun, modelled hair) in under it. FreeGolfer
   turns it on with the cap.

Review renders (Compatibility is fine for shape):

    xvfb-run godot --rendering-driver opengl3 --rendering-method gl_compatibility \
      --path game -s res://tests/golfer_cap_render.gd -- /tmp/caps

## Not done yet

- No adjustable strap or opening at the back (many tour caps are fitted,
  so this is a variation, not an error).
- The cap is rigid on the head bone; it doesn't move in the wind.
- No visor option.
