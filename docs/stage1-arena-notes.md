# Stage 1 arena notes (Godot side)

Written by the arena agent, 2026-09-13. Scope: `Arena/`, `scripts/`, and the exported
`Roboteer/Resources/arena.pck`. The Swift shell is owned elsewhere.

## Files created

| Path | What it is |
|---|---|
| `Arena/project.godot` | Project config. Name "Roboteer Arena", features `4.6` + `Mobile`, main scene `res://main.tscn`, `rendering/renderer/rendering_method="mobile"` (and the `.mobile` override), `physics/3d/physics_engine="Jolt Physics"` (brief §12, locked now even though Stage 1 has no physics), `display/window/handheld/orientation=6` (sensor), `display/window/stretch/mode="disabled"` (the host resizes the embedded window), dark grey clear colour, autoload `Bridge` -> `res://bridge.gd`. No editor plugins. vsync left at default. |
| `Arena/bridge.gd` | The `Bridge` autoload, exactly the spec's Godot-side pattern plus two test seams (below). |
| `Arena/main.tscn` | Node3D scene: `Floor` (BoxMesh 20 x 0.2 x 20, albedo 0.55, top face at y=0), `Cube` (1 m BoxMesh, albedo 0.75, resting at y=0.5), `KeyLight` (DirectionalLight3D, shadows on, top-left key), `Camera3D` (orthogonal, size 12), `WorldEnvironment` (flat grey background, ambient from colour 0.4), `Hud/Label`. |
| `Arena/main.gd` | Scene logic: arena_ready handshake, fight_config -> fight_result, tap affordance, HUD label. |
| `Arena/export_presets.cfg` | One preset, "iOS", platform iOS, `export_filter="all_resources"`, `exclude_filter="tests/*"`, `script_export_mode=0`, bundle id `com.radicraft.roboteer`, team `VQQCV6BB8R`, encryption off. |
| `Arena/icon.svg` | Plain grey square placeholder so the editor does not complain. |
| `Arena/tests/bridge_test.gd` | Headless `SceneTree` contract test, 39 checks. |
| `scripts/export-pck.sh` | Import then export-pack to `Roboteer/Resources/arena.pck`. |
| `scripts/test-arena.sh` | Runs the headless bridge test, returns its exit code. |

`Arena/.godot/` is already covered by `.gitignore` (confirmed with `git check-ignore`); so is `Arena/export/`.

## How to run things

```sh
./scripts/test-arena.sh     # headless bridge contract test, exit 0 = PASS
./scripts/export-pck.sh     # rebuilds Roboteer/Resources/arena.pck
```

Both accept a `GODOT=/path/to/Godot` override; the default is
`~/Applications/Godot.app/Contents/MacOS/Godot`. Re-run `export-pck.sh` after ANY change under
`Arena/`, or the app bundle ships a stale arena.

Smoke check, must exit 0 with exactly one warning:

```sh
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --quit-after 3
```

## Results

- Test: 39 checks, 0 failures, exit 0.
- Export: `Roboteer/Resources/arena.pck`, **18,228 bytes (20 KB on disk)**. It contains
  `project.binary`, `main.scn`, `bridge.gd`, `main.gd` (text), the icon and the uid/class caches.
  A placeholder that was there before has been overwritten.
- Headless run: exit 0, exactly one warning, verbatim:

```
WARNING: Bridge.send before attach: arena_ready
     at: push_warning (core/variant/variant_utility.cpp:1034)
     GDScript backtrace (most recent call first):
         [0] send (res://bridge.gd:39)
         [1] _send_arena_ready (res://main.gd:108)
         [2] _process (res://main.gd:53)
```

That warning is expected and correct: there is no SwiftGodotKit host in a desktop or headless
process, so `arena_ready` is composed, observed, and dropped. In the app it must NOT appear.

## Corrections to docs/bridge-spec.md

**`script_export_mode` is off by one in the spec.** The spec says `1` = text GDScript, `2` = binary
tokens. Measured on Godot 4.6.3: `script_export_mode=1` packs `bridge.gdc` / `main.gdc` (binary
tokens) and `script_export_mode=0` packs `bridge.gd` / `main.gd` (text). The preset uses **0**,
because text was the stated intent. Worth amending in the spec.

Everything else in the Transport and Godot-side pattern sections was implemented verbatim.

## Additions to the spec's Bridge pattern (contract unchanged)

Three things, none of which touch the wire format:

1. `signal message_sent(type: String, payload: Dictionary)` emitted by `send()` **before** the host
   check, so it fires whether or not a host is attached. Local only; nothing crosses the bridge.
