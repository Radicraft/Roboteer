# Wave G, agent G6: commentary and cues

Brief v4 (`docs/brief-v4-playtest.md`) §10 item 2, and the G6 rows of
`docs/wave-g-contracts.md`. Built 2026-09-16.

> **the endgame gets its own music cue** and the horn, and **the ticker carries
> commentary**: short capitals for the moments that matter ("BIG HIT", "PINNED",
> "IN THE ZONE", "PIT OPEN", "HOUSE BOT OUT", "FLIPPED", "SPINNING UP"), driven by
> rules events, never more than one every 2 s, never during the countdown.

Three parts: the line on the HUD, the script that decides what to say, and two new
sounds with the mixer switch that plays them. Wave V turns the line into the broadcast
ticker (§7); nothing below knows about scrolling, which is the point.

---

## 1. What was built

| File | What |
|---|---|
| `Arena/ui/hud.gd` (commentary section) | `push_commentary()`, the queue, the hold and fade, `commentary_step()` |
| `Arena/fight/commentary.gd` (new) | `FightCommentary`: rules events -> the seven lines, and the endgame cue trigger |
| `Arena/fight/fight.gd` (`_commentary_hooks` section) | seven guarded one-liners at event points that already existed |
| `Arena/fx/audio_mix.gd` | the two cues in the catalogue, `play_endgame_horn()`, `set_endgame()` |
| `scripts/gen-sounds.py` | `endgame_horn()` and `endgame_drone_loop()` |
| `Arena/audio/endgame_horn.wav`, `endgame_drone_loop.wav` (+ `.import`) | the cues |
| `Arena/tests/commentary_test.gd` (new) | 81 checks |
| `Arena/tests/audio_test.gd` | one line: the new loop added to `EXPECTED_LOOPS` |
| `Arena/tests/_g6_severity_probe.gd` (new, `_` = not in the suite) | the measurement the BIG HIT threshold comes from, and an end to end print of every line a real fight says |

---

## 2. The line on the HUD

`push_commentary(text)` queues; `commentary_step(delta)` runs the timeline and is called
from the HUD's own `_process`, so it needs nothing from `fight.gd` to keep moving. Hold
1.6 s, fade 0.25 s, one line every 2.0 s, and a queued line older than 2.0 s is **dropped
rather than shown late**.

Three decisions worth writing down.

**Dropping is the feature, not a compromise.** Commentary is about what is happening.
"BIG HIT" four seconds after the hit is a lie, and a queue that never drops turns ten
scrappy seconds into a minute of backlog that is still running when the bell goes. The
test asserts the third of three simultaneous lines never appears at all.

**The order inside the step is promote, then prune.** The other way round, a line queued
directly behind another waits exactly the 2 s gap and is then thrown away on the very
frame it was due, because its age and the elapsed gap are the same accumulated float.
This is the kind of thing that works for a week and then eats the endgame's second line.

**Where it sits.** The contract says "above the names". Today the names are a top-left
band under the clock, so there is nothing above them but the notch; the line is a full
width centred strap on the third row (under the clock and the PAUSED mark), clear of the
knockout count and of G1's ENDGAME sting in the middle. It is built on demand and places
itself (the same pattern G1 used for the sting), so it adds nothing to the shared
`_relayout()` pass and cannot collide with G1's or G2's edits to it. When wave V moves
the names to lower thirds at the bottom, this strap becomes the ticker above them.

Never during the countdown: `push_commentary` drops the line outright if the HUD's phase
is `COACH_COUNTDOWN`. Not queued for later, dropped. There is already a 96 pt "3" in the
middle of the screen and a coach callout on every control.

---

## 3. What makes each line fire

| Line | Trigger | Where it is hooked |
|---|---|---|
| BIG HIT | a damage event at or above `FightFx.IMPACT_HEAVY_SEVERITY` (0.30), or any blow that detaches a part | the `_pending_fx` drain in `_update_presentation` |
| PINNED | `Rules.is_pinned` true and **held for 0.6 s** | the pin check inside `_check_win_conditions` |
| IN THE ZONE | the player's machine enters the corner zone | G2's `_update_zone_warning` edge |
| PIT OPEN | the endgame phase, in the Drop Zone only | `phase_changed` |
| HOUSE BOT OUT | the endgame release, **and** the Stage 5 inactivity entrance | `_release_house_bot`, `_send_in_enforcer` |
| FLIPPED | either machine's inversion, rising edge | the inversion check, read per presentation frame |
| SPINNING UP | a spinner crossing 0.98 readiness, re-armed only below `OpponentAI.READY_DROP` | the weapon readiness already read for the FX |

