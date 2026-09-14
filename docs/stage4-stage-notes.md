# Stage 4 stage notes (agent C2: workshop stage, camera modes, test overlay)

Files owned: `Arena/workshop/**`, `Arena/ui/test_overlay.gd`, `Arena/ui/camera_rig.gd`
(the workshop and menu modes only), `Arena/tests/workshop_test.gd`, this file.
Spec: `docs/stage4-spec.md` section 5, `docs/stage2-art-direction.md` "Owner decision
2026-09-13: menus are AAA cinematic", `docs/stage3-ui-notes.md` for the fight camera it
extends.

Nothing here touches the simulation. The bot on the stage is frozen static, every
animation runs in `_process`, and the fight camera behaves exactly as it did in Stage 3
until someone calls `set_mode`.

**Naming**: the spec calls the scene `workshop.tscn` / `workshop.gd`. It ships as
`Arena/workshop/stage.tscn` + `stage.gd` (`class_name WorkshopStage`) because the owner
decision made it the menu backdrop as well as the builder turntable, and "the stage" is
what it is on every screen but one.

## Wiring, for agent R2

```gdscript
const StageScene := preload("res://workshop/stage.tscn")

var stage: WorkshopStage = StageScene.instantiate()
add_child(stage)
stage.ready_for_host.connect(_on_workshop_ready)   # optional: it also answers the Bridge itself

# switching modes
stage.set_active(true)                              # fight world off, stage on
rig.set_workshop_centre(stage.global_position)
rig.set_mode("workshop")                            # or "menu" behind the SwiftUI chrome
stage.show_bot(config.bots[0])                      # or let the workshop_config message do it

# back to the fight
stage.set_active(false)
rig.set_mode("fight")
rig.fit_arena(FightTypes.ARENA_SIZE)
```

`set_active(false)` also drops the stage's `Environment` from its `WorldEnvironment`, so
two world environments are never live at once. Turn the stage off before the Yard is
shown and the Yard keeps its own lighting untouched.

The stage connects to the `Bridge` autoload **by node** (`/root/Bridge`), not by the
global identifier: a `--script` test run compiles this file as a dependency before the
autoload globals are registered, and `Bridge` would not resolve. Behaviour is identical.

## API as implemented

### WorkshopStage (`class_name WorkshopStage extends Node3D`)

| member | notes |
|---|---|
| `func show_bot(config: Dictionary)` | frees the current bot, instantiates `res://bot/bot.tscn`, `setup(config, 0, RandomNumberGenerator.new())`, `place_at` the turntable centre facing +X, `freeze()`, then forces `freeze = true` and `FREEZE_MODE_STATIC` on **every** RigidBody3D under it. Emits `ready_for_host`. An empty config just clears the stage. |
| `func set_active(on: bool)` | visibility, `_process`, every emitter's `emitting`, and the `WorldEnvironment`. |
| `func is_active() -> bool` | reads it back. |
| `func bot_summary() -> Dictionary` | the bot's `build_summary()` when it has one (P2's, wave 1), else `{}`. |
| `signal ready_for_host(summary: Dictionary)` | after every `show_bot`, including the empty and the failed ones. |
| `func set_auto_rotate(on: bool)` / `auto_rotate()` | idle turntable spin, `AUTO_ROTATE_DEG_PER_S` = 8 deg/s. |
| `func stage_centre() -> Vector3` | the top of the raised disc, which is what the camera should orbit. |
| `func turntable() -> Node3D`, `turntable_angle_deg()`, `bot()`, `last_summary()` | accessors for R2 and the test. |
| `static func load_bot_config(path) -> Dictionary` | reads a `res://` or absolute JSON file; accepts a whole FightConfig (takes `bots[0]`) or a bare bot entry. `{}` when there is nothing usable. |

Bridge contract: a `workshop_config` message with `{"bot": {...}}` calls `show_bot` and
answers `workshop_ready` with the summary. Every message re-assembles, so the Swift side
debounces (spec section 7, 150 ms), not this side.

