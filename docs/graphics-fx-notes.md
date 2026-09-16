# Graphics pass: effects (agent G4)

What changed in `Arena/fx/**` for the PS4-class bar in `docs/graphics-bar.md`, what it costs,
what every emissive value is, and the two hooks other agents need.

Everything here is still **presentation**. It runs on `FightFx`'s clock, it never touches physics
state, and deleting the whole FX subtree still produces the same result JSON. Agent B's Stage 3
contract (`docs/stage3-fx-notes.md`) is intact: the pool, the scatter delay, the magnet constants,
the collect ramp, the ledger, the haptic rate cap and the whole public API are **unchanged**, and
the 32 checks that measured them still measure the same numbers. This was a visual upgrade.

---

## Files

| file | status | what |
|---|---|---|
| `Arena/fx/fx_materials.gd` | **new** | `FxMaterials`. Every FX material and every emission value, in one place. |
| `Arena/fx/flash_pool.gd` | **new** | `FxFlashPool`. Pooled additive billboard quads that pop and fade. |
| `Arena/fx/debris_chips.gd` | **new** | `DebrisChips`. 32 grey shrapnel chips, MultiMesh, one analytic bounce. |
| `Arena/fx/flame_cone.gd` | **new** | `FlameCone`. The flamethrower's fire, built ahead of the W2 weapon. |
| `Arena/fx/impact_shake.gd` | **new** | `ImpactShake`. Camera kick source; the rig reads it, see below. |
| `Arena/fx/light_pool.gd` | **new** | `FxLightPool`. 4 shadowless omnis, 0.15 s, thrown by severe hits. |
| `Arena/fx/textures/` | **new** | four authored billboards plus `make_fx_textures.py` that draws them. |
| `Arena/fx/bolt_shower.gd` | changed | G3's hex nut mesh, gold emissive metal, two axis tumble, streak, collect flash. |
| `Arena/fx/impact_particles.gd` | changed | particle trails, detach core burst, soft dust, chips, spike tip flash. |
| `Arena/fx/fx.gd` | changed | builds and steps the shake, routes a detach to `burst_detach`. |
| `Arena/fx/collect_audio.gd`, `haptics.gd`, `fx.tscn` | untouched | |
| `Arena/tests/fx_test.gd` | changed | 32 checks kept verbatim, 40 added. 72 checks, 0 failures. |

---

> ## SUPERSEDED IN PART BY WAVE F — read `docs/wave-f-f3-notes.md` first
>
> Agent F3 replaced the uniform gold hex nut with a **mix of torn metal** (bent plate, torn
> shard, bolt with washer, wheel nut, snapped bracket, spring, wire tangle, wheel silhouette),
> after the owner played the wave G build and said "the scrap won doesn't look like scrap".
> §1 below still describes the sizing lesson, the streak and the collect flash correctly, and
> all three survive unchanged. What is **no longer true** in §1:
>
> * the mesh is not `debris_bolt.glb` any more. Every shape is a hand built `ArrayMesh` in
>   `Arena/fx/scrap_pieces.gd`; `BoltShower` loads no glb at all (`_mesh_from_glb` stays only
>   because `DebrisChips` still uses it for G3's `spark_chip.glb`).
> * the material is not `FxMaterials.bolt_metal()` any more. It is one small `ShaderMaterial`
>   in `scrap_pieces.gd` that takes albedo from the MultiMesh instance colour and
>   heat/metallic/roughness from `INSTANCE_CUSTOM`, because `BaseMaterial3D` has no per
>   instance emission and a cooling hot edge needs one. `bolt_metal()` is now unused but kept
>   in `FxMaterials` for reference.
> * `BoltShower` no longer draws anything itself: its own `multimesh` is null and the pieces
>   are drawn by eight `ScrapPieces` banks that share the one 120 slot pool.
> * the gold is now a **rim**, not the whole object: pieces are dark steel / milky
>   polycarbonate / black HDPE with a gold hot edge that cools over 0.6 s and re-lights to an
>   ember under the magnet. `BOLT_EMISSION` still sets its energy, so the glow contract and
>   the `fx_test` check that guards it are unchanged.
> * §8's budget table is superseded by `docs/wave-f-f3-notes.md` §7 (measured before and
>   after: 2 924 → 4 964 worst case triangles, 5 → 16 `MultiMeshInstance3D`, no measurable
>   change in CPU step cost).

