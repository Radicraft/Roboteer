# Wave A, hero hull: new proportions for the starter wedge

2026-09-25, hero hull engineer. Owner decision: move the starter machine's PROPORTIONS toward
the face-off target (`docs/look/img2/menu-b-faceoff.webp`: short, tall, heavy beetle, crest about
1.35 wheel diameters, body about two wheels long) WITH a physics retune, and make the collision
match what is drawn (today the pod ridge is drawn at 0.178 in bot space and the collision top is
0.092).

## Where I stopped / Next (2026-09-27)

(HULL FINAL pending the test check in section 12.)

2026-09-27, second hull engineer. All three items done (sections 9 to 11):
- Gauntlet before/after finished (section 9): 48 wedge fights each way, stuck 22.7 -> 1.3 s a
  fight, wins 11 -> 28 of 48.
- The flip question answered (section 10): the hero is NOT unflippable, it is much MORE flippable
  than the old hull (head-on 15 % -> 77 % of clean throws invert it). Ballast set to **2 kg**
  (was 3): same stall cure, flank behaviour closest to the old hull, the flipper gets under the
  flank every time again. No weapon file touched.
- Models (section 11): two pressings a side, the front tyre shown, a peaked facet, grey lower
  body. `docs/aaa/img/wave-a/hull/pass2-faceoff-compare.jpg`, `pass2-hero-crops.jpg`.

Owed by others / next:
1. Goldens: determinism / hazard_determinism / hitstop / venue-kit hashes on the Tinribs fixture
   change with this hull (and again with 2 kg). Re-record from the HULL FINAL commit with the
   reason "hero hull pass: wedge proportions + ballast (docs/wave-a-hull-notes.md)".
   `pause_test` pins "the flipper throws the scripted player out of the yard at tick 342" (combat's
   76300c9, measured on 3 kg): see section 12 for what 2 kg does to it.
2. For the weapons lead (a finding, not changed): the flipper's `_launch_scale` reads the victim's
   `chassis.mass / total_mass`. The wedge's ballast moves hull weight into the wheel bodies, so
   the hero's chassis share falls from 36 % to 27 % (2 kg) and the throw hits the 1.5 clamp. That,
   plus the short tall shell, is why head-on flips went up. A `hull_body_mass()` that counts the
   ballast as hull was measured (section 10) and REJECTED: it made flank flips rare (20 %).
3. Visual gap still open (section 11): the shell top still reads flatter than the target from
   the high face-off camera; the side plate's painted face keeps an orange sill (armour paint).
4. arena.pck not exported (not mine).

