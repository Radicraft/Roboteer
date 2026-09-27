# Wave B: pacing, part 1 (escalation and payoffs)

2026-09-27, pacing engineer. Owner feedback: "it's easy to just drive around or get stuck,
without much drama or skill." Of the four fixes the owner picked, this file covers two:
**A. the arena escalates in stages** and **E. big payoffs**. The boost and the anti-stuck
fix are another agent's (`docs/wave-b-*` boost notes). Numbers: `docs/qa/pacing.md`.

## Where I stopped

(kept current at the end of the session; see the bottom of this file)

## A. The round in stages

fight.gd calls `ArenaBase.set_stage(n)` on fixed ticks of a CAREER fight (`rules.mode`
"fight"; never a Rumble, a side event or the test arena), right after the endgame check:

| stage | when (3 min fight) | scales with | what |
|---|---|---|---|
| CALM | 0:00 | | the arena as it always was |
| HAZARDS UP | 0:45 | 0.375 x endgame | every timed hazard cycles 25 % faster, the grinders bite every 20 ticks (was 30) |
| WAKE | 1:30 | 0.75 x endgame | each arena's new danger (below) |
| ENDGAME | 2:00 | `rules.endgame_at_s` | unchanged: house bot out, everything x2, the existing sting |
| FINAL | 0:25 before the bell | duration | the last push; only if it falls 10 s or more after the endgame |

The opener (endgame 1:20, bell 2:00) runs 0:30 / 1:00 / 1:20 / 1:35.