## 1. Bolts

**The mesh is now G3's.** `res://assets/parts/fx/debris_bolt.glb`, 20 triangles, a real hex nut at
19.05 mm across the flats. `BoltShower` derives the scale from the mesh AABB rather than hard coding
it (`across_corners = across_flats / cos 30`, measured x4.724) so it survives G3 re-exporting the
part at a different size.

**Two sizes, and the distinction matters.** `BOLT_SIZE` (50 mm) is the *physical* size: it sets the
height a bolt rests at on the floor and therefore feeds the ballistics agent B measured, so it is
frozen. `BOLT_VISUAL_SIZE` (**90 mm**) is the *drawn* size and nothing else. A real 50 mm nut is
three pixels at the fight framing on a 6.9 inch phone, which is exactly what the first desktop
frames showed (§10). 90 mm is not a real bolt and does not pretend to be; it is the size at which
"bright gold, small and spinning" survives the camera distance the brief asks for. `fx_test.gd`
asserts both, so nobody can fix readability by moving the number that moves the timings. The Stage 3 procedural nut is kept as a fallback: a missing import degrades to
the old look with a warning rather than to an empty MultiMesh.

**Material** (`FxMaterials.bolt_metal`): albedo `FightTypes.BOLT_GOLD` (`#f2c14e`), metallic 1.0,
metallic specular 0.65, roughness 0.3, **emission gold at energy 5**, per-pixel shading, two sided,
shadows off. Lit *and* emissive on purpose: lit so the hex facets catch the arena key light and the
nut reads as a machined object rather than a sprite, emissive so it still wins against a bright
steel floor. This is the one material in the file that must never lose its saturation, because the
art direction's whole readability rule (`docs/stage2-art-direction.md`) is that gold is the only
strong warm in a frame that is otherwise four fifths cold grey blue.

**Two axis tumble.** A single axis spin reads as a coin flipping in place. There are now two random
axes with independent rates (9 to 20 rad/s and 4 to 11 rad/s), composed as `Basis(a1, t1) *
Basis(a2, t2)`, so the facets flash at irregular intervals. The launch, delay, bounce and magnet
maths are byte for byte what they were.

**The streak.** A second MultiMesh of stretched quads on `trail_streak.png`, additive, gold, energy 3.

- **Cap: 120 segments, and it is structural, not a budget.** Trail slot `i` belongs to bolt slot `i`,
  so there can never be more segments than there are bolts. `fx_test.gd` asserts
  `trail_capacity() <= 120` and `== FightTypes.BOLT_POOL`.
- A segment is a quad from the bolt back along its velocity, `min(speed x TRAIL_LENGTH_S, 0.75 m)`
  long and **50 mm** wide, in gold pulled a third of the way to white at energy 5 so the head has a
  hot core. `TRAIL_LENGTH_S` (0.24 s) is deliberately a *separate scalar* from the 120 ms fade, so
  the streak could be doubled in length without touching the locked fade time. Alpha targets `(speed - 2.2) / (8.0 - 2.2)` clamped, so a bolt bouncing on the floor
  draws nothing and a bolt under the magnet draws a full streak: the stream is the part that streaks.
- **It fades over 120 ms** in both directions. Alpha moves toward its target at `delta / 0.12` per
  second, and a retired bolt's segment is deliberately *not* parked: it keeps its last transform and
  fades, which leaves a 120 ms wake at the point of collection instead of a hole.
- The quad is turned to face the camera in code (one `get_viewport().get_camera_3d()` lookup per
  frame, one cross product per bolt). **`BILLBOARD_FIXED_Y` cannot do this**: Godot pins that to
  *world* +Y, not to the instance's own Y, so a horizontal streak would be edge on and invisible.
  That trap cost an hour; it is written down here so it costs nobody else one.

**Collect flash.** `FxFlashPool`, 8 quads, `spark_glow.png`, additive gold at energy 6, **480 mm**
growing x2.4 over 140 ms with a `(1-t)^2.2` alpha. Fired where the bolt arrives, scaled by the
bolt's own scale so a fat pool-short bolt flashes bigger. The pool recycles its oldest slot when
full rather than dropping the newest event: at 140 ms a stolen flash is never the wrong call.

