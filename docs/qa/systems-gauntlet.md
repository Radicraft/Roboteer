# Systems gauntlet

2026-09-25, QA lead 2. The weapons gauntlet (`docs/qa/weapons-gauntlet.md`) covered weapons.
This file covers everything else that had only ever been unit-tested: drives, arenas and their
hazards, the house bot, bosses, side events, the Rumble, and the career run end to end.
Written section by section as the runs finish (the session may end at any point).

Build: measurements taken on the working tree over `8094748` with the other agents'
uncommitted work in place (opponent_ai.gd, weapons, parts.json). Each section names the commit.

## Not yet tested (kept current)

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

## 2. Arenas, hazards, endgame and the house bot

Harness `Arena/qa/arena_gauntlet.gd` (new). Two kinds of run:

- **Real fights** on `78a60d4`: wedge/4wd/flipper (national brawler) against box/6wd/crusher
  (national technician), 180 s, endgame 120 s, the career house bot for each arena
  (`CareerEngine.houseBot`: Yard THRESHER at 0.5, Grinder CINDER, Drop Zone BANDSAW, Furnace
  GRUDGE, Crush THRESHER, Coliseum ANVIL), seeds 11/22/33; plus the two-minute opener (120 s,
  endgame 80 s) in four arenas, seeds 11/22.
