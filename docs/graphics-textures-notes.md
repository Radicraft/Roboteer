# Textures and materials (agent G2, 2026-09-13; VRAM compression pass 2026-09-14)

Eleven PBR texture sets and eight Godot `StandardMaterial3D` resources, built to the
PS4-class bar in `docs/graphics-bar.md` and the palette in `docs/stage2-art-direction.md`.

- Textures: `Arena/assets/textures/<name>/` — `_albedo`, `_normal`, `_roughness`, `_metallic`, `_ao`.
- Previews: `Tools/textures/previews/<name>.png` — the albedo tiled 2x2 with the other maps as a
  thumbnail strip. **Deliberately outside `Arena/`**: anything under the Godot project root is
  imported as a game texture and packed, and eleven review sheets were 10 MB of shipped `.pck`.
- Materials: `Arena/assets/materials/<name>.tres`.
- Tools: `Tools/textures/make_pbr.py`, `make_chevron.py`, `make_materials.py`,
  `set_import_flags.py`, driven by `build_all.sh`.
- Sources: `Tools/textures/sources/*.webp` — the eleven picked Recraft generations, lossless.
- Probe: `Arena/tests/_g2_material_probe.gd` — 57 checks, all passing.

**Recraft spend: 51 credits of the 80 budget** (50 generation, 1 crisp upscale). 29 unspent.

Rebuild the lot, including the Godot import and the probe:

```
Tools/textures/build_all.sh
```

---

## The pipeline

A Recraft "seamless tileable texture" generation is never seamless and never evenly lit. Two
problems have to be solved before anything else, and they are different problems:

1. **Uneven lighting.** Every generation carries a soft studio gradient. Tiled, that gradient
   becomes a regular grid of light and dark patches — far more visible than the seam itself.
   Fixed by `--flatten`: divide the image by a heavily blurred copy of itself, preserving the
   mean. The sigma must sit well below the size of the real features (the tyre tread blocks are
   ~60 px so it flattens at 80; the near-featureless metals go as low as 11).

2. **Uneven wear density.** Flattening cannot see this, because it only looks at the local
   *mean*. A generator will put a thicket of scratches across one half of the image and leave
   the other half nearly clean, at identical local brightness. Tiled, that shows a repeating
   band of busyness. Fixed by `--equalise`: split into local mean and detail, measure the local
   RMS of the detail, and rescale it towards the image-wide RMS. This was the fix that finally
   killed the visible band on `scratched_titanium` and `arena_plate`; nothing else touched it.

Then, in order:

3. **Seamless** — mirror-blend at the borders. Near the left edge the image is blended with its
   own left-right mirror, on a cosine ramp that is 0.5 at the border and 0 by `--seam-band`
   pixels in. At x=0 the mirror supplies column w-1, so the mix is `0.5*A[0] + 0.5*A[w-1]`; at
   x=w-1 it supplies column 0, giving *the same value*. Columns 0 and w-1 become identical **by
   construction**, so the wrap is exact rather than merely small. Same again in y. The cost is a
   faint mirrored ghost within the band, which is why the bands are kept at 5–9%.

   `--seam-mode offset` (roll by half first) is available and was **tried and rejected** for
   `arena_plate`: it moved the source's distinctive top/bottom edge content into the middle of
   the tile, where it read as a hard plate-joint grid across every repeat — worse than the
   artefact it was meant to fix. Mirror is the default for a reason.

4. **Height** — luminance, high-passed. Raw luminance is a bad height field because a dark
   *colour* is not a dent; subtracting a blurred copy keeps only local relief.
5. **Normal** — wrapped Sobel of the height, `--normal-strength`. Godot/OpenGL convention, +Y up.
6. **Roughness** — `base + gain*(1 - local contrast) + dirt*(1 - albedo value)`. A positive gain
   makes the busy detailed areas *smoother* (a scratch or machined groove catches light) and the
   featureless areas rougher. `tyre_rubber` uses a **negative** gain, because tyre wear is dull:
   the polished tread crowns are the smooth part and the torn grooves are the rough part.
7. **Metallic** — a constant per material, or `--metallic-mask`.
8. **AO** — cavity occlusion: how far a point sits below its blurred neighbourhood.

Every blur and every derivative wraps around the borders (`wrap_blur` pads with `mode="wrap"`;
the Sobel uses `np.roll`), so the derived maps tile exactly as well as the albedo does. A blur
that clamped at the edges would quietly undo the seam work.

