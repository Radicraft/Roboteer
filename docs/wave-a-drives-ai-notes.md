# Wave A: drives and AI notes

2026-09-25, drives + AI engineer. Harnesses: `Arena/qa/drives_gauntlet.gd`, `arena_gauntlet.gd`
(see docs/qa/systems-gauntlet.md for the commands). All numbers headless, fixed 60 Hz.

## Where I stopped

- DONE `b732126` A1 house bots hunt. DONE `aea7064` D2 omni strafe, D3 legs turn + lip, D4 2WD skid.
- NEXT: D5 hover landings, bosses as opponents (item 2), hazards A3/A4/A5, D6 pivot vs stat.

## A1 house bots (b732126)

Three causes, all found by trace:
1. The house bot is sent the competitors' context, which lists ITS OWN position as "released
   house bot, keep clear" and its own corner as a keep-out. `BossAI.think` now strips both when
   `me` is the house bot (its chassis position equals `house_bot_position`).
2. The boss personalities held it back: THRESHER's leash, GRUDGE's low-fuel withdraw, ANVIL's
   2.2 m hold. `BossAI.hunting` (house bot and phase endgame) turns those off; BANDSAW closes to
   1.8 m before it herds.
3. Furnace: the north jet at x = 3.4 fired straight onto the house corner (+X-Z, 2.2 m square
   from x = 2.5). GRUDGE came out at the endgame with drive 0.5 and disrupted. North jets are now
   x = -1.8, -0.3, 1.2 (the arenas test's lane at 1.2 is kept).
Also: the base driver's "get off the hazard" pushes straight away from the hazard, into the wall
behind; for bosses it now slides along the wall (`BossAI.off_the_wall`).

Before / after. Release test (both machines idle, endgame 10 s, 50 s after): GRUDGE 0.0 -> 16.9 m,
THRESHER Crush 1.0 -> 7.9, Yard 4.9 -> 10.9, ANVIL 2.1 -> 13.1 m. Real fights (150 s, endgame 60,
wedge/4wd/flipper vs box/6wd/ram, five arenas x 3 seeds): house bot released in 13, damaged a
machine in 11 (systems gauntlet before: once in 17).

## Drives (aea7064)

| drive | bench | before | after |
|---|---|---|---|
| omni | stick square to nose, 1.5 s | 0.00 m | 2.65 m sideways, yaw 22 deg |
| legs | pivot | 15 deg/s (HEAD; 33 in the gauntlet) | 77 deg/s (catalogue 92 x wedge 0.85 = 78) |
| legs | 90 deg heading turn | 2.2 s | 1.05 s |
| legs | 4 cm lip | stuck | crossed (3.25 s from 3.2 m) |
| 2wd | drift over 7 m | 0.51 m | 0.16 m |
| 2wd | 90 deg heading from rest | never | 0.75 s |
| 2wd | back off a wall | 0.02 m | 1.86 m |
| 2wd | 22 deg ramp | 3.0 s | 1.6 s |

- Omni: wheel friction drops to 15 % in proportion to the sideways part of the stick (the
  rollers), strafe force on the whole machine's mass, yaw held while strafing.
- Legs: feet friction 0.005 while yawing (it steps round), stiffer yaw blend (0.02 s), step-up
  assist: blocked 0.15 s while walking and not touching a machine lifts the body up to 6 cm.
- 2WD: hull material swapped for a 0.08 skid (the nose was a brake).
- Not fixed: 2WD 0-90 % still ~1.0 s (traction bound on two wheels: doubling motor impulse or
  halving skid friction changed nothing); the WEDGE and LONG_LOW noses still stop at a 4 cm lip on
  2WD (the box crosses in 2.15 s). That is the hull resting on the floor (gauntlet bug 16, hull
  engineer).

## Goldens

`hazard_determinism_test` fails yard/grinder/furnace/crush on the tree BEFORE my changes too (the
hull engineer's uncommitted bot.gd / drive_base.gd / wedge.gd), so nothing re-recorded yet.
`mobility_p_test`'s byte-identical parts.json check fails on another agent's uncommitted
Shared/parts.json hunk (flat spinner self_destabilise), not mine.
