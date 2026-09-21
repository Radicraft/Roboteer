# Paint jobs (wave P, agent G, 2026-09-21)

The ten cosmetic paint jobs of brief v5 section 7. Free, Level gated, one every ten Levels,
and they change nothing about a fight. The catalogue owns the ids, names and Levels
(`Shared/parts.json` -> `progression.paint_jobs`); everything here is the art and the
material.

    Tools/paint/make_paint.py            rebuild all thirty files
    Tools/paint/make_paint.py --check    rebuild, then print the seam numbers

Recraft spend: **16 credits of the 80 budget**. 64 unspent.

## What ships

| file | what |
|---|---|
| `Arena/assets/textures/paint/<id>_albedo.png` | 1024 tileable overlay, greyscale in RGB, coverage in alpha |
| `Arena/assets/textures/paint/<id>_normal.png` | the four embossed ones only: carbon 1024, chequer / circuit / hex 512 |
| `Art/paint/<id>.png` | the 512 square picker preview, a lit neutral panel |
| `Arena/bot/livery.gd` | (livery colour, paint id) -> the material |
| `Roboteer/PaintJobs.swift` | the list, the previews, the picker tile |

## The one idea: a detail overlay, not a texture per colour

Six liveries times ten paint jobs would have been sixty textures. Instead each paint job is
ONE achromatic overlay, hung on the existing painted-metal livery material as a Godot
`detail_albedo`, composited over the player's own colour on the GPU. `detail` is a
`BaseMaterial3D` feature, so the generated shader is the same under Forward+ on the phone
and GL Compatibility in the simulator; a `ShaderMaterial` would have meant re-writing the
clear coat, the normal mapping and the PBR by hand and keeping two of them.

Two blend modes, and which one a paint job takes decides what its texture has to contain:

- **MIX** `ALBEDO = mix(livery, overlay.rgb, overlay.a)`. The overlay carries its own value,
  so the paint is achromatic over the machine's colour: black hazard stripes, a pale racing
  stripe, carbon black, bright circuit traces. Alpha 0 is where the livery shows.
- **MUL** `ALBEDO = mix(livery, livery * overlay.rgb, overlay.a)`. The overlay only shades
  the livery, so the paint stays the player's colour: camo, hex plate, and the micro detail
  on the two metals. It can darken, never brighten, so anything wanting a light mark is MIX.

The overlay rides **UV1**, which means it inherits `PartVisuals.density_matched`'s
`uv1_scale` and lands at the kit's 1600 texels per metre like every other material. One
1024 tile is therefore about 0.64 m of machine: hazard stripes 16 cm apart, chequer squares
8 cm, carbon tows 1 cm.

## Where the paint lands

The chassis `livery` slot and the **HDPE armour plates**, and nothing else. Steel, titanium
and polycarbonate armour stay bare metal and bare plastic, which is what the art direction
asks for and what a real machine looks like: you paint the painted panels.

HDPE is in because it is the one armour material that already wears the livery, and on a
clad machine it is a large part of what a player actually sees: measured on a wedge with
HDPE sides, the chassis's own `livery` surfaces are 0.96 m2 and most of them sit UNDER the
plates, while the HDPE plates are 0.62 m2 of the outside. `part_visuals.gd` gained one
helper, `_hdpe_livery`, for this; with no paint it returns exactly the object it always
returned.

`paint_test.gd` asserts all of that on a real assembled machine.

## The ten

Level, blend, and what each one is. "Cover" is the mean alpha, so how much of the machine
the paint actually covers; the rest is the player's livery showing through.

| id | Level | blend | cover | drawn by | what it is |
|---|---|---|---|---|---|
| `paint_hazard` | 10 | MIX | 0.49 | Python + Recraft wear | Black 45 degree hazard stripes, chipped along their edges. Period 256 px on `(x+y)`, and 1024 divides by 256, so it wraps with no blending at all. |
| `paint_racing` | 20 | MIX | 0.21 | Python + Recraft wear | A Le Mans twin stripe: two broad pale stripes, a thin near-black liner outside each, and the machine's own colour down the middle. |
| `paint_camo` | 30 | MUL | 1.00 | Recraft (camo) | Four tone disruptive camo IN THE MACHINE'S COLOUR, because MUL shades the livery rather than replacing it. A works team's camo scheme, not a borrowed army's. Flat finish: the clear coat is turned down to 0.10. |
| `paint_chequer` | 40 | MIX | 0.49 | Python + Recraft wear | Chequered vinyl over the livery, 128 px squares, with a soft lip at every square edge in the normal map because the vinyl has thickness. |
| `paint_flames` | 50 | MIX | 0.41 | Recraft (flames) | A hot rod flame job: black licks with the classic pale pinstripe just outside them. The show finish of the set, clear coat 0.60 at roughness 0.10. |
| `paint_carbon` | 60 | MIX | 1.00 | Python | 2x2 twill drawn tow by tow: blocks two tows square with the fibre turning 90 degrees between them, individual filaments 4 px apart, the tow crown in the normal map. Lacquer at 0.85. |
| `paint_chrome` | 70 | MUL | 1.00 | Python + Recraft wear | Mirror chrome, and this one is almost entirely material: metallic 1.0, roughness 0.055, no clear coat. The overlay carries only the polish swirl. |
| `paint_circuit` | 80 | MIX | 0.14 | Python | Printed circuit traces with pads and vias, generated as a seeded random walk on a 64 px lattice drawn on a torus. Recraft draws circuit boards with invented lettering on them, which is exactly what a texture must not have. |
| `paint_hex` | 90 | MUL | 1.00 | Python | Hexagonal armour plate, seamed and chamfered, with a stable per plate value variation. |
| `paint_gold` | 100 | MUL | 1.00 | Python | Champion gold, engine turned the way a trophy is finished: metallic 1.0, roughness 0.24, gold albedo, jewelled swirl in the overlay. |

