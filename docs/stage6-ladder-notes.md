# Stage 6 ladder notes (agent L6: the async ladder and Game Center)

Written 2026-09-14. Companion to `docs/stage6-spec.md` section 3, `docs/brief-v3.md` section 10
(the async ladder) and section 12 (GameKit for leaderboards and ladder identity),
`docs/stage5-swift-notes.md` (the career engine and the filler generator this reuses) and
`docs/stage6-store-notes.md` (`Gates.ladderAvailable`). Everything here is `Roboteer/Ladder/**`
plus one entitlements file and four small marked insertions in files other agents own.
**Nothing in `Arena/` was touched and the Godot side needs nothing new.**

## What agent R needs: nothing

A ladder fight is an ordinary `fight_config`, byte for byte the shape `CareerFightView` already
sends. The ghost is the second bot with `"controller": "ai"`, `debug.opponent_ai` is `"normal"`,
`rules.mode` is `"fight"`, and the arena id is the one the player's own career tier fights in.
There is no new message type, no new key and no mid fight chatter. The arena cannot tell a ladder
fight from a career tie, and it does not need to.

**Never real time.** The opponent is a saved `BuildSpec`, not a person. Nobody is waiting.

## Files

| file | what it is |
|---|---|
| `Roboteer/Ladder/GameCenterService.swift` | `GKLocalPlayer` authentication, the display name, the owner id, and the two leaderboards. |
| `Roboteer/Ladder/LadderService.swift` | CloudKit public database, the Elo, the session cache, the generated fallback. |
| `Roboteer/Ladder/LadderView.swift` | LADDER: rating, record, opponents, Publish my build, Refresh, Fight. |
| `Roboteer/Roboteer.entitlements` | **new**: Game Center plus iCloud/CloudKit. `CODE_SIGN_ENTITLEMENTS` in both target configurations. |

Insertions in other agents' files, each one marked with `L6 (stage 6)`:

| file | insertion |
|---|---|
| `Roboteer/MenuView.swift` | one `case ladder` route, one `LadderView` destination, one LADDER button, one pad item, and two lines in `RootView.startInput()` (`GameCenterService.shared.start()`, `LadderService.shared.start()`). |
| `Roboteer/CareerModels.swift` | `FightLog.source` (`"career"` or `"ladder"`) with a default value, and the `FightLog.Source` constants. |

## Identity: who the player is on the ladder

`GameCenterService.shared`, one `@MainActor @Observable` instance, started once at launch from
`RootView.startInput()`.

- `GKLocalPlayer.local.authenticateHandler` is installed once for the life of the process, which is
  what GameKit asks for. When GameKit hands back a view controller it is presented from the key
  window's top view controller, because SwiftUI owns the whole window and there is no view
  controller of ours to hang it off.
- **`displayName`** is the Game Center alias when there is one, and otherwise a persisted local
  guest name of the shape **"Roboteer 4821"**, generated once and kept in `UserDefaults` under
  `ladder.guestName`. A guest's published machine therefore keeps the same name forever.
- **`ownerID`** is `GKLocalPlayer.local.gamePlayerID` when authenticated and a persisted
  `local-<UUID>` otherwise (`ladder.localOwnerID`). It is the CloudKit record name of the player's
  own `LadderBuild`, so it must never change under a player who has one.
- **Every failure is silent.** A player who is not signed in gets an error from the handler on
  every launch. It is logged and nothing else happens. There is no alert anywhere in this file.
- `-noGameCenter` skips authentication entirely, for QA.

### The two leaderboards

`GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)`, reported after every ladder fight
and after a reconcile:

| leaderboard id | what it carries |
|---|---|
| `ladder_rating` | the player's Elo |
| `career_wins` | `CareerState.wins`, all tiers |

The ids have to match App Store Connect **exactly** or a submission is dropped in silence, which is
why they are constants in one place (`GameCenterService.Leaderboard`). A submission while not
authenticated is skipped rather than attempted.

## Storage: the CloudKit record schema

Default container, **public** database. Two record types.

