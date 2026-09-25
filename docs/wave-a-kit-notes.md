# Wave A: venue kit notes

## WHERE IT STANDS (2026-09-25, pass 3 / five arenas; keep this block current)
- Owner approved the Yard (pass 2) and crowd A. Now: shared kit upgrades, then Grinder,
  Drop Zone, Furnace, Crush, Coliseum in that order; per-arena proof sections go in a NEW
  page docs/look/arenas/arenas-proof.html (arenas-yard-proof.html stays as is).
- DONE shared kit (commit "Venue kit: shared upgrades"): venue reflection probe baked once
  after the venue is built + cold sky deck (`grade.probe`, medium/high; hides the arena's
  FloorProbe); oil as a dielectric film (no black holes); crisp streaked shafts per real
  flood on high (`kit.shafts`), medium cone cards with rays and motes; container terrace
  piece `add_container_terrace` (Yard east now stands on it right behind the wall; its
  boards were removed, they sat in the fight frame).
- Hash moves with the combat engineer's commits; per arena it must be identical kit
  high / none / low (venue_kit_test).
- DONE venue_kit_test covers every dressed arena (`-- --roboteer-kit-arenas=a,b` to limit).
- DONE Grinder (`venues/grinder.gd`, grinder.tscn has VenueKit): shed shell, tube banks
  (`add_tube`, one flickers), cold downlights (`add_downlight`), bleachers behind mesh,
  machine line from merged blocks (`add_block`/`add_cylinder`/`add_beam_block`), gantry
  crane hero, riveted floor map (`make_kit_textures.grinder_floor`), x-braced wall
  panels (`grade.wall_panels`, shader wall_panel.gdshader, styles xbrace/padded/riveted).
  Hash 3cb03e0a...0add47 identical high/none/low. Proof: docs/look/arenas/arenas-proof.html
  (built by scratch section.py from a json per arena; captures by proof.sh).
- DONE Drop Zone (`venues/drop_zone.gd`): bunker, stepped concrete stands on 4 sides
  (`add_stepped_stand`), cold downlights + rig, amber corner beacons
  (`add_rotating_beacon`), pit embers/haze via `add_state_fx(node, "pit_open")`, concrete
  floor map. Hash c0922dd2...c17823. Capture flag `--roboteer-venue-when=pit_open`.
- DONE Furnace (`venues/furnace.gd`): hall, catwalk stands with uplights, chains,
  crucible pour hero (molten.gdshader), embers, smoke FogVolume band (high). Hash
  6b93a67d...de0dd6.
- NEXT: Crush, then Coliseum.

## 2026-09-25 pass 2 (coordinator brief after the owner saw pass 1)
- OWNER PICKED CROWD A (MakeHuman). Default `crowd_style = "human"`; B/C stay behind
  `--roboteer-venue-crowd=` for QA only.
- Floor: `make_kit_textures.py yard_floor()` now draws the Yard's own plates (`_plates`:
  irregular 2 to 3.4 m, middle row cut round the spike frame), seams, welds, corner bolts,
  heavy tyre skids, oil, damp, and writes `yard_floor_n.png` (normal map from a height
  field). `venue_floor.gdshader` v2: dark metallic steel (`steel`), arena plate texture only
  as low-contrast scratches, whiteout-blended normals, warm/cold albedo pools. Grade keys
  `floor_normal`, `grid_hide` (the arena's 1 m Grid is hidden in the Yard).
- Sheen: `glint` = a DirectionalLight3D with `light_cull_mask` = layer bit 14 only, floor
  mesh gets that layer (sodium, energy 0.12, specular 9, from +x+z). Walls: `wall_tint`
  (2.75, 2.62, 2.45) + `wall_wash` directional on layer bit 13 from the camera side; the
  hazard sleeves carry the wash layer too (meta "wash"). Bit 11 is the stage's ROOM_LAYER:
  do not use it.
- Beams: global volumetric fog lit everything orange (tried, rejected). Now global density
  0.0005 and a FogVolume ellipsoid along each REAL flood's beam (`_add_beam_haze`, high tier
  only), flood `light_volumetric_fog_energy` 5, key/fill 0. Medium: `beam_card` strength
  0.16 (cards), high 0.03.
- Crowd: phones = specks (warm-white, size 0.075, `phone_twinkle`); the card's own phone
  pixels are darkened through the emit mask (sampled at mip bias 1.5). `saturation` 1.35,
  body_light 0.3. Crowd atlases (all four PNGs) now import WITH mipmaps (they had none,
  though the shader uses mip bias).