- **Parked machine benches** on `2636dd9` (after the hull engineer's new wedge): both AIs idle,
  KO count off (`--ko=999`), machine A set down ON a hazard (`--place_a=x,z`), 60 s.

      Godot --headless --fixed-fps 60 --path Arena --script qa/arena_gauntlet.gd -- --arenas=crush --seeds=33 --trace=30
      Godot ... --arenas=drop_zone --secs=90 --house=none --ai_a=idle --ai_b=idle --ko=999 --place_a=0,0
      Godot ... --arenas=furnace --secs=60 --endgame=10 --ai_a=idle --ai_b=idle --ko=999   (house bot release test)

"Warned" means the arena's own `hazard_schedule()` clock (the one the shared telegraph paints)
ran down through the last 1.2 s before the hazard went active. The warn sounds were counted
through the mixer (numbers only, nothing played).

### Verdicts

| arena | hazards | house bot at the endgame | verdict |
|---|---|---|---|
| Yard | **WORKS**: spikes every 6.0 s, 20 of 21 warned, parked machine loses 0.37 in 60 s and 4 parts in 180 s once the endgame holds them up | THRESHER at half speed: released on the tick (120.0 / 80.0) but moves 0.3 to 1.0 m in 60 s; never touches anyone | **WORKS** (house bot BROKEN, bug A1) |
| Grinder | **WORKS**: contact-driven, red on contact; parked on a disc: 4.0 condition and 4 parts off in 60 s | CINDER hunts: 21 to 33 m of travel, closes to 0.5 m; 0 damage dealt (a flipper, by design) | **WORKS** |
| Drop Zone | **WORKS**: pit opens at 40 to 43 s (random 30 to 60), warned with the klaxon, reopens; a machine parked on the lid is out of the arena 0.5 s after it opens (40.5 s) | BANDSAW hunts when idle (6.5 m, to 0.8 m) but only 0.6 m in a real fight | **WORKS**; nobody fell in across three AI fights (the AI avoids it) |
| Furnace | **WORKS**: two banks of three jets every 10 to 11 s, warned; jets 4.0 and 4 parts off in 60 s parked at the north wall; the belt carries a parked machine 6.6 m to the far wall | GRUDGE: **0.0 m** of travel after release in every fight and in the idle test | **WORKS** (house bot BROKEN, A1) |
| Crush | **WORKS** with a start bug: rams every 11 to 14 s, 2 s warning, 4.48 condition and 2 parts in 60 s parked at the west ram; but seed 11 starts with BOTH rams already pressing at 0.0 s (A3) | THRESHER full speed: 0.3 m of travel | **WORKS** (A1, A3) |
| Coliseum | **WORKS**: spikes (2 m patch), two jets, two grinders, turntables; spikes 2.61 and 2 parts in 60 s, grinder 4.0 | ANVIL: 2.0 to 3.4 m of travel, did 0.22 / 0.96 in one fight | **WEAK** house bot; turntable moved a parked machine 0.27 m in 60 s (barely a hazard) |

Endgame: in every fight that reached it, `phase_changed("endgame")`, the arena's `escalated()`
and the house bot's release all happened on the same tick, **120.0 s** in the 180 s fights and
**80.0 s** in the opener (yard 11 and 22, coliseum 22). `rules.endgame_at_s` is read (the progression
notes list it as owed; it is done). About half the fights ended by component kill before the
endgame (the crusher kills in 36 to 103 s).

No machine was ever below the floor (min chassis y 0.00 in every fight) or out of the walls
except by the pit and one Crush ram case (A3). Out-of-arena and pit KOs both end the fight
correctly.

### Hazard and warning table (real fights, 78a60d4)

| arena | seed | result | hazard activations | warned / not (time, ticks of clock) | warn sounds | hazard damage A / B |
|---|---|---|---|---|---|---|
| yard | 11 | B killed 40 s | spikes 7 | 7 / 0 | 8 | 0.00 / 3.03 (impact) |
| yard | 22 | B judges | spikes 21 | 20 / 0.0 s (0) | 21 | 0.33 / 1.77 |
| yard | 33 | B judges | spikes 21 | 20 / 120.0 s (0) | 21 | 0.00 / 0.13 |
| grinder | 11/22/33 | B kill 103 s, A kill 36 s, B KO 141 s | 0, 0, 1 contact | n/a (proximity) | n/a | seed 33: 3.00 / 2.85 |
| drop_zone | 11 | B judges | pit 40, 102, 120 | 2 / 120.0 s (0) | 2 | 0 / 0 |
| drop_zone | 22/33 | B kill 95 s, A kill 40 s | pit 43 / none | 1 / 0 | 1 | ~0 |
| furnace | 11 | A judges | 6 jets x 26 to 27 | 26 each / first bank at 0.2 s (13 ticks) | 54 | 2.17 / 7.97 |
| furnace | 22 | A judges | 6 x 26 to 27 | south bank at 121.2 s (69 ticks) | 56 | 0.00 / 10.09 |
| furnace | 33 | B kill 95 s | 6 x 10 | all | 22 | 0 / 1.09 |
| crush | 11 | B kill 66 s | rams 6 + 6 | 5 each / **both at 0.0 s** (0) | 12 | 0 / 0.10 |
| crush | 22/33 | A out_of_arena win 17 s, 13 s | 1 + 1 | all | 2 to 3 | 0 / 1.07 to 1.71 |
| coliseum | 11/22 | B kill 75 s, 103 s | jets 7 to 10, spikes 12 to 18 | spikes at 0.0 s (seed 22) | 17 to 28 | 0 / 0 |
| coliseum | 33 | A judges | jets 26, spikes 21 | spikes at 120.0 s (0) | 47 | 2.17 / 9.76, ANVIL did 0.22 / 0.96 |

### Arena bugs

**A1. HIGH: three of the five house bots never come out at the endgame.** Repro (house bot
release test, both AIs idle, endgame at 10 s):
`--arenas=furnace --seeds=11 --secs=60 --endgame=10 --ai_a=idle --ai_b=idle --ko=999 --trace=300`.
After the release tick the house bot's travel in 50 s: GRUDGE 0.0 m (Furnace; input heading
(0.96, 0.21), straight into its own corner walls, chassis speed 0.00), THRESHER 0.3 m (Crush) and 0.8 m
(Yard, half speed), ANVIL 2.0 m (Coliseum); against CINDER 33 m and BANDSAW 6.5 m. In the nine
real 180 s fights the house bot dealt damage once (ANVIL). Reading of the code, not verified:
the released house bot drives through `BossAI.think`, and THRESHER's `_thresher` sends it home
whenever the target is past `LEASH_M` ("It does not chase"), GRUDGE's `_grudge` withdraws when
its flame reserve is low (its fuel is spent ticking over in the corner), ANVIL holds a wall. The
Stage 5 boss personalities override the brief v4 "leaves the corner for good and hunts".
Scrapyard (THRESHER), Championship Furnace (GRUDGE) and Crush (THRESHER) and the Masters Furnace
and Crush therefore have no endgame threat at all. Owner: combat engineer (fight.gd house bot)
and AI (boss_ai.gd).