## 2. Sparks, dust, chips

**Sparks** are `GPUParticles3D` with **Godot 4 particle trails**: **48 particles**, `trail_enabled`,
`trail_lifetime` 0.12 s, a `RibbonTrailMesh` draw pass (`SHAPE_CROSS`, size 34 mm, 6 sections of
50 mm, tapered to nothing by a `Curve`) and a material with `use_particle_trails`. Lifetime
**0.25 s**, orange-white ramp (white hot core, orange body, gone), gravity -11 m/s², **collision
disabled**, additive, **energy 5**. Severity still scales `amount_ratio`, initial velocity and particle scale through the
process material, never the node scale.

- `SHAPE_CROSS` rather than `SHAPE_FLAT` because the fight camera is fixed at yaw 45 / pitch 50 and a
  flat ribbon is invisible edge on, which half the sparks would be. Eight more triangles per trail.
- `use_particle_trails` **must not** be set on a material that is not drawn by a trail mesh, or the
  draw breaks. It lives in exactly one function, `_spark_trail_material()`.
- **Particle trails need a RenderingDevice.** The GL Compatibility tier has none and silently draws
  nothing for a ribbon draw pass, so that tier (and headless) falls back to the Stage 3 streak quad.
  `FightParticles.trails_enabled()` reports which path is live.

**Severe hits throw light.** Above severity 0.45 a hit also pops one of four `FxLightPool` omnis:
energy 5.5, range 1.6 m, **0.15 s**, shadows off, falling off as `(1-t)^1.8`. One frame of the floor
and both bots lighting up is most of the difference between an impact that reads as an event and one
that reads as a decal. Four is the cap precisely so a pile-up cannot quietly become a lighting cost;
a detach pops a brighter, wider one.

**Detach** (`burst_detach`) is a bigger moment than a hit: a hot white core flash (`FxFlashPool`,
6 quads, energy 7, 550 mm, 180 ms, scaled 0.8 to 1.7 by severity), the grey dust, 3 to 9 chips and
the light pop.

**Dust** moved onto the authored `dust_soft.png` billboard with a little angular velocity, because a
hard edged grey quad is the most obvious "particle system" tell there is. **20 particles**, quad
**300 mm**, 0.85 s, peak alpha 0.8, mix blended, never additive: dust must occlude, not glow.
Collision disabled.

**Chips** (`DebrisChips`): pool **32**, lifetime **1.2 s**, G3's `spark_chip.glb` (8 triangles)
scaled so its long axis is **85 mm** (still comfortably larger than a bolt, which is the side of the
readability rule that matters), the bolts' exact closed form single floor bounce (restitution 0.34,
friction 0.62), tumbling until they settle, shrinking away over the last 0.3 s.

> **Readability rule, brief §6, enforced mechanically.** Chips are lit, matte, `metallic 0.35`,
> `roughness 0.72`, grey `#6b7078`, and **never emissive**. `fx_test.gd` asserts
> `not emission_enabled` and `albedo_color.s < 0.25` against the bolt's 0.678. A player must never
> drive across the arena for a chip.

## 3. Flame (`FlameCone`, for the W2 flamethrower)

```gdscript
var flame := FlameCone.new()
muzzle_socket.add_child(flame)   # fire goes along local +X, the bot convention
flame.set_length(1.6)            # metres of reach
flame.set_active(true)           # hold to burn
```

Three layers, because one particle system alone reads as sparks:

1. **The cone.** 48 particles, 0.45 s, 13° spread, additive on `flame_soft.png`, a scale curve that
   opens 0.35 to 1.35 along the life (that curve *is* the cone), a ramp from white hot through
   `#ff7019` to a dull red, a separate alpha curve so the colour stays saturated while the particle
   dies, gravity **+1.1 m/s²** (hot gas rises and the tip curls), turbulence for the curl, collision
   off, energy 3.2.
2. **The haze.** A screen-space distortion needs a screen texture read per pixel, which is exactly
   the full screen bandwidth a phone does not have going spare, so the haze is a broad faint
   **additive glow** that breathes in scale and alpha rather than a refraction. It is the cheapest
   lie in the file and it is deliberate.
