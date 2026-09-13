# Stage 3 spec: one complete fight (Wedge + Flipper, The Yard)

Brief §15 Stage 3: "One chassis (Wedge), one weapon (Flipper), one arena (The Yard), one opponent, in
Godot. Real physics, joint-failure damage, bolt showers with magnetism and the pitch ramp, all four win
conditions, both control thumbs, gesture camera, haptics, 90-second timer. This stage proves or kills the
design." Everything below serves that sentence. Read `docs/brief-v3.md` §2, §5, §6, §7, §11, §12 and
`docs/bridge-spec.md` first. Art target: `docs/stage2-art-direction.md` and `Art/direction/*.png`.

Locked for the whole app (decided 2026-09-13): **landscape only**, iPhone only. Twin-thumb driving needs
landscape and the shell must not rotate between garage and arena.

## 0. World scale and layers

- Units are metres, +Y up. The Yard floor is **10 x 10 m** centred on the origin, floor top at y = 0.
  Low walls 0.45 m high, 0.2 m thick, along the edges. Anything outside the walls or below y = -1 is out.
- A bot is about **0.9 m long, 0.6 m wide, 0.18 m tall** (wedge), mass about **45 kg** total.
- Fixed physics tick **60 Hz** (`physics/common/physics_ticks_per_second = 60`), Jolt.
- Collision layers: 1 arena static (floor, walls), 2 bot parts (attached), 3 debris (detached parts), 4 hazards,
  5 out-of-arena sensor. Bot parts collide with 1, 2, 3, 4. Debris collides with 1, 2, 3. Bolts are not bodies.
- Spawn points: player at (-3.2, 0.25, -3.2) facing +X+Z, opponent at (3.2, 0.25, 3.2) facing the player.

## 1. File map and ownership (five agents, disjoint directories)

| owner | path | contents |
|---|---|---|
| shared, written first | `Arena/fight/fight_types.gd` | constants, enums, material table, thresholds, input record shape. Read-only for everyone. |
| P (physics) | `Arena/bot/**`, `Arena/arena/**` | bot assembler, procedural part meshes, joints, damage model, wheels, flipper, srimech; The Yard scene, spike hazard, OOA sensor |
| C (controls) | `Arena/ui/**` | virtual stick, weapon buttons, HUD, touch routing, camera rig |
| B (feel) | `Arena/fx/**`, `Arena/audio/**`, `scripts/gen-sounds.py` | bolt shower, collect pitch ramp, sparks, impact sounds, haptic messages, scrap counter animation hooks |
| R (rules) | `Arena/fight/**` (except fight_types.gd), `Arena/ai/**`, `Arena/tests/**` | fight orchestrator, state machine, win conditions, judges, AI opponent, result builder, replay recorder, headless tests |
| S (Swift) | `Roboteer/**`, `Roboteer.xcodeproj` | landscape-only app, FightView hosting Godot full screen, fixture config, result sheet, haptics player, safe-area insets |

`Arena/main.tscn` (Stage 1 cube) stays as the spike scene; the main scene becomes `res://fight/fight.tscn`
(R changes `project.godot` run/main_scene; nobody else edits project.godot except P adding physics layer
names and the 60 Hz tick, coordinated by doing it in `fight_types.gd` comments and letting R apply it).

## 2. Contract: FightConfig additions for Stage 3

The Stage 1 `FightConfig` is unchanged. Stage 3 adds one optional top-level key from Swift:

```json
"presentation": { "safe_area_px": { "left": 0, "top": 0, "right": 0, "bottom": 0 }, "haptics": true },
"debug": { "opponent_ai": "normal" }
```

`safe_area_px` is in Godot window pixels (points times screen scale). `debug.opponent_ai` is
`normal|idle|charge` for QA (idle never moves, charge drives straight at the player). Both bots in the
Stage 3 fixture are `chassis: "wedge", drive: "4wd", weapon: "flipper", utility: ["srimech"]`, player
armour steel front / hdpe sides / polycarbonate rear / titanium top, opponent all steel.

## 3. Contract: new bridge messages (Godot -> Swift), presentation only

