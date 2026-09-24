# Roboteer front end and meta game: teardown and ranked plan

Written 2026-09-24 by the UX and meta-game lead, pre-production for the AAA pass. Nothing in the app
was changed. Scope: structure, flow, function and content of every SwiftUI screen, the career
economy and pacing, onboarding, accessibility, controller navigation, and the owner's graphics
modes idea. The LOOK of the main menu and the garage belongs to the art director (`docs/look/`);
where this file touches those two screens it says what they must DO, not what they look like.

Sources read: `docs/brief-v3.md`, `docs/brief-v4-playtest.md`, `docs/brief-v5-progression.md`,
`docs/brief-coverage.md`, `docs/design-system.md`, `docs/graphics-bar.md`, `docs/wave-p-*-notes.md`,
`docs/store-copy.md`, `docs/qa-launch-flags.md`, every Swift file under `Roboteer/` (including
Onboarding, Ladder, Events, Replays, Store), `Shared/parts.json` (economy and progression blocks),
`Arena/render/graphics_quality.gd` and `Arena/project.godot`.

Evidence: one iPhone 17 simulator (iOS 26.5), the Debug build of 24 Sep 19:38, walked with the QA
launch flags. Screenshots are in `docs/aaa/img/frontend/`. The simulator runs the LOW render tier
at a sixteenth of the pixels, so the stage behind the menus is either the rendered still or a
blocky live frame; judge layout and flow from them, never the graphics.

Owner's standing rules applied throughout: no coloured edge strokes, skewed accent lines or cyan
edge bars on buttons, cards or panels; no em dashes in player-facing text; no AI-default design
tells; one purchase, no loot boxes, no energy, no dark patterns.

---

## 0. The verdict in one page

The game underneath is real: a physics fight with a genuine build decision, a working economy
engine, 45 parts, ten paint jobs, eight rivals with memory, five house bots, side events, replays
and a ghost ladder. The front end presents all of that as a set of correct, quiet spreadsheets.
Every screen answers "what is this" and almost none answers "why would I want it". The three
Insomniac pleasures the owner named are each missing at the moment they should land:

1. **The vendor is a price list.** The shop is one long table of rows over a dimmed backdrop. A
   part is never seen, never turned on a turntable, never compared with what is fitted, never
   tried on your machine, and the purchase is a word changing from BUY to BOUGHT.
2. **What you earn is never shown off.** A win is a ledger that counts up for 0.4 s. A new Level
   is one line of text. A new part is a comma in a sentence. Nothing is unboxed, nothing is
   revealed, nothing asks to be fitted.
3. **Menus are static.** Screens in the career swap instantly (a `switch` on an enum), there is
   no menu music and no UI sound anywhere in the Swift shell, no UI haptics, and the only motion
   is a ticker and a 0.25 s lower-third slide.

Under the presentation there are also structural problems a player will hit: the career dead-ends
for exactly the player who pays (bug 1), the repair economy has a free bypass (bug 2), armour
materials skip the shop (bug 3), a broke player with a dead core can be stranded (bug 4), and the
whole Level ladder (1 to 100, 45 parts) is spent in 20 wins, so the campaign is two to four hours
and there is very little reason to come back after it.

### The top 12 (ranked by player impact; QW = quick win under half a day)

| # | Item | Why | Cost | QW |
|---|---|---|---|---|
| 1 | Fix the purchase dead end: a save that hit the wall does not move to Series 3 after buying | The paying player's career stops dead with no match, no replay and a "while you wait" line | 0.3 d | QW |
| 2 | Close the economy leaks: free Workshop repair, ungated armour materials, owned parts announced as new | The two currencies stop meaning anything; the rewards screen lies at wins 1, 2, 6 and 16 | 0.5 d | QW |
| 3 | Never strand a player: a floor for the broke player with an unfit machine, and RETRY that knows the machine cannot fight | Today RETRY leads to "There is no match waiting."; once bug 2 is fixed the broke case is a hard softlock | 0.5 to 1 d | needs a decision |
| 4 | The payoff sequence after a win: scrap pours in, the Level bar fills, each new part is revealed on the turntable with FIT IT and BUY IT | This is the Ratchet and Clank moment the game does not have | 3 d | |
| 5 | The vendor: the shop becomes a showroom with the part on your machine, stat deltas against what is fitted, BUY AND FIT | Turns the one spending decision into the best screen in the game | 4 d | |
| 6 | Three medals per match (win, win by knockout, finish above 70 %), shown on the board and the card, replayable for the missing ones | Goals, collection completion and a reason to replay, built on bonuses the arena ALREADY computes | 2 d | needs a decision |
| 7 | One garage, not two: fold the menu Workshop and the career Garage into one stable with the builder, repairs, owned parts and paint | Two screens disagree about capacity and repair cost; the player cannot tell which one is "the" garage | 2.5 d | |
| 8 | Builder that compares: every part row shows what changes against the fitted part, with the opponent's threat named | The build decision is the game; today the player compares pips by memory | 2 d | |
| 9 | The broadcast walk-out: a tale-of-the-tape versus moment before every career match, rival portrait, grudge line, house bot, arena | Turns FIGHT from a button into an event; the grudge lines are currently only in a ticker VoiceOver cannot read | 3 d | |
| 10 | Post-campaign life: a Championship Defence mode, a daily seeded broadcast with a leaderboard, event medals | The campaign is 20 wins; hour five has almost nothing new | 6 to 8 d | needs a decision |
| 11 | Controller and accessibility pass: pad navigation for the shop, builder rows, repairs and post-match; Dynamic Type; reduce motion; the 50 sub-floor body sizes | A pad player cannot buy a part or pick a weapon today; nothing scales with the system text size | 5 d | partly QW |
| 12 | Graphics modes: Auto, Quality, Performance, Battery, with thermal fallback and 120 Hz presentation | The owner's idea, specified in section 6; today the tier is silent and presentation is capped at 60 Hz | 4 d | needs a decision |

---

## 1. The screen map and the loop as a player lives it

### 1.1 Screen map

```
Launch
 └─ Loading (LoadingView, over the live stage)                                  [01, 02]
     └─ Main menu (MenuView, option M1)                                          [02]
         ├─ Welcome panels (first launch only, OnboardingWelcome)                [03]
         ├─ CONTINUE CAREER ─ CareerRootView (one enum, no navigation stack)
         │    ├─ Series screen (CareerHomeView: Series line, Level bar,
         │    │    next-match card, Series strip, ticker)                         [05, 21]
         │    │    ├─ Scouting report (ScoutingView, opponent on the turntable)  [22]
         │    │    ├─ Campaign board (CampaignBoardView, 5 x 4)                  [23]
         │    │    ├─ Repairs sheet (CareerRepairsSheet, overlay)
         │    │    ├─ Garage (CareerGarageView) ─ Builder (fullScreenCover)     [24]
         │    │    │     └─ Owned parts (sheet)
         │    │    ├─ Shop (ShopView)                                            [06, 25]
         │    │    └─ Unlock (UnlockView, sheet; once automatically, else here) [26]
         │    └─ FIGHT ─ Career fight (CareerFightView over the Godot arena)
         │         └─ Match report ─ Rewards (win) | Retry prompt (loss/draw)   [17-20]
         ├─ Quick fight (QuickFightPicker sheet) ─ FightView ─ ResultSheet       [12]
         ├─ Workshop (WorkshopView) ─ Builder (pushed) | Test arena | Quick fight [07-11]
         ├─ Events (EventsRootView, whole screen behind the wall)                [13]
         ├─ Ladder (LadderView, behind the wall)                                  [15]
         ├─ Replays (ReplaysRootView ─ ReplayPlayerView, behind the wall)        [14]
         └─ Settings (SettingsView) ─ Unlock                                      [16]
```