3. **The light.** One `OmniLight3D`, orange, energy 2.6, range `length x 1.5`, **shadows off** (a
   flamethrower that costs a shadow pass every frame would be the most expensive thing in `Arena/fx`;
   the fire is a fill light). Energy flickers on two incommensurate sines, 11 Hz and 4.3 Hz at 28 %
   depth, with a random per-instance phase, so it never visibly repeats.

`set_length` clamps to 0.2 to 6.0 m and drives everything off that one number: particle speed (so a
particle just reaches the tip inside its lifetime), cone width, emitter radius, where the haze sits,
and how far the light throws. `set_active(false)` stops emission but lets particles already in the
air finish, so releasing the trigger does not delete the fire.

## 4. Camera impact feel — **hook for C and R**

`ImpactShake` is a *source*, not an effect. `FightFx` builds one, steps it on the presentation clock
and kicks it from `on_damage_event` (`strength = 0.10 + 0.80 x severity`). It accumulates trauma,
decays it at 2.6 per second, and offers `offset()`.

**Nothing in `Arena/ui` has been touched.** When C wants it, the whole change is:

```gdscript
# once, in CameraRig._ready()
_shake = get_tree().get_first_node_in_group(ImpactShake.GROUP)

# in CameraRig._process, at the three places that currently end with
#   _camera.transform = Transform3D.IDENTITY
var kick := Vector3.ZERO
if _shake != null and is_instance_valid(_shake):
    kick = _shake.offset()
_camera.transform = Transform3D(Basis(), kick)
```

The group lookup is the point: the rig never has to know the FX tree exists, and with the FX subtree
deleted the lookup returns null and the camera behaves exactly as it does today.

The offset is in **camera local space** (x right, y up, z toward the viewer), so it works at any
yaw, pitch and zoom, and because it goes on the `Camera3D` child rather than on the rig it cannot
disturb the rig's own `look_at`. Peak travel is `MAX_OFFSET` = **7 cm** at full trauma, with the z
axis at 35 % of that so it does not read as a zoom wobble. Trauma is clamped to 1.0, so a 30 hit
pile-up cannot shake the camera off the arena. Shake is trauma **squared** (the standard trauma
model): two light hits barely register, one heavy hit is unmistakable, and it tails off smoothly.

## 5. Spike hazard

`on_spikes(risen, position)` is unchanged. On the **rise** only, a warm flash (energy 3.6, 1.5x size)
pops 60 mm above the emitter so it reads as the tips rather than the floor, then the existing
continuous 12 particle fizz keeps the hazard live. Falling spikes flash nothing.

## 6. Emission values, in one table

| what | nominal energy | how it is applied |
|---|---|---|
| bolt metal | 5.0 | `emission_energy_multiplier` on a lit material |
| bolt streak | 5.0 | HDR albedo on an unshaded additive material |
| collect flash | 6.0 | HDR albedo |
| impact sparks | 5.0 | HDR albedo |
| detach core | 7.0 | HDR albedo |
| impact light pop | 5.5 | `light_energy`, 0.15 s |
| flame cone | 3.2 | HDR albedo |
| flame light | 2.6 | `light_energy` |
| spike tip flash | 4.5 | HDR albedo, via the core pool's tint |

All of them come from `FxMaterials`, so retuning is one file.

**The glow contract, and the test that holds it.** `Arena/render/arena_env.tres` does **not** set
`glow_hdr_threshold`, so it is Godot's default **1.0**, and `tonemap_exposure` is applied before the
glow pass. A bolt therefore blooms only if
`BOLT_GOLD.get_luminance() x BOLT_EMISSION x tonemap_exposure > glow_hdr_threshold`, which at the
time of writing is `0.765 x 5.0 x 0.70 = 2.68` against 1.00. G1 owns one side of that sum and this
file owns the other, and neither agent sees the other's change, so **`fx_test.gd` loads the live
`.tres` and asserts it**. If G1 raises the threshold or drops the exposure, the test says so instead
of the bolts quietly going matte.

**Unshaded materials ignore `emission` entirely** — the shader writes `ALBEDO` straight out — so
brightness for the additive layers lives in `albedo_color` as values above 1.0, with alpha left at
1.0 (additive blending is `SRC_ALPHA, ONE`, so an alpha above 1 would double the brightness a second
time). `FxMaterials.hdr()` does that conversion.

