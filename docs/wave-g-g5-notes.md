# Wave G, agent G5: the career as a season you can see

Written 2026-09-16. Brief v4 (`docs/brief-v4-playtest.md`) section 6, and the G5 row of
`docs/wave-g-contracts.md`. Presentation and flow on the existing engine: no new engine rules, two
new pure hooks on `CareerEngine`, and one new field on `CareerState`.

## What the player sees now

**CAREER opens on the season screen.** It used to open on a summary panel with ENTER / BRACKET /
GARAGE and the bracket lived a screen away. It is now the season:

- **Top, full width: the tier strip.** Scrapyard to Masters, the player's circuit filled white, the
  locked ones dim with a padlock, and the **wall** drawn as a hairline gate with FULL GAME on it
  between the last free circuit and the first locked one. The position comes from
  `Gates.firstLockedTier`, so buying the game removes the gate without a line of screen code
  changing.
- **Middle, right column: the bracket of eight** (`CompactBracket`, new in `BracketView.swift`).
  Three columns headed Quarter-final, Semi-final, Final, the player's tie edged bright with the
  livery swatch, beaten machines struck through, results filled in as the season goes. Tapping it
  opens the full board, which is the old `BracketView` unchanged apart from the round names.
- **Bottom, right column: the next-fight card** (`NextFightCard`). Opponent name, roboteer, livery
  swatch, weight, weapon and chassis; the arena; **the house bot on duty and one line saying what it
  does**; entry paid; what a win pays (the final pays the multiplier and says so); anything the
  chosen machine still owes in repairs; the scouting line; and the grudge line when there is
  history. Tapping the card opens the full scouting report.
- **One primary button: FIGHT.** It starts the tie directly. Two secondaries in a row under it:
  **Garage** and **Repairs**.
- The left 45 % is clear for the live machine, framed at `StageLayout.botFrame` (0.28), with
  `StageOrbitPad` under the copy so the turntable still works. Back is a quiet button at the top of
  that column rather than a fourth item in the stack.

**After a fight** the settlement (`DamageAssessmentView`) now opens with a `BracketProgressStrip`:
the player's three ties as chips, and the one just fought slides in from the right and brightens.
The purse, the salvage, the bill and the blueprints are the one settlement below it, as before.
Closing it returns to the **season screen**, not the bracket screen, so the next-fight card updating
is what the player sees.

**Winning the final** puts a `SeasonSummaryPanel` where the card was: the record in words, the scrap
earned against the fee paid, the blueprints won by name, and which circuit the player is in now. The
tier strip above it has already moved on.

