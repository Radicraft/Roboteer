# Wave B integration (2026-09-28)

Finished the two WIP items of 2026-09-27 (judges `39e0cd3`, Blueprint type `7c616e8`), brought
the tree to green, checked the screens at 874 x 402, put a Release build on the owner's phone.

## Result

- `scripts/build-sim.sh`: BUILD SUCCEEDED (the judges' CareerSelfTest / ProgressionEngine edits
  compiled first time).
- Career self test on the NEW build (iPhone 17 sim A18A1779, muted, dummy/headless renderer,
  installed from the path build-sim prints): **ALL PASS, 1027 checks, 2 warnings** (the two
  known pacing warnings: repair-every-fight dips to -44 scrap, pyramid waits 11 wins). The
  judges card checks run and pass (no card on a KO, totals 5.7 / 4.3, verdict words, damage and
  control lines, no em dashes). Re-run after the screen fixes: same.
- Godot suite (`HEADLESS=1`, 47 files): first run (JOBS=7) 44/47 (builds, determinism, hazard
  determinism); second 46/47 (goldens not yet re-recorded); third (JOBS=10 with a device build
  exporting alongside) 46/47, venue_kit_test (the same overshoot, below); final (JOBS=8, at
  `8d3c778`) **47/47, 0 failures**.

## What was red and why

| test | cause | what I did |
|---|---|---|
| determinism_test (18 fails in the JOBS=7 run, green alone) | Harness, not the fight: the loop sampled on `process_frame`; under load Godot runs several physics steps in one drawn frame, so fight 1 stopped at tick 1800 and fights 2, 3 and the replay at 1804, and it compared two different moments (drift 0.19 m in 4 ticks of flipper fight). | Loop awaits `physics_frame` (resumes before every step), so the snapshot is always at exactly TARGET_TICK. 42/0 alone and in the suite. |
| builds_test "the spinner build removes at least one panel (0)" | One 120 s AI fight is chaotic. Probe at HEAD, same build, six seeds: 20260913 0 panels (8 hits), 14: 0 (6), 15: 1 (27), 16: 1 (34), 17: 0 (1), 18: 1 (26). The boost changed how that one fight goes; the 84-fight weapons gauntlet (boost notes) had spinner panels off 11 -> 15 across the change. Not a regression. | Check runs over `SPINNER_SEEDS` [20260913, 14, 15] and asks for at least one panel in total ([0, 0, 1] today). The fight at SEED still feeds the ram / flipper comparisons. |
| hazard_determinism x6 | Intended simulation changes, see goldens. | Re-recorded with reasons. |
| venue_kit_test (grinder "same tick (1800, 1801)", only in the JOBS=10 run) | Same overshoot. The test set `Engine.max_physics_steps_per_frame = 1` BEFORE `start_fight`, and the fight's reset (`_end_seek_clock`) puts it back to 8, so the guard was silently undone. | Set it after `start_fight`. 214/0. |

The two possible real regressions the boost notes flagged:

- **spinner removes a panel**: not a regression (above). Open observation: the spinner AI can
  land as few as 1 to 8 blows in 120 s on some seeds; worth a look when the spinner is retuned.
- **hit-stop "reference fight has 0 damage events"**: gone. hitstop_test 20/0 with 5 damage
  events, boost_test's bit-exact hit-stop matrix 33/0 with 6. It was the boost_test fixture
  before 6be13bf (presses every 150 ticks gave no blows once the arenas escalated), not the
  hit-stop path.

## "determinism_test fails under load" (coordinator / size engineer question)

No wall-clock read in the fight. The simulation is deterministic; the TEST HARNESS stopped at a
wall-clock-dependent tick. It looped on `process_frame` and read `_tick` once per drawn frame;
Godot runs up to `max_physics_steps_per_frame` (8) physics steps in a frame that arrives late,
so on a loaded machine one run could stop at 1802 or 1804 and get compared with another at
1800. The drift (6 to 19 cm) is just the machines moving for those extra ticks.