Per arena (each arena's `_on_stage`, `_wake_word`, `_final_word`):

| arena | 0:45 HAZARDS UP | 1:30 WAKE (HUD word) | 2:00 ENDGAME (unchanged) | 0:25 left FINAL |
|---|---|---|---|---|
| Yard | spike cycle 6 -> 4.5 s | two wall grinders wake at (0, +-3.6), the lane a machine circling the patch drives in (GRINDERS WAKE) | patch stays up, grinders bite x2 | FINAL SECONDS |
| Grinder | bite every 20 ticks | a 1.4 m spike patch wakes on the centre cross (SPIKES WAKE) | bite every 15, patch stays up | FINAL SECONDS |
| Drop Zone | pit opens for 20 s (was 15) and comes back 20 s after it shuts (was 45); a closed pit not due for 20 s is brought forward to 20 s | the pit opens after its own 3 s warning and never shuts (PIT STAYS OPEN) | house bot | FINAL SECONDS |
| Furnace | both banks x0.75, belt 1.2 -> 1.5 m/s | a two-jet east bank wakes, 6 s period, first burn 3 s after the stage (SIDE JETS LIT) | every bank 4 s, belt 2.4 | FINAL SECONDS |
| Crush | ram cycles x0.75 | a 1.4 m spike patch wakes in the middle of the safe corridor (SPIKES WAKE) | rams at half the period, patch stays up | rams as fast as a warned stroke allows, 4.4 s (RAMS NONSTOP) |
| Coliseum | spikes 4.5 s, jets x0.75, grinders 20 | floor discs x1.5 (DISCS SPIN UP) | as before (discs x2 on top) | FINAL SECONDS |

The sleeping hazards are built with the arena and visible from the bell (the grinder
wells, the spike bezels, the east nozzles and their painted burn fans), with the
telegraph's dim IDLE outline on them, so the floor says where the wake stage will bite.

### The warning guarantee, kept by construction

- **A new period is taken on the tick a hazard STARTS acting** (the spike rise, the jet
  burn, the ram press): the countdown the telegraph showed ran all the way to this act, and
  the next act is a whole new period away, always longer than the warning. Nothing is ever
  re-timed inside a warning, so no hazard jumps its clock. Cost: "hazards up" takes effect
  over the next cycle (up to one old period, at most 14 s), not on the stage tick.
- **A hazard that wakes** gets a countdown first (the spike patch its own 3.5 s arming,
  jets and grinders `WAKE_LEAD_S` 3 s): `hazard_schedule()` reports `in_s` NEVER while it
  sleeps, then the wake countdown, then the hazard's own clock, continuous. Sleeping entries
  carry `dormant: true`.
- The endgame's immediate re-time (A4, unchanged) drops any hazards-up period still
  waiting, so the two never fight.
- The Crush's FINAL floor is 3.1 s of stroke + the shared warning + slack (4.4 s): the
  ram's clock reads "never" while it retracts, so the idle after the stroke must hold the
  whole warning. The first try (the endgame's 4.1 s floor) gave a 1.0 s warning and the new
  staged check caught it.
- `tests/hazard_warning_test.gd` now also plays every arena through a whole staged round
  (0:45, 1:30, 2:00, 2:35) and checks every activation after the bell had at least the
  shared warning of unbroken countdown, the AI is never told first, and every sleeping
  hazard is live by the bell.

### The AI

The AI reads the arena's `hazard_helpers().danger_positions`, and every new danger joins
that list exactly when its warning starts (the Yard's wall grinders, the Grinder and Crush
patches, the Furnace's east lanes; the Crush's corridor centre leaves `safe_positions` once
its patch is awake, the Furnace's east safe point moves off the east lane). So every tier
avoids the newly live hazards and the tiers that shove line opponents up on them.

One change in `opponent_ai.gd` (`_shoves`): Championship and Masters always shove (brief v4
§4); a tier that already pins (National) now also shoves from the WAKE stage on, read off a
new context key `stage` (fight.gd `_ai_context`). The late fight gets a reason to push, not
only to circle. Scrapyard and Regional never shove.

## E. Big payoffs

### What counts (simulation side, fight.gd "wave B pacing" section)

- **A hazard visit** (arena damage on one machine, hits closer than 1.5 s are one visit)
  pays the machine that was in PHYSICAL contact with the victim (`Bot.touching_bot` either
  way, or a blow it landed) inside `Rules.PAYOFF_CREDIT_S` 1.5 s, and only when:
  - the victim ENTERED: one second before the first hit it was outside the footprint of
    what bit it (a jet lighting up on two machines grinding in its lane, or the spikes
    rising under a clinch, is the arena's doing, not a shove);
  - the shover is not in the same hazard (no payoff for a shared accident);
  - the victim has not yielded a payoff in the last 10 s (`PAYOFF_VICTIM_COOLDOWN_S`).
  Named by what bit: ONTO THE SPIKES, INTO THE GRINDER, INTO THE FIRE, CRUSHED.
- **HAZARD KILL**: a credited visit that takes a part off (or the core). Once per visit.
- **OUT OF THE ARENA / INTO THE PIT**: every ring-out, credited to the last contact inside
  3 s (a throw lands late). The result banner reads INTO THE PIT for the Drop Zone's pit.
- The house bot is NOT a payoff: its damage was already credited to the last toucher
  (brief v4 §3), and it hunts, so the first measure paid "shoves" into it all fight.

### Scoring

The judges score payoffs as CONTROL (you put them there), on top of the hazard's damage,
which the rules already credit to the shover (`TOUCH_CREDIT_S`):

- `Rules.PAYOFF_HAZARD_S` 8 control-seconds a hazard payoff: 3 of the 10 control points
  (`JUDGE_CONTROL_FULL_S` 30). One shove onto a hazard beats twenty seconds of closing in.
- `Rules.PAYOFF_KILL_S` 12 more for a kill (20 in all, 7 points).
- A new tally key `payoff_s` (`Rules.empty_tally`), added into `control` by
  `judge_scores` and `judge_scores_raw`. The result's `judges` shape is unchanged.

### The celebration (presentation side, never feeds back)

From the presentation drain (`_pacing_present`, after the commentary step; skipped while
paused and dropped during a seek or outside the fight view):

- a named slam across the ENDGAME band (`hud.show_stage_sting(name, true)`, scrap amber
  accent for a payoff, danger red for a stage), and the same words on the ticker;
- slow motion through the hit-stop HOLD, 0.9 s of wall clock at 1/3 speed
  (`_hitstop.request_slowmo`); never Engine.time_scale, so the fight is tick for tick the
  one without it; a ring-out keeps the finish beat's own slow follow;
- a camera punch-in (`ImpactShake.punch_zoom` 0.9) and trauma 0.45;
- the crowd roar (`AudioMix.crowd_reaction("ko")`), the venue kit's excitement to full, and
  pyro on a kill, a pit or a ring-out; a heavy haptic.

Stage changes: the slam and the ticker line, a crowd swell (`big_hit`), excitement 0.6, a
light haptic, and on the WAKE stage the endgame's camera pull-back so the player sees the
new floor.

Signals for QA and the shell: `stage_changed(stage, word)`, `payoff(info)`; readers
`stage_ticks()`, `pacing_stage()`, `payoffs()`.

## Determinism and goldens

Stages are a function of the tick; payoffs of physics facts (contacts, damage events) and
the tick. The holds are the existing hit-stop path. Replays re-simulate and stage/pay on the
same ticks.

### Goldens that move (NOT re-recorded, per the brief)

Proven on an isolated worktree (e994cd3 + only my arena/fight/rules changes, no boost):

| test | | moves? (hash with mine alone) | why |
|---|---|---|---|
| hazard_determinism yard | | YES (0df67bc5) | the two sleeping wall grinders' Area3Ds are new nodes in the physics space (no stage is reached in its 900 ticks) |
| hazard_determinism grinder | | YES (63848beb) | the sleeping centre spike patch: nine new AnimatableBody3Ds |
| hazard_determinism crush | | YES (cd33e139) | the sleeping corridor patch, same |
| hazard_determinism furnace | | YES (b50182a6) | two new east jets (areas) |
| hazard_determinism drop_zone, coliseum | | no, with mine alone | nothing new is built; the 3700-tick Drop Zone fixture passes 0:45 but the pit is already due |
| hitstop_test, determinism_test, ai_test, builds_test | | no, with mine alone | all green on the isolated worktree |

On the shared tree all six hazard_determinism goldens fail: the boost agent's f902361
(unstick, lock-up 3 s, replay column) moves drop_zone and coliseum too. The coordinator
re-records once, on the final tree.

## Where I stopped

2026-09-27 evening. Commits (local, not pushed): `00056bb` arena stages, `e8e6d84` fight
stages + payoffs + HUD + pacing_test, `ca438e1` pacing gauntlet + table tool + raw rows,
`66bf530` National shoves from the WAKE stage.

Suite on the shared tree after my commits (`HEADLESS=1 JOBS=2`, 46 files): 5 fail, none mine
(each passes on the isolated worktree with my changes and without the boost work):
rules_test (the replay row is 7 wide now: boost column), ai_test "masters: an inverted bot
drives nowhere" (the AI's boost), builds_test "spinner removes a panel" (12th check, boost
era), boost_test (theirs, in progress), hazard_determinism (goldens, above), and hitstop_test
failed in the shared run ("reference fight has 0 damage events") but passes 20/0 on the
isolated worktree, so it is the boost/unstick change, not the stages or the payoff hold.
Mine: pacing_test 72/0, hazard_warning_test 103/0, arenas_test 155/0, fight_shape 34/0,
commentary 82/0, ui 379/0.

Owed / next:
1. On the phone: does a stage slam every 45 s feel like broadcast or like nagging? The
   dials are `STAGE_*_AT` in fight.gd and `show_stage_sting` in hud.gd. Does the payoff slow
   motion (0.9 s at 1/3) read as a replay moment or as lag? `PAYOFF_SLOWMO_*`.
2. `Rules.is_on_spike_patch` is the centre +-0.8 m in every arena: two machines clinched in
   the middle of any arena both earn control. Should read the arena's own (awake) patch.
3. Judges' `damage` saturates at 10 for both machines in most gauntlet fights
   (JUDGE_DAMAGE_FULL 2.5), so the cards are decided by aggression and control; the payoffs
   now weigh in control. A damage scale review belongs to whoever owns the judges.
4. The hazard_determinism goldens (coordinator).
