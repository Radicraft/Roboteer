# Wave A: drives and AI notes

2026-09-25, drives + AI engineer. Harnesses: `Arena/qa/drives_gauntlet.gd`, `arena_gauntlet.gd`
(see docs/qa/systems-gauntlet.md for the commands). All numbers headless, fixed 60 Hz.

## Where I stopped

2026-09-27, hazards + AI engineer (continuing). Commits, local: `a8bc994` A3/A4 finished,
`c9b45dc` A5, `d2b23dc` bosses as competitors, `205b550` D6. All four items worked; item 3
only partly met (see 3).

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
3. **Bosses as opponents: PARTLY (`d2b23dc`).** Cause found: a boss named as a competitor
   (`bots[1].boss`, the harness's `--boss_b`) never got its BossAI. fight.gd `_make_driver`
   built a plain OpponentAI at the default REGIONAL tier, so the "boss" numbers were a
   catalogue build driven generically, one tier below the challenger. Now `_make_driver`
   builds BossAI for it (same rng draw point), with `competitor = true`, which switches off
   the house bot's restraints (THRESHER's leash home to a gate at the origin, GRUDGE's
   withdraw, ANVIL's hold) exactly as `hunting` does for the released house bot; the
   personality stays. The house bot path is unchanged. The harness now gives the boss the
   challenger's tier (national); `--boss_skill=` changes it. ai_test 216/216 (+3 checks).
   Measuring loop (rebuilt; scratch, so here in full): for each boss and each of
   `box/4wd/horizontal_spinner`, `wedge/4wd/flipper`:
   `Godot --headless --fixed-fps 60 --path Arena --script qa/arena_gauntlet.gd -- --arenas=yard,coliseum --seeds=11,22,33,44 --house=none --boss_b=<id> --a=<build>`
   Boss wins of 8, vs flipper / vs bar spinner:

   | boss | plain driver, regional (4 fights) | BossAI, restraints on | **BossAI competitor** |
   |---|---|---|---|
   | ANVIL | 0/4, 1/4 | 3/8, 4/8 | **4/8, 3/8** |
   | BANDSAW | 1/4, 0/4 | 1/8, 0/8 | **1/8, 0/8** |
   | CINDER | 1/4, 2/4 | 1/8, 1/8 | **3/8, 3/8** |
   | GRUDGE | 0/4, 0/4 | 4/8, 2/8 | **4/8, 0/8** |
   | THRESHER | 3/4, 0/4 | 3/8, 1/8 | **5/8, 0/8** |

   In the 40-60 % band vs the flipper: ANVIL, GRUDGE, THRESHER, CINDER (3/8). Vs the bar
   spinner only ANVIL and CINDER. Not done, and why:
   - **The bar spinner beats slow weapons outright**: a plain national long_low/6wd/crusher
     loses 8/8 to it, a plain wedge/4wd/saw 6/8. THRESHER and GRUDGE take 3 to 6 condition
     and land ~0 weapon hits. That is weapons balance; the weapons engineer is changing the
     spinner (impulse, spin-up, self_destabilise in the uncommitted tree, which these runs
     partly used), so re-measure the spinner column after that lands.
   - **Masters tier does not help** (all bosses at masters: ANVIL 2/8 4/8, BANDSAW 1/8 0/8,
     CINDER 2/8 0/8, GRUDGE 3/8 0/8, THRESHER 1/8 2/8): skill is not the lever.
   - **BANDSAW is weak however built.** Tried, 16 fights a pair: 4WD 0/16 flipper, 2/16
     spinner; 4WD + twin saw 4/16, 0/16; box hull 1/8, 0/8; herding only near walls
     0/16, 0/16. It is thrown by the flipper and loses on judges or a 10 s KO. All reverted;
     the build is the catalogue's. Owner's call whether BANDSAW gets a heavier build (4WD +
     twin saw was the only thing that moved it) since it changes its "fast and light" identity.
   - Armour moves (THRESHER/GRUDGE to HDPE fronts, "excellent vs spinner") changed nothing
     (0/8 vs the spinner either way). Reverted.
4. **D6 displayed turn stat: DONE (`205b550`).** No behaviour change, no golden change. The
   Turn pips (shop, builder, scouting card: all read `Drive.turnPips`) are now scored in
   Catalogue.swift on a new catalogue field `measured_turn_rate` (display only, Godot never
   reads it), when every drive has one. Measured on the pivot bench (turn held, last 2 of
   3 s), hull `turn_rate_factor` divided out, mean of wedge / box / pyramid, 2026-09-27:

   | drive | turn_rate | wedge | box | pyramid | measured_turn_rate | pips old -> new |
   |---|---|---|---|---|---|---|
   | 2WD | 4.0 | 6.03 | 3.98 | 5.20 | 5.1 | 3 -> 4 |
   | 4WD | 3.2 | 5.39 | 4.14 | 4.56 | 4.7 | 2 -> 4 |
   | 6WD | 2.6 | 4.68 | 3.78 | 3.99 | 4.2 | 2 -> 3 |
   | tracks | 1.8 | 3.35 | 2.94 | 3.14 | 3.1 | 1 -> 2 |
   | omni | 8.0 | 5.90 | 6.77 | 6.49 | 6.4 | 5 -> 5 |
   | legs | 1.6 | 1.58 | 1.58 | 1.57 | 1.6 | 1 -> 1 |
   | hover | 4.4 | 4.35 | 4.31 | 4.31 | 4.3 | 3 -> 3 |
   | adaptive | 3.2 | 5.48 | 4.64 | 4.76 | 5.0 | 2 -> 4 |

   Tests: `tests/turn_stat_test.gd` (new, 24/24, ~2.5 min headless) re-measures every drive
   and holds the catalogue to 12 %, and checks Shared and Arena copies agree; the career
   self test has three new checks (969/969 in the Mac harness, the old parts.json fails two).
   Mac harness recipe as in docs/wave-g-g5-notes.md, plus: `ProgressionTypes.swift`,
   `ProgressionEngine.swift`; stubs for `spikeLog`, `ArenaHost`, `StoreService` (`override`,
   `shared.isUnlocked`, the two snapshots) and `PostCampaign.defenceMatch`; `checkDefence`
   and `checkDaily` cut from the harness copy (PostCampaign drags SwiftUI in).
   **For the hull engineer:** long_low on 4WD does not pivot at all (0.6 deg/s against 260 on
   the wedge; 2WD 2.2 and 6WD 1.5 rad/s, a third of the other hulls). Left out of the mean.
   Bench: `Godot --headless --fixed-fps 60 --path Arena --script qa/drives_gauntlet.gd -- --benches=pivot --hull=long_low`.
   Also the 2WD-on-wedge ratio moved from 1.1 (2026-09-25) to 1.5 after the hull changes.

5. **Lifter AI press cycle: STILL BLOCKED (2026-09-27, second request).** The coordinator
   relayed the user's approval, but an approval passed on by another agent is not the
   user's own, and the permission check told me not to retry, so `opponent_ai.gd` is
   untouched. It needs the user to allow the edit directly (answer the permission prompt, or
   add an allow rule). The plan is unchanged (see git history of this file, `70ed477`).
   **Baseline measured on HEAD `3223200`+ (after the weapons balance pass):**
   `qa/weapons_gauntlet.gd -- --weapons=lifter --seeds=11,22,33,44,55,66,77 --secs=150 --opps=plain,w:flipper`
   (lifter wins / pressed_s of 150 / presses):
   - vs box ram: 4/7. Pressed 143.8, 118.0, 137.3, 130.6, 121.5, 130.2, 120.5 s
     (presses 3, 144, 7, 39, 135, 45, 13).
   - vs wedge flipper: **7/7** (the "3 of 7" figure is out of date after the balance pass).
     Pressed 111.9, 61.8, 128.3, 91.5, 106.3, 93.9, 81.7 s (presses 44 to 108).
   All 14 went to the judges. The hold problem is real: 62 to 144 s of 150 held.
6. **Long_low pivot (hull engineer's area): CAUSE FOUND, nothing changed.** The hull rests
   on the floor and carries the weight, so the wheels spin almost unloaded. Scratch probe
   (pivot bench, turn held, deleted afterwards):

   | long_low | as built | wheel grip 1.2 -> 0.4 | hull friction 0 |
   |---|---|---|---|
   | 2WD | 87 deg/s | 2 | 94 |
   | 4WD | 0.5 | 0.1 | 75 |
   | 6WD | 60 | 0 | 67 |

   Hull touching the floor on 120 of 120 ticks in every long_low run (box: 54, 37, 0 of 120
   for 2/4/6WD). The wheels spin at full command (14 rad/s on 4WD) and the machine does not
   turn; with less wheel grip it turns less, so it is not the skid-steer scrub of the long
   wheelbase, and with a frictionless hull it turns 150 times faster. Why: long_low has
   0.02 m clearance at BOTH ends over 1.2 m of length, default 0.11 m wheels and no wheel
   ballast. The wedge had the same fault and got `wheel_radius` 0.14 and
   `wheel_ballast_kg` 2 in its catalogue row (927b4a6), which is the obvious fix to try.
   The residual (75 deg/s against about 166 expected, 237 on the box x 0.7) is the
   wheelbase/track ratio: 0.8/0.5 = 1.6 against 0.8 on the box.

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