## The tiling method

Nothing here is left to the generator. Two families:

**Drawn** (hazard, racing, chequer, carbon, circuit, hex, gold, chrome) are built from
functions whose period divides 1024 exactly, or drawn on a torus. The hex lattice is worth
recording: `a = (128, 0)`, `b = (64, 102.4)`, so `(1024, 0) = 8a` and `(0, 1024) = 10b - 5a`
and both wraps land exactly on a lattice point. The hexes are squashed 7.6 % against a
regular hexagon, which no eye finds and which buys an exact tile. The per plate value
variation has to be invariant under BOTH of those lattice moves or it puts the seam straight
back in.

**Generated** (camo, flames) are mirror blended at the borders, the G2 trick from
`docs/graphics-textures-notes.md`, and then **re-quantised**: both border columns are fed the
same blended value, so they snap to the same flat tone and the wrap is exact rather than
merely smooth. The flame stencil is also ROLLED first so its busiest rows and columns land on
the tile border, because a mirror blend keeps whatever it is given and two empty margins
blended together make a clean band of bare paint right across the machine once per tile,
which is the loudest tiling tell there is.

**A Recraft wear layer serves all ten.** Two generations (polish swirls, stone chips),
flattened and made seamless, reused as the grunge over every drawn pattern and as the
chipping along every painted edge. That is what stops a drawn pattern reading as a vector
graphic. It is the `make_chevron.py` lesson from G2, applied ten times for four credits.

## Seam numbers

`--check` measures the border pair against the **worst** interior pair, not the mean one.
G2 measured against the mean, which is right for a photographed material with no structure
in it and wrong for a drawn pattern: a chequer's tile border lands on a square edge by
construction and reads as four times the average pair while tiling perfectly. What matters is
whether the wrap is worse than a boundary the tile already contains.

| texture | seam dx | seam dy | vs worst x | vs worst y |
|---|---|---|---|---|
| paint_camo_albedo | 0.000 | 0.000 | 0.00 | 0.00 |
| paint_carbon_albedo | 18.243 | 18.251 | 0.99 | 0.99 |
| paint_carbon_normal | 21.048 | 15.532 | 0.59 | 0.25 |
| paint_chequer_albedo | 0.000 | 0.000 | 0.00 | 0.00 |
| paint_chequer_normal | 12.266 | 19.508 | 1.00 | 1.00 |
| paint_chrome_albedo | 0.053 | 0.018 | 0.01 | 0.00 |
| paint_circuit_albedo | 1.206 | 1.211 | 0.02 | 0.02 |
| paint_circuit_normal | 2.879 | 2.461 | 0.15 | 0.06 |
| paint_flames_albedo | 0.000 | 0.000 | 0.00 | 0.00 |
| paint_gold_albedo | 1.302 | 1.292 | 0.13 | 0.14 |
| paint_hazard_albedo | 0.000 | 0.000 | 0.00 | 0.00 |
| paint_hex_albedo | 1.085 | 0.000 | 0.03 | 0.00 |
| paint_hex_normal | 11.621 | 0.000 | 1.00 | 0.00 |
| paint_racing_albedo | 0.000 | 0.000 | 0.00 | 0.00 |

Every one is at or under 1.00: no paint job's wrap is the loudest boundary in its own
texture.

## The credits, itemised

| generation | credits | kept | why |
|---|---|---|---|
| wear layer, 2 candidates | 4 | both | one for polish swirls, one for stone chips; reused by all ten |
| flames, 3 candidates | 6 | 1 | the pick has the most licks and the most even coverage. The bolder reject had fewer, larger flames, which tile as wallpaper. |
| camo, 3 candidates | 6 | 1 | the pick is classic woodland with four evenly spread tones. One reject's blobs were too large to tile, the other too fine. |
| **total** | **16** | | 64 of the 80 budget unspent |

Everything else is drawn in Python. Two things were tried with Recraft and abandoned before
spending on them: circuit boards (it writes invented lettering on them) and carbon weave (a
photographed weave cannot be made to tile at an exact tow period).

## Import settings

`Tools/textures/set_import_flags.py` walks `Arena/assets/textures` recursively, so it covers
`paint/` with no change: VRAM compression, mipmaps, and the two channel ASTC normal path on
the four normals. Run the headless import first.

    Godot --headless --path Arena --import
    python3 Tools/textures/set_import_flags.py

An overlay that covers the whole panel (camo, carbon, chrome, hex, gold) is written WITHOUT
an alpha channel, because a texture with no alpha samples 1.0 and Godot then imports it as
ETC2 RGB8 at half the size of the RGBA8 it would otherwise pick. That is 3.5 MB of the pack
for a channel that is a constant. The set costs **12.3 MB** of the iOS pack in total.