| type | payload | rule |
|---|---|---|
| `haptic` | `{"kind":"tick\|impact_light\|impact_heavy\|flip\|ko_tick\|bell"}` | one-way, coalesced to at most 30 per second on the Godot side; never affects simulation. This is the single sanctioned exception to "no live chatter" because the phone's haptic engine is only reachable from Swift. |
| `fight_state` | `{"state":"countdown\|fighting\|result"}` | sent on state change so the shell can show/hide its own chrome |

`fight_result` is sent exactly once when the fight resolves, then the arena freezes physics and leaves the
camera free for the wreckage orbit.

## 4. Bot API (P owns, everyone else calls)

`res://bot/bot.tscn`, root `Bot` (Node3D) with script `bot.gd`:

```gdscript
class_name Bot extends Node3D
signal damage_event(info: Dictionary)   # see §6, emitted in _physics_process
signal part_detached(part: String)       # "wheel_fl" etc, "armour_top", "weapon"
signal inverted_changed(is_inverted: bool)
signal weapon_fired()

var bot_id: String
var team: int                    # 0 player, 1 opponent
var chassis: RigidBody3D         # the body everything hangs off; position = bot position
var gas_charges: int             # flipper charges left (start 8)
var livery: Color

func setup(bot_config: Dictionary, team_index: int, rng: RandomNumberGenerator) -> void
func apply_input(inp: Dictionary) -> void   # {"heading": Vector2, "fire": bool, "secondary": bool}; called by R every physics tick BEFORE the step
func is_inverted() -> bool
func is_immobile() -> bool       # chassis speed < 0.15 m/s for the last 0.5 s (rolling window kept by the bot)
func condition() -> Dictionary    # exactly the FightConfig "damage" shape, current values
func weapon_height_band() -> String   # "floor" | "mid" | "high" for the HUD readout
func front_edge_height() -> float     # metres, the wedge lip's current clearance
func opponent_relative() -> Dictionary # filled by R each tick: {"position": Vector3, "distance": float}; AI/hud use
func freeze() -> void            # RESULT state: bodies to sleep, motors off
```

Assembly (all procedural, no imported meshes in Stage 3; ArrayMesh with flat normals, or CSG baked to
mesh, plus ConvexPolygonShape3D):
- **Chassis**: wedge = box 0.9 x 0.14 x 0.6 with the front 0.35 m cut down to a lip 0.02 m above the floor.
  Mass 22 kg, centre of mass slightly rearward and low. Livery colour on the hull.
- **Wheels**: 4 x CylinderMesh radius 0.11, width 0.06, 16 sides, black. Each a RigidBody3D (2.5 kg) on a
  **HingeJoint3D** (axis = wheel axle) with motor enabled. Drive = per-side target angular velocity from
  the input heading (arcade: heading direction sets desired yaw, magnitude sets throttle; the bot turns
  toward the stick at `TURN_RATE_4WD` rad/s by differential wheel speeds). Physics material friction 1.2
  on wheels, 0.6 floor. If motorised hinges prove unstable under Jolt, the fallback is chassis-applied drive
  forces at wheel contact points with the wheel bodies kept on breakable joints purely for detachment and
  the visible handling penalty; document which was used.
- **Flipper**: arm = box 0.5 x 0.03 x 0.4 hinged at the wedge lip (HingeJoint3D, limits 0 to 80 degrees,
  motor). `fire`: if gas_charges > 0 and arm at rest, set motor target velocity +25 rad/s with max impulse
  high for 0.12 s, then -8 rad/s to return; charge consumed; `weapon_fired` emitted; cooldown 0.7 s.
  A flip that gets under the opponent's chassis must launch a 45 kg bot about 0.6 m into the air.
- **Armour panels**: 4 thin boxes (front lip plate, left+right side plates as ONE "sides" pair sharing a
  condition value, rear plate, top plate), each a RigidBody3D (1 to 3 kg by material) attached with a
  **Generic6DOFJoint3D** fully locked. Panel colour: steel brushed grey-blue, titanium dark graphite,
  hdpe = livery colour, polycarbonate translucent light grey (alpha 0.6). Material must be visible.
