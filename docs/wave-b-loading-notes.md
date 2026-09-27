# Wave B: the boot loading screen, "Built on the turntable" (2026-09-27)

Owner picked direction A of `docs/look/loading-options.html`. Built as below.

## What it does

- The warm up (`Arena/render/warmup.gd`) still does exactly the same work (read everything, then draw
  everything once off screen) and still reports the true fraction. Each `preload_progress` now also carries
  `step` (the loading screen row) and `step_fraction` (progress within that phase). Spec in
  `docs/bridge-spec.md`, "preload_progress step and step_fraction".
- The stage (`Arena/workshop/stage.gd`, section "the build behind the loading screen") listens to
  `Bridge.message_sent` and builds the machine in step with the rows. No new message.
- The shell (`Roboteer/LoadingView.swift`) shows the column: ROBOTEER, the machine's real name (from the
  selected `BotBuild`, set by `MenuView.sendStage` into `host.loadingMachine`), "Your machine", five rows,
  the big italic percentage, the cyan gauge and one plain line.

## Phase to row mapping

| Row | Warm up phase (real work) | Line | On the stage |
|---|---|---|---|
| Hull | STAGE: scenes, environments, arena materials, FX textures | Opening the workshop | hull stands in the dark (key 42 %, rig 6 %) |
| Drive | PARTS: every part model and material slot | Fitting the drive | wheels land when the row is done |
| Armour | PAINT: paint overlays | Bolting on the armour | armour lands when the row is done |
| Weapon | SOUND: every sound | Mounting the weapon | weapon and utilities land when the row is done |
| Stage lights | LIGHTS: the off screen draw (pipelines, uploads, venues) | Warming the lights | key full; the rest of the rig comes up with each batch drawn |
| (done) | | Into the workshop | rig to full over about a second, then the stage is itself again |

Headless runs have no LIGHTS phase (nothing to draw), so the walk goes weapon row -> done.

## Decisions

- **The column is on the RIGHT**, mirrored from the mockup. Every menu screen frames the machine at
  `StageLayout.botFrame` (28 % across, panels right), so a left column would sit on top of the machine and
  the menu would have to move it (a second reveal). On the right the menu's plates arrive where the column
  was, over the same lit stage. If the owner wants it left, the stage would have to be framed right while
  loading and then glide to 0.28 at the hand-off.
- Parts are hidden at the part body, not the meshes: seating and framing read the meshes' own flags, so
  nothing moves when a part lands.
- Lights: movers and key are scaled on top of what `_animate_lights` writes each frame; every other light
  and every emissive `StandardMaterial3D` in the rig is set from its built level; beams take the rig level in
  `_fade_beams_near_camera`. Eased on REAL time (tau 0.28 s) so a 1 fps renderer still gets there.
- Safety: forwards only, a finished build never restarts, and 45 s of quiet mid build finishes it (the shell
  gives up at 40 s).
- A thin SwiftUI scrim (ink 90 %) is held only between `arena_ready` and the first progress message, so
  the live stage never flashes lit before the arena darkens it.
- Coordinator request: the workshop test bay (`res://arena/test_arena.tscn`, venue kit since `dfd7a09`) is
  now in `VENUE_SCENES`, so it is drawn in the lights row like the six venues (its scene file was
  already read in the hull row via `res://arena/`).

## Verification

- `HEADLESS=1 JOBS=2 scripts/test-arena.sh bridge_test ui_test warmup_test stage_build_test
  stage_animation_test stage_camera_test stage_director_test stage_seat_test`: 8 files, 0 failures.
  New `Arena/tests/stage_build_test.gd` (38 checks) drives the rows through the Bridge and runs the real
  warm up end to end against a stage.
- `scripts/build-sim.sh` green. Career self test on the iPhone 17 sim: ALL PASS (1021 checks, 2 warnings).
- Captures: `docs/look/loading/built-stage-{1-hull,2-drive,3-armour,4-lights,5-lit}.jpg` (desktop Godot,
  `qa/stage_preview.tscn -- --roboteer-build=STEP --roboteer-frame=0.28`) and
  `built-column-{874,956}-*.jpg` (simulator, headless, `-loadingPose STEP:FRACTION`, the empty-stage
  still behind because the sim draws no live stage).

## Where I stopped

Built, tested, committed, not pushed. Owed on the phone (the sim cannot show the live stage):
- the hull really reads in the dark at 42 % key, and the step from row 3 to row 4 (key to full) is a
  pleasing "lights on" rather than a pop;
- how long each row takes on device (the draw row will be the longest); if the first four rows fly past,
  consider weighting, but only with real work, never a timer;
- the hand-off: the column fading while the rig finishes coming up, no flash, the machine not moving.
