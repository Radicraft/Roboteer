# Stage 3 UI notes (agent C: controls, HUD, camera)

Files owned: `Arena/ui/controls.{tscn,gd}`, `Arena/ui/hud.{tscn,gd}`,
`Arena/ui/camera_rig.{tscn,gd}`, `Arena/tests/ui_test.gd`, this file.
Spec: `docs/stage3-spec.md` sections 0, 1, 2, 4, 10, 14; `docs/brief-v3.md` section 11.

Nothing in `Arena/ui` touches the simulation. Every animation, tween and camera move
runs in `_process`. The rules layer samples `heading`, `consume_fire()` and `secondary`
once per physics tick and nothing is fed back the other way.

## Wiring, for agent R

```gdscript
var controls: FightControls = preload("res://ui/controls.tscn").instantiate()
var hud: FightHud = preload("res://ui/hud.tscn").instantiate()
var rig: CameraRig = preload("res://ui/camera_rig.tscn").instantiate()
add_child(rig); add_child(hud); add_child(controls)
rig.bind_controls(controls)          # or connect camera_pinch / camera_orbit yourself
rig.fit_arena(FightTypes.ARENA_SIZE) # once
rig.set_targets(player.chassis, opponent.chassis)
controls.set_safe_area(safe_px); hud.set_safe_area(safe_px)
hud.set_bot_names(player_name, opponent_name)
```

`FightControls` is a plain `Control`, so it draws on the viewport's default canvas
(layer 0). `FightHud` is a `CanvasLayer` at layer 2, so HUD type always sits above the
stick and the buttons. Both are safe as direct children of the `Fight` Node3D.

Both `FightHud` and `CameraRig` build any missing children in code, so `FightHud.new()`
and `CameraRig.new()` work as well as instancing the scenes. That is what keeps the
headless test free of a display server.

## API as implemented

### FightControls (`class_name FightControls extends Control`)

| member | notes |
|---|---|
| `var heading: Vector2` | screen space, +x right, +y down, length 0 to 1. Zero when nothing is held. R maps it into the world. |
| `func consume_fire() -> bool` | true exactly once per tap of the primary button (or Space in desktop QA). Fires on press, not release. |
| `var secondary: bool` | level, true while the secondary button (or Shift) is held. |
| `func set_safe_area(px: Dictionary)` | `{left, top, right, bottom}` in viewport pixels. Missing keys are 0. |
| `func set_state(inverted: bool, gas_charges: int)` | relabels the secondary button "SELF RIGHT" or "PIVOT" and fills `gas_charges` of the 8 pips. |
| `func set_enabled(on: bool)` | off releases every live touch and zeroes heading. Use it for LOADING, COUNTDOWN and RESULT. |
| `func is_enabled() -> bool` | reads it back. |
| `signal camera_pinch(factor: float)` | factor > 1 means the fingers moved apart. Incremental, one per drag event, not cumulative. |
| `signal camera_orbit(delta: Vector2)` | two finger centroid movement in viewport pixels. |
| `func handle_event(event: InputEvent)` | the seam `_input` delegates to. Public so the headless test can feed synthetic events. |
| `signal pause_requested()` | START on the pad. The shell decides what a pause means; this node only reports it. |
| `signal pad_present_changed(present: bool)` | a controller was plugged in or unplugged. The HUD swaps its glyph hints on this. |
| `signal secondary_label_changed(label: String)` | the secondary button relabelled, so the pad hint can follow it. |
| `func set_scheme(name)` / `func scheme()` | `"arcade"` (default) or `"tank"`. Anything else is arcade. |
| `func tank_mix(l, r) -> Dictionary` | pure twin stick maths, see below. |
| `func tank_yaw_deg() -> float` | the virtual heading the tank scheme is steering. |
| `func pad_present() -> bool` | true while a controller is driving. |
| `func set_pad_present(on)` / `clear_pad_override()` | QA and test override of the connected joypad state. |
| `func secondary_label() -> String` | "Pivot" or "Self right", for the pad hint. |
| `func button_centres() -> Dictionary` | where the on screen furniture sits, so the HUD can place hints without duplicating the layout maths. |

