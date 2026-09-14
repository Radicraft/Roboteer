# Stage 5 Swift notes (agent S3: the career, the stable and the economy)

Written 2026-09-13. Companion to `docs/stage5-spec.md`, `docs/brief-v3.md` sections 4, 8, 9, 10 and
14, `docs/bridge-spec.md` and `docs/stage4-swift-notes.md`, which still holds for everything the
career does not touch. Everything here is `Roboteer/**`, `Shared/parts.json` and
`Roboteer.xcodeproj`. Nothing in `Arena/` was edited; `scripts/export-pck.sh` was run, which copies
`Shared/parts.json` to `Arena/data/parts.json` and rebuilds `Roboteer/Resources/arena.pck`.

## The one thing the Godot side must know

**`workshop_config` now carries an optional `mode`.**

```json
{ "mode": "scout", "bot": { ...the usual bot config... } }
```

The scouting report sends that, and it means: put the machine in this payload on the stage and orbit
it, because it belongs to the opponent, not the player. Everything else about the message is
unchanged, and a `workshop_config` with no `mode` at all is exactly the Stage 4 behaviour, so an
arena that ignores the key keeps working and simply stands the opponent's bot on the turntable
without orbiting. The bot in a scout payload has `"controller": "dummy"` and id `scout-1`.

**Career fights ask for arenas that are not the Yard.** `fight.gd` must select the scene from
`config.arena`. The ids are the ones already in the catalogue: `yard`, `grinder`, `drop_zone`,
`furnace`, `crush`, `coliseum`, and the tier decides which:

| tier | arena |
|---|---|
| Scrapyard | `yard` |
| Regional | `grinder` |
| National | `drop_zone` |
| Championship | `furnace` and `crush`, alternating by round (quarter final Furnace, semi final Crush, final Furnace) |
| Masters | `coliseum` |

Until A5's scenes land, an unknown arena id should fall back to the Yard and say so through
`arena_log` rather than failing to start the fight.

**Boss AI modes.** `bosses.<id>.ai_mode` in the catalogue is one of `pin`, `disable`, `herd`,
`wall`, `thrower`, one per boss. Nothing in the Swift shell sends them yet (bosses are Stage 6's
gauntlet and the inactivity punishment of spec section 4); they are in the catalogue now so B5 and
R can agree on the names. An unknown mode should behave as `normal`.

Nothing else in the contract changed. A career fight is an ordinary `fight_config`: one per fight,
no mid fight chatter, `rules.mode` `"fight"`, `debug.opponent_ai` `"normal"`, two bots, the second
with `"controller": "ai"`.

## The catalogue

`Shared/parts.json` gains four top level keys and **every existing byte is unchanged**. Both sides
read the same file (`res://data/parts.json` for Godot).

- **`career`**: `starting_unlocks` (13 part ids), `tier_order`, `filler_names` and
  `filler_roboteers` (24 each, for the made up entrants), and `tiers`, five of them, each with
  `entry_fee`, `purse`, `final_multiplier`, `garage_capacity`, `arenas`, `rounds`, `power_band`,
  `free` and `blueprints`.
- **`rivals`**: eight original roboteers, each with `name`, `roboteer`, `livery`, `from_tier`,
  `personality`, a valid `build`, three `grudge_lines` with `{player}` and `{bot}` placeholders, and
  `upgrades` keyed by tier, each a list of part swaps.
- **`bosses`**: the brief's five, each with a `build`, a `signature` string, an `ai_mode`, a
  `livery` and a `blurb`.
- **`economy`**: `price_factor` (chassis 10, weapon 12, drive 8, armour 6, utility 6),
  `write_off_threshold` 0.7, `scrap_for_parts` 0.4.

### The numbers

| tier | fee | purse | final | garage | arena |
|---|---|---|---|---|---|
| Scrapyard | 50 | 120 | 360 | 1 | Yard |
| Regional | 120 | 260 | 780 | 2 | Grinder |
| National | 250 | 520 | 1560 | 3 | Drop Zone |
| Championship | 500 | 1000 | 3000 | 4 | Furnace / Crush |
| Masters | 900 | 1800 | 5400 | 5 | Coliseum |

A new career opens with **300 scrap**, which pays the Scrapyard fee and still leaves a repair.

### The blueprint drip

Starting unlocks: `wedge`, `box`, `2wd`, `4wd`, `flipper`, `ram`, `saw`, `steel`, `hdpe`,
`polycarbonate`, `titanium`, `srimech`, `spare_battery`.

| tier | drip, in the order it is handed out |
|---|---|
| Scrapyard | axe, pyramid, vertical spinner |
| Regional | crusher, long low, 6 wheel, horizontal spinner, tracks |
| National | lifter, tall tank, omni, flamethrower |
| Championship | shell, full body spinner, skirts, scoop |
| Masters | counterweight, magnets, rear wedge |