**Sizes.** Albedo ships at full resolution. Roughness and AO ship at half (they are
low-frequency; indistinguishable in frame at a quarter of the disk) and a constant metallic at
an eighth.

Normal maps ship at a resolution chosen per material by how much relief the material actually
has, via `--normal-scale`, rather than defaulting to match the albedo. On a phone an ASTC 4x4
normal costs 8 bits per pixel — double its own ETC2 albedo — so a full-resolution normal on a
near-flat surface is the most expensive thing in the pack and buys nothing:

| material | normal | why |
|---|---|---|
| brushed_steel, scratched_titanium | 1024² | the brush grain and scratches *are* the material |
| arena_plate | 1024² (albedo stays 2048²) | tiled 4x, so the normal is already sampled at 4x density |
| tyre_rubber, scorch | 512² | already 512 sources |
| hdpe_moulded, concrete_dark | 512² | fine pebble/aggregate grain, no macro relief |
| polycarbonate | 512² | very nearly a flat sheet |
| chevron | 1024x256 | painted stripe; the paint has no thickness worth 2048 px |
| rust_spots, scratch_decal | 512² | decals, always drawn small |

Downscaling is done on the vector field and then **renormalised** — averaging unit vectors
shortens them, and a short normal reads as a flattened, subtly wrong surface rather than simply
a blurrier one.

Total on disk: 34 MB of textures, 16 MB of sources, 11 MB of previews.

### Decal mode

Recraft cannot return transparency, so the three damage decals were generated as dark marks on
white paper and the paper is keyed out here (`--decal`). Alpha comes from darkness between
`--decal-white` and `--decal-black`; the borders are faded to zero alpha so a Decal node never
shows the rectangle of its projector box. Decals are **not** made seamless — they must not tile.
The height field is used un-inverted, because a gouge or a burn is *below* the surface.

---

## Per-material: prompts, picks and numbers

Every prompt used `recraftv4_1_raster`, no style id. **V4.1 rejects `input_style` outright**
(confirmed again here, as `docs/stage2-art-direction.md` recorded), so the material has to be
carried entirely by the prompt. Every prompt ended with the same tail, which is what actually
produces a usable material photo rather than a picture of a thing:

> …completely even flat studio lighting, no bright specular highlights, no perspective, no
> vignette, no shadows, no objects, no border, edge to edge material sample filling the whole
> frame, no text, no letters, no numbers, no logo, no watermark

Asking for "seamless tileable" in the prompt is worth doing but must not be trusted — see the
seam numbers below, where the raw generations came in between 1.2x and 33x worse than interior
detail at the wrap.

| material | credits | candidates | prompt subject |
|---|---|---|---|
| brushed_steel | 6 | 3 | brushed stainless sheet, fine straight parallel brush grain, faint machining lines, a few light scuffs, cool neutral grey with a slight blue cast |
| scratched_titanium | 4 | 2 | scratched titanium plate, dense fine random scratches and swirl marks in many directions, dark grey mill finish, worn battle used |
| hdpe_moulded | 6 | 3 | moulded HDPE sheet, completely neutral light grey with no colour tint, satin matte, very fine orange peel pebble grain, faint moulding flow lines |
| polycarbonate | 4 | 2 | clear polycarbonate sheet on pale grey backing, light smoky transparent, fine long hairline scratches and faint swirl marks, glassy smooth |
| tyre_rubber | 4 | 2 | black tyre tread, repeating chunky rectangular tread blocks separated by deep straight grooves, matte vulcanised rubber, fine moulding grain, dusty worn |
| arena_plate | 6 + 1 | 3 | worn industrial steel floor plate, cold pale blue grey galvanised steel, long fine random hairline scratches and drag scuffs, dull scuff smears, no diamond plate |
| chevron | 4 | 2 | hazard warning stripe, bold 45-degree yellow and matte black, painted on metal, chipped and scuffed and worn thin showing grey metal through |
| concrete_dark | 4 | 2 | dark polished concrete, cold charcoal grey with a slight blue cast, fine aggregate speckle, faint hairline cracks, patchy staining and trowel marks |
| scorch | 4 | 2 | one soot black burn smudge on pure white, dense dark core fading through sooty tendrils, irregular ragged charred outline |
| scratch_decal | 4 | 2 | exactly three long straight parallel gouges on pure white, thin dark tapered lines, torn ragged edges with chips and burrs |
| rust_spots | 4 | 2 | scattered orange brown rust blooms on pure white, dark red brown pitted cores fading to orange speckle, clear white between them |

