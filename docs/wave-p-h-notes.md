# Wave P, agent H: the shipped art on the screens, the last owed items, and the diagnostics strip

Built 2026-09-21 on `main` from `566ddba`, in the tree. The owner asked for "everything that needs
doing so I can test a final game", and this is the list of older owed items from
`docs/brief-coverage.md` and the session notes. Agents E (models) and F (fx and audio) were working
in the same tree at the same time; nothing here touches their files.

Nothing here was committed by me. Two of these files (`Arena/bot/chassis/apex.gd`,
`Arena/tests/mobility_p_test.gd`) were swept into `7cdba1c` by another agent's commit while the
tree was shared, and one edit (`Arena/render/graphics_quality.gd`'s doc comment) was lost when the
build image was unmounted mid-session and had to be written again. Both are in the tree now; worth
knowing if the history looks odd later.

Everything below was verified headlessly: `scripts/test-arena.sh` for the arena, one simulator
screenshot per screen inside the `/tmp/roboteer-sim.lock` mkdir lock with the volume forced to 0,
and `-careerSelfTest` for the engine. No window was opened and no sound was played.

Screenshots: `/tmp/roboteer-shots/wave-p-h/`.

---

## 1. The shipped art is on the screens

Agent V1 drew 6 arena cards, 5 boss portraits, 8 rival portraits, 10 weapon glyphs, 7 utility
glyphs and 5 tier badges in `Art/ui` back in wave V. Until now the only ones any Swift screen used
were the five tier backdrops and the menu key art. All of it is on screen now.

| Where | What is drawn |
|---|---|
| Series screen, next-match card (`CareerHomeView`) | the rival's portrait beside their name; the arena's key art as a lower third with the house bot's portrait against its trailing edge |
| Scouting report (`ScoutingView`) | the rival's portrait in the header row; the arena card beside the house bot sentence; the boss's portrait at the end of that row |
| Campaign board (`BracketView`) | the Series badge (`tier_<id>.svg`) at the head of each of the five rows, `line` when the Series is open and faint when it is locked |
| Shop rows (`ShopView`) | the weapon and utility glyphs, one column, ahead of the name |
| Builder part lists (`BuilderView`, outside the Livery section) | the same glyphs on the weapon and utility rows |
| Quick fight arena picker (`QuickFight`) | all six arenas as their own key art, cropped to a 2.35 band |

**Bundling.** Nothing had to be added to `project.pbxproj`. `Art/ui` has shipped as a folder
reference since wave V (`AA0000000000000000000FA1` / `FB1`, the pattern agent G copied for
`Art/paint`), so every file lands under `ui/` in the bundle and `BroadcastArt.image` already found
it. Confirmed on the screenshots: the art is there in a build from a clean `scripts/build-sim.sh`.

**`UIImage` cannot read an SVG, so the glyphs are parsed.** `GlyphArt` in `DesignSystem.swift` is
a small reader for exactly the subset every file in `Art/ui` uses and nothing more: one `<g>` with
`transform="translate(tx,ty) scale(s)"`, `fill`, `stroke` and `stroke-width`, holding `<path>` with
absolute `M`, `L`, `C`, `Z` and `<rect>`. A file it cannot read returns nil and the caller prints
the word instead, which is what `Arena/ui/controls.gd` already does with the same glyphs. Drawing
them rather than rasterising them means they tint (`type` on a row, `typeDim` when the part is
owned) and stay crisp at any size, which a PNG at 2x would not.

**Hierarchy.** No screen gained a panel. Every piece of art is inside the one panel the screen
already had, or (the Series badges, the shop glyphs) is a mark beside a word on the glass. The
next-match card's arena art replaced a sentence rather than being added to one: the card says
"House bot on duty: Cinder." and the band carries "THE GRINDER", where it used to say both.

**New reusable pieces**, all in a `// MARK: - Wave P, agent H` section at the end of
`DesignSystem.swift`: `GlyphArt`, `BroadcastGlyph`, `GlyphMark`, `PortraitPlate`, `ArenaCard`,
`ArenaBand`. `StatPips` gained `pipWidth` and `gap` so six of them fit one row of the report.

## 2. The three missing weapon glyphs

`Art/ui/glyph_weapon_shock_prod.svg`, `glyph_weapon_tesla_arc.svg`, `glyph_weapon_drill_lance.svg`,
64 x 64, white on transparent, with copies and `.import` sidecars in `Arena/assets/ui/`.

Drawn by hand as real 3 unit stroked paths, not generated. The V1 notes are right that Recraft's
line weight is wrong for a glyph: the ten existing ones are filled traces with a measured outline
standing in for a stroke. These three are centrelines at the design system's own weight, which
reads the same at 64 px and is honest geometry for anyone editing them later. Only `M`, `L`, `C`
and `Z`, so the Swift reader above can take them.

- **shock_prod**: grip block, shaft, two pronged fork, a bolt arcing between the prongs.
- **tesla_arc**: two ball topped electrodes on a ground line, an arc leaping between them.
- **drill_lance**: mount block, a barrel with three helical flutes, a conical point. The flutes are
  the point of it: without them a drill and the ram's wedge are the same glyph at 64 px, which the
  first draft was, and the contact sheet showed it.

They were checked against the other ten on one rendered contact sheet before shipping.

**Wiring.** Nothing to wire in GDScript: `controls.gd` builds its kind to part id map from the
catalogue itself and `Broadcast.glyph` loads `res://assets/ui/glyph_weapon_<id>.svg`, so the three
files are all that was needed. `ui_test`'s glyph check used to report "10 of 13 glyphs are drawn"
without failing; it now ASSERTS all thirteen, and passes. Swift's `BroadcastGlyph.weapon(_:)` does
the same borrow-by-kind so `twin_saw`, `napalm_cannon` and `vortex_spinner` use the saw, the
flamethrower and the full body spinner glyphs rather than shipping duplicates.

Probed the exported `Roboteer/Resources/arena.pck` with `--main-pack`: all three resolve and load
out of the pack the phone actually reads.

## 3. Quick fight: the arena picker and the Rumble entry

**Both already existed.** The coverage table's two OWED rows (`§10` quick fight arena picker, `§10`
Rumble entry point) were written on 2026-09-14 and were out of date: `QuickFightPicker` has had a
six arena picker gated by `Gates` and a RUMBLE row since wave G, `QuickFightChoice.rumble` is
remembered, and `FightConfigFixture` sends `rules.mode = "rumble"` with a third machine. Verified
on the sheet and traced end to end. The coverage table is corrected.

