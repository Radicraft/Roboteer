# Roboteer bridge spec (v1, Stage 1)

The Swift shell and the Godot arena talk through ONE narrow, versioned, data-only contract
(brief §12). This file is the authority for both sides. Change it here first.

## Runtime facts (verified 2026-09-13)

- Embedding library: **SwiftGodotKit tag `v4.6.0`** (SPM: `https://github.com/migueldeicaza/SwiftGodotKit`,
  `exact: "4.6.0"`). It pulls SwiftGodot (rev 48112dd) and a binary `libgodot-ios.xcframework`
  from `migueldeicaza/godot` release `v4.6.4` (libgodot patches on Godot 4.6). Device slice 172 MB static,
  simulator slice (arm64 + x86_64) 320 MB static. The README's "no simulator" note is stale from 4.4;
  the 4.6.4 xcframework SHIPS a simulator slice. Whether it runs on the sim is a Stage 1 measurement.
- Editor for authoring/exporting: Godot **4.6.3-stable** at `~/Applications/Godot.app/Contents/MacOS/Godot`.
  Headless pck export works WITHOUT export templates:
  `Godot --headless --path Arena --export-pack "iOS" <out.pck>` (preset "iOS" must exist in
  `Arena/export_presets.cfg`; `script_export_mode=1` keeps GDScript as text, 2 = binary tokens).
- Xcode 27.0, iOS 27 SDK. Team `VQQCV6BB8R`, bundle id `com.radicraft.roboteer`, iPhone only
  (`TARGETED_DEVICE_FAMILY = 1`), `IPHONEOS_DEPLOYMENT_TARGET = 18.0`.
- Required target settings (from the SwiftGodotKitSamples project + Selig's write-up):
  `OTHER_LDFLAGS = "-lc++"`, link `MetalFX.framework`, `SUPPORTED_PLATFORMS = "iphonesimulator iphoneos"`,
  the `.pck` in Copy Bundle Resources. No Catalyst. Portrait AND landscape allowed for now.

## Transport: the SwiftGodotKit host bridge

SwiftGodotKit adds a node named `__swiftgodotkit_bridge__` as a child of the scene tree root once the
Godot instance has started (it polls every frame from the display link). That node exposes:

- signal `message_from_host(message: Dictionary)` emitted when Swift calls
  `GodotAppViewHandle.emitMessage(_:)`;
- method `emit_message_to_host(message: Dictionary)` which delivers to the Swift `onMessage` closure
  passed to `GodotAppView(onReady:onMessage:)`.

Both directions carry a Godot `Dictionary` (Swift `VariantDictionary`). We put exactly two keys in it:

| key    | type   | value |
|--------|--------|-------|
| `type` | String | message name, snake_case, see table below |
| `json` | String | UTF-8 JSON text of the payload (may be `"{}"`) |

JSON-as-string keeps the contract inspectable, loggable and versioned, and avoids Variant type drift.
No other keys, no nested Variants. SwiftGodotKit adds its own `__swiftgodotkit_view_id` key; ignore it.

### Messages

| direction      | `type`         | payload |
|----------------|----------------|---------|
| Godot -> Swift | `arena_ready`  | `{"schema":1,"godot_version":"4.6.4","ticks_msec":<Time.get_ticks_msec()>}` sent once from the main scene's `_ready` after the bridge node is found |
| Swift -> Godot | `fight_config` | a `FightConfig` (below) |
| Godot -> Swift | `fight_result` | a `FightResult` (below) |
| Godot -> Swift | `arena_log`    | `{"level":"info|warn|error","text":"..."}` optional diagnostics, never required for correctness |

Rule: no live chatter mid-fight. Stage 1 sends one `fight_config`, gets one `fight_result`.

### Godot side (GDScript) pattern

`Arena/bridge.gd` is an autoload singleton named `Bridge`:

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
