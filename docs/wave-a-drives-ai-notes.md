# Wave A: drives and AI notes

2026-09-25, drives + AI engineer. Harnesses: `Arena/qa/drives_gauntlet.gd`, `arena_gauntlet.gd`
(see docs/qa/systems-gauntlet.md for the commands). All numbers headless, fixed 60 Hz.

## Where I stopped

2026-09-27, hazards + AI engineer (continuing). Commits, local: `a8bc994` A3/A4 finished,
`c9b45dc` A5. Items 1 and 2 DONE; next 3 (bosses) then 4 (D6 displayed turn stat).

1. **A3/A4 hazard warnings: DONE (`a8bc994`).** Why the WIP still failed:
   - The arena ticks through the 3 s countdown (fight.gd runs physics from start_fight),
     so the first FIGHTING tick is arena tick 181, not 0. `warned_phase` folded phases
     against tick 0, so a spike rise or ram press fell in the countdown and was still on at
     FIGHT. It now judges the phase at `FIGHT_START_TICKS` (181) with 2 ticks of slack, and
     the Crush rams count their whole 3.1 s stroke as "acting" (was 1 tick).
   - Endgame spike hold: waits the shared warning, but starts at once if the patch is
     already in a (warned) up window and sooner if the cycle's own rise is sooner, so the
     patch never drops between a warned rise and the hold.
   - Furnace endgame lead wall: asked for its first burn exactly one warning after the
     endgame (a merely legal phase left the room cold up to 120 ticks).
   - Spike area 0.34 -> 0.52 m tall: the risen tips stand at 0.42, so a machine RESTING on
     them was never inside the area; damage only landed if the 15-tick cadence caught it
     on the way up (Coliseum seed 59: 11.000 -> 11.000; now 11.000 -> 9.333).
   - arenas_test: the two "stays risen" checks and the Furnace "never cold" check now allow
     the shared warning (at most 76 ticks down, the clock counting down, nothing after);
     that was the outdated expectation. The spike damage check was a real bug (above).
   Evidence: idle gauntlet (command below), seeds 11..55 x 5 arenas: unwarned activations
   11 -> 0 (every hazard's first act 1.4 s or later after FIGHT; pit 21.3 s = endgame 20 +
   1.27 s). arenas_test 150/154 -> 155/155, hazard_warning_test 73/73, events_test 101/101.
   `Godot --headless --fixed-fps 60 --path Arena --script qa/arena_gauntlet.gd -- --arenas=yard,furnace,crush,coliseum,drop_zone --seeds=11,22,33 --secs=40 --endgame=20 --ai_a=idle --ai_b=idle --ko=999 --house=none`
   **Goldens:** `hazard_determinism_test` fails all six arenas (yard 7636ee93, grinder
   c6503df0, furnace f2b9219a, crush 20fe1484, drop_zone 114a50d8, coliseum 8fc758e4 on this
   tree). Grinder has no timed hazard, so at least part of that is other agents' bot/hull
   changes; mine move yard/furnace/crush/drop_zone/coliseum (re-phased seeds, the endgame
   holds, the taller spike area). Not re-recorded, per the rules.
2. **A5 turntables: NOT A BUG (`c9b45dc`).** The repro parks the wedge on the disc's exact
   centre, where it turns on the spot and goes nowhere. Probe, 10 s idle at 0 / 0.6 / 1.1 /
   1.6 m from the centre: heading turned 6.01 / 5.98 / 6.00 / 6.01 rad (the disc turns
   6.0), off-centre orbit the full 6.0 rad. arenas_test now also checks the heading turns
   (1.80 rad in 3 s). If the owner wants the discs to THROW machines, that is a design
   change (rate, or a rim lip), not a fix.
3. **Bosses as opponents**: next.
4. **D6**: coordinator decided: keep the pivot feel, change the DISPLAYED turn stat.

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

## D5 hover (ad57ef3)

Cause: a bodiless drive has no wheels to land on, so a throw brings it down on its hull; the
new drop bench shows it (condition lost, wedge/flipper): hover on its side from 1 m 1.22, 4WD
0.32; upside down 0.90 vs 0.11. Fix: `hover.gd` air trim, fans level it while clearly airborne.
After: side 0.00, upside down 0.41 (top plate intact). Fights (weapons gauntlet, hover flipper,
120 s, seeds 11/22/33): vs the flipper 0-3 -> 2-1, inversions 2 to 5 -> 0, no component kill;
vs the ram 0-3 -> 1-2. Catalogue flip_factor 0.55 left alone (0.8 alone did not help).

## Goldens

`hazard_determinism_test` fails yard/grinder/furnace/crush on the tree BEFORE my changes too (the
hull engineer's uncommitted bot.gd / drive_base.gd / wedge.gd), so nothing re-recorded yet.
`mobility_p_test`'s byte-identical parts.json check fails on another agent's uncommitted
Shared/parts.json hunk (flat spinner self_destabilise), not mine.
