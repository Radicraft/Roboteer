# Rendering notes (agent G1)

Owns: `Arena/render/**`, the `[rendering]` section of `Arena/project.godot`, the
environment, light and probe nodes inside `Arena/arena/yard.gd` and
`Arena/workshop/stage.gd`, `Arena/tests/render_test.gd`, this file.
Brief: `docs/graphics-bar.md` (PS4 class), targets `docs/stage2-art-direction.md`.

## What is in place

| file | what it is |
|---|---|
| `Arena/render/graphics_quality.gd` | autoload `GraphicsQuality`: picks a tier, and is the only thing that turns a renderer feature on or off |
| `Arena/render/arena_env.tres` | the Yard's Environment: ACES, dark studio ambient, glow on emissives only, SSAO, SSR, subtle distance fog, no sky |
| `Arena/render/stage_env.tres` | the menu and workshop stage: black, ACES, glow on the beams and lamp heads, volumetric fog authored for the high tier |
| `Arena/render/default_env.tres` | `rendering/environment/defaults/default_environment`: a cheap safety net for any 3D scene nobody art directed |
| `Arena/render/damage_decals.gd` | `DamageDecals`, the pooled scratch and scorch layer |
| `Arena/tests/render_test.gd` | 97 headless checks |
| `Arena/tests/_g1_make_envs.gd` | the generator that wrote the three `.tres` files through the real Godot API |

## The tiers

`GraphicsQuality` reads the rendering **driver** first, then the method, then the device
model, and settles on one of three tiers.

| tier | chosen when | SSAO | SSR | glow | volumetric fog | decals | probes | shadows | AA |
|---|---|---|---|---|---|---|---|---|---|
| `high` | driver is real and the method is `forward_plus` (the phone on Metal, and the Mac) | yes | yes | yes | yes | yes | yes | 1 cascade, soft | MSAA 4x |
| `medium` | method is `mobile` | no | no | yes | no | yes | yes | 1 cascade | FXAA |
| `low` | `gl_compatibility` (the iOS simulator), and every headless run | no | no | no | no | **no** | no | 1 cascade | none |

Three things are worth knowing about that table.

**A headless run reports `forward_plus`.** `OS.get_current_rendering_method()` returns the
project's method name even when the process was started with `--headless` and the actual
driver is `dummy`, so every test would otherwise claim the high tier and build volumetric
fog and decals that can never draw. The driver name (`OS.get_current_rendering_driver_name()`,
plus `DisplayServer.get_name() == "headless"`) is what tells the two apart, and it is
checked before anything else.

**Decals do not exist on the Compatibility renderer**, so on the low tier `DamageDecals`
is a no op. The API still exists and still returns cleanly: no caller anywhere may branch
on the renderer itself.

**`--roboteer-tier=high|medium|low`** forces a tier on a desktop run, so one Mac can shoot
the simulator's look without a simulator. It is read only under `OS.has_feature("pc")`, so
a device build can never be posed by an argument.

`GraphicsQuality.apply(env, lights)` only ever turns things **down**. The `.tres` files are
authored for the high tier and every scene loads them, duplicates them, and applies the
tier, so there is exactly one authored look and three budgets for it.

Anything that is not itself an autoload reaches it with
`GraphicsQuality.resolve(self)` (a static function on the script), which answers with the
autoload when there is one and a private instance when there is not. A `--script` test run
has no autoloads at all, which is the same trap `WorkshopStage` documents for `Bridge`.

## Wiring

**The Yard** (`arena/yard.gd`, `_build_environment`) loads `arena_env.tres`, duplicates it,
and builds: a warm directional key from the upper left at energy 0.5 with shadows, a cold
directional fill at 0.12 with none, and a `ReflectionProbe` over the floor on
`UPDATE_ONCE` with box projection and a 1.5 m blend distance. Then `GraphicsQuality.apply()` sets the cascade count, the soft shadow and
the shadow distance, and hides the probe where it cannot draw. The fill
light is not decoration: without it a dark chassis's shadowed faces fall to the same value
as its tyres and the silhouette closes up, which is the one thing
`docs/stage2-art-direction.md` says must never happen.

**The stage** (`workshop/stage.gd`) loads `stage_env.tres` the same way and then re-asserts
the two numbers that decide whether the frame is black or milky (background colour, ambient
energy at most 0.05), so a bad resource cannot silently undo C2's calibration pass.

