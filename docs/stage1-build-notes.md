# Stage 1 build notes (Xcode side)

Written 2026-09-13 by the agent that built `Roboteer.xcodeproj` and `Roboteer/`.
Companion to `docs/bridge-spec.md`. Where the two disagree, this file records the measurement
and the spec should be amended.

## What was built

- `Roboteer.xcodeproj` written by hand (`objectVersion` 56, `compatibilityVersion` "Xcode 14.0"),
  with a shared scheme at `Roboteer.xcodeproj/xcshareddata/xcschemes/Roboteer.xcscheme`.
  No xcodegen or tuist is installed on this Mac and none was used.
- One app target `Roboteer`, bundle id `com.radicraft.roboteer`, team `VQQCV6BB8R`,
  automatic signing, marketing version 0.1, build 1.
- Four Swift files in `Roboteer/`: `RoboteerApp.swift`, `SpikeModel.swift`, `ContentView.swift`,
  `FightConfigFixture.swift`. Plus `Roboteer/Assets.xcassets` (empty AppIcon and AccentColor)
  and `Roboteer/Resources/arena.pck` in Copy Bundle Resources.

## Three things that were needed to make it build, none of them obvious

### 1. SwiftGodotKit tag v4.6.0 cannot be used as a remote package

The spec pins `exact: "4.6.0"`. That resolution fails outright:

```
xcodebuild: error: Could not resolve package dependencies:
  Failed to resolve dependencies Dependencies could not be resolved because package
  'swiftgodotkit' is required using a stable-version but 'swiftgodotkit' depends on an
  unstable-version package 'swiftgodot' and root depends on 'swiftgodotkit' 4.6.0.
```

The cause is in the tag itself. `Package.swift` at tag `v4.6.0` declares

```swift
dependencies: [ .package(path: "../SwiftGodot") ],
```

a local path dependency that assumes a sibling checkout. No remote consumer can resolve it.
That tag also points at libgodot `v4.6.0`, not the `v4.6.4` the spec describes.

`main` is what the spec's runtime facts actually describe: it depends on
`https://github.com/migueldeicaza/SwiftGodot` at revision `48112dd` (tag 0.75.0) and pulls
libgodot xcframeworks from `migueldeicaza/godot` release `v4.6.4`.

**Resolution used:** `XCRemoteSwiftPackageReference` with `kind = revision`, pinned to
`dabb72ced0bc6b03114e0e31f743b5d889edc433` (SwiftGodotKit `main` as of 2026-09-13). This is
reproducible, not a moving branch. `docs/bridge-spec.md` should be updated to say revision
`dabb72c`, not tag `v4.6.0`.

Resolved versions, from `Roboteer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:

| package | pin |
|---|---|
| SwiftGodotKit | revision `dabb72ced0bc6b03114e0e31f743b5d889edc433` |
| SwiftGodot | revision `48112dd50fffe01f0af78e445a16991ecdc6bc94` (tag 0.75.0) |
| swift-syntax | 600.0.1 (`0687f719`) |
| swift-argument-parser | 1.8.2 (`6a52f325`) |

### 2. MetalFX.framework does not exist in the iOS Simulator SDK

`iPhoneSimulator27.0.sdk/System/Library/Frameworks` has Metal, MetalKit,
MetalPerformancePrimitives, MetalPerformanceShaders and MetalPerformanceShadersGraph.
It has no MetalFX at all. `iPhoneOS27.0.sdk` does. An unconditional `-framework MetalFX`
links on device and fails the simulator link with `ld: framework 'MetalFX' not found`.

**Setting used**, in both Debug and Release on the target:

```
OTHER_LDFLAGS = "-lc++";
"OTHER_LDFLAGS[sdk=iphoneos*]" = ( "-lc++", "-framework", MetalFX );
```

No `PBXFileReference` with `DEVELOPER_DIR` was needed. `otool -L` on the device binary confirms
MetalFX is linked and, usefully, that the linker weak-linked it:

```
/System/Library/Frameworks/MetalFX.framework/MetalFX (compatibility version 1.0.0, current version 1.0.0, weak)
```

The simulator slice of libgodot links clean without it.

### 3. SwiftGodot's build tool plugin has to be trusted

SwiftGodot runs a `CodeGeneratorPlugin` build tool plugin. A plain command line build stops with

```
error: the following command failed with exit code 1 but produced no further output
Validate plug-in "CodeGeneratorPlugin" in package "swiftgodot"
```

Two ways past it, both verified here:

- pass `-skipPackagePluginValidation -skipMacroValidation` to `xcodebuild`, or
- trust it once for this machine, which is what was done so that the plain build command works:

```
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
```

(Apple's key really is spelled `Validatation`.) To undo, `defaults delete` those two keys.
In the Xcode GUI the same thing appears as a one time "Trust and Enable" prompt.

## Build results

Both builds succeeded with zero errors and zero warnings.

| build | command | result | wall time |
|---|---|---|---|
| package resolve | `xcodebuild -resolvePackageDependencies` | ok | 58 s, including the libgodot xcframework download (3.4 GB extracted into `SourcePackages/artifacts`) |
| simulator | `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet` | ok | about 105 s from clean, 6 s incremental |
| device | `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | ok | 289 s from clean |

