# Wave D: commentary with a personality (text only)

Branch `wave-d-commentary`, worktree `/Volumes/RoboteerBuild2/Code/Roboteer-comm`.
Owner decisions: docs/aaa/decisions-2026-09-30.md (text commentary, no voice yet; IP rules per brief v3 §3).

## What it is

- `Arena/fight/commentary_lines.json`: 419 original lines over 49 keys. Each key has a priority `p`
  (0 filler .. 3 payoff/result), a cooldown `cool` (optionally `per` victim/attacker), a `life`
  (how long it may wait for the ticker), an optional `group` (one line per fight across the group:
  `result` = knockout / core_destroyed / count_out, `verdict` = verdict_clear / verdict_close,
  `bell` = judges), a `doc` saying what the facts mean, and `lines`: a plain string, or
  `{t, if, w}` with guards (`flag`, `!flag`, `key=value`, `!key=value`) and a weight (default 10).
  A `{placeholder}` needs that fact; a line whose facts are not all true never fires.
- `Arena/fight/commentary.gd` (`FightCommentary`): the API for every agent:
  `call_event(key, ctx) -> String` (ctx: attacker, victim, house_bot, part, arena, weapon, seconds,
  margin + flags; aliases winner/loser/machine/name), `line_for(key, ctx)` (a line without saying it,
  for a card), `prediction_context()`. From fight.gd also: `setup(info)`, `note_damage`, `note_pin`,
  `note_zone`, `note_house_bot_out(idle)`, `note_stage`, `note_payoff`, `note_result`, `step(delta, facts)`.
  fight.gd exposes `commentary_event(key, ctx)` and `commentary()` for other nodes.
- Detected here from real fight state: prediction (countdown start, from armour / records / weapon
  matchup), fight_start, first_blood, big_hit (FX heavy severity, weapon-kind and house-bot variants,
  name puns for the 8 rivals, 5 house bots and Tinribs), part_off (real armour plate / wheel / track
  names only), pinned (held 0.6 s), flipped (held 0.3 s; credited only with contact inside 1.5 s,
  else "self"), self_right, spinning_up (spinners, drums, full body spinners, saws only: the old
  line fired on flamethrowers), spin_lost, weapon_jammed / weapon_cooked (any machine; replaces the
  player-only "WEAPON DEAD" push), in_the_zone, house_bot_out (endgame vs idle entrance), pit_open /
  endgame, stage_hazards / stage_wake / stage_final (per-arena words), last_ten, comeback (20 %
  condition deficit drawn level), stall (8 s no contact and no blow), hazard_self (arena damage, nobody
  in contact for 3 s), stuck (the unstick nudge), wedge_under, lockup_tow (the lock-up break), all
  payoffs (credited vs self for pit / ring-out), knockout, core_destroyed (self-cooked / hazard),
  judges + verdict_clear / verdict_close (margin <= 2 of 10 points is close).
- Keys other agents call (all answer): fight_start, fight_stop, count_start, count_out, lockup_tow,
  fire_out, marshal_wobble, house_finish, house_late_hit, house_card, verdict_clear, verdict_close,
  walkout_player, walkout_opponent, prediction. Duplicates are harmless: groups and cooldowns dedupe
  (e.g. my knockout and the Marshal's count_out say one line; my lockup_tow and the Marshal's too).
- Pacing (in commentary.gd, not the HUD): one line on screen + one waiting; min 2 s between line
  starts; hold 1.8 to 3.2 s by length; a bigger moment (p +2, or a payoff/result over anything less)
  replaces a line that has been up 0.8 s; a waiting line past its `life`, or no longer true (a flip
  about a machine back on its wheels), is dropped; 7 s of quiet is silence, 8 s draws a jibe.
- HUD: `say_commentary(text, hold, in_countdown)` shows a line at once in the case given; the wave G
  queue (`push_commentary`, capitals) is kept for anyone else. `commentary_fit(text)` for the width test.
  Sentence case is the default (`FightCommentary.SENTENCE_CASE`); the prediction is allowed over the
  countdown (ticker at the foot, count in the middle): my call, easy to revert.
- Presentation only: its own 32-bit xorshift seeded (mixed) from the fight seed; no global random, no
  RandomNumberGenerator, no wall clock. `debug.commentary: "off"` (test only) builds no commentary.

## Grudge bugs (Swift)

(a) `{player}` was the rival's own roboteer name: now `CareerEngine.playerName()` = the Game Center
alias when signed in (written by GameCenterService), else "your team", with sentence-start capitals.
Both the Series card and ScoutingView go through `RivalRecord.grudgeLine(botName:playerName:)`.
(b) Clatterbox and Penny Dread lines 1/2 swapped in Shared/parts.json and Arena/data/parts.json;
Clatterbox's "you beat them" line said "You put {bot} on its back" (the player's own machine): now
"You put Clatterbox on its back"; its line 0 said "got lucky last time" on a first meeting: now
"has been lucky so far". (c) the card now shows line 0 before the two have met (`hasMet` guard gone).
Self test: `checkGrudgeWords` (every rival: line 1 never opens on the player, line 2 always does;
every line at its point in history names the player not the roboteer; Clatterbox/Penny explicit;
first meeting on the card; "your team" default + capital).

## Tests

- `Arena/tests/commentary_test.gd`: 243 checks (lines, guards for every guarded line, variety,
  weighting, triggers, detections, pacing, width at 2622 x 1206 px with 186/186/63 insets in both
  cases with 18-char names, HUD, endgame audio, discipline, and a real fight traced every second with
  and without the commentary: identical).
- determinism_test and hazard_determinism_test: six goldens unchanged.
- QA: `Arena/qa/commentary_transcript.gd` (headless fights + fight log), `Arena/qa/commentary_capture.gd`
  (windowed ticker captures).

## Where I stopped

- Committed the engine, lines, HUD, fight wiring, tests, Swift fixes (see git log).
- build-sim green on the pre-merge tree. NEXT: merge main 7cfa64b, full suite, build-sim + career self
  test on one sim, ticker captures, docs/look/commentary.html with 3 transcripts.
