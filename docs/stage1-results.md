# Stage 1 results: the bridge spike (measured 2026-09-13)

## Verdict: embedding is workable. Proceed.

- **Build and link, device**: green. `Roboteer.app` = 89.2 MB, executable 78.5 MB, `__TEXT` 55.6 MB
  (Apple's ceiling for `__TEXT` is 80 MB; the whole-app ceiling is 4 GB; the cellular prompt threshold
  is 200 MB and user-disableable, see `docs/title-clearance.md`). Six times the brief's 30 MB guess.
  A custom libgodot build with unused modules disabled is the lever if it ever matters; not needed now.
- **Runtime on the iPhone 17 simulator (iOS 26.5 runtime)**, headless display server + dummy renderer:
  Godot instance created, `arena.pck` loaded, GDScript ran, singleton bridge attached.

| measurement | value |
|---|---|
| process start to SwiftGodotKit `onReady` | 962 ms (Debug build, cold) |
| process start to `arena_ready` from GDScript | 981 ms |
| `fight_config` to `fight_result` round trip (1.2 KB in, 0.7 KB out) | 10 ms first call, about 1 ms after |
| `phys_footprint` at ready / after the round trip | 48 MB / 66 MB |
| echo of arena, bot count, seed | matched |

- **Rendering on the simulator: impossible with the stock package.** The prebuilt simulator slice of
  libgodot 4.6.4 is compiled without Metal (it reports only `opengl3` and `dummy`), Godot's own build
  system refuses Metal for the simulator, and the embedded display server's OpenGL path calls the
  standalone app's view controller, which does not exist when embedded. So the arena renders on a
  physical iPhone only. On the simulator the app runs the arena headless (logic, physics and bridge all
  live) and draws a placeholder. The visible test loop for Godot work is the desktop Godot runtime on the
  Mac (`docs/stage3-spec.md` §14). **Physical-device verification is owed** when the owner's iPhone is
  connected; the spike's `-autoSendFight` launch argument makes it a one-tap check.

## Transport finding that changed the contract

SwiftGodotKit's built-in host bridge node (`__swiftgodotkit_bridge__`) delivers Swift -> Godot but never
delivers Godot -> Swift: its `emit_message_to_host` is a Swift `@Callable`, and **`@Callable` methods on
Swift objects are not invokable from GDScript in this SwiftGodot revision** (0.75.0, rev 48112dd). Swift
calling the method itself also delivered nothing. **Signals work in both directions.** The contract now
uses Roboteer's own singleton (`Roboteer/HostBridge.swift`, registered as `RoboteerHost` at scene level):
`message_from_host(type, json)` emitted by Swift, `message_to_host(type, json)` emitted by GDScript and
connected from Swift. `docs/bridge-spec.md` is updated. Rule: **never call a Swift method from GDScript;
emit a signal.**

## Other facts

- SwiftGodotKit must be pinned by revision (`dabb72c`), not the `v4.6.0` tag (local-path dependency).
- The libgodot binary reports `Godot Engine v4.6.1.rc.gh.d064e255e`, so authoring with the 4.6.3 editor is
  a newer-editor / older-runtime pairing. Keep project features at 4.6 and avoid 4.6.2+ only APIs.
- MetalFX must be linked for device only (`OTHER_LDFLAGS[sdk=iphoneos*]`); it does not exist in the sim SDK.
- Xcode's package plugin validation needs skipping for `xcodebuild` (see `docs/stage1-build-notes.md`).
- QA launch arguments on the spike screen: `-autoSendFight`, `-godotDriver`, `-godotMethod`,
  `-godotDisplay`, `-godotVerbose`.