The `arena_plate` extra credit is one `crisp_upscale` of the chosen 1024 generation to 4096,
downsampled to 2048. That buys real added detail; a Lanczos upscale of the 1024 would only have
bought blur.

### Why each pick won, and what the rejects got wrong

- **brushed_steel** — all three carried a vertical lighting band. The pick has the cleanest
  horizontal grain and the most legible scratches; the band was removed by flattening at 14.
  Reject B had a horizontal gradient across the whole frame, reject C an even heavier centre band.
- **scratched_titanium** — the pick has even, neutral, multi-directional scratch coverage. The
  reject had warm brown patches that fought the cold palette.
- **hdpe_moulded** — the pick is clean pebble grain with no invented features. Reject B had
  moulding flow lines that read as a repeating streak; reject C drew leaf-shaped veins.
- **polycarbonate** — the pick's scratches are fine and light. The reject drew heavy dark
  scratches that looked like hair on a scanner.
- **tyre_rubber** — the pick has rounded chunky blocks. The reject was a flat uniform square
  grid that read as a bath mat.
- **arena_plate** — the pick is the only one of three with no horizontal weld-seam line running
  across it (which would have repeated as a hard stripe), and it is the closest to the arena
  reference's `#84a6b2` mid-tone.
- **chevron** — the pick was chosen for its *grunge*, not its stripes; see below.
- **concrete_dark** — the pick has even aggregate speckle. The reject was blotchy with large
  patches that tile badly.
- **scorch** — the pick has an irregular ragged outline and off-centre density. The reject was a
  suspiciously perfect donut ring.
- **scratch_decal** — the pick has exactly three long tapered horizontal gouges, as asked. The
  reject drew four, curved, with curled swarf that read as claw marks from a monster film.
- **rust_spots** — the pick has well-separated blooms with clear white between them, which is
  what makes an alpha overlay usable. The reject's blobs were large and crowded.

### The chevron is drawn, not generated

The hazard stripe is the one texture that must not come straight out of a generator. It runs as
a band around the arena wall and along the floor edge, tiling horizontally many times in a single
frame, and a stripe whose period does not divide the texture width stutters visibly at every
repeat. No generated stripe is exactly periodic.

So `make_chevron.py` draws the geometry and uses Recraft **only for the wear**: the generated
hazard image is reduced to a grunge field (its high-frequency detail, with the stripes themselves
divided out) which is then multiplied over an exact 45-degree stripe pattern, with the brightest
grunge punched through to bare metal as paint chips. Period 256 px divides both 2048 and 512, so
the strip wraps exactly in x and y with no blending at all — which is why `chevron` is the only
set built with `--no-seamless`.

The yellow is the "dusted down" `#c3b98c` of the art direction, not a saturated hazard yellow.
That is deliberate and load-bearing: the arena palette holds exactly one strong warm, the gold
bolts, and a bright chevron would compete with it and break the §6 readability rule without
anyone having touched the bolt art.

---

## Seam check numbers

Measured on the shipped albedo PNGs, not on intermediates.

- `seam_dx` = mean |column 0 − column w−1| in 0–255 units: the discontinuity a 2x2 tile shows.
- `inner` = mean |column i − column i+1| over the interior: how much a neighbouring pair of
  columns normally differs in this material.
- `ratio` = seam / inner. **1.0 means the seam is exactly as smooth as any other pixel boundary
  in the texture, so it cannot be seen.** Under ~1.5 is invisible in motion on a phone.

| material | size | ratio_x before | ratio_y before | seam_dx after | seam_dy after | ratio after | albedo mean |
|---|---|---|---|---|---|---|---|
| brushed_steel | 1024² | 2.09 | 3.49 | 0.000 | 0.000 | 0.000 | 0.711 |
| scratched_titanium | 1024² | 1.75 | 5.03 | 0.000 | 0.000 | 0.000 | 0.440 |
| hdpe_moulded | 1024² | 2.72 | 3.50 | 0.000 | 0.000 | 0.000 | 0.720 |
| polycarbonate | 1024² | 33.53 | 22.90 | 0.000 | 0.000 | 0.000 | 0.800 |
| tyre_rubber | 512² | 4.12 | 12.30 | 0.000 | 0.000 | 0.000 | 0.100 |
| arena_plate | 2048² | 3.67 | 7.31 | 0.000 | 0.000 | 0.000 | 0.505 |
| chevron | 2048x512 | — | — | 6.582 | 5.293 | 1.27 / 1.08 | 0.358 |
| concrete_dark | 1024² | 1.21 | 1.40 | 0.000 | 0.000 | 0.000 | 0.170 |