One per win, and **the last win of a tier hands over everything that is left**, so a tier's drip is
always complete when the tier is. A bracket is three rounds, so the Regional's five parts arrive as
one, one, then three.

The free portion (Scrapyard and Regional, brief section 14) therefore **earns four weapons and two
chassis** on top of the three weapons and two chassis the player starts with. That is the "three or
four weapons and two chassis" the brief asks for, and the self test checks it. Every catalogue part
is either a starting unlock or dripped exactly once; the self test checks that too, so adding a part
to the catalogue without adding it to a tier is a FAIL rather than a part nobody can ever build.

## Data model

Four new `@Model` types plus two fields on the existing one. The container in `RoboteerApp` is now
`ModelContainer(for: BotBuild.self, CareerState.self, RivalRecord.self, FightLog.self)`.

| model | fields |
|---|---|
| `CareerState` | `tierRaw`, `bracketJSON`, `scrap`, `blueprints`, `garageCapacity`, `fightsPlayed`, `wins`, `championshipsWon`, `currentSeasonSeed`, `winsThisTier`, `pendingAssessment` |
| `RivalRecord` | `rivalID`, `name`, `roboteer`, `liveryHex`, `buildJSON`, `tierRaw`, `winsVsPlayer`, `lossesVsPlayer`, `lastResultWasTheirs`, `grudgeLines`, `lastMet`, `lastMetTier`, `lastMetRound` |
| `FightLog` | `date`, `tierRaw`, `round`, `opponentID`, `opponentName`, `botName`, `outcome`, `didWin`, `scrapEarned`, `repairCost`, `arena`, `resultJSON`, `replayJSON` |
| `BotBuild` (added) | `isWrittenOff`, `retiredAt` (`killedBy` was already there) |

`winsThisTier` is not in the spec's list but the drip needs it: it is the index into the tier's
blueprint list.

The bracket is **not** a model. `CareerBracket` is a plain `Codable` value kept as text in
`CareerState.bracketJSON`, so the shape of a tournament can change without a store migration. Eight
entrants, seven ties in one flat array (0 to 3 quarter finals, 4 and 5 semi finals, 6 the final);
the tie at round r slot s is fed by the winners of round r - 1 slots 2s and 2s + 1.

`BuildSpec` and `ArmourFaceSpec` are made `Codable` by hand in `CareerModels.swift`. Swift will not
synthesise Codable for a type declared in another file, and `BuildSpec` lives in `BuildRules.swift`,
which is S2's. **Both encoders set `.sortedKeys`**: a keyed container is unordered, so two identical
values encode to two different strings otherwise, and a season could not be compared to itself.

## The engine

`Roboteer/CareerEngine.swift` is pure: no SwiftData, no SwiftUI, no arena. `CareerStore.swift` is
the only place that reads or writes the store.

- **Randomness** is `SeededRandom`, SplitMix64, seeded from `CareerState.currentSeasonSeed`. The
  same seed draws the same eight entrants, the same filler machines and the same results in the
  ties the player is not in, on every device.
- **A season** is the player plus every rival whose `from_tier` has been reached (up to seven) plus
  filler machines to fill the field, shuffled, with the player inserted at a seeded slot. At the
  Scrapyard that is three rivals and four filler; at the Masters it is seven rivals and no filler.
- **Filler machines** are drawn from the parts unlocked at that tier, then grown by armour until
  they reach the tier's `power_band` fraction of the 100 kg budget, then legalised.
- **`legalise(_:)`** is the safety net every generated or upgraded build goes through: the weapon
  and chassis are made to agree, a chassis that needs a srimech gets one, then weight is shed in
  this order, armour first, then the second utility, then the drive, then the weapon. The last two
  steps are not decoration: a Shell with a full body spinner is 75 kg of parts before a single
  plate, so without them 17 of 200 generated machines came out over the budget. That was a real self
  test failure, not a hypothetical.
- **Ties the player is not in** are settled by comparing a `power(_:)` score (weapon hit and reach,
  drive speed and push, armour weight) with a seeded jitter. It is a comparison, not a simulation:
  the arena is the authority on real fights. When the player is knocked out the rest of the board is
  played out so a champion is still crowned.
- **Rivals keep their machine.** `rivalSpec(_:at:)` applies every tier's swaps in order from the
  rival's starting build, so the Clatterbox met in the Masters is the Scrapyard machine with four
  tiers of upgrades on it, and the record in the store carries the same spec.
- **Grudge lines** pick one of three by history: never met, they beat you last, you beat them last.
  `{player}` becomes the roboteer's name and `{bot}` the player's machine.

