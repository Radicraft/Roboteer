# Wave A: drives and AI notes

2026-09-25, drives + AI engineer. Harnesses: `Arena/qa/drives_gauntlet.gd`, `arena_gauntlet.gd`
(see docs/qa/systems-gauntlet.md for the commands). All numbers headless, fixed 60 Hz.

## Where I stopped

STOPPED 2026-09-25 on the coordinator's call (owner's weekly limit). Commits, all local, unpushed:
`b732126` A1, `aea7064` D2/D3/D4, `ad57ef3` D5 hover + drop bench, `428f2b6` WIP hazards A3/A4.

Next, in order:
1. **Verify the WIP hazard commit (A3/A4).** Idle runs, 40 s, endgame 20, seeds 11..55:
   `Godot --headless --fixed-fps 60 --path Arena --script qa/arena_gauntlet.gd -- --arenas=yard,furnace,crush,coliseum,drop_zone --seeds=11 --secs=40 --endgame=20 --ai_a=idle --ai_b=idle --ko=999 --house=none`
   After 428f2b6: Drop Zone clean every seed; Crush clean except seed 11 west ram at 0.0 s;
   Furnace clean except seed 11 north bank at 0.2 s (13 t) and seed 44 south at the endgame
   1.1 s (66 t); spikes (Yard, Coliseum) still "0.0 s (0 t)" on seeds 11/22 and endgame 20.4 s /
   21.3 s (20 to 38 t). So `warned_phase` is either not reached on the path the harness takes
   (check whether fight.gd calls `setup(rng)` with rng null, or re-seeds, or whether the
   harness counts "active on tick 0" from the schedule before setup) or the harness's warned
   test uses 1.2 s against a clock the hold does not report. First step: print
   `_spike_phase_ticks` and `_ticks` in `_seed_hazards` for yard seed 11. Then run
   `tests/hazard_warning_test.gd` (was 73/73) and `tests/arenas_test.gd` (was 154/154).
2. **A5 turntables** (not started): Coliseum `constant_angular_velocity` moves a parked wedge
   0.27 m in 60 s; `--arenas=coliseum --ai_a=idle --ai_b=idle --ko=999 --place_a=-2.9,2.9`.
3. **Bosses as opponents (item 2)**: measuring run in
   `/private/tmp/claude-502/-Users-white/4f83dc21-2a17-41a2-9bdc-33103197c474/scratchpad/bosses.sh`
   (arena_gauntlet `--house=none --boss_b=<id> --a=<build>`, yard + coliseum, seeds 11/22). On the
   tree after b732126..ad57ef3: ANVIL 2/4 vs the bar spinner, 0/4 vs the flipper; BANDSAW 0/4 and
   0/4 (deals 0.2 to 0.8 to the flipper, stuck 5 to 28 s: still the 2WD wedge nose, see D4).
   CINDER 0/4 and 2/4; GRUDGE 0/4 and 1/4 (was 0/8); THRESHER 1/4 and 2/4 (vs spinner, vs
   flipper). Target 40 to 60 %: every boss is short against the spinner. Nothing changed for
   this item yet. Ideas: BANDSAW on
   a box hull or 4WD in `FALLBACK_BUILDS` / the catalogue `bosses` row; GRUDGE `GRUDGE_RESERVE`
   and its withdraw range.
4. **D6 pivot vs stat** (not started, decision owed): measured pivot / (catalogue turn_rate x hull
   factor) on the wedge: 2WD 1.1, 4WD 1.7, 6WD 1.95, tracks 2.1, adaptive 1.9, omni ~0.8 to 1.0,
   legs now 1.0, hover 1.0. `TURN_SCRUB_GAIN` 2.8 overshoots for 4+ wheels. Changing behaviour
   to the stat makes the starter 4WD pivot 156 deg/s instead of 265: a big feel change for every
   fight and every golden, so it needs the owner's or the combat engineer's nod.
5. Bench commands: `Godot ... --script qa/drives_gauntlet.gd -- --drives=omni --benches=strafe`
   (also `--benches=pivot,heading,lip,straight,drop`, `--hull=box`).

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