### FightHud (`class_name FightHud extends CanvasLayer`)

`set_time_left(s)`, `set_scrap(total)`, `bump(amount)`, `show_ko_count(seconds_left, bot_name)`,
`hide_ko_count()`, `set_height_readout(text)`, `show_countdown(step)`, `hide_countdown()`,
`show_result(title, winner_name)`, `hide_result()`, `set_safe_area(px)`,
`set_bot_names(player, opponent)`, plus `scrap_total()` and `scrap_displayed()` for tests.
Pad hints: `bind_controls(c)`, `set_pad_hints(on)`, `pad_hints_visible()`,
`set_pad_hint_labels(primary, secondary)`, `set_controller_hints(connected, kind)`,
`controller_kind()`.

`set_scrap` is authoritative: it sets the total and rolls the displayed number to it with
a cubic ease. `bump(amount)` is the award hook B calls as bolts land: it ADDS `amount` to
the total, rolls with a back ease (the overshoot) and flashes the counter gold. Call one or
the other per award, not both, and use `set_scrap` to resync if they ever drift.

`set_time_left` rounds up, so 90.0 reads `1:30` and 9.4 reads `0:10`. Under 10 s the timer
goes red (`COL_URGENT`). `show_countdown` scales in with a back ease, holds 0.75 s and fades
out by itself; R can just call it four times.

### CameraRig (`class_name CameraRig extends Node3D`)

`fit_arena(size_m)`, `set_targets(a, b)`, `pinch(factor)`, `orbit(delta_px)`,
`reset_to_default()`, `set_director_cut(enabled)`, `begin_wreckage_orbit(center)`,
`set_input_enabled(on)`, `bind_controls(c)`, plus `camera()`, `distance()`,
`look_target()`, `default_zoom()`, `zoom_min()`, `is_easing_back()` and the readable
state `yaw_deg`, `pitch_deg`, `zoom`.

## Control zone geometry

Everything is quoted in points against a design viewport of **1206 x 556 pt** (an iPhone 17
in landscape). At runtime the layout multiplies by

```
_pt = min(size.x / 1206, size.y / 556)
```

so the project's 2412 x 1112 canvas_items viewport gives `_pt = 2.0` and the controls come
out at true physical size. The min of the two ratios means an unusually wide or tall
viewport shrinks rather than overflows.

| element | geometry |
|---|---|
| stick zone | the left 45 % of the viewport width, minus any button hit area |
| stick base | floating, spawns centred on the touch, ring radius 60 pt |
| stick knob | radius 28 pt, drawn at `origin + heading * 60 pt` |
| stick throw | 60 pt, `heading = (touch - origin) / 60 pt`, clamped to length 1 |
| primary | 92 pt circle, centre inset from the bottom right by the safe area plus 24 pt plus its own radius |
| secondary | 68 pt circle, centre at primary centre + (-92, -78) pt |
| charge pips | 8 dots on a ring 11 pt outside the primary, a 240 degree fan opening away from the screen corner so the thumb never covers them |
| hit slop | every button hit test uses 1.15 x its drawn radius |

Touch routing, in order, for a touch that begins:

1. inside the primary hit area and the primary is free: primary press, `consume_fire()` arms.
2. inside the secondary hit area and the secondary is free: `secondary = true` until release.
3. `x <= 45 % of the width` and no stick is live: the stick spawns there.
4. anything else: a camera touch.

The stick keeps its own touch index for its whole life, so camera touches can come and go
without disturbing driving. With exactly two camera touches, each drag emits
`camera_pinch(new_spread / previous_spread)` and `camera_orbit(centroid_delta)`. One camera
touch does nothing, by design. A third camera touch is tracked but the pinch and orbit keep
using the first two in the dictionary.

Colours: white line work on a dark wash, no gold. `docs/stage2-art-direction.md` records
that gold is the only saturated warm in the arena and has to stay the bolts' alone, so the
gas pips are white (spent ones near transparent) and gold appears only on the HUD scrap
counter, which is the same fiction as the bolts.

## Safe area

`set_safe_area({left, top, right, bottom})` in **viewport pixels** (Swift sends points times
`UIScreen.main.scale`, spec section 2). It is not scaled by `_pt` because it already arrives
in the same pixel space as the layout.

