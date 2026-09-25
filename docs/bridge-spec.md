# Roboteer bridge spec (v1, Stage 1; v2 fight-control additions at the end)

The Swift shell and the Godot arena talk through ONE narrow, versioned, data-only contract
(brief §12). This file is the authority for both sides. Change it here first.

## Runtime facts (verified 2026-09-13)

- Embedding library: **SwiftGodotKit tag `v4.6.0`** (SPM: `https://github.com/migueldeicaza/SwiftGodotKit`,
  `kind = revision`, `dabb72ced0bc6b03114e0e31f743b5d889edc433`; the v4.6.0 TAG is unusable as a remote package because it declares a local-path SwiftGodot dependency). It pulls SwiftGodot (rev 48112dd) and a binary `libgodot-ios.xcframework`
  from `migueldeicaza/godot` release `v4.6.4` (libgodot patches on Godot 4.6). Device slice 172 MB static,
  simulator slice (arm64 + x86_64) 320 MB static. The README's "no simulator" note is stale from 4.4;
  the 4.6.4 xcframework SHIPS a simulator slice. Whether it runs on the sim is a Stage 1 measurement.
- Editor for authoring/exporting: Godot **4.6.3-stable** at `~/Applications/Godot.app/Contents/MacOS/Godot`.
  Headless pck export works WITHOUT export templates:
  `Godot --headless --path Arena --export-pack "iOS" <out.pck>` (preset "iOS" must exist in
  `Arena/export_presets.cfg`; `script_export_mode=0` keeps GDScript as text, 1 = binary tokens (verified on 4.6.3)).
- Xcode 27.0, iOS 27 SDK. Team `VQQCV6BB8R`, bundle id `com.radicraft.roboteer`, iPhone only
  (`TARGETED_DEVICE_FAMILY = 1`), `IPHONEOS_DEPLOYMENT_TARGET = 18.0`.
