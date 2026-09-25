# Wave A, hero hull: new proportions for the starter wedge

2026-09-25, hero hull engineer. Owner decision: move the starter machine's PROPORTIONS toward
the face-off target (`docs/look/img2/menu-b-faceoff.webp`: short, tall, heavy beetle, crest about
1.35 wheel diameters, body about two wheels long) WITH a physics retune, and make the collision
match what is drawn (today the pod ridge is drawn at 0.178 in bot space and the collision top is
0.092).

## Where I stopped / Next

- [x] Proposal (this file, section 1).
- [ ] Baseline numbers (drive, flip threshold, stall repros) on the tree before any hull change.
- [ ] Hull code (wedge.gd, BotMeshes wedge block, chassis-scoped wheel radius + torque scale).
- [ ] Catalogue wedge block (Shared/parts.json + Arena/data/parts.json, my hunks only).
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

## 2. Measurements

(filled in as they are taken)
