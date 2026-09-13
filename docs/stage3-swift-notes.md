# Stage 3 Swift notes (the shell)

Written 2026-09-13 by agent S. Companion to `docs/stage3-spec.md` sections 1, 2, 3, 12, 13, 14,
`docs/bridge-spec.md` and `docs/stage1-build-notes.md`. Everything here is about `Roboteer/**` and
`Roboteer.xcodeproj`; nothing in `Arena/` was touched.

## Screens

| screen | file | what it is |
|---|---|---|
| root menu | `Roboteer/MenuView.swift` | "ROBOTEER", two buttons, the four locked Game Boy greens. Owns the `NavigationStack` and its `path`, so "Back to garage" is `path.removeAll()`. |
| fight | `Roboteer/FightView.swift` | `GodotAppView` full screen ignoring safe areas, status bar hidden, navigation bar hidden. Sends the fight configuration, shows the result sheet. |
| result sheet | `Roboteer/ResultSheet.swift` | Outcome, winner, time, per bot damage, scrap, judges scores, "Back to garage". |
| bridge spike | `Roboteer/ContentView.swift` | The Stage 1 measurement screen, unchanged apart from taking an `ArenaHost` and waking the arena when it appears. |

`Roboteer/ArenaHost.swift` (was `SpikeModel.swift`) is the `@Observable` singleton that owns the one
`GodotApp` for the life of the process. It is never recreated. Leaving an arena screen calls
`pause()` and `stopDrawing()`; arriving calls `resume()` and `startDrawing()`.

The palette lives in `MenuView.swift` as `RoboteerPalette`: `#0f380f` deepest, `#306230` dark,
`#8bac0f` mid, `#9bbc0f` light. Four tones and no fifth, including in the result sheet.

## Message dispatch table

Everything Godot sends arrives at `ArenaHost.receiveRaw(type:json:)`, on the main thread, whether it
came through `HostBridge.onMessage` (the `RoboteerHost` singleton signal, the working path) or through
the `GodotAppView` `onMessage` callback.

| type | payload read | what the shell does |
|---|---|---|
| `arena_ready` | `schema`, `godot_version` | marks `arenaReady`, samples memory, sends any configuration that was waiting, honours `-autoSendFight` |
| `fight_state` | `state` = `countdown\|fighting\|result` | sets `fightState`, cancels the defensive resend, prepares the haptic generators on `countdown` |
| `fight_result` | FightResult v1 | parses into `lastResult`, forces `fightState` to `result` (so the sheet appears even if `fight_state` never says so), records the round trip |
| `haptic` | `kind` | `HapticsPlayer.play(kind:)` |
| `arena_log` | `level`, `text` | logged; `error` also shows on screen |
| anything else | | logged as an unknown type and ignored |

`FightResult` (`Roboteer/FightResult.swift`) is decoded straight from `JSONSerialization` with every
key optional: a missing `judges`, `scrap`, `replay` or `armour` block gives defaults rather than a
failure. Numbers are accepted as int, float or numeric string. `replay.inputs` is counted, not kept.

Haptic mapping (`Roboteer/HapticsPlayer.swift`), per spec section 3:

| kind | generator |
|---|---|
| `tick` | `UIImpactFeedbackGenerator(.light)`, throttled to 30 a second |
| `impact_light` | `.medium` |
| `impact_heavy` | `.heavy` |
| `flip` | `.rigid` |
| `ko_tick` | `.soft` |
| `bell` | `UINotificationFeedbackGenerator` `.success` |

Generators are prepared when a fight starts and again on `countdown`, and released on the way back to
the menu. On the simulator every call is a compile time no operation, so nothing crashes and nothing
is logged per tick.

## The fixture and the safe area

`Roboteer/FightConfigFixture.swift` holds two configurations.

- `FightConfigFixture.json` is the Stage 1 spike fixture, untouched, still sent by the spike screen so
  its measurements stay comparable.
- `FightConfigFixture.stage3Json(safeArea:opponentAI:)` is the Stage 3 fixture from spec section 2:
  both bots `wedge / 4wd / flipper / ["srimech"]`, the player steel front, hdpe sides, polycarbonate
  rear, titanium top, the opponent all steel, seed 123456789, arena `yard`, 90 s, KO count 10 s.
  It adds the two Stage 3 keys:

```json
"presentation": { "safe_area_px": { "left": 0, "top": 0, "right": 0, "bottom": 0 }, "haptics": true },
"debug": { "opponent_ai": "normal" }
```

The fixture is a text template with placeholders rather than a dictionary run through
`JSONSerialization`, deliberately: serialising a Swift dictionary turns `1.0` into `1`, and the arena
would then read the condition values as ints.

Safe area, `SafeAreaPixels.current(fallback:)`:

1. the key window's `safeAreaInsets` (`UIEdgeInsets`, so left and right are physical sides and stay
   correct in a right to left language), times `windowScene.screen.scale`, rounded to whole pixels;
2. if there is no window yet, the `GeometryReader` insets the fight view measured, mapping leading to
   left, times the same scale.

