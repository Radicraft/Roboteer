# Stage 4 Swift notes (agent S2: the builder, the workshop, the AAA menus)

Written 2026-09-13. Companion to `docs/stage4-spec.md` sections 1 and 7, `docs/bridge-spec.md`,
`docs/stage2-art-direction.md` ("Owner decision 2026-09-13: menus are AAA cinematic") and
`docs/stage3-swift-notes.md`, which this replaces wherever the two disagree. Everything here is
`Roboteer/**` and `Roboteer.xcodeproj`. Nothing in `Arena/` was touched.

## The one thing the Godot side must know

**There is exactly one `GodotAppView` in the process and it now lives at the root of the window,
behind every screen, for the whole life of the app.** It is created at launch, not when a fight
starts, so `arena_ready` arrives during the menu and the arena is running while the player is in
the garage and the builder.

That is not a style choice. `UIGodotAppView` hands its own `CAMetalLayer` to the embedded display
server and drives the engine from its own `CADisplayLink`, so two live views would fight over one
surface. The menus are glass panels drawn in front of that view; the fight screen is the same view
with the chrome taken away.

The consequence for the arena: **the arena is asked to draw continuously from launch**, and the
mode it is in is whatever message it was last sent. `workshop_config` puts the stage up,
`fight_config` puts the fight up. The shell never expects the arena to volunteer a switch.

## Screens and navigation

One `NavigationStack` in `MenuView`, path of `MenuView.Route`. `RootView` is the window: the Godot
surface, then the stack.

| screen | file | what it is |
|---|---|---|
| root menu | `Roboteer/MenuView.swift` | ROBOTEER top left, the selected bot's name, weight and parts under it, a right hand column: FIGHT (white fill), WORKSHOP, BRIDGE SPIKE, SETTINGS. The dry ice is brightest at the bottom right, so SETTINGS, the lowest button, is the one on glass. |
| workshop | `Roboteer/WorkshopView.swift` | the stable: one build row plus a dashed "Garage slot locked" row, select, BUILD, TEST IN THE ARENA, FIGHT, RENAME, NEW BOT, DELETE with a confirmation, and a repair panel when the bot is carrying damage. |
| builder | `Roboteer/BuilderView.swift` | weight bar, name field, a six way segmented row (Chassis, Drive, Weapon, Utility, Armour, Livery), the picker list on the left, validation and the `workshop_ready` numbers on the right, the live bot on the stage between them. |
| fight | `Roboteer/FightView.swift` | sends the fight, shows the result sheet. `mode: .fight` or `.test`. |
| test arena | same file, `mode: .test` | BACK and RESET on glass at the top. The physics readout itself is Godot's `TestOverlay`. |
| result | `Roboteer/ResultSheet.swift` | same content as Stage 3, restyled, plus it writes the fight into the machine's record. |
| settings | `MenuView.swift` | a placeholder that still prints what the app knows. |
| bridge spike | `Roboteer/ContentView.swift` | the Stage 1 measurement screen, untouched. |

Back out of a fight and `MenuView` sees the path empty, calls `ArenaHost.showStage(bot:)` and the
stage comes back with the player's bot on it.

## The look (the design system)

`Roboteer/DesignSystem.swift`. **The four Game Boy greens are gone from the menus.** `RoboteerPalette`
no longer exists.

- `Stage` holds the tokens: white type at three opacities, `gold #f2c14e` for scrap and the winner
  mark and nothing else, `Stage.danger` for the over weight bar and the validation sentences, a thin
  light edge at 18 % white, and the fonts. Type is `.system(size:weight:).width(.condensed)`,
  capitals, tight tracking; numerals are monospaced digits so columns line up.
- `GlassPanel` is `.ultraThinMaterial` forced to the dark scheme with a black wash on top and a one
  point light edge.
- `StageButton` / `StageButtonStyle` with five kinds: `primary` (white fill, black type),
  `bare` (thin edge over the stage), `glass` (for bright parts of the picture), `danger`, `quiet`.
  Pressed lifts the fill and brightens the edge at 0.985 scale.
- `StatPips` is five pips filled from a 1 to 5 score, `WeightBar` is used of 100 kg and turns red and
  says "Over by 6 kg" the moment it goes over, `PartRow` is a picker row, `StageSegments` is the
  segmented control, `LiverySwatch`, `StageStat`, `StageHeading`.
- `StageBackdrop` (`Roboteer/StageSurface.swift`) is what a menu screen puts behind itself: nothing
  at all when the arena is live (so the real stage shows through the glass), the rendered still when
  it is not, plus the wash that keeps white capitals readable. `StageScrim` is the top down gradient.

Stills: `Roboteer/Resources/menu-stage.jpg` and `menu-stage-empty.jpg`, both 2048 x 1024 JPEG at
quality 80, downscaled from `Art/direction/menu-stage.png` and `menu-stage-empty.png`. The empty
stage is used on the screens whose own panels describe the machine. If a still is ever missing from
the bundle the backdrop falls back to a dark radial gradient rather than going black.

