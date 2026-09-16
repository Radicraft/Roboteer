# Wave V, agent V5: the hierarchy pass

Written 2026-09-16, after the owner reviewed the first Broadcast pass and said the menus were busy
and confusing, and chose two mockups from `docs/look/menus-options.html`: the career screen as
**option A, the card**, and the main menu as **option M1, career is the hero**. Those two screens
are now built exactly as drawn, and the rules behind them are `docs/design-system.md` section 8.

Presentation only. No flow, no data, no engine call changed: the same taps reach the same screens,
the same numbers come from the same places, and the FIGHT gating is the same test it always was.

## Files changed

- `Roboteer/DesignSystem.swift`: the section 8 components, so no screen builds one by hand.
- `Roboteer/CareerHomeView.swift`: the season screen as option A, and the next fight card rewritten.
- `Roboteer/BracketView.swift`: `CompactBracket` replaced by `BracketStrip`, the four slot strip.
- `Roboteer/MenuView.swift`: the main menu as option M1.

## New in the design system

- **`TierLine`**: the five circuits as ONE LINE OF WORDS. The current one is lit with a 2 pt `line`
  underline, locked ones are dim behind a lock glyph, and the full game wall is a thin 2 pt `line`
  marker standing where the gates put it. It takes plain items, so the career is still the only
  file that knows what a tier is. `TierStrip`, the five score bugs, is gone.
- **`TextLink`**: navigation that is not the hero. Label capitals, no plate, `typeDim` by default,
  `line` when it leads somewhere important, `danger` when it costs scrap. A pad that lands on one
  underlines it. `MenuView`'s private `MenuTextButton` is gone and the quiet corner uses this.
- **`MoneySentence`** and **`MoneyClause`**: money as a sentence with ONLY the numbers coloured,
  `scrap` for income, `danger` for costs, `type` for money already paid. It is a single `Text`, so
  it wraps like prose rather than like a row of boxes.
- **`PanelLabel`**: the one panel's header, with the half that changes lit (`NEXT FIGHT · FINAL`).
- **`BackChevron`**: back, top left, never a boxed button.
- **`String.asName`**: a catalogue name in the case prose wants. `CareerEngine.houseBotName` falls
  back to a SHOUTED id when the catalogue has no boss entry, and "House bot on duty: CINDER." read
  like an error. A name that is already written properly is left alone.

Nothing was orphaned by the rewrite except the two components named above: `ScoreBug`, `StageStat`,
`LowerThird`, `ScrapBadge` and `CountingNumber` are all still used by the scouting report, the
settlement, the builder, the quick fight card and settings, so they stay.

## The career screen (option A)

- Back is a chevron, top left, on the same row as the tier line. The row runs the full width of the
  screen rather than inside the left column: five words plus their locks need about 350 pt and a
  column capped at 340 truncated every one of them to "SCRAPY...". That was caught in the first
  screenshot.
- Under it the circuit in display type and ONE dim line: "Record 4 of 5 · 640 scrap · Tinribs,
  89.5 kg", the scrap in the scrap colour.
- The right column is ONE panel: the label with the round lit and a `Scouting ›` link on the right,
  the livery swatch, the opponent in display type, one dim line of roboteer, build and weight, one
  sentence for the arena and the house bot, one money sentence, FIGHT as the one primary INSIDE the
  panel, and `Garage` and `Repair for 141` as text links under it. The repair link hides itself when
  nothing is owed.
- The FIGHT gating is unchanged (`fitnessFault`, then `isValid`) and its message is now one danger
  line under the button instead of a block of small red type.
- Under the panel, `BracketStrip`: QF, SF, Final and the title, each with its result under it, the
  next tie lit in `line`. Tapping it opens the full board, which is the same `BracketView` as
  before. The pad reaches it as "board" and it draws a `line` border when focused.
- Season over, season taken and season not entered are the same shape: one panel, one primary
  ("Enter for 50" or "Re-enter for 50"), the reasons as plain lines and the money as a sentence.
  `SeasonSummaryPanel` folded into it.
- Gone: the SCRAP bug, the record panel, the machine panel, the three money score bugs, the ARENA
  and HOUSE BOT stat rows, the scouting and grudge prose (both are on the scouting report, one tap
  away) and the boxed BACK.
- The career screen now carries the ticker too, as option A draws it.

## The main menu (option M1)

- Title top left with the rule and ONE dim line for the machine. The lower third that carried the
  machine's name is gone.
- Scrap top right as a plain label and number, not a bug.
- ONE panel: `CAREER · REGIONAL SEMI-FINAL`, "Scuttle is next", one dim line "The Grinder. Cinder on
  duty. Pays 260." with only the number coloured, and one primary, "Continue career". A player with
  no career reads "Start your career" and the line explains the first circuit and its entry fee.
  The card's next tie comes from `NextFight.make`, the same call the season screen uses, so the two
  screens cannot disagree about who is next or what it pays.
- Under it a plain text list at 15 pt in `type`: Quick fight, Workshop, Events. Ladder, Replays and
  Settings stay small, bottom right. The four stacked buttons are gone.
- The menu's right column is 300 pt wide, not `StageLayout.columnWidth`'s 430: option M1's column is
  the width of one card, and a 430 pt card made the menu look like the screen it used to be.

## Pad navigation

Every action on both screens is a `PadItem`. Career: fight (or enter), scout, garage, repairs when
a bill is owed, board, and back on the chevron. Menu: career, quick fight, workshop, events, then
the quiet row left to right. `TextLink` and `BracketStrip` show the focus themselves, so a pad
player can see where they are on a screen made of links.

## Verification

- `scripts/build-device.sh`: **BUILD SUCCEEDED**, twice, no errors and no warnings from our code.
- Screenshots headless through `xcrun simctl` only, on A18A1779, volume forced to 0 before every
  launch, `-godotDriver dummy -godotMethod dummy -godotDisplay headless`, no Simulator window, the
  device shut down afterwards.
- Photographed and read against the mockups: the menu with a season running, the season screen with
  `-career career-regional.json` (semi-final, repairs owing), and the season screen with a fresh
  career (nothing entered, the Enter panel).
- `find . -name '* 2.*'`: nothing.

## Two things a screenshot cannot settle

- **The new player's menu card.** A fresh install raises the onboarding welcome over the menu, and
  the simulator cannot take the tap that dismisses it, so "Start your career" was read in the code
  and not photographed.
- **The black pill at the left edge** of two of the screenshots is the system home indicator in the
  device's own orientation, not our chrome: it moved between shots of identical layouts and is gone
  from the last one.

## Left undone

- `docs/design-system.md` section 5 still describes the old menu (four lower thirds) and the old
  season screen (five score bugs, the card at the bottom). Section 8 overrides both, and section 5
  is the coordinator's to edit.
- The scouting report still prints the money as a row of score bugs. It is not one of this pass's
  files, but it is the last screen with three money bugs on it, and section 8 applies to it too.