Most of both wall times is compiling SwiftGodot's generated bindings, not our code.

## Device build size, which is the number that matters

Measured on `Build/Products/Release-iphoneos/Roboteer.app`, unsigned, arm64 only,
with the 18 KB `arena.pck` in it.

| item | `du -sk` |
|---|---|
| `Roboteer.app` bundle | **91,312 KB** (89.2 MB) |
| `Roboteer` executable | **78,584 KB** (76.7 MB, 80,468,048 bytes) |
| embedded `Frameworks/SwiftGodot.framework` | 12,695 KB (SwiftGodot builds as a dynamic framework and Xcode embeds it automatically) |
| `arena.pck` | 18 KB |

`size -m` on the executable: `__TEXT` 55,590,912 bytes, of which `__text` is 47,565,108.
That is libgodot, statically linked.

**This is six times the brief's assumption.** Brief section 12 budgets "roughly 30MB" for
embedding Godot. The real figure for an empty grey cube scene is 89 MB of bundle before any
model, texture or audio exists. Open question 5 in the brief (binary size versus App Store
cellular download limits) should be treated as answered in the worst direction and checked
properly, not left until Stage 5. App Store thinning will not help much here because there is
one architecture and the bulk is a single static library; compression is the only lever.

For contrast, the simulator Debug bundle is 351,612 KB, but that is a debug dylib build and is
not a meaningful size measurement.

## Deviations from docs/bridge-spec.md in the Swift code

The spec's Swift pattern is correct as written, with one nit. Everything below was verified
against the resolved checkouts, not guessed.

- `VariantDictionary` has `subscript(key: String) -> Variant?`, so `dict["type"] = Variant("x")`
  and reading `dict["type"]` both work as the spec says. Confirmed in
  `SwiftGodot/Sources/SwiftGodotRuntime/Extensions/VariantDictionaryExtensions.swift`.
- `String.init?(_ variant: Variant?)` exists, so `String(dict["type"]) ?? ""` compiles and returns
  `String?` as the spec claims. Confirmed in
  `SwiftGodot/Sources/SwiftGodotRuntime/Core/VariantConvertible.swift` line 783, inside
  `extension String: _GodotBridgeableBuiltin`.
- The nit: the spec writes `var d = VariantDictionary()`. `VariantDictionary` is a reference type,
  so the compiler emits `variable 'd' was never mutated; consider changing to 'let' constant`.
  `SpikeModel.send(type:json:)` uses `let`.
- `GodotAppView(source:scene:onReady:onMessage:)`, `GodotApp(packFile:godotPackPath:renderingDriver:renderingMethod:displayDriver:extraArgs:)`
  with metal/mobile/embedded defaults, `GodotAppViewHandle.emitMessage/pause/resume/isReady/getRoot`,
  `GodotApp.registerEventHandler/pause/resume/startDrawing/stopDrawing/instance` and
  `EnvironmentValues.godotApp` all match the spec exactly.
