# Stage 6 side events (agent E6)

Five events, one arena kit, one test file. `docs/stage6-spec.md` §1, brief §10 ("a direct nod to
the original's trial modes, reworked as physics challenges ... each rewards blueprints, so they're
not optional filler") and brief §3 (no copied layouts or floor markings).

| rules | arena | id | size | the event |
|---|---|---|---|---|
| `Arena/fight/events/sumo.gd` | `Arena/arena/events/sumo.gd` | `sumo` | 6 m ring on a 14 x 14 apron | best of three push-outs in 90 s |
| `Arena/fight/events/gauntlet.gd` | `Arena/arena/events/gauntlet.gd` | `gauntlet` | 24 x 6 corridor | reach the pad, BANDSAW enters at 20 s |
| `Arena/fight/events/pinball.gd` | `Arena/arena/events/pinball.gd` | `pinball` | 10 x 14 table | 60 s, six bumpers, a ramp, two drop targets |
| `Arena/fight/events/football.gd` | `Arena/arena/events/football.gd` | `football` | 12 x 8 pitch | most goals in 90 s against an AI |
| `Arena/fight/events/wall_smash.gd` | `Arena/arena/events/wall_smash.gd` | `wall_smash` | 20 x 6 corridor | five brick walls against the clock |

Shared: `Arena/arena/events/event_arena_base.gd` (rectangular floors, walls and out-of-arena on top
of `ArenaBase`) and `Arena/arena/events/brick.gd` (one breakable brick). Rules extend agent R's
`res://fight/events/event_rules.gd`. Test: `Arena/tests/events_test.gd`, **101 checks, all green**,
picked up automatically by `scripts/test-arena.sh`.

---

## The floor plans

### Sumo, "The Ring"

```
      -7            -3        0        +3            +7
   -7 +---------------------------------------------------+
      |                  . - - - - - .                    |   apron, 0.4 m BELOW the
      |              .                 .                  |   platform, NO WALLS
      |            /     ___________     \                |
    0 |           |  P  |  .  +  .  |  O  |               |   P (-1.8, 0, 0)
      |           |     |___________|     |               |   O (+1.8, 0, 0)
      |            \                     /                |   + centre cross
      |              .                 .                  |   |__| start bars
      |                  . - - - - - .                    |
   +7 +---------------------------------------------------+
```

6 m platform (r = 3.0) standing 0.4 m proud of the apron. The only arena in the game with nothing
to bounce off, which is the point: every other arena rewards pinning a machine against something.
Marks on the east-west diameter, 3.6 m apart, 1.2 m in from the rim, a 180 degree rotation of each
other.

**Marking scheme:** one emissive amber rim line just inside the edge, which is the only thing in
this arena that can hurt you; a plain centre cross; a 1.8 m inner circle; a start bar at each mark;
sixteen radial ticks so a machine being spun on the spot reads as spinning; and on the apron a
broken ring at r = 4.6 that says "this is not the floor you want".

**Off the platform** is a ring sensor plus the base's out-of-arena volumes. The sensor is not an
annulus, because an `Area3D` is made of convex primitives and an annulus is not one: it is a flat
slab over the WHOLE apron with its top at y = -0.06, which a machine standing on the platform
(wheels bottoming at y = 0) cannot reach. The rules also test the chassis radius arithmetically,
which catches a machine still in the air over the apron.

### Gauntlet, "The Run"

```
   -12      -9.6    -7.6     -3.6      0.4      4.6     7.2    9.8    +12
    +----------------------------------------------------------------------+
  -3|  G  P  |       |       |   (g) |  <<<<< |       |[#####]|   /////////|
    |        | ##### | ##### |       |        |[#####]|       |   /////////|
   0|        | ##### | ##### |       |        |[#####]|       |   //PAD////|
    |        | ##### | ##### |   (g) |  >>>>> |       |[#####]|   /////////|
  +3|        |       |       |       |        |       |       |   /////////|
    +----------------------------------------------------------------------+
      start     spike patch   grinders  flame gate  crush presses   finish
```

Every section leaves a lane and no two are the same lane, so the run is a weave rather than a
sprint: spikes 4 m across a 6 m corridor (a 1 m ribbon each flank, or drive over between rises);
grinders at z = +/-1.35 (the centre line, or either edge); a flame gate of two opposed wall jets
that ALTERNATE on a 6.4 s cycle (the lane is the far side from whichever is lit, and twice a cycle
both are out); two overhead presses offset in Z from each other (the lane crosses from the +Z half
to the -Z half between them).

**Marking scheme:** a works floor. A hazard-yellow kerb down each flank; a section bar at the mouth
of each hazard ticked one to four, which is the only counting mark on any floor in the game and is
here because the run has an order to read; a keep-out ring round each grinder; down-chevrons under
each press; the pad hatched and lit green.

The presses are the one piece of hazard kit `ArenaBase` does not ship (the ram lives in `crush.gd`,
which is not this agent's file), so `_add_press` is built from the base's own plumbing
(`_make_hazard_area`, `_box_shape`, `_damage_overlaps`, `_crush_bots_in_area`) with `crush.gd`'s
measured numbers: 58 N s every 24 ticks plus a 0.05 bite through the top face. It comes DOWN rather
than in from a wall because a 6 m corridor has no room for a 0.9 m side stroke.

### Pinball, "The Table"

```
      -5      -3.3     0      +3.3    +5
   -7 +-------------------------------------+
      |          (B)         (B)            |   (B) bumper, post r = 0.35,
      |               (B)                   |       kick ring r = 0.60
   -4 |                                     |
      |      [T]              [T]           |   [T] drop target, 5 s reset
   -2 |                                     |
      | (B)                          (B)    |
    0 | /|                                  |
      |/ |          (B)                     |   /  the RAMP, rising 0.5 m
   +2 |  |                                  |      to a gate at its head
      |  |                                  |
   +4 | \|                                  |
      |                                     |
   +6 | x           P                       |   P player mark, x parking bay
   +7 +-------------------------------------+
```

Three ranks, not a pattern: a three-bumper bank at the head where a fast run ends up, a pair on the
flanks at the waist to bounce between, and one lone bumper on the centre line that is in the way of
every straight line anyone will try to drive. No bumper is within 1.4 m of another, so a kick
throws you clear rather than wedging you in a nest.

**Marking scheme:** a scoreboard. A lit scoring ring under each bumper, the ramp lane hatched and
arrowed toward its gate, a boxed bay under each drop target, a plunger arrow at the mark. Nothing
on this floor is a warning, which is the point: it is the one arena with no danger in it.

### Football, "The Pitch"

```
      -6    -4.5      -2.6    0    +2.6      +4.5   +6
   -4 +--------------------------------------------------+
      |     |                 :                 |        |
      | =GOAL=          .- - - - -.        =GOAL=        |   3.0 m mouths in the
 -1.5 | ###|      P     |    o    |     O      |###      |   END WALLS, a post
      |    |             `- - - - '             |        |   each side
 +1.5 | ###|                 :                 |###      |
      |     |                 :                 |        |
   +4 +--------------------------------------------------+
```

The end walls are CLOSED and the goal is an `Area3D` standing in front of each one, so the ball can
never leave the pitch: a ball out of play is a rule nobody wants to referee with a robot. The
sensor's mask is the DEBRIS layer only, so a machine parked in its own mouth is a defender, not a
goal. Ball: 0.5 m sphere, 3 kg, bounce 0.55, `continuous_cd` on (a flipper punt crosses a 0.2 m
wall in one tick without it), on `LAYER_DEBRIS` so `FightTypes.MASK_BOT` collides with it for free
and the bots-only out-of-arena sensor ignores it.

**Marking scheme:** chalk on plate. A halfway line, a centre spot and a 2.4 m circle, a boxed goal
area at each end, corner ticks, a bay ring under each start position. The lit goal mouths are the
only emissive marks, because the goal is the only thing on this floor that changes the score.

### Wall Smash, "The Demolition Run"

```
    -10    -8.6      -5.0    -2.0    +1.0    +4.0    +7.0        +9.2  +10
     +-----------------------------------------------------------------+
   -3|     |         |###|   |###|   |###|   |###|   |###|      ||||||||
     |  P  >         |###|   |###|   |###|   |###|   |###|      ||FIN||
    0|     >         |###|   |###|   |###|   |###|   |###|      ||||||||
     |     >         |###|   |###|   |###|   |###|   |###|      ||||||||
   +3|     |         |###|   |###|   |###|   |###|   |###|      ||||||||
     +-----------------------------------------------------------------+
        run-up          1       2       3       4       5      finish bar
```

Five walls of six bricks each: three across the corridor, two courses high. The 3.6 m run-up is
deliberate and is about what a 4wd build needs to reach top speed, so the first wall measures your
drive and the rest measure whether you can line up again after a hit.

**Marking scheme:** a works floor counting DOWN. A numbered bay bar in front of each wall, one to
five; a centre lane line the whole length, which is the line a good run never leaves; a kerb each
side; the finish bar lit green. No warning yellow anywhere: nothing in this arena is trying to hurt
you.

---

## Scoring

`fight.gd._finish_event` sends `event_result {mode, score, cleared, time_s, details}` and forwards
only those five keys, so **anything the shell needs that is not `score` or `cleared` has to be in
`details`**, and `time_s` at the top level is the FIGHT's clock, not the event's. Every event below
therefore repeats its own numbers inside `details`.

| event | `score` | `cleared` | `details` |
|---|---|---|---|
| sumo | rounds won | won 2 of 3 | rounds_won, rounds_lost, rounds_played, round_winners, led_on_the_bell |
| gauntlet | `(90 - time) * 100 - damage * 250`, floored at 0, 0 if not cleared | reached the pad | time_s, damage, chaser_entered, chaser |
| pinball | bumper 100, ramp 500, target 250 | score >= 4000 (par) | bumpers, ramps, targets, par |
| football | goals for | more goals than against | goals_for, goals_against, outcome |
| wall_smash | `(90 - time) * 100`, 0 if not cleared | all five walls | time_s, walls_broken, walls, wall_times, par_s |

Score always goes UP for a better run, including the two events whose real measure is a time, so
one "best score" column in the Events screen works for all five. Blueprint rewards are Swift's, off
`cleared`, and nothing in Godot knows about them.

Design notes worth keeping:
- **Sumo is best of three and a 1-0 lead on the bell is a WIN but not a CLEAR.** Leading when the
  time runs out is winning; "not enough time to finish it" is not a draw anybody enjoys. The
  blueprint is for taking two rounds, so `cleared` needs two. Damage carries across rounds on
  purpose: a machine that spent round one being cut up should feel it in round two, or the event is
  three unrelated fights.
- **The ramp is worth five bumpers.** A bumper happens to you; the ramp is something you aim at,
  line up and climb, and the table should pay for intent. The targets' five second reset makes the
  table a route rather than a place to stand: hit both, go and do something else, come back.
- **Wall Smash deliberately rewards nothing but the build.** A 100 kg ram on 6wd beats a nimble
  flipper here, and that is correct: every other event punishes that build, and the five events
  between them should want five different machines out of the garage.

---

## What `fight.gd` already does (agent R landed it while this was being built)

`RULES_EVENTS`, `EVENT_DIR`, `_load_event`, the `physics_tick` / `is_over` call at the end of
`_tick_fight`, `arena_scene_path()` in `_build_world`, `hud_lines()` into the HUD's height readout,
and `_finish_event` sending `event_result`. The events here are written against exactly that and
need nothing else. Two things about it are worth knowing:

1. **`_load_event` runs BEFORE `_build_world` and `_spawn_bots`.** `EventRules`' own doc says
   `setup` is called "after the bots are built and placed", and the file does it the other way
   round, so at `setup` time `arena()` is still the LAST fight's arena and `bots()` is still the
   last fight's machines. Every event here therefore does its configuration reading in `setup` and
   everything that touches the world in an `_arm()` on its FIRST `physics_tick`. That is correct
   under either ordering, so it does not need agent R to change anything, but anyone writing a
   sixth event should copy the pattern rather than trust the doc comment.
2. **The ordinary win conditions are skipped while an event runs** (`_check_win_conditions` returns
   early when `_event != null`), which is what makes a Sumo push-out a round rather than the end of
   the fight.

### The spare machine

The fight always builds two machines. Three of the five events have no opponent, so each one parks
the second machine on a bay mark its arena provides as `spawn_position(1)` and calls `Bot.freeze()`
on it. Freezing rather than deleting: the tallies, the HUD, the camera and the result builder all
index two bots, and a null in that list is a crash waiting for whichever of them reads it first.
A Swift config for a solo event should still set `debug.opponent_ai = "off"`, which saves the
driver's work, but nothing here depends on it.

### Football's opponent is steered through the drive module, not `apply_input`

`fight.gd` has already called `apply_input` on both machines by the time `physics_tick` runs, and
`Bot.apply_input` does two things: it sets the drive's motor targets, which is idempotent, and it
advances the WEAPON'S clock by `dt`, which is not. Calling it a second time in the same tick would
run the opponent's weapon at double speed for the whole event, so `football.gd` drives
`bot.drive_module` directly and leaves the weapon under the fight's own driver. If a later stage
wants an event to own the whole input record, the clean change is in `fight.gd`: ask the rules first
and skip the ordinary driver for any index they claim.

---

## Traps found while building this

1. **Two simulations only agree if each has its OWN `World3D`.** This is the big one. The first
   version of `events_test.gd` built each world as a plain node under `root`, so every run shared
   the root viewport's physics space. MEASURED: four identical Gauntlet runs on one seed, 600 ticks
   each, finished at x = 0.44, -9.48, 4.52 and 4.51. A space that has had bodies removed from it is
   not the space a fresh one is, and Jolt reuses the RIDs. Putting each world in a `SubViewport`
   with `own_world_3d = true`, which is exactly what `fight.gd._build_world` does and why, gave
   x = 4.5364 on all four runs, to four decimal places. Anything in this project that wants to
   compare two simulations has to do the same.
2. **`Bot.place_at` is an initial placement, not a teleport.** It sets the BOT NODE'S global
   transform and pushes each part's node transform at the physics server, which is absolute only
   while the parts are still at the local offsets the assembler gave them. Once a machine has been
   simulating, each part sits wherever the solver put it, so setting the root moves the assembly by
   a DELTA. MEASURED: a machine shoved to x = 4.41 and then `place_at(1.8)`-ed from a mark of 2.5
   landed at 3.71, which is 4.41 minus 0.7, still off the platform, and the Sumo round reset
   awarded the next round to the same machine, ending a best-of-three 2-0 on one push.
   `fight/events/sumo.gd._set_down` computes the rigid transform that maps the CHASSIS onto the
   mark and applies it to every attached part, which also levels a machine that was on its back.
   **`fight.gd._replace_bot` (test mode's stray replacement) is built the same way as `place_at`
   and will have the same behaviour.** Flagged for agent R; it has not been chased here because
   `Arena/fight/fight.gd` is not this agent's file.
3. **Moving the root already moves the children, so a rigid fix must be computed first.** The first
   `_set_down` set the root's transform and then multiplied each part's (already moved) global
   transform by the same fix, applying it twice. A machine asked for (-4.00, 0.62, 1.25) landed at
   (-8.09, 1.09, -0.71), which is exactly `fix` squared, and teleporting it inside the furniture
   filled the log with 434 `!v.is_finite()` errors from the renderer. Compute every target BEFORE
   the root moves; apply them after.
4. **A brick welded to a static anchor cannot be broken on raw contact impulse, and the reason is
   physics, not Godot.** The joint absorbs the blow, so the contact only has to stop the machine's
   penetration a little at a time. MEASURED with the fixture wedge: a full speed ram reported a
   peak of 0.86 N s per step on the brick and 6.1 N s on the machine's own worst part, spread over
   about twenty steps, and a machine STALLED against the wall at full throttle reported the same
   0.86. The number that separates a ram from a lean is the CLOSING SPEED, 2.87 m/s against 0.00.
   `brick.gd` therefore reads, still inside `_integrate_forces`, the momentum the wall is being
   asked to absorb: closing speed along the contact normal times the mass of the MACHINE behind the
   contact (`BotPart.owner_bot.total_mass()`, not the 3 kg plate that touched first). A ram measures
   73 to 122 N s depending on how square the nose lands; the threshold is 60.
5. **A machine is taller than one course of bricks**, so a missing bottom brick is a trip, not a
   door. Freeing a bottom brick frees the one resting on it, which is both what a wall does and
   what turns one good ram into one clear column; a wall counts as broken when a column is clear.
6. **`_striker_mass` is not the part that touched.** A front plate on a 100 kg machine is 100 kg
   arriving. Reading `part.mass` makes a wall four times harder to break for a machine with thick
   armour, which is exactly backwards.
7. **Arming an event resets the ball.** `football.gd._arm` puts the ball on the spot on its first
   tick, which is kickoff and is right, and which will silently undo anything a test set up before
   that tick. `events_test.gd` runs five ticks of event before it kicks the ball.
8. **A `for` over an untyped literal array will not compile** when the loop variable is then used
   in typed arithmetic: `for side in [-1.0, 1.0]` fails with "cannot infer the type" in the first
   `var` that uses it, and the whole script fails to parse. Bind it: `for v in [...]: var side :=
   float(v)`. Same trap `arenas_test` notes for `bot.get_instance_id()`.
9. **`Area3D.body_entered` is not a tick.** Football polls `get_overlapping_bodies()` from its own
   `_physics_process` instead, because a replay has to agree with its fight tick for tick and a
   signal fires whenever the engine gets round to it. The goal lockout (30 ticks) is what stops one
   crossing counting as thirty.

---

## Budgets, as built

| arena | bodies (PhysicsBody3D + Area3D) | meshes |
|---|---|---|
| sumo | 4 | 5 |
| gauntlet | 25 | 31 |
| pinball | 24 | 21 |
| football | 13 | 16 |
| wall_smash | 41 | 42 |

Budget in the test is 56 bodies and 130 meshes, higher than the Stage 5 arenas' 30 / 120 on
purpose: The Demolition Run is thirty bricks plus five anchors, which IS the event. The point of a
budget is to catch an arena that grew by accident, not to forbid one that is made of loose parts.
The thirty bricks have `can_sleep = false`, because a sleeping body runs no `_integrate_forces` and
the first hit on a wall is the one that has to be measured. That is the one place any of this
spends more than it has to, and it has not been measured on a device.

---

## Weaknesses, owed, and what I did not do

- **Nothing has been looked at.** Every frame of this is headless. The tints, the emissive rim line,
  the lit goal mouths, the scoring rings and the brick material are reasoned against
  `docs/graphics-render-notes.md` and the Stage 5 arenas, not shot. The Sumo apron in particular is
  a flat plate 0.4 m down with no wall behind it, and what the camera does at the edge of a floor
  that just stops has never been seen.
- **Nothing is tuned by playing it.** Par for Pinball (4000) and the Gauntlet's score weights
  (100 a second, 250 a condition point) are reasoned, not measured against a person. So is
  BANDSAW's twenty seconds: the spec sets it, but whether a run is winnable with a saw behind it
  has only been tested by a machine driving in a straight line.
- **The Football driver has never lost.** It goes for the ball and lines up behind it, and against
  the fixture wedge in the test it stays nearer the ball than the player. It has not been played
  against a person, and it has no idea about defending: if the player is quick it will chase the
  ball into its own half and leave the goal open.
- **A Gauntlet run has not been driven end to end by anything competent.** The pad test starts the
  machine 2 m short of the pad on purpose, because whether a wedge can thread a four-hazard weave is
  the player's problem and not the arena's. The determinism run drives straight down the middle from
  the start mark and gets about as far as the presses.
- **The Sumo ring sensor will fire on a part thrown clear**, not only on a machine that fell. The
  rules use the chassis test as well, so a thrown wheel cannot lose you a round, but the `body_out`
  signal the arena emits is noisier than the Stage 5 arenas' and anything that connects to it should
  know that.
- **Wall Smash debris blocks the run.** Thirty loose bricks stay on the floor, and in the test run
  the machine was slowed by wall one's rubble on its way to wall two. That is authentic and probably
  good, but a 90 s five-wall clear has not been proven possible by anything other than reasoning.
- **The presses can catch a machine against a wall of the corridor.** The Crush's notes flag the
  same thing for two rams firing together; here the two presses are offset in Z and half a cycle
  apart, so it should not happen, but a seed can put a machine under one as it lands.
- **The test fixture bot is 11.9 kg over the weight budget**, exactly as in `arenas_test.gd`, and
  pushes a warning on every spawn. Harmless for hazard damage, which is impulse based, but the brick
  threshold IS mass based, so a legal 100 kg build would break walls slightly more easily than the
  numbers in trap 4 suggest. Worth re-measuring with a legal build before anyone retunes it.