### The repair bill

`repairBill(for:damage:)` implements spec section 6: **condition lost times price**, part by part,
where price is the catalogue's factor times the part's weight in kilograms.

The arena reports six damage channels and the catalogue has five priced categories, so two are
mapped rather than copied, and this is the one place the engine makes a judgement:

- **chassis** takes the `core`'s loss;
- **drive** loses `1 - drive * mean(wheels)`, because a machine on two good wheels of four is half a
  drive even when the gearbox is fine;
- **armour** is per face, from that face's own weight;
- **utilities** take the `core`'s loss, because they ride the chassis.

`buildValue(_:)` is the same prices summed, so **a machine destroyed to nothing costs exactly its
own value to repair**, which the self test asserts. A write off is a bill over
`0.7 * buildValue`; stripping the wreck returns `0.4 * buildValue`.

## Screens

All new files. Career navigation lives inside `CareerRootView` as a `@State` screen switch rather
than in `MenuView`'s path, so the menu only had to learn one word and one route.

| screen | file | what it is |
|---|---|---|
| career home | `CareerHomeView.swift` | the tier in big capitals, the scrap balance in gold, the season state, record, garage slots and blueprint count, and ENTER FOR 50 / CONTINUE, BRACKET, GARAGE |
| bracket | `BracketView.swift` | the lit tournament board: four columns, eight slots, the player's tie edged in white, beaten machines struck through, the result note under each tie, the champion panel on the right |
| scouting | `ScoutingView.swift` | the opponent's card (name, roboteer, parts, armour, weapon and drive pips), the grudge line, the history line, and CHOOSE YOUR BOT over the stable. The stage behind it is showing THEIR machine |
| career fight | `CareerFightView.swift` | the same bare Godot view as `FightView`, with the arena's name on a capsule during the countdown |
| damage assessment | `DamageAssessmentView.swift` | the bill part by part with the percentage gone, the total against the machine's value, REPAIR / WRITE OFF / LEAVE IT, the purse and salvage, the "New blueprint: Axe" flourish and the rival's line |
| garage | `CareerGarageView.swift` | the stable at the tier's capacity, empty slots and the locked slot, BUILD, NEW BOT (gated by capacity), BLUEPRINTS, RENAME, REPAIR with its price |
| blueprints | `CareerGarageView.swift` | five columns of every part, ticked or locked with "Earned at Regional" |

The builder's pickers respect unlocks: `LockGate` greys a locked row to 34 %, takes its hit testing
away and puts a lock capsule with the earning tier on it. Armour materials are all starting unlocks,
so the material segments are not gated yet; when a material is ever dripped, that is the one place
that will need the same treatment.

**With no career started the builder shows only the starting unlocks**, because nothing has been
earned. That is deliberate rather than a bug: Tinribs and the default new bot are built entirely
from starting unlocks, so a player who never opens CAREER can still build and fight.

Every screen follows the Stage 4 layout rule: a `ZStack` of backdrop and content, content ending in
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` so overflow spills down
rather than lifting the header off the top. Landscape, 874 x 402 pt upward, fixed right hand columns
(250 pt home, 250 pt scouting, 264 pt assessment, 236 pt garage). No em dashes anywhere.

Each career screen registers its own `PadFocus` items with a `back:` action, so S2's controller
navigation works inside the career and menu items do not stay live underneath.

## The loop

```
CAREER -> home -> Enter (fee deducted, bracket drawn) -> bracket -> scouting report
  -> choose a bot -> fight -> damage assessment -> repair or write off -> bracket or home
