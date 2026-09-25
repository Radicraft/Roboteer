# Wave A: lighting, camera and stage

## 2026-09-25 session (stage lead, resumed from the WIP commit 0a69d7a)

Commits: 5f6ebda, a3da8d7, 71d2585, d200b63, a622ea5, ceaa51f. Not pushed.

**Tests, all green:** `stage_director_test` 34/0, `stage_seat_test` 66/0, `workshop_test` 88/0,
`stage_animation_test` 145/0, `stage_camera_test` 14/0, `render_test` pass, `warmup_test` 33/0.

- **Director test** was red for two reasons, neither in the director's logic:
  1. The test never attaches a host, so `fight.gd` autostarts its fixture after 60 frames, builds a
     new World and takes the stage down mid test (the "World freed between messages" mystery). The
     test now sets `_autostarted` before adding the fight.
  2. The face-off x checks read 0.50 / 1.75 because the director camera was PHYSICS INTERPOLATED:
     `unproject_position` went through the previous tick's pose. The solved pose was right (0.33 /
     0.74 by hand). Fix in `stage_director.gd`: the director camera is `PHYSICS_INTERPOLATION_MODE_OFF`
     (it moves in `_process`). This was also a real on-device lag, not only a test artefact.
- **workshop_test** (fog ring 34 % down instead of 90 %) had the same cause on the RIG camera. The
  "6 lights expected, 11 found" note was stale: the test already expects 12 and finds 12 (intended:
  7 stage spots, softbox omni, floor wash, opponent top and rim, test-fire flash).
- **ui_test frame bias** (0.449 / 0.469 / 0.541 for 0.25 / 0.35 / 0.70, menu 0.418): NOT stage code.
  Same interpolation cause on `ui/camera_rig.gd`'s camera; with the camera's mode OFF the probe reads
  0.250 exactly. A SubViewport does not inherit the root's OFF (probe: root OFF, camera under a
  SubViewport still `is_physics_interpolated_and_enabled() == true`), so `fight.gd`'s root switch never
  reaches the rig, the FX or the venue inside the World. The combat engineer has since fixed it
  (e681e1f rig camera OFF, c56a1ab World SubViewport OFF); the ui_test also had 2 unrelated
  floor-corner/frustum failures, theirs.
- **Owner bug, wheels through the floor on stage screens:** fixed in the WIP (seat by geometry); this
  session added a vertex exact check (box and vertex agree to 0.0 mm for all 8 drives) and found a
  second stage bug: `show_bot` placed the machine facing WORLD +X, so a rebuild while the table was
  turned snapped the machine to one world heading and the face-off park could be off by the table's
  angle. Now placed along the table's own +X; tested.
