# The menu stage, animated

Owner, 2026-09-14, after playing the build on his iPhone: *"the main menu image looks awesome
but I want this to be animated with the smoke swirling at the base and changing the light on
the featured robot."* Before this pass the stage was a live 3D scene that read as a still: the
dry ice was 150 billboards drifting at 0.1 m/s with no internal detail, and the three movers
wandered by a slow sine that never took a beam anywhere near the bot.

Everything below is in `Arena/workshop/stage.gd`, the two shaders in
`Arena/render/stage/`, and is asserted by `Arena/tests/stage_animation_test.gd`
(145 checks). Nothing in it is gated on fight state, on a bot being loaded, or on a camera
mode: it is driven from the stage's own `_process` off its own clock, so it keeps moving
behind the SwiftUI menus, in `menu` and in `workshop` alike, and with an empty turntable.

The calibrations the owner has already accepted are unchanged. The fog ring still sits
outside the 1.5 m rim, still hugs the floor under 0.2 m, still never emits over the stage
centre; the frame is still black everywhere a light is not pointing.

---

## 1. What moves, and how often

| thing | period | amount | where |
|---|---|---|---|
| Turntable | 45 s a turn | 8 deg/s | unchanged |
| **Beam sweep**: one mover walks its aim through the bot and out the other side | **8.0 s** (4.4 s of travel, then a rest) | 1.25 m either side | `SWEEP_PERIOD`, `SWEEP_TRAVEL`, `SWEEP_REACH` |
| **Amber hand off**: which mover is warm | hold 14 s, hand over 2 x 1.6 s | one mover, never two | `WARM_HOLD`, `WARM_FADE`, `WARM_ORDER` |
| **Key breathing** | 11 s | +/- 3.5 % of energy 7.0 | `KEY_BREATH_PERIOD`, `KEY_BREATH_AMOUNT` |
| **Key colour drift** | 17 s | 0.35 towards a colder or a more neutral white | `KEY_DRIFT_PERIOD`, `KEY_DRIFT_AMOUNT` |
| **Rim roll**: the rim light swings round behind the bot | 26 s | +/- 48 deg | `RIM_SWING_DEG`, `RIM_SWING_PERIOD` |
| **Aim easing**: every mover glides towards its aim instead of being placed on it | 0.5 s time constant | stops the hand over snapping the outgoing mover 1.25 m back to centre | `AIM_EASE_TAU` |
| **Mover breathing** (the tasteful end of a gobo flicker) | 13 / 16 / 19 s | +/- 5 % each | `MOVER_BREATH` |
| **Beam shimmer**: haze drifting down each shaft | ~12 s to cross a shaft | takes away at most 12 % | `shimmer` in `beam.gdshader` |
| **Dry ice swirl**: the bank walks anticlockwise round the rim | ~110 s for a full circuit at 0.1 m/s | + turbulence curl | `swirl` in `DRY_ICE` |
| **Dry ice drift** towards the camera | over a 9 s particle life | ~0.1 m/s by the end | `wind` in `DRY_ICE` |
| **Ground fog noise**: two octaves scrolling through the alpha | 0.013 / 0.021 m/s | thins a quad to at worst 0.30 | `scroll`, `floor_lift` in `ground_fog.gdshader` |
| **Tendrils** curling over the lip and dissolving | 5.5 s a life | 44 wisps on high | `TENDRILS` |
| **Denser puff** somewhere new on the rim | every 6 to 11 s | 34 quads, one shot | `PUFF_MIN`/`PUFF_MAX` |

Nothing strobes. The fastest thing on the stage is an 11 s sine.

### The light choreography in one paragraph

Three movers hang over the stage. Exactly one of them is amber at any moment and the other
two are cool blues; every 14 seconds the amber is handed on, and the hand off is sequential
(the holder fades all the way cool over 1.6 s before the next one warms up over 1.6 s), which
is what makes "never two warms at once" a property of the code rather than a promise. Mover
0, upper left, is the amber's home and gets it back every other time, so the accepted key art
is what the frame looks like most of the time. Every 8 seconds one mover (a different one
each time, alternating direction) walks its aim 1.25 m from one side of the bot, through it,
and out the other side over 4.4 seconds with a smooth start and stop, so a beam visibly
crosses the bot roughly every 8 s and only ever one at a time. Under that, each mover's energy
breathes 5 % on its own long period, the key breathes 3.5 % on an 11 s period while its colour
temperature drifts between a colder and a more neutral white (never into amber: the frame's
only saturated warm is the mover holding it), and the warm rim light behind the bot swings 48
degrees either side of its mounted angle every 26 s while the turntable turns under it, so the
lit edge travels round the bot instead of sitting on one corner. The rim swings rather than
orbits because a rim light that comes round to the camera side flares into the lens and stops
being a rim.