`ArenaHost.showsStill` is the switch: `(!rendersLive || !arenaReady) && surface == .stage`.
`rendersLive` is false only when this run was launched with a headless or dummy renderer, so the
OpenGL ES 3 simulator path counts as live and the stage is real there too.

## Data model

`Roboteer/BotBuild.swift`, SwiftData, one model.

| field | notes |
|---|---|
| `name` | 18 characters at most when renamed |
| `chassisID`, `driveID`, `weaponID`, `utilities` | catalogue ids only, never numbers |
| `frontMaterial`/`frontThickness` and the same for `sides`, `rear`, `top` | the four faces |
| `liveryHex` | one of six presets, never gold |
| `damageJSON` | the FightConfig `damage` block as text, carried between fights, empty means pristine |
| `fights`, `wins`, `kos`, `killedBy` | the record, written by the result sheet |
| `createdAt`, `isSelected` | the garage: capacity one in Stage 4, `Garage.selected(from:)` picks |

`spec` is the whole bot as a value (`BuildSpec`), which is what the rules and the builder work on.
`toBotConfig(id:controller:)` produces exactly the `FightConfig.bots[i]` shape of `bridge-spec.md`
plus `livery`. Wheel conditions are padded or truncated to the drive's own count (tracks report two,
one per side), so a drive change cannot send a four wheel damage block for a tracked machine.

`Garage.prepare(context:)` runs once at first appearance: an empty store gets Tinribs, the Stage 3
fixture bot (wedge, 4WD, flipper, srimech, steel 3 front, HDPE 2 sides, polycarbonate 1 rear,
titanium 2 top, 85.5 kg), with `assert(BuildRules.isValid(...))` in debug. Then `-build <name>`
selects by name.

The store is a plain `ModelContainer(for: BotBuild.self)`. If it will not open the app runs on an in
memory one rather than refusing to launch.

## The catalogue

`Roboteer/Catalogue.swift` reads `parts.json` from the bundle once, into `Catalogue.shared`.
`Shared/parts.json` is in the app target as a file reference outside the group
(`path = Shared/parts.json`, `sourceTree = SOURCE_ROOT`), so Swift and Godot read the same bytes and
nothing is copied by hand.

**Order matters and `JSONSerialization` has none**, so `Roboteer/JSONTools.swift` has a small
recursive descent parser (`JSONValue`) that keeps object keys in the order the file wrote them. The
player sees chassis in catalogue order: wedge, box, pyramid, long_low, tall_tank, shell.

The same file has `JSONText`, which writes JSON with **floats that stay floats**: every Double leaves
with a decimal point. `JSONSerialization` turns 1.0 into `1` and the arena would read a condition as
an int. This replaces the Stage 3 text template trick; `FightConfigFixture` now builds dictionaries.

Stat pips are the only derived numbers: each catalogue value is scaled across the catalogue's own
range onto 1 to 5, so a five really is the best in the list. Drives use top speed, turn rate and push
force. Weapons use reach, a single "hit" number (`impulse`, else `dps * 2500`, else
`impulse_bonus * 100`) and "setup", which is the spin up or reset time inverted so quick is high.
Measured: 2WD is speed 5 push 1, tracks is speed 1 push 5, the flamethrower has reach 5, the full
body spinner has setup 1.

## Rules

`Roboteer/BuildRules.swift` mirrors `docs/stage4-spec.md` section 1 exactly. Verified against the
shipped catalogue:

| build | result |
|---|---|
| Tinribs | 85.48 kg, no errors |
| all steel 4 on front, sides and top | "Over the weight budget by 16.4 kg." |
| shell + flipper | "The Shell only takes a full body spinner or a ram." |
| wedge + full body spinner | "A full body spinner only fits the Shell." |
| three utilities, two the same, no srimech | "Two utility slots at most." / "Fit two different utilities." / "A Wedge needs a srimech." |
| thickness 7 | "Armour thickness runs from 1 to 4." |

Plain sentences, no em dashes. The builder also steers rather than only complaining: choosing the
Shell swaps in a weapon it allows, choosing a full body spinner swaps in the Shell, and a chassis
that needs a srimech gets one.

## Message table

Everything still arrives at `ArenaHost.receiveRaw(type:json:)` on the main thread.

| direction | type | payload | what happens |
|---|---|---|---|
| Godot to Swift | `arena_ready` | `schema`, `godot_version` | as Stage 3, and any waiting `fight_config` **or** `workshop_config` goes out |
| Godot to Swift | `fight_state` | `state` | as Stage 3 |
| Godot to Swift | `fight_result` | FightResult v1 | as Stage 3, and the sheet writes the record |
| Godot to Swift | `workshop_ready` | `build_summary()` | parsed into `ArenaHost.workshopSummary` |
| Godot to Swift | `haptic`, `arena_log` | | as Stage 3 |
| Swift to Godot | `fight_config` | FightConfig plus `rules.mode` | one per fight, still no mid fight chatter |
| Swift to Godot | `workshop_config` | `{"bot": {...bot config...}}` | on every builder edit, debounced 150 ms, and whenever the menus come back |
| Swift to Godot | `test_reset` | `{}` | the RESET button in the test arena |