It is measured one runloop turn after `FightView` appears, so the window has settled with the status
bar already hidden, and it goes out once with the configuration. The contract forbids mid fight
chatter, so a device rotation between landscape left and landscape right during a fight would swap
the real left and right insets and the arena would keep the ones it was given. That is accepted for
Stage 3; if it matters later the fix is a new presentation-only message, agreed in the spec first.

On an iPhone 17 in landscape expect roughly `left 177, top 0, right 177, bottom 63` pixels (59 pt and
21 pt at 3x), and zero all round on the simulator when the window has no insets.

## Launch arguments

| argument | default | effect |
|---|---|---|
| `-opponentAI idle\|charge\|normal` | `normal` | goes out as `debug.opponent_ai`; anything unrecognised falls back to `normal` |
| `-godotDriver <name>` | `metal` on device, `dummy` on the simulator | `GodotApp` rendering driver |
| `-godotMethod <name>` | `mobile` on device, `dummy` on the simulator | `GodotApp` rendering method |
| `-godotDisplay <name>` | `embedded` on device, `headless` on the simulator | `GodotApp` display driver |
| `-godotVerbose` | off | adds `--verbose` to the Godot command line |
| `-autoSendFight` | off | one second after `arena_ready`, sends the Stage 1 spike fixture (the spike screen's one tap device check) |

The simulator defaults are the Stage 1 finding made automatic: the prebuilt simulator slice of
libgodot has no Metal driver and the embedded display server has no working OpenGL path, so the arena
there runs headless. Logic, physics, GDScript and the bridge are all live; only the picture is
missing. The fight screen says so in a translucent panel over the black view, along with the current
state, the opponent AI and the safe area that was sent. An explicit launch argument still overrides,
so a future working simulator renderer needs no code change to try.

## What agent R needs to know

1. **Re arming is required.** The shell sends a fresh `fight_config` every time the player taps
   "Fight", including after a result, on the same never restarted Godot process. The arena must
   accept a `fight_config` while in RESULT and start a new fight from it: tear down the old bots and
   debris, reset the clock, tallies and the RNG from the seed, and go back to COUNTDOWN.
2. The shell codes defensively around that: if no `fight_state` arrives within 3 seconds of a
   `fight_config`, it sends the same configuration once more, and if that also produces nothing it
   shows "The arena did not start the fight. Go back and try again." and logs the failure. Two sends
   of the same configuration must not produce two fights.
3. **State names are exactly** `countdown`, `fighting`, `result` in `fight_state`. Anything else is
   logged and ignored. `LOADING` is the shell's own idea of "no state yet" and is never sent.
4. `fight_result` alone is enough to raise the result sheet; `fight_state result` is welcome but the
   sheet does not wait for it. Send `fight_result` exactly once per fight.
5. `outcome.type` drives the title: `ko` gives "Knockout", `out_of_arena` "Out of the arena",
   `judges` "Judges decision", `component_kill` "Core destroyed", `timeout` "Time ran out", anything
   else "Fight over".
6. The sheet prints names, not ids. It gets them from the `bots[].name` values in the configuration
   the shell sent, so the result only needs ids.
7. Missing keys in `FightResult` are tolerated, so a partial result is still shown. `wheels` is read
   as a list of any length and "intact" means a condition above 0.
8. `haptic` is fire and forget and is not logged per message. The shell throttles ticks to 30 a
   second on its side as well.
9. `presentation.safe_area_px` is in Godot window pixels, not points, and `presentation.haptics` is
   always `true` for now.
10. Backgrounding the app pauses the GodotApp and stops drawing, and leaving the fight screen does
    the same. Nothing is destroyed, so a paused fight is still there on return, and a physics clock
    that assumes wall clock time will see a jump.

## Project file

`Roboteer.xcodeproj/project.pbxproj` is still hand written. Five new Swift files were added by hand
with fresh ids on the existing `AA00...` pattern (`...0049` to `...004D` for the file references,
`...0059` to `...005D` for the build files), and `SpikeModel.swift` was renamed to `ArenaHost.swift`
in place, keeping its ids. Orientation is now landscape only in both configurations:

```
INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
```

`TARGETED_DEVICE_FAMILY` stays 1, `SWIFT_VERSION` stays 5.0, `SWIFT_STRICT_CONCURRENCY` stays
minimal. `UIRequiresFullScreen` is not set and is not needed on an iPhone only app. Verified in the
built `Info.plist`: both orientation keys landscape only, `UIDeviceFamily` `[1]`.

Both builds are green with zero errors and zero warnings:

```
xcodebuild build -project Roboteer.xcodeproj -scheme Roboteer -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild build -project Roboteer.xcodeproj -scheme Roboteer -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

## Two traps found while doing this

- `Color` is ambiguous in any file that imports both SwiftUI and SwiftGodot: SwiftGodotRuntime
  exports its own `Color`. Write `SwiftUI.Color.black` in those files, which is why `FightView.swift`
  does.
- `plutil -extract <key> json <file>` with no `-o` **overwrites the file it read**. Use
  `plutil -extract <key> json -o - <file>` to print. It clobbered a built `Info.plist` here; a
  rebuild restored it, but doing that to a source plist would be a quiet disaster.