- **Srimech**: a visual arm on the top plate; `secondary` while inverted applies an upward impulse at one
  side plus a roll torque to right the bot (1.2 s cooldown); `secondary` while upright is a handbrake
  pivot (lock one side's wheels for a tight turn).
- **Control core**: no body; a condition value on the chassis exposed once the top panel is gone.

## 5. The Yard (P owns) `res://arena/yard.tscn`

Floor (StaticBody3D, BoxShape, flat grey albedo 0.55 with a subtle 1 m grid line texture generated in
code or a second thin mesh), four low walls (StaticBody3D, albedo 0.35, with a yellow/black chevron strip
on top made from a striped material, as in the arena render), one **spike patch** 1.6 x 1.6 m at the
centre: 9 spikes that rise 0.25 m for 1.2 s every 6 s (timer runs on the physics tick, phase from the
seed) and deal damage to any part body touching them while risen (Area3D on layer 4 reporting bodies; the
damage goes through the same `damage_event` path with attacker "arena"). **OOA sensor**: an Area3D on
layer 5 covering everything outside the walls and below y = -1; R listens to it. Two spawn markers.
Lighting: DirectionalLight3D key from top-left, shadows on, WorldEnvironment flat grey-blue background
(no sky), ambient 0.4, SSAO off (mobile). Camera is NOT in this scene (C owns it).

## 6. Damage model (P owns), brief §6 "damage is joint failure"

Every attached part body (wheels, flipper arm, panels, chassis) overrides `_integrate_forces(state)` and
reads contact impulses (`state.get_contact_count()`, `get_contact_impulse(i)`, `get_contact_collider(i)`).
For each contact with impulse `J` above `BREAK_MIN[part]`:

```
severity = clamp((J - BREAK_MIN) / (BREAK_MAX - BREAK_MIN), 0, 1) * MATERIAL_FACTOR[material][source]
condition[part] -= severity
```

`source` is `impact` (any bot part or wall), `hazard` (spike). Material factors from brief §5.5, table in
`fight_types.gd` (steel transmits shock: impact factor 1.0; titanium 0.7; hdpe absorbs 0.5; polycarbonate
0.85; wheels and the flipper arm use 1.0). The attacker is the other bot if the collider belongs to it, else
"arena"; the attacker also gets credited for arena damage if it touched the victim in the last 2 s
(R keeps that "last toucher" fact from damage_events and contacts; P just reports the collider).

When a part's condition reaches 0: panels and wheels **detach** (free the joint, reparent under
`/root/Fight/Debris`, set layer 3, keep the body; dull grey tint applied to the detached part so it reads as
debris, brief §6 readability rule); the flipper **jams** (stays attached, cannot fire); the chassis with no
top plate exposes the core: chassis impacts then reduce `core`; core 0 is a component kill.

`damage_event` payload:

```gdscript
{"attacker": "player-1" | "ai-1" | "arena", "victim": "ai-1", "part": "armour_front", "severity": 0.35,
 "position": Vector3, "impulse": 123.4, "detached": false, "tick": 1234}
```

Scrap for the event is decided by R (not P): `scrap = round(severity * 40)`, doubled if `detached`.
This scrap value is also the bolt count B spawns (a scrape sheds 3 to 4, a panel loss sheds about 30).

## 7. Determinism (everyone)

- Gameplay state changes only in `_physics_process` or code called from it. Presentation (bolts, sparks,
  audio, HUD tweens, camera) only in `_process` and never feeds back.
- One `RandomNumberGenerator` seeded from `config.seed`, owned by R, passed to bots and AI; nothing
  else calls `randf` in gameplay code. Presentation may use its own unseeded RNG.
- R samples the player's controls ONCE per physics tick into an input record and calls
  `apply_input` on both bots. The record is appended to the replay log as
  `[tick, heading.x, heading.y, fire ? 1 : 0, secondary ? 1 : 0]`; the AI's input is not logged, it is
  regenerated from the seed on replay.
- `Arena/tests/determinism_test.gd` runs the same fixture twice headless with a scripted input list
  and asserts both chassis transforms and both condition dictionaries match at tick 1800.