**Losing** replaces the card with one line ("You are out of the Scrapyard. The board played itself
out without you.") and the primary button becomes **Re-enter for 120**, with the fee in the button.

**Every number the player can be charged is on the screen before FIGHT**: the entry fee (on the card
while a season runs, in the button before one is entered), the purse, and the outstanding repair
bill on every machine in the stable. The Repairs sheet lists them and pays them.

## The fight config

`CareerFightConfig.json` now sends, per `docs/wave-g-contracts.md`:

```json
"rules": { "mode": "fight", "duration_s": 180, "ko_count_s": 10,
           "enforcer": "thresher", "enforcer_mode": "zone", "enforcer_speed": 0.5 }
```

and on the AI bot's own block, `"ai_skill": "scrapyard"` and `"temperament": "bully"`.

- `duration_s` is 180 for mode `fight`, G1's number, named here as
  `CareerFightConfig.fightDurationS` (G1 amended the contracts file to say this is where the host's
  half lives).
- `enforcer` / `enforcer_speed` come from **G2's** `CareerEngine.houseBot(tier:arena:)`. G2 landed
  the real one while this was being written; the stub described in the G5 task was replaced by G2's
  own implementation in place, and there is now exactly one.
- `ai_skill` is the tier id. `temperament` is one of G3's five. **Only the AI bot carries them**; the
  player's block is exactly what the garage built.

## Two pure hooks added to `CareerEngine` (G5's half of the shared file)

Both sit under `// MARK: - Wave G`, after G2's `houseBot`:

| hook | what it is |
|---|---|
| `houseBotName(_ id:)` | the catalogue's own boss name, so a house bot is never printed as an id |
| `houseBotLine(tier:arena:)` | "THRESHER guards the corner zone at half speed and comes out hunting at two minutes." Brief section 10 item 1 asks for this line |
| `aiSkill(for tier:)` | the tier id, which is what `bots[i].ai_skill` is |
| `temperaments` | the contract's five, in order |
| `temperament(for entrant:seasonSeed:)` | a rival keeps theirs for life, a filler draws one from the season seed |
| `temperament(fromID:salt:)` | FNV-1a over the id then one draw from `SeededRandom` |

**Why the id and not a hash.** Swift's `hashValue` is seeded per process, so a rival would have a
different head on every launch. FNV-1a over the id's bytes is the same on every device and every
run, which is what "rivals keep theirs for life" means.

**Where the temperament really comes from.** `CareerCatalogue.RivalEntry` gained a `temperament`
field, read from a `temperament` key in `Shared/parts.json` (G3 owns that key). Until it is there the
derived one is used, so the card and the config are wired end to end today and G3's keys simply take
over when they land. `CareerCatalogue.swift` is in nobody's ownership list; this is a two line
additive change and it is noted here rather than claimed.

## New value types (in `CareerModels.swift`, G5's file)

- **`NextFight`** is everything the card prints and everything the config sends, made in one place by
  `NextFight.make(tier:bracket:seasonSeed:record:playerBotName:repairsDue:)`. The card, the scouting
  report and the arena therefore cannot disagree about who is on duty, which arena it is or what the
  tie pays. It is nil when there is no season or the player is out of it, which is how the screen
  knows to show the summary or the season-over line instead.
- **`SeasonTally`** is the season summary: wins, losses, scrap earned, fee paid, blueprints, and
  whether the tier was taken. Codable, kept as text on `CareerState.seasonTallyJSON` exactly the way
  the bracket is, so it is a lightweight migration and a career saved before wave G reads back as an
  unopened tally (`opened == false`) which the store then opens rather than adding to.
- **`CareerBracket.roundTitle(_:of:)`** gives "Quarter-final", "Semi-final", "Final". The old
  `roundName` keeps its lower case unhyphenated spelling because it is written into the middle of
  sentences (`FightLog.line`); this one is a title and is used on every screen.

## The self test

`-careerSelfTest` is still the tests. **388 checks, all passing** (172 at stage 5; G2 and G5 both
added in this wave). G5's new cases:

- `checkHouseBotWords`: every tier and round's house bot has a printable catalogue name; an unknown
  id never prints as an id; the Scrapyard line names the bot, the corner zone and the two minute
  release and says it is the slow one; a full speed house bot does not claim to be slow; no em dash.
  (Which bot is on duty is G2's `checkHouseBotChoice`.)
- `checkOpponentHeads`: the five temperaments are the contract's five; the skill ids are the tier
  ids; every rival's temperament is legal and does not move with the season seed; sixty filler draws
  are all legal and not all the same; the same id and salt always draw the same head.
- `checkNextFightCard`: a card is made in all three rounds of a scripted Regional season and each one
  is checked for the round title, the arena, the fee, the purse, the house bot, the skill, the
  temperament, the scouting line, placeholders, em dashes and the final flag; a won season, a lost
  season and no season at all all give no card; a repair bill reaches the card.
- `checkSeasonSummary`: a scripted three win season's tally adds up every purse and salvage, holds
  the whole drip, keeps the tier it was fought at, nets off the fee, writes "Won three, lost none.",
  prints three non empty lines naming the blueprints rather than their ids, and survives a round
  trip through text. A season lost in the quarter final is checked too.

**How it was run.** There is no test target, so the pure files compile as a command line binary on
the Mac, the way `docs/stage5-swift-notes.md` describes:

```
cp Roboteer/{JSONTools,Catalogue,BuildRules,FightResult,BotBuild,CareerModels,CareerCatalogue,CareerEngine,CareerSelfTest}.swift  Roboteer/Store/Gates.swift  <harness>/
# point both catalogues at Shared/parts.json instead of Bundle.main, add a Stubs.swift for
# spikeLog / ArenaHost / StoreService, and a two line main.swift
xcrun swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" -target arm64-apple-macos14.0 *.swift -o selftest && ./selftest
```

`QuickFight.swift` imports SwiftUI and drags the whole menu system in, so G2's four Quick Fight
toggle assertions inside `checkHouseBotChoice` are cut from the harness copy only. They run on the
device with `-careerSelfTest` like everything else.

## The build

`scripts/build-device.sh`: **BUILD SUCCEEDED**, no errors, no warnings.

## One thing that had to give

`CareerFightView` and `CareerFightConfig.json` are borrowed by the **async ladder**
(`Roboteer/Ladder/LadderView.swift`), which fights a ghost and has no card. Making `next` a required
parameter broke it, so it is `NextFight? = nil`: with no card there is no `enforcer`, no
`enforcer_mode`, no `enforcer_speed` and no `ai_skill` or `temperament`, and the banner is just the
arena name as before. That is the right answer as well as the convenient one, because brief v4
section 3 puts house bots in **career** fights. A ladder fight does now run for 180 s with G1's
endgame, because it is `rules.mode == "fight"`; that follows from the contract and nothing was done
to stop it.

## What could not be checked without a phone

- **Layout.** The season screen was designed for 874 x 402 pt and reasoned about, not photographed:
  no Simulator windows are allowed while the owner is at the Mac, and the fallback is the rule that
  the content root ends in `.frame(..., alignment: .topLeading)` and the bracket plus card sit in a
  `ScrollView` with the buttons pinned below, so nothing can be pushed off the bottom of a small
  landscape iPhone. **This is the first thing to look at on the device.** If the card feels cramped
  the bracket panel is the thing to shrink.
- **The slide.** The result sliding into the bracket is a 0.5 s ease from 20 pt with a 0.25 s delay.
  Whether it reads as "the result went into the board" or as a twitch is a judgement that needs eyes.
- **The house bot in the fight.** The card and the config now name it; whether the arena honours
  `enforcer_mode: "zone"` and `enforcer_speed` is G2's to prove.
- **The temperament reaching the AI.** The key is sent; G3's `OpponentAI` reading it is G3's.

## Left undone

- **The season summary is a panel, not a moment.** Brief section 6 asks for "a season summary" when
  the final is won and that is what is there, but it appears on the season screen after the
  settlement rather than as its own beat. If the owner wants a curtain, that is a screen, and it is
  wave V's kind of work.
- **`ResultSheet.swift`** is untouched. It is the QUICK FIGHT result sheet (`FightView` is its only
  caller); the career's "purse and repair bill as one settlement" is `DamageAssessmentView`, which
  already did exactly that and now carries the bracket beat as well. `DamageAssessmentView.swift` is
  in no agent's ownership list; the change to it is two added parameters and three added lines.
- **The ladder sends no `ai_skill`.** It could send the player's own tier, but the ladder is outside
  wave G and nothing was invented for it.

## Suite

`scripts/test-arena.sh`, run at the end: **22 of 24 test files green**, `ai_test.gd` (G3) and
`fight_shape_test.gd` (G1) failing. Both are those agents' own files, both were being edited while
this ran, and **no `Arena/` file was touched by G5** (the whole change is Swift plus this document),
so neither failure comes from here. The check that matters for this agent is `-careerSelfTest`
(388 checks, all pass) and `scripts/build-device.sh` (green).
