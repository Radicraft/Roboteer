# Wave G, agent G3: the opponent AI

Brief v4 §4, built 2026-09-16. The driver that had never fought a moving human becomes
**five skill tiers by five temperaments**, with the behaviours the brief lists gated by
tier, and a headless sweep that says out loud whether the ladder is a ladder.

## What changed

| File | What |
|---|---|
| `Arena/ai/opponent_ai.gd` | The tiers, the temperaments, and the new behaviours |
| `Arena/ai/novice_driver.gd` | New, test only: straight at them, fires on contact |
| `Arena/tests/ai_test.gd` | 75 new checks, including the acceptance sweep |
| `Shared/parts.json`, `Arena/data/parts.json` | A fixed `temperament` on each of the eight rivals |
| `Arena/fight/fight.gd` | Two targeted edits in G1's file (below) |
| `docs/wave-g-contracts.md` | The AI section: the two config keys and two new `ctx` keys |

The two edits in `fight.gd`, both minimal and both noted in the contracts file:

1. `_make_driver(mode, cmdline_prefix, bot_config := {})` reads `bots[i].ai_skill` and
   `bots[i].temperament`, and `_arm` passes the two bot configs in.
2. `_ai_context()` gains `time_left_s` always, and `judge_points` (bot id -> points) only
   inside the last twenty seconds. Neither draws from the rng.

## The tiers

The brief's table, in `OpponentAI.SKILLS`, one row per career tier:

| Tier | Reaction | Aim | Hazards | Walls | Srimech | Reading |
|---|---|---|---|---|---|---|
| scrapyard | 0.60 s | 25 deg | spikes only | none | 1.7x slow | none |
| regional | 0.45 s | 18 deg | all | none | normal | weapon |
| national | 0.30 s | 12 deg | all + zone | pin | normal | weapon + armour |
| championship | 0.20 s | 8 deg | all + endgame | pin + shove | 0.6x fast | full |
| masters | 0.12 s | 5 deg | all + endgame | pin + shove + bait | 0.6x fast | full |

Two of those needed a decision about *how*, not just how much:

- **Reaction delay is a belief, not a buffer.** The driver keeps a picture of the
  opponent that eases toward the truth with a time constant of the tier's reaction time,
  and every decision below reads the belief. A Scrapyard driver therefore aims where the
  opponent was half a second ago, which is what a slow driver actually looks like. A jump
  bigger than 0.5 m in one tick cannot be a machine driving, so a spawn or a test fixture
  is believed at once rather than eased into (`TELEPORT_M`).
- **Aim error is a rotation of the finished heading**, drawn once per jitter cadence from
  the shared rng. It is applied in `_jittered`, so every movement path gets it and the
  `charge` debug mode (which bypasses the jitter) stays exact for the existing tests.

## The temperaments

`brawler` (the default, and deliberately the old behaviour: commits sooner, gives ground
briefly), `technician` (wider ring, waits much longer for a flank, leaves when hurt),
`bully` (eager pins and shoves, barely gives ground), `opportunist` (retreats when the
machine is coming apart, charges an inverted opponent), `showboat` (closest ring, almost
no patience, never gives ground).

Rivals carry theirs for life in `parts.json`, chosen from the `personality` line each
already had. Fillers (any bot entry with no `temperament`) draw one from the shared rng at
construction, which is a fixed point in `start_fight`, so the fight still replays.

## The new behaviours

All of them sit between "recover" and "strike" in `think()`, each gated by the tier:

- **Wall pin** (National up): three seconds holding them on the wall, then it lets go and
  stays off them for a moment. The pin rule bites at four seconds, so a pin that ran to
  the rule would be a penalty, not a pin.
- **Hazard shove** (Championship up): lined up behind them with something live within
  2.5 m in front of them, push. The hazard's damage is credited to the last toucher, so
  this is the cheapest damage in the game.
- **Weapon counters** (reading `weapon` and up): a spinner is taken 70 degrees off the
  nose of the spin and waited for two and a half times as long; a flipper is approached
  thirty degrees off its nose, expressed as a point half a chassis to one side that the
  approach converges on and then drops inside contact range (a heading rotated 30 degrees
  every tick is a spiral that never lands: measured, and it cost Masters two thirds of its
  wins); a crusher is never stopped in front of, so a latching weapon keeps working around
  one instead of parking in the jaws.