Plus a per-line repeat window on top of the HUD's 2 s rule: BIG HIT 6 s, PINNED 8 s,
IN THE ZONE 8 s, FLIPPED 5 s, SPINNING UP 12 s, and PIT OPEN / HOUSE BOT OUT once a
fight. The HUD's rule is about the screen; this one is about the writing. "BIG HIT"
three times in six seconds is not commentary, it is a stuck key.

### The BIG HIT threshold is measured, not guessed

`Arena/tests/_g6_severity_probe.gd` histograms every `damage_event` severity over whole
AI vs AI fights. Measured 2026-09-16:

| matchup | events | max severity | p90 | BIG HIT lines |
|---|---|---|---|---|
| flipper vs flipper (the fixture) | 52 | 0.126 | 0.111 | 0 |
| axe vs axe | 24 | 0.111 | 0.111 | 0 |
| spinner vs spinner | 4 | 1.000 | 1.000 | 2 |
| spinner vs flipper, 66 s | 11 | 1.000 | - | 4 |

So a flipper fight gets no BIG HIT at all, and that is right: a flipper fight's damage
really is light, its drama is the flip, and FLIPPED is its own line. A spinner putting a
bar through an armour plate is the hit worth shouting about. The threshold is
`FightFx.IMPACT_HEAVY_SEVERITY` **by reference, not by copy**, so the line can never
disagree with the sample the player just heard. If the owner wants more of them, that is
the one dial and nothing else moves.

### Rates measured in real fights (the whole chain, through fight.gd)

- spinner vs flipper, Drop Zone, THRESHER: 10 lines in a 66 s fight (SPINNING UP x4,
  BIG HIT x4, PINNED x2), about one every 6.6 s.
- flipper vs flipper, Drop Zone, THRESHER, full 180 s: 20 lines, about one every 9 s,
  with `HOUSE BOT OUT` and `PIT OPEN` both at exactly 120.00 s.

Nothing in either run came close to the 2 s ceiling except the endgame pair, which is
exactly the moment the queue exists for.

---

## 4. The endgame cues

**`endgame_horn.wav`**, 1.80 s, mono, -3.00 dBFS peak, UI bus at -3 dB (beside the bell,
out of the arena reverb, cap 1: the round only turns once).

