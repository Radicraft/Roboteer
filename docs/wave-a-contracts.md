# Wave A contracts

Shared agreements between the wave A leads. Each lead owns its own section; to change
someone else's section, say so in your own section and let them fold it in.

## 1. Materials and surface masks (owner: MATERIALS lead)

Status: v2, 2026-09-24 (masks: UV2 bake primary, vertex colour fallback). Built to by
`Arena/assets/materials/shaders/rb_painted.gdshader` and `Arena/bot/part_visuals.gd`. Parts that do not follow it still render (every rule
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

### 1.2 Surface masks

**v2, 2026-09-24 evening: the models lead's baked UV2 mask is the convention**, and the
painted master reads it. It is better than the vertex-colour plan in v1 (a baked texture
does not bleed across long triangles, holds at fight distance and works on the GL tier),
so v1's vertex colours are now only the fallback for parts not yet rebuilt.

**Primary: one baked mask texture per mesh node, on UV2.**

| what | value |
|---|---|
| file | `<part id>[_<node>]_mask.png` next to the part's `.glb` (`_<node>` omitted for the node named `body`) |
| UV | glTF `TEXCOORD_1` (Godot `UV2`), the unscaled non-overlapping unwrap |
| encoding | RGB, linear data (Non-Color), baked by `Tools/blender/rkit.py` `bake_masks` |
| R | **edge**: 0 on flat faces, 1 on a bevel crest (Cycles bevel node, 4 mm radius, creases removed by near AO) |
| G | **AO**: 1 open, 0 fully occluded (16 mm and 80 mm radii mixed) |
| B | **cavity**: 1 in a seam or panel gap, 0 in the open |

How it is used: `PartVisuals.with_mask()` finds the file from the `Model_<id>` root and
the mesh node's name and binds it to that mesh's painted-master material
(`mask_enabled`, `mask_tex`). `livery` and `dark_metal` chip where
`R x wear` exceeds the chip noise (primer ring, then bare steel); grime darkens and
roughens where `max(1 - G, B)` is high. StandardMaterial3D slots (steel, titanium, hdpe,
rubber, polycarbonate) do not read it today.

Import settings for the mask PNGs: `compress/mode=2` (VRAM compressed) and
`mipmaps/generate=true`. As first committed they are Lossless, raw RGBA8 in VRAM
(4 MB per 1024 mask; docs/wave-a-materials-notes.md 4.4). 512 px is plenty for a plate.

**Fallback: vertex colour COLOR_0**, for a part with no mask file. White means clean.

| channel | meaning | 1.0 | 0.0 |
|---|---|---|---|
| R | edge cover, `1 - convexity` | flat or protected | sharpest exposed edge |
| G | occlusion | open | occluded |
| B, A | reserved, export 1.0 | | |

With no mask file the shader also measures curvature from screen derivatives (1.3), so a
bevelled part with no bake still gets light wear on its bevels at close range, and none
at fight distance or on the GL tier.

Blender notes for the fallback: a Float Color attribute (Byte Color is sRGB and gets
linearised by the exporter), `export_vertex_color='ACTIVE'`, bevels of at least 2
segments. `Tools/textures/make_test_board.py` is a worked example.

**Open item for the models lead:** the fitted HDPE plates (`plate_<chassis>_<face>_hdpe`)
are bound with the HDPE armour material on their `steel` slot (`bot.gd`
`_add_panel_visual`), so `paint_test` counts a painted `steel` surface and fails
("steel is left bare, not painted"). Naming that glTF slot `hdpe` in the model (and
binding `{"hdpe": ...}`) fixes the count and says what the surface is.

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
4. UV2 carries the baked mask (1.2) and nothing else. Keep it non-overlapping.

### 1.4 What the materials lead provides back

1. The masters in `Arena/assets/materials/` and their shaders in
   `Arena/assets/materials/shaders/`, bound by slot through `PartVisuals` (no call site
   changes).
2. `Arena/qa/material_board.tscn`: a test board of bevelled panels, a sphere and a
   cylinder built to this contract under a fixed showroom rig; `--board-hero` puts the
   fixture machine under the same rig, with any paint job and livery.
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
| crowd reaction (`big_hit`, `flipped`, `ko`, `endgame`) | the kit WATCHES `AudioMix._swell_at` (read only), which the mixer stamps each time a swell really plays, after its own gap check; so picture and sound fire on the same frame with no edit to `Arena/fx/audio_mix.gd`. OWED to the audio lead: a `crowd_reacted(key, intensity)` signal on AudioMix; when it lands the kit connects to it and drops the watch. `get_tree().call_group("venue_kit", "on_crowd_reaction", key, intensity)` also works for anyone else | crowd cheers or flinches, phone flashes burst, the screen stings |
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

## 4. Hazards and the shared warning layer (owner: ARENA HAZARDS engineer)

Status: v1, 2026-09-24. Built to by `Arena/arena/arena_base.gd` (`hazard_schedule()`),
`Arena/arena/hazard_telegraph.gd`, `Arena/arena/hazard_meshes.gd`. Write-up:
`docs/wave-a-hazards-notes.md`. (Numbered 4 so the combat engineer's shake budget can be §3.)

### 4.1 Who edits what in the arena files

- The hazards engineer owns `arena_base.gd`, the six arena subclasses, the hazard kit,
  arena lights and environment tweaks, floor markings, hazard FX and hazard audio.
- The venue kit lead adds exactly one `VenueKit` child to each `<id>.tscn` (§2.1) and
  nothing else. The hazards engineer does not touch that node. The arenas are built in
  code, so the hazards side never needs to edit a `.tscn` at all.

### 4.2 `hazard_schedule()` (read-only, on every arena)

Returns one Dictionary per hazard: `id`, `kind` (spikes | flame | ram | pit | grinder |
turntable), `group`, `position` (floor centre), `size`, `shape` (rect | disc | ring), `yaw`,
`in_s` (seconds to its next activation, 0 while active, 999 never), `active`, `warn_s`,
`always_on`, `contact`, `sound_at`, `lamps`. It is derived from the hazard tick clock and
never mutates anything; `hazard_warning_test.gd` reads it ten times a tick for 90 s and
proves the timeline is unchanged. Anyone may read it (the venue kit's crowd lean-in, a
screen showing "SPIKES IN 3", the intro camera), never write through it.

### 4.3 `hazard_fx` signal change

The Drop Zone's warning now emits `hazard_fx("pit_warning", on, ZERO)` instead of
`("pit", true)`, and `("pit", true)` fires once, as the leaves START to slide (it used to
fire at the warning and again at full open). Listeners keyed on `"pit"` see one event per
opening, at the right moment. Every other kind is unchanged.

### 4.4 FightFx entry points the telegraph calls (in `Arena/fx/fx.gd`, now combat-owned)

- `on_hazard_warning(kind, position)`: plays the hazard's wind-up (`warn_spikes`,
  `warn_flame`, `warn_ram`, `warn_pit`), once per group, exactly `ArenaBase.WARN_LEAD_S`
  (1.25 s) before it acts.
- `on_hazard_strike(kind, position, near_player)`: camera trauma by kind and a haptic when
  the player's machine is within 1.5 m of the footprint.
- ALL hazard camera motion goes through one function, `FightFx._hazard_shake(strength)`,
  which calls `ImpactShake.add_trauma(strength, "hazard")` when the combat engineer's
  budget API is present and the old `kick()` otherwise. Retune the hazard ceiling in
  `ImpactShake.SOURCE_CEILING["hazard"]`, the per-kind strengths in `FightFx.HAZARD_SHAKE`.

### 4.5 Rules the warning layer keeps

1. `_process` only; no physics body, no collision shape, no shared RNG (the test walks the
   subtree for collision objects). `HazardTelegraph.enabled = false` removes it entirely;
   the Coliseum hashes identically either way.
2. No warning starts later than the AI can perceive the hazard (owner, 2026-09-24).
   `hazard_warning_test.gd` re-derives the AI's longest look from `opponent_ai.gd`
   (`SKILLS[*].danger_s + HAZARD_LEAD_S`, `SPIKE_AVOID_LEAD_S`) and fails if any arena's
   warning window is shorter. Anyone lengthening the AI's lookahead must lengthen
   `ArenaBase.SPIKE_WARN_S` with it.
3. Hazard information never degrades by quality tier: the decal, lamps, light and
   wind-up are identical on every tier.
