# Stage 6 store notes (agent P6: the single unlock purchase and the content gates)

Written 2026-09-13. Companion to `docs/stage6-spec.md` section 5 and `docs/brief-v3.md` sections 9
and 14. Everything here is `Roboteer/Store/**` plus four small marked insertions in files other
agents own. Nothing in `Arena/` was touched.

## The rule this stage exists to keep

**Nothing inside the game is purchasable.** One non-consumable, `com.radicraft.roboteer.unlock`,
one price, offered in exactly two places, never during a fight, never on a timer, never at a
discount. Every weapon, chassis, material and blueprint is earned by playing. If a future diff adds
a second product, a consumable, a "starter pack", a timed offer or a third place that presents the
unlock screen, that diff is wrong.

## Files

| file | what it is |
|---|---|
| `Roboteer/Store/StoreService.swift` | StoreKit 2. Loads the one product, buys it, restores it, listens for updates, publishes `isUnlocked`. |
| `Roboteer/Store/Gates.swift` | The pure gate type. Give it a bool and it answers every question the wall poses. |
| `Roboteer/Store/UnlockView.swift` | The one unlock screen, plus `View.unlockScreen(isPresented:host:onDismiss:)`, which is the only way to present it. |
| `Roboteer/Store/LockedPresentation.swift` | `LockedBadge`, the `.lockedRow(...)` modifier and `LockedPanel`, the three ways a locked thing is drawn. |
| `Roboteer/Store/Roboteer.storekit` | The local StoreKit configuration, referenced by the shared scheme's run action. |

Insertions in other agents' files, each one marked:

| file | insertion |
|---|---|
| `Roboteer/SettingsView.swift` | the placeholder "Restore purchases" row is now live, and a "The full game" row above it opens the unlock screen. |
| `Roboteer/MenuView.swift` | one line in `RootView.startInput()`: `StoreService.shared.start()`. |
| `Roboteer/CareerGarageView.swift` | `CareerUnlocks.lockNote(for:)` asks `Gates.snapshot` first, so a part behind the wall says "Unlocks with the full game." instead of "Earned at National". |

## StoreService

`@MainActor @Observable final class StoreService`, one shared instance. Published: `isUnlocked`,
`product` (for the localized display price), `state` (`idle`, `loading`, `purchasing`,
`failed(message)`), `notice` (a plain sentence that is not an error) and `didLoad`.

The entitlement is settled from three places:

1. `Transaction.currentEntitlements` at launch. This is the local receipt, so it works offline and
   it never asks for a password. A revoked transaction (a refund, a withdrawn Family Sharing grant)
   closes the door again.
2. `Transaction.updates`, one listener for the life of the process, started before the launch pass.
   This is what catches a purchase made on another device, an Ask to Buy approval landing days
   later, and a Family Sharing grant arriving.
3. `AppStore.sync()` from the Restore purchases row. **The only call in the app that can ask for an
   Apple Account password, and it only ever runs because the player pressed the row.**

`start()` is idempotent and is also called by the initialiser, so touching `StoreService.shared`
from anywhere is enough to get the entitlement moving. `MenuView` calls it explicitly at launch so
the entitlement is settled before the first screen asks a gate.

`purchase()` handles all four outcomes: verified (unlock, `finish()`, done), unverified (a sentence
pointing at Restore purchases, no unlock), pending (Ask to Buy: no error, a sentence saying the
game unlocks by itself when it goes through, and the listener does exactly that), and cancelled
(silence, back to idle, no nagging).

Every player facing sentence is plain and has no em dash.

### The QA override

`-unlocked` and `-locked` on the scheme (DEBUG builds only; `-locked` wins if both are passed).
They settle `isUnlocked` before anything asks and they suppress the payment sheet, so:

```
-unlocked    the whole game, for shooting screenshots and for testing the paid half
-locked      the free half, which is the half that needs testing
```

There is no override on a device Release build: the `#if DEBUG` makes sure of it.

### The StoreKit configuration file