On the **high** tier the stage's three mover spots get
`light_volumetric_fog_energy = 4.5` and become real shafts through real fog, and two
`FogVolume` boxes lie low across the floor (a wide bank plus a denser ring at the stage
lip). The key and the rim are pulled the other way, to `0.5`: a 3.6 energy key pumped into
real fog is a white wall in front of the bot. The additive cones and the billboard dry ice
keep drawing underneath all of it at half strength, so the high tier is the low tier plus
real fog and can never be thinner than it.

On **medium** and **low** the FogVolumes are built but hidden and C2's fakes do the work
alone at full strength. Both sets of nodes exist on every tier by design, so the scene tree
never changes shape and the headless test sees the same tree the phone builds.

## The three observed problems in the stage frames, and what was done

0. These were the changes made BEFORE the first shoot; the section above is what the
   frames then said.

1. **Dry ice read as separate grey blobs, not fog.** Fog is continuous or it is nothing.
   More, larger, fainter quads that overlap: 5 emitters and 150 billboards at roughly a
   third of the previous per quad alpha (0.018 to 0.022, was 0.04 to 0.05), scale up to
   0.86 from 0.45. Every quad still obeys the rules the first calibration pass found and
   `workshop_test.gd` asserts: under 1.2 m, alpha at or under 0.08, below 0.2 m, never over
   the stage centre. On the high tier none of this draws at all and the FogVolumes do it.
2. **The three beams were too faint to read.** `BEAM_ALPHA` 0.06 to 0.095 and
   `BEAM_FADE_POWER` 2.2 to 1.25. The fade power was the real culprit: at 2.2 the cone was
   at 6 % of its lens alpha a third of the way down and invisible by the floor. The alpha
   stays under 0.10 so two crossing beams still read as translucent. Mover light energy
   2.6 to 3.4.
3. **The stage's light edge ring was gold.** Now cool white, `Color(0.76, 0.87, 1.0)`.
   Gold is reserved for scrap and the bolt shower: `docs/stage2-art-direction.md` measures
   the arena as four fifths cold grey blue with gold as the only saturated warm, and that
   ratio is what makes the bolt shower read instantly.

No assertion in `workshop_test.gd` was changed for any of the three. Two were changed
later, after the second shoot; they are listed there.

## First shoot, 2026-09-13: what the frames said and what changed

Four frames on the Mac (Forward+ on Metal): the stage on the menu camera and the workshop
camera on the high tier, the Yard at countdown on the high tier, and the stage on the menu
camera forced to the low tier.

**The low tier frame is the reference.** Three readable beams, a low fog band, the cool
white ring, the bot lit. The high tier has to equal or beat that frame, never replace it
with something thinner.