2. `func inject_from_host(message: Dictionary)` calls `_on_message_from_host` directly, so a headless
   test drives the real receive path.
3. `func is_attached() -> bool` returns whether the host node has been found, so the scene can handle
   both attach orders.

## Assumptions about the SwiftGodotKit bridge node

None of this could be verified without the app, so it is all assumption and is what will break first
if Stage 1 misbehaves:

- The node is named exactly `__swiftgodotkit_bridge__` and is a **direct child of the scene tree
  root**, so `get_tree().root.get_node_or_null(...)` finds it. If SwiftGodotKit parents it elsewhere,
  the poll never succeeds and the app sees no `arena_ready`. That is the first thing to check.
- Its signal is `message_from_host(message: Dictionary)` and its method is
  `emit_message_to_host(message: Dictionary)`, both as the spec states. `bridge.gd` calls the method
  by name with no `has_method` guard, matching the spec's pattern.
- The node appears within a frame or two of start. `main.gd` waits **180 process frames (3 s at
  60 fps)** in a windowed/embedded process before giving up and sending `arena_ready` anyway (which
  is then dropped with the warning above); in a headless process it waits 2 frames, which is what
  makes `--quit-after 3` produce the warning. If the host attaches after 3 s, the handshake is lost.
  Raise `HOST_WAIT_FRAMES_WINDOWED` if that ever happens.
- Attach order is handled both ways: `_ready` sends immediately if `Bridge.is_attached()`, otherwise
  it waits for the synthetic `bridge_attached` message.
- SwiftGodotKit's extra `__swiftgodotkit_view_id` key on incoming dictionaries is ignored; `bridge.gd`
  only reads `type` and `json`.

## Godot version facts

- Authoring/export editor: **4.6.3.stable.official.7d41c59c4**.
- `--headless --path Arena --export-pack "iOS" <out>` works with **no export templates installed**,
  confirmed again here. `--import` first is still required after any asset change.
- `arena_ready.godot_version` is `Engine.get_version_info()["string"]` read at runtime, so in the app
  it will report the **libgodot build SwiftGodotKit links (4.6.4)**, not 4.6.3. A mismatch between the
  editor and the embedded runtime is expected and is exactly why the field is sent.
- Godot's JSON parser returns whole numbers as **floats**. `main.gd::_as_number()` converts integral
  floats back to ints for `seed`, so `diagnostics.echo.seed` serialises as `123456789` and not
  `1.23456789e+08`. The test asserts the value survives a `JSON.stringify` round trip.
- The 12-float `Transform3D(...)` literal in a `.tscn` fills the basis **rows**, not the x/y/z basis
  vectors. Getting this backwards silently points the camera and the light the wrong way with no
  error. Verified numerically: the camera reports `rotation_degrees = (-50, 45, 0)` and the world
  origin unprojects to the exact centre of the viewport.

## Scene details worth knowing

- Camera: orthogonal, `size = 12`, near 0.1, far 100, at `(9.0904, 15.3209, 9.0904)`, yaw 45,
  pitch -50, looking at the origin. `keep_aspect` is the default KEEP_HEIGHT, so `size` is the
  **vertical** world span; on a portrait phone viewport that leaves roughly 5.5 m of visible width.
  Revisit if the embedded view turns out to be landscape.
- Light: `DirectionalLight3D`, forward `(0.408, -0.816, -0.408)`, i.e. shining down and toward
  screen-right, so the key comes from the top-left. Shadows enabled, energy 1.2.
- Tap affordance: `_unhandled_input` accepts `InputEventScreenTouch` (pressed) and a left
  `InputEventMouseButton` (pressed) for desktop. The cube tweens `position:y` up 0.6 m and back over
  0.35 s and cycles albedo through three greys. This is the proof that touch reaches Godot through
  the embedded view; if the cube does not hop on the simulator, input routing is broken.
- HUD label reads `Roboteer arena, Godot <version>` and the viewport size on a second line, updated on
  `get_viewport().size_changed`. A screenshot therefore proves both the runtime version and that
  resize/rotation reaches Godot. No em dashes in it.
- `fight_result` is a **placeholder**: no simulation runs. `outcome.type` is always `judges`, winner is
  the first bot, loser the second, `at_s` and `duration_s` are `rules.duration_s`, judges and scrap are
  zero, and `damage` is the config's own damage dictionaries copied straight back. `diagnostics.echo`
  is the real payload-integrity proof.
- Unknown message types produce an `arena_log` at level `warn` and nothing else.
