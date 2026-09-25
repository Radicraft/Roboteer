# Wave A, hero hull: new proportions for the starter wedge

2026-09-25, hero hull engineer. Owner decision: move the starter machine's PROPORTIONS toward
the face-off target (`docs/look/img2/menu-b-faceoff.webp`: short, tall, heavy beetle, crest about
1.35 wheel diameters, body about two wheels long) WITH a physics retune, and make the collision
match what is drawn (today the pod ridge is drawn at 0.178 in bot space and the collision top is
0.092).

## Where I stopped / Next

- [x] Proposal (this file, section 1).
- [x] Baseline numbers (drive, flip threshold, stall repros) on the tree before any hull change.
- [x] Hull code (wedge.gd, BotMeshes wedge block, chassis-scoped wheel radius + torque scale).
- [x] Catalogue wedge block (Shared/parts.json + Arena/data/parts.json, my hunks only).
- NOTE: until the Blender rebuild lands, the wedge .glb is still the old one: it draws 30 mm
  high and long at the tail against the new physics (the wheels are right: scaled by the engine).
- [ ] Blender: wedge, wheel_standard (radius), plate_wedge_* re-fit, sockets.
- [ ] After numbers, stall repros, full gauntlet on the wedge, suite, goldens with reasons.
- [ ] Evidence: face-off before | after | target, fight camera.

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

