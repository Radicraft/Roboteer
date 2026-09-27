# Wave B: the Workshop test arena as a venue

## WHERE I STOPPED (2026-09-27; keep this block current)
- Owner feedback: the six venues look great, the builder's TEST ARENA did not (a floor in a
  black void with a dead spike bezel in the middle). Now dressed as its own place, a private
  test bay after hours, with the shared venue kit.
- `Arena/arena/test_arena.tscn` has a `VenueKit` child, `venue = "workshop"`; the layout is
  `Arena/arena/kit/venues/workshop.gd` (placement API only, nothing collides).
- `Arena/fight/test_arena.gd`: `_remove_spikes()` now also HIDES the SpikePatch node (its
  bezel is render only). Hidden, not freed. The test arena fight hash is the same with and
  without this change (fa73b5ec...537a48 both ways).
- Textures (generator `Tools/blender/arena_kit/make_kit_textures.py`, `workshop_floor()` +
  `_workshop_paint()` + `workshop_wall()`; `yard_floor()` gained `paint=`, `save_normal=`,
  `tone_range=`, defaults unchanged so the other floors regenerate byte-identical):
  `workshop_floor.png` (2048, imported at size_limit 1536), `workshop_floor_n.png` (512),
  `workshop_floor_wet.png` (512 L8 lossless), `workshop_wall.png` (1024 x 512, VRAM).
  NOTE: a headless `--import` did NOT pick up a changed size_limit on an already imported
  file; delete `.godot/imported/workshop_floor.png-*` to force it.
- Package: arena.pck 95.18 -> 97.50 MB (+2.32 MB), measured by exporting both ways from a
  worktree. arena.pck NOT committed.
- Floor paint is in world metres (fight_types.gd spawns +-3.2, pad at the north wall, x 0).
  Text faces +z (readable from the fight camera in the -x -z corner).
- Lights: 2 real LED downlights + 2 real halogen tripods on high (budget 4), the 2 LEDs on
  medium, none on low. No screen (no second render of the scene), no gates, no pyro, no
  crowd: two mechanics as crowd cards, no phones.
- Tests: venue_kit_test now includes `test_arena` (runs it with arena "yard" and
  rules.mode "test"; checks pieces instead of crowd cards): yard + test_arena 84/0, hashes
  identical high / none / low. test_arena_runs_test 24/0. weapons_test: "weapons work in
  the workshop test arena too" PASS (the one failure, the axe wind-back, is the weapons
  model, unrelated).
- Captures: `Arena/qa/venue_capture.gd` takes `--roboteer-capture-mode=test`
  (with `--roboteer-capture-arena=yard`). Proof: docs/look/arenas/arenas-proof.html section
  "Pass 5", images docs/look/arenas/proof/p5-test-*.jpg.
- Main tree was mid-edit by another lead (arena_base.gd did not parse) while this ran, so
  captures and tests ran in a worktree `/Volumes/RoboteerBuild2/Code/wb-test` (HEAD
  e994cd3 + these files). Remove it with `git worktree remove` when done.
- Cost (fight camera, desktop M4): high 106 / 77 draw calls venue / none, medium 75 / 46,
  low 246 / 235 (Compatibility counts differently).

## Gaps / next
1. Dressing is merged primitive blocks; fine at fight and wide cameras, plain up close.
   Candidates for Blender pieces: roll cabinet, bench, tripod light, the machine on the stand.
2. Mechanics use crowd idle/cheer poses, not working poses.
3. The near side of the room (behind the camera) is dark; the grade matches the family's
   night look.
4. Not in `render/warmup.gd` VENUE_SCENES (loading screen lead's file); most pipelines are
   shared with the Yard. Add `res://arena/test_arena.tscn` there if the first frames hitch.
5. Device fps per tier not measured.