- **Do wheels sink in FIGHTS? Yes, and it is physics.** Headless, slice hero (wedge 4wd flipper) vs
  the slice opponent (box 4wd vertical spinner), lowest vertex vs a raycast floor:

  | machine | tick 30 | tick 90 to 150 (countdown, at rest) | tick 240 to 420 (fighting) |
  |---|---|---|---|
  | hero 4wd, wheel collision shapes | +0.1 mm | -10.4 to -10.6 mm | -10.6, then -3.7 mm |
  | hero 4wd, wheel render meshes | +0.6 mm | -9.9 to -10.0 mm | -10.0, then +0.5 mm |
  | opponent 4wd spinner, shapes | -1.9 mm | -1.9 mm | -34.6 to -36.9 mm |
  | hero tracks, wheel shapes / belt meshes | +0.1 / -9.6 mm | -10.1 / -20.4 mm | -1.2 / -14.9 mm |
  | hero 2wd, 6wd, omni, legs (shapes, at rest) | | -0.0, -10.3, -10.4, -13.8 mm | |

  The render follows the physics within 0.6 mm for wheels, so the sink is contact depth in the Jolt
  solver (the heavier hero settles ~10 mm into the floor; the spinner machine pushes a wheel 35 mm in
  once its weapon runs, probably the spinner's reaction on the chassis). Physics and determinism:
  reported to the lead for the combat engineer, not touched. One presentation part: the `TrackSkin*`
  belts draw ~10 mm below the wheel shapes they wrap (models).
- **Tuning pass (face-off first):** hero parked three quarters to the lens (FACEOFF_NOSE_TO_ROOM 22 ->
  85), opponent slot nearer (3.1,-2.5 -> 2.5,-1.9) and facing out (+14 instead of -16), rim energy 8.5
  -> 5 and rim specular 0.3 (the white blob on the wedge and at the rear wheels was the cold rim's
  specular on bare steel, found with the new `--roboteer-hide=` flag), glow tighter (threshold 1.6, no
  wide levels), PAR lenses half size and half emission, floor wash aimed in front of the hero with low
  specular, plate floor a touch lighter within the 0.04 guard (a 0.09 plate made no visible
  difference: the floor needs light, not albedo). Showroom and garage open with the table at -15 deg.
- **Proving slice page:** `docs/look/proving-slice.html`. Blunt distances: face-off and showroom about
  a third of the way, garage a quarter (no room), part pull-out about 40 %. Biggest gaps in payoff
  order: the hero model's silhouette (models), the garage room (art), light on the floor plus visible
  haze (stage), a readable plinth (stage), a hall behind the face-off (venue kit).

## 2026-09-25 evening: pass 2 (face-off and showroom gaps)

Commits: 496cebc, 8e46e53, 9e6186d, f24425f (and this notes commit). Tests green:
`workshop_test` 88/0, `stage_director_test` 34/0, `stage_seat_test` 66/0, `stage_animation_test`
145/0, `stage_camera_test` 14/0, `render_test`, `warmup_test` 33/0.

- **Why the face-off floor was black (the real cause):** `FogFloor`, a 13 x 15 m FogVolume of
  density 0.8 with no emission and no light feeding it, lay along the floor. From a 0.26 m lens the
  grazing rays cross metres of it and it ABSORBED the floor past the hero, whatever light was put
  there (proved by hiding it: the floor appeared at once). Now density 0.4 with a 3D noise density
  texture (wisps and gaps), a faint emission, lit by the floor-only pools, and drifting (the volume
  moves on two slow sines, `SMOKE_DRIFT_*`). `FogRim` treated the same way (it was a black moat round
  the plinth).
- **Floor:** plate shader base 0.16 grey, metallic 0.08, roughness 0.24 (wet dielectric: fresnel at
  grazing gives the sheen). `workshop_test`'s old guard (albedo <= 0.04, metal > 0.3) is replaced
  with 0.1 to 0.2 albedo and a wet, low-metal check, with the measured reason in the test.
- **Pools, floor only:** `Room/FloorWash` (warm, 22) now has `light_cull_mask = ROOM_LAYER` so it
  paints the floor and not the machine (it was flattening the orange), and is on in every shot.
  New `OpponentSlot/OpponentPool` (cold, 14, floor only). Their fog energy is small on purpose (the
  wash's cone fills the air in front of the lens: 0.12; the pool 0.7).
- **Shafts:** env volumetric density 0.02 -> 0.025; `OpponentTop` fog energy 9 (was 4.5); new
  `Room/HeroTop` warm top back light (face-off only, fog 1.6). 14 lights now (test updated).
- **Hall** (`_build_hall`, own kit): `HallWall` with `render/stage/hall_wall.gdshader` (unshaded; a
  patchy cold spill at the foot; NB unshaded ignores EMISSION, write ALBEDO), 12 steel ribs, a
  0.8 m barrier of panels with gaps, a truss with dim rig lamps (bokeh). No lights added. A metal
  wall picked up the room probe and read as a flat grey sheet: it is matte now.
- **Opponent:** slot (2.5,-1.9) -> (2.2,-1.55), nose 10 deg off the hero. The slice opponent now
  carries an AXE (`qa/stage_slice_bots.json`): the vertical spinner is a floor drum and never reads.
- **Plinth:** `STAGE_RADIUS` 1.5 -> 0.95 (a 3 m disc had its edge outside every frame), a
  `render/stage/plinth.gdshader` (16 bolted brushed panels, lip chamfer, steel band round the gloss
  top), the edge light moved to the foot (across the middle of the side it read as a neon stripe),
  showroom framing 0.58 -> 0.42 width share. Dry ice positions scaled in with the plinth.
- **Animation:** `aim_step_max` is now quoted per 60 Hz frame (the check failed on a slower headless
  frame, not a jump); `_process` clamps a hitch to 1/15 s.
- **Medium tier** (no volumetrics): floor, pools and hall hold; shafts fall back to the additive
  cones. `docs/aaa/img/wave-a/stage/pass2-faceoff-medium.jpg`.
- **QA:** `stage_preview` debug line prints platform share, h_offset and the hero pixel. Captures:
  take the frame at 6 s on medium (shader compiles delay the first frames; a 2 s frame showed the
  platform still up).
- **Verdict (page):** face-off about 60 % (was a third), showroom about half (was a third), garage
  and part unchanged (the room and the exploded view are the gaps).

## Next (stage)

1. M1: overhead light bars, brighter smoke round the plinth, a wetter lit floor. Device timing of
   the pass 2 high tier (FogVolume noise, two extra spots, hall draw calls).
2. The garage room (G1 parts wall, gantry, softbox in frame): needs art; plan with the kit lead.
3. G2 as a real exploded view (every category apart, not one 11 cm slide).
4. Full `scripts/test-arena.sh` and `scripts/build-sim.sh` (find-check for " 2" dupes first); device
   60 fps; AgX vs ACES A/B; probe re-capture after a fight.

---

# Earlier: WIP notes, stopped 2026-09-24 evening

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