`workshop_ready` key names are read loosely, because `build_summary()` is P2's and does not exist
yet: `total_kg` / `total` / `total_weight` / `weight_total` / `mass_kg`; `clearance` / `clearance_m` /
`front_clearance` / `clearance_front`; `com_height` / `com_height_m` / `centre_of_mass_height` /
`center_of_mass_height`; and per category weights from a nested `weights`, `categories` or
`per_category` object, shown in the order they arrive. **An empty `{}` is expected and fine**: the
builder shows its own parts and armour totals instead and says the arena has not measured it yet.
Lengths are read as metres and printed as millimetres.

Two things the arena should know about `workshop_config`:

1. It is sent **after 150 ms of quiet**, not per change, and an identical configuration is never sent
   twice in a row. Every send is meant to re assemble.
2. It is also sent when the player leaves a fight, so a `workshop_config` arriving in the RESULT
   state must put the stage back up rather than being ignored.

`rules` now carries `mode`: `"fight"` (90 s, KO count 10 s) or `"test"`. The test configuration sends
`{"mode": "test", "ko_count_s": 10}` with **no `duration_s` at all**, and the opponent's
`controller` is `"dummy"`. If R2 would rather have an explicit `duration_s: 0`, say so and the shell
will send it.

The opponent is still the Stage 3 fixture machine, Scrapheap: wedge, 4WD, flipper, srimech, all
steel 2, now with `livery` `#8a2f24`.

## Launch arguments

| argument | effect |
|---|---|
| `-build <name>` | selects the garage build with that name, case insensitive |
| `-autoWorkshop` | opens the workshop at launch |
| `-autoFight` | opens the fight at launch, as Stage 3 |
| `-opponentAI idle\|charge\|normal` | goes out as `debug.opponent_ai` |
| `-autoSendFight` | the Stage 1 spike fixture, one second after `arena_ready` |
| `-godotDriver`, `-godotMethod`, `-godotDisplay`, `-godotVerbose` | unchanged, and a headless or dummy choice now also makes the menus use the rendered still |

## Layout

Landscape only, iPhone only. Every screen is laid out for the iPhone 17 at 874 x 402 pt and gets
wider from there: fixed width right hand columns (250 pt menu, 236 pt workshop, 250 pt builder) and a
flexible left. Text sits inside the safe area; only the backdrop, the still and the washes use
`ignoresSafeArea`. The validation panel prints at most four sentences, which is what fits at 402 pt
tall.

## Project file

`Roboteer.xcodeproj/project.pbxproj` is still hand written. Eight new Swift files and three
resources were added with fresh 24 hex ids on the existing `AA00...` pattern: file references
`...0070` to `...007A`, build files `...0080` to `...008A`. `Shared/parts.json` is the only file
reference outside the `Roboteer` group.

One build setting was added at the project level, in both Debug and Release:

```
"ARCHS[sdk=iphonesimulator*]" = arm64;
```

Without it a generic simulator build fails at the link, and it is not this code: the project now
points at a local `../../../Build/SwiftGodotKit` whose `libgodot.xcframework` carries an **arm64 only
simulator slice** (the OpenGL ES 3 work), so the x86_64 slice of a generic simulator build has
nothing to link against. Every Swift file compiles for x86_64; only the link fails. An Apple Silicon
Mac only ever needs arm64, so the setting is the honest fix. If an x86_64 simulator slice is ever
shipped, delete the line.

| build | result |
|---|---|
| `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet` | **green**, zero errors, zero warnings from our code |
| `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | **green**, zero errors, zero warnings from our code |

Both were run with the default DerivedData. If a build stops with "database is locked", another
agent is building the same project at the same time: wait for `xcodebuild` to leave and run it again.

## Traps found while doing this

1. **A second `GodotAppView` is not a second view of the same thing.** Both would call
   `DisplayServerAppleEmbeddedBridge.setNativeSurface` with their own layer and both would run a
   `CADisplayLink` that iterates the engine. That is why the surface moved to the root of the window
   instead of the menu owning one and the fight owning another.
2. **`JSONSerialization` loses key order and float ness**, and the catalogue needs the first while
   the bridge needs the second. One small parser and one small writer solve both, and they are worth
   more than the 300 lines they cost.
3. A method parameter named the same as a method (`func faceWeight(face: String ...)` calling
   `face(...)`) shadows the method and gives "cannot call value of non function type String".
4. `Color` is still ambiguous in any file that imports both SwiftUI and SwiftGodot, so
   `StageSurface.swift` writes `SwiftUI.Color`.
