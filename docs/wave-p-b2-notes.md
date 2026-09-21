# Wave P, agent B2: the Series screen, the shop, the campaign board and the career flow

Built 2026-09-21 against `docs/brief-v5-progression.md`, `docs/wave-p-contracts.md` and
`docs/design-system.md` section 8, on top of agent A's engine (`ProgressionEngine`,
`CareerStore.settleMatch` / `buy` / `startReplay`) and agent C's arena ledger. The mockups are
`docs/look/series-options.html`; the options the page recommends (S1, H1, C1) are the ones built,
unchanged. Nothing in the engine contradicted them, so the page was not redrawn.

## What was built

**`CareerHomeView.swift`.** Two things:

- `CareerRootView` owns the whole career loop and nothing else does: FIGHT ->
  `CareerFightView` -> `CareerStore.settleMatch` -> `MatchReportView` -> `RewardsView` on a win or
  `RetryPromptView` on a loss or a draw -> back to the Series screen. B1's three screens are called
  with the parameters B1 wrote into the contracts file (`matchTitle:`, and `attempts:` on the retry
  prompt). The retry prompt's RETRY starts the same match again on a new seed (the attempt count
  was already bumped by `settleMatch`, and `NextMatch.seed` reads it); REPAIR AND RETRY pays the
  bill through `CareerStore.repair` first. After the Series 5 final, a won match tapped on the
  strip or the board runs `CareerStore.startReplay` and the card comes back labelled "Replay" with
  a "Leave the replay" link (`cancelReplay`).
- `CareerHomeView`, the Series screen, option S1: the chevron and the five Series as one line of
  words across the top with the scrap at the right, the Level bar as a full width rule under them,
  the Series in display type on the left with one dim housekeeping line, ONE panel on the right
  (the next match, FIGHT inside it, money as a sentence), the four matches plus the Series after
  them as a strip under the panel, Garage / Repair / Shop as text links, the ticker along the
  bottom. When the Series is finished the panel becomes the completion panel: the campaign is
  yours, or Series N taken with the full game offer as the one primary.

**`ShopView.swift`** (option H1): one list the whole width, grouped under kind headings, the five
kinds as a line of words that jump the list. A row is name, weight, what the catalogue knows, the
price in the scrap colour, and one action word: BUY, OWNED, "Level 35", "Full game", or the price
in the danger colour when it cannot be afforded. Prices, weights and gating all come from
`ProgressionEngine.shopEntries`; buying is `CareerStore.buy`, which re-checks everything, so a row
and a purchase cannot disagree. Level and scrap are one sentence at the top, never two bugs.

**`BracketView.swift`** keeps its file name and holds the campaign board (option C1: five rows,
four columns, the whole game with no scrolling, locked Series dimmed with the reason said once on
the row) and `SeriesStrip`, the four slot version under the next-match card. `BracketStrip` and
`BracketProgressStrip` are deleted with the bracket; `DamageAssessmentView`, the only other caller
of the second one, was retired by B1 in the same wave.

**`ScoutingView.swift`** takes `NextMatch` now. Its three money bugs are gone (see below), the
header reads "Series 2, match 3" instead of a tier and a round, the history line reads "Last met in
Series 2, match 3", the arena and the house bot are one sentence rather than two stat rows, and
FIGHT carries the same fit-to-fight gate the Series screen does.

