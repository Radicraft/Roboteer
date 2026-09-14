# Stage 4 rules notes (agent R2)

What changed in the fight orchestrator, the AI and the tests for Stage 4. Companion to
`docs/stage3-rules-notes.md`, which is still the authority for everything Stage 3 settled
and which nothing here undoes. Spec: `docs/stage4-spec.md` §6, with §5 for the stage API
and `docs/stage4-swift-notes.md` for the messages.

Files owned: `Arena/fight/**`, `Arena/ai/**`, `Arena/arena/test_arena.tscn`,
`Arena/tests/{rules,ai,determinism,builds}_test.gd`, `scripts/test-arena.sh`, the
non-rendering keys of `Arena/project.godot`, this file and
`docs/stage4-rumble-decision.md`.

## One process, three views

The shell now keeps ONE `GodotAppView` alive from launch (`docs/stage4-swift-notes.md`),
so the arena is whatever message it was last sent, for the life of the app.

| message | what the arena does |
|---|---|
| `fight_config` | stage off, camera `set_mode("fight")`, HUD and controls back, build the fight (a fresh `World3D`, as Stage 3) |
| `workshop_config` | tear the fight down, stage on, camera `set_mode("workshop")`, HUD and controls hidden |
| `workshop_config` with `"mode": "menu"` | the same, with camera `set_mode("menu")` |
| `test_reset` | rebuild both machines from the configuration the fight started with |

`workshop_config` is accepted in **every** state. In LOADING or RESULT it simply puts the
stage up. Arriving during COUNTDOWN or FIGHTING it means the player walked out of the
fight: the arena sends `fight_state {"state":"abandoned"}`, sends **no** `fight_result`,
and drops back to LOADING. A fight nobody watched has no result worth recording, and a
half fight written into the machine's record would be worse than no record.