- Required target settings (from the SwiftGodotKitSamples project + Selig's write-up):
  `OTHER_LDFLAGS = "-lc++"`, link `MetalFX.framework`, `SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"`,
  the `.pck` in Copy Bundle Resources. No Catalyst. Portrait AND landscape allowed for now.

## Transport: the RoboteerHost singleton (changed 2026-09-13 after the spike)

`Roboteer/HostBridge.swift` defines `@Godot final class HostBridge: Object`, registered at scene level as
the engine singleton **`RoboteerHost`** (`Engine.registerSingleton`) via SwiftGodotKit's `initHookCb`
before the `GodotApp` starts. It carries two signals, each `(type: String, json: String)`:

- `message_from_host` emitted by Swift (`HostBridge.send(type:json:)`, main thread); GDScript connects.
- `message_to_host` emitted by GDScript (`Bridge.send`); Swift connects at registration time.

**Never call a Swift method from GDScript.** `@Callable` methods on Swift objects do not dispatch from
GDScript in SwiftGodot 0.75 / libgodot 4.6 (measured), which is also why SwiftGodotKit's own
`__swiftgodotkit_bridge__` node cannot deliver Godot -> Swift. Signals work both ways. The Bridge
autoload still falls back to that node if the singleton is absent, for Swift -> Godot only.

Each message is `(type, json)`: `type` snake_case message name, `json` UTF-8 JSON text (may be `"{}"`).
JSON-as-string keeps the contract inspectable, loggable and versioned, and avoids Variant type drift.

### Messages

| direction      | `type`         | payload |
|----------------|----------------|---------|
| Godot -> Swift | `arena_ready`  | `{"schema":1,"godot_version":"4.6.4","ticks_msec":<Time.get_ticks_msec()>}` sent once from the main scene's `_ready` after the bridge node is found |
| Swift -> Godot | `fight_config` | a `FightConfig` (below) |
| Godot -> Swift | `fight_result` | a `FightResult` (below) |
| Godot -> Swift | `arena_log`    | `{"level":"info|warn|error","text":"..."}` optional diagnostics, never required for correctness |

Rule: no live chatter mid-fight. Stage 1 sends one `fight_config`, gets one `fight_result`.

### Godot side (GDScript) pattern

`Arena/bridge.gd` is an autoload singleton named `Bridge` (the shipped file is the authority; the
sketch below shows the shape). It polls `Engine.has_singleton("RoboteerHost")` each frame until found,
connects `message_from_host`, and `send` emits `message_to_host` on the singleton:

```gdscript
extends Node
signal message_received(type: String, payload: Dictionary)
const BRIDGE_NODE := "__swiftgodotkit_bridge__"
var _host: Node = null

func _process(_dt: float) -> void:
    if _host == null:
        _host = get_tree().root.get_node_or_null(BRIDGE_NODE)
        if _host != null:
            _host.message_from_host.connect(_on_message_from_host)
            set_process(false)
            emit_signal("message_received", "bridge_attached", {})

func send(type: String, payload: Dictionary) -> void:
    if _host == null:
        push_warning("Bridge.send before attach: " + type)
        return
    _host.emit_message_to_host({"type": type, "json": JSON.stringify(payload)})

func _on_message_from_host(message: Dictionary) -> void:
    var type := str(message.get("type", ""))
    var parsed = JSON.parse_string(str(message.get("json", "{}")))
    var payload: Dictionary = parsed if parsed is Dictionary else {}
    emit_signal("message_received", type, payload)
```

When running the project in the desktop editor (no host), `_host` stays null; `send` warns and the
scene must still run. A `--headless` desktop run must not crash.

### Swift side pattern

```swift
@State var app = GodotApp(packFile: "arena.pck")   // renderingDriver "metal", method "mobile", display "embedded" are the defaults
GodotAppView(
    onReady: { handle in bridge.handle = handle },   // fires once the scene tree root exists
    onMessage: { dict in bridge.receive(dict) }      // main thread
)
.environment(\.godotApp, app)

// send
var d = VariantDictionary()
d["type"] = Variant("fight_config")
d["json"] = Variant(jsonString)
handle.emitMessage(d)

// receive
let type = String(dict["type"]) ?? ""      // SwiftGodot: String(Variant?) initialiser
let json = String(dict["json"]) ?? "{}"
```

Only ONE `GodotApp` may exist per process. Create it once (an `@State` on the root view or a
singleton) and never recreate it; navigating away should `pause()`/`stopDrawing()`, not destroy.

## FightConfig v1

```json
{
  "schema": 1,
  "seed": 123456789,
  "arena": "yard",
  "rules": { "duration_s": 90, "ko_count_s": 10 },
  "bots": [
    {
      "id": "player-1", "name": "Tinribs", "controller": "player",
      "chassis": "wedge", "drive": "4wd", "weapon": "flipper",
      "utility": ["srimech", "spare_battery"],
      "armour": {
        "front": { "material": "steel", "thickness": 3 },
        "sides": { "material": "hdpe",  "thickness": 2 },
        "rear":  { "material": "polycarbonate", "thickness": 1 },
        "top":   { "material": "titanium", "thickness": 2 }
      },
      "damage": { "wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 }
    },
    { "id": "ai-1", "name": "Scrapheap", "controller": "ai", "chassis": "box", "drive": "2wd", "weapon": "saw",
      "utility": ["srimech"], "armour": { "front": {"material":"steel","thickness":2}, "sides": {"material":"steel","thickness":2}, "rear": {"material":"steel","thickness":2}, "top": {"material":"steel","thickness":2} },
      "damage": { "wheels": [1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 } }
  ]
}
```

Enumerations (brief §5): chassis `wedge|box|pyramid|long_low|tall_tank|shell`; drive `2wd|4wd|6wd|tracks|omni`;
weapon `horizontal_spinner|vertical_spinner|flipper|lifter|crusher|axe|saw|ram|flamethrower|full_body_spinner`;
utility `srimech|rear_wedge|skirts|magnets|scoop|spare_battery|counterweight`;
material `steel|titanium|hdpe|polycarbonate`; arena `yard|grinder|drop_zone|furnace|crush|coliseum`.
Damage values are 0.0 (destroyed) to 1.0 (pristine).

## FightResult v1

```json
{
  "schema": 1,
  "outcome": { "type": "ko", "winner": "player-1", "loser": "ai-1", "at_s": 42.5 },
  "duration_s": 42.5,
  "judges": { "player-1": { "damage": 0, "aggression": 0, "control": 0 }, "ai-1": { "damage": 0, "aggression": 0, "control": 0 } },
  "damage": { "player-1": { "wheels": [1.0, 0.6, 1.0, 1.0], "weapon": 0.9, "armour": {"front":0.7,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 },
              "ai-1":     { "wheels": [0.0, 1.0], "weapon": 0.0, "armour": {"front":0.0,"sides":0.4,"rear":1.0,"top":1.0}, "drive": 0.3, "core": 0.2 } },
  "scrap": { "player-1": 340, "ai-1": 60 },
  "replay": { "seed": 123456789, "tick_hz": 60, "inputs": [] },
  "diagnostics": { "ticks_msec_at_config": 0, "ticks_msec_at_result": 0, "physics_ticks": 0, "echo": { "arena": "yard", "bot_count": 2, "seed": 123456789 } }
}
```

`outcome.type` is `ko|out_of_arena|judges|component_kill|timeout` (brief §6 win conditions; `timeout`
only if judges could not score, should not happen in the real game). `diagnostics.echo` exists so the
Stage 1 spike can prove the payload arrived intact: Godot copies `arena`, `bots.size()` and `seed` from
the config it received.

## FightResult v2 (additive, schema stays 1)

Added 2026-09-17 for the career progression system (brief v5 sections 3, 5 and 9.3; wave P agent
C). Four new top-level keys, ALWAYS present, nothing removed and nothing renamed, so `schema`
stays `1`: Swift tolerates a missing key, and a reader that has to ask whether a key exists is a
reader with a bug in it.

```json
{
  "hits":            { "player-1": {"landed": 14, "taken": 6}, "ai-1": {"landed": 6, "taken": 14} },
  "parts_lost":      { "player-1": [],
                       "ai-1": [ {"part": "weapon", "label": "Weapon", "state": "destroyed"},
                                 {"part": "wheel_rl", "label": "Rear left wheel", "state": "destroyed"} ] },
  "condition_start": { "player-1": { "wheels": [1.0,1.0,1.0,1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 },
                       "ai-1":     { "wheels": [1.0,1.0,1.0,1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 } },
  "scrap_breakdown": { "player-1": {"base": 120, "damage": 91, "survivor": 60, "flawless": 100, "total": 371},
                       "ai-1":     {"base": 120, "damage": 0, "survivor": 0, "flawless": 0, "total": 120} }
}
```

- **`hits`**: weapon hits, from the fight's own tallies (`weapon_hits`, spec section 8: a fire that
  produced damage inside 0.35 s made contact, counted once per fire). `taken` is the sum of the
  other machines' `landed`, which in a two bot fight is exactly the opponent's count.