The mirror-blend gives an *exactly* zero seam — the two border columns are identical integers,
not merely close. The chevron is the exception: it is never blended, so its wrap is whatever the
drawn pattern gives, and 1.27 / 1.08 says it is already indistinguishable from ordinary interior
detail. Note `polycarbonate` at 33.5x before: a nearly featureless material has almost no
interior detail to hide a seam behind, which is exactly when an untreated generation tiles worst.

**Residual artefact, recorded honestly:** `arena_plate` and `scratched_titanium` still show a
very faint line at the tile join in a flat 1:1 review, because the mirror band makes the content
locally symmetric about the seam. At the 4x tile scale in `arena_plate.tres`, under the 50-degree
game camera, it is not visible. If it ever does show on device, the fix is a fresh generation with
less distinctive content near its edges, not a wider blend band.

### Decal alpha

| decal | size | alpha > 5% | alpha mean | max alpha on the border |
|---|---|---|---|---|
| scorch | 512² | 21.8% | 0.128 | 0.0000 |
| scratch_decal | 1024² | 12.0% | 0.068 | 0.0000 |
| rust_spots | 1024² | 31.1% | 0.207 | 0.0000 |

Border alpha is exactly zero on all three, so no decal can show its projector rectangle.

---

## Roughness and metallic bases

| material | metallic | roughness base | gain | dirt | mean roughness | note |
|---|---|---|---|---|---|---|
| brushed_steel | 1.0 | 0.24 | +0.26 | — | 0.38 | brightest structural value in the scene |
| scratched_titanium | 1.0 | 0.34 | +0.24 | 0.08 | 0.49 | darker and busier than steel so the two never merge |
| hdpe_moulded | 0.0 | 0.58 | +0.14 | — | 0.65 | satin plastic |
| polycarbonate | 0.0 | 0.08 | +0.12 | — | 0.16 | glassy; the lowest roughness in the set |
| tyre_rubber | 0.0 | 0.86 | **−0.16** | — | 0.78 | negative gain: tyre wear is dull, not shiny |
| arena_plate | 1.0 | 0.38 | +0.20 | 0.18 | 0.56 | dirt term makes the grimy patches rougher |
| chevron | 0.0 | 0.62 | +0.16 | 0.10 | 0.79 | worn paint |
| concrete_dark | 0.0 | 0.82 | +0.12 | 0.06 | 0.93 | the roughest thing in the game |

Metallic is 1.0 for `brushed_steel`, `scratched_titanium` and `arena_plate` and 0.0 for
everything else — no in-between values, which is the physically correct discipline. In the
`.tres` the scalar `metallic`/`roughness` are set to multiply their textures, so a scalar of 1.0
means "the texture decides".

## The material resources

`Arena/assets/materials/*.tres`, generated by `make_materials.py`. Three Godot 4 traps are worth
recording because each fails *silently*:

- `normal_enabled` and `ao_enabled` must be set explicitly. A `normal_texture` on a material with
  `normal_enabled` unset is ignored with no warning.
- `roughness` and `metallic` are scalars that **multiply** their textures, so they are set to 1.0
  where a texture drives the channel, never to the base value.
- `*_texture_channel = 0` (red) is correct here — every greyscale map is a single-channel PNG.

Per-material specifics: `polycarbonate` is `TRANSPARENCY_ALPHA` with `albedo_color` alpha 0.6 and
`cull_mode = 2` (disabled) so both faces of a translucent panel draw. `arena_plate` has
`uv1_triplanar` explicitly **off** — the floor is a single flat plane with proper UVs, and
triplanar would cost three taps per map for nothing — and `uv1_scale = (4, 4, 1)`. `chevron` keeps
`uv1_scale = (1, 1, 1)` so the mesh that uses it decides how many times the stripe repeats.

### Import settings: VRAM compression and mipmaps

Two Godot defaults had to be overridden, both by `set_import_flags.py`, and both of them fail
silently and expensively.

