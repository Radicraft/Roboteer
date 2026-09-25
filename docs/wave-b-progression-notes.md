# Wave B: progression and economy (engine, data, model)

Progression engineer. Started 2026-09-24 (WIP `251bc04`, data and model only), finished
2026-09-25. Owner decisions: `docs/aaa/decisions-2026-09-24.md` (3, 4, 5, 6, 8, 9, 12, 13).
The owner has NOT chosen the payoff / shop / walk-out / garage / post-campaign screens
(`docs/look/progression-screens-v1.html`), so none were built: only minimal functional hooks in
the existing style (no edge strokes, no em dashes, 13 pt body floor).

## Status: done, self test ALL PASS

`-careerSelfTest` on one iPhone 17 simulator (iOS 26.5, Debug, headless dummy driver, no audio):

| run | result |
|---|---|
| plain | ALL PASS (1018 checks, 2 warnings) |
| `-locked` | ALL PASS (1019 checks, 2 warnings) |
| `-unlocked` | ALL PASS (1019 checks, 2 warnings) |

The two warnings are the pacing sim's repair case (below), not defects. Was 918 checks.
`scripts/build-sim.sh` green; no iCloud " 2" duplicates found.

## What landed

1. **Medals (decision 3).** `ProgressionEngine.medals(for:rules:)`: win; Survivor = the arena's
   survivor line when the rules paid one, else own condition kept >= `medals.survivor_min`;
   finisher = an outcome in `knockout_outcomes` or flawless (the arena's line when paid, else no
   part lost). `settle(..., medals:, medalsHeld:)` returns `medals`, `newMedals`, `newMedalKeys`,
   `medalTopUp`, `banked`. A replay that earns a medal for the first time pays the whole match:
   `topUp = round(total / replay_scale x new_medal_scale) - total`, and full points. The wire still
   carries the replay's half (the HUD under-promises; the top up lands on the rewards screen).
   `CareerState.medals` (keys "s2.m3.survivor"), `medalBoard`; `seriesSlots` fills `medals`.
   RewardsView: "Medal bonus" ledger row, a plain medals line, `bankedTotal` counted.
2. **Two-minute opener (decision 9).** `ProgressionEngine.roundClock`: Series 1 match 1 (not a
   replay, retries included) is 120 s with the house bot at 80 s ("comes out hunting at 1:20");
   everything else 180 / 120. `CareerFightView` sends `rules.duration_s` and `rules.endgame_at_s`
   and sends the enforcer keys only when `next.hasHouseBot`. Contract: `docs/wave-a-contracts.md`
   section 6. **Owed by the combat engineer: `fight.gd` reads `rules.endgame_at_s`.**
3. **One garage (decision 12).** `Garage.capacity(career:gates:)` (Scrapyard with no career, held
   at 2 while locked) and `Garage.canDelete` (never the last living machine). WorkshopView uses both
   (bug 11 gone), counts living machines, shows one locked row naming what opens the next slot.
   `CareerStore.state(in:)` and `settleMatch` keep the stored capacity in step.
4. **Taster (decision 13).** `CareerState.tasterEventsUsed/tasterLadderUsed`; `Gates.sideEventOpen`,
   `ladderFightOpen`, `spendsTaster`, `tasterLine`. Events and Ladder open one play each on the free
   game (spent when the fight starts), with one plain line saying so; publishing stays full game.
   `EventStore.awardBlueprint` refuses a part `Gates.partAvailable` refuses.
5. **Ladder is an exhibition (brief v5 9.3).** Sent pristine (`toBotConfig(pristine: true)`), no
   damage home, no fights/wins/KOs on the machine. The `FightLog` (source ladder) is its history.
6. **Post-campaign (decision 8), `Roboteer/PostCampaign.swift` (in the pbxproj).**
   - Championship Defence: once the campaign is won and no replay is queued, `nextMatch` returns
     `mode: .defence(n)`. Challenger `(n-1) % 8` at Masters spec, arena cycles the six, Masters house
     bot for that floor, +0.05 speed per full cycle (cap 1.25), pay = Series 5 rules x 0.5, no points.
     Needs the whole game. Win extends the reign (`defenceStreak`, `defenceBest`), loss ends it, a
     draw leaves it. Settled in `CareerStore.settleMatch` (log source `defence`, round -2). Card label
     "Defend the title", ticker line, rewards headline "Title defended. A reign of 3."
   - Daily exhibition: UTC `dayKey`, FNV seed, arena / rival / twist from the seed (Championship
     spec, Masters for Heavyweight; Sprint 90/60, Open corner no house bot, Hungry house bot x1.25).
     Zero scrap rules, no points, machine sent pristine, nothing home. Score = the published formula;
     best per day in `CareerState.dailyBestJSON` (days older than `days_kept` dropped). Today's score
     goes to Game Center `daily_exhibition`. Entry: a "Daily" text link on the Series card once the
     campaign is won; `DailyExhibitionView` is a plain list of the last 7 days + card + FIGHT + score.
7. **Self test** updated (ladder table, cap check accepts Champion gold, full-coat prices 184 / 208 /
   61, utilities 60 to 180 at factor 20, Saw first buy) plus checks for every item above and a
   pacing sim.

## Dial changed

- `level_required.apex` 95 -> **93** (both parts.json copies). With the shipped points the Series 5
  final is fought at Level 93 (wins 1 to 19, no flawless), so Apex at 95 still arrived WITH the final
  win, which is exactly what decision 6 set out to fix. Overcharge 85 and Vortex 90 were already
  fine. Revert is one line if the owner wants 95.

## Pacing (from the self test's sim)

- Scrap per campaign (base + half damage + survivor on each win): 720, 1,200, 1,920, 2,880, 4,160
  by Series = **10,880** plus the 300 float. The shop costs **7,673** to clear.
- No repairs: the shop clears on win 19 with 3,507 left; no part waits more than 2 wins.
- Repairing EVERY fight at about a fifth of the machine's value (front armour 55 %, weapon 75 %,
  core 80 %; 177 to 227 scrap a fight) at 1.3 to 1.6 tries a win: repairs cost 920 in Series 1 against
  720 earned, the bank dips to -44 in Series 1 (the emergency patch-up covers that), and the shop is
  never cleared (pyramid waits 11 wins). These are the two warnings. How hard the arena really hits
  decides which of the two is the truth; watch the owner's real repair bills.
- About **1.9 hours** for the campaign (1.3 to 1.6 tries a win, 2.5 min a fight, 2 for the opener,
  1.5 of menus).

## Owed to the owner (App Store Connect, never touched by an agent)

- Create a **recurring** Game Center leaderboard with id `daily_exhibition` (daily reset at 00:00
  UTC, higher is better, integer). Until it exists the report is silently dropped.

## Owed / not verified

- `fight.gd` reading `rules.endgame_at_s` (combat engineer).
- The defence and the daily were not fought on the simulator (1 fps dummy arena); the rules are
  proven in the self test, the flow is read, not played.
- Medal stamps on the Series strip and the board, the medals count on the career card, a Hall of
  fame: screens the owner has not chosen.

## Migration notes

- New `CareerState` fields all have defaults (lightweight migration): `medals`, `defenceStreak`,
  `defenceBest`, `dailyBestJSON`, `tasterEventsUsed`, `tasterLadderUsed`. Old saves keep the Saw
  (`migrate()` only adds). An old save that won matches before medals existed earns them on a
  replay, which pays that match in full once.