- The Godot side names in the spec are right. `SwiftGodotHostBridge` is `@Godot`, its signal is
  `messageFromHost` (GDScript `message_from_host`) and its `@Callable` is
  `emitMessageToHost(message:)` (GDScript `emit_message_to_host`). The node name constant is
  `__swiftgodotkit_bridge__`. SwiftGodotKit adds its own routing key to the dictionary, so the
  Godot side must ignore unknown keys, which `bridge.gd` does.

## What the Swift side does

- `LaunchClock` in `RoboteerApp.swift` latches `firstTouch` as a `Date` in the `@main` initialiser
  and reads true process start from `kinfo_proc.kp_proc.p_starttime` via `sysctl(CTL_KERN, KERN_PROC,
  KERN_PROC_PID, getpid())`. Every reported millisecond figure is measured from the kernel's process
  start, so it includes dyld and runtime setup, not just our code. If the sysctl ever fails it falls
  back to `firstTouch` and the app logs which reference it used.
- `SpikeModel.shared` owns the one and only `GodotApp(packFile: "arena.pck")`. It is created once in
  a private initialiser and never recreated. Backgrounding calls `pause()` and `stopDrawing()`,
  returning calls `resume()` and `startDrawing()`. SwiftGodotKit also observes the UIApplication
  notifications itself, and its pause and resume are guarded, so the double call is harmless.
- Every `GodotAppEvent` case is logged: `startupFailure`, `warning`, `bridge`, `windowBinding`,
  `lifecycle`. A `startupFailure` also surfaces on screen in red, which is what you will see if the
  `.pck` is missing or malformed.
- Memory is `task_info` with `TASK_VM_INFO`, reading `phys_footprint`. Sampled when `arena_ready`
  arrives, again 5 s later, and on demand from the "Sample memory" button.
- The screen checks `diagnostics.echo` against the config it sent (arena `yard`, 2 bots,
  seed 123456789) and shows an error line if they disagree, so acceptance point 2 in the spec is
  checked by the app rather than by eye.
- `FightConfigFixture.json` is the spec's FightConfig block copied verbatim out of
  `docs/bridge-spec.md` and validated as JSON.

All log lines go to `Logger(subsystem: "com.radicraft.roboteer", category: "spike")`. To watch them:

```
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.radicraft.roboteer"' --style compact
```

## What the main session needs to know before launching this

1. **Nothing has been run.** No simulator was booted and the app has never launched. Both builds
   link, and `arena.pck` (18,228 bytes, `GDPC` magic, produced by the other agent) is in both
   bundles, but whether libgodot's simulator slice actually renders is still the open Stage 1
   measurement. The SwiftGodotKit README's "no simulator" note is stale from 4.4, and the 4.6.4
   xcframework does ship a simulator slice, but stale documentation is not proof it works.
2. The two `defaults write` keys above are now set on this Mac. If a future build suddenly fails on
   plugin validation, that is the first thing to check.
3. `Roboteer/Resources/arena.pck` is a real file in the repo and in Copy Bundle Resources. Re-running
   `scripts/export-pck.sh` overwrites it in place and an incremental Xcode build picks it up; there
   is no stale-copy problem, but a build is still needed after every export.
4. Orientation is portrait plus landscape left and right, confirmed in the generated Info.plist.
   `TARGETED_DEVICE_FAMILY` is 1, `SUPPORTS_MACCATALYST` is NO, deployment target 18.0.
5. `SWIFT_VERSION` is 5.0 and `SWIFT_STRICT_CONCURRENCY` is minimal on our target. SwiftGodotKit is
   not Swift 6 strict concurrency clean. Do not raise either without expecting work.
6. The device build was made with `CODE_SIGNING_ALLOWED=NO`. A real device install needs the normal
   automatic signing path, which is configured but untested.