Built the way an air horn works, not as a synth chord: a 1/k harmonic stack soft clipped
into a reed buzz, through two broad bore formants (380-3200 Hz and 700-1500 Hz), with a
7 % pitch scoop over the first 25 ms as the air column catches, two tones a fourth apart
(F3 and A#3) so they beat against each other, the reservoir sagging 14 % after the first
blast, and the valve's own metal tick under the attack.

Measured: **8.6 % of its energy below 200 Hz**, 28.3 % below 400 Hz. That is deliberate.
The formants cut the fundamentals, which is both what a real horn sounds like and what
survives a phone speaker (`docs/audio-notes.md` §4).

**`endgame_drone_loop.wav`**, 4.00 s, mono, seamless, PCM, Music bus at -22 dB. A drone
on a fifth with one pulse a second: a heartbeat under the crowd, not music on top of it.
It is the first thing ever to play on the Music bus, which agent AU wired and left empty
for exactly this.

> **The first build of it was wrong and the measurement caught it.** Written at 55 Hz it
> measured 98.3 % of its energy below 200 Hz: correct for a drone, inaudible on the
> device, an "endgame music cue" nobody would ever hear. Rebuilt at 110 Hz with the
> weight on the 220 / 330 / 440 partials and the pulse as a 200-1500 Hz swell: now 62 %
> below 200 Hz and 38 % in the band a phone can actually reproduce, with the 55 Hz
> octave still underneath for headphones.

**The ambience gets hotter rather than getting a second recording.** `AudioMix.set_endgame(true)`
lifts the Ambience bus by `AMBIENCE_HOT_DB` (+4 dB, about a third louder) and starts the
drone; `set_endgame(false)` puts back **the level it found**, not a number from this
file, because the player's settings write that bus too. `stop_all()` calls it, so a fight
cannot leave the crowd 4 dB hot into the next one. Verified numerically: -14.00 dB ->
-10.00 dB -> -14.00 dB.

> **One bug found while writing that, worth recording.** The lift is a setting on a
> GLOBAL bus, but `AudioMix` is not global: a new fight builds a new world, a new FX
> subtree and a new `AudioMix`, and frees the old one. The first version handed the
> level back only through `set_endgame(false)` and `stop_all()`, neither of which is
> called when a world is torn down — so a fight that reached its endgame would have left
> the crowd 4 dB hot into the next fight, 8 dB into the one after, and so on, and the
> new mixer's `_ambience_db_before` would have recorded the drifted value as the
> "ordinary" level. `AudioMix._exit_tree()` now hands the bus back when the node goes.
> The test frees a mixer mid-endgame and checks the level is back at -14.00, and the
> real two-fight path was run in one process to confirm it: -14.00 -> the cue -> -10.00
> (horn 1 voice, drone running) -> a second `start_fight` -> -14.00, no drone, endgame
> inactive.

Seams, from `audio_test.gd` against the bytes Godot actually imported:
`endgame_drone_loop.wav ch0 wrap 97, max inner 1369` (seamless), imported as 16-bit PCM.

The countdown and the bell are untouched.

### Regenerating

`gen-sounds.py` uses one seeded generator consumed in call order, so the two new writes
are at the **end** of `build_all()` on purpose: every one of the 28 existing files is
byte identical after the change (checked by md5 before and after). The usual sequence:

```
python3 scripts/gen-sounds.py
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
python3 scripts/gen-sounds.py --patch-imports
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
```

---

## 5. Determinism

Commentary and audio are presentation (spec §7) and the discipline is enforced three ways:

1. **Every hook records a fact and returns.** The ones inside the physics tick
   (`_commentary_pin`) write one array slot; all the timing, the edge detection and the
   lines themselves happen in `step()`, on the presentation frame.
2. **No randomness, no wall clock.** `commentary_test.gd` reads `commentary.gd`'s own
   source back and fails if it contains `randf(`, `randi(`, `randf_range(`,
   `randi_range(`, `Time.get_ticks_msec`, `Time.get_unix_time` or `OS.get_`, and if it
   mentions `_bots`, `apply_input`, `set_meta`, `queue_free` or `_rng`. It talks to the
   HUD and to the audio director and to nothing else, so there is nothing of the
   simulation it could write into.
3. **`determinism_test` is green** (42 checks), which is the actual proof: the same seed
   and the same input log re-simulate to the same result with all of this in place.

The audio director's own generator (`AudioMix._rng`, seeded with a constant) is what the
variant picker uses and it was already separate from the fight's rng; neither new cue has
variants anyway.

---

## 6. Tests

```
sh scripts/test-arena.sh commentary_test.gd ui_test.gd determinism_test.gd audio_test.gd
```

- `commentary_test.gd` (new): **81 checks, 0 failures**. Every trigger fires its own line
  once; the light hit says nothing and the detaching blow does; the momentary pin says
  nothing and the held one does; all seven of the brief's lines are reachable; the HUD
  shows one line every 2 s and drops the stale third; nothing during the countdown; the
  horn starts at the endgame and **not** before or on the open phase; the drone really
  plays, on the Music bus, at its written trim; the Ambience bus moves by exactly
  `AMBIENCE_HOT_DB` and comes back; a commentary with no audio director still says its
  lines; and the line's own rect really sits below the names row and above the
  knockout count, because "it looks fine" is not a headless answer.
- `audio_test.gd`: 42 checks, 0 failures, now walking 30 files and 8 loops.
- `ui_test.gd`: 298 checks, 0 failures. `determinism_test.gd`: 42 checks, 0 failures.
- Full suite: green.

**No audio was played on this Mac.** Everything above is a number: the file's peak,
length and spectrum from the wav, the import's loop mode and codec from what Godot
wrote, the voice's `playing` flag and bus from the mixer, and the bus level from
`AudioServer`. The owner was working here.

---

## 7. What is owed, and what only a phone can answer

1. **Nobody has heard the horn or the drone.** Every judgement in §4 is from spectra and
   peak measurements. The owner's ear is the gate. If the horn is too much, its trim is
   one number (`AudioMix.LEVELS["endgame_horn"]`, -3 dB); the drone is `-22.0`; the
   crowd's lift is `AudioMix.AMBIENCE_HOT_DB`, +4.
2. **The drone is synthesised, like everything else** (`docs/audio-notes.md` §6). A
   licensed replacement drops in by file name and needs no code change. What to source:
   horn = a real air horn, one take with the valve in it, 1.8 s; drone = a low room tone
   or engine bed, 4 s, genuinely seamless.
3. **No ducking.** The drone does not get out of the way of the bell or a heavy hit
   (`audio-notes.md` §8 weakness 4, unchanged). At -22 dB it should not need to.
4. **IN THE ZONE has never fired in a measured fight**, because the AI routes around the
   corner zone, which is G3 working as intended. It fires in the unit test and it will
   fire the first time the owner drives into the corner; that is the one line whose real
   rate is still unknown.
5. **Line placement is a wave G placeholder.** It is a plain centred strap; §7 makes it
   the ticker.
