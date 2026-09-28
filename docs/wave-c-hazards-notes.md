# Wave C: hazards that live somewhere

2026-09-28, environment artist, branch `wave-c-hazards` (worktree
/Volumes/RoboteerBuild2/Code/Roboteer-haz, from main 39e0cd3). Owner: "the 3d elements in the
arena need checking ... like not having spikes appear from just nowhere."

Proof page: `docs/look/hazards.html` (before/after strips in `docs/look/hazards/`, fight camera
and a close low angle, per state).

## Where I stopped

Done and committed on the branch (not merged, not pushed). The owner still needs to review
the page and make the calls listed at its end.

## Inventory and verdicts

| arena | element | before | verdict | fix |
|---|---|---|---|---|
| Yard, Grinder (wake 1:30), Crush (wake 1:30), Coliseum, Run | spike patch | painted 6 mm plate on solid floor; pins rose through solid floor and floated 8 cm over the plate at full height (the mesh ended at the collar) | FAIL | real floor hole, slotted grate with bored holes and bore liners, dark tray, lit guide plate on the patch's lamp list (holes glow in the warning rhythm), pin = long post |
| Yard (wake), Grinder, Coliseum, Run | floor grinders | disc lying ON the floor in a painted collar; sleeping disc wore the spin blur; snapped from still to full spin on wake | FAIL | round hole in the floor, lined well 0.3 m, motor drum + ribs + spindle, disc 13 mm proud, blur hidden while asleep, spin-up over WAKE_LEAD |
| Drop Zone | pit leaves | believable (drop 12 cm, slide under floor) but vanished into plain wall | minor | dark leaf pockets on E/W shaft walls, rails at the pocket bottom, N/S steel lip |
| Furnace, Coliseum, Run | flame jets | housing + barrel + fuel line | minor | bolted wall plate, always-lit pilot flame on the jet's lamp (flares in the warning) |
| Furnace | belt | scrolling slats, runs under the walls | pass | none |
| Crush | rams | warning lamp floated 24 cm above the 0.65 m wall; rods entered bare wall | FAIL | port plate with bolts, rod glands, lamp riser |
| Coliseum | turntables | proud disc lying on the floor | minor | flush bearing bezel ring (gap + bolted steel) |
| Coliseum | arena banners (static) | crossbar floating 1.6 m over the wall | FAIL | two masts each, one merged mesh |
| Test bay | floor | the Yard's wave B grinders sat there asleep forever | FAIL | hidden, taken out of the hazard schedule (no ghost idle ring), holes filled |
| Run (event) | overhead presses | platen hanging in mid-air | FAIL | C-frame (column on the far side only, clear of the fight camera), braced crosshead, cylinder, chrome rod on the platen |
| Pinball (event) | drop targets | sank through solid floor, popped in one tick | FAIL | floor slot + well + frame; mesh eases after the body (0.12 s down, 0.3 s up) |
| all six | static floor dressing | checked low + fight cam | pass | none needed |

## How it works (for whoever touches it next)

- `ArenaBase._floor_cutouts` / `floor_cutouts()`: sunk hazards register render holes
  (`{"rect"}` or `{"circle", "radius"}`, plus `"owner"`). `_apply_floor_cutouts()` runs in
  `build()` after `_build_decor()` and swaps each `Floor*` slab's MeshInstance mesh for
  `HazardMeshes.floor_slab(size, holes)` (a round hole is a square cut with the floor
  filled back in round it). The BoxShape3D is untouched, so a machine drives over the
  holes as over floor. `_remove_floor_cutouts(owner)` re-cuts (the test bay uses it).
- The venue kit's `add_ground` (a plane 2 cm under the floor) reads `arena.floor_cutouts()`
  and cuts the same holes, as one mesh built by `HazardMeshes.rects_minus`. Without this the
  ground plane lids every hole.
- New HazardMeshes builders: `square_minus_circle`, `bore` (inward-facing tube), `recess`.
- Everything new is render only: MeshInstance3Ds added after every body and area (tree order
  unchanged), no collision, no new lights, no textures. Motion that is new (grinder spin-up,
  pinball target easing) moves meshes only: the disc was already a MeshInstance, and the
  target's body still jumps on its tick.
- QA: `Arena/qa/hazard_states_capture.tscn` (excluded from export by `qa/*_capture.*`):
  `-- --roboteer-hs-dir=DIR [--roboteer-hs-only=job,...]`. It winds each arena's clock by
  hand to each state and saves fight and close frames. **Trap:** on a busy Mac a Godot window
  behind others stops presenting and `get_texture().get_image()` returns the SAME stale
  frame (identical files). The tool calls `RenderingServer.force_draw()` twice before each
  grab. Check `md5 -q DIR/* | sort | uniq -d` is empty. Flames only draw if the arena's
  tick keeps running during the settle frames (the tool does that for "active" states).

## Proof

- hazard_determinism_test `--record` on base 39e0cd3 and on the branch: identical hashes in all six
  arenas (yard c814ec9e2c1a3b19, grinder 948cea0b512e1375, furnace fa79709c3fddc315, crush
  29b028f7726a2f2f, drop_zone 3c8a0a72052ca8cf, coliseum 7c37e036b6df6957). No golden moves
  because of this branch. The committed GOLDEN table already differs from 39e0cd3 because of
  other agents' work (integration re-records it).
- arenas_test 155/0, hazard_warning_test 104/0, venue_kit_test 215/0 (kit high = none = low
  in every arena), events_test 101/0, test_arena_runs_test 25/0.
- Budget (arena + hazards, no kit): +44 to +3,314 triangles and +0 to +6 surfaces per arena
  (table on the page). No assets added. The pck grows by script bytes only.

## Follow-ups (coordinator, same day)

- The Coliseum arena banner on the north wall over the north jet (x = -1.5) is dropped
  (`coliseum.gd _build_decor`, skipped by distance to `JET_NORTH_X`; the other 15 stay). The
  burn zone now reads clear from the wall. The barrel tip shows over the wall top, but the
  wall itself hides the rest of the housing from the fight camera: the nozzle faces into
  the arena, away from a camera looking in over the north wall.
- The Grinder's kit spark plumes fire only while that disc is cutting:
  `GrinderArena.grinder_cutting(i)` (read-only), and `VenueKit.add_state_fx(node, method,
  args)` now takes call args. The plume, core, floor glow and fire light are all state fx.
  The plume is a low rim spray (`VenueFx.grinder_plume(tier, 0.55, rim 0.62)`: emitted on
  the rim, radial velocity outward, 0.7 s). Idle discs show only the arena's own IdleSparks
  trickle. The capture tool's `force_touch` state stands a contact in.
- The pilot flames and the Crush ram height are kept, as asked.

## Owner calls (on the page)

1. Done: banner dropped, plumes only fire while cutting. Pilot flames stay lit and the
   Crush ram height stays, as the coordinator decided.
2. The Coliseum is very dark: check the dark metal on the phone.