- **`parts_lost`**: what went out during the fight, in the order the match report reads it: the
  weapon, the drive, the wheels, the armour faces, the core. `label` is the words a player reads
  ("Weapon", "Drive", "Front armour", "Rear left wheel", "Left track"); `part` is the condition key
  behind it. `state` is `destroyed` at zero condition, or `disabled` for a part that is still on the
  machine and not answering: a weapon `jammed` (condition gone) or `cooked` (electronics down), and
  a drive whose motors have burnt out at zero. A machine with no weapon fitted reports no weapon
  row, even though `Bot.weapon_fault()` calls it "jammed" for the button's sake.
- **`condition_start`**: the condition dictionary each machine STARTED the fight in, the same shape
  as `damage` (which is what it ended in) and as the config's own `damage` block. Career condition
  carries from match to match, so a report can only say what this match cost by comparing the two.
- **`scrap_breakdown`**: the career scrap lines, per bot. `total` is always the sum of the four
  lines. Every line is 0 when the fight carried no `rules.scrap`.

`FightConfig` gains one optional key to turn the ledger on:

```json
"rules": { "duration_s": 180, "ko_count_s": 10,
           "scrap": { "base": 120, "damage_full": 200, "survivor": 60, "survivor_min": 0.7, "flawless": 100 } }
```

