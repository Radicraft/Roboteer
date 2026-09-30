# Wave C crowd (branch wave-c-crowd)

Owner 2026-09-28: "the crowd do look a bit robotic and AI in their looks and movements."
Options page 2026-09-28 (A real, B broadcast, C mix). OWNER PICKED C on 2026-09-30
(docs/aaa/decisions-2026-09-30.md item 2). Built page: docs/look/crowd-options.html
(assets docs/look/crowd/ and docs/look/crowd/built/).

## Where I stopped (2026-09-30)
- C BUILT and the default everywhere (VenueKit.crowd_style = "mixed"), incl. the arena menu
  stage (checked by merging wave-c-menus over this branch in a throwaway worktree, since
  removed; the stage only calls crowd.stage(), unchanged).
- Main merged at 7cfa64b. After the merge: venue_kit_test 215/0 (fight hash identical with the
  kit high, low and off in all six arenas), determinism_test 42/0.
- OWED: device frame time (Coliseum, high). No launch flag puts a fight in the Coliseum and
  there is no on-device frame time log; installing an unmerged branch would replace the
  owner's build. Recipe: add a QA Godot arg for the arena to the Swift launch path (or play a
  Coliseum quick fight by hand on a build of this branch), add a presentation-only
  `Performance.TIME_PROCESS` / `RenderingServer` frame-time print every 5 s behind a flag, then
  `xcrun devicectl device process launch --console` and read it. Compare high vs medium.
- OWED (small): seated clip is used only by the 3D people scattered into the dark house; in
  the standing rows a sitter's legs pushed through the row in front. A bench venue could use
  `seated_share` on its own rows. The menu stage's CROWD_STAGING (spill 1.15, body 0.5) makes
  the 3D people a little pale there; the menus lead may want `person_light` < 1.8 in that dict.

## Reaction API (for the Marshal / verdicts, branch wave-d-marshal)
- `VenueCrowd.react(kind: String, strength: float = 1.0, origin: Variant = null)`
  - "hit": a ripple from `origin` (world; the kit passes the machines' midpoint): the keen raise
    their arms (a fifth film it on a phone), others clap, then settle.
  - "cheer": a clear judges' decision. Sweeps the whole house from `origin` (null = arena
    centre) faster than a hit, ~75 % raise their arms, holds about twice as long.
  - "boo": a close decision. ~90 % boo (clip boo_in + boo: fists thrust out and down, head
    shaking), some cover their faces; seated people stay put; the cards cover their faces.
  - "flinch": the arena biting (same as set_excitement(..., true)).
  - `strength` 0..1 scales who joins and how long they hold.
- Through the kit (preferred, it also lifts the house excitement and flashes):
  `VenueKit.on_crowd_reaction("verdict_clear", 1.0)` and `("verdict_close", 1.0)`; the old
  keys big_hit / flipped / ko / endgame still map to "hit". The kit is in the group
  "venue_kit".
- Presentation only: nothing here feeds back into the fight; the fight hash is unchanged.

## Tiers (VenueCrowd._classify, `tier` set by VenueKit from GraphicsQuality)
- The front row of each stand side is found at commit; `rel` = metres behind it.
- high: 3D for rel < people_depth (1.9 m), thinning to cards over people_blend (1.4 m); 5 % of
  the lit house and 2.5 % of the silhouettes scattered in as far-LOD 3D (35 % of those seated).
- medium: 3D for the front row only (rel < 0.35 m).
- low: cards only (broadcast house, density 0.3, no specks, no silhouettes).
- The dark house: every card carries its darkness in COLOR.a (smoothstep over the 3D depth
  + 1.8 m), 3D people carry it in INSTANCE_CUSTOM.z (dimmed by house_dim); rims soften and the
  cards lose their specular with depth. No band where the 3D rows end.

## Numbers (desktop render info, whole frame; before = picture cards, high tier)
| | Yard | Coliseum | Grinder |
|---|---|---|---|
| 3D people high / medium / low | 203 / 34 / 0 | 271 / 45 / 0 | 94 / 28 / 0 |
| wide shot tris, before | 120k | 71k | 84k |
| wide shot tris, high / medium / low | 317k / 154k / 118k | 313k / 117k / 68k | 175k / 111k / 83k |
| stand / close tris, high (side culling) | 177k / 119k | 212k / 162k | 79k / 73k |
- Draw calls: people MultiMeshes = 24 bodies x 2 detail levels, only those with instances in
  view (+30 wide at high). Culling: each MultiMesh's buffer is reordered visible stand sides
  first and `visible_instance_count` cut, only when the visible set changes.
- Video memory: +12 to 14 MB at high/medium (VAT 2048 x 1392 RGB + meshes); low loads none.
- pck: +2.26 MB VAT (lossless webp in the import) + 0.27 MB crowd_people.res, -1.53 MB
  (stylised atlas + json + emit left out of the export in export_presets.cfg) = about +1.0 MB.

## What is here
- `Tools/blender/arena_kit/crowd_vat_human.py`: builds the 16 card-atlas MakeHuman people
  plus 8 more (EXTRA_VARIANTS), ~1,000 tris (joints protected in the collapse so no
  triangle spans a knee or elbow), far LOD ~280 (snapped to same-segment full-mesh vertices,
  no phone), a phone in the right hand (zone 7), 11 clips (idle 16 frames at 4 fps, clap_in,
  clap, raise, cheer, flinch_in, boo_in, boo, sit, sit_raise, sit_cheer = 87 frames),
  shelf-packed into `Arena/arena/kit/crowd/crowd_people_vat.png` + JSON in
  `Tools/blender/arena_kit/crowd_out/crowd_people.json`. Then
  `Godot --headless --path Arena --script qa/_crowd_people_bake.gd` writes
  `Arena/arena/kit/crowd/crowd_people.res` (CrowdPeopleData: ArrayMeshes per person and LOD,
  UV = VAT column / person's first row, UV2.x = zone). About 3 to 7 min in Blender.
- `crowd_people_vat.png.import`: lossless, no mipmaps, detect_3d off. Keep it that way.
- Shaders: `crowd_person.gdshader` (VAT playback, reactions, verdicts, phones, head follow,
  palette, house dim, `world_to_arena`), `crowd_card.gdshader` (dissolve, house ramp in
  COLOR.a, react_kind, `world_to_arena`), `crowd_flag.gdshader`.
- `Arena/qa/crowd_capture.tscn`: `--roboteer-crowd-shots=wide,stand,close,front,near,fight`,
  `--roboteer-crowd-frames=N`, `--roboteer-crowd-react=big_hit|verdict_clear|verdict_close`,
  `--roboteer-crowd-lift=Y,AT` (Coliseum 2.5,4.0), `--roboteer-crowd-stage=k=v`,
  `--roboteer-venue-tier=`, `--roboteer-venue-crowd=`; run with `--fixed-fps 15`.
- Traps: Blender winds CCW, Godot needs two corners swapped (inside-out people otherwise);
  a hidden phone collapsed far away drags any triangle it shares with the hand (keep phones
  out of decimated LODs); interleaved pos/normal rows compress badly (blocks do not);
  previews of a shelf-packed VAT must offset by the person's column.
