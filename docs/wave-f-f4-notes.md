# Wave F, agent F4: the smart AI

2026-09-16. The owner played the wave G build on his iPhone and said the enemy AI was
**"really stupid, driving straight into the spikes"**. He was right, and the verdict that
followed overrides the brief's table:

> **NO TIER MAY EVER LOOK STUPID.** Beatability comes from reaction delay, aim error,
> hesitation and weaker aggression, never from suicidal pathing. Every tier avoids every
> hazard, every wall and the house bot unless it is pushed.

Wave G's G3 agent had specified Scrapyard as "spikes only" awareness and measured four
hazard entries per fight at that tier, and every one of G3's numbers came out of a
kinematic toy arena rather than the physics world. Both halves of that were wrong.

## What changed

| File | What |
|---|---|
| `Arena/ai/context_steering.gd` | **New.** Pure context steering: interest map, danger map, mask, choose. No state, no rng, no clock. |
| `Arena/ai/opponent_ai.gd` | The movement layer rebuilt on it. The decision layer kept. The skill table's hazard column replaced. |
| `Arena/tests/ai_test.gd` | Unit tests for the steering; three checks re-baselined (below); the kinematic sweep kept for the statistics. |
| `Arena/tests/ai_physics_test.gd` | **New.** The acceptance numbers, measured in real arenas with real machines. |
| `Arena/ai/novice_driver.gd` | Unchanged. It is the owner's first night at the sticks and it is supposed to be dumb. |

Nothing outside `Arena/ai/` and `Arena/tests/` was touched. `fight.gd`, `boss_ai.gd`,
`hud.gd` and every arena file are as F4 found them.

## The technique: context steering

Andrew Fray, GDC 2015, *Context Steering: Behaviour-Driven Steering at the Macro Scale*.
The Godot recipe at `kidscancode.org/godot_recipes/3.x/ai/context_map/` was read first,
along with `github.com/konbel/steering-behaviors-godot-4` and
`github.com/WaffleAWT/Godot-4.2-AI-Steering-Behaviors` (neither of those two implements
context maps, only classic steering forces -- worth knowing before anyone else goes
looking).

**Why it is the answer to the owner's bug.** Wave G steered by summing forces: a "toward
the opponent" vector plus an "away from the hazard" vector. A 1.0-long approach against a
0.6-long avoid is still a 0.4-long approach, and the machine went in. It is the classic
failure of summed steering, and it gets worse the more the AI wants to attack.

Context steering cannot do that. The driver keeps two arrays indexed by direction:

* **interest** -- a cosine lobe from the current intent (close, hold the ring, flank,
  retreat, escape, pin, shove, back off, re-spin)
* **danger** -- everything that could hurt, probed `lookahead` metres along each slot:
  every live hazard from `hazard_helpers().danger_positions`, the spike patch off its own
  clock, the walls with a distance falloff, the house bot and its corner zone, and the
  opponent's weapon arc when the intent is not to go and hit them

Interest is then **masked** by danger -- a condemned slot is removed from the list, not
discounted -- and the best survivor is taken. Sixteen slots, 22.5 degrees apart.

Three things in that file are not in the recipe and each one was measured into existence:

1. **Exact interpolation, not a weighted sum.** The recipe sums every surviving slot. Do
   that here and a danger cone struck out of the middle of an interest lobe leaves
   survivors that are symmetric about the hole -- they sum back to the direction that was
   just condemned, and the driver goes straight into the thing it was avoiding. Measured:
   a Championship driver drove at a house bot it had a *wider* berth of than a Regional
   one, because a wider berth made the mask more symmetric. The fix is to take the best
   slot and read the peak off it and its better neighbour: the interest map is a cosine
   lobe, so two samples pin the peak exactly
   (`d = atan2((i1 - cos(step)*i0)/sin(step), i0)`). Sixteen slots therefore quantise the
   decision and never the steering.
2. **A probe that leads away from a hazard is scored differently from one that leads at
   it.** A pure closest-approach measure saturates: a machine inside a hazard's radius
   scores 1.0 in every direction, every slot ties, the mask does nothing, and the driver
   has no opinion at the exact moment it most needs one. So a slot whose direction has the
   hazard *behind* it is scored on present nearness, halved (`RETREAT_WEIGHT`).
