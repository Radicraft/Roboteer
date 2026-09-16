# Wave V, agent V3: the broadcast package

Written 2026-09-16. `docs/design-system.md` sections 1, 2, 3, 5 and 6 in Swift, across every screen
the shell owns. Brief v4 (`docs/brief-v4-playtest.md`) section 7 is the reason the system exists;
this is the half of it that is not the arena.

Nothing in this pass changes a flow, a piece of data or a rule. Every screen shows the same things
to the same taps; they are drawn in the Broadcast system instead of the 2026-09-13 cinematic one.

## The one file

**`Roboteer/DesignSystem.swift` is the whole system.** It was rewritten rather than extended, and it
keeps every name the screens were already written against, so a screen that says `Stage.text`,
`GlassPanel`, `StageButton` or `StatPips` picks up the new look without being touched. The old names
now point at the spec's tokens:

| old name | now |
|---|---|
| `Stage.text` / `textDim` / `textFaint` | `type` #F4F6F8 / `typeDim` #9CA6B2 / `typeDim` at 72 % |
| `Stage.edge` / `edgeBright` | `glassEdge` (white 10 %) / `line` (#35D6F0), because a bright edge means "selected" and selection is cyan |
| `Stage.panel` / `panelDeep` / `ground` | `glass` / `glassDeep` / `ink` |
| `Stage.gold` / `good` | `scrap` #F0B23A / `win` #5BE38F |
| `Stage.corner` | 10, the cut, not a radius |

New in the file, and what the spec calls them:

- **`CutRect`** is the shape. There are no rounded rectangles left in the app: every plate, chip,
  row and badge is a rectangle with one cut corner, top right, clamped to 10 pt. The conversion was
  mechanical (`RoundedRectangle(cornerRadius: n, style: .continuous)` to `CutRect(n)`), which is why
  it reached every screen in one pass.
- **`PanelChrome` / `Panel` / `GlassPanel`**: `glass` fill, a `glassEdge` hairline on the top and the
  left only, the cut corner, a `line` hairline along the bottom.
- **`LowerThirdShape` / `LowerThirdBarShape` / `LowerThird`**: the 12 degree lean with the 3 pt bar
  on the leading edge, and the 0.25 s entrance from the edge it belongs to.
- **`ScoreBug`**: label over tabular numerals in a `line`-rimmed plate. Scrap, the tier strip, the
  money on the next-fight card.
- **`HairRule`** (`typealias Rule`): 1 px `lineDim`, never thicker, never a box. Every
  `Divider().overlay(Stage.edge)` in the app became one.
- **`Ticker`**: one line at a time, in from the right edge at 120 pt/s, the next waiting for the one
  before it to clear. On the menu it runs the season news.
- **`CountingNumber`** and `CountingStat`: numbers count over 0.4 s. Used on the settlement's purse
  and salvage, the scrap bug on the settlement, and the result sheet's scrap.
- **`BroadcastButtonStyle`** (`typealias StageButtonStyle`) and `StageButton` (`typealias
  BroadcastButton`): a button IS a lower third. Focused, the fill sweeps to `line` at 18 % from the
  leading edge in 0.15 s and the bar goes to full; pressed, `line` at 30 % with an `ink` label.
  Primary is 54 pt tall, secondary 36, quiet 30, which is the spec's 1.5x. Danger swaps `line` for
  `danger`. Nothing scales and nothing bounces.
- **`BroadcastArt`**: V1's raster art by name, every lookup allowed to fail.

## Type

**Barlow Condensed ships and is what you are looking at.** V1's four faces landed in
`Roboteer/Fonts` during this pass and are in the build.

- `Roboteer/Fonts` and `Art/ui` are **folder references** in the project (blue folders), so a build
  taken while either was still empty succeeds and the files ship the moment they appear. That was
  deliberate: the wave started with both folders empty.
- `Roboteer/Info.plist` is new and carries exactly one key, `UIAppFonts`, with the four faces under
  their `Fonts/` prefix. `GENERATE_INFOPLIST_FILE` stays `YES` and `INFOPLIST_FILE` now points at
  this file, so Xcode merges its own keys (bundle identity, scene manifest, launch screen, the
  landscape-only orientations, controller support) into it and the hand written half never has to be
  kept in step. Verified in the built `Info.plist` on both SDKs.
  **`INFOPLIST_KEY_UIAppFonts` does not work**: the generator writes unknown keys as strings and
  `UIAppFonts` has to be an array. That was tried first and produced no key at all.
- `BroadcastType.register()` runs in `RoboteerApp.init` and registers every font file in the bundle
  by hand as well, which is what makes a folder reference work whatever path the files land at. If
  the family is ever missing, every role falls back to the system condensed face at the same weight
  and `BroadcastType.familyNote` says so in the launch log. No screen changes shape either way.
- **The legibility floor of section 7 is enforced in the font helpers**: `Stage.label` clamps to
  11 pt and `Stage.body` to 13 pt whatever a screen asks for. That is the single biggest layout
  change in this pass and it broke three screens, all fixed below.
- Numerals are tabular through a font descriptor feature, not `monospacedDigit()`, which only speaks
  for the system family.

## Screen by screen

- **Main menu.** Title as display type top left, the machine's name and parts on a lower third under
  it, the scrap bug top right, four lower-third buttons (CAREER primary, QUICK FIGHT, WORKSHOP,
  EVENTS), the quiet corner as label-size text buttons (LADDER, REPLAYS, SETTINGS, plus SPIKE with
  `-showSpike`), and the ticker along the bottom carrying the season news. The FIGHT button is now
  called QUICK FIGHT, which is what it does.
- **Career season screen.** The tier strip is five score bugs joined by one rule, with the wall drawn
  as FULL GAME between the last free circuit and the first locked one. The next-fight card has a
  lower-third header and the money as a row of score bugs.
- **Garage, workshop, builder, career garage.** Machine live on the left, panels in the right column
  only, `frame` 0.28, `StageOrbitPad` in the clear area: unchanged, restyled.
- **Quick fight, events, ladder, replays, settings, onboarding, unlock, locked states.** Panels,
  lower thirds, cut corners and the cyan selection. Every pill in the app (the locked badge, the
  simulator note, the fight banners) became a cut plate; there are no capsules left outside the
  volume bar, which is now a plain bar.
- **Pause.** An `ink` 70 % wash and one panel, per section 5.
- **Result and settlement.** A display banner: WON in `win`, LOST in `danger`, on a lower third that
  comes in from the left, with the kind of win beside it. Damage lines are stat strips. Scrap, the
  purse and the salvage count up.
- **Scouting sheet.** Name, parts, then the money as score bugs, then the arena and the house bot,
  then the pips and the grudge line.
- **Bridge spike.** The Stage 1 diagnostic screen was on iOS system colours; it is now on the
  tokens. It is still a diagnostic screen.

## Backdrops

`StageBackdrop` takes a `keyArt:` name. The menu asks for `menu_keyart`; V1's art ships under `ui/`
in the bundle and is found by `BroadcastArt`. **The ink ground is only ever painted when there is no
live picture** (`host.showsStill`), because the one Godot view is below every screen and an opaque
full-bleed colour above it hides the arena. That rule is from `docs/stage4-swift-notes.md` and it is
the easiest way to black out the whole game by accident.

If a piece of art is missing the screen falls back to the rendered still and then to the ink wash,
and says nothing about it. Nothing's chrome depends on any raster asset: panels, lower thirds, bugs,
rules and buttons are drawn.

## What the type floor broke, and what was done

1. **The full bracket board slid off the top and the bottom.** Eight machines at two lines each
   (name over roboteer) came to 440 pt on a 402 pt screen, and an oversized child in a `ZStack` is
   centred, so the header and the SCOUTING REPORT button went off screen. Each slot is now ONE line
   (name, then the roboteer in label type), the later rounds are offset by a fixed amount instead of
   `maxHeight: .infinity`, and the board sits in a vertical `ScrollView` so no future change can do
   it again.
2. **The season screen sat 70 pt too low and the next-fight card was below the fold.** Two causes.
   `Color.clear.frame(width: 8)` in the tier strip is infinitely flexible vertically, so the strip
   claimed a share of the screen's height; it is `frame(width: 8, height: 1)` now. And the compact
   bracket's columns used `maxHeight: .infinity`, which made the panel as tall as the space it was
   given. **The card is now above the bracket in the scroll**, which is the other way round from
   brief v4 section 6: the bracket of eight is 150 pt of a 402 pt screen and the card is what has to
   be read before FIGHT, so the card is what you land on. The whole board is a flick down and FULL
   BOARD still opens it outright.
3. **The settlement overflowed both ways.** The right column's panels plus two buttons came to about
   420 pt. The panels now scroll and the answers are pinned under them.

Two more layout calls made from the screenshots:

- **Every number the player can be charged is above the fold**, not merely on the card. The entry,
  the purse and any repair bill are a row of score bugs immediately under the opponent's parts line,
  on both the card and the scouting report. Brief v4 section 6 asks for them "on screen before the
  FIGHT button" and on a 402 pt phone that has to mean without a scroll.
- **The result sheet's BACK TO GARAGE is pinned**, not scrolled to. A player who has just lost has to
  be able to leave without reading the judges' card first.

## One deliberate departure from section 5

Section 5 draws the main menu with "four lower-third buttons stacked left". They are stacked in the
RIGHT column instead. The menu is a stage screen: the player's machine stands at
`StageLayout.botFrame` (28 % across) and the left 45 % of every stage screen stays clear of chrome.
That rule exists because the owner played the first build and could not see his own machine
(`docs/stage4-swift-notes.md`), and it outranks the sketch. Everything else in section 5's menu is
where it says: title top left, scrap bug top right, the quiet text buttons bottom right, the ticker
along the bottom.

Section 5 also calls the workshop "GARAGE". The button still says WORKSHOP, because that is what the
screen it opens is called and the career has its own garage. One word, the owner's call.

## New QA flags

The simulator cannot take a touch, so most of the package could not be reached to be photographed.
These are additive, presentation only, and documented in `docs/qa-launch-flags.md`:

`-autoEvents`, `-autoReplays`, `-autoLadder`, `-autoSettings`, `-autoQuickFight`, and with a career
loaded, `-autoBracket`, `-autoScouting`, `-autoCareerGarage`, `-autoCareerFight` (starts the next tie
straight away, which is how the settlement was reached), `-autoUnlock`.

## The touch forwarder (coordinator's bug, fixed in this pass)

**Career fights did not answer the stick; quick fights did.** `FightView` has
`FightTouchForwarder()` as the first child of its `ZStack` and `CareerFightView` did not. The one
Godot view is a sibling BELOW the navigation controller's container view, and that container answers
`hitTest` with itself even when it is clear, so on a pushed fight screen no touch reaches the engine
unless something hands it over (`StageSurface.swift`, "Fight touches").

The forwarder is now the first child of the `ZStack` in **`CareerFightView`** (which the async ladder
also uses, so ladder fights are covered) and in **`EventFightView`**, with the banner, the leave
button and the pause overlay above it. The workshop, the builder, the menu and the career screens
keep `StageOrbitPad` and must NOT get the forwarder: the orbit pad reads the gesture itself and sends
it as `stage_camera`.

## Verification

- `scripts/build-device.sh`: **BUILD SUCCEEDED**, no errors, no warnings from our code.
- `scripts/build-sim.sh` is new, a copy of the device script with the same serialised lock, for
  layout checks only. **It does not pass `-sdk iphonesimulator`**, which the task asked for: that
  flag makes Xcode build the SwiftGodot macro plugin for the simulator SDK, and a macro plugin has to
  run on the Mac. It fails with "external macro implementation type could not be found ... produced
  malformed response" and leaves an `IOSSIMULATOR` binary in `Debug-iphonesimulator`, which has to be
  deleted before the next attempt. `-destination 'generic/platform=iOS Simulator'` alone is correct
  and green.
- Screenshots were taken headless, through `xcrun simctl` only, with the volume forced to 0 before
  every launch. No Simulator window was opened and no sound was played. The simulator was shut down
  at the end.
- Screens photographed and read: main menu, workshop, builder, test arena, career season screen, the
  full bracket, the scouting report, the career garage, settings, side events (locked), replays
  (locked), ladder (locked), the quick fight card, onboarding, the unlock screen, the quick fight
  result sheet and the career settlement.
- `find . -name '* 2.*'`: nothing.

## What the owner should look at

1. **The menu and the season screen on the phone**, where the machine is live behind the glass
   rather than the key art still. That is the one thing the simulator cannot show.
2. **The ticker.** One line at a time is the spec; whether the pause between lines reads as calm or
   as broken is a judgement that needs eyes.
3. **The next-fight card above the bracket** on the season screen, and whether he would rather have
   the board first and scroll for the card.
4. **The WON and LOST banners** on the settlement and the result sheet, and the scrap counting up.

## Left undone

- **The replay player screen** (`Roboteer/Replays/ReplayPlayerView.swift`) picks up the system
  through the shared components but was never photographed: it needs a recorded replay, which needs
  a fight finished on a device.
- **The side event result card** was not photographed either, for the same reason.
- **The tier key art is unused so far.** `StageBackdrop(keyArt:)` is wired and the menu uses
  `menu_keyart`; `backdrop_<tier>.png` is in the bundle and is the obvious backdrop for a career
  screen with no live machine, but every career screen currently has one.
- **Glyphs, tier badges, boss and rival portraits and arena cards** all ship in the bundle and are
  reachable through `BroadcastArt`, and no screen draws them yet. The scouting report wants the rival
  portrait, the card wants the arena card, and the quick fight picker wants both.
- **Dynamic Type** is not supported, which is deliberate for a landscape game, but the type floor is
  a fixed floor rather than a scale.