## 8. Fight flow and rules (R owns) `res://fight/fight.tscn`, `fight.gd`

Node tree: `Fight` (Node3D) -> `Arena` (instance of yard), `Bots` (two Bot instances), `Debris` (Node3D),
`CameraRig` (C), `HUD` (C, CanvasLayer), `FX` (B). R instantiates and wires all of them.

States: `LOADING` (scene ready, waiting for `fight_config`) -> `COUNTDOWN` (3, 2, 1, FIGHT over 3 s,
bots frozen) -> `FIGHTING` (timer 90 s counting down in HUD) -> `RESULT` (freeze, send `fight_result`).

Win conditions (brief §6):
1. **Knockout**: a bot `is_immobile()` for 10 consecutive seconds. The HUD shows the count; movement resets it.
   Immobile means the chassis is not moving; an inverted bot that cannot self-right counts down too.
2. **Out of the arena**: the OOA sensor reports a bot chassis. Immediate.
3. **Judges' decision**: at 0:00, per bot: `damage` = total condition removed from the opponent (0..10
   scaled: 2.5 condition points = 10), `aggression` = seconds spent within 1.5 m of the opponent while
   moving toward it plus 1 per weapon fire that made contact (scaled so 45 s = 10), `control` = seconds the
   opponent spent airborne or inverted within 2 s of your contact plus seconds the opponent spent on the
   spike patch after your push (scaled so 15 s = 10). Higher total wins; tie goes to damage, then to
   aggression.
4. **Component kill**: a bot's `core` reaches 0.

`outcome.type` in the result: `ko | out_of_arena | judges | component_kill`. `at_s` = fight time.

FightResult (bridge-spec v1) is built by `result_builder.gd`: outcome, duration, judges (always filled, even
on a KO, from the tallies at that moment), damage = `condition()` of both bots, scrap totals per bot from the
event tally, replay `{seed, tick_hz: 60, inputs: [...]}`, diagnostics with the echo. Sent once.

## 9. AI opponent (R owns) `res://ai/opponent_ai.gd`