- Controls: the primary button centre is inset from the bottom right by `safe.right` and
  `safe.bottom` plus the 24 pt margin plus its radius. The secondary follows it. The stick
  zone is a fraction of the full width and deliberately ignores the safe area, since a
  floating stick spawns wherever the thumb is and the notch cannot be touched anyway.
- HUD: every label is laid out as a full width band inset by `safe.left + 18 pt` and
  `safe.right + 18 pt`, with the top row at `safe.top + 18 pt` and the height readout at
  `safe.bottom + 18 pt` from the bottom. In landscape the notch inset is a left or right
  inset, which is exactly what the timer, the names and the scrap counter need.

## HUD layout and type

One band across the top holds the bot names (left, dimmed), the timer (centre) and the scrap
counter (right, gold). The height readout is a band across the bottom centre, clear of the
stick on the left and the buttons on the right. Countdown and result sit dead centre. The
knockout count sits 40 pt above centre so it does not land on the two bots at the default
framing.

Type is Godot's default font (Open Sans), all capitals for banners, white with a dark
outline sized at 14 % of the font size. No font file is shipped, so there is no licence to
record. Sizes in points, doubled at the 2x design viewport: timer 40 (80 px), scrap 32,
knockout 34, readout 22 (44 px), countdown 96, result title 58. That clears the spec's 28 px
timer and 22 px readout floors with room to spare.

## Camera

- Default pose: yaw 45, pitch 50, and `DEFAULT_ZOOM` (0.6) of the fit distance. Fitting
  the whole arena (zoom 1.0) leaves a 0.9 m bot about 30 px across on a 556 px frame,
  which is not readable, so the rig rests closer and the player pinches out to
  `CAM_ZOOM_MAX` when they want the walls. `CAM_ZOOM_MAX` is still the walls on screen
  limit, it is just no longer the resting pose. Measured at 1206 x 556: fit distance
  28.7 m, default distance 17.2 m, a 0.9 m bot about 45 px along the screen vertical
  and 58 px along the horizontal. `DEFAULT_ZOOM` is the one lever if that is still small.
- The fit distance is recomputed **every frame** from the camera's own projection matrix
  (`get_camera_projection()`), not from an assumed FOV axis, so it is right at any aspect.
  For each of the 8 corners of the arena box (half the floor plus one wall thickness,
  y = 0 to the wall top) it solves the smallest distance that keeps the corner inside the
  frustum, takes the largest and adds a 5 % margin. It is always measured about the arena
  centre, so moving the look-at point can never push the camera back out.
- `zoom` multiplies that fit distance and is clamped to `[zoom_min(), CAM_ZOOM_MAX]`.
  `pinch(factor)` divides the zoom by the factor, so fingers apart moves in.
- Pitch is clamped to `[CAM_PITCH_MIN, CAM_PITCH_MAX]` (20 to 70). Yaw is free and wrapped.
  Orbit rate 0.12 degrees per pixel of yaw, 0.09 per pixel of tilt. Dragging up raises the
  camera toward the top down clamp.
- **Look-at bias.** Below zoom 1.0 the aim slides from the arena centre toward the midpoint
  of the two bots, clamped so the visible ground footprint never leaves the floor rectangle:
  the limit is the floor half extent less the footprint half extent, measured at the far
  edge of the frustum (where the top of the frustum meets the floor), projected onto world
  x and z. **Measured consequence: at FOV 28 the footprint still covers the whole 10 m floor
  at every legal zoom, so the clamp collapses to zero and the aim stays on the centre until
  zoom drops below about 0.25.** The bias is implemented and tested but inert at the current
  constants. See the weaknesses below for the two levers.
- After `CAM_EASE_BACK_AFTER_S` (3 s) with no camera input the rig eases yaw, pitch and zoom
  back to the default pose over `CAM_EASE_BACK_S` (0.8 s) with an out cubic, taking the short
  way round in yaw. Any pinch or orbit cancels the ease immediately. The ease target is the
  default pose, which is `DEFAULT_ZOOM` and not 1.0.
