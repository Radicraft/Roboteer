# Wave B: progression and economy (engine, data, model)

Progression engineer, 2026-09-24. STOPPED EARLY on the coordinator's order (owner near the session
limit). This is a WIP handover: nothing below has been built on the simulator or self tested yet.
No simulator was booted.

## Done (WIP commit, not built)

- `Shared/parts.json` (and the `Arena/data/parts.json` copy, byte identical):
  - Decision 4: `economy.price_factor.utility` 6 -> 20 (utilities 60 to 180); economy notes say
    armour is a full coat.
  - Decision 5: `saw` out of `career.starting_unlocks`; `level_required.saw` 5 -> 4, so the Saw
    is buyable after win 1 (350 points = Level 4) with the 300 float plus one win's scrap (144).
  - Decision 6: `overcharge_core` 90 -> 85, `vortex_spinner` 95 -> 90, `apex` 100 -> 95 (frontend
    meta 3.3). With the shipped points that is buyable after Series 5 wins 18, 19, 19: the final
    is fought with the best hull and the vortex.
  - New `progression` blocks, all read with defaults: `round` (180 s, endgame 120), `opener`
    (decision 9: 120 s, endgame 80), `medals` (decision 3), `defence` and `daily` (decision 8),
    `taster` (decision 13: 1 event, 1 ladder fight).
- `CareerCatalogue.swift`: `RoundRules`, `MedalRules`, `DefenceRules`, `DailyRules`,
  `TasterRules` on `Progression` (defaulted vars, parsed in `readProgression`).
- `ProgressionEngine.swift`: armour priced as a full coat (`referencePlateWeight` = every face's
  area x 2 units): Steel 184, Reinforced 208, HDPE 61, Titanium 98, Polycarbonate 73, Reactive 159.
- `ProgressionTypes.swift`: `NextMatch.Mode` (campaign, defence(n), daily(dayKey)), `durationS`,
  `endgameAtS`, `hasHouseBot`, title per mode; `Rewards.medals/newMedals/medalTopUp/headline/
  bankedTotal`; `MedalKind` (win, survivor, finisher), `MedalBoard` (keys "s2.m3.survivor",
  counts out of 60); `SeriesMatchSlot.medals`.

## Self test checks that WILL FAIL until updated (CareerSelfTest.swift, not yet touched)

- `checkLadder`: the brief table still expects saw 5, overcharge 90, vortex 95, apex 100; and
  "something is unlocked at the cap" (apex moved to 95; Level 100 now opens only Champion gold).
  Update the table to the owner's new numbers and let the cap check accept a paint job.
- `checkShopPrices`: "a material is priced as a front plate at two units" must become the full
  coat (sum of face areas x 2 x factor), and assert Steel 184, Reinforced 208, HDPE 61.
- Re-run `checkAffordability` / "a won campaign can clear the whole shop" with the new prices.

## Next, in order (the plan I was building to)

1. Medals engine in `ProgressionEngine`: `medals(for report)` (win; survivor = arena survivor line
   > 0, else own condition >= 0.7; finisher = outcome in `knockout_outcomes` or flawless); extend
   `settle` with `outcome:` and `medalsHeld:` (defaulted); on a REPLAY a new medal pays the full
   match: `medalTopUp = round(total / replay_scale) - total` and full points; `CareerState.medals:
   [String] = []` (lightweight migration); `CareerStore.settleMatch` banks `bankedTotal` and
   appends new keys; `seriesSlots` fills `medals`. Keep the replay scrap rules at half on the wire
   (the HUD bug under-promises, the top up lands on the rewards screen). RewardsView: a medals
   line, a "Medal bonus" ledger row, `CountingNumber(value: rewards.bankedTotal)`.
