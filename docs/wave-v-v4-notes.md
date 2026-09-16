# Wave V, agent V4: sharp machines, resolution, bot size

Brief v4 (`docs/brief-v4-playtest.md`) §7 "Blurry house bots", built 2026-09-16. The owner
played a fight on his iPhone and said:

> the bot feels a bit small on screen and not high res enough

and earlier

> house bots look blurry

Three separate faults, measured separately. In order of how much of the complaint each one
turned out to be:

1. **The machine was 10 % of the frame height.** 55 pt on a 556 pt screen. Fixed in the
   camera: it is 19 to 25 % through an exchange now, and never under 17 %.
2. **The largest surface on every machine was untextured.** The `livery` slot — 12.0 m² of
   the parts kit's 52.6 m², more than any other slot — was a flat `StandardMaterial3D` with
   no albedo, normal, roughness or AO map at all. It now wears `hdpe_moulded.tres`, which
   is what `docs/graphics-textures-notes.md` has specified all along.
3. **The chassis unwrap carries an eighth of the texel density the rest of the kit does.**
   288 to 434 texels per metre against a weapon's 1 900 to 3 400. On the workshop stage
   that is 0.63 texels per screen pixel: magnified, which is blur that no filter can undo.
   Normalised at bind time; the raw spread is 11.4x, it is 1.6x after.

And one fault found, measured and **deliberately not fixed here**, because the fix is one
key in a section that decides how two files this agent may not touch lay themselves out:

4. **The fight is drawn at 85 % of the device's pixels.** See "The resolution loss that is
   still there" below. It is the single largest remaining sharpness lever.

Nothing was regenerated or upscaled. The measurements say no texture in the game is too
small; the pack grew 3.1 MB, all of it ASTC.

---

## 1. Resolution audit

Every question in the brief, answered with where the answer comes from.

| | before | after | where |
|---|---|---|---|
| Tier an A19 iPhone picks | `high` | unchanged | `graphics_quality.gd` `detect()` |
| `scaling_3d/scale` | never set (Godot default 1.0) | **pinned at 1.0** | `project.godot` |
| `scaling_3d/mode` | never set (default 0, bilinear) | **pinned at 0** | `project.godot` |
| MSAA | 4x (`msaa_3d=2`), re-applied per SubViewport | unchanged | `project.godot`, `apply_viewport()` |
| Screen space AA | off on high, FXAA on medium | unchanged | `apply_viewport()` |
| Mipmap bias | 0.0 (default) | **−0.35** | `project.godot` |
| Anisotropic level | `2` = **4x** | **`3` = 8x** | `project.godot` |
| Mipmap filter | linear (default) | unchanged, now asserted | `project.godot` |
| Material texture filter | `5` (linear + mipmaps + anisotropic) on all 8 `.tres` | unchanged | `assets/materials/*.tres` |
| iOS compression | `import_etc2_astc=true`; ETC2 on 38 of 49 maps, ASTC on the 11 normals | **ASTC on 35 of 49**: every map of the 7 sets a machine wears | `assets/textures/**/*.import` |
| Size limits | `process/size_limit=0`, `mipmaps/limit=-1` everywhere | unchanged (there were none) | `.import` files |
| Simulator path | `gl_compatibility` → low tier, `stretch_shrink = 4` | unchanged | `apply_subviewport_container()` |

**The tier is `high` and that is correct.** `detect()` reads the driver first (`metal`, not
`dummy`), then `DisplayServer.get_name()` (not `headless`), then the method
(`forward_plus`, from `renderer/rendering_method.mobile`), then the model: an iPhone 17 is
`iPhone18,x`, and `_iphone_is_modern()` wants `>= 14`. So Forward+, MSAA 4x, SSAO, SSR,
volumetric fog, decals, 4096 shadow atlas, soft shadows. Nothing in the tier machinery was
costing resolution.

**`scaling_3d` was never the problem but is now pinned anyway.** It had no key in
`project.godot` at all, so it ran on Godot's defaults, which are the right ones (bilinear,
1.0). One stray editor click on that page would have been a silent resolution cut with no
way to notice it, so both keys are written down and `render_test` asserts them.

**Anisotropic 4x → 8x** is the one measured raise. The arena floor is a 2048 plate tiled
4x (`arena_plate.tres`, `uv1_scale = (4, 4, 1)`) seen at `CAM_PITCH_DEG` 50, so the far half
of it is sampled at an anisotropy around 1:6 and 4 taps leave it smeared. 16x was not taken:
past 8 the taps double again on the largest surface in the frame for a difference this pitch
cannot show.