### CameraRig additions (`Arena/ui/camera_rig.gd`)

`set_mode(mode)` takes `"fight"`, `"workshop"` or `"menu"`; anything else is treated as
`"fight"`. `mode()` reads it back. Every Stage 3 behaviour is untouched in fight mode
and `ui_test.gd` is unchanged and green.

| mode | behaviour |
|---|---|
| `fight` | exactly as `docs/stage3-ui-notes.md` describes: arena fit distance, look-at bias, ease back, wreckage orbit. Entering it restores the default pose. |
| `workshop` | look-at is `workshop_centre + 0.15 m` and never moves. Distance is `WORKSHOP_BASE_DISTANCE` (2.4 m) times a zoom clamped to 0.4 to 1.5, so 0.96 m to 3.60 m. Tilt clamps 5 to 85 degrees, yaw free. No ease back, no wreckage cut, no arena fit. Idle rotation is the turntable's job, not the camera's. |
| `menu` | yaw drifts 20 to 40 degrees and back on a cosine, one sweep every 20 s (`MENU_PERIOD_S` 40 s round trip), pitch 18, distance **4.8 m** aimed at **0.28 m** (`MENU_LOOK_HEIGHT`), which is wider and higher than the workshop's. `orbit` and `pinch` are ignored outright. |

The menu distance is not a taste call. At 2.9 m aimed at 0.15 m the near side of the
floor is only visible out to radius 1.08 m, which is **inside** the 1.5 m disc, so a low
fog bank can never appear at the bottom of the frame and every emitter beyond the rim
projects *behind the bot at mid frame* instead, which is what veiled it in the first
build. At 4.8 m aimed at 0.28 m the floor is visible out to radius 1.74 m, fog at the rim
lands 87 to 100 % down the frame, the bot's top plate sits 42 % down and the bot is 40 %
of the frame height. `workshop_test.gd` projects both points through the real camera and
asserts it.

`set_workshop_centre(v)` moves the point both stage modes orbit (default: the origin,
which is where `WorkshopStage` puts its turntable). `workshop_zoom()` reads the zoom
fraction.

**Input.** The workshop has no driving controls, so there is no `FightControls` to route
touches and the rig takes them itself in `_unhandled_input`, connected only while the
mode is `"workshop"`. One finger drags: orbit. Two fingers: pinch on the spread of the
first two, plus a half weight orbit on the moving finger, which matches the fight feel.
`InputEventMagnifyGesture` (trackpad) is a pinch. `handle_event(event) -> bool` is the
public seam `_unhandled_input` delegates to, the same pattern `FightControls` uses, so
the headless test feeds synthetic events through it.

The Stage 3 desktop QA key map still works in every mode, because it arrives through
`orbit()` and `pinch()` and those now apply the current mode's clamps. `--roboteer-yaw`,
`--roboteer-pitch` and `--roboteer-zoom` still pose the **fight** camera only.

### TestOverlay (`class_name TestOverlay extends CanvasLayer`, layer 3)

| member | notes |
|---|---|
| `func bind(bots: Array, camera: Camera3D)` | the bots to read and the camera to project through. Either may be empty or null. |
| `func set_visible_overlay(on: bool)` | hides the drawing and the readings; the button bar stays up so it can be brought back. |
| `func is_overlay_visible() -> bool` | reads it back. |
| `func note_damage_event(info: Dictionary)` | the spec section 6 payload. Keeps the last line and fades it over about 6 s. |
| `signal reset_requested` | the Reset button. R2 connects it to `test_reset`. |
| `func canvas() -> Control`, `draw_count()`, `last_damage_line()` | accessors for the test. |

Per bot it draws: a centre of mass crosshair projected from
`chassis.global_transform * chassis.center_of_mass`; the weapon reach arc, an arc on the
screen centred on the weapon socket and radiused by projecting a point one reach ahead
of it; and a text panel with the front lip clearance in mm (`front_edge_height()`), the
weapon height band, the speed, the wheel contact count and the weapon readiness. The
last damage event runs along the bottom. Bot 0's panel is on the left, bot 1's on the
right.

