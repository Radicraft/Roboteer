# Wave D: walk-outs and the tale of the tape

Owner decision 2026-09-30 (docs/aaa/decisions-2026-09-30.md, item 1): walk-outs through the venue gate
with a tale-of-the-tape card; stats plus a strength and a weakness line the player writes in the builder;
rivals get written ones. Review page: `docs/look/walkouts.html` (assets in `docs/look/walkouts/`).

## Where I stopped

- Branch `wave-d-walkout` (worktree /Volumes/RoboteerBuild2/Code/Roboteer-walkout), main 7cfa64b
  (fitment) merged in. Not pushed, not merged to main. The working-tree arena.pck is NOT committed.
- Done: Godot walk-outs + card + house card, Swift tape + builder sheet, bridge spec, rival and house bot
  lines, walkout_test (88/0 after the merge), intro_test unchanged, build-sim green, career self test
  1035/0 (2 warnings, as before) on a dedicated simulator (deleted after), captures in the Yard, Grinder,
  Coliseum (clips), Crush and Furnace (stills), the card at 874 and 956, the builder link and sheet.
- Full suite: see "Tests" below.
- Owner calls owed: house bot shot on every first-visit career intro (+1.3 s)? quick fights walk out at
  all? The staging call below.

## What it does

- Before the hazard fly-past, the opponent then the player each roll out of their corner under their venue
  gate: `VenueKit.play_entrance(team)` (floods to 25 %, gate strip chases, pyro at 1.0 s; a short walk-out
  fires the gate pyro itself at 22 %), a follow spot (SpotLight3D, presentation only) picks the machine out,
  the camera is low on the arena side pushing in, aimed right of the machine so it stands in the left of the
  frame. The machine rolls (ease-out) onto its fight mark and rocks to a stop. The card slides in from the
  right.
- Full career intro with a zone house bot: a 1.3 s shot of the house bot in its corner with its card.
- Mid-fight, when the house bot comes out of its corner (endgame release or the idle entrance), its small
  card (name, strength, weakness) slides in top left under the player's name plate for 3.5 s.
- Skippable with the intro's own skip (any tap/button/key): straight to the drop, every machine shown,
  card cleared, entrance stopped.

### Staging call (mine)

The brief says "rolls out of the venue gate". The gates stand 2.2 m outside the arena corners. I first
drove the ghost out of the gate onto the apron: every camera there was blocked by the Yard's fence and the
crowd, or black (no floor light outside the walls), and the gate itself never read. The shipped version
starts the machine in the arena corner under its gate (the lit portal, its MACHINES IN sign and its pyro
behind it over the wall) and rolls it onto its mark, so the hand-over to the real machine is exact.

## Timings (added before the unchanged fly-past)

| | intro full | intro short |
|---|---|---|
| career (`tape.style` career) | 2.2 + 2.2 (+ 1.3 house) = 4.4 / 5.7 s | 1.0 + 1.0 = 2.0 s |
| quick fight, ladder (`quick`) | 1.4 + 1.4 = 2.8 s | 0.8 + 0.8 = 1.6 s |

None for: intro none (quick restart, test arena), replays, events, rumbles (bot count != 2), and any
config without `tape`. Constants at the top of `Arena/fight/fight_intro.gd` (WALK_*, HOUSE_SHOT_S).

## Hash proof

`Arena/tests/walkout_test.gd` (88 checks) fights the fixture with a rival and THRESHER as zone house bot,
hashing every 30th arena tick to 480 (arena and fight ticks, state, both chassis transforms bit exact,
condition, hazard read and schedule):

| arena | none | full career | short career | quick full | skipped halfway |
|---|---|---|---|---|---|
| yard | 9850b37b54ae4226 | same | same | same | |
| coliseum | 9e80cace22beee10 | same | same | | same (1x, tap at 0.5 s) |
| crush | 44d3f4a4c5d0358c | same | same | | |