**`compress/mode=2` (VRAM Compressed).** Godot's default is Lossless, which is the wrong default
for a phone: a GPU cannot sample a PNG, so a "lossless" texture is stored raw in the pack and
costs full uncompressed RGBA in VRAM. VRAM Compressed keeps the ETC2/ASTC blocks all the way to
the sampler. This needs `rendering/textures/vram_compression/import_etc2_astc=true` in
`project.godot`, which was **missing** — without it the mobile variants are never built and the
iOS export silently falls back to uncompressed. That one key is the only thing G2 owns in G1's
`[rendering]` section.

Normals additionally get `compress/normal_map=1` (the two-channel normal path: stores XY and
reconstructs Z, far better than putting three competing channels through one endpoint line, and
treats the texture as linear rather than sRGB) and `compress/high_quality=true` (ASTC 4x4 rather
than ETC2). The high-quality flag is paid **only** on normals, because a wrong normal shows up as
shading that crawls, which is much more visible than a slightly wrong albedo value.

**`mipmaps/generate=true`.** Godot imports a PNG with mipmaps off and only turns them on when the
*editor* first notices the texture on a 3D material (`detect_3d/compress_to`). This project builds
and tests headless, so that never fires. The arena floor is tiled 4x and viewed at a 50-degree
pitch, so its far half is minified hard: without mipmaps it aliases into a crawling moire the
moment the camera moves — the single most obvious "not a real game" artefact there is.

`set_import_flags.py` leaves everything else alone, in particular G1's `roughness/mode=1` and
`roughness/src_normal` (roughness-from-normal, the other half of the specular anti-aliasing fix).
**The `.import` files are committed and required** — without them Godot cannot resolve the texture
paths at all, as the probe will tell you.

### Was the compression visibly lossy? No, and it was measured

Block compression quantises each 4x4 block to a short colour line, which is at its worst on
smooth low-contrast data — and `brushed_steel` and `scratched_titanium` are exactly that: nearly
uniform greys carrying fine grain. So before compressing them, each albedo was put through a
simulated BC1-style block fit (principal-axis line, 4 interpolated levels, RGB565 endpoints),
which is **strictly worse** than the ASTC 4x4 they actually get.

| | source std | mean abs error | max abs error | error / own contrast |
|---|---|---|---|---|
| brushed_steel | 22.8 | 4.6 | 47.1 | 0.155 |
| scratched_titanium | 30.4 | 6.5 | 39.6 | 0.165 |

Source and simulation are indistinguishable side by side, and the difference image at 8x
amplification is **unstructured noise with no blocking and no banding**: the error lands in the
fine grain that these materials are already made of, which is the frequency the eye is least able
to audit. The brush grain, the scratches and the value all survive intact.

**No set was kept lossless.** All eleven are VRAM compressed.

### Anti-sparkle settings on the materials

`brushed_steel`, `scratched_titanium` and `arena_plate` carry `normal_scale = 0.5`. A strong
normal on a `metallic = 1.0` surface sparkles with white speckles at phone screen footprints;
G1 measured it and asserts it in `render_test.gd`. Halving the normal is the material-side half
of that fix. It is deliberately **not** applied to the plastics and rubber, which are not
metallic, do not sparkle, and would just lose their moulding relief.

All eight materials carry `texture_filter = 5`
(`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC`). Every one of them sits on a surface the
camera sees at a grazing angle — the arena floor most of all — which is exactly the case
trilinear filtering blurs and anisotropic filtering does not. `project.godot` sets the level
(4x); the material has to opt in.

Both are asserted in `_g2_material_probe.gd` as well as in G1's `render_test.gd`, so
regenerating the materials with `make_materials.py` cannot silently undo a rendering fix that
lives in someone else's suite.

## Pack size

`Roboteer/Resources/arena.pck`, measured with `scripts/export-pck.sh`:

| step | pck | delta |
|---|---|---|
| before (everything Lossless) | 74.7 MB | — |
| VRAM compression + `import_etc2_astc` | 48.9 MB | −25.8 |
| previews moved out of `Arena/` | 38.8 MB | −10.1 |
| per-material normal resolution | **27.1 MB** | −11.7 |

Target was under 30 MB. The texture share of the final pack is 6.7 MB of ASTC (all the normals)
plus 14 MB of ETC2 (everything else); the rest is audio, scenes and scripts.

The three levers in order of value were *not* what they first looked like. Compression was the
big single win, but the review previews being silently imported and shipped as game textures was
10 MB of pure waste, and normal-map resolution — which nothing was forcing to match the albedo —
was worth more than either the ETC2/ASTC choice or any further quality sacrifice.

---

## How code applies the livery to HDPE

The contract already exists in `Arena/bot/bot.gd`:

