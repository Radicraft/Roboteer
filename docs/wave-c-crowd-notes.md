# Wave C crowd (branch wave-c-crowd)

Owner 2026-09-28: "the crowd do look a bit robotic and AI in their looks and movements."
Review page: docs/look/crowd-options.html (assets in docs/look/crowd/). OWNER PICKS A, B or C
before the full build.

## Where I stopped
- Phase 1 diagnosis + Phase 2 prototypes done; page written. Recommendation: A tiered
  (high A, medium C, low B).
- NOT done (build phase, only after the pick): per-stand MultiMeshes for culling, idle loop
  40 -> 24 frames, binary mesh resource instead of crowd_people.json, far LOD ~200 tris for
  the Coliseum, phones in the 3D hands, seated clip, more body types, tier wiring in
  venue_kit.gd (CROWD_DENSITY etc.), device timing (Coliseum + arena menu stage).
- Default style is still "human" (cards); the only change it sees is the pose dissolve
  (crowd_card.gdshader fade_s 0.36; fade_s=0 reproduces the old pops exactly).

## What is here
- `Tools/blender/arena_kit/crowd_vat_human.py`: rebuilds crowd_cards_human.py's 16 MPFB people
  as ~1,350-tri meshes (colour baked to vertices, zones for re-tinting, hidden skin dropped,
  head skin flattened), bakes 6 clips into `crowd/crowd_people_vat.png` (RGBA8, row 2f =
  position, 2f+1 = normal, column = vertex) + `crowd/crowd_people.json` (indices, colours,
  zones, far LOD `lod1` = QEM-decimated copy snapped to same-bone full-mesh vertices, so it
  needs no texture of its own). ~2 min: `Blender -b --python ...crowd_vat_human.py`.
- `crowd_people_vat.png.import`: lossless, no mipmaps, detect_3d off (VRAM compression would
  destroy the data). Keep it that way.
- `shaders/crowd_person.gdshader`: VAT playback, clips via `action()`, ripple reactions,
  ambient slots, flinch, head/shoulder twist toward `focus_pos`, palette re-tint, same staging
  uniform names as the cards (+ `person_light`). `debug_view` 1 albedo, 2 zones, 3 normals.
- `shaders/crowd_flag.gdshader`: flags on poles (B/C).
- `kit_crowd.gd`: styles `real` (A), `broadcast` (B), `mixed` (C) next to stylised/human/
  lights; `--roboteer-venue-crowd=` selects. Winding: Blender CCW -> Godot needs two corners
  swapped (people were inside out before that).
- `Arena/qa/crowd_capture.tscn` (+ .gd): stills + clip frames per shot with a big hit at 1/3;
  run with `--fixed-fps 15`; `--roboteer-crowd-stage=k=v` sets crowd uniforms,
  `--roboteer-crowd-lift=Y,AT` raises stand shots (Coliseum 2.5,4.0).
  Clips were encoded to mp4 with a small AVFoundation tool (no ffmpeg on this Mac).

## Numbers (desktop, whole frame, wide shot)
Yard today 119.7k tris / 196 dc; A 433.1k / 226; B 119.7k / 197; C 310.9k / 213.
Coliseum today 71.0k / 200; A 824.6k / 230; B 71.6k / 201; C 264.2k / 217.
Grinder today 83.9k / 164; A 229.5k / 194; B 83.9k / 165; C 138.7k / 180.
VRAM +10-11 MB for A/C. pck: VAT ctex 3.27 MB + json 0.42 MB; the stylised atlas (1.53 MB)
is only reachable by a QA flag and can leave the export (size engineer, 2026-09-28).
Crowd audio untouched.