- Grit 130/60/0, slightly smaller and brighter.
- Credits: `Roboteer/SettingsView.swift` About blurb names the CC BY 4.0 authors (13 pt body).
- Tests: venue_kit_test 58/58 (the extra checks are the two new directional lights per
  tier casting no shadow); hash identical high/none/low, now `ae4b963f...9ea9` (it moved
  with the combat engineer's AI commits, not the kit). warmup_test 33/33, determinism 42/42.
  hazard_determinism_test: GRINDER golden fails (the Grinder has no VenueKit; the combat
  AI commit 08eaccd changes fights; for the combat engineer/hazards lead to re-golden).
- Proof page: pass 2 column added, gap list rewritten.

## 2026-09-25: the Yard proof (night relight, MakeHuman crowd)
- PROOF PAGE: `docs/look/arenas/arenas-yard-proof.html` (images in `docs/look/arenas/yard-proof/`):
  concept | before (no venue) | first pass | after, per shot; three crowd treatments; medium
  and low tiers; the gap list; cost. Owner reviews the Yard before any other arena is dressed.
- Night grade: `VenueKit.grade(dict)` (venue_kit.gd), called from `venues/yard.gd _grade`. Sets
  ONLY render properties of what the arena built: KeyLight (sodium, from the east flood
  tower), FillLight (cold blue rim from across), ambient, fog, the floor slab's
  material_override (`shaders/venue_floor.gdshader` over the arena's own plate textures x the
  unique map `textures/yard_floor.png`, alpha = wet/oily), the wall material tint, the 1 m
  grid colour, and a hazard sleeve on the wall tops (`shaders/hazard_trim.gdshader`; the
  arena's thin Chevron cap is hidden). Runs once after GraphicsQuality applied the tier; the
  endgame key shift reads the live values so it still works. Low tier gets a slightly
  higher key and ambient.
- Yard dressing: LED ring REMOVED (concept has none; it outshone the arena), boards at
  `board_level` 0.42, flood spots 3.2, beams end in the air and fade near the camera (grey
  fog discs before), moving-head beams halved, drifting grit (`VenueFx.grit`, 70/30/0),
  east front row at wall + 0.38 m (only people within ~1 m of the wall reach the top of the
  fight frame at pitch 50).
- Crowd: MakeHuman/MPFB2 atlas `crowd/crowd_atlas_human.*` built by
  `Tools/blender/arena_kit/crowd_cards_human.py` (fe5e3eb; licences in
  docs/third-party-models.md; CC-BY authors owed a credits line: Elvaerwyn, Mindfront,
  punkduck, DredNicolson). `crowd_style` default is now "human". Yard staging via
  `kit.crowd_staging` (body_light 0.22, spill 0.32, warm rim 0.75, phone_glow 1.1).
- Warm-up: `Arena/render/warmup.gd` VENUE_SCENES stands the Yard up once, scaled 0.012, in
  the off-screen viewport (warmup_test updated). Shader cache cleared: first 8 Yard frames
  1040 ms cold -> 287 ms warmed (desktop M4). The "9 s" in the older note was not reproduced.
- Determinism: venue_kit_test 52/52, hash 2f5c4b8e...773d identical with kit (high), without,
  and at low.
- Perf (fight_a, venue vs none): high 96/73 draws, 93.9k/67.9k prims; medium (Mobile) 69/54;
  low (Compatibility) 278/268 (that renderer counts differently). Device numbers still owed.
- Capture: `Arena/qa/venue_capture.tscn` has a `concept` pose (the concept's angle) and
  `--roboteer-venue-pose=fx,fy,fz,tx,ty,tz,fov` for one quick frame.
- Textures: `make_kit_textures.py` writes yard_floor.png (seeded). yard_floor and
  floor_grime are VRAM compressed with mipmaps; boards mipmapped.

### Next (after the owner's review)
1. Yard-specific plate set (bigger plates, no bolt-hole grid) and stronger tyre marks.
2. Crowd colour under the night grade (bodies near black); phone sparkle instead of rectangles.
3. Containers directly behind the far wall if the owner wants the concept's stacking.
4. Device frame time per tier; decide on the live-feed rate.
5. The other five arenas (plan below), only after the Yard is signed off.

---

## 2026-09-24 (earlier state, kept for history)

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