- RESULT, the director cut: `begin_wreckage_orbit(node)` eases in over `WRECKAGE_EASE_S`
  (1 s) from wherever the camera is, then holds `WRECKAGE_DISTANCE` (2.6 m) from the node at
  `WRECKAGE_PITCH_DEG` (35), look-at locked on the node, orbiting at 20 degrees per second.
  Any camera gesture cancels it. `set_director_cut(false)` disables it entirely so open
  question 4 can be A/B tested.
- `set_input_enabled(false)` makes `pinch` and `orbit` no ops (for the countdown).
- **Impact shake.** The rig reads agent G4's `ImpactShake`
  (`docs/graphics-fx-notes.md` section 4) and puts its `offset()` on the **Camera3D
  child's local transform** each frame, after its own placement, so it can never
  disturb the rig's `look_at`. The source is found with
  `get_tree().get_first_node_in_group("roboteer_impact_shake")`, by group and not by
  class, so `Arena/ui` keeps no dependency on `Arena/fx`: delete the FX subtree and the
  lookup finds nothing and the camera behaves exactly as it did. The lookup repeats
  whenever the cached node is null or freed, because R rebuilds the fight world for
  every fight. **Fight mode only**: workshop and menu keep the camera transform at
  identity. Peak travel is `ImpactShake.MAX_OFFSET`, 7 cm.

## Desktop QA camera arguments

Read once in `_ready` from `OS.get_cmdline_user_args()`, and only when `OS.has_feature("pc")`
so a device build can never be posed by an argument. They override the **default pose**, so
the rig starts there and eases back there, which is what makes a close up hold still without
touch input.

```
Godot --path Arena -- --roboteer-zoom=0.4 --roboteer-yaw=20 --roboteer-pitch=30
```

| argument | range | effect |
|---|---|---|
| `--roboteer-zoom=` | 0.3 to 1.0 | default zoom fraction of the fit distance. If it is below `CAM_ZOOM_MIN` the pinch clamp widens to match, so the player (and the ease back) can reach it. |
| `--roboteer-yaw=` | any degrees, wrapped | default yaw |
| `--roboteer-pitch=` | clamped to `CAM_PITCH_MIN..CAM_PITCH_MAX` | default pitch |

## Game controller

The owner requires the game to play on a physical pad (Xbox or PlayStation) as well as
touch. Godot wraps iOS `GCController` in its joypad API, so the same code path serves the
phone and a pad plugged into the Mac. **Joypad 0 only**: this is a one player game and a
second pad on a phone is far more likely to be a stray Bluetooth device than a second
driver.

Touch, pad and (on desktop) keyboard are all live at once. Per tick the resolution is:
**a deflected pad stick wins, then a live touch stick, then the keyboard.** The three
sources are kept in separate fields (`_pad_heading`, `_touch_heading`, `_key_heading`) so
releasing one can never wipe another.

| pad input | effect |
|---|---|
| left stick | `heading`. Circular deadzone `PAD_DEADZONE` 0.18, and the remaining travel is rescaled to 0..1 so the stick still reaches full throttle. The joypad y axis is already negative upward, which is this node's screen convention, so no flip is needed. |
| A, or right trigger past 0.5 | fire, edge triggered, exactly one `consume_fire()` per press |
| B, or left trigger past 0.5 | secondary, level |
| right stick | camera orbit (x) and tilt (y), `PAD_ORBIT_PX_PER_S` 900 and `PAD_TILT_PX_PER_S` 600 pixels per second |
| right shoulder / left shoulder | zoom in / out, `PAD_ZOOM_PER_S` 1.5 per second |
| START | `pause_requested`, once per press |

**The camera needs no new code.** Pad orbit, tilt and zoom go through the same
`camera_orbit` and `camera_pinch` signals the touch gestures use, so they inherit the
pitch and zoom clamps, the look-at bias and the ease back for free. `camera_rig.gd` was
not changed for this.

**Timing.** Gameplay inputs (heading, fire, secondary) are polled in `_physics_process`,
which is the clock the rules layer samples them on, and `process_physics_priority` is set
to -100 so the controls run before the `Fight` node; a parent processes before its
children, so without that every pad input would arrive a tick late. Camera inputs stay in
`_process` because they are presentation and want the frame delta.

