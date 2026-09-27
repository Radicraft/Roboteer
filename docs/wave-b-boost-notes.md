# Wave B pacing, part 2: BOOST and NO MORE STUCK

2026-09-27, pacing engineer (part 2). Owner: "it's easy to just drive around or get stuck, without
much drama or skill." Part 1 (arena escalation, big payoffs) is the other agent's.

## Where I stopped (2026-09-27 evening)

DONE and committed on main (not pushed): f902361, ede4db2, c72dd92 (took back the intro agent's
section f902361 swept up), 66e8e67, 5d966a5, 839ca22, 1463099, 6be13bf, and this note.

Suite (`HEADLESS=1 JOBS=2`, worktree at 1463099 = my commits + the escalation agent's 00056bb /
e8e6d84), then the three test fixes of 6be13bf re-run by hand:
- PASS everything except:
- `hazard_determinism` 6 goldens MOVE (not re-recorded, per instruction). Why: every golden fixture is
  an AI fight, and the AI now presses BOOST (escape / stuck / attack), wedged machines are nudged, the
  referee breaks lock-ups at 3 s instead of 8, and the AI rights itself sooner (0.6 m/s, 50 ticks).
  The escalation agent's stages also move them. Re-record once both pacing agents are final.
- `builds_test` "the spinner build removes at least one panel (0)": a single-seed 120 s AI fight; it
  passes on e994cd3 and fails from 66e8e67 (my boost) on, so the dashes changed that one fight. Not
  weakened. The 84-fight gauntlet says the spinner is not worse: horizontal spinner parts off
  11 -> 15, damage out 3.94 -> 4.16 per fight. Owner / weapons lead to decide (another seed, or
  two seeds with "at least one").
- Fixed in 6be13bf: rules_test (row is seven wide), ai_test (the inverted window follows the faster
  srimech retry), boost_test (fixture presses every 200 ticks; 150 gave no blows once the arenas
  escalated).
- Swift untouched (rows are opaque in the shell), so `scripts/build-sim.sh` was not needed.

Owed / ideas:
- The AI's "stuck" boost fires about 12 times a fight, mostly in clinches (it counts a shove that
  is going nowhere as stuck). Reads as aggressive; if it looks spammy on the phone, raise
  BOOST_STUCK_TICKS or skip it while touching the opponent.
- `boost` sound file (hook is live, key `boost`).
- A boost glyph for the button (word for now).
- Ring-outs went up (1 -> 5 in 84 fights): dashes carry machines over the edge. Probably good drama;
  watch it.

## C. The BOOST

**Sim** (`Arena/bot/bot.gd`, section BOOST): a recorded input. `boost` is the LEVEL in the input
record; the bot takes the edge (as it does for fire). On the edge, if charged, upright, drive alive
and not disrupted: `BOOST_TICKS` 21 (0.35 s) of