Also checked: the walk-out order and seconds per mode/style, the real machines hidden while they wait
(26 meshes) and put back exactly (visibility and transform per mesh path vs the no-intro run), both on
their marks, no ghost/spot/card left, entrance stopped, fight camera current, each walk-out's own card up,
commentary got walkout_opponent / walkout_player / prediction with the right machines, the written lines
(13 of them, <= 60 chars, no em dash or exclamation mark, all different), the default lines, trimming and
capping, the shell's words winning, the house card mid-fight, no walk-outs in a replay, and the longest
card fitting 874 x 402 and 956 x 440 (x3 px) inside the safe area with every line on two rows at most.

## Files

- `Arena/fight/fight_intro.gd`: section "walk-outs (wave D)" at the end + small hunks (constants,
  `set_walkouts`, `walk_seconds`, `_start_shot` / `skip` / `finish` / `step`). The kit is built early
  (`_build`, idempotent) when walk-outs are planned: it builds call_deferred and the intro starts in the
  same frame, so the gates were not there yet.
- `Arena/fight/tape_cards.gd` (TapeCards): the card data, merging `fight_config.tape` over defaults made
  from the bot config and parts.json (rival found by machine name, `bosses` for the house bot).
- `Arena/ui/tape_card.gd` (TapeCardOverlay): the blueprint plate (#0E3A8C at 92 %, 10 pt graph paper),
  Saira Stencil name, Saira labels and numbers (not B612 Mono: the "." gap), no strokes or skew.
- `Arena/fight/fight.gd`: section "wave D: walk-outs" at the end; one-line hooks in `_begin_intro`,
  `_end_intro`, `_on_intro_beat`, `_release_house_bot`, the idle entrance. `_favourite()` (for the
  prediction) reads the catalogue only, never the fight RNG.
- `Arena/qa/walkout_capture.gd`: captures (`--walk-shots`, `--walk-sequence`, `--walk-house`,
  `--walk-house-card`, `--walk-safe`, `--walk-overview` debug top-down). Clips: run it with
  `--fixed-fps 15 --write-movie DIR/f.png`, then PIL to animated WebP (no ffmpeg on this Mac).
- `Shared/parts.json` (+ Arena copy): `strength` / `weakness` after each rival's `personality` and each
  boss's `blurb`.
- Swift: `Roboteer/TaleOfTheTape.swift` (cards, default lines, head to head, `forCareer`,
  `forQuickFight`), `Roboteer/TapeLinesSheet.swift`, `BotBuild.strengthLine` / `.weaknessLine`
  (optional, lightweight migration), `ArenaHost.tapeNextFight` + `injecting(key:value:into:)` (cleared by
  events and replays), `CareerFightView.start` and `FightView.start` arm it, `-builderTape` QA flag,
  `CareerSelfTest.checkTaleOfTheTape` (8 checks).
- `docs/bridge-spec.md` "fight_config.tape"; `docs/qa-launch-flags.md` `-builderTape`.

## Integration notes

- **wave-c-menus (builder rebuild):** my BuilderView change is three small hunks: `@State showsTape`, a
  `TextLink("Tale of the tape")` in `header` after the name field, and `.sheet(isPresented: $showsTape)
  { TapeLinesSheet(build: build) }` on the body. On their builder, put the same link wherever the name
  field lives. `TapeLinesSheet` uses main's Stage tokens; restyle to Blueprint if wanted, it is standalone.
- **wave-d-commentary:** I call `_commentary.call_event(key, ctx)` guarded by `has_method` for
  `walkout_opponent`, `walkout_player` (ctx attacker = the machine walking out, victim = the other, arena,
  roboteer, strength, weakness) and `prediction` (attacker = the favourite, victim, arena, favourite =
  "player"/"opponent"). The HUD is hidden during the intro, so lines fired then must queue or show later.
  commentary.gd not edited.
- **wave-d-marshal:** `_release_house_bot` and the idle entrance each got one line
  (`_tape_house_bot_out()`) next to `_commentary_house_bot_out()`; trivial conflict if they edit there.
- `intro_beat` gains `walkout` and `walkouts_done`.
- The career self test and build were done before the fitment merge; the merge touched no Swift.

## Tests

- walkout_test 88/0 (after merging main 7cfa64b); intro_test yard+crush 35/0 before the merge.
- Full suite: PENDING at the time of writing (HEADLESS=1 JOBS=2, two Godot processes per the Mac rule).