### `LadderBuild`

One per player. **The record name is the owner id**, so publishing is a fetch and save rather than
a query, and a player can only ever have one machine on the ladder.

| field | type | meaning |
|---|---|---|
| `ownerID` | String | the Game Center player id, or a local UUID for a guest |
| `displayName` | String | what the ladder prints, alias or guest name |
| `buildJSON` | String | the `BuildSpec` as JSON, sorted keys |
| `rating` | Int64 | Elo, 1200 to start |
| `wins` | Int64 | ladder wins |
| `losses` | Int64 | ladder losses |
| `updatedAt` | Date | when the machine was last published |

### `LadderResult`

A pending result addressed to somebody else, written when their ghost has been fought. They apply
it and delete it on their next launch.

| field | type | meaning |
|---|---|---|
| `targetOwnerID` | String | whose ghost was fought |
| `challengerName` | String | who fought it |
| `won` | Int64 | 1 when the challenger won (so the target lost) |
| `ratingDelta` | Int64 | what to add to the target's rating, already signed |
| `createdAt` | Date | when |

### What the owner has to set queryable in the CloudKit dashboard

A CloudKit field is not queryable or sortable until it is marked so. Without these the two queries
return an error, the app falls back to generated ghosts, and nothing looks broken, which is exactly
the failure that is hard to notice.

| record type | field | index |
|---|---|---|
| `LadderBuild` | `rating` | **Queryable** and **Sortable** |
| `LadderBuild` | `updatedAt` | **Sortable** |
| `LadderBuild` | `recordName` | **Queryable** (fetch by id) |
| `LadderResult` | `targetOwnerID` | **Queryable** |
| `LadderResult` | `recordName` | **Queryable** |

Public database security: the default `_world` read and `_creator` write is what this needs.
A `LadderResult` is written by the challenger and **deleted by the target**, who is not its
creator, so the `LadderResult` record type needs the **Authenticated** role given write access
(create and delete), or the deletes fail and a result is applied again on every launch. That is the
one permission worth checking after the schema is deployed.

## The entitlement: what the owner must do, in order

The app builds and runs with none of this done. The ladder simply stays offline.

1. **Apple Developer portal, Identifiers, `com.radicraft.roboteer`**: turn on **iCloud** and
   **Game Center**.
2. **iCloud Containers**: create **`iCloud.com.radicraft.roboteer`** and tick it for the App ID.
   The name has to match `Roboteer/Roboteer.entitlements` exactly.
3. In Xcode, target Roboteer, Signing and Capabilities: the capabilities are already declared by
   the entitlements file. Press the refresh on the provisioning profile so the new entitlements are
   in it. **An automatic signing build will fail with "no profile matching" until step 2 is done.**
   That is the one way this work can break the owner's device builds, and it is fixed in the portal
   rather than in the repo.
4. **CloudKit Console**: the two record types above are created by the first successful save from a
   development build. Then mark the indexes in the table above and **Deploy Schema to Production**
   before the app ships. A production build against an undeployed schema gets errors and falls back
   to the offline ladder for everybody.
5. **App Store Connect, Game Center**: create the two leaderboards with the ids `ladder_rating`
   (integer, high to low) and `career_wins` (integer, high to low). Until they exist the
   submissions are accepted by the device and dropped by the service, silently.

`Roboteer/Roboteer.entitlements` contains exactly three keys: `com.apple.developer.game-center`,
`com.apple.developer.icloud-container-identifiers` and `com.apple.developer.icloud-services`
(`CloudKit`). Nothing else. There is no key value store, no iCloud Documents and no push.

## The fallback, which is the part that matters

**Offline or unavailable CloudKit is not an error state. It is the ladder.**

Anything that stops CloudKit answering ends in the same place: no iCloud account, no entitlement,
a container that is not enabled, no network, an undeployed schema, a query that came back empty
because the ladder is thin at this rating. The service builds **eight ghosts** with
`CareerEngine.fillerEntrant(index:tier:rng:)` at the player's own career tier, gives them the
catalogue's invented roboteer names, and spreads their ratings around the player's own
(`[-140, -95, -55, -20, 15, 55, 105, 165]` plus a seeded jitter).