Numbers in brackets are screenshot files in `docs/aaa/img/frontend/`.

Two navigation systems run side by side. The menu uses a `NavigationStack` with routes; the career
is one pushed route whose inside is a `switch screen` over nine cases, so moving between the Series
screen, the shop, the garage, the fight and the post-match screens is an instant swap with no
transition, no back stack and no gesture. The builder is pushed from the Workshop but presented as
a full-screen cover from the career Garage. The quick fight picker and the unlock are sheets. The
repairs list is an overlay inside the Series screen. A player meets five presentation idioms for
the same kind of move.

### 1.2 The loop as lived, first launch to hour five

Times assume a player who wins about two in three career matches once past Series 1, 3 minutes a
fight, and a minute or two of menus between fights.

| Clock | What happens | How it feels |
|---|---|---|
| 0:00 | Loading: "ROBOTEER", one grey line ("Warming the lights", "Opening the workshop") over a dark stage that brightens. On the simulator a fresh install took over 60 s ([02b]); the device time is unmeasured. | Calm, but it is a wait with nothing to do and no sound. |
| 0:01 | Welcome: BUILD. TEST. FIGHT. with three cards and BUILD A BOT / SKIP ([03]). The FIGHT card still says "Enter the circuit, win the purse", words from the retired bracket. | Clear, generic. Nothing shows the machine, the arena or a fight. |
| 0:02 | Workshop with one machine (Tinribs), a callout "This is your machine. Change anything you like..." and TEST IT. | The player is handed a spreadsheet of six tabs before they have driven anything. |
| 0:04 | Test arena against a dummy. No goal, no prompt to try the flipper, nothing to hit. Leaving it completes the tutorial. | The first drive is in an empty room. |
| 0:06 | Callout: "Now put it in front of something that fights back." FIGHT opens the QUICK fight picker, not the career. | The first real fight is an exhibition that banks nothing. |
| 0:10 | Quick fight result sheet: WON or LOST, two columns of numbers, "Back to garage" (which goes to the menu). No rematch, no replay, no reward. A draw reads LOST (bug 8). | The first win of the game pays nothing and shows nothing. |
| 0:11 | The player finds CONTINUE CAREER. Series screen: Level 1, 300 scrap, Iron Sprat next, The Yard, Thresher on duty, "A win pays up to 270 scrap and 350 points" ([05]). | Readable. The filler opponent has an empty grey portrait square. |
| 0:15 | First career win. Match report ([17]), then Rewards ([18]): four ledger rows, a total that counts for 0.4 s, Level 4, and "New in the shop: Spare battery", a part the player has owned since the start (bug 5). | The first payoff is a lie and a table. |
| 0:20 | Second win: Level 8, "New in the shop: Saw, Polycarbonate, Pyramid". Two of the three are already owned. Pyramid costs 340; the player has about 660. | The first real purchase opportunity arrives around minute 20, and nothing on the rewards screen points at the shop. |
| 0:25 | The shop ([06]): a list. Tap BUY on Pyramid and the word turns into BOUGHT. To use it the player must back out to the Series screen, go to Garage, press Build, find the Chassis tab. | Four screens between buying and seeing. |
| 0:25 to 0:55 | Series 1 and 2 at The Yard then The Grinder. Every Series 1 match is at The Yard; every Series 2 match at The Grinder. Rivals and fillers vary, the room does not. | Variety is the opponent's weapon only. |
| about 0:55 | Series 2 final won. Free player: rewards, then the unlock screen once ([26]). Paid player at this point: straight to Series 3. A player who buys AFTER reaching the wall is stuck (bug 1). | The wall is honest; the recovery path after paying is broken. |
| 1:00 to 3:00 | Series 3 to 5. Two parts per win keep arriving. Scrap outpaces the shop from Series 3: a typical Masters win pays about 1,040 and the most expensive part costs 480. Level 95 (Vortex spinner) and Level 100 (Apex) only arrive WITH the final win, so they are never used in the campaign. | The shop runs dry, then the Level ladder does. |
| about 3:00 | "The campaign is yours." Replays of won matches pay half. Events (five, one clear each, rewards worth 18 to 48 scrap), ladder ghosts. | There is no next goal. |
| 5:00 | A player still here is replaying matches for half pay with every part owned and scrap they cannot spend. | This is the retention cliff. |

Where it is thin: rewards, the shop, the first ten minutes, arena variety inside a Series, and
anything after the campaign. Where it is confusing: two garages, the Workshop repairing for free
while the career charges, quick fights that count toward a machine's career record, words from the
retired bracket (circuit, purse, blueprint, tie). Where it dead-ends: buying after the wall, RETRY
with an unfit machine, the broke player, and the finished campaign.

---

## 2. Screen by screen

Each entry: purpose, what is there, what the AAA version has, what is missing functionally. The
AAA column is written against the owner's two references: Ratchet and Clank (the vendor, the
upgrade loop, everything earned shown off, fast menus with motion and personality) and Gear.Club
Stradale (your machine as the lit hero, showroom presentation, calm tiles).

### 2.1 Loading (`LoadingView.swift`) [01, 02b]

- **Purpose.** Pay the shader and texture warm-up once, where waiting is expected.
- **There.** Title, one line of progress words, the stage brightening. 40 s give-up timer
  (`ArenaHost.preloadGiveUpSeconds`), which cannot fire while the engine holds the main thread.
- **AAA.** The wait is the title sequence: the machine is lit piece by piece as its parts warm,
  the turntable starts, a sting plays, a tip or a rival's line rotates. On second launch it is
  under two seconds.
- **Missing.** Any sound; a measured device time; a promise that the second launch skips most of
  it (a warm pipeline cache). HEAD is the WIP commit `81a743d` ("may not compile"); the build I
  walked was compiled at 19:38 today and did finish loading, slowly.

### 2.2 Welcome and onboarding (`Onboarding/Onboarding.swift`, `CoachPolicy.swift`) [03]

- **There.** Three cards, BUILD A BOT or SKIP; then callouts on the Workshop and the menu; fight
  coaching in the first three fights and always in the test arena.
- **AAA.** Starts with action and teaches by doing (section 4).
- **Missing.** The career is never introduced; scrap, Level, repairs and the shop are never
  explained; the first fight is an exhibition; stale copy on the FIGHT card.

### 2.3 Main menu (`MenuView.swift`, option M1) [02]

The art director owns the look. Functionally:

- **There.** Title with a cyan rule, the machine line, scrap, one career card with CONTINUE
  CAREER, a text list (Quick fight, Workshop, Events), a quiet row (Ladder, Replays, Settings),
  a ticker.
- **AAA (function, not look).** The menu is a status board for your machine and your next thing:
  the machine stands lit as the hero (already true on device); the card names the next match AND
  what is waiting (new parts you can afford, a paint job just earned, repairs owed, a daily
  broadcast); every tile leads somewhere that is alive. Badges count real things, never nags.
- **Missing.**
  - The Shop is not reachable from the menu. It lives only inside the career.
  - For a free player three of the seven entries (Events, Ladder, Replays) lead to locked screens.
    Locked is fine; a locked screen that shows nothing of what it holds is not (see 2.17 to 2.19).
  - Nothing tells the player something new exists: no "3 new parts you can afford", no "new paint".
  - The ticker repeats the card ("NEXT UP, SERIES 1, MATCH 1: ...") and carries a rules line
    ("ONE ROUND OF THREE MINUTES...") on every visit.
  - No menu music, no UI sound, no UI haptics.

### 2.4 Series screen (`CareerHomeView.swift`, option S1) [05, 21]