**Mipmap bias −0.35.** Every surface a machine wears is MINIFIED at the fight camera — the
measured worst is 6.4 texels per screen pixel and the typical is 8 to 10 — so the sampler is
reading mip 2 to mip 3 and the grain that makes brushed steel look like metal is averaged
out before it reaches the screen. A third of a mip of negative bias puts some back. It is the
first dial to back off if the floor plate shimmers in motion on the phone, before anything
else in `[rendering]` is touched.

**ASTC rather than ETC2 on everything a machine wears.** `compress/high_quality=true` is what
picks ASTC 4x4 over ETC2 on the `etc2_astc` platform. Before this pass it was paid only on
normal maps (G2's note explains why: a wrong normal crawls). But ETC2 RGB8 is 4 bits per
pixel with one colour line per 4x4 block, and it is at its worst on exactly what these
materials are — near uniform grey carrying fine grain — and worst of all in the MIPS, which
is where the fight camera reads. The seven sets a machine or a house bot wears
(`brushed_steel`, `scratched_titanium`, `hdpe_moulded`, `polycarbonate`, `tyre_rubber`,
`scratch_decal`, `rust_spots`) are now ASTC on every map: 24 `.import` files flipped.

`arena_plate`, `concrete_dark`, `chevron` and `scorch` stay on ETC2 on purpose. They are
the floor, the walls and a burn mark; they are half the texture bytes in the pack
(`arena_plate` alone is a 2048 albedo), and they are seen at a grazing angle where block
error hides. Moving them too would have cost about another 2 MB for a difference nobody
would be able to point at.

### The resolution loss that is still there

**Measured: the fight is rendered at 2417 x 1112 and blown up to 2622 x 1206.** That is
85 % of the device's pixels, upscaled by a non integer 1.0846, on every frame of every
fight. `GraphicsQuality.viewport_oversample()` is the probe and `describe()` now reports it,
so it can be read off the phone; `render_test` asserts the arithmetic against a SubViewport
posed exactly the way the phone poses the root window.

Where it comes from, in three steps:

- `project.godot` `[display]` sets `window/stretch/mode = "canvas_items"` with a base of
  2412 x 1112. In that mode Godot renders the root window at its REAL pixel size and gives
  every Control a `get_visible_rect()` in stretched canvas units. On an iPhone 17 those are
  2622 x 1206 and 2417 x 1112.
- The fight is not drawn into the root viewport. `fight.tscn` has a `SubViewportContainer`
  called `Stage` with `stretch = true`, and `fight.gd` builds the whole 3D world inside a
  `SubViewport` under it.
- A `SubViewportContainer` sizes its child from its own **Control** size, which is in canvas
  units. So the SubViewport is 2417 x 1112 and its texture is drawn across a 2622 x 1206
  window.

**The fix is `window/stretch/mode = "disabled"`, and it is not this agent's key.** It
changes the coordinate space `hud.gd` and `controls.gd` lay out in, and brief v4 §8 gives
those to V2. Everything needed to make that call is measured here:

- Both files are already resolution independent in exactly the way the change needs. Each
  computes `_pt = min(s.x / 1206, s.y / 556)` from `get_visible_rect().size`
  (`hud.gd:1118`, `controls.gd:900`) and sizes every font, pad and control off it. Today
  that is `min(2417/1206, 1112/556) = 2.00`, multiplied by the 1.0846 stretch on the way to
  the glass: 2.169 device pixels per point. With the stretch disabled it becomes
  `min(2622/1206, 1206/556) = 2.169` with no stretch. **The same number.** Nothing on the
  HUD or the controls changes size.
- The safe area gets BETTER, not worse. `FightConfigFixture.swift` sends
  `safe_area_px` in **device** pixels (`insets * UIScreen.scale`) and `hud.gd` consumes it
  as canvas units with no conversion, so today every inset is 8.5 % too generous. With the
  stretch disabled the two units are the same thing and it becomes exact.
- `fight.gd._points_to_pixels()` uses the same ratio, so a forwarded orbit drag changes
  sensitivity by 8.5 %, in the direction of being correct.
- The simulator gets FASTER. Today the low tier's `stretch_shrink = 4` divides a 2417-wide
  canvas; with the stretch disabled it divides an 874-wide one, so the software rasterizer
  draws a sixteenth of what it draws now.

Two things were tried on paper and rejected here rather than shipped:

- **Supersampling the fight SubViewport** (`scaling_3d_scale` 1.085 on the high tier) would
  render the 3D pass at device density and resolve it down before the container's upscale.
  It removes aliasing but it cannot restore the resolution, and it costs 18 % more fragment
  work on a phone whose frame rate has still never been measured. Left at 1.0.
- **Sizing the SubViewport by hand** (`stretch = false`, native `size`, a compensating
  `Control.scale`) works only under one of the two plausible readings of
  `SubViewportContainer`'s draw rectangle, and the wrong reading crops or shrinks the whole
  fight view by 8 %. There is no way to tell which is right headlessly — the dummy
  rasterizer records no draw commands — and it is not a thing to guess at on a build the
  owner is playing.

---

## 2. Texel density

The only number that says whether a texture is big enough:

```
texels per screen pixel  =  (UV units per metre  x  uv1_scale  x  texture size)
                            / screen pixels per metre
```

Above 1 the texture is minified and the mip chain is doing the work. Below 1 it is
**magnified**, which is blur no filter can undo and the only case where a bigger texture is
the answer.

Measured over all 41 `.glb` files, 145 machine surfaces, by
`Arena/tests/texel_density_test.gd` through the same code the game binds with.

### The screen, measured

| camera | distance | frame height | screen pixels per metre |
|---|---|---|---|
| fight, two machines 1.5 m apart | **6.10 m** (was 9.88) | 3.04 m | **183** |
| workshop turntable | 2.40 m | 1.20 m | **465** |
| workshop pinched to `WORKSHOP_ZOOM_MIN` | 0.96 m | 0.48 m | 1163 |

The workshop is the closest a machine is ever seen and is therefore the view that decides
how big a texture has to be. The fight is not: at 183 px/m a 1024 texture is minified
whatever you do with it.

### What the unwraps carry

UV units per metre, from the glTF itself. This is the finding:

| part group | UV units/m | texels/m at the shipped `uv1_scale` |
|---|---|---|
| chassis (`tall_tank`, `box`, `wedge`, `pyramid`, `long_low`) | 0.143 to 0.211 | **293 to 434** |
| chassis (`shell`) | 0.469 | 961 |
| house bot hulls and weapons | 0.394 to 1.229 | 807 to 2 517 |
| player weapons, utilities, wheels, armour | 0.742 to 1.646 | 1 519 to 3 405 |

The slots inside one `.glb` agree to within 2 % (`box.glb` is 0.167 to 0.176 across four
slots), so this is a property of the part, not of the material. A chassis at 0.176 UV/m with
`uv1_scale = 2` shows **less than a third of one tile** of brushed steel across its whole
body: the material is not tiling, it is being blown up. That is the blur, and it is an
unwrap that does not match the rest of the kit rather than a texture that is too small.

### What was done, and why not bigger textures

`PartVisuals.bind()` now measures each mesh's UV density once (strided over at most 256
triangles of its largest surface, cached by mesh RID for the life of the process) and gives
each surface a `uv1_scale` snapped from `UV_SCALE_STEPS` so it lands on
`TARGET_TEXELS_PER_M = 1600`. The texture sets are seamless by construction —
`docs/graphics-textures-notes.md` measures their wrap seam at exactly zero — so scaling the
UVs is free and is what they were authored for.