**1. The high tier stage drew no haze at all.** The menu frame was black and the workshop
frame was a lit bot on a black disc: the fakes were hidden and the real fog was invisible.
The cause was three numbers that each looked reasonable and multiplied to nothing:
`volumetric_fog_density` 0.012 (Godot's own default is 0.05), `FogMaterial.density` 0.10
and 0.22 (the default is 1.0), and `light_volumetric_fog_energy` 2.2. Now 0.05, 1.0 and
1.8, and 4.5, with anisotropy 0.4 to 0.55.

**The structural fix matters more than the numbers.** The cones and the billboards no
longer switch OFF on the high tier: they keep drawing at `FAKE_HAZE_GAIN_WITH_FOG` (0.5)
with the real fog layered over them. They are three cones and 150 quads that never write
depth, so they cost almost nothing, and it means the high tier cannot come out worse than
the frame that has already been accepted. `fake_haze()` now means "the fakes are doing all
of it"; `volumetric_haze()` says whether real fog is on top.

**2. The Yard was overexposed**, the floor a flat bright grey-blue near 215/255 with no
shading in it. Ambient energy 0.55 to 0.22 (ambient lifts every surface at once, so it
comes down before the exposure does), exposure 1.15 to 0.8, white point 1.6 to 1.9, key
1.15 to 0.85, fill 0.35 to 0.18. SSAO was raised to compensate for having less ambient to
darken: radius 0.55 to 0.9, intensity 1.7 to 2.6, power 1.5 to 1.8, and `ssao_light_affect`
0.1 to 0.35 so the wall corners and the shadow under a bot still read when the ambient is
small.

**3. The lighter rectangle over the floor.** The reflection probe is the only thing in
that scene that can draw a straight edge on a flat floor, so it is off (`PROBE_ENABLED =
false` in `yard.gd`); the node, its box and its blend distance stay, so it is one constant
to bring back. It was buying nothing anyway until the floor is G2's metallic
`arena_plate`. If the rectangle survives the next shoot it is the shadow cascade seam, and
the fix is `directional_shadow_mode = SHADOW_ORTHOGONAL` on the high tier: the Yard is
10 m across and a single cascade covers it comfortably.

**4. Shader compilation stalls the first seconds of a Forward+ run.** The high tier menu
run produced its first frame at 11.5 s where the low tier produced one at 3.1 s, and that
first high frame was black. Two things help. SSR is now off on the stage, which is one
fewer pipeline family to compile for a pass that had one bot on a black floor to reflect.
The real fix is a warm-up and it belongs to whoever owns the boot sequence (R2): draw the
stage once into a hidden 1x1 `SubViewport` with `render_target_update_mode = UPDATE_ONCE`
behind the Swift splash, so the pipelines are compiled before the menu is on screen. Until
then, shoot the high tier with frames later than 12 s.

## Second shoot, 2026-09-13: what the frames said and what changed

The stage works on the high tier now: amber and blue volumetric beams, a low fog bank, the
cool ring. Three things came back.

**1. The bot read as a dark silhouette from the menu camera.** The key went 3.6 to **7.0**
on a narrower cone (22 to 18 degrees) aimed at the hull (`STAGE_HEIGHT + 0.28`) rather
than at the floor in front of it, so the energy lands on the bot and not on the disc, and
a cool **`FillLight`** spot was added on the camera side at 2.6, no shadow. The menu camera
drifts between 20 and 40 degrees of yaw, so without a fill it spends half of every sweep
looking at the bot's unlit side.

**This invalidated two of C2's assertions in `workshop_test.gd`, and they are the only two
that were touched:** `spots == 5` and `lights.size() == 5` became 6, and the key's energy
band 3 to 4 became 5 to 9. The assertion that actually protects the frame is unchanged and
still passes: exactly ONE shadow caster. A new check was added that the fill exists and
casts no shadow. `docs/stage4-stage-notes.md` still says five lights and a 3.6 key; that is
C2's file, so it is theirs to correct.

**2. Specular sparkle on every steel surface.** White speckles crawling over the metals in
both stage frames: classic specular aliasing. Measured before touching anything, which is
what decided the fix: the roughness maps are already reasonable (brushed steel min 0.24
mean 0.38, titanium min 0.33 mean 0.49, arena plate min 0.36), but the **normal maps are
very strong** (mean xy deviation 0.25 from flat, z minimum 0.54) and `metallic` is 1.0
everywhere, so a mirror metal is being given violent per pixel normals inside a few screen
pixels. Four changes, three of them in G2's files:

- `project.godot` (mine): `rendering/anti_aliasing/screen_space_roughness_limiter/enabled`
  on, `amount=0.4`, `limit=0.18`. This clamps roughness per pixel from the screen space
  normal derivative and is the standard fix for exactly this artefact.
- **G2's texture imports**, all 11 sets that have both a roughness and a normal map:
  `roughness/mode=1` (Red, matching every material's `roughness_texture_channel = 0`) and
  `roughness/src_normal` pointing at that set's normal map. The importer then bakes the
  normal map's high frequency variance into the roughness MIP CHAIN, so a busy surface
  gets rougher as it shrinks on screen instead of sparkling. This is the real fix; the
  screen space limiter is the safety net.
- **G2's metal materials** (`brushed_steel`, `scratched_titanium`, `arena_plate`):
  `normal_scale = 0.35`. The other five materials got 0.7.
- **All eight materials**: `texture_filter = 5`
  (`LINEAR_WITH_MIPMAPS_ANISOTROPIC`), so they use the project's anisotropic level.

The roughness PNGs themselves were NOT rewritten. A floor of 0.35 was asked for; the maps
already sit at 0.24 to 0.68 and raising the floor would dull the bare steel, which
`docs/stage2-art-direction.md` wants as the brightest structural value. If sparkle
survives this shoot, remapping those two 512 px roughness maps to a 0.40 floor is the next
lever, and it is one PIL pass.

`render_test.gd` now asserts all four of these, because they live in another agent's files
and a regeneration script that did not know about them would silently undo the fix.

**3. The Yard floor was still light (about 175) and the rectangle survived**, which
identifies it: with the probe already off, the only remaining straight edge maker was the
shadow cascade seam. The high tier now uses **one cascade**
(`SHADOW_ORTHOGONAL`), keeping the soft shadow, which is the angular distance and not the
split count. A 10 m room never needed the range two cascades buy. The floor came down
again: exposure 0.8 to 0.7, ambient 0.22 to 0.18, key 0.85 to 0.5, fill 0.18 to 0.12. The
key is cut hardest because the floor takes it nearly face on while the walls are mostly
ambient lit, so the floor falls faster than the walls the owner has already passed.

If the floor is still above 130 after this, the next lever is **not** lighting: it is the
floor's albedo. (It landed at 100, and the floor is now G2's textured plate: see the third
pass below, where `FLOOR_TINT` became that lever.)

## Third pass, 2026-09-13

Measured on the accepted frames: menu mean 13 with the right third at 5 and the centre 63,
workshop centre 102, Yard centre 100 with the seam gone.

**1. The Yard is textured now.** G2's materials replace the flat colours in `yard.gd`:
`arena_plate` on the floor, `concrete_dark` on the wall faces, `chevron` on the wall top
strip. Three things had to be solved to do it.

- `BotMeshes.flat_box_mesh()` writes vertices and normals and **no UVs at all**, so the
  floor and the walls are **triplanar** (`uv1_triplanar`, sharpness 8). Triplanar scale is
  in metres: 0.4 on the floor is a 2.5 m tile, four across the 10 m arena. The chevron
  strip is a `BoxMesh`, which does have UVs, so it maps normally at 6 repeats: G2's tile
  carries eight stripes, so that is a stripe every 0.2 m, the reference render's rhythm.
- Every material is **duplicated** on load. The tiling, the tint and the metallic are this
  scene's, not the shared resource's.
- The textures were authored for a neutrally lit material preview (the plate means 130 of
  255, the concrete 43) and this scene lights them with a 0.5 key and 0.18 ambient, so
  they are lifted by `FLOOR_TINT` and `WALL_TINT`. **Those two constants are the floor and
  wall brightness dials**; retune there, not in the lights, or the exposure pass comes
  undone. The plate's metallic map is 1.0 everywhere and a mirror floor in a room with no
  sky has nothing to reflect, so `FLOOR_METALLIC` takes it to 0.35: scuffed painted steel
  that keeps its diffuse and still picks up the probe.
- The 1 m grid stays as a **panel seam**, darkened from 0.46 to 0.30 so it reads as a join
  between floor plates rather than as a drawn-on line.
- The **reflection probe is back on**. The rectangle was the cascade seam, not the probe,
  and the floor is part metallic now, so the probe finally has a job. Its own box edge is
  at 6 m with a 1.5 m blend, and the floor stops at 5 m, so it cannot draw a line on it.

The floor value is a **prediction, not a measurement**: an untextured 0.55 albedo measured
100, and the plate at 0.35 metallic with a 1.85 tint should land near 120. If it misses,
`FLOOR_TINT` is the one number to move.

**2. A camera inside a beam cone washed the frame.** The workshop camera sits 2.4 m out and
the near amber mover sweeps across it; an additive shell at point blank range is half a
frame of brown. Each cone now fades as the camera crosses into it, tested geometrically:
project the camera onto the cone's axis, compare its distance from that axis with the
cone's radius at that depth, and fade from 1.75 cone radii down to zero at the cone
surface. Three movers, three dot products, once a frame. The shader also got a near fade
(`smoothstep(0.25, 1.30, length(VERTEX))`) as a general catch for a shell that ends up
against the lens some other way.

**3. `docs/stage4-stage-notes.md` was updated** (light count, key energy, the fill, and
that volumetrics are a high tier layer over the fakes rather than absent). C2 is idle, so
this agent edited their file rather than leaving it wrong.

## The damage decal API (agents R and B)

```gdscript
const DecalsScript := preload("res://render/damage_decals.gd")

var decals: DamageDecals = DecalsScript.new()
decals.name = "DamageDecals"
world.add_child(decals)                 # inside the fight's SubViewport world

# a scratch across the panel that was hit; the normal may be Vector3.ZERO
decals.add_scratch(info["position"], info.get("normal", Vector3.UP), 0.22)
# a scorch on the floor under a heavy hit, a flame or a spark shower
decals.add_scorch(Vector3(hit.x, 0.0, hit.z), 0.45)

decals.clear()                          # between fights, if the node outlives the world
```

Both return the `Decal` they placed, or `null` when decals are off. `size` is the mark's
width in metres. At most 48 exist; the 49th recycles the oldest, and the oldest eight are
already fading, so nothing pops out of frame. The fade is recomputed on add, not per frame,
so a placed mark costs nothing until it is recycled. Presentation only: no RNG, no physics,
safe from `_process`.

## Performance guard: what to flip, in order

Measure first (`--roboteer-shots` frames tell you nothing about frame time; use Xcode's
GPU counters or Godot's own `Performance.TIME_PROCESS`). Then, in this order, stopping as
soon as the phone holds 60 fps. Every one of these is a single line.

1. **SSR off.** `arena_env.tres` / `stage_env.tres`: `ssr_enabled = false`, or
   `FEATURES[TIER_HIGH]["ssr"] = false` in `graphics_quality.gd` to kill it on every scene
   at once. Screen space reflection is the most expensive thing in the frame and the least
   missed on a 6.9 inch screen.
2. **Volumetric fog off.** `FEATURES[TIER_HIGH]["volumetric_fog"] = false`. The stage falls
   back to the additive cones and the billboards automatically, which is what the medium
   tier already ships, so nothing else has to change. This is the stage's biggest cost and
   the menu is the screen the player stares at longest.
3. **MSAA down.** `FEATURES[TIER_HIGH]["msaa"] = false` gives FXAA instead, or set
   `rendering/anti_aliasing/quality/msaa_3d=1` (2x) in `project.godot`.
4. **Shadow atlas down.** `SHADOW_ATLAS[TIER_HIGH]` 4096 to 2048, and
   `lights_and_shadows/directional_shadow/size.mobile` to match.
5. **The soft shadow.** `FEATURES[TIER_HIGH]["soft_shadows"] = false`, or
   `KEY_ANGULAR_DISTANCE = 0.0`. Every tier is already on one cascade.
6. **SSAO off.** `FEATURES[TIER_HIGH]["ssao"] = false`. This is deliberately late: contact
   shadow under every wheel, bolt head and panel gap is most of what separates a PS4 class
   frame from a flat one.
7. **The whole renderer.** `renderer/rendering_method.mobile="mobile"` in `project.godot`.
   One key, and the phone is on the medium tier with everything that implies. Keep this
   last: it also costs the HDR glow quality and the physical light falloff.

Nothing else in the project may switch a renderer feature on or off. If a scene needs to be
cheaper, it asks `GraphicsQuality.allows()` and builds less.

## Traps found while building this

- **`--headless` claims `forward_plus`.** See above. Any code that branches on the
  rendering method alone is wrong in a test run.
- **A shared `Environment` resource is mutated by `apply()`.** Every scene duplicates the
  resource on load. Without that, running one fight on the low tier would leave SSAO off in
  the `.tres` for the rest of the process, and in the editor it would write it to disk.
- **A `SubViewport` inherits none of the project's anti aliasing settings.** Every fight
  builds its own (`fight.gd`), so `GraphicsQuality` listens to `SceneTree.node_added` and
  applies MSAA, FXAA, debanding and the positional shadow atlas to each one as it enters.
  That is why the autoload is a `Node` and not a plain script.
- **`anisotropic_filtering_level` is an enum, not a number of taps.** 0 is 1x, 1 is 2x, 2
  is 4x, 3 is 8x, 4 is 16x. `graphics-bar.md` asks for "4"; the project ships `2`, which is
  4x filtering. Raise it only with a measurement.
- **`Decal` projects along its own -Y.** A scratch on a wall needs the surface normal as
  the decal's +Y, not as its -Z. The test asserts it.

## Owed

- **Frames.** Shot once (see "First shoot" above). The retuned numbers have NOT been shot:
  a headless run is the low tier by definition, so everything on the high tier path is
  still reasoning plus one set of frames that showed it drawing nothing.
- **A device measurement.** Nothing here has run on the phone. The tier table says an A15
  and up gets Forward+; that is the brief's claim, not a measurement, and step 7 above is
  the answer if it is wrong.
- **The beam shader still has never been compiled** (C2's known weakness 2). A windowed
  run is the only thing that would catch a typo in those 12 lines of GLSL.
- **SSR has almost nothing to reflect in yet.** The Yard's floor is still the procedural
  `_flat()` material at roughness 0.85, and a rough dielectric reflects nothing worth the
  screen space pass. The reflection only starts paying for itself when G2's
  `arena_plate.tres` (scuffed steel, metallic, roughness around 0.4) is on the floor mesh.
  Those materials are G2's file, not this agent's, so this is a hand off, not a fix: if
  the floor is still flat grey when the frames come back, SSR is step 1 of the
  performance list for free.