Earlier stop (2026-09-25 late, owner's weekly limit at 97 %) for the record:

DONE and committed: proportions (0.14 wedge wheel, 0.81 m, crest 0.364 = collision), physics
(shell + crest plate collision, torque scaled, turn factor 0.85, 5 mm sink allowance, 3 kg wheel
ballast = the stall fix), models (wedge, top, sides), evidence (section 5), arenas_test pit fix.
The "NEXT" list of that stop (gauntlet, suite attribution, goldens) is superseded by the list
above; its suite attribution is in section 8.

## 1. Proposal

Scope rule: every change is WEDGE-SCOPED. The drive blocks (shared by every chassis) do not change,
`FightTypes.WHEEL_RADIUS` stays 0.11 for every other hull, `flipper.gd` and every global physics
setting stay as they are. The wedge already has the hook it needs: `ChassisBase.wheel_radius_min()`
(the pyramid uses it) makes the drive build bigger wheels and scales the wheel model.

| | today | proposed | why |
|---|---|---|---|
| wheel radius (wedge only) | 0.110 (D 0.22) | **0.140** (D 0.28) | the target's big wheels; catalogue `wheel_radius` on the wedge row |
| hull length | 0.90 (4.1 D) | **0.76** (2.7 D) | shortened at the REAR only: the front ramp, lip and flipper pivot are the signed-off ground game and the flipper arm (0.44 long) is a weapon, not mine |
| 4wd wheelbase | x 0.25 / -0.30 (0.55) | x 0.24 / -0.20 (0.44) | short beetle stance; rear tyre inside the shorter tail |
| crest (drawn = collision) | drawn 0.288 over floor, collision 0.202 | **0.36 over floor** both | 1.29 D; pods become collision (two convex shoulder pods), so hits land on the shell and inverted it rests on the pods instead of sinking 7 cm into the floor |
| ground game (lip 15 mm, underside 40 mm, slope angle, flipper pivot relative to the FLOOR) | | **unchanged relative to the floor** | the whole ramp frame moves down by the 30 mm the axle rose |
| chassis mass | 30 kg | 30 kg | catalogue weight rules untouched |
| COM height (from floor) | 0.07 | about 0.10 | taller shell, higher axle; measured against the flipper before accepting |
| wheel motor impulse | 120 x push | x R/0.11 on the wedge only | same force at the tread as today, so acceleration and push stay comparable |

The stall (gauntlet bug 1) is expected to go with the higher axle: the underside and lip keep
their floor clearance but the nose load now sits on a shorter overhang behind bigger wheels. It
will be measured, not assumed; if it persists the next lever is the hull's own skid friction
(a per-body material on the wedge, not a global setting).

## 2. What was built (physics)

| file | change |
|---|---|
| `Arena/bot/part_meshes.gd` | wedge constants: `WEDGE_WHEEL_R` 0.14, `WEDGE_DROP` 0.03 applied to BODY_TOP/BOTTOM, LIP_*; `REAR_X` -0.36 (tail); `wedge_shell_points()`: the shell over the deck (x -0.36 to 0.06, out to +-0.33 over the tyres, top 0.194 under the top plate) |
| `Arena/bot/chassis/wedge.gd` | two convex shapes (wedge + shell); `wheel_radius_min()` from catalogue `wheel_radius`; `wheel_torque_scale()` = R/0.11; `com_local()` from the wedge's own floor; wheel slots always from the catalogue (physics never reads the model); top plate = the crest (outer face 0.224 bot = 0.364 over the floor, 0.42 x 0.64); side plate fills the gap between tyres (0.19 long at x 0.01); rear plate at -0.36; flipper pivot down 30 mm; srimech socket in the channel; `top_y()` = crest |
| `Arena/bot/chassis/chassis_base.gd` | hooks `wheel_torque_scale()` (1.0) and `rear_x()` (-half_len), no change for any other hull |
| `Arena/bot/drive/drive_base.gd` | motor impulse limit times `hull.wheel_torque_scale()` (1.0 everywhere but the wedge) |
| `Arena/bot/bot.gd` | the rear wedge utility bolts to `rear_x()` |
| parts.json (both) wedge row | `com_height` 0.07 -> 0.10, `wheel_radius` 0.14, `turn_rate_factor` 0.85, rear slots -0.30 -> -0.23 (2wd, 4wd), 6wd 0.29 / 0.01 / -0.27 |

## 3. Measurements

Probe: `Arena/tests/_hull_probe.gd` (headless, test arena, Tinribs fixture, opponent idle).
`--flip` adds the flip thresholds (smallest upward impulse under the flank / under the nose that
leaves it inverted 1.2 s later, bisection) and self-righting (put on its back by a flank
impulse, the srimech pressed whenever its cooldown allows, righted = upright for 1 s).

| | before (0.11 wheel, 0.9 m) | after (0.14 wheel, 0.81 m, shell collision) |
|---|---|---|
| wheel radius / axle height (sink) | 0.110 / 0.1075 (2.5 mm) | 0.140 / 0.1375 (2.5 mm) |
| lip over floor / underside | 8 mm / 37 mm | 8 mm / 38 mm |
| collision crest over floor (chassis / top plate) | 0.18 / 0.20 | 0.335 / 0.364 (1.30 D) |
| mass | 44.4 kg | 44.4 kg |
| 90 deg turn from rest | 0.63 s | 0.63 s |
| to 2 m/s / to 3 m/s | 1.07 s / never in the run | 0.95 s / 1.23 s |
| top speed seen | 2.92 m/s | 3.19 m/s |
| distance at 2 s | 2.21 m | 2.34 m |
| pivot on the spot | 253 deg/s | 257 deg/s (300 before `turn_rate_factor` 0.85: the short wheelbase scrubs less) |
| flip threshold, under the flank | 69 N s | 78.5 N s |
| flip threshold, under the nose | 85 N s | 112 N s |
| self-righting | **0 of 5** (the srimech throws it 0.9 m up and it turns a full 360, lands inverted again, every press) | **3 of 3** (righted in 1.0 to 2.0 s, 1 or 2 presses) |

For scale: the flipper's launch is 115 N s x a 0.75 to 1.5 mass scale, so the flipper still turns
it over on a clean flank hit; it takes a better one than before.


## 4. Models (Tools/blender/parts_hero.py)

- Constants follow `part_meshes.gd`: `DROP` 0.03 on every ground-game point, `REAR_X` -0.36,
  `CREST_Y` 0.224, `PIVOT` (0.1115, 0.0677).
- `wedge`: hull loft ends at the new tail and sits 30 mm lower; sponsons fit the 0.20 m gap
  between the tyres; motors moved inboard (z 0.236, clear of the tyre's inner face; they sit
  under the pods now); hinge brackets on the new pivot; sockets written by the part itself
  (wheels from the catalogue row, armour/utility/srimech/weapon_top on the new hull).
  `verify_parts.py --compare` reports every wedge socket move: all deliberate (the engine
  reads wheel slots from the catalogue and pins the front weapon and srimech in `wedge.gd`).
- `plate_wedge_top`: the lid's frame origin is the crest (the physics plate's outer face), the
  deck plate sits down in the channel at the deck, the pods run from the tail over the rear tyre
  (no wrap-down: the tyre reaches the tail) to fenders that wrap down in front of the front tyre;
  underside 0.149 (9 mm over the tyre tops), crest 0.224.