| | before | after |
|---|---|---|
| Lowest texel density on a machine | 293 (`tall_tank`) | **1 173** |
| Highest | 3 342 (`srimech`) | **1 896** |
| Spread across the kit | **11.4x** | **1.6x** |
| Worst texels per screen pixel, workshop | **0.63** (magnified) | **2.52** |
| Worst texels per screen pixel, fight | 1.6 | 6.4 (minified, correct) |
| Pack cost | — | **zero** |

**No texture was regenerated or upscaled, and that is the measured answer, not a shortcut.**
After the scale, the worst surface in the game sits at 2.52 texels per screen pixel at the
closest view there is. Raising `hdpe_moulded`, `brushed_steel` and `scratched_titanium` to
2048 (the obvious reading of the brief) would have added roughly 16 MB of ASTC to a 28 MB
pack to buy headroom on a number that is already 2.5x above the line.

The 1 600 target is a compromise and is documented as one in `part_visuals.gd`. The close
views want about 900 to be exactly sharp; the fight camera at 183 px/m wants about 250; one
number serves both. 1 600 gives the workshop 3.4 texels per pixel of headroom and leaves the
fight to the mip chain, the normal map and the machine now being a quarter of the frame
instead of a tenth. Raise it to sharpen the workshop and flatten the fight; lower it for the
reverse.