```

- Losing ends the season. The fee is gone, the bill still stands, and the board plays itself out.
- Winning the final advances the tier, raises the garage capacity and completes the drip. The board
  from the season just won stays on screen under its own tier's name until a new one is entered.
- The purse is paid per win and the tier's `final_multiplier` applies to the last round.
- The machine carries its damage home exactly as a quick fight does, so LEAVE IT FOR NOW is a real
  choice and the garage prints the outstanding bill.

## Messages

Only the two rows marked new are different from `docs/stage4-swift-notes.md`.

| direction | type | payload | what happens |
|---|---|---|---|
| Swift to Godot | `workshop_config` | `{"bot": {...}}` or **new** `{"mode": "scout", "bot": {...}}` | the stage, or the scouting orbit |
| Swift to Godot | `fight_config` | **new**: `arena` may be any of the six ids, both bots are real builds | a career tie |
| everything else | | | unchanged, including S2's `settings` |

`ArenaHost` gained `sendWorkshopConfig(_:mode:)`, `startCareerFight(configJSON:)` and
`scoutingOpponent`, which is what stops `MenuView` putting the player's own bot back over the
scouting orbit when the selected build changes.

## Launch arguments

Every Stage 3 and Stage 4 flag still works. New ones:

| argument | effect |
|---|---|
| `-careerSelfTest` | runs the whole career engine through a scripted season at launch and prints one PASS or FAIL line per invariant, then a summary. Pure, changes nothing |
| `-career <fixture.json>` | clears the store and loads a saved career. The value may be a bundle resource name, a file name or an absolute path. Opens CAREER at launch |
| `-autoCareer` | opens CAREER at launch without loading a fixture |

## The self test

There is no test target, so `CareerSelfTest` is the tests. **172 checks, all passing.** It covers
the catalogue's shape, the tier numbers, the drip's completeness and the free portion's contents,
every rival and boss build at every tier, two hundred generated filler machines, the price and
repair formulas at both ends, the season's shape and its determinism, a whole scripted season won
three ties in a row with the scrap arithmetic asserted (500 - 50 + 120 + 120 + 360), a season lost
in the quarter final, and the rival memory's three branches.

It found three real defects while being written: filler Shells that could not be made legal, a
determinism check that was really testing JSON key order, and a grudge line check comparing
substituted text to the raw catalogue string.

To run it without a simulator, the pure files compile as a command line binary on the Mac. That is
how the 172 checks above were actually run:

```
cp Roboteer/{JSONTools,Catalogue,BuildRules,FightResult,BotBuild,CareerModels,CareerCatalogue,CareerEngine,CareerSelfTest}.swift /tmp/harness/
# point Catalogue.load and CareerCatalogue.load at Shared/parts.json instead of Bundle.main,
# add a stub for `spikeLog` and `ArenaHost.hasLaunchFlag`, and a main.swift of one line
xcrun swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.0 *.swift -o selftest && ./selftest
```

## Fixtures

`Roboteer/Fixtures/career-regional.json`, in the bundle. A career part way through the Regional:
640 scrap, one tie already won, the Scrapyard drip plus the Regional's first blueprint, a two slot
garage and **three machines, one of them written off** (Bodkin, killed by Hob Nail). Three rival
records carry history, and Hob Nail beat the player last, so the scouting screen shows its second
line. The season is redrawn from the fixture's own seed and then run forward by the wins the fixture
claims, so the bracket is always consistent with the state rather than being stored twice.

## Project file

Eleven new Swift files and one new resource, file reference ids `...0090` to `...009B` and build
file ids `...00B0` to `...00BB`, following `docs/stage1-build-notes.md`. S2 took `...007B` to
`...007D` and `...008B` to `...008D` in the same session, which is why the career skipped to 0090
and B0.

| build | result |
|---|---|
| `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet` | **green**, zero errors, zero warnings |
| `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | **green**, zero errors, zero warnings |

If a build stops with "database is locked", another agent is building the same project: wait for
`xcodebuild` to leave and run it again. That happened twice while this was written.

## Traps found while doing this

1. **Swift will not synthesise Codable across files.** `extension BuildSpec: Codable {}` in a file
   that does not declare `BuildSpec` is an error, not a warning. Both conformances are written out.
2. **A keyed container is unordered**, so two equal values encode to two different JSON strings and
   `encoded() == encoded()` is not a determinism test. `.sortedKeys` on the encoder, and compare
   values rather than text.
3. **A generated build can be impossible, not just heavy.** Shaving armour is not enough to make a
   Shell with a full body spinner legal; the reduction has to be able to reach the drive and the
   weapon or the machine can never fit the budget.
4. **`??` erases tuple labels.** `entry?.powerBand ?? (0.6, 0.8)` turns a `(low:high:)` tuple into a
   plain one and `band.low` stops compiling. Label the fallback.
5. **`fullScreenCover(item:)` needs an `Identifiable`** and `PersistentIdentifier` is not one, so
   the garage wraps it in a one field struct.
6. The scouting stage and the menu's own stage send compete: the menu re sends the player's bot
   whenever the selected build changes, which would pull the opponent off the turntable. Hence
   `ArenaHost.scoutingOpponent` and one extra clause in `MenuView.sendStage`.

## What is not done here

- Bosses are in the catalogue with builds, signatures and AI modes, but nothing spawns them. The
  gauntlet events and the inactivity punishment of spec section 4 are B5's and Stage 6's.
- `FightLog.replayJSON` is written for every career fight and nothing reads it yet. That is Stage 6.
- The Stage 6 paywall reads `career.tiers.<id>.free` and `arenas.<id>.free`, both already in the
  catalogue. Nothing is gated yet: every tier is enterable.
- Side events, Sumo, the async ladder and quick fight arena choice are not career and are untouched.
