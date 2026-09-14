# Stage 6 Swift notes (agent S6: side events, replays and sharing, onboarding)

Written 2026-09-14. Companion to `docs/stage6-spec.md` sections 1, 2 and 7, `docs/brief-v3.md`
section 10, `docs/stage5-swift-notes.md` (which still holds for everything the career does),
`docs/stage6-store-notes.md` (the gates) and `docs/stage4-swift-notes.md`.

Everything here is `Roboteer/Events/**`, `Roboteer/Replays/**`, `Roboteer/Onboarding/**`, one new
top level key in `Shared/parts.json`, and six small marked insertions in files other agents own.
Nothing in `Arena/` was edited; `scripts/export-pck.sh` was run because `Shared/parts.json`
changed, which copies it to `Arena/data/parts.json` and rebuilds `Roboteer/Resources/arena.pck`.

## What the Godot side must know

Three contracts, all of them ordinary `fight_config` with one extra key or one different value.

### 1. A side event is `rules.mode`

```json
{
  "schema": 1, "seed": 4812993,
  "arena": "sumo",
  "rules": { "mode": "sumo", "duration_s": 90, "ko_count_s": 10 },
  "presentation": { "safe_area_px": {...}, "haptics": true },
  "debug": { "opponent_ai": "normal" },
  "bots": [ player, opponent ]
}
```

- `rules.mode` is `sumo`, `gauntlet`, `pinball`, `football` or `wall_smash`.
- **`arena` is the same string as the mode**, so `Arena/arena/events/<mode>.tscn` is selectable
  from one id and the Stage 5 arena switch does not need a second table. If E6 would rather have
  `event_sumo`, say so and this is a one line change in `EventFightConfig.json`.
- `duration_s` is the clock from the catalogue: 90 for everything except Pinball, which is 60.
- **Two bots only for Sumo and Football.** Gauntlet, Pinball and Wall Smash send one bot. The
  gauntlet's chasing boss is the arena's to spawn (it has the Stage 5 boss builds); the shell does
  not send it.
- The opponent for Sumo and Football is a filler machine from `CareerEngine.fillerEntrant` at the
  player's current tier, so it is legal, deterministic from the seed, and gets harder as the
  career does.

The reply is **`event_result`**, not `fight_result`:

```json
{ "mode": "sumo", "score": 2, "cleared": true, "time_s": 47.5,
  "details": { "falls_against": 1 } }
```

`details` is free form: every key in it is printed on the result sheet with its name tidied up, so
adding `walls_broken` or `damage_taken` needs no Swift change. Values may be strings, numbers or
booleans.

### 2. A replay is a `fight_config` with a `replay` key

```json
{ ...the original fight_config, verbatim..., "replay": { "inputs": [ ... ] },
  "presentation": { "safe_area_px": {...}, "hud": false, "camera": "replay" } }
```

The shell keeps the configuration each fight was fought with (see `FightLog.configJSON` below) and
sends it back with the recorded inputs attached and this run's safe area. `presentation.hud` false
and `presentation.camera` `"replay"` are the two additions: the replay bar is the shell's, so the
arena is asked for the bare view and the free camera.

Back come **`replay_state`** messages, expected every ten ticks:

```json
{ "tick": 1240, "total": 5400, "finished": false }
```

`finished` true drops the bar into its paused state. The bar's time readout assumes the arena ticks
at 60 Hz, which is the contract's physics rate.

The bar sends **`replay_control`**:

| action | value | when |
|---|---|---|
| `play` / `pause` | none | the play button |
| `speed` | 0.25, 0.5 or 1.0 | the speed segments |
| `restart` | none | the restart button |
| `seek` | tick number | **once, on release of the scrubber**, never while the thumb moves |

Seeking backwards re-simulates from the start, so one message per gesture is deliberate.

### 3. `fight_state` may now say `abandoned`

`{"state": "abandoned"}` means the arena gave the fight or the event up without a result.
`ArenaHost.FightState` has an `abandoned` case, `FightView` leaves for the garage on it and
`EventFightView` goes back to the events list. Nothing is recorded. Any exhaustive switch on
`FightState` added after this has to handle the fifth case.

## The catalogue: one new key in `Shared/parts.json`

`events`, a top level array, owned by S6. **Every other byte of the file is unchanged.**

```json
{ "id": "sumo", "name": "Sumo", "pitch": "Push the other machine off a six metre platform. Best of three.",
  "reward_part": "rear_wedge", "clock_s": 90 }
```