**On screen furniture.** While a pad is present `_draw` returns early, so the stick and
both buttons disappear and the HUD shows glyph hints in their place ("A FLIP",
"B PIVOT", following the secondary label so it becomes "B SELF RIGHT" when the bot is
inverted). **The touch routing stays live underneath**, so a thumb on the now invisible
button still fires: the brief asks for both at once, not for one to lock the other out.

The HUD finds the controls through the group `roboteer_fight_controls` (`FightControls.GROUP`)
rather than being wired by the rules layer, the same trick the camera rig uses for
`ImpactShake`, and falls back to recomputing the button positions from the same constants
if there is no controls node.

### The shell's `settings` message

The Swift shell sends `settings` after `arena_ready` and on every change; the rules layer
routes it. Three of its fields land here:

| field | call |
|---|---|
| `scheme` | `FightControls.set_scheme("arcade" \| "tank")` |
| `director_cut` | `CameraRig.set_director_cut(bool)` |
| `controller_connected`, `controller_kind` | `FightHud.set_controller_hints(connected, kind)` |

`set_controller_hints` picks the glyphs: a kind containing `dualsense`, `dualshock`,
`playstation`, `ps3`, `ps4` or `ps5` (case insensitive) gets a cross and a circle,
anything else gets A and B. **Measured: Godot's default font carries neither U+2715 nor
U+25CB, so the symbols currently fall back to the letters X and O.** The fallback is
checked with `Font.has_char` rather than assumed, so shipping a font that has the glyphs
turns the real symbols on with no code change. A missing glyph draws as a blank box, which
reads as a bug, so the fallback is not optional.

`set_controller_hints` drives the **hints only**. Whether the pad can actually *drive* is
`FightControls.pad_present()`, which follows Godot's own joypad list. If the shell reports
a connected controller while `FightControls.pad_seen_by_engine()` is false, that is exactly
the failure in item 3 below: the glyphs will appear and nothing will move.

### Tank scheme (brief section 11's optional twin stick)

`set_scheme("tank")`. Left stick y is the left track, right stick y is the right track,
both flipped so ahead is positive. It needs a pad: with one floating touch stick there is
no second track to drive, so touch stays arcade whatever the scheme says.

The Bot API takes a **heading and a throttle**, not two track speeds, so the mapping is:

```
throttle  = (l + r) / 2
turn      = (l - r) / 2
magnitude = max(|throttle|, |turn| * TANK_PIVOT_THROTTLE)
```

`tank_mix(l, r)` returns exactly those plus `reverse`, and is pure so the maths is tested
on its own. The scheme then integrates `turn` into a virtual heading at `TANK_TURN_RATE`
(2.6 rad/s) which the bot chases, and emits `heading = direction(tank_yaw) * magnitude`,
negated when `reverse`.

**The one place this is not faithful** is a pure pivot (`l = -r`): the mean throttle is
zero and a zero length heading turns nothing at all, so `magnitude` keeps
`TANK_PIVOT_THROTTLE` (0.35) of the turn instead and the bot pivots slowly on the spot
rather than spinning like a real tracked machine. The honest fix is a second Bot API field
for a turn demand; that is P's file, not mine. In tank mode the right stick's y axis is a
track, so it cannot also tilt the camera: x still orbits and the shoulders still zoom.

## Desktop QA key map

Only read when `OS.has_feature("pc")` (spec section 14), so the phone build never sees it.

| input | effect |
|---|---|
| W A S D or the arrow keys | stick heading, only while no touch stick is live |
| Space | fire, one edge per press, ignores auto repeat |
| Shift | secondary, level |
| Q / E | orbit left / right, 700 px per second |
| R / F | tilt up / down, 500 px per second |
| minus / equals | zoom out / in, 1.5 pinch factor per second |
| two finger trackpad pinch | `InputEventMagnifyGesture`, passed through as its factor |
| two finger trackpad drag | `InputEventPanGesture`, delta scaled by 26 to reach pixels |
| mouse drag | a real touch, because `project.godot` sets `emulate_touch_from_mouse` (R owns that key) |
| a pad plugged into the Mac | the same code path as the phone, no special case |
| `-- --roboteer-pad=on` | forces the pad path on with no controller attached, for QA |