**A2. MEDIUM: two machines can sit locked together for a minute and nothing ends it.** Yard
seed 33 (78a60d4): from 30 s to 104 s the flipper and the crusher sit 0.6 m apart against the
north wall at 0.00 to 0.03 m/s, both AIs giving heading (0, 0) with fire held; the KO count stays at
0.00 to 0.05 (the crusher is "engaged" because it keeps removing a little condition, and the
gripped flipper is treated the same). Ended by component kill at 104 s. The same shape at
2636dd9 in the Crush, seed 33, 133 to 137 s (both 0.00 m/s in a corner). Stuck-together seconds
per fight reached 95 s (yard 33), 54 s (grinder 11), 47 s (drop zone 22), 34 s (furnace 33). The
inactivity house bot does not come out because the machines are "in contact".

**A3. LOW: some hazards start the fight already firing, unwarned.** Crush seed 11: both rams
active on the first fighting tick (0.0 s) with no warning; Yard and Coliseum seed 22: the spikes are up
at 0.0 s. A machine is not on either at the spawn, so it is harmless unless someone spawns close
(parked at (4.2, 1.2) beside the east ram at 2636dd9, the machine was OUT OF THE ARENA at 0.8 s:
`--arenas=crush --seeds=11 --ai_a=idle --ai_b=idle --ko=999 --place_a=4.2,1.2`; this may be the set-down
overlapping the ram, not a shove).

**A4. LOW: the endgame re-times hazards without the full warning.** At the endgame tick the Yard
and Coliseum spikes go up and stay up, the Drop Zone pit opens and the Furnace's second bank fires
1.15 s after its clock started (69 of the 75 ticks): all with less than the shared 1.25 s. The
endgame has its own horn and sting, so this may be deliberate; flagged because the warning
language promises "identical everywhere".

**A5. LOW: the turntables barely move a machine.** Parked on the Coliseum's west turntable for
60 s, a wedge moved 0.27 m. "Spinning floor discs" read as a hazard in the brief.

## 3. Bosses, the house bot as an opponent, side events and the Rumble

### Bosses as the opponent (`--boss_b=<id>`: the catalogue build with its own BossAI), 180 s, no house bot

Measured on `9f950de`. Two challengers: the wedge/4wd/flipper and a box/4wd/horizontal spinner
(national brawler). Yard and Coliseum, seeds 11 and 22. Counts are out of 4 each.

    Godot ... --script qa/arena_gauntlet.gd -- --arenas=yard,coliseum --seeds=11,22 --house=none --boss_b=grudge --a=box/4wd/horizontal_spinner

| boss | vs flipper: boss won | vs bar spinner: boss won | fights and damage | verdict |
|---|---|---|---|---|
| ANVIL (tall tank, axe) | 2 of 4 (kills at 64 s and 168 s) | 1 of 4 | takes 2.1 to 3.9 from the spinner, gives 3.7 to the flipper | **WORKS**: can win, can be beaten |
| BANDSAW (wedge, 2WD, saw) | 1 of 4 | 0 of 4 | deals 0.2 to 1.1 a fight; stalled 45 to 70 s in two fights (2WD, bug D4) | **WEAK** |
| CINDER (box, 6WD, flipper) | 3 of 4 | 2 of 4 | wins on control (throws), 0 damage by design; beaten by damage | **WORKS** |
| GRUDGE (box, tracks, flame) | 0 of 4 | 0 of 4 | 0.3 to 1.2 condition a fight; stuck 36 to 59 s in three of the spinner fights | **WEAK**: never won |
| THRESHER (long low, 6WD, crusher) | 2 of 4 | 0 of 4 | 0.05 to 1.8 a fight | **WEAK** against a spinner |