| event | clock | reward blueprint | why that one |
|---|---|---|---|
| Sumo | 90 s | Rear wedge | it is a pushing event |
| Gauntlet | 90 s | Skirts | it is a surviving event |
| Pinball | 60 s | Magnets | it is a traction event |
| Football | 90 s | Scoop | it is a herding event |
| Wall Smash | 90 s | Counterweight | it is a smashing event |

Every reward is a **Championship or Masters drip part**, so clearing an event brings a part
forward rather than inventing one. The career's own drip is untouched: a part earned in an event
is simply already held when the drip would have handed it over, which `CareerEngine.newBlueprints`
already tolerates because it filters against what is held. The events are behind the wall, so the
free half's part library is unchanged and `CareerSelfTest`'s 172 checks still pass unaltered.

Adding a sixth event is a catalogue edit plus a Godot rules file. `EventCatalogue` drops any entry
whose id is not an `EventMode`, so a mode Godot has but Swift does not is invisible rather than
broken, and there is a hardcoded five entry fallback for a build made from an older catalogue.

## Models

One new `@Model` and one new field on an existing one.

| model | fields |
|---|---|
| `EventRecord` (new) | `mode`, `bestScore`, `bestTimeS`, `cleared`, `plays`, `lastPlayed` |
| `FightLog` (added) | `configJSON`, the `fight_config` the fight was fought with |

`RoboteerApp.makeContainer()` now lists `EventRecord.self` in both the disk and the in memory
container. Both additions are additive with defaults, so SwiftData migrates lightly and an
existing garage opens untouched.

**Why `configJSON` had to exist.** A replay is the original configuration plus the recorded
inputs. `FightLog` kept the result and the replay block but not the configuration, and
`diagnostics.echo` only carries the arena, the bot count and the seed, which cannot rebuild two
machines. `ArenaHost.sendFightConfig` now keeps `lastFightConfigJSON` and both `CareerStore.settle`
and `EventStore` copy it into the log. **Every fight logged before this change can be read but not
watched**, and the replay row says exactly that rather than offering a button that does nothing.

`bestTimeS` is zero until the event is first cleared. For the two raced events (Gauntlet, Wall
Smash) the headline number is the time and a lower one is better; for the other three it is the
score and a higher one is better. `EventRecord.bestLine(_:)` is the one place that decides which.

## Screens

| screen | file | what it is |
|---|---|---|
| events | `Roboteer/Events/EventsView.swift` | the five, with the pitch, the clock, the best, the run count and the reward, and Play |
| the event itself | same file, `EventFightView` | the bare Godot view with the event's name on a capsule and a Leave button |
| event result | same file, `EventResultSheet` | the score, the time, whatever `details` carried, the best line, the New blueprint flourish, Run it again |
| replays | `Roboteer/Replays/ReplaysView.swift` | every recorded fight, newest first: machine, opponent, when, arena, outcome, Watch |
| the replay | `Roboteer/Replays/ReplayPlayerView.swift` | the replay bar over the Godot view |
| welcome | `Roboteer/Onboarding/Onboarding.swift` | three panels, Build Test Fight, one sentence each |

