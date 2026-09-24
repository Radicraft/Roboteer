# Wave A contracts

Shared agreements between the wave A leads. Each lead owns its own section; to change
someone else's section, say so in your own section and let them fold it in.

## 1. Materials and surface masks (owner: MATERIALS lead)

Status: v1, 2026-09-24. Built to by `Arena/assets/materials/shaders/rb_painted.gdshader`
and `Arena/bot/part_visuals.gd`. Parts that do not follow it still render (every rule
below degrades to "clean, no wear"), so nothing has to land at once.

### 1.1 Slot names (glTF material names)

A part names its materials by slot, exactly as today (`PartVisuals` matches by
`resource_name`, never by surface index). Unchanged slots:

| slot | what it is | master |
|---|---|---|
| `livery` | painted panel, takes the player's colour and the paint job | painted master (clearcoat, edge wear) |
| `hdpe` | moulded plastic, takes the livery tint | StandardMaterial3D |
| `dark_metal` | black powder coat on frames, brackets, motor cans | painted master, powder coat preset (wears to steel) |
| `steel` | bare brushed steel | StandardMaterial3D, anisotropic |
| `titanium` | bare titanium | StandardMaterial3D, light anisotropy |
| `polycarbonate` | clear or smoked shell | StandardMaterial3D, alpha depth pre-pass |
| `rubber` | tyres, bump stops | StandardMaterial3D |
| `copper` | bus bars, windings | derived from steel |
| `core_glow` | the power core, the only thing that blooms | emissive |

New slot, optional:

| slot | what it is |
|---|---|
| `status_light` | small indicator lenses (arming light, LED strip). Emissive, below the glow threshold at rest; `PartAnim` or gameplay may pulse it. Use sparingly; `core_glow` stays the one hero emitter. |

### 1.2 Vertex colour masks (COLOR_0)

One colour attribute per mesh, exported as glTF `COLOR_0`. **White means clean**, so a
part with no colour attribute (Godot supplies white) renders with no wear and no grime,
which is correct for every part that has not been baked yet.

| channel | meaning | 1.0 | 0.0 | used by |
|---|---|---|---|---|
| R | **edge cover**: `1 - convexity` | flat, concave, or an edge that is protected | the sharpest, most exposed convex edge | painted master: paint chips through to primer then metal |
| G | **occlusion** (AO / cavity) | open to the sky | fully occluded crease | painted master: cavity grime (albedo -20 %, roughness +0.15); StandardMaterial3D: not read |
| B | reserved (weld / heat mask, future titanium heat tint) | no weld | at a weld bead | not read yet, export 1.0 |
| A | reserved | | | export 1.0 |

Authoring notes for Blender (`Tools/blender/`):

1. Use a **Float Color** attribute on the Point or Face Corner domain (linear, no sRGB
   curve). A Byte Color attribute is sRGB encoded and the glTF exporter linearises it,
   which moves every mid value (0.5 becomes 0.21).
2. Export with the colour attribute forced on: `export_vertex_color='ACTIVE'` (Blender 4.2
   and later only exports colours a material uses unless told to).
3. R: bake convexity, clamp it, invert. `paint.vertex_color_dirt` (Dirty Vertex Colors)
   with `dirt_angle` about 90 deg is an acceptable first pass once its output is remapped
   so flat reads 1.0; a geometry-nodes edge-angle bake is better. Then **hand paint it
   down** on the edges a machine actually hits (front wedge lip, weapon mount, wheel guard
   tops) and **up** (back to 1.0) on edges that would be protected. The shader does the
   2 to 6 mm edge band by itself from the geometry (1.3); R says WHERE wear is allowed and
   how much.
4. G: Cycles AO bake to vertex colours (Bake type Ambient Occlusion, target Color
   Attribute), distance 0.05 m, then level it so open faces sit at 0.95 to 1.0.
5. Bevel segments: at least 2 on a painted edge, so there are vertices ON the bevel for R
   to live on. With 1 segment the R value bleeds across the whole neighbouring face.

### 1.3 Geometry the shader depends on

1. **Bevels 4 to 8 mm** on major plate edges with **smooth (weighted) normals across the
   bevel**, not a hard edge either side of it. The painted master measures curvature per
   pixel from the normal's screen derivative (`|dN| / |dP|`), which finds a 6 mm bevel as a
   band about 250 rad/m and a flat plate as zero, independent of triangle size. A hard
   edge split gives it nothing to measure.
