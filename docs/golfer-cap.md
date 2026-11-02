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

## Dad cap

`PlayerLook.cap_style` "dad" (creator: Outfit > Dad cap; about 3 in 10
random golfers and spectators) wears `RB_<person>_dadcap`: an
unstructured low-profile cotton cap. It is built the same way, but:

- no stiffened front or dome: the crown follows the head, and the front
  panels lie on the forehead;
- it sits down on the head (hair pressed to 7.8 cm over the seam, not
  8.5) with the brim seam 1.5 cm over the eyebrows;
- a softer bill, 6.8 cm, 13 degrees down, its sides curved down more;
- an adjustable strap 1.6 cm tall at the back with a half-elliptical
  opening above it, 7 cm across and 3.5 cm tall. The crown vertices round
  the hole are moved onto its edge so it is smooth.

Both caps share one `cap_press` shape (each head vertex goes as far in as
the tighter cap needs).

    ... -s res://tests/golfer_cap_render.gd -- /tmp/caps dad

## Not done yet

- No buckle on the dad cap's strap and no binding round its opening.
- The cap is rigid on the head bone; it doesn't move in the wind.
- No visor option.