What this wave did add:

- The picker's six chips became the six arenas' own key art. A locked one is desaturated and says
  **"Full game"** in the `line` colour on its own face.
- The line that used to sit under the grid ("4 arenas unlock with the full game") is gone: every
  locked card says it now, and the RUMBLE row needs the height more than the sentence does. On a
  874 x 402 pt phone ARENA, OPPONENT and RUMBLE are all on the sheet without a thumb, which is what
  the comment in that file has been asking for.

Rumble keeps its 90 second clock while a fight is three minutes. That is deliberate and documented
in `FightConfigFixture`; it was not changed here.

## 4. The free game's wall, in the engine

Coverage row `§14`. `ProgressionEngine.settle` already refused to ADVANCE past Series 2 while the
game is locked. What was missing is the case an advance can never produce: a save that is already
standing on the wrong side of the wall. An entitlement that lapses, a Family Sharing organiser who
turns it off, a `-career` fixture, a build run with `-locked`.

`ProgressionEngine` gains:

- `lastOpenSeries(gates:)`, read from `Gates` rather than hard coded, so what is free stays defined
  in one file. Free = 1, bought = 4.
- `isBehindWall(state:gates:)`.
- `nextMatch` now takes `gates:` (defaulted) and returns **nil** behind the wall.
- `settle` refuses behind the wall: no scrap, no points, no advance. Second lock on the same door.