- **Purpose.** Where am I, what is next, what does it pay, go.
- **There.** Series line with the wall, Level bar, Series title, housekeeping line, the next-match
  card (portrait, livery swatch, arena band with the house bot, money sentence, FIGHT, Garage /
  Repair / Shop links), a five-cell Series strip, a ticker.
- **AAA.** The next match is a broadcast promo: both machines, the arena, the house bot, a line
  from the rival, the medals still to win in this match, and one button. Progress is felt, not
  read: the strip fills like a season graphic; the Level bar has milestones on it (the next part,
  the next paint) so the player can see what the next win buys.
- **Missing.**
  - Filler opponents show an empty grey portrait square ([05]); 6 of the 20 matches are fillers.
  - The Level bar has no milestones. The player cannot see that Level 8 brings the Pyramid.
  - Scrap is printed twice (top right and in the housekeeping line).
  - The grudge line and the "two more wins take Series 2" line live only in the ticker, which is
    `accessibilityHidden` and scrolls past.
  - Scouting is a small link at the top right of the card; the richest pre-fight screen is the
    hardest to find.
  - With the Series complete and nothing to fight, the copy says "Replay any match you have won
    from the board while you wait." There is nothing to wait for (bug 1).

### 2.5 Scouting report (`ScoutingView.swift`) [22]

- **There.** The opponent's machine on the turntable, portrait, name, parts line, six pips, the
  personality line, the history line, the house bot sentence with the arena card and the boss
  portrait, the machine chooser and FIGHT along the foot.
- **AAA.** A tale of the tape: their machine and yours side by side on the stage, with the three
  facts that decide the match (their weapon's height against your clearance, their weapon type
  against your armour materials, their drive against your push) as plain sentences, and one
  suggestion ("Titanium on the front would take half of that axe"). The brief's height readout
  ("your wedge: floor, their bar: mid") belongs here as well as in the HUD.
- **Missing.** Any comparison with the player's own machine; any advice; a way to go straight to
  the builder with the threat in mind and come back.

### 2.6 Campaign board (`BracketView.swift`, option C1) [23]

- **There.** Five rows by four matches, badges, notes on won cells, replay taps when allowed.
- **AAA.** The trophy wall of the campaign: each cell carries its medals, the rival's face, how it
  was won; a finished Series row gets its own trophy; the board is where completion lives.
- **Missing.** Medals (none exist yet); per-match best result; the ability to see WHY a locked
  Series is locked beyond one line.

### 2.7 Career fight (`CareerFightView.swift`)