Every boss can be beaten (the spinner beat all five). GRUDGE never won; BANDSAW won once.

### The house bot (see A1 in section 2)

In 9 real 180 s fights and 8 opener fights the house bot damaged a competitor once (ANVIL,
Coliseum seed 33: 0.22 and 0.96). THRESHER, GRUDGE and ANVIL barely leave the corner at the
endgame; CINDER and BANDSAW hunt. Verdict: **BROKEN** for three of five.

### Side events and the Rumble (`Arena/qa/events_gauntlet.gd`, on `a37bed8`)

AI on every machine. The player side is the ordinary fight AI, which does not know an event's
objective, so scores measure the rules running, not how the event plays.

    Godot ... --script qa/events_gauntlet.gd -- --modes=sumo,gauntlet,pinball,football,wall_smash,rumble --seeds=11,22

| mode | runs to an end | what happened (seeds 11, 22) | verdict |
|---|---|---|---|
| Sumo | yes, `event_result` | best of three: the flipper was pushed off twice, in 11.9 s and 23.8 s; round reset and set-down work | **WORKS** |
| Gauntlet | yes | cleared both (33.3 s with BANDSAW entering behind, 13.0 s before it entered), score 14534 / 16645 | **WORKS** |
| Pinball | yes, on the clock (180 s) | score 0, 0 targets, bumpers or ramps: the AI never touches one | **NOT TESTED** by play (needs a human or an event-aware driver) |
| Football | yes, 180 s | 1-1 draw and 0-1 loss; goals count | **WORKS** |
| Wall Smash | yes, 180 s | 2 of 5 walls, both inside 10 s, then nothing for 170 s | rules **WORK**; never played to 5 walls |
| Rumble (3 machines) | yes, `fight_result` | seed 11: the flipper component-killed and eliminated at mid-fight, the other two fight on, judges at 180 s | **WORKS** |

## 4. Career, end to end

### Swift rules: `-careerSelfTest` on one iPhone 17 simulator (iOS 26.5, Debug, dummy driver)

Built on `1e0bd76`: **ALL PASS, 1018 checks, 2 warnings** (the known pacing warnings: repairing
every fight dips the bank to -44 in Series 1, and the pyramid waits 11 wins). The self test
already simulates the whole run: 20 wins through five Series to the title, Level 100 on the last
final, replays, the wall at Series 2 when locked, the title defence (streaks, arena cycle, pay at
half Series 5, speed step per cycle) and the daily exhibition (seeded arena / rival / twist, zero
scrap, best per day). No separate campaign simulation was added: it would repeat the self test,
and QA does not add Swift files to the project.

### Godot side: real career fights (`Arena/qa/career_gauntlet.gd`, on `1e0bd76`)