**The save is never touched.** The MATCH is refused, not the career. The moment the entitlement
comes back the same save carries on from the same place, and the Series screen says exactly that:
"SERIES 3 NEEDS THE FULL GAME / The free game is Series 1 and Series 2. This career is standing in
Series 3. / Nothing is lost. Unlock the full game and it carries on from exactly here." with UNLOCK
THE FULL GAME as the one primary. The menu card says the same in one line.

**A finished campaign wins over the wall.** A career that has taken all five Series and then lost
its entitlement has not lost the twenty matches it won; what it loses is the REPLAYS. Both screens
say so in those words ("The campaign is yours / Nothing you have won is lost. Replaying a match
needs the full game.", with `Gates.lockedReason(.replays)` under the unlock), rather than claiming
Series 5 has stopped. A locked player still inside Series 2 is unaffected: their match is handed
out as usual and the strip's sixth cell says "Series 3 / needs the full game", which is what it has
always said.

**And it waits for StoreKit.** This is the trap the first cut walked into. `Gates.snapshot` reads
`StoreService.unlockedSnapshot`, which is FALSE at launch until `Transaction.currentEntitlements`
answers. Enforcing on that would have shown a paying player "your career has stopped" for a moment
on every cold launch. `Gates` now carries `entitlementSettled` (mirroring `StoreService.didLoad`
through a new nonisolated `didLoadSnapshot`), and `isBehindWall` returns false until the
entitlement is KNOWN rather than assumed. Everything that merely dims or padlocks still acts on the
assumption, because the worst that costs is a padlock that disappears a moment later.

`CareerSelfTest.checkTheWall` gained: the free game's last Series is 2; for each of the five
Series, whether it is behind the wall and whether `nextMatch` hands a match out, locked and
unlocked; and a win smuggled in behind the wall banking nothing. The self test's own non-wall
`nextMatch` calls now pass `gates: .open` (they run before StoreKit has answered, which is what
`Gates.open` is documented for).

**`-careerSelfTest`: ALL PASS, three ways.**

| run | result |
|---|---|
| plain | ALL PASS (869 checks, 0 warnings) |
| `-locked` | ALL PASS (870 checks, 0 warnings) |
| `-unlocked` | ALL PASS (870 checks, 0 warnings) |

B2's last run was 832 checks with 1 warning; the warning was the 13 unbuilt ladder ids, which D1
and D2 have since built.

## 5. The fight is drawn at the phone's own pixels

`Arena/project.godot` `window/stretch/mode` is **`"disabled"`**. V4 measured the cost of
`canvas_items`: the fight's SubViewport was sized from a Control rect in stretched canvas units, so
the whole 3D image was rendered at 2417 x 1112 and blown up to 2622 x 1206 on every frame. 15 % of
the phone's pixels, thrown away, on the only screen the owner said was blurry.

**Nothing on the glass changed size.** `hud.gd` and `controls.gd` both compute
`_pt = min(s.x / 1206, s.y / 556)` from `get_visible_rect()`. That was 2.0 in canvas units times a
1.0846 stretch; it is 2.1692 in device pixels with no stretch. The same number, which is V4's own
arithmetic and is now asserted. The safe area, which Swift sends in DEVICE pixels and `hud.gd`
consumes unconverted, stopped being 8.5 % too generous and became exact.

The HUD pass:

- `hud.gd`: the `REF_SIZE_PT` comment said "base canvas"; it is a RATIO and says so now. New public
  `points()` so a test can assert a point sized piece of the layout instead of assuming `_pt` is 1.
- `controls.gd`: the same comment corrected (it claimed 2412 x 1112 gives `_pt` = 2.0).
- `render/graphics_quality.gd`: the long "nothing here fixes it" note rewritten to what was done.

**The broken checks, and what was actually wrong.** V4 predicted three in `ui_test`; the whole
suite turned up nine, across four files. None of them were a HUD bug.

Under `canvas_items` the root viewport reported the 2412 x 1112 BASE whatever the real window was,
and any test that put a Control in `root` and measured it was quietly leaning on that. A headless
run's root window is **64 x 64 and cannot be resized**: the headless DisplayServer has no window to
resize, and `root.size = ...` reads back correctly for one line and is gone by the next frame.
(`content_scale_mode` / `content_scale_size` set at runtime do not help either; measured.) So the
HUD was being laid out in 64 x 64, a stick drag written in design points landed outside the stick
zone, and `_points_to_pixels` scaled a 120 point drag down to 6 pixels.

| file | what broke |
|---|---|
| `ui_test` | the reserved corner, its clearance, and which side each lower third is on |
| `commentary_test` | the commentary line was not inside the ticker strip |
| `test_arena_runs_test` | the stick drag missed the controls, the machine never moved, and the names and the scrap bug were not below the shell's 60 pt row |
| `stage_camera_test` | a forwarded orbit turned the camera by 0.76 degrees instead of 45 |

Fixed properly rather than by loosening the checks: each of them now gets its own SubViewport at a
size that means something, which is the pattern `ui_test`'s controls tests have used all along.
`ui_test`'s HUD host is posed at the phone's real pixel rect (`DEVICE_PX` 2622 x 1206), and its two
checks that quote a point constant multiply it by the HUD's own `points()` instead of assuming 1.0.
The other three use `DESIGN_SIZE` 1206 x 556, one unit per design point, because what they measure
is written in points. **`ui_test` 372/0, `commentary_test` 82/0, `test_arena_runs_test` 24/0,
`stage_camera_test` 14/0.**

`render_test` asserts the key itself and reads the oversample back as **1.0000** on a viewport
posed the way the phone poses it, and still proves the probe can SEE a blow up (the old
`canvas_items` pose still reads 1.0846). **115 checks, 0 failures.**

**`apex.gd` has `has_own_ring()`.** D1's note: the Shell hands its ring to any `fbs` weapon and the
Apex needs the same rule, or the vortex builds a ring at the front socket and
`vortex_spinner._shield()` correctly refuses to take the armour faces out of the world. The Apex
has no separate ring mesh to hide, so it pulls its WHOLE body in to a core instead: the waist's far
corner is 0.610 m from the middle and the two `fbs` weapons reach 0.45 m and 0.48 m, so a full size
Apex would stand proud of its own ring at all four corners. At `CORE_FRACTION` 0.64 the corner comes
in to 0.391 m, inside the shorter ring with 0.06 m to spare, all the way round. `levels()` drives
both the collision hull and the silhouette, so the two cannot disagree. Four checks in
`mobility_p_test.gd` (`_check_apex_ring`): **47 checks, 0 failed.**

## 6. What was stripped for shipping

Six things showed in a Release build with no launch flag, or sat one modifier away from doing so,
and should not have. The QA launch flags themselves all stay: they are how this is tested.

1. **The settings screen's engine diagnostics.** The sidebar panel read "The arena / State: ready /
   Godot: 4.6.3.stable.official / Controller: none". The engine's state and version are a
   diagnostic and mean nothing to a player. They are now behind `-showSpike`, which is already the
   flag for the bridge diagnostics screen. The Controller line stays, because whether a pad is
   connected is a real question a player has, and the panel's heading is "Controls" so the word is
   not said twice.
2. **`HostBridge.deliver` logged a line for every message from the arena**, including `haptic`
   (many a second during a fight). A `quiet` set now skips `haptic` and `replay_state`.
3. **`ArenaHost.receiveRaw` logged `replay_state`**, six a second for the whole length of a replay.
   It already skipped `haptic`; it skips both now.
4. **The main menu's "Arena ready."** The engine reporting its own state to nobody, bottom left of
   the menu, in every shipped build. Only the other half of that line is a player's business, so
   "Arena loading." stays while there is something to wait for and nothing is said once there is
   not.
5. **`FightView.statusLine`**, a dead private property that built the string "Fight. Bot: Tinribs,
   89.5 kg. State: fighting. Opponent: normal. Safe area: 59, 0, 59, 21 px." Nothing has drawn it
   since the fight HUD took the feed over. Deleted rather than left one modifier away from
   shipping; the same facts are in the arena log and behind `-showSpike`.
6. **`ScoutingView`'s "CHOOSE YOUR BOT" heading** was label type floating on the live stage with no
   plate under it, unreadable over the turntable light. Gone; a row of machines with one of them lit
   beside FIGHT says what it is.

Swept and found clean: no `TODO`, `FIXME` or lorem string reaches any screen; no frame counter or
perf readout anywhere; the test arena's physics overlay is gated to `rules.mode == "test"`, which is
the brief's own Workshop Test Arena; the simulator's renderer note is gated to
`ArenaHost.isSimulator` and never reaches a device; `QaShots` is inert without `--roboteer-shots=`; the `-locked`
and `-unlocked` overrides are `#if DEBUG`; the SPIKE chip is behind `-showSpike`. The one `TODO`
comment left in the codebase (`Gates.freePartIDs`, about a `progression` block that is now always
present) is a code comment, not a screen, and is not mine to resolve.

## 7. B2's three nits

**The scouting report's fold landing mid sentence.** The report does not scroll any more. The
machine chooser and FIGHT moved out of the right hand column and along the foot of the screen,
which gave the report the whole column; the opponent's six catalogue scores moved into the header
row, where the portrait is 52 pt tall and three rows of pips are 45, so they ride in height the row
already had and cost the report nothing; and the weight joined the parts line so the header row had
the width for them. On the phone the owner plays (874 x 402 pt) the whole report is on screen: the
portrait, the six pips, the parts line, the armour line, the arena card, the house bot and what it
does, the money sentence, the grudge line and the history line. Below 370 pt of landscape height
only the PIPS go (`pipsNeed`); every sentence still fits, because a report that cuts a sentence in
half is the one thing this screen must not do.

**A replay of an earlier Series showing the current Series' strip.** The strip and the board cells
now follow `ProgressionEngine.pending(state)`, which is the match on duty, so replaying Series 1
match 2 prints Series 1's four matches under a card about Series 1. The "what comes after" cell and
its lock follow the same Series.

**The career ticker repeating the card's house bot line.** It was the card read out twice: the
opponent, the roboteer, the arena, the house bot, the Level and the scrap are all already on the
screen. The ticker is the season's talk now: what the other corner has to say (the rival's grudge
line, which is otherwise only on the scouting report), how much of the Series is left to run ("TWO
MORE WINS TAKE SERIES 2"), and the career's record and parts owned.

---

## Verification

| what | how | result |
|---|---|---|
| Godot, the three I changed | `scripts/test-arena.sh ui_test render_test mobility_p_test` | ui_test 372/0, render_test 115/0, mobility_p_test 47/0 |
| Godot, everything | `scripts/test-arena.sh` | **PASS, 34 test files, 0 failures** (the first run found 3 failing files, all of them the stretch change; fixed and run again clean) |
| Swift | `scripts/build-sim.sh` | BUILD SUCCEEDED, no new warnings |
| the engine's wall | `-careerSelfTest`, `-locked`, `-unlocked` | ALL PASS 869 / 870 / 870 checks, 0 warnings |
| the shipped pack | Godot `--main-pack Roboteer/Resources/arena.pck` | the three new glyphs resolve and load; `stretch/mode` reads `disabled` |
| the screens | headless simulator screenshots | table below |

Screenshots, all `/tmp/roboteer-shots/wave-p-h/`, taken on `A18A1779-2368-4FFF-9195-1523D4ABA146`
inside the lock with `-godotDriver dummy -godotMethod dummy -godotDisplay headless`:

| Shot | What it proves |
|---|---|
| `series.png` | the rival's portrait, the arena band, the boss's portrait, the money sentence, FIGHT, the four slot strip and the ticker all on one 402 pt screen |
| `scouting.png` | the whole report with no scroll and no fold: portrait, six pips, arena card, boss portrait, both sentences, the grudge and the history |
| `board.png` | the five Series badges on the campaign board, open in `line` and locked faint |
| `shop-weapons.png`, `shop-utility.png` | the weapon and utility glyphs in the shop rows |
| `builder-weapon.png`, `builder-utility.png` | the same glyphs on the builder's part rows |
| `quickfight.png` | six arena cards, two open and four saying "Full game", with OPPONENT and RUMBLE still on the sheet |
| `wall.png` | `career-masters.json` with `-locked`: the engine hands out no match and the screen says why, with the unlock as its one primary |
| `wall-regional.png` | `career-regional.json` with `-locked`: a free player inside Series 2 is unaffected, gets their match, and the strip's sixth cell says "Series 3 / needs the full game" |
| `complete-unlocked.png` | the same masters save with the game bought: the completion panel, no false wall |
| `menu.png`, `settings.png` | the menu card, and the settings sidebar with the engine diagnostics gone and "Arena ready." off the menu |

## One thing found and deliberately NOT fixed

**Fifty pieces of body type across the app are under the design system's own legibility floor.**
Section 7 says body never below 13 pt. Counted with `grep` over `Roboteer/**/*.swift`: one at 9 pt,
21 at 10, 22 at 11, six at 12, against 40 that are at 13. They are in fourteen files: the builder,
the career garage, the events list, the ladder, the onboarding, the quick fight, the replay screens,
the result sheet, the settings, the unlock screen and the workshop.

The two on the scouting report are fixed, because that screen was being re-laid out here anyway and
was verified on a screenshot afterwards. The other forty-eight are NOT, and should not be: raising
type is a layout change on every screen it touches, each one needs its own photograph to prove
nothing fell off the bottom, and doing fourteen of those blind on the day the owner wants to play
the game is how a working build stops working. It is a real finding with a real number, and it
wants its own pass with the sim in front of it.

## What needs the phone

- **The fight itself, at its new resolution.** This is the whole point of item 5 and it cannot be
  photographed here: a headless simulator launch draws the menus over a STILL, so no screenshot of
  this machine shows anything about the fight or the machine in it (agent G proved it; agent G's
  note is in `docs/wave-p-g-notes.md`). The arithmetic is asserted by `render_test` and the layout
  by `ui_test`, and `GraphicsQuality.describe()` reports `oversample` so it can be read off the
  phone: it should say **1.0000**.
- **The Apex wearing a full body spinner.** The collision and the silhouette both come from
  `levels()` and are tested, but nobody has seen a vortex ring standing proud of an Apex core.
  ⚠️ If agent E's `apex.glb` lands, the MODEL will not shrink with the hull: `_build_visual` uses
  the .glb and ignores `procedural_meshes()`. The Apex then needs the Shell's other half of the
  handover, a `_on_model_bound()` that hides or pulls in the bodywork, the way `shell.gd` hides its
  `ring` mesh. Written down here because it is a one line symptom (a hull sticking through its own
  ring) with a five minute fix.
- Whether the six arena cards read at thumb size, and whether the scouting report at its new
  density is comfortable rather than merely complete.

## The one thing that would have bitten quietly

`window/stretch/mode = "disabled"` is not a rendering change with a UI side effect. It is a
**coordinate space** change, and the thing it broke was not the HUD but the TESTS, because
`canvas_items` had been handing every headless run a 2412 x 1112 viewport that no window ever had.
Any test that adds a Control to `root` and measures it in points was relying on that, and there
were four of them, not the one V4 predicted. There is one pattern that survives it, and it is the
pattern `ui_test`'s controls tests already used: **give the thing its own SubViewport at the size
you mean.** Anything added to `root` in a headless run is laid out in 64 x 64, and no amount of
`root.size`, `DisplayServer.window_set_size` or `content_scale_size` changes that.

It is also why the whole suite had to run rather than the three files the change obviously touched.
Two of the four broken files (`stage_camera_test`, `test_arena_runs_test`) have nothing to do with
the HUD and would not have been on anybody's list.