- **There.** The arena, a 13 pt faint banner during the countdown ("SERIES 1, MATCH 1 · THE YARD ·
  HOUSE BOT THRESHER"), the pause overlay.
- **AAA.** A walk-out: the two machines introduced, the house bot shown in its corner, the rival's
  line, the countdown as a broadcast sting. Brief v4 section 7 already imagines this.
- **Missing.** Any introduction at all; `PadFocus` is not cleared on entry (bug 6).

### 2.8 Match report (`MatchReportView.swift`) [17]

- **There.** WON or LOST banner, the clock and hits, parts destroyed, a two-column condition list,
  CONTINUE.
- **AAA.** The damage is shown ON the machine: the turntable turns to the damaged side and the
  broken parts glow; each row can be tapped to highlight the part. "Watch the finish" plays the
  last eight seconds from the replay the arena already recorded.
- **Missing.** Visual link between the list and the machine; the finish replay; the repair price
  per part (the player learns the bill later).

### 2.9 Rewards (`RewardsView.swift`) [18, 19]

- **There.** One panel: four ledger rows, a banked total counting for 0.4 s, the Level with a bar
  that fills from before to after, one line for what opened, CONTINUE.
- **AAA.** The payoff sequence: each ledger line lands in turn with a sound and a haptic; the
  total counts with the bolt-collect pitch ramp from the arena (the one sound the game is built
  around); the Level bar fills, and on a Level up the screen stops for a beat; each new part is
  revealed as a card and then on the turntable (the machine stands aside, the part turns alone
  under a spotlight), with FIT IT (if owned or affordable and bought) and SHOP. A finished Series
  gets a trophy moment; the campaign gets a proper ending.
- **Missing.** All of the above, and the lie in bug 5. "Scrap is banked on a win only, and this
  one is banked." explains a rule at the moment of joy.

### 2.10 Retry prompt (`RetryPromptView.swift`) [20]

- **There.** LOST banner, what was forfeited, RETRY, "Repair and retry for N", back to the garage.
- **AAA.** Losing teaches: one sentence on why (from the result: "You were flipped at 1:12 and
  your srimech was gone"), one suggestion, and the same one-press retry.
- **Missing.** RETRY is enabled when the machine cannot fight (bug 4); no reason for the loss; no
  route to the builder with the lesson.

### 2.11 Repairs sheet (`CareerRepairsSheet` in `CareerHomeView.swift`)

- **There.** A row per machine with PAY N.
- **Missing.** Per-part repair (fix the weapon, leave the scratched rear plate); pad navigation of
  the PAY buttons (only CLOSE is registered, `CareerHomeView.swift:999`); the write-off that brief
  v3 promises is shown ("WRITTEN OFF" styling exists) but can no longer be reached.

### 2.12 Career garage (`CareerGarageView.swift`) [24] and Workshop (`WorkshopView.swift`) [07]

Two screens do one job.

| | Workshop (from the menu) | Garage (from the career) |
|---|---|---|
| Capacity | hard-coded 1 (`WorkshopView.swift:27`) | from the Series, 1 to 5 |
| Repair | free, clears the damage (`WorkshopView.swift:298`) | charges the bill |
| New bot | only when empty | up to capacity |
| Delete | yes | no (write-off is gone) |
| Test arena, quick fight | yes | no |
| Owned parts | no | yes |
| Back | boxed button | boxed button |

- **AAA.** One Garage: your stable as a row of lit machines you can swipe between (the Stradale
  model), each with its record, condition and bill; Build, Test, Paint and Repair as the machine's
  own actions; the shop one step away.
- **Missing.** A single definition of the garage; machine records that separate career from
  exhibition; per-machine history ("what finally killed it", which brief v3 section 9 promises).

### 2.13 Builder (`BuilderView.swift`) [08 to 11]

- **There.** Six tabs, a readout strip (parts kg, armour kg, clearance), a scrolled list of part
  rows with pips and blurbs, lock notes, the livery presets and the paint wall, the live machine.
- **AAA.** Every row answers "what happens if I fit this": weight change against the budget left,
  pips that move with arrows against the fitted part, and one line about the next opponent. The
  machine animates the swap (the old weapon lifts off, the new one drops on). Locked rows open the
  shop entry directly. The paint wall previews on the machine by hovering, before committing.
- **Missing.**
  - No comparison with the fitted part anywhere; the weapon list opens on locked rows
    (Horizontal spinner, Level 25) rather than the fitted weapon ([10]).
  - Material names truncate in the armour segments ("REINFORCED...", "REACTIVE AR...") and both
    are selectable at Level 1 ([09]).
  - Armour materials are not gated by ownership or the wall (`BuilderView.swift:448`, bug 3).
  - The pad can switch tabs and go back but cannot select a single row (`BuilderView.swift:193`).
  - No shop link from a locked row; no damage shown per part.

### 2.14 Shop (`ShopView.swift`) [06, 25]

- **There.** Header sentence, five jump words, one list of 45 rows grouped by kind, a "still to
  come" block (empty now), a ticker. One tap buys, no confirmation.
- **AAA (the vendor).** A showroom: pick a part and it appears on YOUR machine on the turntable
  (the stage already takes a bot config; a preview is a config with the part swapped), with the
  stat deltas against what is fitted, the weight against your budget, and what it counters. BUY,
  then a stamp, a sound, bolts spent from the counter, and FIT IT NOW. Filters: "you can buy",
  "new since last visit", "counters your next opponent". A part you cannot afford says how many
  wins away it is.
- **Missing.** Everything above, plus pad support (`ShopView.swift:57` registers no items), plus
  any "new" state, plus a shop entry on the main menu.

### 2.15 Owned parts (`OwnedPartsPanel` in `CareerGarageView.swift`)

- **There.** Five columns of names with a tick or a lock and one note.
- **AAA.** The collection: 13 of 45 as a lit shelf, with silhouettes for the unowned, and the
  paints and medals beside it.
- **Missing.** It duplicates the shop in a worse form. Fold it into the shop as a "collection" view.

### 2.16 Quick fight (`QuickFight.swift`, `FightView.swift`, `ResultSheet.swift`) [12]

- **There.** Arena picker with key art, opponent cycle, rumble and house bot toggles, FIGHT.
  Result sheet with columns and one button.
- **AAA.** One press to rematch; watch the finish; change machine and go again.
- **Missing.** Rematch; replay; a draw reads LOST (`ResultSheet.swift:75`); exhibition results are
  written into the machine's career record (`ResultSheet.swift:252`); "Back to garage" goes to the
  menu.

### 2.17 Events (`Events/EventsView.swift`) [13]

- **There.** Five events, best scores, run counts, PLAY, a result screen. Whole screen behind the
  wall. Each clear gives one utility part.
- **AAA.** Each event has bronze, silver and gold targets, a Game Center leaderboard, and a
  cosmetic reward (a paint, a title, a decal). A free player can play one event once as a taster.
- **Missing.** Targets and medals; leaderboards; meaningful rewards (the five parts cost 18 to 48
  scrap, less than one Scrapyard win); the word "blueprint" is still on screen.

### 2.18 Replays (`Replays/ReplaysView.swift`, `ReplayPlayerView.swift`) [14]

- **There.** A list of logged fights, WATCH, a player with speed, restart, free camera, share clip.
- **AAA.** Auto-kept highlights (the knockout, the biggest hit, the pit throw) with thumbnails;
  one tap from the match report.
- **Missing.** Any entry point from the post-match flow; highlights; the empty-state copy says
  "career tie", a retired word.

### 2.19 Ladder (`Ladder/LadderView.swift`) [15]

- **There.** Rating, record, ghost list, fight, publish, refresh.
- **AAA.** A season: divisions, a weekly reset of the ladder list (not of the rating), the ghost's
  owner name and machine on the turntable before you fight it.
- **Missing.** The opponent preview (the stage is right there); a reason to publish.

### 2.20 Settings (`SettingsView.swift`, `Settings.swift`) [16]

- **There.** Control scheme, knockout camera, control tips, haptics, one volume, the full game,
  restore, about.
- **Missing.** Graphics mode (section 6); separate music and effects volumes; left-handed control
  swap; stick size and opacity; reduce motion override; text size (if Dynamic Type is adopted);
  reset career. "circuits" twice in the unlock row's copy.

### 2.21 Unlock (`Store/UnlockView.swift`) [26]

- **There.** Two bullet lists (what you played, what it opens), price, buy, restore.
- **AAA.** Shows what is behind the door with the art that exists: the four arena cards, four boss
  portraits, the Series badges, a line from the Masters rival. Still one price, still no timer.
- **Missing.** The art; accurate copy ("CINDER, the first arena boss" while Series 1 fields
  THRESHER; "circuits").

### 2.22 Pause (`FightPause.swift`)

Fine for purpose. Missing: a controls reminder and the settings that matter mid-fight (camera,
volume).

---

## 3. The meta game

### 3.1 The dials as shipped (`Shared/parts.json`)

- Level: 100 points per Level, cap 100, wins pay 350 / 450 / 500 / 550 / 625 by Series, flawless
  +25 %, replays half. Level 100 lands exactly on the 20th win.
- Scrap per win (base + damage x fraction + survivor + flawless): Series 1 up to 270 (typical
  180), Series 2 up to 450 (300), Series 3 up to 720 (480), Series 4 up to 1,080 (720), Series 5 up
  to 1,560 (1,040). A clean campaign banks about 10,880. Opening float 300.
- Prices: `price_factor` x kg. Chassis 10, weapon 12, drive 8, armour 6, utility 6. Everything not
  owned at the start costs 6,744 in total.
- Repairs: condition lost x part price. A destroyed Wedge core alone is 300.

### 3.2 What the numbers do

**Pacing is two parts a win, from win 2 to win 20** (computed from the ladder):

| Win | Level | Newly buyable (a star means already owned from the start) |
|---|---|---|
| 1 | 4 | spare battery* |
| 2 | 8 | saw*, polycarbonate*, pyramid |
| 3 | 11 | reinforced |
| 4 | 15 | axe, tracks |
| 5 to 8 | 19 to 33 | rear wedge, ram*, vertical spinner, horizontal spinner, long and low, 6WD, legs, lifter |
| 9 to 12 | 38 to 53 | shock prod, skirts, flamethrower, counterweight, reactive, tall tank, crusher, magnets |
| 13 to 16 | 58 to 75 | hover, scoop, tesla arc, omni, drill lance, shell, titanium*, twin saw |
| 17 to 20 | 81 to 100 | full body spinner, napalm cannon, adaptive tracks, overcharge core, vortex spinner, apex |

Consequences:

1. **Win 1 unlocks nothing new** (the spare battery is owned). The first purchase is possible at
   win 2 and it is a chassis, not a weapon.
2. **The brief's headline beats are pre-owned.** Saw (Level 5), Ram plow (20) and Titanium armour
   (70) are in `career.starting_unlocks`, so three of the brief's 21 milestones announce nothing.
3. **Vortex spinner and Apex are never used in the campaign.** They arrive with the final win.
4. **Scrap outruns the shop from Series 3.** From about win 9 a typical win pays more than any
   part costs, and by the end the player has several thousand scrap and nothing to spend it on.
5. **Armour and utilities are almost free.** A material is priced as ONE reference plate (the
   front face at 2 units), so Reinforced is 49 and HDPE 14, while a weapon is 144 to 384.
   Utilities are 18 to 54. The agents' instinct was right: these read as rounding errors.
6. **Repairs are the only real sink, and the Workshop repairs for free** (bug 2).

### 3.3 Recommended dials (owner decision on the numbers; each is one line of JSON)

- **Armour priced as a full coat**: `kg_per_unit_area x total face area (5.1) x 2 units x 6`:
  Steel 184, Titanium 98, HDPE 61, Polycarbonate 73, Reinforced 208, Reactive 159. This is what
  fitting a material everywhere actually weighs, so the price finally agrees with the weight.
- **Utility factor 6 to 20**: 60 (skirts) to 180 (overcharge core).
- **A first-win purchase**: take the Saw out of the starting loadout so it is the first thing the
  player buys (144, affordable after one win on top of the 300 float), or move the Axe to Level 4.
  The code already names the starting list as "the owner's dial" (`ProgressionEngine.startingOwned`).
- **Bring the tail forward**: Vortex spinner to 90, Overcharge core to 85, Apex to 95, so the
  final is fought with the best hull in the game.
- **A late scrap sink that is not a timer**: part upgrades (3.5).

### 3.4 Rewards

Today a win gives scrap, Level points and a sentence. Every reward should have a moment and a
place it lives afterwards:

| Reward | Moment | Where it lives |
|---|---|---|
| Scrap | ledger lines land in turn, bolt-collect pitch ramp on the total | the counter on every screen |
| Level | bar fills, Level-up stop, the next milestone named | the Level bar with milestones |
| New part in the shop | card, then the part alone on the turntable, SHOP / BUY AND FIT | the shop's "new" filter |
| Paint job | the machine repainted on the turntable, WEAR IT | the paint wall |
| Medal (new, 3.6) | the medal stamped on the match cell | the board, the career card |
| Series won | trophy on the Series row, the rival's concession line | the board, the Garage shelf |
| Campaign won | an ending: the five finals as a montage of replays already recorded | Hall of fame |

### 3.5 An Insomniac upgrade loop that fits a one-purchase game

Ratchet and Clank's weapons level up by USE and are upgraded at the vendor with a second currency.
Roboteer can have the first half for free and the second with scrap:

- **Part mastery.** Every weapon and drive earns mastery from hits landed and metres driven in
  CAREER matches (the result already reports hits). Mastery 1 to 3 per part, visible as pips on
  the shop and builder rows.
- **Mk II and Mk III**, bought with scrap once mastery allows: a small, plainly stated gain (spin-up
  10 %, one more flipper charge, 5 % more push) and a visible flair on the part (a machined finish,
  a heat-blued blade, a stripe). Prices sized to the late-game glut (Mk II about the part price,
  Mk III about twice it).
- **Why it fits.** No timers, nothing for sale, every step earned by playing; it gives the shop a
  reason to exist after Series 3 and gives a favourite weapon a story.
- **Cost of saying yes.** Arena side: per-part stat multipliers in the bot config (a new field the
  bridge carries, deterministic, replay-safe because it is config, not state). Swift: mastery on
  `CareerState`, rows in the shop. About 6 to 8 agent days. It changes brief v5, so it is an owner
  decision.

### 3.6 Goals and challenges: medals from the bonuses the arena already pays

The arena already computes, per match: a win, the damage fraction, survivor (70 % condition) and
flawless. Turn them into three medals per match, the stars of every good mobile game but with
plain meaning:

- **Win.** Beat them.
- **Survivor.** Win with at least 70 % of your machine left.
- **Knockout or Flawless** (pick one per Series so it varies): end it before the bell, or lose no
  part.

Twenty matches, sixty medals, one board that shows them. Replaying a won match for a missing medal
pays the full match reward the FIRST time that medal is earned and half after, which makes replays
purposeful rather than a grind. Cost about 2 agent days (Swift only: the engine settles, the board
and card draw, the self test grows). Owner decision: replay pay rule.

### 3.7 Variety of opponents and events

- Series 1, 2, 3 and 5 are each fought in ONE arena for all four matches; Series 4 alternates two.
  Give every Series two arenas (the free Series share The Yard and The Grinder) and put a house
  bot "headline" match in each Series: match 3 is a one-on-one against the house bot itself with
  its own rules (survive 90 s, or push it into its own hazard). Five boss fights already have
  their AI (`boss_ai.gd`).
- Fillers are 6 of 20 matches and have no portraits. Either draw a generic silhouette plate per
  weapon class or promote two fillers per Series to named minor rivals with one line each.
- Events: medals and leaderboards (2.17).

### 3.8 Reasons to come back tomorrow, without dark patterns

| Idea | What it is | Why it is not a dark pattern | Cost |
|---|---|---|---|
| Daily broadcast | One seeded exhibition per day, the same for everyone (seed from the date), with a twist rule (Furnace, flippers only; Crush, house bot out from the start). Score = a published formula. Game Center leaderboard. | No streaks, no loss for missing a day, the last seven are always playable, rewards are titles and a paint, never power | 3 d |
| Championship Defence | After the campaign: the five Series again at Masters AI with the rivals' machines upgraded, medals to win, a gold-edged trophy | Content, not a timer | 3 d |
| Ladder season | The ghost list refreshes weekly; a division badge | Rating is never reset or decayed | 1.5 d |
| Rivals who move | Rivals upgrade between meetings (brief v3 section 9) and say so in the walk-out | Narrative only | 1 d |
| Collection | Parts, paints, medals, trophies, rivals beaten, bosses beaten on one Hall of fame | Nothing is behind money | 2 d |

---

## 4. Onboarding and the first ten minutes

### 4.1 What is there

Welcome cards, a Workshop callout, the test arena, a quick fight, then nothing. The player has
been told build, test, fight, and has done all three, and has not met the career, the shop, a
reward, or a rival. The first win pays nothing.

### 4.2 Proposed first ten minutes

The principle: action first, one idea at a time, every idea landed by a reward.

| Clock | Beat | Teaches | Built from |
|---|---|---|---|
| 0:00 | Loading is the stage lighting your machine | "This is yours" | exists |
| 0:20 | One sentence: "Series 1, match 1. Iron Sprat, at The Yard." FIGHT. No welcome cards. | The career is the game | Series card |
| 0:30 | The walk-out, then the fight with the coach callouts (drive, weapon, self-right) and the corner zone line the first time | Controls, the house bot | coach exists |
| 3:30 | Win: the payoff sequence, first scrap, Level up | Scrap and Level | 2.9 |
| 4:00 | "The Saw is yours to buy." SHOP opens on the Saw, turning on your machine. BUY AND FIT. | The vendor | 2.14, dial 3.3 |
| 5:00 | Garage: the Saw on the machine, "Try it in the test arena?" with a dummy to cut | The builder and the test arena, with a purpose | exists |
| 6:30 | Back to the Series screen, repairs named in one sentence, match 2 | Repairs | exists |
| 7:00 | Loss or win, the right screen, then the medals on the card | Goals | 3.6 |

Owner decisions: whether the first match is the full three minutes or a shortened opener (two
minutes, endgame at 1:20), and whether a player can skip straight to the menu (recommended: yes,
a quiet SKIP that marks onboarding done).

---

## 5. Accessibility and polish debts

### 5.1 Body text under the 13 pt floor: 50 calls in 14 files

`Stage.body(_:)` clamps to 13 at run time (`DesignSystem.swift:100`), so these render at 13 but
the layouts around them were sized for 10 to 12, and most carry a `minimumScaleFactor` that can
then shrink the clamped text back below the floor (63 `minimumScaleFactor` calls in the app). Each
of these should be written at 13 and its layout re-checked, or be moved to the label role (11 pt
capitals) if it is really a label.

| File | Lines (authored size) |
|---|---|
| `BuilderView.swift` | 248 (11), 290 (11), 319 (11), 438 (10), 550 (11), 592 (11), 657 (11), 663 (11), 733 (11) |
| `CareerGarageView.swift` | 164 (10), 168 (10), 172 (10), 215 (10), 257 (10), 425 (9) |
| `CareerHomeView.swift` | 1022 (10) |
| `Events/EventsView.swift` | 175 (12), 188 (11), 193 (11), 202 (11), 251 (12), 538 (12) |
| `FightView.swift` | 191 (10) |
| `Ladder/LadderView.swift` | 133 (11), 204 (11), 209 (11), 237 (10), 264 (10), 271 (10), 321 (10) |
| `Onboarding/Onboarding.swift` | 199 (12) |
| `QuickFight.swift` | 362 (10), 408 (10) |
| `Replays/ReplayPlayerView.swift` | 90 (10), 156 (10) |
| `Replays/ReplaysView.swift` | 186 (12), 250 (11), 256 (10) |
| `ResultSheet.swift` | 167 (11) |
| `SettingsView.swift` | 110 (11), 262 (11) |
| `Store/UnlockView.swift` | 97 (11), 150 (12), 170 (11), 181 (11), 188 (11) |
| `WorkshopView.swift` | 208 (10), 214 (10), 247 (10), 308 (10) |

Also under a floor, and NOT clamped (these really render small):
`Stage.display(12)` at `CareerGarageView.swift:418`; `Stage.numerals(12)` at
`DesignSystem.swift:1348`; `.system(size:)` below 13 at `BracketView.swift:133` (8),
`BuilderView.swift:536` (11) and 647 (10), `CareerGarageView.swift:207` (12), 413 (9) and 478
(8), `DesignSystem.swift:945` (11), `QuickFight.swift:385` (10), `SettingsView.swift:288` (11),
`Store/UnlockView.swift:146` (9), `WorkshopView.swift:239` (12). Most are SF Symbols beside text;
icons at 8 or 9 pt are too small to read as icons. 66 `Stage.label` calls ask for 9 or 10 and are
clamped to 11; harmless, but they should say 11.

### 5.2 Dynamic Type

None. Every face is `Font(UIFont(name:size:))` at a fixed size (`DesignSystem.swift:190`), with no
`UIFontMetrics` scaling and no `dynamicTypeSize` reading. Recommendation: scale body and label
roles with `UIFontMetrics(forTextStyle:)` up to `accessibility1` (about 1.4x), keep display and
numerals fixed, and let the one column on each screen scroll. Landscape at 402 pt tall leaves
little room, so cap it and test the four densest screens (builder, shop, match report, scouting).
About 2 agent days.

### 5.3 VoiceOver

- 53 accessibility modifiers in the app, 30 of them in `DesignSystem.swift`; most screens rely on
  button titles alone.
- The ticker is `accessibilityHidden` (`DesignSystem.swift:519`) but carries the only copy of the
  rival's grudge line and the Series run line. Expose the current line as a static element, or
  move the facts onto the card.
- Pips are drawn shapes; `StatPips` should read "Reach 3 of 5".
- Part rows, shop rows and the board cells need a single combined label and a hint.
- The fight is a Godot view and cannot be VoiceOver-driven; the pre and post screens can.

### 5.4 Reduce motion

Nothing reads `accessibilityReduceMotion`. The ticker scrolls forever, lower thirds slide, numbers
count. With reduce motion: the ticker shows one static line that changes every 6 s with a fade,
lower thirds fade, counts land at once, the stage camera drift (menu) stops.

### 5.5 Contrast

`typeDim` #9CA6B2 on `glass` is fine, but `textFaint` is used for real information (the retry
footnote, the "nothing new opens until Level N" line, filler notes, record lines) and several
screens dim whole rows to 0.34 to 0.62 opacity (locked parts, owned rows). Measure each against
the brightest backdrop and keep information out of the faint role; faint is for decoration only.

### 5.6 Controller navigation

The pad model is a linear list per screen (`ControllerObserver.swift:290`). Coverage:

| Screen | Pad status |
|---|---|
| Menu, Series screen, Scouting, Board, Workshop, Garage, Quick fight, Settings, Unlock, Events, Ladder, Replays list, Pause | Items registered |
| Builder | Tabs by shoulder, back only: **no part can be chosen** (`BuilderView.swift:193`) |
| Shop | Back only: **nothing can be bought** (`ShopView.swift:57`) |
| Repairs sheet | CLOSE only; PAY cannot be reached (`CareerHomeView.swift:999`) |
| Match report, Rewards, Retry prompt | **Nothing registered**; the previous screen's items are still live (bug 6) |
| Replay player, test arena chrome | Cleared, nothing registered |
| Owned parts sheet, rename alerts, text field for the machine name | Not reachable |

A pad player can start a career match and cannot then buy a part or change a weapon. The fix is a
2D focus model (rows and columns) plus registration on the five missing screens; about 2 days.

### 5.7 Polish debts

- No menu music; no UI sound (select, back, buy, level up, unlock); no UI haptics (the only
  haptics are the arena's).
- Career screens switch without a transition; the career has no back gesture.
- Five presentation idioms for moving between screens (push, enum swap, sheet, full-screen cover,
  overlay).
- Stale words from retired systems in player-facing text: "circuit", "purse", "blueprint", "tie"
  (listed in section 8, bug 9).
- Filler portraits empty; four glyphs missing (twin saw, napalm cannon, vortex spinner weapon
  glyphs, the overcharge core utility glyph are not in `Art/ui`).

---

## 6. Graphics modes: the spec

### 6.1 What exists

`Arena/render/graphics_quality.gd` picks a tier silently: `high` for Forward+ (every iPhone, since
`rendering_method.mobile="forward_plus"`), `medium` only for an iPhone older than A15 by model
name, `low` for the simulator and headless. Features per tier are a table (`FEATURES`); resolution
is pinned native (`scaling_3d/mode=0`, `scale=1.0`); physics ticks at 60 Hz; there is no
`max_fps`, no physics interpolation, no thermal reading, no player choice. `Info.plist` has no
`CADisableMinimumFrameDurationOnPhone`, so ProMotion presentation is capped at 60 Hz on iPhone.

### 6.2 What the player sees

Settings gains one row, **Graphics**, with four choices and one plain sentence each:

| Mode | The sentence | Default for |
|---|---|---|
| Auto | "Picks the best look your phone can hold, and eases off if it gets warm." | everyone |
| Quality | "Every effect on, full resolution, 60 frames a second." | |
| Performance | "Smoother motion, up to 120 frames a second on ProMotion screens, fewer effects." | |
| Battery | "Longer play on a charge. Fewer effects and a lower frame rate in the menus." | Low Power Mode, when Auto |

When Auto is chosen, the row's value reads what Auto resolved to ("Auto: Quality"). Nothing else
is exposed. There is no FPS counter in the shipping build.

### 6.3 What each mode does

| | Quality | Performance | Battery |
|---|---|---|---|
| Renderer | Forward+ | Forward+ | Forward+ (Mobile if a device test shows it saves power) |
| Fight frame rate | 60 | 120 on ProMotion, 60 elsewhere | 60 |
| Menu and stage frame rate | 60 | 60 | 30 |
| 3D resolution | native (1.0) | 0.67 with MetalFX temporal on A17 Pro and newer, else 0.8 bilinear | 0.75 |
| Upscaler | none | MetalFX temporal (spatial as fallback) | bilinear |
| Anti aliasing | MSAA 4x | from the temporal upscaler | FXAA |
| SSAO, SSR | on | SSAO on at half res, SSR off | off |
| Volumetric fog | on | off (plain fog) | off |
| Shadows | 4096, soft | 2048, soft | 2048, hard |
| Glow | on | on | on (the bolts must still glow) |
| Decals | on | on | on (damage is gameplay information) |

The last two rows are rules, not settings: no mode may remove what a player reads the fight by
(bolt glow, damage decals, hazard warnings, the corner zone).

### 6.4 Auto: device class and thermal fallback

- **Device class** from `OS.get_model_name()` (already read): A19 class and newer start in
  Quality; A17 Pro and A18 start in Quality with a Performance fallback; A15 and A16 start in
  Performance at 60 Hz; older than A15 keep today's medium tier.
- **Thermal ladder** from Swift, where `ProcessInfo.thermalState` and
  `NSProcessInfoPowerStateDidChange` live. Swift sends `thermal: nominal | fair | serious |
  critical` and `low_power: bool` in the existing `settings` message (`ArenaHost.sendSettings`).
  - `serious`: step down one mode.
  - `critical`: Battery.
  - Low Power Mode on: Battery.
  - Step back up only after 60 s at `nominal` or `fair` (hysteresis), and never more than once a
    minute in either direction.
- **When changes apply.** Resolution scale and frame cap may change mid-fight (they are invisible
  apart from sharpness). Feature switches (fog, SSR, shadow size) wait for the next scene load so
  nothing pops during a fight.

### 6.5 120 Hz as presentation only

- The simulation stays at `physics_ticks_per_second=60`. The fight tick, the input log and the
  replay recorder do not change, so replays stay bit-exact and the ghost ladder stays fair.
- Turn on Godot's 3D physics interpolation (`physics/common/physics_interpolation=true`) so bodies
  are drawn between ticks. Every teleport (spawn, test reset, replay seek, the endgame camera)
  must call `reset_physics_interpolation()` or it will smear.
- Input: inputs must be sampled into the tick, not per frame. Verify `controls.gd` writes into
  the state the tick reads, and that the replay recorder records per tick. Add a replay test that
  plays one recording with interpolation on and off and asserts identical results.
- Presentation: add `CADisableMinimumFrameDurationOnPhone = YES` to `Info.plist` and set the
  display link's `preferredFrameRateRange` to 80 to 120 (preferred 120) during fights in
  Performance, 60 elsewhere. The link belongs to SwiftGodotKit's `UIGodotAppView`, so this needs a
  small hook in the host (or a patch like `docs/godot-embedded-gl.patch`).
- Menus stay at 60 even in Performance: a turntable at 120 Hz costs battery for nothing.

### 6.6 MetalFX

Godot 4.5 added MetalFX spatial and temporal scaling to `Viewport.scaling_3d_mode` on the Metal
driver. Confirm the 4.6 SwiftGodotKit build links MetalFX and exposes both modes before promising
them; if it does not, Performance uses bilinear at 0.8 and the row still works. Temporal needs
motion vectors (Forward+ has them) and replaces MSAA; the fight SubViewport is where it is set
(`GraphicsQuality.apply_viewport`).

### 6.7 Where it goes in the code

- `graphics_quality.gd`: keep `tier` as the device capability; add `mode` (the player's choice or
  Auto's answer) and resolve features as the intersection; `set_mode(mode)` and
  `set_thermal(state)` entry points; `apply_viewport` learns scale and upscaler.
- `Settings.swift`: `graphicsMode` (auto, quality, performance, battery), sent in
  `dictionary` as `graphics_mode`, plus the thermal and low power readings.
- `SettingsView.swift`: the row.
- Tests: `render_test` for the mode table and hysteresis; a replay determinism test with
  interpolation on.
- Device acceptance on the owner's iPhone 18 Pro Max: frame time p50 and p99 in the Coliseum
  endgame with the house bot out, per mode; a 20-minute thermal soak per mode; energy impact from
  Instruments. About 4 agent days plus one owner session.

---

## 7. The ranked backlog

Player impact: 5 is felt by every player in the first hour, 1 is polish only. Cost is in agent
days. "Owner" means a decision is needed before building.

| Rank | Item | Impact | Cost | Files | Owner |
|---|---|---|---|---|---|
| 1 | Purchase dead end: advance a walled save when the next Series opens, plus a self-test case | 5 | 0.3 | `ProgressionEngine.swift`, `CareerStore.swift`, `CareerSelfTest.swift` | no |
| 2 | Economy leaks: Workshop repair charges (or goes), armour materials gated, `newlyUnlocked` skips owned parts, fight start checks ownership | 5 | 0.5 | `WorkshopView.swift`, `BuilderView.swift`, `ProgressionEngine.swift`, `CareerHomeView.swift` | no |
| 3 | Never strand a player: RETRY disabled with a reason when unfit; a floor for the broke player | 5 | 0.5 to 1 | `RetryPromptView.swift`, `CareerHomeView.swift`, `CareerStore.swift`, `CareerEngine.swift` | yes |
| 4 | Post-match pad focus: clear on fight entry, register the three post-match screens | 4 | 0.2 | `CareerFightView.swift`, `MatchReportView.swift`, `RewardsView.swift`, `RetryPromptView.swift` | no |
| 5 | Payoff sequence on the rewards screen, part reveal on the turntable, FIT IT / SHOP | 5 | 3 | `RewardsView.swift`, `DesignSystem.swift`, `ArenaHost.swift`, stage scripts | no |
| 6 | The vendor: showroom shop with preview on your machine, deltas, BUY AND FIT, new filter, menu entry | 5 | 4 | `ShopView.swift`, `ArenaHost.swift`, `MenuView.swift`, stage | look with art director |
| 7 | Medals: three per match, board and card, replay pay rule | 4 | 2 | `ProgressionEngine.swift`, `ProgressionTypes.swift`, `CareerModels.swift`, `BracketView.swift`, `CareerHomeView.swift`, self test | yes |
| 8 | Economy dials: full-coat armour, utility factor, first-win purchase, tail forward | 4 | 0.5 | `Shared/parts.json`, `Arena/data/parts.json`, self test | yes |
| 9 | One garage | 4 | 2.5 | `WorkshopView.swift`, `CareerGarageView.swift`, `MenuView.swift`, `BuilderView.swift` | look with art director |
| 10 | Builder deltas, opponent threat line, shop links, per-part damage | 4 | 2 | `BuilderView.swift`, `DesignSystem.swift` | no |
| 11 | Onboarding rewrite (section 4) | 4 | 3 | `Onboarding.swift`, `MenuView.swift`, `CareerHomeView.swift`, `CoachPolicy.swift` | yes |
| 12 | Walk-out and tale of the tape | 4 | 3 | `CareerFightView.swift`, `ScoutingView.swift`, arena stage and camera | no |
| 13 | Controller: 2D focus, shop, builder rows, repairs | 3 | 2 | `ControllerObserver.swift`, `ShopView.swift`, `BuilderView.swift`, `CareerHomeView.swift` | no |
| 14 | Menu and UI sound, menu music, UI haptics | 4 | 2 | new `UISound.swift`, `DesignSystem.swift` (button style), `Arena/audio` or bundled Swift audio | yes (music) |
| 15 | Screen transitions in the career and one navigation idiom | 3 | 1.5 | `CareerHomeView.swift` (root), `MenuView.swift` | no |
| 16 | Watch the finish from the match report; rematch and replay on the quick fight result | 3 | 2 | `MatchReportView.swift`, `ResultSheet.swift`, `Replays/*` | no |
| 17 | Post-campaign: Championship Defence | 3 | 3 | engine, board, self test | yes |
| 18 | Daily broadcast with leaderboard | 3 | 3 | new view, `GameCenterService.swift`, `FightConfigFixture.swift` | yes |
| 19 | Part mastery and Mk II / Mk III upgrades | 4 | 6 to 8 | engine, bridge, arena bot config, shop, builder | yes |
| 20 | Graphics modes (section 6) | 3 | 4 | `graphics_quality.gd`, `project.godot`, `Info.plist`, `Settings.swift`, `SettingsView.swift`, host display link | yes |
| 21 | Dynamic Type, reduce motion, VoiceOver pass, contrast | 3 | 3 | `DesignSystem.swift` and every screen | no |
| 22 | Sub-floor sizes (5.1) | 2 | 0.5 | 14 files | no |
| 23 | Event medals, leaderboards, cosmetic rewards | 3 | 2 | `Events/*`, `GameCenterService.swift`, `parts.json` | yes |
| 24 | Two arenas per Series and a house bot headline match | 3 | 2 | `parts.json`, `ProgressionEngine.swift`, `boss_ai.gd` | yes |
| 25 | Filler portraits and missing glyphs | 2 | 1 | `Art/ui`, `DesignSystem.swift` | no |
| 26 | Unlock screen with the real art behind the door | 3 | 1 | `Store/UnlockView.swift` | no |
| 27 | Hall of fame and collection | 3 | 2 | new view, `CareerGarageView.swift` | no |
| 28 | Settings: music and effects volumes, left-handed, stick size, reset career | 2 | 1.5 | `Settings.swift`, `SettingsView.swift`, `controls.gd` | no |

### 7.1 Quick wins (each under half a day)

1. Bug 1, the purchase dead end.
2. Bug 2, Workshop free repair (route through `CareerStore.repair` or remove the button).
3. Bug 3, gate armour materials in the builder with the same `LockGate` the other tabs use.
4. Bug 5, `newlyUnlocked` filters owned parts.
5. Bug 4 first half: RETRY disabled with a sentence when the machine has a fitness fault.
6. Bug 6, pad focus after a career fight.
7. Bug 8, the quick fight draw reads LOST.
8. Bug 7, a draw is not a rival's win.
9. Bug 9, stale copy.
10. Shop link on the main menu's text list.
11. UI haptics on primary buttons and purchases (`sensoryFeedback`).
12. Reduce motion for the ticker and lower thirds.
13. Expose the ticker's current line to VoiceOver, and put the grudge line on the card.
14. Filler portrait plate (a silhouette per weapon class) so no card shows an empty square.
15. The 50 sub-floor body sizes written at 13.

---

## 8. Bugs found while reading

Ordered by severity. Line numbers are at `81a743d` plus the working tree of 24 Sep.

1. **Buying the full game after reaching the wall strands the career.** `ProgressionEngine.settle`
   leaves a walled save at `matchIndex = 4` in Series 2 (`ProgressionEngine.swift:624`). After the
   purchase nothing advances it: `nextMatch` asks `series.match(4)`, which is nil
   (`ProgressionEngine.swift:246`); `replaysAvailable` turns false because the next Series is now
   open (`ProgressionEngine.swift:382`); nothing in `Store/` touches the career. The Series screen
   says "Series 2 taken" and "Replay any match you have won from the board while you wait." with
   no match, no replay and no way on. The self test covers "win the final while locked" and "win
   it while unlocked", never "locked, then bought". Reproduced on the simulator with a fixture at
   Series 2, match index 4, and `-unlocked` ([28], [29]).
2. **The Workshop repairs for free.** `WorkshopView.swift:298` and `:357` call
   `selected?.repair()`, which clears the damage without charging, while the career charges the
   same bill through `CareerStore.repair`. Any player can walk out of the career, repair in the
   Workshop and walk back in.
3. **Armour materials bypass the shop and the wall.** The armour tab offers every material in the
   catalogue (`BuilderView.swift:448`) with no `LockGate`, and `BuildRules` does not check
   ownership. Reinforced (Level 10) and Reactive (Level 45, behind the wall) can be fitted at
   Level 1 in the free game. `startFight` checks legality and fitness only
   (`CareerHomeView.swift:312`).
4. **RETRY with an unfit machine goes nowhere, and a broke player can be stranded.** RETRY is always
   enabled (`RetryPromptView.swift:123`). If the machine has a destroyed core, weapon or drive,
   `retry` clears the report and calls `startFight`, whose guard fails silently
   (`CareerHomeView.swift:312`), so the player lands on "There is no match waiting." With one
   machine, a bill larger than the scrap in hand and no write-off (retired with the bracket),
   the only way out today is bug 2. Fix bug 2 without a floor and this becomes a hard softlock.
   Seen on the simulator with `fx-broke.json`: 40 scrap, "Repairs owing 641", FIGHT disabled
   with "Core destroyed. Repair it for 641 before the match, or send another machine." and no
   other machine to send ([30]).
5. **The rewards screen announces parts the player already owns.** `newlyUnlocked` filters by the
   catalogue, not by ownership (`ProgressionEngine.swift:175` to `177`). With the shipped starting
   loadout, wins 1, 2, 6 and 16 say "New in the shop" for the spare battery, saw, polycarbonate, ram
   and titanium.
6. **Stale pad actions after a career fight (likely; needs a real pad to confirm).**
   `CareerFightView` never calls `PadFocus.shared.clear()` (compare `FightView.swift:102`), and
   the match report, rewards and retry screens register no items. The Series screen's or the
   scouting screen's items stay live, so pressing A on the match report can fire FIGHT
   (`CareerHomeView.swift:521`) and start the next match without the report or rewards being read.
7. **A draw counts as the rival's win.** `CareerStore.swift:167`:
   `if report.isWin { lossesVsPlayer += 1 } else { winsVsPlayer += 1 }`, so grudge lines and the
   history line treat a draw as a defeat.
8. **A quick fight draw reads LOST.** `ResultSheet.swift:75` chooses between WON and LOST only.
9. **Stale words from retired systems in player-facing text.** `Onboarding/Onboarding.swift:156`
   ("Enter the circuit, win the purse"), `SettingsView.swift:191` and `:192` ("circuit",
   "circuits"), `Store/UnlockView.swift:38` and `:47` ("circuits"), `Store/UnlockView.swift:40`
   ("CINDER, the first arena boss", while Series 1 fields Thresher), `Events/EventsView.swift:174`,
   `:524` and `:537` ("blueprint"), `Replays/ReplaysView.swift:204` ("career tie").
10. **Quick fights write into a machine's career record.** `ResultSheet.swift:252` increments
    fights, wins and knockouts and sets "killed by" for an exhibition.
11. **The Workshop's capacity is hard-coded to one** (`WorkshopView.swift:27`) while the career
    garage allows up to five, so the two garages disagree about how many machines you may have.
12. **Text floors defeated by scaling.** Body text is clamped to 13 (`DesignSystem.swift:100`) and
    then `minimumScaleFactor` (as low as 0.6) shrinks it below 13 on long lines, for example the
    scouting and Series card lines.
13. **The Replays lock badge is drawn over the empty-state sentence** on a free game, so neither
    reads ([14], `Replays/ReplaysView.swift:204` under the `LockedPanel`). Events has the same
    stamp laid across its panels, and its panels run over the machine, against the clear-left
    layout rule every other stage screen keeps ([13]).
14. **Fresh-install loading on the simulator ran past 60 s** ([02b]) against a 40 s give-up timer
    that cannot fire while the engine holds the main thread (`ArenaHost.swift:367` to `392`).
    The simulator is not the phone, so this is a flag for a device measurement, not a verdict.

---

## 9. Decisions for the owner

1. **Broke with an unfit machine: free patch-up or scrap a part?** Either (A) a free emergency
   patch that brings the core, drive and weapon to 25 % when the player cannot afford the bill and
   has no other fit machine, or (B) bring back the write-off: scrap the machine for 40 % of its
   value (`scrap_for_parts`, already in the data) and start a fresh starter machine.
2. **Workshop repair: charge it or remove it?** Either the Workshop charges the same bill as the
   career, or repairs only happen in the career and the Workshop shows the bill as read-only.
3. **Medals: yes or no, and how do replays pay?** Either medals with "full pay the first time a
   medal is earned, half after", or no medals and replays stay at half pay.
4. **Armour and utility prices: full-coat pricing or leave as is?** Either armour at the full-coat
   formula (Steel 184, Reinforced 208, HDPE 61) and utilities at factor 20 (60 to 180), or keep
   today's 14 to 49 and 18 to 54.
5. **The first purchase: take the Saw out of the starting loadout, or move the Axe to Level 4?**
6. **The tail: bring Vortex spinner, Overcharge core and Apex forward so they are used in the
   campaign, or keep them as post-campaign trophies?**
7. **Part mastery and Mk II / Mk III upgrades: build it (6 to 8 days, changes brief v5) or not?**
8. **After the campaign: Championship Defence, a daily broadcast, both, or neither for 1.0?**
9. **The first match: full three minutes, or a shortened two-minute opener for the very first
   career fight only?**
10. **Menu music: a menu theme, or sound effects only in the shell?**
11. **Graphics modes: ship the four-mode row, or Auto only with no player choice?** And: is
    Battery allowed to run the menus at 30 frames a second?
12. **Garages: one Garage reachable from the menu and the career, or keep the Workshop as a
    sandbox that never touches the career machines?**
13. **Free taster of the locked modes: one event and one ladder fight for free players, or keep
    them fully behind the wall as brief v3 section 14 says?**