**Every reading is duck typed.** `front_edge_height`, `weapon_height_band`,
`wheel_contacts`, `weapon_readiness`, `weapon_socket_world`, `weapon_reach` / `reach`
are each used only when the Bot has them, so the overlay written in wave 1 keeps working
as P2, W1 and W2 add methods. What the Bot cannot answer is simply not drawn. The
fallbacks are: the weapon socket falls back to a child named `Flipper*` or `Weapon*` and
then to the chassis nose, and the reach falls back to `DEFAULT_REACH` (0.45 m, the
Stage 3 flipper).

## Node tree

```
WorkshopStage (Node3D, stage.gd)
├── Environment (WorldEnvironment)   dark blue-black BG, ambient 0.35, glow on
├── Floor (MeshInstance3D)           16 m plane, near-black, roughness 0.22, metallic 0.55
├── Stage (Node3D)
│     ├── Disc (CylinderMesh, r 1.5, h 0.12)      the raised 3 m stage
│     ├── Ring (TorusMesh)                        the turntable ring
│     ├── EdgeLight (TorusMesh, unshaded emissive) the thin light edge, the only bloom source
│     └── Turntable (Node3D)                      the bot's parent, 8 deg/s
│           └── ShowBot (Bot)                     frozen static, rides the turntable
├── Backdrop (MeshInstance3D)        a 22 x 6 m wall at z = -7, deep blue-black
├── Movers (Node3D)
│     ├── Mover0 ├── Spot (SpotLight3D, amber) ├── Beam (cone, additive ShaderMaterial)
│     │          └── Head (small emissive lamp head, as in the key art)
│     ├── Mover1 (cold blue)
│     └── Mover2 (cold blue, dimmer)
├── KeyLight (SpotLight3D, cold white, front left, THE shadow caster)
├── RimLight (SpotLight3D, warm, from behind)
├── DryIce0 / DryIce1 / DryIce2 (GPUParticles3D)
└── Dust (GPUParticles3D)
```

## Light, particle and draw budget