The starter-class machine (wedge / 4WD / flipper, heaviest legal armour, AI at the tier's skill)
against every rival that has joined by that tier with its upgrades applied, in the tier's arena,
with the tier's house bot and speed, the rival's temperament, and the round clock the shell sends
(Scrapyard: the 120 s opener with the endgame at 80 s; otherwise 180 / 120). Legal fights:
player 11 wins, rivals 17.

    Godot ... --script qa/career_gauntlet.gd -- --tiers=regional --seeds=11,22

| tier | arena | house bot | rival (build at tier) | legal as sent here | seed 11 | seed 22 |
|---|---|---|---|---|---|---|
| scrapyard | yard | thresher | clatterbox (box/4wd/saw) | yes | rival won judges 120s | player won judges 120s |
| scrapyard | yard | thresher | penny_dread (wedge/2wd/flipper) | yes | rival won judges 120s | rival won judges 120s |
| scrapyard | yard | thresher | scuttle (long_low/2wd/saw) | yes | player won ko 12s | player won judges 120s |
| regional | grinder | cinder | clatterbox (box/4wd/axe) | yes | rival won component_kill 64s | player won ko 175s |
| regional | grinder | cinder | penny_dread (wedge/4wd/flipper) | yes | player won judges 180s | rival won out_of_arena 16s |
| regional | grinder | cinder | scuttle (long_low/2wd/saw) | yes | player won ko 79s | player won ko 75s |
| regional | grinder | cinder | hob_nail (wedge/4wd/axe) | yes | player won judges 180s | player won judges 180s |
| regional | grinder | cinder | cold_snap (pyramid/4wd/vertical_spinner) | yes | rival won out_of_arena 8s | rival won out_of_arena 27s |
| national | drop_zone | bandsaw | clatterbox (box/6wd/horizontal_spinner) | no, 102.4 kg (the shell legalises; not representative) | rival won judges 180s | player won out_of_arena 151s |
| national | drop_zone | bandsaw | penny_dread (wedge/4wd/flipper) | yes | rival won out_of_arena 11s | rival won out_of_arena 14s |
| national | drop_zone | bandsaw | scuttle (long_low/4wd/crusher) | yes | player won judges 180s | rival won out_of_arena 54s |
| national | drop_zone | bandsaw | hob_nail (wedge/6wd/axe) | yes | player won component_kill 45s | rival won component_kill 114s |
| national | drop_zone | bandsaw | cold_snap (pyramid/4wd/horizontal_spinner) | yes | rival won component_kill 155s | rival won judges 180s |
| national | drop_zone | bandsaw | brass_neck (box/6wd/ram) | yes | rival won judges 180s | rival won component_kill 115s |
| championship | furnace | grudge | clatterbox (box/6wd/horizontal_spinner) | no, 106.6 kg (the shell legalises; not representative) | rival won judges 180s | player won ko 81s |
| championship | furnace | grudge | penny_dread (wedge/4wd/vertical_spinner) | yes | rival won judges 180s | rival won judges 180s |
| championship | furnace | grudge | scuttle (long_low/tracks/crusher) | no, 109.4 kg (the shell legalises; not representative) | player won judges 180s | rival won component_kill 113s |
| championship | furnace | grudge | hob_nail (wedge/6wd/crusher) | no, 101.4 kg (the shell legalises; not representative) | player won ko 103s | player won ko 48s |
| championship | furnace | grudge | cold_snap (pyramid/6wd/horizontal_spinner) | no, 100.5 kg (the shell legalises; not representative) | rival won judges 180s |  |
| masters | coliseum | anvil | clatterbox (box/6wd/horizontal_spinner) | no, 110.6 kg (the shell legalises; not representative) | rival won ko 151s | player won judges 180s |
| masters | coliseum | anvil | penny_dread (wedge/6wd/vertical_spinner) | no, 102.8 kg (the shell legalises; not representative) | rival won ko 61s | rival won component_kill 19s |
| masters | coliseum | anvil | scuttle (long_low/tracks/crusher) | no, 112.4 kg (the shell legalises; not representative) | player won ko 90s | rival won component_kill 133s |

The rows marked "no" are a harness limit: it applies rival upgrades without
`CareerEngine.legalise`, so they fought an over-weight rival the shell would never send (the self
test checks every rival is legal in every Series on the Swift side).

What the fights show: career fights reach a result at every tier and arena with the house bot
present, and the opener ends at 120 s. COLD SNAP (pyramid / vertical spinner) throws the starter
out of the Grinder at 7.5 s and 27 s; PENNY DREAD puts it in the Drop Zone pit at 10.9 s and 14.2 s.
The starter flipper wins mostly on the cards and loses when it is turned over (bug D1).

## Ranked bugs (all sections)

| # | severity | bug | owner | repro |
|---|---|---|---|---|
| 1 | HIGH | **D1** the srimech rolls a non-invertible machine a full turn and lands it inverted again, for ever (wedge, box, shell; every wheeled drive) | combat engineer (`Bot._try_secondary`) | `QA_TRACE=1 Godot ... qa/drives_gauntlet.gd -- --drives=4wd --benches=flip` |
| 2 | HIGH | **A1** THRESHER, GRUDGE and ANVIL do not hunt when released at the endgame (0.0 to 2.0 m of travel); the house bot hurt someone once in 17 fights | combat engineer + AI (`fight.gd` house bot, `boss_ai.gd` leash / reserve) | `qa/arena_gauntlet.gd -- --arenas=furnace --endgame=10 --ai_a=idle --ai_b=idle --ko=999 --trace=300` |
| 3 | HIGH | **D2** Omni cannot strafe: stick square to the nose moves 0.00 m | combat engineer (`omni.gd`) | `qa/drives_gauntlet.gd -- --drives=omni --benches=strafe` |
| 4 | MEDIUM | **D5** hover machines are component-killed by landings (0-6; killed at 19 s and 22 s by a flipper that never hit them) | combat engineer (hover `hull_bleed`, `flip_factor`) | `qa/weapons_gauntlet.gd -- --weapons=flipper --drive=hover --opps=w:flipper --seeds=11` |
| 5 | MEDIUM | **A2** two machines locked together for up to 95 s with no KO count and no house bot | combat engineer (rules: engaged / pin) | `qa/arena_gauntlet.gd -- --arenas=yard --seeds=33 --trace=600` (78a60d4) |
| 6 | MEDIUM | **D3** walker pivots at 35 % of its catalogue rate and cannot cross a 4 cm lip | combat engineer (`legs.gd`) | `qa/drives_gauntlet.gd -- --drives=legs --benches=pivot,lip` |
| 7 | MEDIUM | **D4** 2WD: 1.9 s to 90 % speed, drifts off line, stalls on a 22 degree ramp and a 4 cm lip; BANDSAW (2WD) stalls 45 to 70 s a fight | combat engineer (`2wd.gd`) | `qa/drives_gauntlet.gd -- --drives=2wd` |
| 8 | MEDIUM | GRUDGE never wins as a boss (0 of 8); BANDSAW once in 8 | AI / balance | `qa/arena_gauntlet.gd -- --arenas=yard,coliseum --seeds=11,22 --house=none --boss_b=grudge` |
| 9 | LOW | **A3** Crush rams and Yard / Coliseum spikes can be active on the first tick, unwarned | venue / arena | `--arenas=crush --seeds=11` (activation at 0.0 s) |
| 10 | LOW | **A4** endgame escalation fires hazards with less than the shared 1.25 s warning | arena | Furnace seed 22, south bank at 121.2 s |
| 11 | LOW | **D6** measured pivot order contradicts the turn stat (2WD slowest, tracks faster than rated) | combat engineer / data | `--benches=pivot` |
| 12 | LOW | **D7** an inverted wedge still drives; the invertible shell cannot | combat engineer | `--benches=flip --hull=shell --weapon=ram` |
| 13 | LOW | **A5** Coliseum turntables move a parked machine 0.27 m in 60 s | arena | `--arenas=coliseum --ai_a=idle --ai_b=idle --ko=999 --place_a=-2.9,2.9` |
| 14 | LOW | the wedge's hull rests on the floor (chassis contact with `Floor` at rest on every wedge build, not on box / pyramid / shell): holds it on a 4 cm lip for 3.5 s, and fits weapons gauntlet bug 1 | hull engineer (being rebuilt now) | `--benches=rest,lip` |

Nothing here was fixed by QA.