2. Opener: `nextMatch` sets `durationS/endgameAtS` from `progression.opener` for Series 1 match 1
   (not a replay), `round` otherwise; house bot line says "at 1:20" for the opener.
   `CareerFightView.swift` (combat engineer's file) needs a two-line change: send
   `rules.duration_s = next.durationS`, `rules.endgame_at_s = next.endgameAtS`, and only send
   `enforcer` when `next.hasHouseBot`. `Arena/fight/fight.gd` uses a fixed `ENDGAME_AT_TICKS`
   (120 s), so with a 120 s opener the house bot would never come out: the combat engineer must
   read `rules.endgame_at_s` (default 120). Put this in `docs/wave-a-contracts.md`.
3. One garage (decision 12): `Garage.capacity(career:gates:)` = `gates.garageCapacity(forTier:)`
   (Scrapyard when there is no career); `CareerStore.state(in:)` re-syncs the stored
   `garageCapacity`; `Garage.canDelete` = more than one machine. WorkshopView: replace
   `private let capacity = 1` (bug 11) and gate Delete. BotBuild is already one store for both
   screens, so no data moves; over-capacity garages keep every machine, they just cannot add.
4. Taster (decision 13): `CareerState.tasterEventsUsed/tasterLadderUsed` (default 0) and a pure
   rule next to `Gates` (unlocked, or used < `progression.taster`); EventsView/LadderView use it
   instead of `sideEventsAvailable/ladderAvailable` for one play; mark used at fight start;
   `EventStore.awardBlueprint` must refuse a part `Gates.partAvailable` refuses.
5. Ladder record (flag from wave A): per brief v5 9.3 the ladder is an exhibition. Stop writing
   fights/wins/kos into the machine (`LadderView.swift` ~452), send the machine pristine, do not
   carry damage home. The `FightLog` with `source = ladder` stays its history.
6. Post-campaign (decision 8), new file `Roboteer/PostCampaign.swift` (add to the pbxproj):
   Championship Defence: `nextMatch` returns `mode: .defence(streak + 1)` when the campaign is
   complete and no replay is queued; challenger n = `defence.challengers[(n-1) % 8]` at Masters
   spec, arena cycles `defence.arenas`, house bot `bossForArena`, speed +0.05 per full cycle
   (max 1.25), pay = Series 5 rules x 0.5, no points; `CareerState.defenceStreak/defenceBest`;
   a loss ends the reign. Daily: `dayKey` (UTC "yyyy-MM-dd"), seed from the key, arena/opponent/
   twist drawn from it, `NextMatch(mode: .daily)` with zero scrap rules, score = published formula
   in `progression.daily.score`, best per day kept as JSON on `CareerState`, last 7 days playable,
   `GameCenterService.report(leaderboard: "daily_exhibition")` (a recurring leaderboard to create
   in App Store Connect; silent when missing). Entry: a "Daily" text link on the Series card once
   the campaign is complete, a simple Broadcast-style screen, fought through `CareerFightView`.
7. Self test: all of the above, plus a campaign simulation that buys parts as they open and pays a
   repair per win, printing the scrap curve and an hours estimate; 0 failures with `-locked` and
   `-unlocked`. Then `scripts/build-sim.sh` and the self test on one iPhone 17 simulator.

## Pacing numbers (from the numbers, not yet from the self test)

- Scrap per typical win (base + half damage + survivor): 180, 300, 480, 720, 1,040 by Series;
  a won campaign banks about 10,880 plus the 300 float.
- New shop total to clear (not owned at start): about 7,900 (was 6,744): +144 Saw, armour
  materials to full coat (Reinforced 208, Reactive 159), utilities x 20/6.
- Hours: 20 wins; at about 2.5 min a fight plus 1.5 min of menus, and 1.3 to 1.6 attempts per win
  rising by Series, the campaign is roughly 2 hours of play. To be confirmed by the self test's
  simulation once written.

## Migration notes

- Every new field planned on `CareerState` has a default (lightweight migration). Old players
  keep the Saw: `migrate()` only ever adds `startingOwned`, never removes, and every post-wave-P
  save already owns it. Only new careers start without it.
