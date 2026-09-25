# Systems gauntlet

2026-09-25, QA lead 2. The weapons gauntlet (`docs/qa/weapons-gauntlet.md`) covered weapons.
This file covers everything else that had only ever been unit-tested: drives, arenas and their
hazards, the house bot, bosses, side events, the Rumble, and the career run end to end.
Written section by section as the runs finish (the session may end at any point).

Build: measurements taken on the working tree over `8094748` with the other agents'
uncommitted work in place (opponent_ai.gd, weapons, parts.json). Each section names the commit.

## Not yet tested (kept current)

- Arenas and hazards
- House bot / enforcer, endgame
- Bosses, side events, Rumble
- Career end to end (Swift self test + campaign sim)
- Screen flow on the simulator
- Page `docs/look/systems-gauntlet.html`

## 1. Drives

Measured on `78a60d4` (working tree with other agents' uncommitted weapon/AI work).
Harness `Arena/qa/drives_gauntlet.gd` (new): a SCRIPTED driver (not the AI) runs each drive
through a bench in the Workshop Test Arena, on the first legal hull for a flipper (the wedge,
for every drive), steel armour, srimech fitted. Real AI fights: the weapons gauntlet with
`--drive=` (flipper subject, national brawler, vs box/4wd/ram and vs the wedge flipper, seeds
11/22/33, 120 s, the Yard).

    Godot --headless --fixed-fps 60 --path Arena --script qa/drives_gauntlet.gd -- --drives=legs --benches=pivot,lip
    Godot --headless --fixed-fps 60 --path Arena --script qa/weapons_gauntlet.gd -- --weapons=flipper --drive=hover --opps=plain,w:flipper --secs=120

### Verdicts

| drive | verdict | one line of evidence |
|---|---|---|
| 2wd | **WEAK** | 0 to 90 % of top takes 1.9 s (others 0.4 to 0.6 s); pulls 0.4 to 0.6 m sideways over 7 m of straight; a 90 degree turn from rest takes 2.4 s; stalls on a 22 degree ramp and dead on a 4 cm lip |
| 4wd | **WORKS** | 3.42 of 3.5 m/s in 0.53 s, clean turns, climbs both ramps; a 4 cm lip holds the wedge for 3.5 s (the wedge hull sits on the floor, below) |
| 6wd | **WORKS** (drive) | 2.99 of 3.0 m/s, best lip crossing of the wheels; but 21 self-inversions a fight against the flipper (srimech bug 1) |
| tracks | **WORKS** | 2.4 of 2.4 m/s in 0.37 s, climbs everything, 3-3 |
| omni | **BROKEN** (strafe) | stick 90 degrees off the nose: moves 0.00 m in 1.5 s and does not turn (bug 2). Everything else is fine and it went 5-1 |
| legs | **WEAK** | pivot 33 deg/s against a catalogue 92 (35 %); 90 degree turn 1.4 s; cannot cross a 4 cm lip; stalled 6.7 s a fight; 2-4 |
| hover | **BROKEN** in a fight | benches are great (5.17 m/s, crosses every ramp and the lip), but 0-6 in fights, killed by component loss at 19 s and 22 s by the flipper without a weapon hit landing (bug 5) |
| adaptive_tracks | **WORKS** | 2.9 of 2.9 m/s, best ramp climber of the tracked drives, 3-3 |

### Bench numbers (script-driven, Test Arena)

| drive | mass kg | rest chassis y (m) | wheel sink mm (centre below radius) | top m/s (cat) | 0-90 % s | pivot deg/s (cat) | 90 deg turn s | stick 90 deg off nose: sideways m | 12 deg ramp | 22 deg ramp | 4 cm lip | wall run: off the wall after | srimech: first upright s / state changes in 8 s / upright in last 2 s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2wd | 47.1 | 0.102 | 0.1, 0.1 | 3.98 (4.2) | 1.92 | 212 (229) | 2.42 | 0.10 | top 1.9 s | **stalls** | **stuck** | 7.3 m, fine | 0.20 / 12 / 8 % |
| 4wd | 50.2 | 0.109 | 2.0, 2.1, 0.2, 0.3 | 3.42 (3.5) | 0.53 | 265 (183) | 0.58 | 2.11 (turns) | 1.5 s | 2.4 s | 5.0 s | 8.0 m, fine | 0.27 / 12 / 9 % |
| 6wd | 45.4 | 0.110 | 0.8 to 0.0 | 2.99 (3.0) | 0.47 | 247 (149) | 0.60 | 2.16 (turns) | 1.6 s | 1.9 s | 2.2 s | 7.7 m | 0.27 / 12 / 9 % |
| tracks | 47.5 | 0.110 | 0.7 to 0.0 | 2.40 (2.4) | 0.37 | 183 (103) | 0.72 | 1.81 (turns) | 1.9 s | 2.1 s | 2.3 s | 6.6 m | 0.27 / 12 / 10 % |
| omni | 44.4 | 0.109 | 1.2 to 0.0 | 3.18 (3.2) | 0.48 | 389 (458) | never | **0.00** | 1.5 s | 2.4 s | 2.1 s | 7.6 m | 0.25 / 12 / 9 % |
| legs | 49.6 | 0.136 | n/a | 1.84 (2.0) | 0.13 | **33 (92)** | 1.42 | 0.59 (turns slowly) | 2.8 s | 2.5 s | **stuck** | 5.4 m | 0.23 / 5 / 100 % |
| hover | 46.4 | 0.198, bobs 18 mm | n/a | 5.17 (5.2) | 0.50 | 248 (252) | 0.43 | 4.39 (slides) | 1.0 s | 1.1 s | 1.1 s | 8.9 m, tilts 18 deg on the wall | 0.22 / 17 / 52 % |
| adaptive_tracks | 50.6 | 0.110 | 0.5 to 0.0 | 2.90 (2.9) | 0.53 | 291 (183) | 0.58 | 1.81 (turns) | 1.6 s | 1.7 s | 2.0 s | 7.4 m | 0.28 / 12 / 10 % |

Ramps are 0.30 m high with a 1 m deck; "top" is the time from a standing start 3.2 m away to the deck.
No machine turned over on a ramp or at a wall; every drive backs off a wall and runs along a
30 degree glancing wall without catching.

Wheel sink at rest: 0 to 2 mm (physics wheel centre below its 0.11 m radius) on every wheeled
drive, including the wedge with a vertical or horizontal spinner (0.8 to 1.5 mm). The 10 mm and 35 mm
sink a stage lead measured does not show in the physics bodies; if it is seen on screen it is a
model offset (the tyre mesh against the collider), not the simulation. Every wedge build reports
its CHASSIS touching `Floor` at rest (box, pyramid and shell do not): the wedge's lip is on the
floor, which is what holds it on the 4 cm lip and fits the weapons gauntlet's bug 1 (wedge stalls).

### Real AI fights per drive (flipper on the wedge, 120 s, the Yard, 3 seeds x 2 opponents)

| drive | hull/armour | W-L | dmg out | dmg in | throws | self inverted | stuck s | close s | fights |
|---|---|---|---|---|---|---|---|---|---|
| 2wd | wedge/steel2 | 4-2 | 0.01 | 0.72 | 14.5 | 7.5 | 1.6 | 66.3 | ram L judges 120s; ram W judges 120s; ram W judges 120s; flip W judges 120s; flip W judges 120s; flip L judges 120s |
| 4wd | wedge/steel2 | 4-2 | 0.01 | 0.53 | 11.67 | 7.67 | 1.58 | 78.47 | ram W judges 120s; ram W judges 120s; ram W judges 120s; flip L judges 120s; flip W judges 120s; flip L judges 120s |
| 6wd | wedge/steel1 | 3-3 | 0.01 | 1.09 | 14.5 | 21.17 | 4.23 | 65.05 | ram W judges 120s; ram W judges 120s; ram W judges 120s; flip L judges 120s; flip L judges 120s; flip L judges 120s |
| tracks | wedge/steel1 | 3-3 | 0.0 | 1.06 | 9.5 | 12.0 | 1.73 | 73.67 | ram W judges 120s; ram L judges 120s; ram W judges 120s; flip W out_of_ 40s; flip L judges 120s; flip L judges 120s |
| omni | wedge/steel1 | 5-1 | 0.01 | 0.78 | 10.0 | 2.17 | 1.0 | 78.28 | ram L judges 120s; ram W out_of_ 35s; ram W judges 120s; flip W judges 120s; flip W judges 120s; flip W judges 120s |
| legs | wedge/steel1 | 2-4 | 0.0 | 0.89 | 12.17 | 2.83 | 6.7 | 62.73 | ram L judges 120s; ram W out_of_ 21s; ram L compone 86s; flip L judges 120s; flip L judges 120s; flip W judges 120s |
| hover | wedge/steel1 | 0-6 | 0.01 | 1.15 | 6.33 | 5.5 | 0.1 | 52.95 | ram L judges 120s; ram L judges 120s; ram L judges 120s; flip L compone 22s; flip L judges 120s; flip L compone 19s |
| adaptive_tracks | wedge/steel1 | 3-3 | 0.0 | 0.96 | 12.67 | 10.0 | 1.4 | 71.67 | ram W judges 120s; ram W judges 120s; ram L judges 120s; flip L judges 120s; flip W judges 120s; flip L judges 120s |

"dmg out" is condition removed from the foe by the subject (a flipper does almost none by design);
"self inverted" counts landings upside down. Every hover loss to the flipper is a component
kill with no weapon hit counted against it: the damage is all `arena` impacts from landings.

### Drive bugs (details and repro)

**D1. HIGH: the srimech cannot right a non-invertible machine. It rolls it a full turn in the
air and lands it on its back again, for ever.** Repro:
`QA_TRACE=1 Godot ... --script qa/drives_gauntlet.gd -- --drives=4wd --benches=flip` (wedge / 4wd /
flipper, 50 kg). Each press gives the chassis 8 to 10 rad/s of roll and 0.8 m of height; `up`
goes -0.99, -0.20, +0.79, +0.94 (upright at the top of the arc), +0.43, -0.52, -1.00: a
360 degree roll, landing inverted. Twelve state changes in 8 s with the button pressed every
time it is down, never staying upright. Same on the box (13 changes, upright 13 % of the last
2 s) and the shell (11, 13 %). The pyramid (invertible) and the walker and hover (bodiless) do
right and stay right. In fights this is the lifter's 36 self-inversions a fight (weapons
gauntlet bug 4), the 6WD's 21 and the flipper's 7 to 9: once a flipper puts you over, your own
srimech keeps you over. For a player this is a knockout they cannot do anything about.
Owner: combat engineer (`Bot._try_secondary`, `SRIMECH_IMPULSE` 150 and the torque impulse,
scaled by mass / 42.8 and by `tip_resistance / flip_resistance`).