**`MenuView.swift`**: the card reads the Series state through `ProgressionEngine.nextMatch`
("CAREER SERIES 2, MATCH 3" / "HOB NAIL IS NEXT" / "The Grinder. Cinder on duty. A win pays up to
450."), the campaign-complete and Series-taken cases have their own lines, the ticker no longer
says circuit, season, bracket or blueprints, and the card's headline is one size up (22 to 24),
which was the nit.

**`CareerGarageView.swift`**: the Blueprints panel is OWNED PARTS, and a part not owned reads
"Level 25 in the shop" or "In the shop for 96" instead of "Earned at Regional" (that note is also
what the builder's locked picker rows print, through `CareerUnlocks.lockNote`). The two slot lines
no longer say circuit. The fit-to-fight gate and the repair bill sentence are untouched.

**`DesignSystem.swift`**, in a new `// MARK: - Wave P, series` section at the end: `LevelBar` (the
Level as a rule with one sentence of remainder, never a panel) and `SlotCell` (one cell of the
Series strip and of the campaign board, a word, a note and a 2 pt state bar, never a box).

## The three money bugs in `ScoutingView`

Found as asked; all three were money that brief v5 abolished, printed as boxed score bugs, which
breaks design system section 8 twice over:

1. `ScoreBug(label: "Entry paid", value: next.entryFee)` : there is no entry fee any more.
2. `ScoreBug(label: "A win pays", value: next.purse)` : there is no purse. A win pays the scrap
   lines of brief v5 section 3, which vary with the fight.
3. `ScoreBug(label: "Repairs owing", ...)` : the number is real, but money is a sentence.

All three are now one sentence: "A win pays up to 450 scrap and 450 points. Repairs owing 237.",
the same sentence the next-match card prints, built from `NextMatch.scrapRules` (base + damage +
survivor + flawless, which is what "up to" means) and `NextMatch.winPoints`.

## The RETIRED functions

Deleted from `CareerStore.swift` once the repo-wide grep was clean: `enterSeason`, `settle`,
`writeOff`, `defer_`, the `Settlement` struct and the private `noteFor` helper (only `settle` used
it). `CareerEngine`'s entry fee, purse and bracket functions stay, because the self test and the
old save migration still read them, and `NextFight`, `CareerBracket` and `SeasonTally` stay in
`CareerModels.swift` for the same reason: they are agent A's to remove.

## The 13 ladder ids D1 and D2 have not built yet

They are on the ladder in `parts.json` but not in the catalogue, so `shopEntries` cannot price
them. My call: **show them**, at the foot of the list under a "Still to come" heading, as the name
and the Level they arrive at, with the reason said once ("These are still being built. They join
the shop at these Levels."). Hiding them would make the ladder look as though it stops at Level 40.
Each one leaves that list and becomes an ordinary priced row the moment D1 or D2 adds its catalogue
entry; nothing else has to change. Until then their names come from the id (`Legs`, `Hover`,
`Apex`), because the catalogue has no display name for them yet and inventing one in Swift would
put a second source of truth next to `parts.json`.

## Verified from headless simulator screenshots

`scripts/build-sim.sh` green (four times, warning free for my files). Screenshots on
`A18A1779-2368-4FFF-9195-1523D4ABA146`, inside the `/tmp/roboteer-sim.lock` mkdir lock, volume
forced to 0, `-godotDriver dummy -godotMethod dummy -godotDisplay headless`, in
`/tmp/roboteer-shots/wave-p-b2/`:

| Shot | What it proves |
|---|---|
| `series-screen.png` | Option S1 as drawn: Series words, wall, scrap, Level bar, one panel, money sentence, strip, ticker. The attempt line reads because the fixture has one attempt on the clock. |
| `series-complete.png` | `career-masters.json`: Level 100 bar full, "The campaign is yours", the strip offering a replay on all four matches. |
| `campaign-board.png` | Option C1 with Series 3 to 5 locked and the reason said once per row. |
| `board-replays.png` | The same board after the campaign: twenty cells, every one "won. Replay it". |
| `shop.png`, `shop-level-100.png` | The shop at Level 20 (OWNED, LEVEL 27, FULL GAME) and at Level 100 unlocked (BUY rows). |
| `shop-weapons.png` | Weapon rows with the catalogue's own pips and "Level 22 / 25 / 32". |
| `shop-armour.png`, `shop-still-to-come.png` | Materials priced off the reference plate, and the 13 unbuilt ladder ids. |
| `scouting.png` | The new header, the money sentence and the house bot sentence. |
| `career-garage.png` | OWNED PARTS and the Series wording on the slot lines. |
| `menu.png` | The menu card reading the Series state, at the new size. |

`-careerSelfTest`: **ALL PASS (832 checks, 1 warning)**, the warning being the 13 ladder ids D1 and
D2 have yet to add. Captured with `xcrun simctl launch --console-pty` (a plain `--console` run and
an `os_log` stream both truncate before the summary; the pty does not, which is worth knowing for
the next agent).

## What I could not verify without a phone

- The post-match flow end to end. A career match is a three minute fight and the simulator's arena
  is a dummy renderer, so the loop was read screen by screen, not played: B1's `-openMatchReport`,
  `-openRewards` and `-openRetryPrompt` show the three screens on fixture data, and my side of the
  wiring (which screen follows which, and what RETRY does to the seed) is covered by the self test's
  campaign script rather than by a photograph.
- Buying a part, which needs a tap. The self test proves the prices and the gates; the row's own
  BUY path is one call to `CareerStore.buy`.
- Anything about feel: whether the Level bar counting up after a win reads as a reward, and whether
  the strip is tappable enough with a thumb.

## Known limits, for the owner or for whoever picks this up

- **The scouting report scrolls and the fold can land mid sentence.** On a 402 pt phone the report
  panel gets about 190 pt once the machine chooser and FIGHT have theirs, which is the opponent,
  the parts line, the money and the house bot; the armour line, the pips and the grudge line are
  below the fold. It is better than it was (three score bugs and two stat rows became two
  sentences) but it is still a scroll with no visible affordance.
- **A replay of a match in an earlier Series** shows that Series' name on the card and the CURRENT
  Series' strip underneath. The card says "Replay · Series 1, match 2" so it is not wrong, but the
  strip is about somewhere else.
- **Armour prices look small** next to weapons and chassis (14 to 43 against 96 to 450) because a
  material is priced as one reference plate, which is agent A's formula. It is a dial in
  `economy.price_factor.armour` if the owner wants materials to feel like a purchase.
- The board's bottom half is empty stage on a 402 pt phone. Twenty cells at the top, nothing under
  them. It reads fine, it is just not full.

## Dials the owner can turn

Every number is in `Shared/parts.json` under `progression` and `economy`; no screen of mine holds
one.

- `progression.series[n].scrap` : what "a win pays up to" says on the card and the report.
- `progression.series[n].win_points` and `points_per_level` : how fast the Level bar moves.
- `progression.level_required` : where a part sits on the ladder, which is what the shop prints.
- `progression.replay_scale` : what a replay pays, and so how long the shop stays alive after the
  campaign.
- `economy.price_factor` : every price in the shop.
- The words on the Series screen, the shop and the board are all in the three Swift files, one
  sentence each, no string table.
