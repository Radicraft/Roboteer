# Wave G, agent G1: the shape of a fight

Built 2026-09-16 against `docs/brief-v4-playtest.md` §2 and `docs/wave-g-contracts.md`.
One three minute round with an endgame at two minutes: the arena turns nasty, the lights go
hot, the camera shows you what it has become, the HUD stamps ENDGAME and the phone kicks.

## What the round is now

| | before | after |
|---|---|---|
| Round | 90 s | **180 s** (`FightTypes.FIGHT_DURATION_S`) |
| Phases | none | `open` 0:00–2:00, `endgame` 2:00–3:00 (`ENDGAME_AT_S` 120) |
| Judges: aggression window | 45 s | **90 s** |
| Judges: control window | 15 s | **30 s** |
| Rumble | 90 s | 90 s, unchanged, and it never enters the endgame |
| Side events | own clocks | own clocks, untouched |

The endgame exists for `rules.mode == "fight"` and nothing else.

## The moment, at exactly tick 7200

`fight.gd` `_tick_fight` runs `_enter_endgame()` the first tick `_tick >= ENDGAME_AT_TICKS`,
before anything else that tick reads the arena, so the escalated floor is the floor the
drivers are steered around. In order, as the contract says:

1. `_arena.call("set_phase", PHASE_ENDGAME)`
2. `_camera_rig.call("endgame_reveal")` if it has the method (G4's)
3. `_hud.call("show_endgame_sting")`
4. one heavy haptic through the existing rate limiter (`FightFx.haptics().send("impact_heavy", now)`)
5. `Bridge.send("fight_state", {"state": "fighting", "phase": "endgame"})`, once
6. `phase_changed.emit("endgame")`

**Ticks, not seconds.** `ENDGAME_AT_TICKS` is `round(120 * 60)` and the test is `_tick >=`.
`_fight_time` is a sum of 7200 deltas and lands a hair either side of 120.0; a replay has to
turn on the same tick the fight did, and `_tick` is the only number that is bit-identical.
`fight_phase()` is derived the same way, so the phase on the wire, in the HUD and in the AI
context all agree with the recording. `determinism_test` is green.

`_endgame_done` latches, so a seek, a re-send or a paused frame cannot play the moment twice.
It is cleared in `start_fight`, so every fight (and every replay restart, which goes through
`start_fight`) opens in the open phase.

## The phase on the wire

Every `fight_state` carries `"phase"` — the three sends are `_set_state`, `_set_paused`
(paused/resumed) and `_abandon_fight` — plus the one extra on the endgame tick. Swift
`ArenaHost` publishes `fightPhase: String`, parsed **before** the `FightState` guard, because
`paused` and `resumed` are not members of that enum and fall out of it; the half of the round
they were sent in is still true. It resets to `"open"` at all three fight starts.

`phase_changed` fires exactly twice in a fight: `open` from `_set_state(FIGHTING)`, `endgame`
from the moment. G2 hangs the house bot release on it, G6 the horn and the music cue.

One consequence of the contract's "PHASE_OPEN outside FIGHTING" worth knowing: the `result`
`fight_state` carries `phase: "open"` even for a fight that ended in the endgame, because by
then the state is RESULT. Anything that wants to know how a fight ENDED should read the result,
not the phase. If a screen ever needs "this one went the distance", say so here first.

## Arena escalation

`ArenaBase.set_phase(phase)` / `phase()` / `escalated()`, with the subclass hook `_on_phase`.
Two rules hold everywhere:

- **It latches.** `set_phase("open")` after an endgame does nothing at all. That is what "the
  pit opens and never closes again" means, and it also means a mid-fight pause, a re-send or a
  second call cannot let the floor off.
- **It is a function of the tick.** The one exception is the key-light shift, which is paint
  and runs on the frame clock in `_process`.

| Arena | What the last minute is |
|---|---|
| Yard | the centre spike patch stays risen, no gaps (`_tick_spikes` clamps the height) |
| Grinder | the discs spin at double speed and bite every 15 ticks instead of 30 |
| Drop Zone | the pit opens on the tick and never closes: the 15 s window and `REOPEN_S` are off |
| Furnace | jets on a 4 s period, north and south exactly half a period apart, and the belt at double speed |
| Crush | each ram's cycle halved (floored at the stroke plus a second) |
| Coliseum | all of the above it has, plus the two floor discs at double angular velocity |

Lights: `ENDGAME_KEY_TINT` (a warm multiplier on the arena's own key colour, so each arena
keeps its cast) and `ENDGAME_KEY_ENERGY` 1.35, cross-faded over `LIGHT_SHIFT_S` 0.6 s from the
LIVE key values — read live because `GraphicsQuality` may already have pulled the energy down
for this tier and the shift has to start from what is actually on screen.

Two judgement calls worth flagging:

- **The Grinder.** Brief §2 says "both flank grinders run continuously", which they already
  did in the open phase, so as written it was not an escalation at all. It now spins up: 2 Hz
  → 4 Hz on the bite, discs at double speed. Measured note from Stage 5 still stands (6 Hz
  took five of eleven condition points off a parked bot in three seconds); 4 Hz is about 3.3
  points in three seconds, and only while you are parked on a disc. If that reads as too much
  on the phone, `ArenaBase.ENDGAME_RATE` is the one dial.
- **The Furnace.** A 4 s period against a 2 s burn, with the south wall put exactly half a
  period behind the north, means one wall or the other is alight on every tick and never both.
  The middle of the floor and the belt lane stay clear. The seeded north phase is kept, so the
  timeline is still the seed's.

## The HUD

- The clock now counts down from `3:00`. The `set_time_left` formatter already handled minutes;
  only the pre-fight placeholder (which read `1:30`) had to change.
- `show_endgame_sting()`: `ENDGAME`, 72 pt scaled, outlined, centred, a 0.20 s scale-in, held,
  then a 0.25 s fade — 1.5 s in all. It builds its own label on demand rather than joining
  `_build()` / `_relayout()`, so the sting owns itself and the shared layout pass (which G2 and
  G6 are also editing) has nothing of it to know about. `endgame_sting_visible()` and
  `hide_endgame_sting()` are there for the tests. Wave V §7 replaces the drawing with the
  broadcast sting; the name stays.

## Swift

- `FightConfigFixture.fightDurationS = 180`, used for mode `fight` only. Rumble's dictionary
  still says 90. The Stage 1 spike fixture's `duration_s` went to 180 as well: it carries no
  `mode`, so the arena reads it as a fight, and a QA fight that belled at 90 s with no endgame
  would have been a second, silently different, fight shape.
- `CareerFightView.fightDurationS` was already 180 when I got there (G5 had landed it).
- `ArenaHost.fightPhase`, reset at each of the three fight starts.
- **Not changed: `ArenaHost.startEvent(clockSeconds: Int = 90)`.** The contracts file said to
  make it 180. It is the default argument of a SIDE EVENT's clock, and brief §2 and §10 item 3
  both say the side events are untouched; every real caller passes `EventCatalogue.clockSeconds`
  anyway. The amendment is written into `docs/wave-g-contracts.md`.
- `Arena/fight/fixtures/stage3_config.json` is left at 90: it is the arena's own desktop QA
  autostart fixture and several tests read it as an oracle.

## Tests

`sh scripts/test-arena.sh rules_test.gd arenas_test.gd fight_shape_test.gd determinism_test.gd`

- **`Arena/tests/fight_shape_test.gd` (new, 34 checks).** The constants; a fight with no
  `rules.duration_s` runs 180 s; the phase is open on tick 7199 and endgame on tick 7200;
  `phase_changed` fires exactly twice; exactly one `{fighting, endgame}` bridge send, and it
  does not repeat over the next 120 ticks; every `fight_state` carries a phase; the arena
  escalated and cannot be put back; the HUD stamped ENDGAME; and a Rumble at 2:10 is still
  open, never escalates its arena and never sends an endgame state.
  The clock is driven by hand (`_tick` set near the mark, `_tick_fight` called directly)
  because with no physics stepping both machines are immobile and the knockout rule would end
  the fight at ten seconds — and the tick is exactly what is under test.
- **`arenas_test.gd`** gained `_check_endgame_escalation`: all six arenas expose
  `set_phase`/`phase`, start open, escalate, shift the key light to hot inside 0.7 s, refuse to
  go back, and are still escalated a minute later — plus the per-arena assertion in the table
  above (spikes never down for ten seconds; the cut rate halved; the pit open for ninety
  seconds with no tick shut; the belt doubled and no cold tick in twelve seconds; both ram
  cycles halved; both disc rates doubled). 154 checks.
- **`rules_test.gd`** gained `_test_three_minute_round`: 45 s of aggression is now 5 and not
  10, a whole round still scores 10, and a real fight run to the bell with neither machine
  driven produces `outcome.type == "judges"` at `duration_s` 180 on two identical blank cards.
  Its three older judge fixtures were rescaled to the constants (they had 45.0 and 15.0 written
  into them as literals, which is why they now read `FightTypes.JUDGE_*` instead).
- **`determinism_test.gd`** green, unchanged: three fights and a replay, bit-identical.

Whole suite at the end of the wave: `sh scripts/test-arena.sh` → **PASS, 25 test files, 0
failures**. `sh scripts/build-device.sh` → **BUILD SUCCEEDED** (Release, device).

## What I could not verify without a phone

- The endgame **feel**: whether the horn-less version of the moment already reads as
  unmissable, whether 0.6 s of light shift is long enough to notice, and whether the ENDGAME
  stamp is big enough at 72 pt on a 6.3" screen.
- The heavy haptic. The Simulator has no engine and the headless test only counts the message.
- Whether the last minute is fun or punishing. Six arenas at double rate is a lot of floor; the
  Furnace's always-alight wall and the Grinder's 4 Hz bite are the two most likely to be too
  much, and both are one constant each.
- Whether three minutes is the right length. It is four times the old fight in wall-clock terms
  once the endgame slows everything down, and only the owner's thumb can say.

## Left undone

- No horn, no music cue: G6's, hung off `phase_changed`.
- No camera work: `endgame_reveal()` is G4's and is called if it exists.
- The zone stripes going red at the endgame is G2's (`CornerZone.set_zone_state("released")`),
  driven from the same signal.
- The ENDGAME stamp is a plain label. Wave V restyles it.