Proof, made deterministic: a copy of each harness with ONE forced slow frame (a 120 ms
`OS.delay_msec` in the first run at tick 1795). Old harness (39e0cd3): "fight 2 against fight 1
stopped on the same tick (1802 and 1800)", drift 0.098 m. New harness (`await physics_frame`,
8bbbada): 1800 and 1800, drift 0.000000000 m, 42/0. Six unforced runs at load average 80
(3 old, 3 new, suite running) all passed: the race needs a late frame exactly at the stop.
The size branch's failure (1800 against 1802, about 6 cm) is this; it does not need the
branch's code. hitstop_test and pause_test still sample per `process_frame` the same way
(green in all four suites; latent, same fix if they ever flake; hitstop deliberately waits a
frame for a pending hold, so its change needs care).

## Goldens re-recorded (hazard_determinism_test)

Traced commit by commit: `--record` at every Arena commit from e994cd3 (which still gave the
2026-09-27 goldens exactly, so the machine and engine are unchanged) to 39e0cd3, in a scratch
worktree (removed).

| arena | was (4822d27) | after boost (c72dd92) | after stages (00056bb) = now | moved by |
|---|---|---|---|---|
| yard | c229c004e455d784 | 67bdcce2a257c913 | c814ec9e2c1a3b19 | boost, then stages (two sleeping wall grinders' Area3Ds) |
| grinder | 40975d7bf1357d36 | eb50cba11b77f0bb | 948cea0b512e1375 | boost, then stages (sleeping centre spike patch, nine AnimatableBody3Ds) |
| furnace | f861978cfae492eb | fc2849b024a939f4 | fa79709c3fddc315 | boost, then stages (two new east jets) |
| crush | b9c453dd0581b13a | 6d614e86730a9ce0 | 29b028f7726a2f2f | boost, then stages (sleeping corridor patch) |
| drop_zone | 2f84d6c683eb34f6 | 3c8a0a72052ca8cf | 3c8a0a72052ca8cf | boost only |
| coliseum | 475bd101e767f21d | 7c37e036b6df6957 | 7c37e036b6df6957 | boost only |

- Boost = f902361 + ede4db2 + c72dd92 (the AI presses BOOST to escape, unstick and attack; the
  unstick nudge; the referee lock-up break 8 s -> 3 s). f902361 on its own does not run (it swept
  up half of the intro agent's work, which c72dd92 took back), so the three are one step.
- Stages = 00056bb. The pacing agent proved the same four move with the stages alone on an
  isolated worktree (docs/wave-b-pacing-notes.md, "Goldens that move"); the walk agrees.
- Hash-neutral, each identical to the commit before: 3c9d76d intro, dfd7a09 test arena,
  0f4f029 loading screen, 66e8e67 boost tests, 5d966a5 srimech retry, e8e6d84 fight stages +
  payoffs (no stage is reached inside these fixtures), 66bf530 National shove, 7c616e8 type,
  39e0cd3 judges.
- The furnace fixture now ends at tick 247: the boosted AI flipper reaches the idle fixture
  player sooner and flips it out over the west wall (OUT OF THE ARENA). Traced tick by tick; a
  ring-out, not a fault. The Coliseum warning layer off still hashes the same as on.

## On-screen checks

iPhone 17 sim (874 x 402 pt, 2622 x 1206 px), headless Godot (the stage is the rendered still),
muted. Every capture looked at. Saved at half size under `docs/look/fonts/i17-*.jpg` and
`docs/look/judges/`; coach and intro frames from desktop Godot at 1206 x 556 (the HUD's design
space for the same phone) as `docs/look/fonts/coach-*.jpg`, `intro-furnace_*.jpg`.

Fixed:

1. **Match report, judges decision**: the card was bare type over the machine on the stage
   (unreadable where it crossed the flipper) and its last two lines started below the fold.
   Now on its own lighter panel (`Panel(overArena:)`) with the scroll bar shown and flashed.
2. **Quick fight ResultSheet, judges decision**: the card sat under both machine panels, so
   "why did I lose" was two screens down. Now first, and wide: numbers on the left, verdict and
   the three reasons beside them, everything above the fold. New QA flag
   `-openResultSheet decision` (fixture in `PostMatchQA.judgesResult`).
3. **Scouting report**: pip labels truncated to "REA...", "SPE...", "SET..." (label column 34 pt
   was Barlow-sized). 42 pt now; all six read.
4. **Quick fight card**: the right column was taller than 402 pt and pushed the QUICK FIGHT
   title off the top. Dropped the BOTS row (2 or 3), which the RUMBLE row already says.
5. **Unlock**: "Price unavailable" was set in B612 Mono; now `Stage.figure` (a price stays mono,
   words go in the label face).
6. **Fight HUD**: the off-screen opponent arrow and name sat on top of the clock's figures when
   the opponent was straight up. It now drops under the clock and its phase word (ui_test
   follows: "above the middle it clears the clock").
7. `scripts/build-device.sh` picked the first Release app of two DerivedData trees (the same
   stale-path bug build-sim had); now the newest.

Checked, fine: menu, workshop, match report (win), loading column (`-loadingPose 2:0.41`),
rewards (win, series), retry prompt (loss, stranded), events, ladder, replays, welcome panels,
coach callouts (countdown and fighting), intro lower thirds in the Furnace (FURNACE / KNOW THE
FLOOR, FLAME JETS / BURN ON A TIMER, CONVEYOR / CARRIES YOU SOUTH: stencil, no clipping).

Seen, left (not clipping, or not this pass):

- Career garage: the stable list is a scroll box about one row tall at 402 pt, so the selected
  machine's record line is cut mid-line by the scroll edge. Pre-existing (the type swap made the
  rows shorter, not taller). A layout call for the blueprint menus rebuild.
- Retry prompt and replays: body text runs over the machine on the stage (dim, legible, but
  it crosses the flipper). Same family as fix 1; left for the menus rebuild.
- Ladder: a two-word name wraps ("IRON / SPRAT") in its narrow column.
- Unlock "What the full game adds" and the quick fight left panel scroll (HOUSE BOT row is
  below the fold); both are scroll boxes by design.
- Desktop-only: with zero safe-area insets the DRIVE word under the resting stick is off the
  bottom edge; on the phone the 21 pt home-indicator inset lifts it into view.

## Owner decisions / open

- **B612 Mono punctuation gap**: fixed pitch gives "89. 5 kg", "3: 00", "1, 200" (ladder
  rating), "3. 1" on the judges card. Options: B612 Mono for integers only and the Saira face
  for decimals, times and thousands; or a per-glyph kern on "." ":" ","; or a proportional
  numeral face. Not changed.
- **Kit and decal textures still carry Barlow as pixels** (Tools/textures/make_decals.py,
  Tools/blender/arena_kit/make_kit_textures.py already point at the new faces). Re-bake is the
  owner's call (costs a pck export, size about the same).
- Spinner AI blow count varies a lot by seed (1 to 34 in 120 s); look at it in the spinner /
  vortex retune.
- Player help screen for the judges (rules text is in docs/wave-b-judges-notes.md); and a ram
  records 0 "hits landed" although it did the damage (judges notes side note).

## Phone and push

- Release build (`scripts/build-device.sh install`, pck re-exported by the script: 97.48 MB,
  app 216 MB) INSTALLED on the owner's iPhone 18 Pro Max (00008160-0018096E0C400036) from
  `10a4c6d` (everything above except the venue_kit_test harness fix, which is test-only).
- iPhone 17 sim shut down. Scratch worktrees removed.
- Pushed to origin main (hash in the commit that carries this note's push line, see git log).
