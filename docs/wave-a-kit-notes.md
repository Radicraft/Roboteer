# Wave A: venue kit notes (WIP, stopped 2026-09-24 on the coordinator's STOP)

## Where it stands
- Kit: `Arena/arena/kit/` (venue_kit.gd/.tscn, kit_crowd.gd, kit_screen.gd, kit_fx.gd,
  kit_materials.gd, shaders/, textures/, models/ (22 Blender glbs), crowd/ atlas),
  Blender/PIL sources in `Tools/blender/arena_kit/`. The Yard has ONE child `VenueKit`
  (`Arena/arena/yard.tscn`), layout in `Arena/arena/kit/venues/yard.gd`.
- Yard dressed: scaffold bleachers + screen with live feed (south), container terraces
  with standing crowd (east), fences/scrap/road cases/jibs (north, west), two fighters'
  gates with pyro and a truss with moving heads, sodium flood towers, LED board ring just
  behind the wall (the piece the fight camera sees), sky dome, far container stacks,
  dust motes, floor grime.
- Determinism: `Arena/tests/venue_kit_test.gd` PASSES (51 checks): no collision objects
  under VenueKit at any tier; the Yard fixture fight hash is identical with the kit (high),
  without it, and with the kit at low tier:
  `2f5c4b8e7d3c7cd1e8ac9ca519a4f19030a8984bfda4e2b99057349d1ac7773d`.
  determinism_test and arenas_test also passed with the kit in.
- Perf (desktop Forward+, fight camera, kit vs no kit): draw calls 107 vs 72, primitives
  92k vs 64k, shadow draws 85 vs 62; wide view 184 vs 71 draws. Kit counts per tier
  (high/medium/low): cards 273/166/73, real lights 4/2/0 (+1 transient pyro flash per
  group on high), particles 1668-ish/976/288 ceiling (pyro only while firing), atlas
  2048x1024 RGBA. The live feed renders the scene again at 320x180 every 3rd frame (high
  only) - measure on device. Medium/low captures were NOT run correctly (zsh arg bug);
  redo with `--rendering-method mobile` / `gl_compatibility`.
- Recraft: 4 credits (two crowd look targets, docs/aaa/img/wave-a/kit/crowd-target-recraft-*.jpg).

## Crowd rework (owner: "pretty bad and fake") - IN PROGRESS
- Done: staging in `crowd_card.gdshader` (dark bodies, warm spill on front rows, top rim,
  bluish haze/desaturation with distance, mip softness, ripple reactions from the machines,
  no identical neighbours, +-8 % scale). Three treatments selectable with
  `crowd_style` / `--roboteer-venue-crowd=stylised|human|lights`.
- Running when stopped: an Opus agent building a MakeHuman/MPFB2 CC0 atlas
  (`crowd_atlas_human.*`, `Tools/blender/arena_kit/crowd_cards_human.py`, licences into
  docs/third-party-models.md). Check whether it committed.
- NOT done: the proof page `docs/look/arenas/arenas-yard-proof.html` with the 2-3 crowd
  treatments side by side in the closer fight framing (captures exist for stylised and
  lights in docs/aaa/img/wave-a/kit/after-*.jpg, lights-*.jpg; human pending).

## Next
1. Proof page (before/after + concept + treatments), owner picks a crowd treatment.
2. Tier captures medium/low and device frame time; decide on live feed rate.
3. Shader warm-up for kit materials (first build stalls ~9 s of shader compiles on desktop).
4. AudioMix `crowd_reacted` signal (audio lead) to replace the read-only `_swell_at` watch.
5. Per-arena plan for the other five (containers->bleachers behind mesh for Grinder,
   dark stands + lights crowd for Drop Zone, catwalks for Furnace, concrete behind glass
   for Crush, full 360 stadium with truss ring and jumbotron for Coliseum) after review.

## Known issues
- main HEAD had others' fx.gd referencing untracked `feel_tiers.gd` (breaks fresh
  checkouts); captures ran in worktree /Volumes/RoboteerBuild2/Code/kitcap pinned to 9123a5d + kit.
- scripts/build-sim.sh not run this wave.