3. **`HARD_DANGER`.** When everything the driver wants is condemned there is a graded
   fallback (Fray's subtractive variant: pick the least bad of the directions it actually
   wanted, rather than reversing away down the safest slot on the compass, which reads as
   frightened). That fallback may never choose a slot at or above 0.9 danger, at any
   throttle. Measured: without that line a driver whose opponent stood beyond the Yard's
   spike patch **crept toward the patch at a third throttle** -- the fallback traded a
   full-strength hazard against a strong wish to attack and the wish won.

The chosen heading is eased into last tick's (`STEER_SMOOTH` 0.35, about a tenth of a
second) so the machine reads as a driver turning a wheel rather than an array being
re-sorted sixty times a second. Getting off something live is exempt (`0.8`): a flinch is
not a change of mind.

## The tier table now

The brief's "hazard awareness" column is gone. Every tier knows everything is dangerous.
What a tier buys is **how far ahead it plans**, and the four handicaps:

| Tier | Reaction | Aim | Danger lookahead | Hesitation | Aggression | Pin | Shove | Bait | Zone | Endgame |
|---|---|---|---|---|---|---|---|---|---|---|
| scrapyard | 0.60 s | 25 deg | 0.6 s | 0.55 s | 0.55 | – | – | – | – | – |
| regional | 0.45 s | 18 deg | 0.8 s | 0.32 s | 0.70 | – | – | – | – | – |
| national | 0.30 s | 12 deg | 1.0 s | 0.16 s | 0.82 | yes | – | – | yes | – |
| championship | 0.20 s | 8 deg | 1.25 s | 0.06 s | 0.92 | yes | yes | – | yes | yes |
| masters | 0.12 s | 5 deg | 1.5 s | 0.0 s | 1.00 | yes | yes | yes | yes | yes |

* **Danger lookahead** is seconds turned into metres at 3 m/s, with a hard floor of one
  metre: *a hazard within 1.0 m is full danger at every tier, Scrapyard included*. That
  floor is the owner's verdict in one constant.
* **Hesitation** is a beat of eased-off throttle (0.40) after the driver changes its mind
  about what it is doing. Never on the first intent of a fight, and never over a hazard.
* **Aggression** is *commitment*, and it may only ever cost the weaker tier. The first cut
  had a low tier hold a wider ring and wait longer for a flank, and measured that it made
  a Scrapyard driver **better** -- it beat a Regional one 19 of 20 -- because patience and
  distance are tactics, not handicaps. What it now scales is: how long a run-in stays
  committed before it can be talked out of it (`DART_MIN_TICKS`), how much ground is given
  after a shot, and how far off the nose the driver will still press the button
  (trigger discipline: same range at every tier, because the range a flipper is worth
  firing at is a property of the flipper).
* **Endgame** no longer means "avoids the house bot" -- every tier does -- it means a berth
  half again as wide, so the tier that plans for it is already going round at four metres
  where a Regional driver is still coming on.

One more wave G bug fell out of this: a dart was abandoned on the very tick after it was
committed to whenever the opponent was still nose-on, which is *exactly* when patience
runs out and the driver goes in anyway. So "it gives up looking and commits" was one tick
of heading the machine never had time to act on. A dart is now a commitment for at least
`DART_MIN_TICKS * aggression` (0.3 to 0.6 s).

## The bug the owner actually saw

The physics test found it, and the toy never could.

`ArenaBase` publishes the spike patch as dangerous while `_spikes_up` **or** while the
countdown reads under 1.5 s. Those two are read a tick apart -- `seconds_to_spike_rise()`
uses the arena's current tick counter, `_spikes_up` is set from the previous tick's height,
and the patch takes a quarter second to travel before it counts as up. **So at the instant
the cycle wraps there are about nine ticks in which the countdown has already jumped from
"now" to "in 5.8 seconds" and the patch is not up yet, and `hazard_helpers()` reports
nothing dangerous anywhere on the floor.**

Measured in the Yard: a driver that had been giving the patch a wide berth read that gap,
believed the middle of the floor was free for the next six seconds, drove back in, and was
standing on the patch when the spikes came through it. Twice in one 60 s fight.