**D2. HIGH: Omni cannot strafe.** `--drives=omni --benches=strafe`: stick straight left of the nose
for 1.5 s from rest moves the machine 0.00 m and turns it 0 degrees. `omni.gd` sets both sides'
wheel motors to `v_fwd` (0 when the stick is square to the nose), which holds the four hinged
wheels at zero speed, and pushes the chassis sideways with at most 0.8 g of the CHASSIS mass
through `apply_central_force`: the locked wheels' friction wins. The drive's one selling line
("Strafes and pivots instantly") does not happen. At 45 degrees it just drives forward. Omni
still fights well (5-1) because it drives like a light 4WD.

**D3. MEDIUM: the walker turns at a third of its catalogue rate and cannot step over a 4 cm lip.**
`--drives=legs --benches=pivot,heading,lip`: pivot 32.6 deg/s (catalogue `turn_rate` 1.6 rad/s = 92
deg/s); 90 degree turn 1.4 s; stops dead at a 4 cm step (the chassis bottom is at 0.136 m, but the
feet do not climb). Its blurb is "steps over floor hazards". Stalled 6.7 s a fight, 12 s in one.

**D4. MEDIUM: 2WD is sluggish from rest and cannot climb.** `--drives=2wd`: 1.9 s to 90 % of its
top speed (4WD 0.5 s), drifts 0.42 m off line in 7 m, a 90 degree heading change from rest takes
2.4 s and 1.4 m of travel, and it stops on the 22 degree ramp and dead at the 4 cm lip. Its stat
card says "Light, fast" with the highest turn rate of the wheeled drives (4.0); measured pivot is
the LOWEST of them (212 deg/s against 4WD 265).

**D5. MEDIUM: the hover is killed by being thrown.** 0-6; against the flipper it was component-killed
at 19.3 s and 22.0 s with no weapon hit landing on it, and inverted 6 to 17 times a fight
(`flip_factor` 0.55 makes it the easiest machine to throw). All of its damage is `arena` impact
from landings, which the hover's `hull_bleed` 0.22 turns into drive loss. `--weapons=flipper
--drive=hover --opps=w:flipper --seeds=11`. It also bobs 18 mm at rest and tilts 18 degrees
against a wall (cosmetic).

**D6. LOW: pivot rates do not follow the catalogue.** Measured pivot is 1.4 to 1.8 times the
catalogue `turn_rate` for 4WD, 6WD, tracks and adaptive tracks (TURN_SCRUB_GAIN 2.8), but 0.9 times
for 2WD and 0.85 for omni, so the order the garage's turn stat implies is wrong: tracks (catalogue
1.8, slowest) pivot at 183 deg/s, faster than the stat says 2WD should.

**D7. LOW: an upside-down wedge still drives (1.35 m in 1 s) though the wedge is not invertible,
and the invertible shell cannot drive upside down at all (0.00 m).** `--benches=flip --hull=shell --weapon=ram`.