2. **Tangents exported** (`export_tangents=True`). Brushed steel and titanium are
   anisotropic, and the brush runs along **UV U** (the tangent). Lay the U axis of a steel
   island along the machining direction: lengthwise on a blade or plate, around the axis
   on a turned part (hub, shaft, disc face uses a polar unwrap so U runs round the rim).
3. **UV1 only**, one unwrap per part, texel density as uniform across the kit as you can
   get it. `PartVisuals.density_matched()` rescales every surface to 1600 texels/m, so the
   absolute value does not matter; consistency within one part does.
4. No UV2 is read. If a lightmap or a baked curvature texture is ever wanted, it goes on
   UV2 and this section changes first.

### 1.4 What the materials lead provides back

1. The masters in `Arena/assets/materials/` and their shaders in
   `Arena/assets/materials/shaders/`, bound by slot through `PartVisuals` (no call site
   changes).
2. `Arena/qa/material_board.tscn`: a test board of bevelled panels, a sphere and a
   cylinder built to this contract, lit by the workshop stage, for checking a part's
   masks against a known good one.
3. Decals (warning stripes, invented stencils, bolt grime, scorch) as Decal textures in
   `Arena/assets/textures/decals/`, placed by code, never baked into a part's UVs.

## 2. Venue kit (owner: ARENA KIT / VENUE lead)

Status: v1, 2026-09-24. Built to by `Arena/arena/kit/venue_kit.gd`.

### 2.1 One node per arena scene

Each `Arena/arena/<id>.tscn` gets exactly ONE extra child, added by the kit lead and by
nobody else:

    [ext_resource type="PackedScene" path="res://arena/kit/venue_kit.tscn" id="kit"]
    [node name="VenueKit" parent="." instance=ExtResource("kit")]
    venue = "<id>"

The hazards engineer owns everything else in those files and in the arena scripts
(hazards, telegraphs, lamp bezels, arena lights, floor markings). The kit lead does not
edit `arena_base.gd` or the six subclasses. If the two of us both touch a .tscn, rebase
on the other's commit; the VenueKit node is one self-contained block, so the merge is
trivial.

### 2.2 Rules the kit keeps (and the tests assert)

1. NOTHING under `VenueKit` is a `CollisionObject3D` (no bodies, no areas, no shapes).
   `Arena/tests/venue_kit_test.gd` walks the subtree and fails on any.
2. Nothing under `VenueKit` reads or writes the shared fight RNG, `_physics_process`, or
   any physics state. It runs in `_process` and on the GPU. Its randomness is a private
   `RandomNumberGenerator` seeded from a constant.
3. It READS the parent arena (`arena_size()`, `escalated()`, the `hazard_fx` signal,
   `spike_patch_centre()`); it never calls anything that changes it.
4. Every kit piece degrades by tier (`GraphicsQuality`): high, medium, low. Nothing in the
   kit carries hazard information, so the kit may drop pieces freely on low tiers.
5. Visual layer: kit geometry renders on VisualInstance3D layer 1 like the arena, plus
   layer 11 (`VenueKit.RENDER_LAYER_VENUE`) so a camera (the screen feed, a later intro
   camera) can include or exclude the venue.

### 2.3 Presentation events the kit listens to

| event | source | effect |
|---|---|---|
| crowd reaction (`big_hit`, `flipped`, `ko`, `endgame`) | `AudioMix.crowd_reaction()` calls `get_tree().call_group("venue_kit", "on_crowd_reaction", key, intensity)` after its own gap check, so picture and sound fire together (a two-line addition in `Arena/fx/audio_mix.gd`, owned by the audio lead; the kit lead made it) | crowd cheers or flinches, phone flashes burst |
| hazard | parent arena's existing `hazard_fx(kind, active, position)` | small crowd lean-in |
| endgame | polls `arena.escalated()` in `_process` | pyro burst, crowd to full excitement, floods warm |

### 2.4 Hooks the later intro/camera wave calls

    venue_kit.play_entrance(side: int)   # 0 player gate, 1 opponent gate: light sweep + gate strip chaser + pyro, 3.5 s
    venue_kit.skip_entrance()            # snaps everything to the idle state
    venue_kit.fire_pyro(kind: String)    # "gate", "columns", "sparks", "all"
    venue_kit.set_excitement(v: float)   # 0..1, decays by itself
    venue_kit.intro_camera_marks() -> Array[Transform3D]   # suggested flyover poses per venue

None of them are called by the fight today; `--roboteer-venue-entrance` on the QA capture
scene calls `play_entrance` so the pieces can be judged in isolation.