The driver now **latches**: once the countdown has been under 0.3 s the patch stays live
for 100 ticks whatever the arena says next, which is also how a human plays it ("they have
just come up, stay off them"). It needs nothing from the arena that the arena does not
already publish. **A one-line fix in `arena_base.gd` would close the hole at source** --
`_danger_positions()` should use `_spikes_up or seconds_to_spike_rise() < 1.5 or
seconds_to_spike_rise() > SPIKE_CYCLE_S - SPIKE_UP_S` -- but that is an arena file and F4
does not own it. **Recommended for whoever owns the arenas next.**

Two more numbers moved because a wedge takes half a second to turn round before it goes
anywhere: a machine starts leaving the patch 2.4 s before it rises (was 1.0 s) and from
1.8 m out (was 1.2 m).

## The numbers

### The physics test -- `Arena/tests/ai_physics_test.gd`

Real arenas from `Arena/arena/*.tscn`, real machines from `res://bot/bot.tscn`, the
world-spawning shape `physics_test.gd` and `events_test.gd` use. Five tiers x two
opponents (the novice driver and Masters) x two seeds x two arenas = 40 seeded 60 s
fights.

**An entry counts only if it was UNPUSHED**: the machines have to have been out of contact
for half a second beforehand, and the machine has to be the right way up. A machine that
is rammed onto a grinder has been beaten, not fooled, and counting that against the driver
would only teach the test to reward a driver that never engages. Entries are counted
against `spikes_risen()` in the Yard and against disc geometry in the Grinder -- machines
**on risen spikes** and **on spinning discs**, not machines that crossed the middle of the
floor during the down phase and left in good time.

| | unpushed hazard entries | bar |
|---|---|---|
| Yard, every tier, 4 fights each | **0** | 0 |
| Grinder, every tier, 4 fights each | **0** | at most 1 |

Pushed entries did happen (five across the forty fights), which is the measurement working:
the machines really are shoving each other onto things.

Alongside, so that "it avoids everything" can never quietly become "it does nothing", each
tier is also required to drive the floor and land hits. Typical per-fight figures:

```
  tier          against   hazard  pushed  driven walltime   hits  close
  scrapyard     novice         0       0    15.3     6.4%      4    89%
  regional      masters        0       0    25.6     0.0%      1    31%
  national      novice         0       0    20.4    23.8%      6    72%
  championship  masters        0       0    27.1    15.6%      4    51%
  masters       novice         0       1    29.5     9.4%      7    87%
```

15 to 39 m driven per 60 s fight, 0 to 88% wall time, 0 to 12 hits landed. Wall time
varies enormously between fights and is the number most worth watching if the AI ever
starts to look like it is hiding.

**The whole suite runs in about fifty seconds** because the script re-runs itself in a
child process with `--fixed-fps 60`. Headless Godot steps physics in real time otherwise:
measured, the same forty fights took **forty minutes** of wall clock for seven minutes of
CPU. `--fixed-fps` also pins the delta to exactly 1/60, which is stricter than the default,
not looser. This is worth knowing for every other physics test in the repo.

### The kinematic sweep -- `Arena/tests/ai_test.gd`

The brief's two headline numbers, both still green and both better than wave G's:

```
SWEEP Masters vs Scrapyard: 100 wins, 0 losses, 0 draws of 100   (brief asks for 85)
SWEEP Novice vs Scrapyard:  100 wins, 0 losses, 0 draws of 100   (brief asks for 60)
SWEEP worst hazard entries in one fight:
  { scrapyard 0, regional 0, national 0, championship 0, masters 0 }   (wave G: scrapyard 4)
```

207 checks, 0 failures. `determinism_test` 42 checks, 0 failures.

### Three checks re-baselined, with reasons

1. **"a Scrapyard driver walks into the hazard more often, which is what the tier is."**
   Deleted. That check *was* the bug. Replaced with: every tier, Scrapyard included,
   drives into a live hazard at most once in a fight. Measured zero at all five.
2. **The rung sweep.** G3 ranked the tiers by their win rate against a Scrapyard driver.
   With hazard suicide gone that comparison stopped meaning anything: two adjacent tiers
   in the toy are a near mirror, and the mirror is decided by the clinch model rather than
   by skill. Bisected, 40 fights a row, both sides of the draw order:

   ```
   regional (as is)          vs scrapyard   W 2 L38
   regional minus reaction   vs scrapyard   W 4 L36     <- give it back Scrapyard's 0.6 s
   regional minus aim        vs scrapyard   W 6 L34     <- and Scrapyard's 25 degrees
   regional minus lookahead  vs scrapyard   W 3 L37
   regional minus hesitation vs scrapyard   W 3 L37
   regional minus aggression vs scrapyard   W10 L30
   regional minus reading    vs scrapyard   W11 L29
   regional = scrapyard      vs scrapyard   W20 L20     <- a true mirror, so the harness is fair
   ```

   Every single handicap the brief names makes a driver **worse in the toy when it is
   removed**, which is anti-correlated with skill by any definition. The reason is that
   the toy's damage model pays for disengaging and re-approaching and has no idea what
   control of a clinch is worth: `SIM_FACE_WEIGHT` makes a rear hit nine times a front
   hit, a wide aim error sweeps the nose across the opponent like a scan, and every tick
   of grinding trades evenly. **The toy cannot rank adjacent tiers and should not be asked
   to.** The rung check now uses the novice as a fixed yardstick, both sides of the draw
   order, and what it ranks is the thing the brief's table actually gates:

   ```
   SWEEP against the novice over 20 fights:
     { scrapyard 0, regional 0, national 0, championship 19, masters 20 }
   ```

   The cliff is at Championship, which is where the hazard shove arrives. Monotone, which
   is what the check asserts. (The novice beating three tiers is the toy overrating
   relentless ramming, not a statement about the game.)
3. **"in the endgame a Championship driver bends around the house bot and a Regional one
   goes through it."** No longer true and must not be: every tier goes round it. Replaced
   by two checks -- all five tiers steer around a house bot a metre in front of them, and
   at four metres the Championship driver is already going round where the Regional one is
   not.

## What only a phone can judge

* **Whether it still reads as a fight.** Every number above is AI against AI. Close time
  swings from 4% to 97% of a fight depending on the pairing, and a fight where both
  machines circle at 30% close time may be tactically correct and dull to watch.
* **Whether the hesitation reads as a driver thinking or as a machine stuttering.** A beat
  of 0.40 throttle for half a second at Scrapyard is a big, visible thing on a phone and
  it is deliberately the loudest of the four handicaps. It may be too loud.
* **Whether the berths look respectful or timid.** The arenas publish danger as bare points
  with no radius, so `DANGER_RADIUS_M` is one number (0.95 m) standing in for a 1.6 m spike
  patch, a 0.55 m grinder disc, a ram head, a flame jet mouth and a 2.4 m pit. **A
  `danger_radii` array alongside `danger_positions` in `hazard_helpers()` is the single
  most useful thing an arena could give this driver**, and the Drop Zone's pit is the case
  where the guess is worst.
* **Whether a machine ever looks stuck.** Traced in the Yard: a wedge commanding full
  throttle sat at 0.01 m/s for several seconds, apparently wedged on the opponent. That is
  a physics/drive question rather than an AI one, but it looks like stupidity from the
  stands and it is what to watch for first.
* **Whether the Coliseum's walls are in the right place.** `fight.gd` does not put the
  arena's extent on the AI context, although every arena knows it (`arena_half_extent()`).
  The driver falls back to the Yard's 10 m and grows its belief from where it has seen
  machines drive, which is deterministic and never models a wall further out than it is --
  but **one line in `_ai_context()` (`ctx["arena_half_extent"] = _arena.arena_half_extent()`)
  would make it exact**, and the physics test already passes it. Recommended, and not F4's
  file to change.

## Determinism

Unchanged rule, unchanged order. The rng is still drawn at a fixed cadence before any
branching, in every mode. The steering is pure arithmetic over fixed-size arrays; the only
memory it carries between ticks -- the smoothed heading, the intent, the hesitation clock,
the spike latch, the believed arena extent -- is a function of the ticks before it and of
nothing else. No wall clock, no second rng, no `Engine.get_frames_drawn`.
`determinism_test` is green (42 checks) and `ai_test` still proves a Masters bully, a
Scrapyard showboat and a drawn-temperament Championship driver each replay bit for bit.
