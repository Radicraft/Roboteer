# Wave A: front end fixes

Front end engineer, 2026-09-24. The confirmed bugs from `docs/aaa/frontend-meta.md` section 8,
plus owner decisions 1 and 2 of `docs/aaa/decisions-2026-09-24.md`. Before shots are the
teardown's own (`docs/aaa/img/frontend/`); after shots are in `docs/aaa/img/frontend-fixes/`
(iPhone 17, iOS 26.5 simulator, Debug, `-skipLoading`, so the stage is the still).

Self test: `-careerSelfTest` 918 checks, 0 failures, with `-locked` and with `-unlocked` (was 869).

| Bug | Fix | Verified |
|---|---|---|
| 1 Purchase after the wall | `ProgressionEngine.openedWallAdvance` / `carryPastOpenedWall`; `CareerStore.advancePastWall` runs on every career fetch (relaunch after buy or restore) and from `MenuView` on launch and whenever `StoreService.isUnlocked` turns true | self test (locked stays put, bought moves to Series 3 match 1 with attempts and queued replay cleared, relaunch, once only, mid-Series and finished campaign untouched); sim: `fx-walled.json -unlocked` opens on Series 3 match 1 (`after-28-walled-then-bought.png`, before = `28`, `29`) |
| 3 Armour gate | Builder armour segments locked by ownership like other rows, three to a row so names are not cut, one "Locked: ..." line; FIGHT (Series card, scouting, `startFight`) refuses a machine carrying an unowned part with a sentence (`ProgressionEngine.ownershipFault`) | self test; `after-09-builder-armour.png` (before = `09`) |
| 4 (part) RETRY | `ProgressionEngine.retryBlock`: RETRY disabled with a plain reason naming the fix (repair and retry, or the garage) | self test; `after-20b-retry-unfit.png`, `after-20-retry-stranded.png` |
| 5 Owned parts announced | `newlyUnlocked(from:to:owned:)`; `settle` passes the owned list | self test over a whole campaign; `after-18-rewards-win.png` |
| 6 Pad focus | `CareerFightView` clears `PadFocus`; `CareerRootView.go` clears on every screen change; match report, rewards and retry register their own items (static `padItems` so the self test can drive them) | self test drives `PadFocus` (A after the fight fires nothing, A on the report continues, B on rewards does nothing, RETRY off is never fired). **Owed: a real pad check on device.** |
| 7 Draw as rival win | `ProgressionEngine.remember(_:in:)`: a draw moves no count and clears "they won last" | self test |
| 8 Quick fight draw | `ResultSheet` uses `ProgressionEngine.resultKind` and `PostMatch` words: DRAW | self test (`resultKind`); not seen on the sim (a quick fight to a draw at 1 fps was not run) |
| 9 Retired words | Onboarding FIGHT card, Settings unlock row, Unlock lists (THRESHER and CINDER free, three more house bots), Events (part, not blueprint), Replays (match, not tie) | `after-26-unlock.png`, `after-13-events-locked.png`, `after-14-replays-locked.png` |
| 10 Quick fight record | `ResultSheet` no longer writes fights, wins, knockouts or killed-by | code read (the only writers left are `CareerStore.settleMatch` and the ladder) |
| 12 13 pt floor | `BroadcastType.floorScale(role, size:, wanted:)`: every one of the 62 `minimumScaleFactor` calls is now floored (body, display and numerals 13, labels 11), so floored text never shrinks under it; all 50 sub-13 `Stage.body` calls written at 13, `Stage.label(9/10)` at 11, `display(12)`/`numerals(12)` at 13, SF Symbols at 8 to 10 pt raised to 11. Lines that no longer fit wrap (ladder subtitle, lock badge) or take tighter tracking (Series strip names) | screens walked: home, scouting, report, rewards, retry, shop, builder, workshop, garage, settings, unlock, ladder, events, replays |
| 13 Locked overlaps | `LockedPanel` puts the badge above the greyed content instead of across it; Events and Replays keep their list to `StageLayout.columnWidth`, and Events' machine panel became plain lines in the right column | `after-13-events-locked.png`, `after-14-replays-locked.png` (before = `13`, `14`) |
| Owner 1 Stranded | `emergencyPatchAllowed` (unfit, bill over the bank, no other fit machine) and `emergencyPatched` (core, weapon, drive, wheels up to 25 %, armour untouched); "Free patch-up and retry" on the retry prompt, "Patch it up free" replaces the unpayable repair link on the Series card | self test; `after-30-broke-home-patch.png` (before = `30`), `after-20-retry-stranded.png` |
| Owner 2 Workshop repair | The Workshop's Repair button is "Repair N", paid from career scrap through `CareerStore.repair`, disabled when the bank cannot pay | `after-07-workshop-charged.png` (641 owed, 40 in the bank: disabled) |

## Left / notes for the next wave

- Bug 11 (Workshop capacity 1) untouched: the unified garage is the owner's decision 12, a later wave.
- The ladder still writes fights and wins into the machine (`LadderView.swift:452`); not in this list.
- Truncation that remains is honest (tail ellipsis at the floor, never shrinking): long opponent
  names in the Series strip ("CLATTE..."), the strip's last-cell note. A strip redesign should give
  names room.
- The Workshop's garage-slot row clips its bottom line at this height; it predates this wave and the
  garage is being redesigned.
- Running the self test drives `PadFocus.handle`, which turns the focus ring on for the rest of that
  launch. It only happens under `-careerSelfTest`.
- A `-career` fixture with `-unlocked` is now carried past the wall on load if it stands at a
  finished free Series; that is the bug-1 behaviour, not a fixture fault.