- `plate_wedge_sides`: 0.19 m long (the gap between tyres), louvred upper flank up to 0.140.
- Triangles: wedge 11,260 -> 11,612; top 7,752 -> 8,092 (hdpe 8,220); sides 2,044 -> 1,964.

## 5. Evidence (`docs/aaa/img/wave-a/hull/`)

| file | what |
|---|---|
| `faceoff-compare.jpg` | M2 face-off, `stage_preview --roboteer-shot=faceoff --roboteer-slice`, 1434x660: before (HEAD with the hull commits reverted, a scratch worktree) / after / target |
| `fight-camera-compare.jpg` | fight camera, Yard, desktop fixture, player AI charge, 7 s: before / after |
| `fight-camera-after-12s.jpg` | after, 12 s: the pods and the channel read from above |

Verdict, blunt: the wheels now read as the target's (big, chunky, at the corners) and the shell
stands clear over them, so the buggy read is mostly gone from the face-off. It is still not the
beetle: the flipper ramp is 0.35 m of the machine's 0.81 m and draws as a big flat dark plate,
and the face-off camera sits high enough that the crest reads as a flat slab rather than a
ridged shell. The next gains are the flipper (weapons) and the pod top (models: a stronger ridge
and a break between the two pods), not more hull change.

## 6. The wedge stall (gauntlet bug 1): cause and fix

Measured on HEAD after 8c89474 (Jolt defaults back). Trace of `--weapons=ram --hull=wedge
--opps=plain --seeds=11 --trace=60` on the new hull before the fix: stuck at (1.53, -1.31) for
5 s, AI asking for a sweeping turn (left wheels 0.7 rad/s, right 32 rad/s), the chassis touching
the floor, wheel heights 0.139 / 0.117 / 0.125 / **0.104** on a 0.14 wheel: the loaded rear
wheel had sunk 36 mm into the floor and the tail was grounded. The old hull does the same
(front wheels 10.6 mm in at rest, the lip on the floor at 0.6 mm). The mechanism is Jolt's
joint-plus-contact solve converging badly when a light wheel (4 kg) carries a heavy body
(30 kg + weapon + armour): the loaded contact sinks, the hull grounds, the turn cannot scrub.
The combat engineer's global fix (20 velocity steps, 5 mm slop) cured it and broke hazards.