`fight_config` mid fight is still refused (Stage 3's duplicate send rule, unchanged).

**`workshop_ready` is sent by the stage, not by `fight.gd`.** `WorkshopStage` subscribes to
the same `workshop_config` message and answers it with its own `build_summary()`, so
`fight.gd` only does the mode switch. Two consequences worth knowing:

- The stage is instantiated in `_ready`, **before** the bridge is connected. Created
  lazily inside the handler it would miss the very first `workshop_config` and the shell
  would wait forever for an answer. `rules_test` asserts exactly one `workshop_ready` per
  `workshop_config`.
- The stage outlives every fight world. It is instantiated once and **reparented** into
  each new `SubViewport` as `_build_world` replaces it, so it always lives in the world
  the camera is in.

Tearing the fight down frees the bots, the debris **and the arena**. Leaving the Yard in
place would leave its `WorldEnvironment` and its key light burning behind the workshop
stage, which is the one thing C2's notes ask not to happen.

## Test mode

`rules.mode == "test"` (the shell sends `{"mode": "test", "ko_count_s": 10}` with no
`duration_s` at all, which is fine because nothing in test mode reads the clock).

- **Nothing can be won or lost.** No timer, no judges, no knockout count, no out of arena
  loss. Component kill is disabled too, which the spec does not list: a result sheet
  appearing in the middle of testing a build would end the session the player is in the
  middle of, and the test arena is a sandbox (brief §10). The player leaves from the
  shell, which sends `workshop_config`. Nothing sends `fight_result` in test mode.
- **A bot that leaves is put back**, on its mark, two seconds later, in whatever condition
  it left in. Two seconds so the player sees where it went.
- **`controller: "dummy"` gets no driver.** The shell sends `debug.opponent_ai` on every
  configuration and it defaults to `"normal"`, so `"normal"` cannot be told apart from the
  default and the controller has to win. An explicit `charge` or `idle` still overrides,
  which is what spec §6's "debug.opponent_ai may still make it fight" is for:
  `-opponentAI charge` wakes the crash test bot up.
- **`test_reset` rebuilds rather than repairs.** Both machines are re-assembled from the
  configuration the fight started with, not patched in place, because that is the only way
  to be sure nothing carries over: a bent joint, a detached panel in the debris, a spent
  gas bottle. The debris is cleared and the tallies are zeroed with them.
- `Arena/ui/test_overlay.gd` is instantiated in test mode only, bound to the bots and the
  fight camera, re-bound after every reset, fed every `damage_event`, and its
  `reset_requested` signal is wired to the same `test_reset`.

### `Arena/arena/test_arena.tscn`

The Yard with the spike hazard taken out and a wall mounted target pad. The script is
`Arena/fight/test_arena.gd` (`class_name TestArena extends Yard`) because R2 owns that
directory and the scene file, but not `Arena/arena/yard.gd`.

It subclasses the Yard rather than copying it, so the floor, the walls, the chevrons, the
out of arena sensor and the spawn markers are the ones a real fight uses. A build that
behaves a certain way in the test arena has to behave the same way in a fight or the test
arena is lying. `seconds_to_spike_rise()` returns 999 and `_physics_process` is dropped
entirely, so the AI's spike avoidance is a no-op in there and no hidden bodies are ticked.
The pad is static and indestructible on purpose: an impulse read off it is the build's,
not a shared guess about how much the target gave way.

## The AI is per weapon now

Everything the AI does differently per weapon lives in `OpponentAI.PROFILES`, one row per
`WeaponBase.kind`, and nowhere else, so a new weapon is a row rather than a branch.

| field | meaning |
|---|---|
| `standoff` | the ring it holds while it looks for an angle, metres. 0 means it has no ring (a ram charges; a flame computes one from its own reach) |
| `engage` | fire range as a multiple of the weapon's own `reach()`, plus 0.65 m. 0 means it has nothing to fire |
| `flank` | needs a side or rear angle before committing, or charges straight in |
| `spin_up` | will not commit below 0.85 readiness and disengages to re-spin below 0.45 |
| `hold` | the weapon is held on (saw, flame, spinners) rather than tapped, so there is no tap cooldown |
| `latch` | stays in the clinch instead of giving ground after a hit |
| `orbit` | circles at the standoff while engaged instead of closing |

Which gives, per spec §6: spinners and the drum spin up before engaging and back off to
re-spin; flipper, lifter and drum work the flanks; the axe engages at 0.7 of its reach, so
it is on top before it swings; saw and crusher latch and stay; the ram has no ring and no
trigger and simply charges; the flame holds its own reach and sweeps; the full body spinner
orbits. The kind, the reach and the readiness are read off the Bot through `has_method` /
`get` with the Stage 3 flipper as the fallback (`weapon_kind()`, `weapon_reach()` / `reach()`,
`weapon_readiness()`, then the `weapon` object's `kind` / `reach()` / `readiness()`), so the
AI works against P2's Bot before and after `weapon_readiness()` lands, and against W1's and
W2's weapons before and after they do.

### The nose is +X, and it always was

**Measured 2026-09-13, and this was a real bug.** `Bot._drive` steers by
`chassis.global_basis.x` and `Bot.place_at` yaws to match, so a bot's nose is **+X**. The
AI was computing forward as `-basis.z`, Godot's usual convention, which is ninety degrees
out. The Stage 3 tests did not catch it because `FakeBot.place` used `looking_at`, so the
fakes had a -Z nose and agreed with the bug.

`FakeBot.place` now uses the same yaw as `Bot.place_at`, so the tests exercise the real
convention. On the feel probe the fix roughly doubled the damage in a 45 second AI against
AI fight (36 events to 75) and moved the bots from grinding nose to nose to fighting at
range: ticks within 1 m fell from 1193 to 108 and minimum separation rose from 0.18 m to
0.85 m, because the AI now actually points its wedge where it thinks it does.

## Tests

    scripts/test-arena.sh

| test | checks | notes |
|---|---|---|
| `rules_test.gd` | 148 | the four win conditions, the judges' maths, the result shape, the duplicate send rule, and the Stage 4 mode switch and test mode driven through the real `Bridge.inject_from_host` seam |
| `ai_test.gd` | 52 | approach, strike, recover, spike avoidance, AI against AI determinism, and one case per weapon profile against a fake that reports a kind, a reach and a readiness |
| `determinism_test.gd` | 28 | unchanged: three fights on one Fight node, re-armed between them |
| `builds_test.gd` | SKIP | the three builds proof. SKIPs until `res://bot/weapons/horizontal_spinner.gd` and `ram.gd` exist |

`builds_test.gd` is written in full behind the skip, so it runs the moment W1 and W2 land:
three AI driven builds against the same opponent (box, 4wd, saw, all steel) from the same
seed, asserting that the spinner takes a panel off, the flipper throws the opponent above
0.4 m at least twice, the ram pushes furthest and damages least, every build is inside
100 kg and passes `BuildRules`, and the three fights are not the same fight. It costs about
three minutes of wall clock, because 60 simulated seconds cost 60 real ones.

`Arena/tests/_rumble_probe.gd` is a measurement, not a test, and the runner skips it along
with every other underscore file. See `docs/stage4-rumble-decision.md`.

## Two follow-ups after the first desktop run

### The HUD was showing a knockout count that was not counting

A clinch made the HUD flash "TINRIBS KNOCKOUT COUNT 10" the instant the bots met. Both
halves of the count were working: `is_immobile()` goes true after half a second below
0.15 m/s, so the count starts, and the pin rule then freezes it at whatever it reached.
What was wrong was the display, which showed the frozen number as though it were running.

`FightRules.should_show_ko_count(count_s, advancing)` is now the whole rule, and
`Fight.ko_count_display()` is the whole of what the HUD is told:

- **frozen means hidden.** A pinned bot is not being counted out, so nothing is shown,
  however far the count had got before the clinch.
- **under one second means hidden.** Anything below `KO_SHOW_MIN_S` is the half second
  immobility window plus noise, and showing it flickers the banner on every hard shove.

`_ko_advancing` is written in the physics tick next to the count itself, so the readout
cannot drift from the rule. Both are covered in `rules_test.gd`, as pure functions and
again through `ko_count_display()` on a real Fight node.

### The AI was standing off instead of fighting

P2 measured 202 ticks of 2900 inside 1 m with `--pai=normal`. The cause was the flank gate
being treated as a requirement: the bot holds its ring until the approach angle is more
than 50 degrees off the opponent's facing, and against an opponent that keeps its nose on
you (a faster bot, or another AI doing exactly the same thing) that angle may never come.
A bot that waits forever for a perfect entry never fights.

Two changes, both in `opponent_ai.gd`:

- The flipper's ring comes in from 1.4 m to **1.15 m** and the lifter's from 1.2 to 1.05.
  Both are contact weapons; a ring wider than the bots are long turns backing off into
  standing off.
- `COMMIT_AFTER_TICKS` (120, two seconds): after two seconds of circling the bot goes in
  regardless of the angle. Spinning up is still not negotiable, because a cold bar is a
  handle rather than a weapon. The timer resets on every dart, every approach from
  outside the ring and every backoff, so it measures circling and nothing else.

`ai_test.gd` pins the behaviour rather than the numbers: a flipper bot held at a bad angle
must be driving in within about two seconds, and a flipper bot given an open flank must
commit on the first tick rather than waiting the timer out.

The feel probe moved from 202 to 282 ticks inside 1 m on the run after the change, but
that probe is a chaotic 45 second simulation against a `bot.gd` that agent P2 is rewriting
underneath it, and single runs of it swing widely (75 damage events on one run, 22 on the
next, with no AI change between them). It is a smell test, not a measurement. The
deterministic re-engagement checks in `ai_test.gd` are what this behaviour is held to.

## Stage 5 groundwork landed early

### The bosses (`Arena/ai/boss_ai.gd`)

`BossAI extends OpponentAI`. Each boss is a personality laid over the ordinary weapon
driver, not a replacement for it: the base class already knows how to recover from being
inverted, dodge the spikes, hold a ring, find a flank and work a weapon of a given kind,
and a subclass cannot silently lose any of that. It also means the rng is drawn on exactly
the same fixed cadence as any other driver, so a career fight with a boss in it replays.

| boss | build | the one rule that makes it recognisable |
|---|---|---|
| THRESHER | long_low / 6wd / crusher | never chases: past a 3.2 m leash it walks back to its gate, and it is throttled to 0.62 even when it does move |
| GRUDGE | box / tracks / flamethrower | holds its own reach and sweeps; below 20 % fuel it stops burning and backs away rather than being caught dry at contact range |
| BANDSAW | wedge / 2wd / saw | aims past the target at the nearest wall, shoving it along; once the target is within 0.9 m of a wall it holds it there cutting |
| ANVIL | tall_tank / 4wd / axe | never shows its back: facing comes before everything, and it waits rather than chasing past 2.2 m |
| CINDER | box / 6wd / flipper + scoop | works round to the far side of the target from the nearest hazard, so the throw sends them at it |

Builds come from the catalogue's `bosses` key when agent S3 lands it (`build_for()` is the
one place either source is read) and from `FALLBACK_BUILDS` until then. The chassis, drive
and weapon of each are `docs/stage5-spec.md` §4 exactly.

**All five are inside the 100 kg builder budget**, measured with `BuildRules.total_weight`.
The first draft was not: THRESHER came out 35.9 kg over and ANVIL 47.2. A boss is not an
entrant (brief §8) and arguably should not be held to the entrants' budget, but an over
budget boss logs a validation error on every assembly and reads as an accident rather than
a decision. The weight went into the machine instead of the plate, which is the trade these
five are meant to embody anyway: THRESHER is a chassis and a crusher with almost nothing on
it, and ANVIL puts what it has on the front, where its whole character is, and is
deliberately soft on the sides and the back.

`hazard_helpers()` is read off the arena when it has one and passed to the boss as
`ctx.hazards`; the spike patch centre is the fallback, so CINDER works in the Yard today.

### The inactivity enforcer

`rules.enforcer: "cinder"` in a `mode: "fight"` config arms it. Fifteen seconds with the
two machines never inside 1.2 m of each other and the named boss comes in from its gate,
attacks whoever is nearest, and withdraws once they have been fighting again for three
seconds; at the gate it leaves the floor.

The gate is the corner of the arena opposite both spawns. The Stage 3 spawns sit on the
-X-Z to +X+Z diagonal, so the other diagonal is clear and its +X-Z end is 7.6 m from each
of them: far enough that the entrance is an entrance and not an ambush.

**It is deliberately not a third competitor.** It is not in `_bot_ids`, so `_index_of`
returns -1 for it and no tally, no scrap and no win condition ever sees it. A fight the
arena ended would be a fight the arena won. It is the third body the Rumble measurement
priced (`docs/stage4-rumble-decision.md`), so it stays inside brief §12's cap.

### Rumble is NOT done

`rules.mode == "rumble"` with three scored bots is not implemented, and it was asked for in
the same message as the bosses. It is not a small change and it should not be pretended to
be: `_bots`, `_bot_ids`, `_tallies`, `_scrap`, `_ko_count`, `_last_touch_by`,
`_last_heading`, `_replace_at` and every one of the four win conditions are pairs, and the
judges' card is scored against *the* opponent, singular. `docs/stage4-rumble-decision.md`
lists what would have to change and why the physics is the easy half. The enforcer above is
the three-bodies-on-the-floor case working today, without touching any of it.

## The settings message

`settings` arrives after `arena_ready` and again on every change
(`docs/stage4-swift-notes.md`). `Fight.apply_settings()` routes it and owns nothing:

| key | goes to |
|---|---|
| `scheme` | `FightControls.set_scheme` |
| `director_cut` | `CameraRig.set_director_cut` |
| `haptics` | `FightFx.set_haptics_enabled` |
| `controller_connected`, `controller_kind` | `FightHud.set_controller_hints` |
| `volume` | `AudioServer` master bus |

Three things worth knowing:

- **It is merged, not replaced.** The shell sends the whole struct today, but a partial
  update is a reasonable thing for it to start doing, and one that silently cleared every
  other setting would be a bug nobody would look for.
- **The last settings are kept and re-applied after every `_build_world`.** A fight builds
  a new world, which means a new `CameraRig` and a new `FightFx`; without this the player's
  choices quietly revert on the second fight.
- **A volume of zero mutes the bus rather than setting its gain.** `linear_to_db(0)` is
  minus infinity, which some audio drivers take badly.

Unknown keys are ignored silently rather than logged, because the shell is allowed to grow
the message without the arena being updated first. Presentation only: none of it reaches
the simulation, so a replay is unaffected by what the player has turned on. Covered in
`rules_test.gd` with fakes for the four target nodes, so it tests the routing rather than
three other agents' implementations.

## Stage 5 and 6 fight-side work

### Six arenas

`config.arena` selects from `ARENA_SCENES` (yard, grinder, drop_zone, furnace, crush,
coliseum), falling back to the Yard with an `arena_log` warn. Career tier to arena id is
Swift's mapping; this file only reads the id it is handed. The camera fits
`_arena_size()` rather than the constant, because the Coliseum is 12 m across and the
constant framed it 20 % too tight.

**One of agent A5's five edits was a bug, not a feature.** `Rules.is_out_of_arena()`
hardcoded `FightTypes.ARENA_SIZE * 0.5`, so a Coliseum bot standing at x = 5.5, comfortably
inside its own walls, was declared out of the arena and lost the fight. It now takes the
arena's half extent, with the old constant as the default so every existing caller and test
stays correct.

The AI context carries `hazard` (the arena's whole `hazard_helpers()` dictionary) and
`hazards` (its `danger_positions`), which is the key `boss_ai.gd` already reads, so CINDER
throws people at the nastiest thing in any of the six. `hazard_fx` is connected to
`FightFx.on_arena_hazard` with one line that covers all six arenas.

### Replays

`config.replay.inputs` starts a replay. **A replay is not a recording: it is the same
fight, re-simulated** from the same seed and the same input log, in a world built the way
every fight's world is built. That is only possible because of the two things earlier
stages settled (a fresh `World3D` per fight, and every driver drawing from the shared rng
on a fixed cadence), and it is why the log carries only the player's record: the opponent
is regenerated, not stored.

The whole of the difference from an ordinary fight is reporting. `replay_state
{tick, total}` goes out every 10 ticks and `{tick, total, finished: true}` at the end;
**no `fight_result` is sent**, because the fight being replayed already produced one and a
second would be written into the machine's record as a second fight.

`replay_control {action, value}`: play, pause, speed (0.25 / 0.5 / 1 only, snapped to the
nearest), restart, seek. **Speed never changes the physics tick rate**, only the rate the
engine is asked for steps, so slow motion is the same fight and not a different one.

**Seek re-simulates, because there is nothing else to seek**: the fight only exists as the
sum of its ticks. It rebuilds the world and runs forward with the SubViewport's
`render_target_update_mode` disabled, at `time_scale` 24 and 32 steps a frame, which is
roughly 1400 ticks a second: about four seconds to reach the end of a 90 second fight, and
under half a second to go ten seconds in. Linear in the distance sought, and it always
starts from tick 0, so seeking backwards costs exactly what seeking forwards does. A phone
will be slower. If that ever matters the answer is keyframes, not a faster loop.

`determinism_test.gd` now runs a fourth pass through the replay path, handing the log back
as `config.replay.inputs` the way the shell does, and asserts it lands on the same tick with
the same transforms, conditions, scrap and damage events as the fight it replays. It does,
to the bit.

### Rumble

`rules.mode == "rumble"` with three machines. Every per bot array is sized from
`_bot_count` and every rule loops to it; `_fill(value, n)` of length 2 is the same array the
literals used to be, so **the two bot path is byte for byte what it was** and
`determinism_test` is the guard on that claim.

- A machine knocked out, destroyed or thrown out is **eliminated**, not victorious over:
  it freezes, the others carry on, and the last one still moving wins.
- `FightResult` gains `eliminated`, the ids oldest first. Always present, empty in an
  ordinary fight, because a key that only sometimes exists is a key Swift has to guess at.
- At time-out the judges score every machine still in the fight on its own card, best card
  wins, same tiebreaks. An eliminated machine cannot win on points, which is the whole
  reason to survive.
- "The opponent" is now "the nearest machine still in the fight" (`_foe_index`). With two
  bots that is always the other one, which is exactly what `1 - i` meant.
- The extra machines each get **their own RandomNumberGenerator**, seeded `seed + i * 7919`,
  rather than drawing from the shared one. Two reasons: sharing would interleave draws with
  the first two drivers and change every two bot fight replayed at three; and three drivers
  on one stream behave identically to each other in the same situation, which looks
  scripted, which is the thing the jitter exists to prevent.
- The third machine spawns on the corner the two bot diagonal leaves free, and everyone
  faces the middle. The arenas only carry two marks and answer the second one for anything
  past it, so `_spawn_origin` only trusts the arena for a mark it actually has.

### Side events

`rules.mode` in sumo, gauntlet, pinball, football or wall_smash loads
`res://fight/events/<mode>.gd` and hands it the fight. The event owns the clock and the win
condition; `fight.gd` still owns the state machine, the countdown, the tick order, the
replay log, the rng, the camera and the HUD. The ordinary four win conditions are skipped
while one is running, because they would end a Sumo the moment somebody was pushed out,
which is the opposite of the point. It sends `event_result {mode, score, cleared, time_s,
details}` rather than `fight_result`: an event has no winner, no loser and no judges' card,
and a result sheet built for a fight would have to invent all three.

`Arena/fight/events/event_rules.gd` is the base, with exactly the API agent E6 codes
against: `setup(fight, config)`, `physics_tick(dt)`, `is_over()`, `result()`,
`arena_scene_path()`, `hud_lines()`. An event whose file has not landed yet warns and runs
as an ordinary fight rather than failing to start. `fight.gd` exposes a deliberately small
public seam for events (`bots()`, `arena()`, `fight_time()`, `rng()`, `bot_id(i)`): an event
that needs more than that is probably a rule, not an event.

### Two small ones

- `workshop_config` with `"mode": "scout"` is the workshop camera with the turntable
  turning, for reading a machine you cannot touch (agent S3).
- The catalogue names boss personalities by what they do (`pin`, `disable`, `herd`, `wall`,
  `thrower`), so `BossAI.resolve()` takes either spelling and an unrecognised one drives
  normally rather than failing.

## One risk handed to agent P2 rather than fixed

`Arena/bot/bot.gd` sets `max_contacts_reported = 6` on each part body. That is a **cap**,
and when a body has more contacts in a step than the cap, the engine reports an arbitrary
subset. Which subset depends on internal body ordering, which depends on physics RIDs,
which are recycled between fights in one process. That is the same shape as the Jolt
contact pair cache bug recorded in `docs/stage3-rules-notes.md`, and it has the same
symptom: the first fight in a process sees a different set of contacts from every later
one.

It was observed once, on a mid-edit version of `bot.gd` during P2's rewrite: the same
scripted fight produced 30 damage events on fight 1 and 29 on fights 2 and 3, with every
chassis transform still bit identical, because the lost hit was armour damage and armour
damage moves nothing. It is **not** reproducible against the current file, and the
determinism test is green.

Not fixed here on purpose: `bot.gd` is P2's and was being rewritten while this was
measured, so editing it would have been a conflict with no evidence to justify it. The
suggested change, if it comes back, is to raise the cap rather than lower the contacts. A
wedge resting flat on the floor already reports four points before anything hits it, so 6
is reached in any real clinch; 24 is never reached, and `_integrate_forces` sums the
impulses per collider anyway, so a larger cap costs a little memory and nothing else.