---

## 2. The dry ice

Five ring emitters outside the 1.5 m rim (unchanged positions), two new tendril emitters on
the camera side, and one one-shot puff walked round the rim by the golden angle.

- **Swirl**: each ring emitter's `direction` is the tangent at its own position with a little
  outward lean, spread narrowed from 88 to 55 degrees. A coherent flow reads as a moving bank;
  a hemisphere of directions reads as static fizz.
- **Curl**: GPU turbulence on every dry ice emitter (`turbulence_noise_strength` 0.13 on the
  ring, 0.30 on the tendrils). It is a noise field the particle shader samples, so it costs
  nothing on the CPU and behaves the same on Forward+ and on `gl_compatibility`. The strength
  is chosen so a curl cannot lift a quad above the stage lip line.
- **Drift**: a very small constant acceleration (`wind`) pulls the near emitters towards the
  camera and everything gently down. The two emitters behind the bot get almost none, so
  nothing ever drifts across the bot's silhouette from behind.
- **Tendrils**: thrown outward over the lip at 0.16 to 0.30 m/s, falling, heavily turbulent,
  growing as they go (`scale_curve`) and dead in 5.5 s.
- **Puffs**: `one_shot`, fired every 6 to 11 s from a seeded RNG at a new point on the rim.

### `ground_fog.gdshader`

Replaces the static gradient billboard. Three things it does that the StandardMaterial3D
could not: two octaves of scrolling value noise bite into the alpha, so even the thin layer
churns; each particle picks one of **three procedural sprites** (a round blob, a stretched
wisp, a lumpier blob) from a stable per particle seed, the particle's own rotation, which
never changes because every dry ice emitter sets zero angular velocity; and it is plain GLSL
with no texture fetch, so it is identical on both renderers. It billboards by hand with the
standard Godot keep-scale snippet and re-applies the particle rotation in UV space.

**Brightness.** The noise can only ever *reduce* alpha (mean about 0.8), and the authored per
quad alpha came down from ~0.020 to ~0.013 because there are more quads. Integrated over the
bank that is about 0.96 of what the accepted still shows, so the bottom of the frame is not
brighter than before.

### The simulator's opaque tan rectangles (fixed here, two passes, 2026-09-14)

Two live Simulator runs (gl_compatibility over OpenGL ES 3, low tier) showed the stage's
beam dust as **opaque tan rectangles**, about 10 x 40 pt, vertical, hard edged, each one the
whole quad with no falloff at all.

**First cause**: `_soft_quad_material` was a `StandardMaterial3D` whose only source of alpha
was a `GradientTexture2D` generated at runtime. **Second cause**, still there after the
texture was gone: the replacement shader billboarded itself by writing `MODELVIEW_MATRIX`,
which the compatibility renderer does not apply to particles, so the quads stayed as world
space rectangles (hence the vertical 10 x 40 aspect) and their alpha never reached the
pixels.

The rule all three stage shaders now follow, and that `stage_animation_test.gd` asserts:

- **the emitted colour is itself multiplied by the falloff and by the authored alpha**:
  `ALBEDO = base_colour * fall * amount`, with `ALPHA = fall`. If the renderer honours ALPHA
  the quad draws at `base * fall^2 * amount`; if it ignores ALPHA entirely it still draws at
  `base * fall * amount`, which is soft edged and faint. **There is no path that produces a
  hard edged solid quad.** (`fade_power` and `softness` came down to compensate for the
  falloff now being applied twice.)
- **the billboard is done by the particle system**, not the shader:
  `GPUParticles3D.transform_align = TRANSFORM_ALIGN_Z_BILLBOARD` is computed engine side into
  the instance transform, so it works on Forward+ and on GLES3 alike.