Runs in `_physics_process` from R with the shared rng. Produces a BotInput dictionary. Behaviour:
- `approach`: drive toward a point 0.5 m short of the opponent's chassis, preferring to attack its side or
  rear (choose the flank with the larger angle to the opponent's facing); heading magnitude 1.
- `strike`: when its own front edge is within 0.45 m of the opponent's chassis and roughly facing it, fire.
- `recover`: when inverted, press `secondary` once the bot is nearly still; when a flip fails twice, drive
  in reverse to rock off a wall.
- `avoid`: when the spike patch is about to rise (within 1 s) and it is within 1.2 m of the patch, steer away.
- jitter: every 0.5 s add a small heading noise from rng so two AI bots never look scripted.
- `debug.opponent_ai`: `idle` returns zero input; `charge` always drives straight at the player and fires
  on proximity.

## 10. Controls and HUD (C owns) `res://ui/controls.tscn`, `hud.tscn`, `camera_rig.tscn`

Landscape. Touch routing on a full-screen Control:
- **Left thumb, floating stick**: a touch that begins in the left 45 % of the screen (and not on a button)
  spawns a stick centred at the touch point (base radius 60 pt, knob 28 pt); heading = knob offset
  normalised to a 60 pt throw; released = zero. Sets `controls.heading`.
- **Right thumb, primary** (weapon): a 92 pt circular button at bottom-right inset by the safe area
  and 24 pt; tap = fire (flipper). Shows gas charge pips around it. `controls.fire` is edge-triggered
  (true for exactly one physics tick; C exposes `consume_fire()` for R).
- **Right thumb, secondary**: a 68 pt button above-left of primary; hold = handbrake pivot when upright,
  press = self-right when inverted; label changes with the bot's state.
- **Camera gestures**: any touch that did not start on the stick or a button is a camera touch. Two camera
  touches: pinch distance -> zoom, centroid drag -> orbit (x) and tilt (y). One camera touch does nothing.
  Driving is unaffected throughout (the stick keeps its own touch index).
- HUD (CanvasLayer, respects `safe_area_px`): timer top centre (mm:ss, turns red under 10 s), scrap counter
  top-right with a rolling number and the overshoot animation hook `bump(amount)` that B calls, KO count
  centre ("KNOCKOUT COUNT 7") when active, height readout bottom-centre in plain words ("Your wedge:
  floor. Their flipper: mid.") from `weapon_height_band()` and `front_edge_height()`, countdown 3 2 1 FIGHT,
  result banner ("KNOCKOUT", "OUT OF THE ARENA", "JUDGES DECISION", "CORE DESTROYED") plus winner name.
  Type: a chunky bitmap-style font is fine but the arena HUD is full colour, not the GBC chrome.
  No em dashes in any string.
- **Camera rig** (`camera_rig.gd`, Camera3D perspective FOV 28 degrees): default yaw 45, pitch 50, distance
  computed each frame so the whole 10 m floor plus walls fits the current viewport (aspect-aware); pinch
  zoom factor clamped to [0.55, 1.0] of that distance (1.0 = walls always on screen, the brief's rule);
  orbit free in yaw, pitch clamped 20 to 70 degrees; after 3 s with no camera input ease back to default
  over 0.8 s (cubic). When zoomed in the look-at point biases toward the midpoint of the two bots. In
  RESULT the rig performs a slow 20 degrees/s orbit around the loser's wreckage until the user touches
  (open question 4: the director cut; the rig exposes `set_director_cut(enabled)` so it can be A/B tested).

## 11. Feel: bolts, audio, sparks, haptics (B owns) `res://fx/fx.tscn`

- `BoltShower` (MultiMeshInstance3D, 120 instances of a small gold hex-nut mesh, emissive gold, each
  spinning): `spawn(position: Vector3, count: int, target_getter: Callable)`; when count exceeds free
  instances spawn fewer, larger bolts (scale 1.6). Per bolt: launch velocity in a cone (2 to 5 m/s, up-biased),
  gravity 9.8, one floor bounce (restitution 0.4) computed analytically, scatter delay 250 ms randomised
  plus or minus 90 % per bolt, then magnet pull with acceleration `k / max(distance, 0.3)` toward the
  target chassis position, speed capped at 12 m/s, arrival within 0.25 m -> `collected(target_id)` signal.
  All in `_process`. Visual size 0.05 m, tint gold `#f2c14e`, never grey.
- `CollectAudio`: on each collect play `bolt_collect.wav` with `pitch_scale` rising one semitone
  (x 2^(1/12)) per consecutive collect, reset to 1.0 after 380 ms without a collect, cap at +24 semitones.
- Haptics: on collect send `haptic tick` (coalesced 30/s); on damage_event severity < 0.3 `impact_light`,
  else `impact_heavy`; on weapon_fired `flip`; KO count `ko_tick` per second; result `bell`.
- Sparks: GPUParticles3D one-shot at damage_event positions (orange-white, 0.3 s), a continuous small
  emitter on risen spikes. Detached-part puff of grey dust.
- Sounds: `scripts/gen-sounds.py` (numpy + scipy present, python3.9; output 44.1 kHz 16-bit mono WAV)
  generates `Arena/audio/bolt_collect.wav`, `impact_light.wav`, `impact_heavy.wav`, `flipper_fire.wav`
  (pneumatic hiss then clunk), `wheel_off.wav`, `panel_off.wav`, `motor_loop.wav` (drive hum, pitch follows
  throttle), `countdown_tick.wav`, `bell.wav`, `ko_tick.wav`, `spikes.wav`. These are placeholders for
  Stage 3 feel testing; recorded or sampled sounds replace them later.
- HUD hooks: B calls `hud.bump(scrap_amount)` when bolts land (C exposes it); B listens to R's
  `scrap_awarded(bot_id, amount, position)` signal to spawn the shower.

## 12. Swift (S owns)

- Project becomes landscape only (`UISupportedInterfaceOrientations` = landscape left + right, and the
  same iPhone key); status bar hidden on the fight screen.
- `FightView`: full-screen `GodotAppView` ignoring safe areas (Godot draws under the notch; the HUD keeps
  clear via `safe_area_px`), sends the Stage 3 fixture `fight_config` (add `presentation` with the real
  safe-area insets times `UIScreen.main.scale`, and `debug.opponent_ai` from a launch argument
  `-opponentAI idle|charge|normal` for QA) on `arena_ready`; listens for `fight_state` and `fight_result`;
  on result presents a sheet: outcome, winner, per-bot damage summary, scrap, "Back to garage" (which
  pauses and stops drawing the Godot view and returns to a root menu).
- Root menu (temporary, plain SwiftUI, GBC four greens from `docs/stage2-art-direction.md`): "Fight",
  "Bridge spike" (the Stage 1 screen kept for measurements).
- Haptics: `HapticsPlayer` maps `haptic` messages to `UIImpactFeedbackGenerator` (.light for tick,
  .medium for impact_light, .heavy for impact_heavy, .rigid for flip) and `UINotificationFeedbackGenerator`
  for bell; prepare generators on fight start; ticks throttled to 30/s.
- Keep the process-single `GodotApp`. Never recreate it.

## 13. Acceptance (measured on the iPhone 17 simulator by the main session)

1. Fight runs end to end from tap "Fight" to the result sheet, 60 fps in the sim's Debug build or close.
2. Each of the four win conditions can be produced (`-opponentAI idle` + drive them out for OOA; ram them
   into the spikes and flip for damage; leave them for judges; component kill via repeated flips into
   walls or a debug config with low thresholds).
3. A flipper throw launches the opponent visibly; the landing sheds bolts that scatter, pause, then stream
   back with the rising pitch. Wheels and panels detach and stay as grey obstacles.
4. Camera gestures never disturb driving; the camera eases back after 3 s.
5. Determinism and rules tests pass headless (`scripts/test-arena.sh` runs them all).
6. Result JSON validates against bridge-spec v1 and the Swift sheet shows it.

## 14. Desktop QA mode (added 2026-09-13 after the Stage 1 measurement)

Finding: the prebuilt libgodot simulator slice has no Metal driver and the embedded display server has no
working OpenGL path, so **the arena renders on a physical iPhone only**. On the simulator the Godot
runtime, GDScript and the bridge all work with `displayDriver: "headless"` and the dummy renderer, which
proves the contract but shows a black view. Therefore the visible test loop for everything in `Arena/` is
the **desktop Godot runtime on the Mac**: `~/Applications/Godot.app/Contents/MacOS/Godot --path Arena`
opens a window, and the main session takes screenshots of it.

Every Stage 3 agent must make its work testable that way:
- `project.godot`: `input_devices/pointing/emulate_touch_from_mouse = true` so a mouse drag is a touch.
  Desktop window size 1206 x 556 (an iPhone 17 landscape at 1x points ratio, scaled) with
  `display/window/size/viewport_width = 2412`, `viewport_height = 1112`, `window_width_override = 1206`,
  `window_height_override = 556`, stretch mode `canvas_items`, aspect `expand`.
- The fight scene must **auto-start without a host**: if no bridge attaches within 60 frames, R loads
  `res://fight/fixtures/stage3_config.json` (the same fixture Swift sends, with `presentation.safe_area_px`
  all zero) and runs the fight exactly as if it had arrived over the bridge. A `--` argument
  `--roboteer-ai=idle|charge|normal` (read from `OS.get_cmdline_user_args()`) overrides `debug.opponent_ai`.
- Camera gestures need desktop equivalents for QA only: `InputEventMagnifyGesture` = pinch,
  `InputEventPanGesture` = two-finger drag, and the keys `Q`/`E` orbit, `R`/`F` tilt, `-`/`=` zoom.
- Driving needs a keyboard equivalent for QA only: WASD or arrow keys = stick, Space = weapon,
  Shift = secondary. The keyboard path produces the same input record as the touch path and is only read
  when `OS.has_feature("pc")`.
- Headless tests (`scripts/test-arena.sh`) remain the automated gate; the desktop window is the feel gate.

Physical-device verification of the embedded arena is owed and will be done when the owner's iPhone is
connected again (the spike's `-autoSendFight` flag makes it a one-tap check).