`Roboteer/Store/Roboteer.storekit`: one non-consumable, reference price 4.99, storefront GBR,
locale en_GB, **Family Sharing on**. The shared scheme's `LaunchAction` carries

```xml
<StoreKitConfigurationFileReference
   identifier = "../../../Roboteer/Store/Roboteer.storekit">
</StoreKitConfigurationFileReference>
```

so a simulator run can buy the product for real (Xcode's local store), see the price come back as
£4.99, and test Restore. The file is a project file reference only: it is deliberately **not** in
the Resources build phase, because it must never ship inside the app. The price in it is a local
test value; the real price is set in App Store Connect and the UI only ever prints
`product.displayPrice`.

## Gates: how every other screen asks

`Gates` is a pure struct over one bool, so the wall is provable by reading one file.

```swift
let gates = Gates.current          // on the main actor, which is every view
let gates = Gates.snapshot         // off the main actor (a nonisolated helper, e.g. a lock note)
```

| question | answer |
|---|---|
| `tierAvailable(.national)` | false while locked. Reads the catalogue's own `career.tiers.<id>.free` flag, so the data decides, not this file. |
| `arenaAvailable("furnace")` | false while locked. Free: `yard`, `grinder`, and `test`, which is never gated. |
| `bossAvailable("cinder")` | true always. The other four are false while locked. |
| `partAvailable("flamethrower")` | false while locked. The free library is `career.starting_unlocks` plus the Scrapyard and Regional drips, read from `Shared/parts.json` (`CareerCatalogue.unlocks(upTo: .regional)`), with a hardcoded fallback if the career block ever goes missing. |
| `garageCapacity(forTier: .masters)` | the tier's capacity, capped at 2 while locked. |
| `sideEventsAvailable`, `replaysAvailable`, `sharingAvailable`, `ladderAvailable` | false while locked. |
| `careerAvailable`, `quickFightAvailable`, `testArenaAvailable` | true, always. The free half has to be a game, not a demo. |
| `lockedReason(.arena("furnace"))` | "The Furnace unlocks with the full game." |
| `lockedReasonIfLocked(_:)` | the sentence, or **nil** when the thing is open. This is the shape views want. |

### What S3 and S6 still have to wire

The gates answer; the screens draw. Each of these is one line:

```swift
// A tier row on the career home screen
tierRow(tier)
    .lockedRow(Gates.current, .tier(tier))

// An arena row in quick fight
arenaRow(id)
    .lockedRow(Gates.current, .arena(id))

// A garage slot past the second
slotRow(slot)
    .lockedRow(Gates.current, .garageSlot(slot))

// The events, replays and ladder screens, whole
LockedPanel(reason: Gates.current.lockedReasonIfLocked(.sideEvents)) { eventsList }
```

and the two that are not presentation:

- **Entering a tier**: `CareerEngine` must refuse to advance past Regional while
  `!Gates.current.tierAvailable(next)`. The Regional final still resolves and still pays; the
  player is simply at the wall.
- **Garage capacity**: `CareerState.garageCapacity` is the earned number. Read the usable one
  through `Gates.current.garageCapacity(forTier:)` so a player who bought, played and refunded
  cannot keep five bots. Nothing is ever deleted: the extra machines stay in the store and come
  back the moment the game is unlocked again.

The builder is already wired: its picker rows go through `LockGate`, and `CareerUnlocks.lockNote`
now returns "Unlocks with the full game." for anything outside the free library while the game is
locked. The badge is one line with `minimumScaleFactor`, so the long sentence shrinks rather than
wrapping; if that reads badly on the 402 pt case, shorten the part sentence in
`Gates.lockedReason(.part)` rather than changing the badge.

## Where the wall is offered, and nowhere else

1. **Once, after the Regional final.** The career screens call

```swift
if Gates.shouldOfferAfterRegionalFinal {
    Gates.markRegionalOfferShown()   // set it as the screen appears, not when it closes
    showUnlock = true
}
```

   `markRegionalOfferShown()` persists `store.regionalOfferShown` in UserDefaults. Setting the flag
   as the screen appears rather than when it closes means a crash on the unlock screen cannot turn
   one offer into two. `Gates.resetRegionalOffer()` exists for QA only.

2. **The Settings row**, permanently: "The full game", with the live price as its value, and
   "Restore purchases" under it.

Nothing else may present `UnlockView`. It is reachable only through
`View.unlockScreen(isPresented:host:onDismiss:)`, which is a full screen cover, so grepping for
`unlockScreen(` finds every place the wall can appear. There are two.

The screen itself: what the free game gave on the left, what the full game adds in the middle, the
price and the buttons on the right, and the sentence "One purchase. No subscription, no ads, no
other purchases." in the header. The price is never hardcoded in the UI; while the store has not
answered it says "Loading the price" and after a failed load "Price unavailable", and the buy
button still works because the payment sheet carries its own price.

## App Store notes for the owner

- **Product**: one non-consumable, product id **`com.radicraft.roboteer.unlock`**, reference name
  "Roboteer full game unlock", display name "The full game". Price tier **£4.99** (UK), with Apple
  setting the equivalents elsewhere. The id has to match exactly or the app shows no price.
- **Family Sharing is a checkbox in App Store Connect**, on the in-app purchase itself
  (In-App Purchases, the product, Family Sharing, Turn On). It costs nothing and it is worth real
  goodwill. The app needs no code for it beyond what is already here: a shared entitlement arrives
  through `Transaction.updates` and through `currentEntitlements` on the next launch.
- **Review notes**: the reviewer needs to reach the wall. Tell them the free half is the Scrapyard
  and Regional circuits and the unlock row sits in Settings, so they can buy without playing four
  hours.
- **The store page sentence, to be used as written** (no em dashes, plain):

  > Free to play the Scrapyard and Regional circuits. One £4.99 purchase unlocks everything
  > forever: the National, Championship and Masters circuits, four more arenas, four more arena
  > bosses, the full part library, five garage slots, side events, replays and the ladder. No other
  > purchases, no subscription, no ads.

  A stated wall is a selling point in a category defined by gacha. A surprise one earns one star.
- **The owner submits.** Nothing in this repo presses Add for Review, picks a build or releases.

## Traps found while doing this

1. **A static gate helper can read a stale entitlement forever.** `Gates.snapshot` reads a
   nonisolated mirror of `isUnlocked`, and a mirror is only correct if something instantiated the
   service. That is why `StoreService.shared` starts itself in its initialiser *and* why
   `MenuView` calls `start()` at launch. Reading `Gates.snapshot` alone would otherwise report
   "locked" to a paying customer for the whole session.
2. **The `@Observable` macro and `didSet` do not mix**, so the nonisolated mirror is kept in step
   by a single `setUnlocked(_:)` funnel rather than a property observer. Every assignment to
   `isUnlocked` goes through it; there are seven.
3. **A full screen cover steals the pad.** `PadFocus` is one object for the whole app, so the
   unlock screen registers its own items on appear and the presenting screen registers its rows
   again in the cover's `onDismiss`. Without that, Settings comes back with a dead pad.
4. **Pending is not a failure.** Ask to Buy returns `.pending` and the right answer is a sentence
   and silence, not an error: the update listener unlocks the game whenever the approval lands,
   possibly days later in another session.
5. **The blueprint gate and the purchase gate are different questions.** A part can be locked
   because it has not been earned yet (career) or because it is behind the wall (store). The
   sentence has to say which, or a free player is told to earn something at a tier they cannot
   enter.
6. The `.storekit` file must stay out of the Resources build phase. It is a scheme reference, not
   an app resource, and shipping it would put a test price inside the binary.

## Builds

| build | result |
|---|---|
| `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator' -quiet` | **green** |
| `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet` | **green** |

Project file: five file references `AA00000000000000000000C0` to `...C4` (four Swift files and the
`.storekit`), one group `...C8` named Store, four build files `...E0` to `...E3` in Sources. The
`.storekit` has a file reference and no build file, on purpose.

If `xcodebuild` says the build database is locked, another agent is building the same project. Wait
and run it again.
