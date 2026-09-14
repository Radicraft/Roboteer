# Rumble: the measurement and the decision

Brief §10 keeps Rumble (a three bot free for all) in scope "decided on physics grounds
after Stage 4". `docs/stage4-spec.md` §6 sets the bar: **keep it if three bots stay under
8 ms worst case physics step time on this Mac**, which is a proxy, with the final call made
on the phone.

## Recommendation: KEEP Rumble in scope, and re-measure on the phone before building it

A third machine costs about **15 % more physics time per step**, not 50 %, and three bots
land at roughly **1.7 ms** against a budget of 16.7 ms for a 60 Hz frame. The physics is
not what will decide Rumble. What will decide it is the camera (three bots do not fit the
Stage 3 framing rule that the walls stay on screen), the judges' scoring, which is written
for two, and readability. None of those are measured here.

## How it was measured

`Arena/tests/_rumble_probe.gd`, skipped by `scripts/test-arena.sh` because it is a
measurement rather than a test:

    Godot --headless --path Arena --script tests/_rumble_probe.gd -- --secs=30

It runs the real fight scene headless with `player_ai` and `opponent_ai` both on `normal`,
for 30 simulated seconds with two bots and then 30 with three, discarding the first 120
ticks so the countdown and the settle are not in the sample, and reads
`Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)` once per physics tick. The
third machine is built and driven by the probe, not by `fight.gd`: the orchestrator is a
two bot machine by contract, and the point of this was to price a third one before anyone
commits to changing that.

Two things had to be got right for the number to mean anything.

1. **One physics step per sample.** `TIME_PHYSICS_PROCESS` is the time spent in one engine
   *iteration*, and an iteration can contain several physics steps. The first version ran
   with `Engine.time_scale = 6` to save wall clock time and was silently reporting three
   steps added together as one (3 bots "worst 10.1 ms"). The probe now pins
   `max_physics_steps_per_frame = 1` and runs at real time, so one sample is one step, and
   the measurement costs its own minute.
2. **The machine has to be quiet.** This Mac was running other agents' Godot processes
   during some runs, and a single contaminated sample lands straight in the worst case.

## The numbers

Hardware: the owner's Mac, macOS 25.6, Godot 4.6.3 headless, Jolt, 60 Hz fixed step,
`body_pair_contact_cache_enabled = false` (see `docs/stage3-rules-notes.md`).
1800 samples per row.

| run | machine | bots | median | mean | p95 | p99 | worst |
|---|---|---|---|---|---|---|---|
| 1 | quiet | 2 | | 0.719 | 1.377 | | 1.438 |
| 1 | quiet | 3 | | 0.831 | 1.494 | | 1.808 |
| 3 | quiet | 2 | 1.486 | 1.463 | 1.899 | 1.941 | 1.941 |
| 3 | quiet | 3 | 1.716 | 1.630 | 1.920 | 1.938 | 1.938 |
| 2 | busy | 2 | | 1.967 | 6.646 | | 10.043 |
| 2 | busy | 3 | | 1.830 | 3.132 | | 13.324 |

All figures milliseconds per physics step.

**Run 2 is the one to ignore, and it is instructive.** Its three bot *mean* came out
**lower** than its two bot mean (x0.93), which is impossible for the thing being measured
and is proof the sample was contaminated by other processes on the machine. A worst case
drawn from a single sample on a shared Mac measures the Mac, not the arena. Runs 1 and 3
agree closely on the figure that matters: **a third bot costs x1.15 to x1.16 on the
median**.

## Reading it against the bar

- Three bots, quiet machine: worst case **1.94 ms**, comfortably inside the spec's 8 ms.
- The 60 Hz frame budget is 16.7 ms in total. Physics at 1.7 ms is about a tenth of it.
- The marginal cost of the third machine is 0.2 ms per step. Even five bots would be
  inside the bar on this evidence, which is a useful thing to know for the gauntlet events
  in brief §8 as well as for Rumble.

## What this does not prove

- **It is a Mac, not a phone.** The brief says so and the spec says so. An A19 will be
  slower per core and, more importantly, will throttle. The number to trust is the ratio
  (x1.15), not the absolute, and the phone measurement is owed.
- **Bodies, not bots, are the real budget.** Brief §12 caps a bot at chassis plus six
  wheels plus weapon plus four panels, so a third bot is up to twelve more bodies and the
  measurement above used the Stage 3 wedge (eleven). A three bot fight between six wheeled
  machines with spinners is heavier than what was measured. The cap is what keeps this
  honest; nothing in Stage 4 should raise it.
- **Contacts are the spiky part, not body count.** The cost is dominated by how many pairs
  are touching, and three bots in one corner is a worse case than three bots spread out.
  Thirty seconds of AI driving produced clinches but cannot promise the worst one.
- **Nothing outside physics was measured.** Rendering, the bolt showers and the AI are not
  in `TIME_PHYSICS_PROCESS`. Three bots means a third bolt shower and a third motor voice.

## What would have to change to actually ship Rumble

Listed here because the physics answer is the easy half:

1. `fight.gd` is two bots throughout: `_bots`, `_tallies`, `_scrap` and every win condition
   are pairs. Making them lists is mechanical but touches every rule.
2. The judges' card is scored against one opponent (spec §8: damage removed from *the*
   opponent). Three way scoring needs a rule that does not exist yet.
3. The camera's fit rule keeps the whole arena on screen, so three bots are already
   covered, but the look-at bias toward "the midpoint of the two bots" is not.
4. Out of the arena eliminates a bot rather than ending the fight.

None of that is Stage 4 work. The recommendation is to keep Rumble in scope, leave the two
bot orchestrator alone (brief §12: "preserve working gameplay over adding sophistication"),
and take the phone measurement before writing any of it.
