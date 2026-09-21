# Wave P, agent B1: the three post-match screens

2026-09-21. Brief v5 sections 5, 6 and 9.4, built to the recommended set of the mockup page
`docs/look/postmatch-options.html` (R1 + W1 + T1). The owner has not seen that page yet; nothing in
agent A's engine or agent C's ledger contradicted it, so it was not redrawn and the three
recommendations stand exactly as written.

## What was built

| File | What it is now |
|---|---|
| `Roboteer/MatchReportView.swift` | Option R1: the banner, the clock and the hits as plain type on the left with the machine behind them, one panel holding the part by part condition in two columns, CONTINUE inside it. Plus `PostMatch` (the words and colours the three screens share) and `PostMatchQA` (the launch-flag fixture). |
| `Roboteer/RewardsView.swift` | Option W1: one panel, the four scrap lines counting up to a banked total, the Level bar filling under it, then what that Level opened in the shop and which paint job came free. |
| `Roboteer/RetryPromptView.swift` | Option T1: no panel at all. The losing banner, three short lines, RETRY as the only primary with "Repair and retry for N" a step quieter under it and the garage as a text link. |
| `Roboteer/CareerFightView.swift` | Takes `NextMatch` instead of the retired `NextFight`, and sends `rules.scrap` on every career match (nothing else sends it). Banner reads "SERIES 2, MATCH 3" and the pause overlay's quit reads "Give up the match". |
| `Roboteer/DesignSystem.swift` | A new `// MARK: - Wave P, post-match` section at the END of the file: `FillRule`, `ConditionRow`, `LevelGainBar`, `LedgerRow`. Appended only; nothing above it was touched. |
| `Roboteer/DamageAssessmentView.swift` | **Deleted** (see below). |
| `Roboteer/RoboteerApp.swift` | Five lines: the QA launch flags raise one post-match screen instead of `RootView`. |
| `docs/qa-launch-flags.md` | `-openMatchReport`, `-openRewards`, `-openRetryPrompt`. |
| `docs/wave-p-contracts.md` | An "Amended by B1" paragraph under **Views**. |

`ResultSheet.swift` and `FightView.swift` were left alone: the quick fight is an exhibition that
banks nothing into the career, carries no damage home and has no Series behind it, so there is
nothing for the match report to report. Adopting the report there would have meant inventing a
Series line and a scrap breakdown that do not exist. That is the one item in B1's row of the
ownership table deliberately not taken.

### DamageAssessmentView is retired, not folded

Brief v5 section 9.4 moves repairs to the Series screen and the retry prompt, and section 9.1
retires the blueprint drip and the bracket strip. That left the old settlement screen with nothing
of its own: its purse line, its write-off offer, its `New blueprint` flourish and its
`BracketProgressStrip` are all retired by the brief, and the one part worth keeping, the part by
part condition, is now the match report's panel. So the file was deleted and its four
`project.pbxproj` lines with it. Nothing referenced it once B2's `CareerRootView` landed (checked
before deleting). The write-off path (`CareerStore.writeOff`) is untouched and still reachable from
the career garage; only this screen went.

### The three parameters added

All with defaults, so every call written against the stubs still compiles (written into the
contracts file as required):

- `MatchReportView(matchTitle:)`, `RewardsView(matchTitle:)`: `NextMatch.title`, the lit half of
  the panel label.
- `RetryPromptView(matchTitle:attempts:)`: `attempts` is `CareerState.attempts` after the match was
  settled (this loss included). Two or more prints "That was the third attempt at Series 2,
  match 3."; fewer prints nothing, because saying "the first attempt" to somebody who has just lost
  once is noise.

B2's `CareerRootView` currently passes neither, which is why they default to "" and 0 and why the
screens read correctly without them. One line each on B2's side turns them on:
`matchTitle: next.title` on the report and the rewards screen, and `matchTitle: next.title,
attempts: state.attempts` on the retry prompt.

## What the screens actually show

**Match report.** Result word (WON in `win`, LOST in `danger`, DRAW in `type`) and the kind of
result beside it; "TINRIBS AGAINST CLATTERBOX" under it; "2:14 on the clock. 41 hits landed, 28
taken."; then either "Destroyed or disabled: Rear left wheel and Sides armour." in `danger` or
"Nothing came off the machine." faint. The panel lists every part the arena reports a condition
for, in `ProgressionEngine.partConditions` order (weapon, drive, wheels, armour faces, hull), each
with a 3 pt bar that is `line` above 70 %, `scrap` from 25 to 70 % and `danger` below, with the
name and the number in `danger` once the part is at zero. The list scrolls if a machine ever
carries more parts than the panel is tall, so a six wheeler cannot push the CONTINUE button off.

**Rewards.** The four scrap lines are always printed, zeroes included and faint, in the brief's own
order (base, damage dealt, survivor, flawless), then BANKED with the total counting up in `scrap`.
Then the Level: "LEVEL 18", "450 points earned", the bar, and "100 points to Level 19." A win that
crosses a Level fills the bar to the end, resets it and fills the new Level, so the crossing is
seen rather than inferred. Then what opened: "New in the shop: Tracked wheels and Rear anti-spinner
wedge." with the
names in `line`, and the paint job on its own line. When nothing opened it says when the next thing
does ("Nothing new opens until Level 40."), read from the real ladder rather than left blank. The
line under the banner changes at the end of a Series: "Series 2 is complete. Series 3 is open.",
"Series 2 is complete. The next Series is in the full game.", or "Every Series is won. Any match
can be fought again from the Series screen."

