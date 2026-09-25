# Wave A: lighting, camera and stage (WIP, stopped 2026-09-24 evening)

Lead: lighting + camera + stage. Owned files: `Arena/workshop/`, `Arena/render/stage*`,
`Arena/render/stage_env.tres`, `Arena/qa/stage_preview.*`, `Arena/qa/stage_slice_bots.json`.
Spec: `docs/look/reference-study.md` section 3. Targets: `docs/look/img2/menu-b-faceoff.webp` (M2),
`garage-a-assembly.webp` (G1). Bridge additions: `docs/bridge-spec.md`, "workshop_config.shot".

## Where I stopped (owner session limit, coordinator STOP)

Committed as a local WIP commit, not pushed. State:

1. **Owner bug "wheels go through the floor": FIXED, test passing.** Cause: `Bot.place_at` puts the
   root at `max(origin.y, drive radius)`. Right on the arena floor (origin y 0), wrong on anything
   raised: on the 0.12 m turntable the root landed AT the platform top and every wheel sank by its
   whole radius (measured 95 to 120 mm for all 8 drives). Fix, stage side only (Bot untouched):
   `WorkshopStage.seat_on_ground()` stands the machine on its lowest GROUND CONTACT render mesh
   (wheel bodies, `TrackSkin*`, `Leg*`, `HoverSkirt`), measured from geometry every `show_bot`, for
   the hero (turntable, raised or retracted) and the face-off opponent (floor). Test:
   `Arena/tests/stage_seat_test.gd`, 57 checks, every drive within 2 mm on the raised turntable, the
   retracted turntable and the opponent slot, plus "no other part buried". Evidence:
   `docs/aaa/img/wave-a/stage/seat-before-*.jpg` / `seat-after-*.jpg`.
   Not fixed (not my files): `Bot.place_at` itself still has the max() for any other raised
   origin; fights are unaffected (origin y 0).
2. **Stage rig, post, floor, room: built** (below). `workshop_test` 88/0, `stage_animation_test`
   145/0, `render_test` 116/0, `stage_camera_test` 14/0, `warmup_test` 32/0 at the last run.
3. **Director (cameras): built, its test is NOT green yet.** `Arena/tests/stage_director_test.gd`:
   legacy, showroom, face-off, fallback and part checks pass; after the face-off the `garage`
   message was not applied (`shot` empty, and the World SubViewport captured at the start had been
   freed) and two x-position checks are off in headless. Next step: find what frees the fight's
   World between messages in the headless run (another agent had `fight.gd` mid-edit with a parse
   error during my run; retest against a clean `fight.gd` first), read viewport size fresh each
   check. Do not add this test to the gate until it passes.
4. **Not done yet:** `scripts/test-arena.sh` full run and `scripts/build-sim.sh`; the final combined
   captures with the models and materials leads' work committed (their WIP was already in the working
   tree during my later captures: new wedge, flipper, wheels); `docs/look/proving-slice.html`;
   the contracts section in `docs/wave-a-contracts.md`; device timing.

## What was built

- **Rig** (`stage.gd`): warm 4300 K key front left 35 deg up 2.6 m, energy 7, soft shadow, the one
  shadow caster; neutral fill 1.75 (4:1); two cold 8500 K rims at 8.5, low and range-limited so they
  never pool on the disc; key/fill specular reduced (0.3 / 0.08) so the glossy disc is not spotted;
  top softbox (emissive, 3.0) + weak omni; two strip lights; black flags on all four sides;
  ReflectionProbe (UPDATE_ONCE, room layer only so a machine never reflects itself).
- **Floor**: `Arena/render/stage/stage_floor.gdshader`, procedural staggered steel plates, seams,
  rivets, roughness breakup, wet patches, all fwidth anti-aliased; flat material kept as fallback.
  Disc top is now black gloss (as G1), edge light thinned to a line.
- **Post** (`stage_env.tres`): AgX (contrast 1.4, exposure 1.0 locked), glow threshold 1.1, Screen,
  SSAO on, SSR on (32 steps; stripped below high by GraphicsQuality), volumetric density 0.02,
  saturation 1.06. Vignette + luminance grain: `stage_post.gdshader`, one multiply quad drawn last,
  never samples the screen (a screen copy would erase the haze). Grain on high only. No chromatic
  aberration: needs a CompositorEffect (post-transparent) and is left for later.
- **Haze**: floor banks lowered under the lowest lens (a lens inside a bank went black and milky);
  the rim bank hides when the platform retracts; practical PAR can clusters on a low back truss
  with haze cones (in frame on the face-off).
- **Face-off**: platform retracts into the floor (0.75 s), hero parks facing the opponent turned 22
  deg to the room; opponent slot at (3.1, 0, -2.5) with a cold top spot, visible cone, lamp head,
  cold rim and its own dry ice; warm floor wash in front of the hero.
- **Director** (`stage_director.gd`): shots showroom 50 mm / faceoff 50 mm (solved so the hero lands
  at 34 % and the opponent at 76 % across, lens 0.26 m) / garage 40 mm (frame 0.31, orbit with
  inertia, turntable pause and 4 s resume) / part 70 mm (category bodies pulled 11 cm out, near and
  far DOF). 750 ms in-out cubic moves with focus pull, drift on 23/17/29 s sines, attract test-fire
  spark (signal `attract_cue`) after 6 s idle. Releases to the rig on no-shot or a fight.
- **QA**: `stage_preview.tscn` flags `--roboteer-shot=`, `--roboteer-slice`, `--roboteer-spark=`,
  `--roboteer-quit-after=`, `--roboteer-measure[=off,...]`, env `STAGE_DEBUG=1`.

## Per tier (estimates; device owed)

| tier | on | est. phone cost of the stage adds |
|---|---|---|
| high (Forward+, A15+) | SSR, SSAO, volumetric fog + FogVolumes, probe, DOF, glow, vignette + grain, practical cones | SSR 1.5 ms, SSAO 1 ms, vol fog 1.5 ms, DOF 1 ms, glow/post 1 ms, probe ~0 per frame; target under 14 ms total (study 3.4) |
| medium (mobile) | probe, DOF, glow, vignette, fake haze | about 4 ms less than high |
| low (GL compat, simulator only) | vignette, fake haze, no probe/DOF/glow/practical cones | readability only |

Mac timing was not usable: the M4 was at load average 12 to 33 with other agents' Godot, Blender
and simulators running, and Metal returned 0 for GPU time. Owed: a device run of the menu and
garage for 60 s each at 60 fps (study 3.7), with the drop order SSR, fog, DOF quality, soft shadows.

## Next

1. Green `stage_director_test.gd` (item 3 above), then full `scripts/test-arena.sh` and
   `scripts/build-sim.sh` (find-check for " 2" dupes first).
2. Recapture face-off, showroom, garage, part with the committed models/materials work and build
   `docs/look/proving-slice.html` (target | before `docs/look/img2/current-engine-*.jpg` | after).
3. Add section 3 (stage) to `docs/wave-a-contracts.md`: hero is framed from render bounds, parts
   are found by `part_kind`, ground contact by wheel bodies and `TrackSkin*`/`Leg*`/`HoverSkirt`.
4. Device: 60 fps check; AgX vs ACES A/B on a red and a yellow livery; probe re-capture after the
   stage is hidden during a fight.