- **6 lights** (5 until agent G1's lighting pass on 2026-09-13). Three SpotLight3D movers
  (one amber, two cold blue), a cold white **key** from the front left at energy **7.0** on
  an 18 degree cone aimed at the hull, a cool **fill** from the camera side at 2.6, and a
  warm **rim** from behind at 2.4. **One shadow caster**, the key: three moving shadow
  casters is the whole phone budget, and the key is the light that both grounds the bot on
  the disc and makes its plates read. The key was 3.6 on a 22 degree cone and there was no
  fill, which left the bot reading as a dark silhouette from the menu camera in the shot
  frames; the menu camera drifts 20 to 40 degrees of yaw, so without a fill it spends half
  of every sweep on the bot's unlit side. `workshop_test.gd` asserts 6 lights, 6 spots, one
  shadow caster and a key between 5 and 9.
- **Black is the default state.** Background colour is pure black, ambient light energy
  is **0.05** (it was 0.35, which lifted every surface at once and is the single biggest
  cause of a milky frame), the floor albedo is 0.028 with the metallic sheen kept
  (metallic 0.55, roughness 0.22), the disc is 0.042 and matte, and the backdrop is
  0.006. Everything visible on screen is put there by a light.
- **Volumetrics on the high tier only** (agent G1, 2026-09-13): on Forward+ the stage
  carries real volumetric fog plus two `FogVolume` boxes, and the three movers light it
  through `light_volumetric_fog_energy`. The cones and billboards below still draw
  underneath at half strength, so the high tier is the low tier plus real fog. Everything
  in the rest of this bullet is what medium, low and the simulator still use:
  the mobile renderer has no volumetric fog and no `FogVolume`, so
  each beam is a 20 segment open cone (`CylinderMesh`, 0.035 m at the lens,
  `tan(8 degrees)` wide at the far end) with a 12 line `ShaderMaterial`: `unshaded,
  blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled`. Alpha is
  `BEAM_ALPHA` 0.06 at the lens falling as `pow(1 - along, 2.2)` to zero at the floor,
  and `along` comes from model space `VERTEX.y`, not `UV`, so it does not depend on
  `CylinderMesh`'s UV convention. **Each cone is cut to the distance from its own mount
  to the stage** (about 4.3 m), so no shaft passes through the floor and out the far side
  of the frame. A small emissive lamp head sits at each mount, as in the key art.
- **4 emitters, 58 particles.** Dry ice is 14 + 11 + 11 billboards in a ring just outside
  the 1.5 m rim at y 0.035, quads 0.29 to 0.59 m, alpha 0.04 to 0.05, drifting outward at
  0.08 to 0.15 m/s and sinking slightly. Small is the point: the workshop camera sits
  2.4 m away, where a 1 m billboard already covers the whole screen height, and the first
  build's 1.5 to 2.7 m quads over the stage centre were the milky bands across the frame.
  Beam dust is 22 quads of 0.008 to 0.018 m in a 1.1 m box at y 1.05, inside the shafts
  where they cross, and nothing else floats in the air. Every quad is unshaded additive
  with `DEPTH_DRAW_DISABLED` but depth **testing** left on, so the bot occludes the fog
  behind it.
- **Mesh count**: floor, disc, ring, edge, backdrop, 3 beams, 3 lamp heads = 11 draw
  calls plus the bot.

## Calibration pass, 2026-09-13

The first build rendered as a milky grey-blue wash: opaque beams, screen filling dry ice,
an unlit bot and a lifted background. Diagnosis and levers, in order of how much each one
mattered:

1. **Ambient light energy 0.35** lifted every surface in the frame at once. Now 0.05.
2. **Dry ice quads of 1.5 to 2.7 m emitted over the stage centre.** At 2.4 m from the
   camera one of those covers the entire screen, and twenty of them additively is a wash.
   Now 0.29 to 0.59 m, in a ring outside the rim, never over the bot.
3. **Beams 16 degrees wide and 9 m long**, so each cone shot past the floor and out of
   frame as a solid wedge. Now 8 degrees, cut at the stage, alpha 0.06.
4. **No key light.** The bot was lit only by sweeping movers and a rim, so it read as a
   silhouette in fog. Now a 3.6 energy cold white key from the front left, and it is the
   shadow caster.
5. **The menu camera was too close to have a foreground at all** (see the camera section).
6. Background, floor, disc and backdrop albedos all pulled down toward black.

Every one of those is now asserted in `workshop_test.gd` (ambient energy, background
luminance, floor and backdrop albedo, beam alpha and angle, dry ice size, alpha, height
and distance from the centre, dust containment, the key light's energy and shadow, and
the projected positions of the fog band and the bot's top plate), so the frame cannot
silently drift back.

## QA arguments and commands

```
# the stage with the Stage 3 fixture bot on it
Godot --path Arena -- --roboteer-workshop

# the stage with a specific bot config (a FightConfig, or a bare bot entry)
Godot --path Arena -- --roboteer-workshop=/abs/path/to/bot.json

# frames without screen recording, using the existing QaShots autoload
Godot --path Arena -- --roboteer-workshop --roboteer-shots=/tmp/stage,2,6
```

`--roboteer-workshop` is read only when `OS.has_feature("pc")`, so a device build can
never be posed by an argument. Without a value it loads
`res://fight/fixtures/stage3_config.json` `bots[0]`. The stage scene is not the main
scene, so until R2 wires the mode switch this argument only does anything in a run that
already has the stage in the tree.

Tests:

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/workshop_test.gd
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/ui_test.gd
scripts/test-arena.sh
```

`workshop_test.gd` is 85 checks, exit 0 on pass, and is picked up automatically by
`scripts/test-arena.sh` (anything in `tests/` that is not in its ORDER list still runs).
It covers: the scene builds 4 lights with exactly one shadow caster and 3 haze cones; the
dry ice hugs the floor; `set_active` hides the stage and stops the particles; `show_bot`
puts exactly one Bot on the turntable with every RigidBody3D frozen and no velocity, at
the stage centre; a second `show_bot` frees the first; `ready_for_host` fires once per
call with a Dictionary; a `workshop_config` bridge message answers `workshop_ready`; the
turntable turns 8 degrees per second and stops on `set_auto_rotate(false)`; the workshop
camera sits 2.4 m from the stage centre looking at 0.15 m, a synthetic one finger drag
orbits it, tilt clamps at 5 and 85, pinch clamps at 0.4 and 1.5 of the base distance and
it never eases back; the menu drift starts at yaw 20, reaches 40 at 20 s, returns at 40 s,
sits at pitch 18 and ignores input; `set_mode("fight")` restores the Stage 3 pose; and the
overlay binds, draws (the draw count is asserted, so the draw call signatures really are
exercised), toggles, records a damage event, fires `reset_requested`, and survives being
bound with no bots and no camera.

Time is stepped by hand (`rig._process(dt)`, `stage._process(dt)`), the same trick
`ui_test.gd` uses, so nothing depends on the frame rate.

## Known weaknesses

1. **This agent has still seen only one render of it**, the coordinator's frames from the
   first build, which is what the calibration pass above answers. The second shoot is
   owed. The remaining unknowns are the absolute brightness of the fog where a spot
   crosses it, whether the key at 3.6 over-exposes a bare steel plate, and whether the
   three beams read as three shafts or as one glow where they cross.
2. **The beam shader has never been compiled.** `--headless` builds the resource but
   never compiles it, so a typo in the shader body would only show on a windowed run.
   The GDScript around it is tested; the 12 lines of GLSL are not.
3. **Glow is on.** It is supported on the mobile renderer but it is a full screen pass on
   a phone. The environment now comes from `res://render/stage_env.tres` and every
   scalable switch on it goes through `GraphicsQuality` (see
   `docs/graphics-render-notes.md`), so the lever is `FEATURES[...]["glow"]` there rather
   than a line in this scene.
4. **The turntable carries frozen static bodies.** A `FREEZE_MODE_STATIC` RigidBody3D
   follows its parent transform, which is what makes the bot ride the turntable, and the
   test proves the freeze but not the ride (headless physics is not stepped here). If a
   bot ever shears off the disc on a device, the fix is `FREEZE_MODE_KINEMATIC`.
5. **`build_summary()` does not exist yet.** P2 adds it in wave 1, so `bot_summary()`
   and every `workshop_ready` payload is `{}` until then, by design. The Swift side must
   tolerate an empty dictionary rather than assuming keys.
6. **The reach arc is a flat screen space arc**, drawn about the projected socket with a
   radius taken from a point one reach ahead. At a low camera tilt that radius is
   foreshortened, so the arc understates the reach when the camera is nearly level with
   the floor. A ground projected ellipse would be correct and costs more; this is a debug
   overlay, so it is not worth it.
7. **The overlay's two column layout assumes two bots.** A third bot (Rumble) would draw
   its panel on top of bot 1's. Only the test arena uses the overlay and the test arena is
   one on one.
8. **The mode switch is R2's.** `set_mode` and `set_active` are exposed and tested, but
   nothing in `fight.gd` calls them yet, so no run yet shows the stage and the fight in
   sequence.
9. **A `--script` test that fails to LOAD still exits 0.** While agent P2 was mid-edit,
   `bot.gd` did not parse, so `class_name Bot` did not resolve, so `workshop_test.gd`
   (which named `Bot` in two checks) failed to parse and the suite printed
   "8 test files, 0 failures" with the workshop test never having run a single check.
   The test no longer names `Bot`: it duck types on `setup` and `place_at`, and it prints
   SKIP and keeps going when `bot.tscn` cannot assemble. **Any test that names another
   agent's `class_name` can be silenced this way, and the suite will not tell you.**
10. **`set_active(false)` releases the environment** by setting `WorldEnvironment.environment`
   to null. If R2 ever wants both the stage and the arena visible at once (a picture in
   picture preview), that has to change to one shared environment.
