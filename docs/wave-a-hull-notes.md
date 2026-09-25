# Wave A, hero hull: new proportions for the starter wedge

2026-09-25, hero hull engineer. Owner decision: move the starter machine's PROPORTIONS toward
the face-off target (`docs/look/img2/menu-b-faceoff.webp`: short, tall, heavy beetle, crest about
1.35 wheel diameters, body about two wheels long) WITH a physics retune, and make the collision
match what is drawn (today the pod ridge is drawn at 0.178 in bot space and the collision top is
0.092).

## Where I stopped / Next (2026-09-25 late, owner's weekly limit at 97 %)

DONE and committed: proportions (0.14 wedge wheel, 0.81 m, crest 0.364 = collision), physics
(shell + crest plate collision, torque scaled, turn factor 0.85, 5 mm sink allowance, 3 kg wheel
ballast = the stall fix), models (wedge, top, sides), evidence (section 5), arenas_test pit fix.

Gauntlet on HEAD, wedge hull, before (old hull) -> after, 150 s fights (section 7):
- ram 9 fights: stuck 34.6 -> 4.2 s a fight, wins 0 -> 2, condition out 0.28 -> 1.46.
- vertical spinner 9 fights: stuck 12.4 -> 0.8 s, wins 3 -> 8.
- The named repros: ram vs flipper seed 11: KO at 12.2 s (stalled) -> goes the distance, 2.0 s
  stuck, won 2 of 3 vs flipper; vertical spinner vs flipper seed 22: KO at 18.5 s (stalled
  14.2 s) -> 0.2 s stuck (lost by a ring-out at 19 s, a fight, not a stall).

NEXT (exact):
1. The rest of the wedge gauntlet was running when I stopped (shock_prod, flipper, lifter,
   twin_saw): scratch runner `wg2_new.sh` / `wg2_headbase.sh`, or rerun:
   `Godot --headless --fixed-fps 60 --path Arena --script qa/weapons_gauntlet.gd -- --weapons=shock_prod,flipper,lifter,twin_saw --hull=wedge --seeds=11,22,33 --opps=plain,w:flipper,w:horizontal_spinner --secs=150 --out=X.jsonl`
   on this tree and on a worktree with 9f950de, 2636dd9, 7857132, 927b4a6 reverted (keep the
   arenas_test fix). Watch the FLIPPER numbers: the nose flip threshold went from 83 N s to more
   than 200 (heavy wheels, short tail); flank 65 -> 82. If the flipper mirror stops turning the
   hero over head-on, consider ballast 2 kg (repros: 0 kg 6.7 s stuck, 3 kg 0.8 s, 6 kg 0.9 s).
2. Suite (`scripts/test-arena.sh`) was mid-run. Failures seen so far, NOT yet attributed:
   venue_kit_test crush kit tiers (the kit lead has that test modified, uncommitted),
   "a bot on the Coliseum spikes is damaged" and "yard/coliseum spikes stay risen", "furnace
   jets 4 s period" (hazard tests: check on the before worktree; if the hero hull causes the
   spike one, it is the taller ride: spikes must reach the 40 mm underside, which is unchanged
   against the floor, so suspect not mine), "a horizontal spinner hit lurches its own chassis"
   (the weapons engineer's uncommitted self_destabilise 0.9 -> 1.2 is in the tree).
   Then determinism goldens: hazard_determinism / hitstop / venue kit hashes that use the
   Tinribs fixture WILL change because the hero hull changed; re-record each deliberately with
   the one-line reason "hero hull pass: wedge proportions + ballast (docs/wave-a-hull-notes.md)",
   after proving (revert the four hull commits -> old hash).
3. arena.pck not exported (not mine). No Swift change needed (new catalogue keys are ignored).

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