**The compatibility tier.** `FxMaterials.energy()` caps the multiplier at `LDR_ENERGY` = 1.45 when
there is no `RenderingDevice`, because GL Compatibility has no HDR buffer and no glow: everything
above 1.0 clips flat, an orange spark clips to a white smear, and the "gold is the only saturated
warm" rule breaks without anyone having changed the bolt art. The test exercises this path (headless
has no RenderingDevice either) and asserts the tamed value.

## 7. Textures

`Arena/fx/textures/`, drawn by `python3 Arena/fx/textures/make_fx_textures.py` (deterministic: fixed
seed, pure maths, byte identical on a re-run so Godot does not re-import for nothing).

| file | size | what |
|---|---|---|
| `flame_soft.png` | 128 | radial gradient, dense to 20 % then smoothstep to the rim |
| `spark_glow.png` | 64 | hot core with an inverse square halo |
| `dust_soft.png` | 128 | soft puff, rim broken by two octaves of wrapped value noise |
| `trail_streak.png` | 64x128 | head at v=0 to tail at v=1, soft round section across |

All four are **white with an alpha shape**; the materials tint them, so nothing in the sprites bakes
a hue the art direction might later move. The generator lives next to its output inside `Arena/fx/`
rather than in `Tools/` because `Arena/fx/**` is this agent's scope; Godot has no importer for `.py`
so it is inert in the project, and it is 7 KB.

**Mipmaps had to be forced on**, the same trap `docs/graphics-textures-notes.md` records for the
material textures: Godot imports a PNG with `mipmaps/generate=false` and only flips it when the
*editor* first notices the texture on a 3D material (`detect_3d/compress_to`), and this project
imports headless, so that never fires. An FX billboard without mipmaps sparkles and crawls the
moment the camera moves. `make_fx_textures.py` patches the four `.import` files after the import
step, and `fx_test.gd` reads the `.import` files back and fails if any of them says `false`.

```
python3 Arena/fx/textures/make_fx_textures.py                        # draw them
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
python3 Arena/fx/textures/make_fx_textures.py                        # force mipmaps on the new .import files
```

## 8. Budget

Worst case on screen, all at once:

| thing | instances | draw data |
|---|---|---|
| bolts | 120 | one MultiMesh, 20 tris each, 2 400 tris |
| bolt streaks | 120 (hard cap) | one MultiMesh, 2 tris each, additive |
| collect flashes | 8 | one MultiMesh, 2 tris each |
| spark emitters | 8 x 48 particles | ribbon trails, 6 sections x cross, or streak quads on Compatibility |
| dust emitters | 4 x 20 particles | alpha blended billboards |
| spike fizz | 12 particles | continuous, one emitter |
| chips | 32 | one MultiMesh, 8 tris each, 256 tris |
| detach cores | 6 | one MultiMesh, 2 tris each |
| impact lights | 4 | shadowless omnis, 0.15 s each |
| flame (W2) | 48 particles + 1 quad + 1 unshadowed omni | per flamethrower on the field |

Five extra draw calls over Stage 3 (streaks, chips, two flash pools, and the flame when it exists),
all of them usually empty, all of them shadow-casting off and GI disabled. Nothing in here allocates
during a fight: every pool is built in `_ready` and recycled.

## 9. Known weaknesses

1. **One round of visual verification, on the desktop only.** See §10. The second round is owed,
   and the phone is still owed after that.
2. **Headless cannot simulate a particle.** `GPUParticles3D` never runs without a renderer, so the
   sparks, the dust, the spike fizz and the flame cone are constructed and configured but never
   *emit* in the test. The trails path in particular has never executed. The CPU parts (bolts,
   streaks, chips, flashes, shake) are fully covered.
3. **A headless run ends with `1 RID allocations of type DummyShader were leaked at exit`.** This is
   Godot's **dummy** renderer failing to release one `BaseMaterial3D` shader at shutdown, not a leak
   in the game, and it is **not new**: `rules_test.gd` prints the same line at `HEAD`. It is
   unaffected by free order, by extra frames and by nulling the materials first. The suite still
   passes (exit 0, and `scripts/test-arena.sh` does not match on it). Do not spend an afternoon on
   it, as this agent nearly did.
