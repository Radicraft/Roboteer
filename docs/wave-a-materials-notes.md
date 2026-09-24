# Wave A materials notes (materials lead, 2026-09-24)

The surface half of the proving slice: one machine at target in the real engine. What was
built, what it costs per tier, what the fallback tiers do, what was measured and what is
owed. The mask convention is in `docs/wave-a-contracts.md` section 1.

Evidence: `docs/aaa/img/wave-a/materials/` (windowed desktop Godot 4.6.3, Metal, M4).

| image | what it shows |
|---|---|
| `hero_three_quarter.jpg`, `hero_masks_close.jpg`, `hero_side.jpg` | the fixture wedge (the models lead's new bevelled parts, baked masks bound) under the board's showroom rig |
| `hero_markings_side.jpg`, `hero_markings_rear.jpg` | the same machine wearing the decal set via `BotMarkings` |
| `hero_hazard_three_quarter.jpg`, `hero_hazard_rear.jpg` | paint job `paint_hazard` on the new master (paint contract kept) |
| `hero_close_fill_side_blowout.jpg` | why the camera must not sit beside the fill: the wedge plate is one mirror of it (4.2) |
| `board_forward_plus.jpg`, `board_close_*.jpg`, `board_spheres.jpg` | every master on known-good bevelled test shapes |
| `board_mobile.jpg`, `board_mobile_close_paint.jpg`, `board_compat_close_paint.jpg` | the same on the Mobile and GL Compatibility renderers |
| `board_before_distance_fix.jpg` | the vertex-mask bleed that was fixed (4.1) |
| `stage_preview_menu_cam.jpg` | the workshop stage's menu camera as it stood mid stage-rework (for the stage lead) |
| `decal_set_sheet.jpg` | the seven decals on a rust panel |

To reproduce:

    Godot --path Arena --resolution 1920x1080 res://qa/material_board.tscn -- --board-out=DIR
    Godot --path Arena --resolution 1920x884  res://qa/material_board.tscn -- --board-out=DIR --board-hero[=paint_id][@#rrggbb]
    add --rendering-method mobile | gl_compatibility for the lower tiers

## 1. The masters

| slot | master | key values (reference-study 3.3) |
|---|---|---|
| `livery` | `painted_livery.tres`, ShaderMaterial `shaders/rb_painted.gdshader` | colour x1, roughness 0.40 +-0.08 from the surface texture, **clear coat 1.0 / 0.05** plus up to +0.25 in micro-scratches, wear 0.45 (chips through a primer ring to bare steel), cavity grime (albedo -20 %, roughness +0.15) |
| `dark_metal` | `powder_coat.tres`, same shader | albedo 0.05 linear, roughness 0.55, no clear coat, wears straight to bare steel |
| `steel` | `brushed_steel.tres`, StandardMaterial3D | albedo 0.56/0.57/0.58, roughness 0.32 +-0.04 sd in U streaks, **anisotropy 0.7** along the tangent, normal 0.25 |
| `titanium` | `scratched_titanium.tres` | albedo 0.54/0.50/0.45, roughness 0.28, anisotropy 0.3, normal 0.25 |
| `hdpe` | `hdpe_moulded.tres` (kept, retuned) | normal 0.35 (was 1.0); livery tint and paint jobs unchanged |
| `polycarbonate` | `polycarbonate.tres` | smoked 0.42/0.46/0.50, alpha 0.45, **alpha depth pre-pass** |
| `rubber` | `tyre_rubber.tres` | normal 0.7 (tread relief is legitimate on rubber) |
| `status_light` | `status_light.tres` (new slot) | emission 0.8, below the 1.1 glow threshold at rest |
| `core_glow` | built in `PartVisuals` | emission energy 3.0 (was 1.6, which no longer clears the new 1.1 threshold) |

Why ShaderMaterial for paint and StandardMaterial3D for the rest: edge wear needs a mask
and a chip threshold, which StandardMaterial3D cannot express next to a paint-job detail
layer (it has one detail layer and the paint job uses it). Everything else is served
fully by StandardMaterial3D (clear coat, anisotropy, depth pre-pass) and stays on the
engine's own, best-optimised shader.

The foil fix (the owner's "crumpled foil"): the old steel and titanium carried a strong
Recraft-derived normal (strength 3.0, high-passed at 18 px) at scale 0.5. The new sets
are procedural (`Tools/textures/make_masters.py`): the grain lives in roughness streaks
along U, the normal is generated at low relief and applied at 0.25. At the menu camera
the plate now reads as one smooth sheet with a stretched highlight, not as bumps.

### 1.1 How wear is decided

1. **Baked mask (primary).** The models lead's `<part>[_<node>]_mask.png` on UV2
   (R edge, G AO, B cavity). `PartVisuals.with_mask()` binds it per mesh. Chips where
   `R x wear` beats the rank-equalised chip noise; grime where `max(1 - G, B)`.
2. **No mask.** Screen-derivative curvature (`dot(dN, dP) / |dP|^2`, signed, so convex
   only) times the vertex-colour exposure (`max(1 - COLOR.r, 0.5)`), trusted only while
   a pixel is under 2.1 to 3.5 mm. Past that, no chips.
3. **GL Compatibility:** mask only; no mask means clean paint.

## 2. Cost per tier

Texture memory is on device (iOS imports ETC2/ASTC: `import_etc2_astc=true`; normals
ASTC 4x4 at 8 bpp, everything else ETC2 at 4 bpp RGB or 8 bpp RGBA), mips included.

| set | maps | VRAM |
|---|---|---|
| `painted_surface` (livery + powder coat share it) | 1024 RGBA | 1.33 MB |
| `brushed_steel` | 1024 albedo, 1024 roughness, 512 normal | 0.67 + 0.67 + 0.33 = 1.67 MB (was about 2.4 MB with 1024 normal, AO and metallic maps) |
| `scratched_titanium` | same | 1.67 MB (was about 2.4 MB) |
| decals, 7 textures | 1024x256 to 256x128 RGBA | 0.9 MB compressed on disk; **about 2.4 MB in the decal atlas**, which Godot keeps as uncompressed RGBA8 |
| models lead's masks | 12 files, 512 to 1024 RGB | see 4.4: today imported **Lossless**, about 4 MB each at 1024 in VRAM; VRAM-compressed with mips they would be 0.67 MB (1024) or 0.17 MB (512) |

Net for the materials themselves: about 1.5 MB less than before, plus 1.33 MB for the
new surface texture, so roughly flat.

Shader cost (`rb_painted`, per pixel, est. from the code, to be measured on device):

| tier | texture fetches | extra |
|---|---|---|
| Forward+ (phone A15+, Mac) | surface + mask, + paint overlay (+ relief) when a paint job is on: 2 to 4 | curvature: 6 derivatives, about 25 ALU; clear coat is a second specular lobe (engine side) |
| Mobile (older phones) | same as Forward+ | same; the shader has no Mobile-specific cut because it costs the same as the engine's own clear-coated StandardMaterial3D plus one fetch |
| GL Compatibility (simulator) | surface + mask (+ overlay) | no derivatives, no scratch breakup; decals off (GraphicsQuality `decals` = false) |

One shader, so one pipeline family for every painted surface; masks and colours are
uniforms and never compile a new variant. Anisotropy on steel and titanium is a flag on
the engine shader, so it is one more StandardMaterial3D variant each (already warmed by
`warmup.gd`, which loads every file in `assets/materials/`).

## 3. Paint jobs (the contract kept)

`bots[i].paint` still rides from Swift (`PaintJobs.swift`, `BotBuild.paintID`) into
`Livery.begin()`; ids unchanged, the `JOBS` table unchanged. What moved: on the `livery`
slot a paint job is now uniforms on the master (`Livery.painted_master()`: `detail_*`,
`metallic`, `roughness`, `clearcoat`) instead of a StandardMaterial3D detail layer. The
`hdpe` armour path is still StandardMaterial3D and still uses `Livery.painted()`. The
metals no longer need the grain compensation (the master has no grain texture). All ten
jobs bind and survive density matching (`paint_test`: 106 checks).

## 4. Measured, and fixed or handed on

1. **Vertex masks bleed across long triangles.** A vertex value interpolates across a
   whole face, so wear blotched the flat faces of the board's blocks at distance
   (`board_before_distance_fix.jpg`). Fixed: without a baked mask, chips need the
   per-pixel curvature and fade out with distance; the GL tier shows clean paint.
2. **The fill-side camera blows the wedge out.** From beside the fill light the steel
   front plate is one specular lobe and blooms (`hero_close_fill_side_blowout.jpg`).
   That is correct metal behaviour; it matters for the stage lead's hero framing (keep
   big flat steel out of the fill's mirror angle, or drop the fill's specular).
3. **An unshaded emitter adds its albedo.** A softbox made of an unshaded white
   material at emission 3.0 shines at about 4. The board uses black albedo; the stage
   lead's softbox and strips should too, or the 1.1 glow threshold is crossed by every
   steel plate that reflects them.
4. **Mask import settings (models lead's files).** `*_mask.png.import` are
   `compress/mode=0` (Lossless), i.e. raw RGBA8 in VRAM, 4 MB per 1024 mask, and the
   mipmaps flag should be checked too (a mask sampled without mips aliases at fight
   distance). Recommended: `compress/mode=2`, `mipmaps/generate=true`, and 512 px for
   plates and small parts (a mask is low frequency). `Tools/textures/set_import_flags.py`
   does this for `Arena/assets/textures/`; running the same over `Arena/assets/parts/`
   is a one-line change the models lead may want.
5. **Fitted HDPE plates count as painted steel** in `paint_test` (contract 1.2, open item).

## 5. Decals

Seven procedural decals (`Tools/textures/make_decals.py`, `Arena/assets/textures/decals/`):
hazard stripe, KESTREL WORKS maker's mark, TORQ-9 model code, LIFT POINT, HIGH VOLTAGE,
NO STEP, bolt grime. The damage scorch and scratch sets are unchanged. Stencils are
white on transparent and tinted per machine by `Decal.modulate` (white on dark
liveries, near black on pale).

Recraft: one `recraftv3_vector` call, 2 images, **4 credits**. It drew tanks and
soldiers and misspelt the model code; stencil lettering is beyond it. The marks are
set in Barlow Condensed (OFL, already shipped) with cut stencil bridges instead.

`BotMarkings.apply(bot, livery)` (`Arena/render/bot_markings.gd`) places the maker's
mark on each side plate, the model code on the rear deck and the hazard stripe on the
rear face. Each decal is snapped to the visible skin by ray-casting five points against
the skin's triangles; the bounding box face is usually a bolt or a rim and a shallow box
placed there misses the panel (it did, twice). Boxes are 3.5 cm deep, so they never
reach the floor, the opponent, or the chassis wall behind a plate (a 6 cm box printed a
second offset copy there).

## 6. Owed

1. **Hooks (other leads' files):** one line after `setup()` in `workshop/stage.gd`
   `show_bot` and in `fight/fight.gd` where machines are built:
   `BotMarkings.apply(bot, Color(str(config.get("livery", "#d1662b"))))`.
2. **On-device numbers:** shader cost and the decal atlas at 60 fps on the iPhone 17/18
   Pro Max. Everything in section 2 is estimated from the code.
3. **Titanium heat tint near welds** (reference-study 3.3): needs a weld mask; the
   baked mask's channels are all used, so it wants either a fourth channel (alpha) or
   the vertex-colour B channel reserved for it in the contract.
4. **HDPE stress whitening** from the mask edge (StandardMaterial3D cannot read it; would
   move `hdpe` onto the painted master with a plastic preset).
5. The TORQ-9 deck code sits under the flipper arm on the wedge; a per-chassis nudge.