- top speed x (1 + 0.5 x factor) (`speed_factor()`), so the wheel motors are allowed to go faster;
- a central force of 10 m/s^2 x factor x drive condition x total mass along the flat nose (or the
  tail when the stick is more than 135 deg off the nose, the drive's own reverse rule), only while
  the machine is below the raised top speed and (wheeled drives) has a wheel on the floor: no air
  dash. A strafing drive (omni) dashes along the stick;
- full throttle; a stick at rest dashes straight ahead.

Cooldown `BOOST_COOLDOWN_TICKS` 240 (4 s) from the moment it fires. Clocks are simulation ticks (a
hit-stop hold never ages them). Velocity and the nose are read through the physics server's direct
state (the srimech damping's lesson: the node cache lags in a 16-a-frame replay seek).

Per drive factor (`BOOST_FACTORS`, a catalogue `boost_factor` on the drive row wins):
2WD 1.15, omni 1.15, 4WD 1.0, 6WD 0.9, hover 0.85, adaptive tracks 0.75, tracks 0.7, legs 0.6.

Measured (`qa/drives_gauntlet.gd --benches=boost`, wedge/flipper, first version at gain 0.6, hover
1.1; shipped at gain 0.5, hover 0.85 so the peaks are a little lower):

| drive | plain: 0.5 s / peak | boost from standing: 0.5 s / 1.0 s / peak | boost from cruise: peak |
|---|---|---|---|
| 2WD | 0.62 m / 4.0 m/s | 1.90 / 4.06 m / 5.8 | 7.2 |
| 4WD | 0.58 / 3.4 | 1.66 / 3.44 / 5.1 | 5.7 |
| 6WD | 0.56 / 3.1 | 1.52 / 3.08 / 4.6 | 4.7 |
| tracks | 0.54 / 2.5 | 1.20 / 2.42 / 3.5 | 3.5 |
| omni | 0.58 / 3.2 | 1.84 / 3.62 / 5.5 | 5.5 |
| legs | 0.82 / 1.8 | 1.12 / 2.04 / 2.8 | 2.8 |
| hover | 1.18 / 5.2 | 2.10 / 4.46 / 6.8 | 8.3 |
| adaptive tracks | 0.54 / 3.0 | 1.36 / 2.84 / 4.1 | 4.3 |

No run ended off its wheels (up_end 0.98-1.0).

**Replay**: rows are seven wide `[tick, hx, hy, fire, secondary, turn, boost]`
(`FightTypes.replay_row`); a six wide row replays with no boost. Spec updated
(docs/bridge-spec.md). Swift keeps rows opaque, so no Swift change.

**Touch** (`Arena/ui/controls.gd`, section BOOST): a 64 pt disc 126 pt left of FIRE, 12 pt lower
(the thumb rolls off the weapon onto it). Charged: the disc takes the `selectedFill` wash. Pressed or
dashing: the pressed fill. Charging: a gauge ring fills clockwise from the top (a gauge, like the
spin-up ring; no rim, no line accent: design system section 0). Word BOOST (no glyph yet).
Captures: `docs/aaa/img/wave-b/boost/` (ready with the coach up, pressed, charging at ~25 %).

**Pad**: RB (Xbox) / R1 (PlayStation), the right shoulder, under the index finger already on the
fire trigger. The camera zoom moved from the shoulders to the d-pad (up in, down out). Pad hint on
the button's spot: "RB BOOST" / "R1 BOOST" (`hud.gd` `_hint_boost`). Desktop QA key: B.

**Coach**: a fourth callout "BOOST  TAP TO DASH" left of the button, fading on first use; the
weapon callout moved ABOVE the fire button (its old spot is the boost button now), 12 pt clear of
the gas pips.

**Feel**: `FightFx.on_boost(bot_id, is_player)`: an `impact_light` haptic for the player's own dash
and a sound HOOK `boost` (no file yet; AudioMix returns null for an unknown key, so it is silent
until the audio lead adds one to the manifest). Tests never play audio.

**AI** (`Arena/ai/opponent_ai.gd`, section BOOST; edits were permitted): one-tick press when charged,
no rng drawn. Reasons in order: escape (intent ESCAPE, way out within ~37 deg of nose or tail),
stuck (heading >= 0.6, speed < 0.25 m/s for 0.75 s: a pin, a wall edge, a lip), attack (Regional and
up; CLOSE / PIN / SHOVE, 1.1-3.0 m, nose within ~20 deg, weapon readiness >= 0.7 or a ram). BossAI:
THRESHER and ANVIL never dash in (attack presses dropped), only out.

## D. No more stuck

1. **Referee lock-up break** `LOCKUP_S` 8 -> 3 s (fight.gd). Consequence: two machines still inside
   2 m of each other for 3 s are separated, which includes a static wall pin; the AI's own pin hold
   is 3 s (PIN_HOLD_TICKS), so an AI pin is let go at about the same moment. `lockup_breaks` now
   resets per fight (it never did).
2. **UNSTICK** (fight.gd, section UNSTICK, FIGHT and RUMBLE rules only, never the test arena): a
   machine with the stick >= 0.6, planar speed < 0.2 m/s, upright, drive >= 0.5 condition, and NOT
   within pin range + 0.35 m of its opponent nor touching it, for 1.5 s, gets one impulse of
   (1.0 m/s up + 0.8 m/s against its stick) x total mass; the clock restarts. Read only off the
   recorded heading and physics, so replays nudge on the same tick. A dead drive is never nudged (the
   knockout by immobility stands). A pin (opponent within range or touching) is never rescued.
3. **Self-righting**: the kick itself rights a hull in 0.25-0.42 s on every drive (flip bench), so
   the slowness was the waiting: `SRIMECH_COOLDOWN_S` 1.2 -> 0.8, AI presses at 0.6 m/s (was 0.35)
   and retries every 50 ticks x tier (was 90).

## Tests

`Arena/tests/boost_test.gd` (new): row format and back-compat, edge + cooldown (three presses, one
inside the cooldown, fire two), dash distance and peak, unstick vs pin, the 3 s referee break, and
hitstop_test's whole bit-exact matrix (hit-stop, 0.25x, 0.5x, seek) on a script that presses BOOST
every 150 ticks, with the boost / nudge / break counts folded into the compared hash.
`ui_test`: d-pad zoom, RB = BOOST, the fourth coach callout.

## Before / after (weapons gauntlet, 84 matched fights)

Every weapon on its legal hull, AI (National) against plain and weapon opponents (Regional), seeds
11-55, 150 s. Before = e994cd3 (+ the new metrics), after = 5d966a5 (my commits + the escalation
agent's 00056bb stages). The full 160 was stopped at 84 because the machine was shared and slowed to
two minutes a fight; rows were matched one to one (same build, opponent, seed).

| | before | after |
|---|---|---|
| judges' decisions | 73 % | 58 % |
| component kills / KO / ring-outs | 20 / 2 / 1 | 30 / 0 / 5 |
| blows per fight (judged fights) | 17.7 (16.0) | 19.1 (17.4) |
| mean fight length | 131.8 s | 123.5 s |
| stuck_s (still, > 1.5 m from the foe) mean / fights over 5 s | 2.32 s / 16 | 1.26 s / 2 |
| wedged_s (still while driving hard) | 2.25 s | 1.21 s |
| time on its back, subject / opponent | 1.49 / 0.57 s | 1.26 / 0.42 s |
| boosts per fight, subject / opponent | - | 20.8 / 16.3 (attack 710, escape 109, stuck 1037 in total) |
| unstick nudges / referee breaks per fight | - | 0.23 / 1.96 |

Stuck time roughly halves and long stuck spells almost vanish. The escalation agent's stages are in
the after column too, so the judges' share is the pair of changes, not the boost alone.