- **Armour reading** (National up): when the opponent's rear is its weakest face, the
  flank is worked deeper behind the shoulder.
- **Zone and house bot** (National / Championship up): the corner zone is left the way a
  hazard is left, and in the endgame the released house bot is routed around rather than
  driven through.
- **Retreat to re-spin** at `READY_DROP` (kept from before), **inverted = press the
  srimech and drive nowhere** (kept; after two failed presses it still rocks in reverse,
  which was a Stage 3 fix), and **the last twenty seconds**: behind on the judges' tally,
  the driver fights like a showboat for the rest of the fight.

## Determinism

Unchanged rule, unchanged order: the player's driver thinks first, then the opponent's.
The only new draw is the aim error, taken unconditionally on the same cadence as the
jitter, before any branching, in every mode. The temperament draw happens once per driver
at construction. Nothing reads a clock. `determinism_test` is green (42 checks), and
`ai_test` proves a Masters bully, a Scrapyard showboat and a drawn-temperament
Championship driver each replay bit for bit and each fight differently from another seed.

## The acceptance sweep, and what it is worth

`ai_test.gd` fights the tiers in a small kinematic arena rather than the physics one: a
hundred three-minute fights is five seconds of headless GDScript, where a hundred real
fights would be an hour. What the toy keeps: a heading drive with a finite turn rate,
contact that shoves, a weapon that bites only inside its reach and a 30 degree effective
cone, a hit on the back worth nine times a hit on the nose, the walls where the walls are,
one live hazard on the floor (every arena has one), and both drivers sharing one rng in
fight.gd's order. What it drops: the physics, the parts, the flips, the house bot.

It is a test of **driving**, which is what a skill tier is. It is not a prediction of the
real fight, and nothing here has been felt by a thumb.

Measured, all seeded, printed by the test:

```
Masters vs Scrapyard:        100 wins, 0 losses, 0 draws of 100   (brief asks for 85)
Novice vs Scrapyard:         100 wins, 0 losses, 0 draws of 100   (brief asks for 60)
Against Scrapyard, 20 each:  regional 15, national 18, championship 20, masters 20
Worst hazard entries/fight:  scrapyard 4, regional 0, national 0, championship 0, masters 0
Temperament fingerprint      [pins, shoves, retreats, ticks inside a metre]
  brawler     [25, 0, 0,  39]
  technician  [ 0, 0, 3,  34]
  bully       [52, 0, 0,  34]
  opportunist [ 0, 0, 5,  34]
  showboat    [56, 0, 0, 139]
```

Three numbers worth arguing with later:

1. **Both headline numbers are saturated at 100.** That is comfortably over the bar but it
   means the sweep cannot see a small regression in the win rate; the 20-fight rung sweep
   (15 / 18 / 20 / 20) is the gradient that can.
2. **A fifteen second fight is a coin toss.** The first version of this sweep fought 15 s
   rounds and Masters won 26 of 100, because the better driver's edge is a hit or two a
   minute and fifteen seconds is inside the noise. The sweep now fights the real three
   minute round and ends on the knockout.
3. **The hazard carries a lot of the separation.** Without a live hazard on the floor
   Masters beats Scrapyard about 28 of 40 rather than 40 of 40. Hazard awareness is one of
   the six things the brief's table says a tier IS, and every arena has something live in
   it, so the acceptance fight has one too. Worth remembering when reading the 100.

## What I could not verify

- Nothing here has been played on the phone. Every number above is AI against AI.
- The house bot keys (`house_bot_position`, `zone_rect`, `phase`) are read from G2's
  context in tests with hand-made fixtures. The real thing wants one look at a Regional
  career fight to confirm the opponent actually skirts the corner.
- `BossAI` still constructs at the default tier (regional, brawler) so the five enforcers
  fight exactly as they did, plus a small aim error. If the house bots should be sharper
  than a Regional driver, that is a one-line change in `boss_ai.gd` and G2's call.
- The wall model is the Yard's (`FightTypes.ARENA_SIZE`), so in the Coliseum, which is
  bigger, a pin is slightly shy rather than wrong.