- The generator is seeded from the player's rating and the tier, so the list does not reshuffle
  every time the screen appears.
- The only thing the player is told is a quiet **"Offline ladder"** label. No alert, no retry
  button that implies something is broken, no red.
- A result against a generated ghost still moves the player's rating. It is simply never written to
  CloudKit, and the result panel says "This machine was generated, so nobody else was told."
- `LadderService.noteCloudFailure` is the one place failures land. For `notAuthenticated`,
  `permissionFailure`, `badContainer`, `missingEntitlement` and `managedAccountRestricted` it stops
  asking for the rest of the session, because nothing this session will fix those.
- `-noCloudKit` forces the offline ladder for QA, and it also means `CKContainer.default()` is
  never touched, which matters because that call **raises** rather than returning nil in a process
  with no iCloud entitlement.

## The loop

```
LADDER -> Publish my build -> pick an opponent -> Fight (ordinary fight_config)
  -> fight_result -> Elo moves locally -> FightLog tagged ladder -> leaderboards reported
  -> a LadderResult is written for the ghost's owner -> back to the list
```

- **Elo, K = 32.** `expected = 1 / (1 + 10^((theirs - mine) / 400))`, delta is
  `round(32 * (actual - expected))`, and a delta that rounds to zero is forced to plus or minus one
  so a win is never worth nothing. The rating floor is 100.
- The rating moves **locally first**, before any network call, so the result panel is instant and
  correct whatever CloudKit is doing.
- The `LadderResult` written for the ghost's owner carries **their** delta, computed from their
  rating against the player's pre fight rating. Their rating moves when they next open the app.
- `reconcilePending()` runs once at launch (from `RootView.startInput()`), applies up to 50 results
  addressed to this player, deletes them, republishes the new rating and reports `ladder_rating`.
  A delete that fails means the result is applied once more next launch. That is the known cost of
  doing this without a server, and it is why the delete permission above is worth checking.
- The machine carries its damage home from a ladder fight exactly as it does from a career tie, and
  the bot's record (fights, wins, knockouts) is written. **There is no scrap and no repair bill**:
  the ladder is not the career economy and cannot be farmed for money.
- The session cache is five minutes at the same rating. Refresh forces a refetch.

## The screen

`LadderView`, landscape, the Stage 4 design system, the Stage 5 layout rule (a `ZStack` of backdrop
and content, content ending in a top aligned `maxWidth`/`maxHeight` frame). Left column flexible,
right column fixed at 250 pt.

- The heading carries the player's rating and their win and loss record. The line under it is the
  display name, whether the ladder is offline, and whether the machine on screen has been published.
- Each opponent row is a glass panel: livery swatch, machine name, the roboteer's name, the parts
  line and weight, four stat pips (weapon hit and reach, drive speed and push), their rating, their
  record and a FIGHT button.
- The right column is PUBLISH MY BUILD, REFRESH, the selected machine's name and weight, the Game
  Center line, and BACK.
- Pad navigable: publish, refresh and then one item per opponent, with B for back. The result panel
  registers its own single item.
- **Gated**: `LockedPanel(reason: Gates.current.lockedReasonIfLocked(.ladder))` wraps the list, so a
  free player sees the whole ladder greyed with "The ladder unlocks with the full game." and can
  still walk out. Publish, Refresh and Fight are all disabled by the same gate rather than by the
  panel alone, so no path around the wall exists.

## Fight logs

`FightLog.source` is `"career"` or `"ladder"`. It has a default value, so this is a lightweight
SwiftData migration and every log written before Stage 6 reads back as a career tie. A ladder log
also fills in S6's `configJSON`, rebuilt from the same inputs and the safe area `CareerFightView`
sent, so a ladder fight is watchable in the replay screen like any other.

Ladder logs use `round = 0`, `scrapEarned = 0`, `repairCost = 0`, `opponentID` is the ghost's owner
id and `opponentName` is "Machine of Roboteer".