Hull fix, no global setting touched: `wheel_ballast_kg` (catalogue, wedge row, 3 kg). Each wheel
body carries 3 kg of the HULL's weight and the chassis gives exactly that back (`bot.gd
_build_drive`), so the machine weighs the same, BuildRules and the budget are unchanged. Side
effect: a detached wheel takes its 3 kg with it (the remaining machine is lighter by 3 kg).
Plus a 5 mm collision allowance on the wedge wheel (`WHEEL_SINK_ALLOWANCE`) so it rests at the
drawn ride height.

Quick repros (ram and shock prod x plain / flipper x seeds 11, 22, 60 s fights, mean seconds
stuck a fight): ballast 0: 6.7 s, **3 kg: 0.8 s**, 6 kg: 0.9 s.

Probe with the ballast (final):

| | before (HEAD, old hull) | after |
|---|---|---|
| axle at rest (front / rear wheel y) | 0.099 / 0.110 on 0.11 | 0.134 / 0.145 on 0.14 (+5 mm allowance) |
| lip over floor | 0.6 mm (on the floor) | 3.8 mm |
| 90 deg turn from rest | 0.82 s | 0.77 s |
| to 2 m/s / to 3 m/s | 1.25 s / never | 1.15 s / 1.35 s |
| top speed seen / distance at 2 s | 2.75 m/s / 2.14 m | 3.32 m/s / 2.33 m |
| pivot | 201 deg/s | 250 deg/s |
| flip threshold, flank | 65 N s | 82 N s |
| flip threshold, nose | 83 N s | more than 200 N s (the short, heavy-wheeled tail will not go over backwards from a lift under the lip) |
| self-righting | 0 of 5 | 4 of 4 |

(Section 3's first table was taken while the combat engineer's global settings were in the
tree; this one is on HEAD without them, for both hulls.)

## 8. Suite result at 3fcc4d5 (full run finished after the report)

9 of 41 files exited non-zero. Files WITH FAIL lines: arenas_test (the 4 hazard-timing
failures, traced to 428f2b6), venue_kit_test (crush kit tiers, the kit lead's uncommitted test),
weapons_test ("horizontal spinner lurches": the uncommitted self_destabilise 1.2), and one
"every weapon works on every hull" check: `axe/wedge removed nothing`, which COULD be the hull
(the axe on the taller wedge); lifter/apex and lifter/pyramid are not wedge. physics_test,
builds_test, assembly_test, hazard_determinism_test, mobility_p_test and weapons_a_test exited
1 with NO FAIL line (a script error or crash; other agents were editing the tree mid-run):
rerun each alone first. hazard_determinism is expected to need hull goldens (section "Next" 2).

## 9. Wedge gauntlet, before / after (2026-09-27)

`qa/weapons_gauntlet.gd --hull=wedge --secs=150`, seeds 11, 22, 33. BEFORE = a worktree of
c84de51 with 9f950de, 2636dd9, 7857132, 927b4a6 reverted; AFTER = c84de51 (3 kg) and the same
with 2 kg. Both on COMMITTED code: the weapons lead's uncommitted parts.json balance (spinner
spin-up/impulse, twin saw dps) was not in either tree, so the pair is like for like.
Stuck = seconds the subject sat under 0.05 m/s more than 1.5 m from the foe. me_inv = times the
subject was turned over.

Main set, shock_prod / flipper / lifter / twin_saw x plain / w:flipper / w:horizontal_spinner
(36 fights each):

| | before | after, 3 kg | after, 2 kg (FINAL) |
|---|---|---|---|
| wins | 7 / 36 | 25 / 36 | 21 / 36 |
| stuck, s a fight | 21.4 | 1.6 | 1.0 |
| turned over by the flipper (12 fights) | 26 | 66 | 65 |

Per row, stuck s a fight before -> 2 kg: shock_prod plain 54.4 -> 3.7, vs flipper 25.5 -> 0.8,
vs h-spinner 17.9 -> 1.8; flipper plain 29.2 -> 0.5; lifter plain 54.8 -> 0.2, vs flipper
12.4 -> 0.4, vs h-spinner 26.2 -> 0.2; twin_saw plain 15.1 -> 1.1. Worst row after: flipper vs
h-spinner 2.6 s (8.8 on 3 kg). The lost-to-h-spinner rows (0/3 for shock prod, lifter mostly)
are the spinner winning fights, not stalls.

The stall repros, ram / vertical_spinner x plain / w:flipper (12 fights each):

| | before | 3 kg | 2 kg |
|---|---|---|---|
| wins | 4 / 12 | 6 / 12 | 7 / 12 |
| stuck, s a fight | 26.7 (ram plain 61.5) | 2.4 | 2.1 |

Raw rows are not in the repo (scratch jsonl); rerun with the command above in two worktrees.

## 10. The flip question: can a flipper still turn the hero over? (2026-09-27)

The probe's "nose threshold > 200 N s" (section 6) is an impulse at the lip; the flipper does
not throw like that. `flipper.gd` puts `115 N s x launch scale` straight up through the victim
CHASSIS centre plus a spin about the wielder's right axis, and the launch scale is
`(22/48) / (chassis mass / total mass)`, clamped 0.75 to 1.5.

New probe `Arena/tests/_flip_headon.gd` (skipped by the suite): the fixture's wedge flipper
drives at the subject (a legal wedge build of each gauntlet weapon, AI idle) and fires the
moment the subject is on its arm, as the AI does. Head-on: yaw 0, +-10, +-20, 30 deg x lateral
0 / 0.15 m x run-up 1.4 / 0.9 m; `--flank`: yaw +-60, +-90, +-120 x 0.9 / 1.2 m x 0 / 0.15 m.
Counted: inverted 1.5 s after a throw that landed. 4 victims pooled:

| | head-on | flank (60-120 deg) | throws that landed, flank | launch scale | chassis / total |
|---|---|---|---|---|---|
| before (old hull) | 14 / 93 (15 %) | 57 / 96 (59 %) | 96 / 96 | 1.16-1.30 | 17.7 / 45-50 kg |
| 3 kg | 77 / 93 (83 %) | 43 / 60 (72 %) | 60 / 96 | 1.5 (clamped) | 11.4 |
| **2 kg (FINAL)** | 72 / 94 (77 %) | 61 / 96 (64 %) | 96 / 96 | 1.5 (clamped) | 13.5 |
| 3 kg + `hull_body_mass` scale | 51 / 93 (55 %) | 12 / 60 (20 %) | 60 / 96 | 1.16-1.30 | 11.4 |
| 2 kg + `hull_body_mass` scale | 44 / 94 (47 %) | 21 / 96 (22 %) | 96 / 96 | 1.16-1.30 | 13.5 |

(Chassis masses are sim kg, MASS_SCALE 0.52.) In real fights (section 9) the w:flipper opponent
turned the hero over 65 times in 12 fights on 2 kg (26 before), and the hero still won 11 of those
12: self-righting is 4 of 4 on both ballasts (`_hull_probe --flip`: 2 kg righted in 0.13 to
0.17 s, one press; flank impulse threshold 80 N s, 3 kg 82).

Decision: **2 kg**. Stall: 1.0 / 2.1 s a fight vs 1.6 / 2.4 on 3 kg (both cured). Flip: the
risk was "unflippable"; the evidence says the opposite on both, and 2 kg is the one whose flank
behaviour matches the old hull (every flank approach gets the arm under, 64 % vs 59 % invert),
with head-on a little lower than 3 kg. The `hull_body_mass` idea (count the hub ballast as hull
in `_launch_scale`) was built in a worktree and rejected: it made the hero nearly flank-proof.
Head-on went from rare to usual; that is the short, tall beetle doing what beetles do against a
flipper, and the flipper's own numbers are the weapons lead's to tune if it is too much.

## 11. Models pass 2 (2026-09-27): toward the beetle read

Visual only, collision unchanged (`verify_parts.py --compare`: every socket PASS; the lid's
highest point is still the crest, bolts 6 mm proud of it as before). `Tools/blender/parts_hero.py`:

| part | change |
|---|---|
| `plate_wedge_top[_hdpe]` | TWO pressings a side: a rear pod (crest 0.224) ending in a chamfer at x -0.06, and a front pod 14 mm lower and 6 mm narrower each side starting tucked under it, ending over the front tyre (x 0.25) instead of a fender run to the flipper tip (0.425). The orange mass is 0.61 m long, not 0.79; the front tyre shows. Outer face 62 mm under the ridge (was 40), so the facet climbs steeply to the crest. Upper pressing moved onto the rear pod. Two rail bolts a side (was four) to pay for it. |
| `plate_wedge_sides[_hdpe]` | The creased pressing is dark metal, not livery. |
| `wedge` | Sponsons bare titanium, not livery: paint on the shell only, grey metal below, as the target. |

Triangles: top 8,092 -> 8,556 (hdpe 8,220 -> 8,684); sides and wedge unchanged. Hero build about
58.7k (ceiling 60k). `build_parts.BUDGET_NOTE`: top 8,800, wedge 11,700 (it was already 11,612
after the first hull pass, over the 11,500 note).

Evidence (`docs/aaa/img/wave-a/hull/`): `pass2-faceoff-compare.jpg` (M2 face-off,
`stage_preview --roboteer-shot=faceoff --roboteer-slice`, 1434x660, frame at 6 s: before = HEAD
models, after, target), `pass2-hero-crops.jpg` (the hero only).

Verdict, blunt: better, not there. The long buggy nose is gone, the break between the two shell
halves reads, the lower body stops shouting orange, the front wheel reads as a big separate
wheel like the target's. Still missing: from the high face-off camera the shell top reads as a
flat lid (the target's shell is a tall domed pair of plates ABOVE a narrower dark body, about
twice our shell's apparent height; ours is capped at the collision crest); the hdpe side plate's
painted face leaves an orange sill (armour paint, materials); the flipper plate is still a big
flat dark card (weapons / materials: darker lip, scuffing).