`rules.scrap` is sent on career matches only. A quick fight, a side event, the test arena and the
ladder send none, and then nothing changes: `scrap[bot]` stays the legacy bolt total to the unit and
every breakdown line is zero. With `rules.scrap` present:

- `scrap[bot_id]` (v1) becomes `scrap_breakdown[bot_id].total`, so every existing reader keeps
  working and no shell code has to choose between two numbers.
- The ledger is derived from CONDITION, not from the bolt shower. Bolts still spawn and
  `scrap_awarded` still carries their legacy value for the fx and the haptics, but a collected bolt
  adds nothing to the tally.
- Live, the HUD's scrap bug shows `base + damage_full x damage fraction so far`, where the damage
  fraction is `1 - condition_total(opponent now) / condition_total(opponent at the start)`, clamped
  to 0..1. The survivor and flawless lines are decided at the bell and never shown running, because
  a number that can go down is not a tally.
- Survivor: own condition total at the bell at least `survivor_min` of what it started with.
  Flawless: WON and no wheel or track, weapon, drive, core or armour face at zero (dented does not
  cost it; lost does).
- Both machines get a breakdown. The AI's is data, not a payment; only the career decides what to
  bank, and it banks nothing on a loss or a draw (brief v5 section 3).

The maths is pure and lives in `Arena/fight/rules.gd` (`damage_fraction`, `damage_bonus`,
`survivor_bonus`, `flawless_bonus`, `any_part_zero`, `scrap_breakdown`, `parts_lost`, `part_label`,
`hits_from_tallies`), reads no rng and no clock, and is covered by `Arena/tests/scrap_test.gd`, so a
replay of a fight produces the same ledger the fight did.

## Fight control (v2 additions)