**Retry prompt.** "The 343 scrap from this match is forfeited." as a money sentence with only the
number in `danger`, then "Nothing is lost but the scrap. The same opponent, the same arena, a
different fight." The repair button carries its own price in its label and is disabled when the
scrap will not cover it, and the footnote then says why: "Repairs cost 184 and there is 90 in the
bank." A pristine machine gets no repair button at all.

## What was verified, and how

Build: `scripts/build-sim.sh`, BUILD SUCCEEDED (Debug, simulator), twice: once when the screens
landed and once after the panel change below. The career self test was run on the final build,
headless, on the same simulator: `career self test: ALL PASS (832 checks, 1 warnings)`.

Headless Simulator screenshots on `A18A1779-2368-4FFF-9195-1523D4ABA146` (iPhone 17), inside the
`/tmp/roboteer-sim.lock` mkdir lock, volume forced to 0, launched with
`-godotDriver dummy -godotMethod dummy -godotDisplay headless`. No window was opened and no sound
was played. The screens were raised by the new launch flags, on fixture data, with no fight:

| Shot | Flag |
|---|---|
| `/tmp/roboteer-b1-shots/report-win.png` | `-openMatchReport win` |
| `/tmp/roboteer-b1-shots/report-loss.png` | `-openMatchReport loss` |
| `/tmp/roboteer-b1-shots/rewards-win.png` | `-openRewards win` |
| `/tmp/roboteer-b1-shots/rewards-camp.png` | `-openRewards campaign` |
| `/tmp/roboteer-b1-shots/retry-loss.png` | `-openRetryPrompt loss` |
| `/tmp/roboteer-b1-shots/retry-broke.png` | `-openRetryPrompt broke` |

(Those are outside the repo on purpose: they are layout checks, not assets. `report-win.png` and
`report-loss.png` are from the final build; the other four are from the build before the panel
change, which did not touch them.)

**What the shots caught.** The first pass let the report's panel take the whole height, which left
a hand's width of empty glass between an eleven row condition list and the CONTINUE button. The
panel now hugs the list and only takes the full height (and scrolls) when a column would run past
eight rows, which is a six wheel machine with every armour face. That is the only thing the
screenshots changed; everything else read as drawn.

**One wording nit that is not B1's to fix.** The armour faces are labelled by
`ProgressionEngine.partConditions` as "`<face name>` armour", and the catalogue's face is called
"Sides", so the report reads "SIDES ARMOUR". "Side armour" would read better. The face names are
agent A's file and `Shared/parts.json`, so it is recorded here rather than changed.

## What only the phone can settle

1. **Whether the report is read at all.** It stands between the bell and the money. On the Mac it
   reads in one glance; on a phone after three minutes of fighting the owner may want CONTINUE
   under his right thumb rather than inside the panel. Moving it is one line.
2. **The condition list at phone size.** Eleven rows in two columns at 11 pt label type is the
   legibility floor of the design system. It passes on a screenshot at 3x; it has to be read at
   arm's length before it is trusted.
3. **The Level bar crossing more than one Level.** With `points_per_level` 100 and `win_points` 350
   to 625, an ordinary win crosses three to six Levels at once, and the bar fills once, resets, and
   fills again to the remainder. That is honest but it undersells the jump. If the owner wants the
   Levels counted off, the bar has to pulse per Level, which is a rewrite of `LevelGainBar`.
4. **Whether the mockups survive contact.** The owner has not seen `postmatch-options.html`. If he
   prefers R2, W2 or T2, each is a layout swap inside one file.

## The dials the owner can turn

- **Which option each screen is.** R1/W1/T1 are built; R2, W2 and T2 are drawn in
  `docs/look/postmatch-options.html` and are a layout change in one file each, no engine work.
- **The condition colour thresholds** (`ConditionRow` in the wave P section of
  `DesignSystem.swift`): `line` above 0.7, `scrap` above 0.25, `danger` below. Those are the same
  bands the HUD's condition bar uses.
- **Whether zero scrap lines are printed.** They are, faint, so the four sources always read in the
  same place. `LedgerRow` prints them; hiding them is a filter on one array.
- **The wording of every line above.** All of it is in the three view files, no string table.
- The money itself is not a dial here: it is `progression.series[n].scrap` in `Shared/parts.json`
  (agent C's notes list those dials).

## Two things the next agent in this area should know

1. **`LevelBar` was taken.** B2's Series section of `DesignSystem.swift` added a `LevelBar` (a
   label, a bar and the remainder sentence) at the same moment as this one. B1's is now
   `LevelGainBar` and is the animated one: it fills from before to after and wraps on a Level
   crossing. Two bars, two jobs, both in the wave P sections.
2. **The simulator lock is only as good as the traps in it.** Two agents ran shot scripts against
   `A18A1779-2368-4FFF-9195-1523D4ABA146` inside `/tmp/roboteer-sim.lock` at the same time. The
   other script's EXIT trap does `rmdir "$LOCK"` unconditionally, so when it exited while this one
   held the lock it released somebody else's lock and shut the device down mid run. Nothing was
   lost (the shots were retaken), but a trap that releases a lock should check it owns it first.

## Nothing was faked

No placeholder art, no stub in a shipped path, no TODO. The QA fixture is the only fixture and it
is behind a launch flag, exactly as `CareerStore.loadFixtureIfRequested` is.