All of them follow the Stage 4 layout rule: a `ZStack` of backdrop and content, content ending in
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`, a fixed left column
(300 pt on both list screens) and the scrolling half taking the rest. Landscape, 874 x 402 pt
upward. Every screen registers its own `PadFocus` items with a `back:` action. No em dashes.

### Gates

- The events list and the replays list are each wrapped in `LockedPanel(reason:)` with
  `Gates.current.lockedReasonIfLocked(.sideEvents)` and `.replays`. The list stays visible and
  readable, greyed, with the sentence on it, and its buttons stop responding. The Back button sits
  **outside** the panel so a locked screen is never a trap.
- `EventsRootView.play(_:)` checks `Gates.current.sideEventsAvailable` again before starting
  anything, because a gate that is only drawn is not a gate.
- Share clip is `Gates.current.sharingAvailable` plus a `.lockedRow` on the button itself.
- The EVENTS and REPLAYS buttons are always on the menu. Nothing is hidden: brief section 14's
  wall is a stated one.

## ReplayKit, and which path was taken

**`RPPreviewViewController`, not an exported movie URL.** `RPScreenRecorder.shared()` records the
whole screen, which is the Godot view plus the replay bar, exactly as the spec asks;
`stopRecording` hands back Apple's own preview controller, which is a trim, a share sheet and a
save, all of it outside our process.

That path was chosen over `startCapture` / `AVAssetWriter` to a temporary URL because:

- it needs **no photo library permission**, so no `NSPhotoLibraryAddUsageDescription`;
- the microphone is explicitly left off (`isMicrophoneEnabled = false`), so no
  `NSMicrophoneUsageDescription` and nothing anyone says near the phone is captured. **Do not turn
  the microphone on without adding that key, or the app will crash on the first recording**;
- it writes no file of ours, so there is nothing to clean up and nothing to leak;
- `UIActivityViewController` with a movie URL is the fiddlier path: the file has to be finished,
  moved somewhere shareable and deleted afterwards, and some share targets refuse a URL in a
  temporary directory.

Details that matter:

- **The Simulator cannot do this.** `RPScreenRecorder.isAvailable` is false there and the button
  says so in a plain sentence rather than failing silently. A clip can only be tested on a device.
- The recording stops itself at **30 seconds** (`ClipRecorder.maximumSeconds`), with the seconds
  left counting down on the button, which is the cap in the spec.
- Leaving the replay screen calls `cancel()`, so ReplayKit is never left running behind the menus.
- SwiftUI has no view controller to present from, so the preview is presented from the key
  window's topmost controller.
- ReplayKit records the screen, so **the replay bar is in the clip**. That is what the spec asks
  for. If the owner wants a clean clip later, the bar would have to hide itself for the duration
  of the recording, which is one `opacity` and a state flag.

## Onboarding

One string in `UserDefaults` (`onboarding.step`) and one overlay.

```
first launch -> welcome panels (Build, Test, Fight)
  -> "Build a bot" -> the Workshop with the starter machine
  -> callout: take it to the test arena
  -> the test arena, which is the tutorial (brief section 10). Nothing is drawn over it
  -> leaving the test arena -> callout: now put it in front of something that fights back
  -> a fight or the career -> done, and never shown again
```

- The overlay is applied to `MenuView`'s `NavigationStack`, so one modifier covers the menu **and**
  every pushed screen, and `WorkshopView` needed no edit at all.
- Every advance happens in `OnboardingCoach.noteScreen(_:)`, driven by `MenuView`'s own path, so
  the rules are in one place and a screen only has to say its own name.
- "Not now" hides a callout until the next screen change. It does not end the flow: the player
  still has to do the thing. "Skip" on the welcome panels ends it for good.
- The step is persisted, so closing the app in the test arena comes back to the right prompt.
- `-resetOnboarding` puts a shipped build back to a first launch. The other QA flags
  (`-career <fixture>`, `-autoCareer`, `-autoWorkshop`, `-autoFight`) finish onboarding instead, so
  the welcome panels never sit on top of whatever is being tested. `-resetOnboarding` wins if both
  are passed.

## The root menu, restructured

Eight full sized buttons (CAREER, LADDER, FIGHT, EVENTS, REPLAYS, WORKSHOP, BRIDGE SPIKE,
SETTINGS) needed about 438 pt of the 356 pt the right hand column has on a 402 pt landscape
screen, so SETTINGS was off the bottom. The column is now:

| row | buttons | kind |
|---|---|---|
| three big ones, 250 pt wide | FIGHT, CAREER, WORKSHOP | FIGHT and WORKSHOP bare, CAREER the one white call to action |
| one quiet row, 336 pt wide | EVENTS, LADDER, REPLAYS, SETTINGS | `StageButtonStyle.Kind.quiet`, equal widths, one line with `minimumScaleFactor(0.6)` |

About 204 pt in total, so it fits the smallest landscape iPhone with room to spare, and every mode
is still one press from the menu. Pad focus runs down the three big ones, then left to right along
the quiet row.

**BRIDGE SPIKE is hidden** unless `-showSpike` is passed, when it appears as a fifth chip. It is a
diagnostic screen, not a mode, and it was the only thing on that menu a player could not use.

The column is 34 pt in from the screen edge on top of the system safe area, and the title column
is a `maxWidth` rather than a fixed width, so it compresses on a device with wide landscape insets
rather than pushing the buttons out.

## Messages, in one table

Only the rows marked new are different from `docs/stage5-swift-notes.md`.

| direction | type | payload | what happens |
|---|---|---|---|
| Swift to Godot | `fight_config` | **new**: `rules.mode` is one of the five events, `arena` equals the mode | a side event |
| Swift to Godot | `fight_config` | **new**: a `replay` key with `{"inputs": [...]}` | a replay |
| Swift to Godot | `replay_control` | **new** `{action, value}` | the replay bar |
| Godot to Swift | `event_result` | **new** `{mode, score, cleared, time_s, details}` | the event result sheet |
| Godot to Swift | `replay_state` | **new** `{tick, total, finished}` | the scrubber |
| Godot to Swift | `fight_state` | **new** state `abandoned` | leave the screen, record nothing |

## Insertions in other agents' files, each one marked

| file | insertion |
|---|---|
| `Roboteer/ArenaHost.swift` | the `abandoned` state, `ReplayState`, the Stage 6 state block, `handleEventResult`, `handleReplayState`, `startEvent`, `startReplay`, `stopReplay`, the four replay controls, `beginArenaRun`, `lastFightConfigJSON`, and two lines in `showStage` |
| `Roboteer/MenuView.swift` | the `events` and `replays` routes and destinations, the whole right hand column rebuilt as three big buttons plus a quiet row of four (see above), `-showSpike`, and the onboarding overlay, `screenName` and `coach.begin()` |
| `Roboteer/FightView.swift` | `abandoned` in the status line switch, and leaving the fight when it arrives |
| `Roboteer/CareerModels.swift` | `FightLog.configJSON` |
| `Roboteer/CareerStore.swift` | one line in `settle`, writing `configJSON` from `ArenaHost.shared.lastFightConfigJSON` |
| `Roboteer/RoboteerApp.swift` | `EventRecord.self` in both model containers |

`beginArenaRun` is the one refactor: `startEvent` and `startReplay` need exactly what
`startCareerFight` does, so the common half was lifted out. `startFight` and `startCareerFight` are
unchanged in behaviour and were deliberately left alone rather than rewritten on top of it, because
they carry Stage 3 and Stage 5 details that are not worth risking here.

## Project file

Five new Swift files in three new groups, following `docs/stage1-build-notes.md`: file reference
ids `...0100` to `...0104`, build file ids `...0120` to `...0124`, group ids `...0110` to `...0112`.
L6 took `...00D0` and `...00F0` in the same session.

| build | result |
|---|---|
| `xcodebuild build -project Roboteer.xcodeproj -scheme Roboteer -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet` | **green**, zero errors, zero warnings |
| `xcodebuild build -project Roboteer.xcodeproj -scheme Roboteer -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | **green**, zero errors, zero warnings |