4. **The streak is one segment per bolt, not a history ribbon.** It represents the last 120 ms of
   travel as a straight quad, so a bolt on a tight curve draws a chord rather than an arc. At 120 ms
   and the magnet's alignment damping the curvature is small; if it reads badly, the fix is a real
   trail history, which costs 4 to 8 segments per bolt and would blow the 120 cap.
5. **`ImpactShake` is wired but nothing reads it yet.** `FightFx` kicks it on every damage event; the
   camera rig change in §4 is owed to C. Until then it decays harmlessly.
6. **`FlameCone` has no caller.** It is built, tested and parked for W2.
7. **The chips do not collide with anything.** They bounce once off `y = 0` analytically, like the
   bolts, so a chip can settle inside a wall or on top of a bot. At 45 mm and 1.2 s this has never
   been visible in any still, but it is a real limitation of doing this in the presentation layer.

---

## 10. What the first desktop frames changed

Forward+ desktop run, `--roboteer-player-ai=charge --roboteer-zoom=0.45`, frames at 0.1 / 0.45 /
0.9 s after each scrap award. The showers fired at the right moments (throws, wall slams) and the
ledger and timing were visibly right, so the Stage 3 contract held. Everything else was **too
small**.

Magnified 3x, the streaks, the hex nuts, the ribbons and the flashes were all present and correctly
shaped — the trail orientation maths, the ribbon cross section and the collect flash all did exactly
what they were built to do. At 1x, on a 1206 px frame that shows about the same pixels per bolt as a
6.9 inch phone at this framing, a bolt was a three pixel gold speck, the streaks were sub-pixel wide,
the flash was invisible and the spark bursts were short faint dashes.

**The lesson worth keeping: at this framing, size beats brightness.** A three pixel source barely
blooms no matter how hot it is, because `glow_intensity` 0.55 with the blur weighted onto the high
mips spreads what little energy it has over an area where it disappears. Roughly two thirds of the
fix below is geometry and one third is energy.

| | before | after |
|---|---|---|
| drawn bolt | 50 mm | **90 mm** (`BOLT_VISUAL_SIZE`, physical size untouched) |
| bolt emission | 3 | **5** |
| streak length | `speed x 0.12 s`, max 0.55 m | `speed x 0.24 s`, max **0.75 m** |
| streak width / energy / colour | 30 mm, 3, pure gold | **50 mm**, **5**, gold lerped 35 % to white |
| collect flash | 160 mm, energy 4.5 | **480 mm**, energy **6** |
| spark particles / ribbon | 24, size 16 mm, 4 x 30 mm | **48**, size **34 mm**, **6 x 50 mm** |
| spark trail lifetime | 0.08 s | **0.12 s** |
| spark energy | 4 | **5** |
| severe hit light | none | **`FxLightPool`, 4 omnis, 0.15 s, energy 5.5, range 1.6 m** |
| dust | 14 particles, 160 mm quad, peak alpha 0.5 | **20**, **300 mm**, peak alpha **0.8** |
| detach core flash | 200 mm, energy 6 | **550 mm**, energy **7** |
| chip length | 45 mm | **85 mm** |
| bolt spin | 7 to 16 and 3 to 9 rad/s | **9 to 20** and **4 to 11** rad/s |
| LDR fallback energy | 1.25 | **1.45** |

**Unchanged, and checked:** every pool cap (120 bolts, 120 streak segments, 32 chips, 8 + 6 flashes),
the scatter delay, the magnet, the ledger, the collect ramp, the haptic cap, and `BOLT_SIZE` itself
so the ballistics still land where agent B measured them.

### The second pass

The bolts, the streaks, the collect flashes and the detach flash all read at 1x. One correction: at
`TRAIL_MAX_LEN` 1.10 m and `TRAIL_WIDTH` 65 mm the streaks read as **tracer fire** rather than as a
stream of nuts — long, thin, and bright enough that the eye followed the line instead of the bolt on
the end of it. Wrong genre. Cut to **0.75 m and 50 mm**, which keeps the stream and gives the bolt
itself back the eye. Nothing else moved; the detach core flash at 550 mm did not wash out.

**Owed:** the phone, at 60 fps, which is the only gate that counts.