W A S D and Q E R F use physical key positions so a non QWERTY layout still drives.

## Test

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/ui_test.gd
```

121 checks, exit 0 on pass. The checks read the QA arguments too, so
`--script tests/ui_test.gd -- --roboteer-zoom=0.32 --roboteer-yaw=20 --roboteer-pitch=28`
and `-- --roboteer-pad=on` also pass and are what prove those argument paths.

**Joypad test seam.** `Input.parse_input_event` does fake joypad axes and buttons
headless, but it **queues** them: the state only lands on `Input.flush_buffered_events()`,
which the helpers call. It also never fakes a *connection*, so
`Input.get_connected_joypads()` stays empty and the test forces the pad path with
`set_pad_present(true)`. That is why the override exists. The `--import` is only needed after a file is added or renamed:
`class_name` lookups come from `.godot/global_script_class_cache.cfg`, which a plain run does
not rebuild. **R: add `tests/ui_test.gd` to `scripts/test-arena.sh` and have that script run
`--import` first.**

The test covers: the three scenes load; a touch at (200, 400) dragged to (260, 400) gives
heading (1, 0); one tap of the primary makes `consume_fire()` true exactly once; the
secondary is level; a single camera touch does nothing; two camera touches moving apart emit
`camera_pinch` above 1 and `camera_orbit`; a live stick is unaffected by camera touches; the
timer, scrap roll, knockout count, readout, countdown and result banner all set their text;
`_draw` runs with every element on screen (a smoke check for the draw call signatures, which
nothing else exercises before a device does); the four floor corners and the four wall tops
project inside 0..1 in screen space at 16:9 once pinched out to zoom 1.0; the default
distance is exactly `DEFAULT_ZOOM` of the fit distance; a narrower viewport increases the fit
distance; the look-at holds the centre at zoom 1.0 and never leaves the floor rectangle when
biased; pitch and zoom clamp; the ease back has begun by 3.1 s and yaw, pitch and zoom are
back at the default pose (not zoom 1.0) by 3.0 + 0.8 s; input disable and the director cut
switch both work; the wreckage orbit settles at 2.6 m, pitch 35, looking straight at the
wreck, turning 20 degrees per second, and a camera gesture cancels it; a fake
`ImpactShake` in the group moves the camera's local origin to its offset in fight mode,
leaves the rig's own position alone, reads zero in workshop and menu modes, and returns
to zero when the source is freed. Pad: the left stick drives heading with the deadzone
rescaled and reads zero inside it, stick up is up the screen, A and the right trigger fire
exactly once per press, B and the left trigger hold secondary, START emits
`pause_requested` once, the right stick emits `camera_orbit` and the shoulders emit
`camera_pinch` above and below 1, the five tank mix cases, the tank heading integrates a
differential into a swing, the HUD hints appear and disappear with the pad and follow the
secondary label, the hints land on the button positions, and touch still drives with no
pad connected. Controller hints: an Xbox kind keeps A and B, four PlayStation kinds swap
to the cross and circle glyphs, a disconnect hides the hints, and the kind is remembered.

`Input.parse_input_event` needs a real input driver, so the test calls
`FightControls.handle_event` instead, which is the same seam `_input` uses.

## What the Swift side (agent S2) needs to do

Nothing in `Arena/**` can prove a controller actually reaches the embedded runtime, so
this is owed:

1. **Link `GameController.framework`** into the app target. Godot's iOS joypad driver is
   built on `GCController` and its connect/disconnect notifications; if the framework is
   not linked into the host, `Input.get_connected_joypads()` stays empty forever and every
   pad path here is dead code.
2. **`Info.plist`: `GCSupportsControllerUserInteraction = true`.** Without it the system
   treats the app as not controller aware. There is no entitlement for MFi or for
   Xbox/PlayStation pads on iOS 14 and later: they pair at the system level and any app may
   read them, so an entitlement file change should not be needed. Add
   `GCSupportedGameControllers` only if a specific profile has to be forced.
3. **Confirm the pad reaches Godot.** `FightControls.pad_seen_by_engine()` is the probe:
   if the shell's `settings` says `controller_connected` and that is false, this is broken.
   The one check I cannot run: with a pad paired, is
   `Input.get_connected_joypads()` non-empty inside the embedded host? If the embedded
   libgodot does not start its joypad observer (it may expect to own the `UIApplication`
   lifecycle, which it does not here), tell me and I will add a bridge driven override:
   `FightControls.set_pad_present(on)` already exists for exactly that, and R only needs to
   forward a new `pad_state` message to it.
4. **The pad Home button must not background the fight.** If it does, that is a shell
   level decision, not something this node can see.

Until 3 is confirmed, the desktop path is the only proven one:
`Godot --path Arena -- --roboteer-pad=on` with a pad plugged into the Mac.

## Known weaknesses

1. **This agent has still seen nothing.** The desktop window is the feel gate (spec section
   14) and this agent may not open one; the framing numbers above are computed, and the only
   eyes on them so far are the coordinator's review of a 1206 x 556 window, which produced
   the default zoom change. The draw calls are proven to execute without errors headless, but
   the actual sizes, spacing and contrast of the stick, buttons, pips and HUD have never been
   looked at. Expect a tuning pass.
2. **The ease back is 3.0 s plus a 0.8 s ease.** The spec's checklist phrase "after 3.1 s the
   yaw returns to 45" cannot be literally true given `CAM_EASE_BACK_S` is 0.8, so the test
   asserts the ease has begun at 3.1 s and that yaw is exactly 45 at 3.0 + 0.8 s.
3. **The look-at bias is inert at the current constants.** The clamp asked for (the frustum
   never leaves the floor) is strictly stronger than the bias at FOV 28: the visible ground
   footprint is wider than the 10 m floor at every zoom down to 0.55, so the limit is zero
   and the camera keeps aiming at the arena centre. It only starts to move below zoom 0.25.
   Two levers if the camera should actually follow the bots: relax the clamp so only the near
   half of the footprint has to stay on the floor (a change here), or lower `CAM_ZOOM_MIN`
   in `fight_types.gd` (R's file). Not changed unilaterally because the clamp was specified.
4. **Pinch and orbit fire together.** A two finger drag that also changes the spread emits
   both signals, which is correct but means a sloppy orbit drifts the zoom slightly. If that
   feels wrong on a device, add a dominance test (ignore the pinch until the spread changes
   by more than a few percent) rather than separating the gestures.
5. **A third camera finger is tracked but unused.** Pinch and orbit keep using the first two
   entries in the dictionary, whose order after an erase is insertion order, not screen
   order. Three finger gestures are not a Stage 3 requirement.
6. **No shipped font.** Open Sans at large sizes with an outline is legible but it is not the
   chunky face the art direction asks for. If a face is added later it must be free to
   redistribute and its licence recorded here.
7. **`bump` and `set_scrap` can drift** if R and B both report the same award. `set_scrap` is
   the resync.
8. **The stick zone ignores the safe area** on purpose. On a device with a large left inset
   in landscape the effective zone is slightly under 45 % of usable width.
9. **The desktop keyboard path is polled**, so at a low tick rate a very short Space tap
   could be missed if it lands entirely between two polls. The touch path is event driven
   and does not have this problem. The pad's fire is polled too, but on the physics tick at
   60 Hz, which is under the 80 ms a human press lasts at its shortest.
10. **PlayStation glyphs are letters.** See the settings section: the default font has no
   cross or circle glyph, so they render as X and O until a font that has them is shipped.
11. **No pad has been held.** The controller path is proven only by synthetic events fed
   through `Input.parse_input_event` headless. Button *mappings* in particular are a guess
   at Godot's normalisation: `JOY_BUTTON_A` is the bottom face button and should be Cross on
   a PlayStation pad, but nobody has pressed one. Deadzone, stick rates and the tank turn
   rate are all first guesses that want a hand on a real pad.
12. **Tank cannot pivot properly**, see the tank section: the Bot API takes a heading, not a
   turn demand, so a pure pivot is faked with a small throttle.
13. **A second pad is ignored.** Joypad 0 only.