**A signing note that is not S6's.** Without `CODE_SIGNING_ALLOWED=NO` the project currently fails
before compiling with four provisioning errors: the team provisioning profile carries neither the
Game Center nor the iCloud capability that the ladder's entitlements ask for. That is agent L6's
entitlements file and the owner's Apple Developer account, not this work, but it means **the plain
build command in the earlier stage notes no longer works** until the capabilities are added to the
App ID.

## Traps found while doing this

1. **A replay needs the configuration, and nothing was keeping it.** The obvious source,
   `diagnostics.echo`, has the arena, the bot count and the seed, which is not enough to rebuild
   two machines. Hence `FightLog.configJSON` and `ArenaHost.lastFightConfigJSON`. Every log written
   before Stage 6 is unwatchable and the row says so; there is no way to reconstruct them.
2. **Adding a case to `ArenaHost.FightState` breaks every exhaustive switch on it.** There was one,
   in `FightView.statusLine`. A future case will find more.
3. **`StageSegments`'s memberwise initialiser is `values`, `title`, `selection`,** in that order,
   because `@Binding` keeps its declaration position. Passing `selection:` second does not compile.
4. **Two agents building the same project at once do not just contend on the build database.** A
   concurrent device build produced `failed creating index directory ... Read-only file system` and
   `Unable to resolve module dependency: 'SwiftSyntax'` in the SwiftGodot package, neither of which
   is a real fault in the source. Wait for the other `xcodebuild` to leave, then build.
5. **`xcodebuild` without `-scheme` ignores `-destination`** and says so in a warning that is easy
   to miss: the "simulator" build was really building for `iphoneos`. Every build here passes
   `-project` and `-scheme`.
6. **DerivedData is a symlink to `/Volumes/RoboteerBuild`.** A build that stops with "DerivedData
   couldn't be saved" wants `scripts/mount-build-volume.sh` run first.
7. **The Simulator has no ReplayKit.** Anything about Share clip has to be measured on a device;
   the screen says so rather than pretending.

## What is not done here

- **Nothing has been run.** Both builds link; no simulator was booted by this agent. The events
  cannot be played until E6's five rules files and arenas exist, and a replay cannot be watched
  until R6's playback lands. Every message above is what the shell sends and expects.
- The replay bar assumes 60 Hz for its time readout. If the arena ever reports its own tick rate,
  that is one line.
- Sharing does not offer a photo library save of its own, deliberately: Apple's preview already
  has one.
- Game Center leaderboards for event scores are not wired. The ladder (L6) owns GameKit; if event
  scores should be leaderboards too, the hook is `EventStore.apply`.