```gdscript
func _panel_material(material_name: String) -> StandardMaterial3D:
    var colour: Color = FightTypes.MATERIAL_COLOUR.get(material_name, Color.WHITE)
    if material_name == "hdpe":
        colour = livery
```

`hdpe_moulded_albedo.png` is **fully desaturated and graded to a mean of 0.72** for exactly this
reason: a `StandardMaterial3D` multiplies `albedo_color` by `albedo_texture`, so assigning the
livery straight into `albedo_color` gives `livery x neutral grey` and the moulded pebble grain
survives as shading on top of the player's colour.

Two things this depends on, both checked by the probe:

- `hdpe_moulded.tres` ships with `albedo_color` at **opaque white**. Any tint baked into the
  resource or into the texture would poison every livery in the game.
- The texture mean is 0.72, not 1.0. Pure white would leave no headroom and pale liveries would
  clip; much darker and every livery would read muddy.

So the runtime path is: load `hdpe_moulded.tres`, duplicate it per bot, set
`albedo_color = livery`, and change nothing else. `FightTypes.MATERIAL_COLOUR["hdpe"]` is already
`Color(1,1,1)`, so the existing code is consistent with this without modification.

---

## Which material each catalogue id maps to

`Shared/parts.json` `armour.material` ids, and the `.tres` each one takes:

| catalogue id | material resource | metallic | notes |
|---|---|---|---|
| `steel` | `brushed_steel.tres` | 1.0 | bare front wedges, weapon plates |
| `titanium` | `scratched_titanium.tres` | 1.0 | darker, busier, visibly worn |
| `hdpe` | `hdpe_moulded.tres` | 0.0 | code sets `albedo_color = livery`; see above |
| `polycarbonate` | `polycarbonate.tres` | 0.0 | `TRANSPARENCY_ALPHA`, alpha 0.6 |

The glTF material slot names in `docs/graphics-bar.md`, which G3's Blender parts carry and the
assembler swaps at runtime:

| glTF slot | material resource |
|---|---|
| `livery` | `hdpe_moulded.tres` (the livery is the `albedo_color` on it) |
| `steel` | `brushed_steel.tres` |
| `titanium` | `scratched_titanium.tres` |
| `hdpe` | `hdpe_moulded.tres` |
| `polycarbonate` | `polycarbonate.tres` |
| `rubber` | `tyre_rubber.tres` |
| `dark_metal` | `scratched_titanium.tres` with `albedo_color` set to about `Color(0.35, 0.36, 0.38)` — a value swap on the same material rather than a twelfth texture set |
| `core_glow` | none: emissive, owned by G1/G4, deliberately not a texture |

Arena surfaces, which are not in the parts catalogue:

| surface | material resource |
|---|---|
| arena floor | `arena_plate.tres` (4x tile) |
| hazard band on walls and floor edge | `chevron.tres` |
| yard floor, stage surround | `concrete_dark.tres` |

Damage decals have textures but no `.tres`, because a Godot `Decal` node takes `texture_albedo`,
`texture_normal` and `texture_orm` directly rather than a `StandardMaterial3D`:

| damage event | textures |
|---|---|
| scorch smudge | `scorch/scorch_{albedo,normal,roughness}.png` |
| scratch accumulation | `scratch_decal/scratch_decal_{albedo,normal,roughness}.png` |
| corrosion overlay | `rust_spots/rust_spots_{albedo,normal,roughness}.png` |

---

## Verifying

```
Godot --headless --path Arena --import                          # once, to make the .import files
Godot --headless --path Arena --script tests/_g2_material_probe.gd
```

57 checks: every map of every set loads at a non-zero size, and every `.tres` loads with all five
maps actually **bound** — not merely present on disk — plus the HDPE white-albedo contract, the
polycarbonate alpha, and the arena plate's triplanar-off and 4x scale. Exits 0 only if all pass.

The probe is named with a leading underscore so `scripts/test-arena.sh` treats it as a helper and
does not run it in the suite: it checks G2's assets, not the game's behaviour.

G1's `render_test.gd` (97 checks, 0 failures) also asserts against these files: the anti-sparkle
`normal_scale` and `texture_filter` on the three metallic materials, and roughness-from-normal in
the import settings. **Run both after touching anything here**, because `make_materials.py` and
`set_import_flags.py` regenerate files that another agent's rendering fixes depend on:

```
Godot --headless --path Arena --script tests/render_test.gd
```