- **nothing outside the core built ins**: no `MODELVIEW_MATRIX` write, no `INV_VIEW_MATRIX`,
  no `INSTANCE_CUSTOM`, no `texture(` fetch, no derivatives, no screen or depth texture. The
  test scans the comment-stripped source of all three shaders for every one of those.
- **no dependence on particle data for safety**: the particle's alpha is used only as a
  normalised life fade, and if it is not what the shader expects it clamps to 1 and the quad
  falls back to the authored `alpha_scale` constant, which is 0.013 to 0.04 for fog.
- The three sprite variants are now per **emitter** (`stretch`, `softness`, `bite` in
  `FOG_VARIANTS`) instead of per particle, because picking them per particle needed
  `INSTANCE_CUSTOM`.

The old gradient material survives only as the fallback for a checkout with no
`res://render/stage/` directory.

---

## 3. Budgets per tier

The tables in `stage.gd` are the **high** tier; `PARTICLE_SCALE` scales every emitter and
`ALPHA_TIER_GAIN` raises the per quad alpha by roughly the same factor, so a thinner bank is
not also a fainter one.

| tier | ring | tendrils | puff | dust | **total billboards** | per quad alpha |
|---|---|---|---|---|---|---|
| high (Forward+, A15 and up) | 178 | 44 | 34 | 24 | **280** | x 1.0 (and x 0.5 again while real volumetric fog is drawing under it) |
| medium (mobile renderer, older iPhones) | 107 | 26 | 20 | 14 | **167** | x 1.5 |
| low (gl_compatibility / the simulator, and headless) | 57 | 14 | 11 | 9 | **91** | x 2.2 |

280 on the high tier is the whole particle budget of the menu; the fight scene has its own.
It is a few hundred soft additive quads that never write depth and never cast a shadow, which
on an A19 is a fill cost and nothing else. The first lever if a device ever drops frames is
`PARTICLE_SCALE["high"]`, then the tendrils, then the puff.

No volumetric fog was added: `FogVolume` needs the Forward+ volumetric buffer and the
compatibility renderer has none, so the two existing FogVolumes still only draw on high and
everything new works on both renderers.

## 4. Lights

Unchanged at **six**: three movers, a key, a fill and a rim, with the key still the only
shadow caster on the stage. Nothing was added; the movers, the key and the rim are
re-pointed and re-coloured each frame instead. `workshop_test.gd` asserts the count, the one
shadow, and the key's 5 to 9 energy band, and all three still hold (the breathing is
+/- 3.5 % of 7.0).

## 5. Verifying

Headless, no window, no simulator:

```
scripts/test-arena.sh stage_animation_test      # 145 checks
scripts/test-arena.sh workshop_test             # 86 checks, the still frame rules
scripts/test-arena.sh                           # the whole suite
```

The shader checks are real: Godot's `ShaderLanguage` pass runs even under `--headless`, and a
shader that does not compile comes back with an **empty uniform list**, so "N uniforms" in the
test output is proof the whole file parsed.

### What to look at on a device

1. **Is it moving at all?** Park on the main menu for 30 s without touching anything. The fog
   at the base should be visibly churning, not sliding as a sheet.
2. **The 8 second beam.** Watch the bot, not the lamps. A beam should walk across it about
   every 8 s. If two cross at once, `_advance_sweep` is being called more than once a frame.
3. **One warm.** Freeze-frame anywhere: exactly one shaft should be amber. Two ambers means
   `_animate_warmth` skipped its fade-out phase.
4. **The fog line.** It must still sit in the bottom of the frame and never rise over the
   bot's top plate. `workshop_test.gd` projects that through the real menu camera, but the
   turbulence is the one thing that could break it in motion.
5. **Bottom-right brightness.** The accepted still peaks at 240/255 there. If the fog now
   washes the lowest menu button, drop `floor_lift` or the authored alphas, not the counts.
6. **The tendrils.** They should read as a few separate wisps pouring over the lip on the
   camera side, not as a general haze. If they are invisible, GPU turbulence is not running
   on that renderer and `turbulence_noise_strength` is the first thing to check.
7. **The beam dust.** A dozen or so tiny soft motes inside the shafts above the stage. If any
   of them is a hard edged rectangle of solid colour, a sprite has gone back to taking its
   alpha from a texture: see section 2 and run `stage_animation_test`, which checks for
   exactly that. Check this on the SIMULATOR as well as the phone: the fault only ever
   appeared on gl_compatibility.