## Traps found while doing this

1. **`CKContainer.default()` raises, it does not return nil.** In a process with no iCloud
   entitlement it throws an Objective-C exception that Swift cannot catch, so the container is
   created lazily behind a flag and is never touched when `-noCloudKit` is passed. Every other
   CloudKit failure is an ordinary Swift error and is caught.
2. **An empty query result is not success.** A ladder with nobody on it is not a mode. An empty
   fetch falls back to the generated ghosts exactly as an error does.
3. **A CloudKit field is not queryable until somebody says so in the dashboard**, and the failure
   looks exactly like an empty ladder. The index table above is the first thing to check when the
   ladder is offline on a device that is signed in.
4. **The player deleting a `LadderResult` is not its creator.** Default public permissions let
   anybody read it and only the creator delete it, so without the Authenticated write role the
   same result is applied on every launch and a rating drifts on its own.
5. **`Int` and `Bool` in CloudKit.** There is no boolean field type; `won` is an Int64 of 1 or 0.
6. **A published build can be illegal by the time it is fought**, because the catalogue moves under
   it. Every spec read back from CloudKit goes through `CareerEngine.legalise` before it is sent to
   the arena, which is the same safety net the career's generated machines use.
7. **The rating must move before the network is asked.** Settling locally first and pushing
   afterwards is what makes the result panel instant and what makes the offline ladder identical to
   the online one from the player's side.

## Builds

| build | result |
|---|---|
| `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet` | **green** |
| `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | **green** |

Project file: three file references `AA00000000000000000000D0` to `...D2` plus the entitlements at
`...D3`, one group `...D8` named Ladder, three build files `...F0` to `...F2` in Sources. The
entitlements file has a file reference and no build file, on purpose.

If `xcodebuild` says the build database is locked, another agent is building the same project. Wait
and run it again.

## One thing the menu needs, and it is not the ladder's alone

The root menu column is a fixed 250 pt `VStack` with no scroll. After Stage 6 it holds eight
buttons: CAREER, LADDER, FIGHT, EVENTS, REPLAYS, WORKSHOP, BRIDGE SPIKE and SETTINGS. A non quiet
`StageButton` is about 46 pt tall and the spacing is 10 pt, so the column now wants roughly
`8 * 46 + 7 * 10 = 438 pt` inside about 335 pt of usable height on the 402 pt case (874 x 402 minus
26 pt top padding, 20 pt bottom padding and the landscape home indicator).

That is about two buttons of overflow. Per the Stage 4 layout rule the content is pinned with
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`, so it spills
**downward**: the title stays put and **BRIDGE SPIKE and SETTINGS go off the bottom of the screen**.
One of these is the only way into Settings.

It is not one agent's button that did this, it is the three that Stage 6 added together, so it
wants one decision rather than three. The cheap fixes, in order of least damage:

1. Wrap the column in a `ScrollView` with `.scrollBounceBehavior(.basedOnSize)`, which is what the
   other screens do with their lists.
2. Drop BRIDGE SPIKE behind a debug flag. It is the Stage 1 measurement screen and no player wants
   it.
3. Give the secondary rows `kind: .quiet`, which is about 38 pt instead of 46 pt.

Whoever closes the menu should pick one. The ladder does not care which.

## What is not done here

- Nobody else is on the ladder yet, so the online path has been exercised against an empty public
  database only. The first real two device test is owed and needs the portal steps above done first.
- The leaderboards have not been created in App Store Connect, so no submission has ever been
  accepted. The code path is silent by design, which means this cannot be proved from the app: it
  has to be seen in App Store Connect after the owner creates them.
- There is no Game Center dashboard button (`GKAccessPoint` or the leaderboard view controller).
  The brief asks for leaderboards and ladder identity, and both are here; a place to look at the
  leaderboard inside the game is a small addition if the owner wants one.
- Ratings are not decayed and there is no matchmaking beyond the rating window. Both would need a
  server to do properly and neither is in the brief.