Added 2026-09-14 after the first device playtest ("no idea what the controls are ... no idea how to
move the camera"). Everything here is OPTIONAL: a host that sends none of it behaves exactly as before.

### `fight_control` (Swift -> Godot)

```json
{ "action": "pause" }
```

`action` is `pause`, `resume` or `quit`.

- **pause** freezes the SIMULATION and nothing else. `fight.gd` sets `SceneTree.paused`, which stops every
  `_physics_process` and `PhysicsServer3D` with it; `fight.gd`, the HUD, the touch controls and the `Bridge`
  autoload are `PROCESS_MODE_ALWAYS`, so the arena is still drawn, the HUD shows a small `PAUSED` mark and
  the bridge can still deliver the message that resumes. The touch controls are disabled and release every
  live touch. **No tick runs while paused**, so nothing is skipped or doubled: the recorded input stream and
  the result of a paused fight are bit for bit those of an unpaused run of the same seed and inputs
  (`Arena/tests/pause_test.gd` proves it).
- **resume** starts the clock again on the tick that would have been next.
- **quit** takes the existing abandoned path: `fight_state {"state":"abandoned"}`, no `fight_result`, the
  fight world torn down and the fight UI hidden. The host is expected to follow with a `workshop_config`.

`pause` outside a fight (in the workshop or menu view) is ignored. `fight_state` carries `paused` and
`resumed` alongside the existing `abandoned`.

Implementation note, because it is easy to get wrong: `PROCESS_MODE_ALWAYS` is INHERITED, so the fight
world under `$Stage` is explicitly put back to `PROCESS_MODE_PAUSABLE`. Without that the bots, the arena
hazards and the FX keep running their `_physics_process` while the physics server is off, their timers
age without a single body moving, and a paused fight ends a metre and a half from where the same fight
ended unpaused.

### `pause_requested` (Godot -> Swift)

```json
{ "tick": 412 }
```

Emitted when the pad's START button is pressed during COUNTDOWN or FIGHTING. The arena does NOT pause
itself: the shell shows its own overlay and replies with `fight_control {"action":"pause"}`. `tick` is the
simulation tick at the moment of the press, for logs only.

### `fight_config.coach` (Swift -> Godot, optional)

```json
{ "schema": 1, "seed": 1, "coach": true, "arena": "yard", "rules": { ... }, "bots": [ ... ] }
```

A top-level boolean. `true` draws the how-to-play callouts over the real controls: "DRIVE  slide your thumb
here" at the resting stick, "`<WEAPON WORD>`  tap" (or "hold") at the primary button, and "CAMERA  drag to
look, pinch to zoom" in the free right-middle area. They are shown through the countdown and the opening
seconds of the fight; each one fades the moment its input is first used, and all of them are gone after 8
seconds of FIGHTING. They are draw-only and never intercept a touch. `rules.mode = "test"` turns them on
whether or not the flag is present. Absent means false.

The weapon word comes from the fitted weapon's `kind` (the `kind` column of `Shared/parts.json`) and is the
same word the primary button and the pad glyph hint show:

| kind | word | worked by |
|---|---|---|
| `flipper` | FLIP | tap (gas pips around the button) |
| `spinner` / `drum` / `saw` / `fbs` | SPIN | hold (spin-up ring around the button) |
| `axe` | SWING | tap |
| `crusher` | CLAMP | hold |
| `lifter` | LIFT | hold |
| `flame` | FIRE | hold |
| `ram` | RAM | tap (passive weapon; the button does nothing) |

### `stage_camera` (Swift -> Godot)

```json
{ "orbit": [24.0, -8.0], "pinch": 1.06 }
```

Either key, or both. `orbit` is a drag delta in **screen points**, +x right, +y down; `pinch` is a factor,
above 1 moves the camera in. The arena converts points to viewport pixels (viewport size against the
1206 x 556 design size) so a forwarded gesture feels exactly like a touch, then calls the camera rig's
`orbit(Vector2)` and `pinch(float)` with the rig's existing clamps and ease.

Why the shell sends this at all: on the workshop and menu screens the SwiftUI navigation container
swallows every touch before the embedded Godot view sees it, so the shell captures the gesture itself in
the clear area and forwards the deltas.

**Stage screens only.** Ignored in a fight (the player's own thumbs own that camera through
`FightControls`) and in a replay. The rig's own `_unhandled_input` workshop path is unchanged and is
still what the desktop QA build uses. The menu camera is a cinematic drift and the rig ignores gestures
in that mode by design, so on a menu screen the message routes but does nothing.

### `workshop_config.frame` (Swift -> Godot, optional)

```json
{ "mode": "workshop", "frame": 0.34, "bot": { ... } }
```

A float 0 to 1 (clamped to 0.12 to 0.88): where across the screen the stage centre should project, so a
SwiftUI panel can own one side and the bot still be framed in what is left. `0.5`, and absent, is centred
and is exactly the old behaviour. Applied as `Camera3D.h_offset = (0.5 - frame) * 2 * distance *
tan(fov / 2) * aspect`, eased at a constant rate (0.35 s to cross the whole screen) so switching screens glides. **Fight mode ignores it.**

### `workshop_config.shot`, `.opponent`, `.focus` (Swift -> Godot, optional, wave A 2026-09-24)

```json
{ "mode": "menu", "shot": "faceoff", "bot": { ... }, "opponent": { ... } }
{ "mode": "workshop", "shot": "garage", "frame": 0.3, "bot": { ... } }
{ "mode": "workshop", "shot": "part", "focus": "weapon", "frame": 0.3, "bot": { ... } }
```

Opt-in stage framings from `docs/look/reference-study.md` 3.2, drawn by the stage's own camera
(`Arena/workshop/stage_director.gd`). **Absent `shot` is exactly the old behaviour**: the camera rig's
`menu` / `workshop` camera has the picture and nothing below applies. `mode` keeps its meaning for the
rig and the turntable; `workshop_ready` is answered as before.

| `shot` | lens | picture |
|---|---|---|
| `showroom` | 50 mm | M1: the machine alone, centred, turning at 5 deg/s, slow three-sine drift |
| `faceoff` | 50 mm | M2: the machine large and low on the left in warm light, `opponent` across the floor on the right in cold light. The platform retracts into the floor and the machine parks facing the opponent. **No `opponent` (or `{}`) falls back to `showroom`.** |
| `garage` | 40 mm | G1: the machine on the lit turntable at `frame` (default 0.31), drag to orbit (`stage_camera`), the turntable pauses on touch and resumes after 4 s |
| `part` | 70 mm | G2: `focus` (`weapon`, `drive`, `armour`, `chassis`, `utility`, `paint`) framed with shallow depth of field; the category's bodies slide out of the machine (presentation only, frozen) |

- `opponent` is a bot config exactly like `bot`. It is rebuilt only when it changes, so re-sending it on
  every builder edit costs nothing.
- Moving between shots takes 750 ms (in-out cubic) with the focus pulled on the same curve.
- `stage_camera` orbit and pinch drive the stage camera while a `garage` or `part` shot is up (the rig
  still receives them too, harmlessly: its camera is not current). The menu shots ignore gestures.
- After 6 s with no gesture, `showroom` and `faceoff` fire a test-fire spark off the weapon every 9 to
  14 s (`StageDirector.attract_cue`).
- A fight (`fight_config`), a `workshop_config` with no `shot`, or the stage going dark hands the picture
  straight back to the rig's camera.
- Desktop QA: `--roboteer-shot=faceoff|showroom|garage|part:weapon` on `res://qa/stage_preview.tscn`
  (add `--roboteer-slice` for the proving slice machines).

### Knockout count arming (Godot side, no message)

Recorded here because it changes what a `fight_result` can say. The knockout count on the PLAYER's
machine does not start until the player has asked for any drive in this fight, or
`FightRules.PLAYER_KO_GRACE_S` (10 s) after the countdown ends, whichever comes first. The opponent's
count is unchanged. The rule is a pure function of the recorded input stream and the simulation clock
(`FightRules.ko_count_armed`), so a replay arms on exactly the tick its fight did.

While such a count is running on the player, the HUD adds a white line "DRIVE TO STOP THE COUNT" under
the count and the resting stick pulses until the player moves.

### Replay row `fire` is the LEVEL (changed 2026-09-14)

`FightResult.replay.inputs` rows are `[tick, heading.x, heading.y, fire, secondary]`. `fire` used to be
the tap EDGE, true for one tick per press. It is now the LEVEL, true for as long as the button is held;
`bot.apply_input` derives the edge from it (`fire and not _fire_was`) and hands the weapon both, which is
what it always did. Nine of the ten weapons are worked by holding (a spinner spins up, a crusher closes, a
flamethrower burns) and reading only the edge meant a held thumb reached them for exactly one tick and no
spinner ever span. Determinism is unaffected: a row still drives the same tick the same way, so old logs
replay as recorded and `Arena/tests/determinism_test.gd` is unchanged.

### Default fight framing (Godot side, no message)

Changed 2026-09-14 for the same reason: at the old fixed framing (a constant fraction of the arena fit
distance) the machines were about 20 pt tall on a 402 pt screen, the whole floor fitted and both bots were
dots. The resting fight camera now frames the BOTS: it sits at the distance that fits both machines plus about
one bot length of margin on every side, clamped between a near limit (a 0.9 m machine at 30 % of the
viewport height) and the old walls-on-screen fit. Above that sits a **player-priority floor**: the player's
own machine may never project smaller than 10 % of the viewport height, so at the opening bell (8 m apart)
the camera stops pulling back and holds that distance instead of fitting the pair.

**Changed again 2026-09-16 (brief v4 §5, agent G4): it TRACKS THE PLAYER.** The aim is no longer the
midpoint of the pair. It is the player's own chassis plus a lead of 25 % of the vector to the opponent,
capped at 1.2 m and flattened to the floor, eased with the same `SUBJECT_EASE_S`; and after the ease it is
leashed so the player never projects further than 30 % of the frame from its centre. The distance fits the
pair only while the opponent is inside 4 m; past that the opponent is clamped to 4 m for the fit, so the
zoom HOLDS rather than pulling back until both machines are dots. So `is_player_floored()` now means the
camera is holding for EITHER reason (the opponent past 4 m, or the 10 % floor binding), which is the same
thing it always meant to the HUD. One scripted move exists, `endgame_reveal()`: 0.6 s back to the arena fit
at the endgame and 0.8 s to tracking again, no input, no cut. Pinching out still returns the old composed
whole-arena shot, aim included, and letting go returns the tracking camera. While the camera is
holding (`CameraRig.is_player_floored()`) the opponent can be outside the frame, and the HUD then draws a
small white outlined arrow at the screen edge along the direction to it with its name under it, until it is
back in view. As the machines close, the pair fit comes back inside the floor and frames both as before. Distance and look point both ease, so a machine being thrown or flipping never snaps
the camera. Yaw (`FightTypes.CAM_YAW_DEG`, -135: behind the player's spawn) and pitch 50 are unchanged and
nothing in the tracking ever turns the camera, so `fight.gd._heading_to_world()` keeps mapping the stick to
the world the same way all fight long. Pinch and orbit still work on top of it with the same
clamps, and the rig still eases back after `CAM_EASE_BACK_AFTER_S`. `CameraRig.DEFAULT_ZOOM` is now only
the fallback used when there are no bots to frame.

### Test arena chrome (`rules.mode = "test"`)

The shell owns the top 60 pt of the screen there for its own Back / TEST ARENA / Reset row, so the HUD
shows **no clock** (the spec never had one in the sandbox) and puts the names and the scrap counter below
that band. The Godot test overlay no longer draws HIDE or RESET buttons of its own: the shell's Reset is
the only one, and it reaches the arena as `test_reset`. The overlay's readout starts below the band too.

### Screen regions the arena keeps clear

- **Top right**: a 64 x 64 pt square inside the safe area, for the shell's own pause button. The HUD's
  scrap counter is inset by that much plus a further 12 pt of clearance (76 pt effective) and right aligned
  against it, so its digits never sit against the button; `FightHud.reserved_corner()` returns the reserved
  64 pt rectangle in viewport pixels.
- **During COUNTDOWN** the stick and both buttons are drawn at 60 % alpha and take no input, so the coach
  callouts point at something rather than at empty corners; they fade to full at the bell. LOADING and
  RESULT draw nothing.
- **Bottom left**: the resting drive stick, about 70 pt in from the safe area on both edges, radius 60 pt,
  with a "DRIVE" label under it. Nothing else of the shell's may go there.

## Stage 1 acceptance (brief §15)

The spike is done when, on the iPhone 17 simulator AND (when the phone is plugged in) on the device:

1. The SwiftUI screen shows the embedded Godot view rendering a grey cube on a grey floor, lit, at the
   near-orthographic isometric default framing (camera pitch ~50 degrees, yaw 45 degrees, orthographic or
   long-lens perspective).
2. Tapping "Send fight" hands the hardcoded `FightConfig` to Godot and the screen shows the returned
   `FightResult` JSON with `diagnostics.echo` matching the config.
3. The screen shows, and the app logs via `Logger(subsystem: "com.radicraft.roboteer", category: "spike")`:
   time from process start to `onReady`, to `arena_ready`, and config->result round trip (ms);
   physical memory footprint (`task_vm_info.phys_footprint`) sampled at ready and 5 s later;
   the app binary size is measured from the device build's `.app` (`du -sk` of the bundle and of the
   executable) and recorded in `docs/stage1-results.md`.
4. Neither side crashes on backgrounding and returning, or on rotating.