**The proper fix is a re-unwrap in `Tools/blender/**`**, which is agent G3's. When the
chassis are unwrapped at the same density as the weapons bolted to them, every scale here
converges on 1.0 and nothing in `part_visuals.gd` has to change: the code measures, it does
not assume.

### The livery, which had no texture at all

`PartVisuals._livery_material()` was `_flat(colour, 0.42, 0.25)`: a bare
`StandardMaterial3D`, no maps. `livery` is **12.0 m² of the kit's 52.6 m²**, the largest
single slot there is, so the biggest area of every machine in the game had no grain, no
normal, no roughness variation and no ambient occlusion. It is now `hdpe_moulded.tres`
duplicated with `albedo_color = livery` and the clear coat kept on top — which is the
contract `docs/graphics-textures-notes.md` wrote down ("load hdpe_moulded.tres, duplicate it
per bot, set albedo_color = livery, and change nothing else") and which the `hdpe` slot
three lines away had been honouring all along. The albedo is graded to a mean of 0.72 for
exactly this, so the moulded pebble grain survives as shading over the player's colour.

Two smaller changes came with it: `roughness = 0.62` multiplies the texture's 0.65 mean back
to the 0.40 the flat material sat at, and the old `metallic = 0.25` is gone — `hdpe_moulded`
ships a constant-zero metallic map that would have multiplied it away, and the clear coat is
what paint's specular actually is.

### Geometry: is there enough of it?

Measured the same way. 134 808 triangles across the kit, 52.58 m² of surface.

| | triangles | tris/m² | p90 triangle edge | on screen at the fight camera |
|---|---|---|---|---|
| chassis | 8 424 to 11 856 | 2 020 to 3 260 | 52 to 71 mm | 10 to 13 px |
| player weapons | 1 308 to 3 512 | 2 250 to 3 400 | 46 to 128 mm | 8 to 23 px |
| **house bot hulls** | **1 384 to 3 328** | **1 495 to 3 640** | **85 to 118 mm** | **16 to 22 px** |
| armour plates | 1 136 to 1 540 | 2 140 to 2 150 | 171 to 266 mm | 31 to 49 px |
| wheels | 956 to 992 | — | 21 to 34 mm | 4 to 6 px |

A built machine is 20 to 30 k triangles and a fight with a house bot is 60 to 80 k, which is
nothing for an A19. **No part needs remodelling for the new framing.** The armour plates
have the longest edges in the kit and that is correct: they are flat panels, and a flat panel
does not get better with more triangles.

What WOULD need remodelling, if it is ever shown larger: `anvil_hull` and `cinder_hull` are
the two lowest triangle densities a player sees up close (1 495 and 3 640 tris/m² with a p90
edge over 110 mm, 55 px on the workshop stage), and they are the parts whose surfaces are
drums and discs rather than panels. If wave V gives the house bots a portrait or a close
pass, those two are where faceting shows first. `Tools/blender/**`, agent G3.

---

## 3. Bot size on screen

`Arena/ui/camera_rig.gd`, constants and their reasons only. G4's tracking design
(`docs/wave-g-g4-notes.md`) is untouched: the aim is still the player plus a capped lead,
the leash is still exact and applied to the eased aim, the endgame reveal is still mixed
over the tracking pose, and yaw, pitch, the manual orbit and the 3 s ease back are all
unchanged.

| constant | was | now | why |
|---|---|---|---|
| `PLAYER_MIN_FRACTION` | 0.10 | **0.16** | the lever G4's own notes named |
| `SUBJECT_MARGIN_BOTS` | 1.0 | **0.20** | a whole bot length of empty floor on each side was most of the frame |
| `PLAYER_LEASH_LIMIT` | 0.25 | **0.21** | forced: the frame is 3.61 m tall at the new hold, not 5.78, so the 0.25 m chassis went from 4.3 % of it to 6.9 % |
| `DEFAULT_ZOOM` | 0.6 | **0.30** | 0.6 of the arena fit is 17.2 m; the pre-spawn frame now opens near the fight's own framing |
| `NEAR_BOT_FRACTION` | 0.30 | **0.30**, unchanged | see below |
| `TRACK_PAIR_RANGE_M` | 4.0 | **4.0**, unchanged | brief v4 §5's number, and `_track_foe` still uses it |

### Measured, headless, 1206 x 556 (iPhone 17 landscape)

| separation | distance before | distance now | player's height on screen before | now |
|---|---|---|---|---|
| 0.9 m (in contact) | — | **5.31 m** | — | **25.0 %** |
| 1.2 m | — | 5.70 m | — | 23.0 % |
| 1.5 m | 9.88 m | **6.10 m** | 11.7 % | **21.3 %** |
| 2.0 m | 10.54 m | 6.75 m | 11.0 % | 18.9 % |
| 2.4 m and beyond (holding) | 11.60 m | **7.25 m** | **10.2 %** | **17.1 %** |

So: **19 to 25 % through an exchange, and never below 17.1 %.** The brief asked for 18 to
22 % and never below 16.

| | before | now |
|---|---|---|
| Worst the player sat from frame centre, driving the brief's 3 m square at 2.5 m/s for 584 frames | 16.2 % | **21.6 %** (the brief allows 30) |
| Smallest the player ever projected over that run | 10.2 % | **17.0 %** |
| Lead carried, worst case | 1.200 m (the cap) | 1.200 m, unchanged |
| Endgame reveal | 11.6 m out to 28.7 m | **7.3 m out to 28.7 m**, biggest single frame 0.892 m = 4 % of the move |
| Pre-spawn pose | 17.2 m | 8.61 m |

### `NEAR_BOT_FRACTION` was not moved, and the measurement is why

It is the *closest* the auto framing may go, and it is **not the binding constraint and
never was**. Two machines in contact (0.9 m centre to centre) ask for 5.31 m; this clamp
bites at 3.87 m. That is 1.44 m of slack. Raising it would change no frame the player will
ever see and would only loosen a live guard in `camera_track_test` and `ui_test`, both of
which assert the framing never goes past it. It is the next lever after
`SUBJECT_MARGIN_BOTS` if a point blank grapple ever needs to frame tighter than 30 %, and
that is the whole of what is left to say about it.

### The one thing that got worse, stated plainly

**Past about 2.6 m of separation an opponent that is straight up or down the camera's own
ground axis can now reach the edge of the frame**, where at 11.60 m it did not. Measured on
every bearing at 5-degree steps:

| separation | worst opponent offset from frame centre (0.5 is the edge) |
|---|---|
| 0.9 m | 0.225 |
| 1.5 m | 0.275 |
| 2.0 m | 0.327 |
| 2.6 m | 0.489 |
| 2.8 m | 0.509 — out |
| 4.0 m | 0.835 |

**This cannot be had both ways at `CAM_FOV` 28.** Keeping a 0.9 m opponent wholly framed at
4 m of separation needs 8.4 m of distance, and at 8.4 m the player is 13.8 % of the frame —
below the 16 % floor the owner's complaint asks for. The two rules are in direct conflict
and the player's size wins, because that is what he reported. `is_player_floored()` is true
in exactly this case and `fight.gd`'s off screen arrow is already drawn for it; the arrow
now does its job from 2.6 m rather than from 4 m.

It is the camera PITCH that costs this, not the distance: at 50 degrees a machine is
foreshortened to 0.64 of its height, so the camera has to come in close to make it read, and
the ground axis is compressed into the short side of a 2.17:1 frame. If the owner wants both
the size and the opponent, the lever is `FightTypes.CAM_PITCH_DEG` — at pitch 40 the same
16 % is reached at 8.64 m, which frames a 4 m opponent — and that is a look change, not a
constant, so it belongs to whoever owns the art direction and not to this pass.

---

## 4. Verification

`sh scripts/test-arena.sh render_test.gd camera_track_test.gd stage_camera_test.gd
texel_density_test.gd` — green.

**Full suite: 27 of 28 files green.** The one red is `ai_physics_test.gd` (2 of 30 checks,
"1 unpushed hazard entries in yard" in the scrapyard and regional arenas), which is hazard
shove behaviour in another agent's files and cannot be reached from anything here: every
file this pass touched is presentation, and `determinism_test` passed 42 of 42 in the same
run, which is the check that proves the simulation is bit identical to what it was. An
earlier run during the same window had four reds (`rules_test`, `ai_test`, `fx_test`,
`builds_test`); all four were other agents mid-edit and all four pass now.

| file | checks | note |
|---|---|---|
| `render_test.gd` | 104 → **114** | new `_test_sharpness()`: MSAA, screen space AA, anisotropy, mipmap filter and bias, `scaling_3d` mode and scale, `import_etc2_astc`, and the oversample probe against a SubViewport posed like the phone's root window |
| `camera_track_test.gd` | 30 → **34** | new `_test_exchange_size()`: the player's height at 0.9 / 1.2 / 1.5 / 2.0 m, and the separation out to which the opponent is wholly in frame on EVERY bearing |
| `texel_density_test.gd` | **new, 20** | every `.glb`, 145 machine surfaces, the band, the close view, and the import path |
| `stage_camera_test.gd` | 14 | unchanged and green |
| `ui_test.gd` | 298 | unchanged and green — its "at 2 m the pair still fits" is the tightest constraint on `PLAYER_MIN_FRACTION`, and it holds with 0.50 m of slack (a 6.75 m fit against a 7.25 m ceiling) |

### A headless capture is not possible, and here is the proof

`QaShots` (`Arena/qa/shots.gd`) saves `vp.get_texture().get_image()`. Probed directly on a
`SubViewport` with `render_target_update_mode = UPDATE_ALWAYS` under `--headless`:

```
texture = <ViewportTexture#...>          # the texture object exists
ERROR: Parameter "t" is null.            # the dummy rasterizer has no render target behind it
image = <Object#null>
```

So the shots path needs a real driver and there are no frames from this pass. Every number
above is geometry, arithmetic or a file's contents, which is what a headless run can prove.
What it cannot say is whether 19 to 25 % of the frame FEELS right in the hand, whether
−0.35 of mipmap bias shimmers on the floor plate in motion, or whether the ASTC albedos are
visibly better than the ETC2 ones on an OLED. Those are the phone's to answer.

### Pack size

`Roboteer/Resources/arena.pck`, re-exported at the end of this pass: **35 694 924 bytes,
34.0 MB**, against a 60 MB budget. It was 29 787 416 (28.4 MB) when this pass started, but
that whole 5.6 MB delta is NOT this agent's: V1's UI assets, V3 and F3 all landed in the
same window. So the cost was measured directly instead, on the imported `.ctex` files, which
attributes it exactly:

| | bytes |
|---|---|
| the 24 maps as ETC2 (before) | 7 650 192 |
| the same 24 maps as ASTC 4x4 (after) | 12 502 880 |
| **this agent's entire pack cost** | **+4 852 688 = +4.63 MB** |

Per set, the albedo is the bulk of it: a 1024² goes 699 116 → 1 398 180, a 512² 174 828 →
349 604. Two maps cost **nothing at all** — `scratch_decal_albedo` and `rust_spots_albedo`
are RGBA, and ETC2 RGBA8 and ASTC 4x4 are both 8 bits per pixel, so those two got the better
codec for free.

Everything else in this pass cost zero bytes. No texture was regenerated, resized or added;
the `.png` files on disk are byte for byte what G2 shipped, and the texel density fix is a
per surface `uv1_scale` computed at bind time.

---

## What the owner should see

- His machine is between a fifth and a quarter of the screen height while he is fighting,
  where it was a tenth. The camera sits 6.1 m back in an exchange instead of 9.9, and never
  further than 7.25 m instead of 11.6.
- The body of the machine has a surface now. The livery panels carry the moulded grain, the
  normal and the AO instead of being flat paint, and the chassis shows a material at the
  right scale instead of one tile blown up across the whole hull.
- The house bots read the way the weapons on them do, rather than a step softer.
- Metal grain and scratches survive the trip to the phone: ASTC instead of ETC2 on
  everything a machine wears, 8x anisotropic on the floor, a third of a mip of sharpening.
- The opponent goes off the edge of the frame sooner when it runs away — from about 2.6 m
  instead of 4 m — and the HUD arrow points at it.

## Owed

- **A device look.** Nothing here has been seen. The three things most worth his eye: the
  mipmap bias in motion (shimmer on the floor plate), the livery's new grain at a livery he
  actually uses, and whether the opponent leaving the frame at 2.6 m is annoying.
- **`window/stretch/mode = "disabled"`**, which is 15 % of the phone's pixels and belongs to
  whoever owns `hud.gd` and `controls.gd`. Everything needed to make the call is in §1
  above; `GraphicsQuality.describe()["oversample"]` reads 1.0000 when it is done.
- **A chassis re-unwrap** in `Tools/blender/**` (G3). The runtime scale correction is a
  patch over an unwrap that is eight times coarser than the rest of the kit.
- **`anvil_hull` and `cinder_hull`** if a house bot is ever shown large.
- **A frame rate on the phone.** Still none, which is why supersampling was left off and why
  `docs/graphics-render-notes.md`'s performance list is still theory.
