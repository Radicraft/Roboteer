# Wave F, agent F2: the fight's sound

The owner played the wave G build on his iPhone and said:

> **"I can't hear the crowd properly, there are no movement noises"**

Both halves were literally true, and neither was a taste problem. This is what was
wrong, what it measures at now, and the one-number trims for the phone test.

**No audio was played on this Mac.** Every number below is from the PCM, from the
mixer's own bookkeeping, or from `AudioServer`. The owner was working here.

---

## 0. The two findings

### "There are no movement noises" — there were none. At all.

`FightFx.set_motor_state(bot_id, throttle)` has existed since Stage 3, is correct, and
**nothing in the game has ever called it**. Grep the repo: the only callers are
`Arena/tests/fx_test.gd`. Two machines have been driving round a steel shed in silence
since Stage 3, and the unit test passed the whole time because it called the function
itself.

So the fix is not another method for `fight.gd` to remember: `Arena/fx/machine_audio.gd`
is a node under `FightFx` that **finds the machines itself** (they are `World/Bots`, FX
is `World/FX`) and reads their drive state every presentation frame. It cannot fall out
of the wiring, because there is no wiring to fall out of.

### "I can't hear the crowd" — measured, it was 41 dB down

| | old | now |
|---|---|---|
| file RMS | -21.00 dBFS | **-17.15** |
| energy above 2 kHz | 2.9 % | **19.6 %** |
| energy in 700 Hz - 8 kHz (what a phone reproduces) | 22 % | **65.5 %** |
| `LEVELS["crowd_ambience_loop"]` | -6 dB | **-4 dB** |
| Ambience bus | -14 dB | **-10 dB** |
| **loudest 200 ms at the master** | **-35.5 dBFS** | **-29.5 dBFS** |
| whole-file loudness at the master | -41.0 dBFS | **-31.1 dBFS** |

Against a heavy impact at -15.9 dBFS. A crowd 25 dB under the fight, with 3 % of its
energy in the band a phone speaker can move air in, is a crowd nobody was ever going to
hear. **Roughly 10 dB of that is level and the rest is placement**; both had to move.

### And a third thing, found while checking the mix

`Arena/fx/collect_audio.gd` put its six collect voices on the **Master** bus at 0 dB —
the one place in the game that skips both the SFX bus and `AudioMix.LEVELS`. The tick is
normalised to -3 dBFS like every other file, so each collect was arriving **13 dB hotter
than the -13 dB trim the catalogue says it has**: second only to a heavy impact, and
louder than the bell. A 120-bolt shower sat on the master limiter and pulled everything
else — including the crowd — down with it. Two lines, and it is now asserted in
`audio_test.gd` so it cannot drift back.

---

## 1. Every level, in dB

Measured from the source wavs and the live tables (`AudioMix.LEVELS`, `BUSES`,
`audio_bus_layout.tres`). `pk200` is the loudest 200 ms window, which is the measure
that matters: every file is normalised to -3 dBFS peak, so **a peak comparison says
every sound in the game is the same size**. That is exactly how the horn ended up
quieter than the bell it is meant to out-announce.

```
group                  bus         peak   pk200     rms |   trim    bus |  MASTER  M-pk200
ram_crush              SFX        -3.00  -13.00  -19.02 |   -2.0    0.0 |   -5.00   -15.00
impact_heavy           SFX        -3.00  -12.94  -15.76 |   -3.0    0.0 |   -6.00   -15.94
ram_hit                SFX        -3.00  -12.99  -16.58 |   -5.0    0.0 |   -8.00   -17.99
pit_open               SFX        -3.00  -13.66  -16.73 |   -5.0    0.0 |   -8.00   -18.66
axe_hit                SFX        -3.00  -16.46  -20.54 |   -4.0    0.0 |   -7.00   -20.46
bell                   UI         -3.00  -14.43  -22.79 |   -4.0   -3.0 |  -10.00   -21.43
panel_off              SFX        -3.00  -15.93  -20.60 |   -6.0    0.0 |   -9.00   -21.93
endgame_horn           UI         -3.00  -17.99  -21.18 |   -1.0   -3.0 |   -7.00   -21.99
spikes                 SFX        -3.00  -14.68  -17.43 |   -8.0    0.0 |  -11.00   -22.68
scrape_loop      *     SFX        -3.00  -15.06  -16.05 |   -8.0    0.0 |  -11.00   -23.06
skid_loop        *     SFX        -3.00  -16.89  -17.67 |   -7.0    0.0 |  -10.00   -23.89
flipper_fire           SFX        -3.00  -17.43  -20.37 |   -7.0    0.0 |  -10.00   -24.43
flame_jet              SFX        -3.00  -15.96  -17.93 |   -9.0    0.0 |  -12.00   -24.96
flame_loop       !     SFX        -3.00   -7.20   -7.90 |  -18.0    0.0 |  -21.00   -25.20
crowd_roar       *     Ambience   -3.00  -12.29  -14.68 |   -3.0  -10.0 |  -16.00   -25.29
wheel_off              SFX        -3.00  -20.75  -25.24 |   -5.0    0.0 |   -8.00   -25.75
chassis_thud     *     SFX        -3.00  -20.26  -23.43 |   -6.0    0.0 |   -9.00   -26.26
axe_swing              SFX        -3.00  -14.41  -16.51 |  -12.0    0.0 |  -15.00   -26.41
crowd_swell      *     Ambience   -3.00  -12.54  -15.03 |   -4.0  -10.0 |  -17.00   -26.54
spin_up_loop           SFX        -3.00   -9.02   -9.12 |  -18.0    0.0 |  -21.00   -27.02
crusher_clamp          SFX        -3.00  -18.16  -22.89 |   -9.0    0.0 |  -12.00   -27.16
ko_tick                UI         -3.00  -18.98  -18.98 |   -7.0   -3.0 |  -13.00   -28.98
impact_light           SFX        -3.00  -20.12  -20.12 |   -9.0    0.0 |  -12.00   -29.12
crowd_ambience   !     Ambience   -3.00  -15.51  -17.15 |   -4.0  -10.0 |  -17.00   -29.51
roll_wheel_loop  *     SFX        -3.00  -14.82  -15.66 |  -15.0    0.0 |  -18.00   -29.82
grinder_loop           SFX        -3.00  -11.09  -14.47 |  -19.0    0.0 |  -22.00   -30.09
track_clatter    *     SFX        -3.00  -15.22  -16.06 |  -15.0    0.0 |  -18.00   -30.22
roll_omni_loop   *     SFX        -3.00  -17.39  -18.34 |  -13.0    0.0 |  -16.00   -30.39
drive_whine_loop *     SFX        -3.00  -10.87  -11.41 |  -20.0    0.0 |  -23.00   -30.87
motor_loop       x     SFX        -3.00  -11.16  -11.52 |  -20.0    0.0 |  -23.00   -31.16
bolt_collect     !     SFX        -3.00  -18.35  -18.35 |  -13.0    0.0 |  -16.00   -31.35
saw_cut_loop           SFX        -3.00  -15.45  -15.80 |  -16.0    0.0 |  -19.00   -31.45
countdown_tick         UI         -3.00  -21.24  -21.24 |   -8.0   -3.0 |  -14.00   -32.24
disc_spin_loop         SFX        -3.00  -12.71  -13.38 |  -20.0    0.0 |  -23.00   -32.71
endgame_drone_loop     Music      -3.00  -10.81  -11.60 |  -22.0   -4.0 |  -29.00   -36.81

*  new in wave F        !  changed in wave F        x  superseded, nothing calls it
```

### The buses

```
Master   0 dB   AudioEffectHardLimiter, ceiling -0.8 dB, release 120 ms
Music   -4 dB   the endgame drone
SFX      0 dB   AudioEffectReverb, 12 % wet     everything the fight does
Ambience -10 dB (was -14)                       the crowd bed and its reactions
UI      -3 dB                                   countdown, KO count, bell, horn
```

### Three levels that changed for a measured reason, not a taste one

1. **Ambience -14 -> -10 dB**, with `LEVELS["crowd_ambience_loop"]` -6 -> -4. See §0.
2. **`endgame_horn` -3 -> -1 dB.** G6 wrote that the horn is "the loudest announcement
   after the bell". Measured, it was not: its loudest 200 ms reached -24.0 dBFS against
   the bell's -21.4, because a horn is a sustained tone with a low crest factor and a
   bell is a transient with a high one, and both files are normalised to the same peak.
   At -1 dB the sentence is true (-22.0) and it is still under the bell.
3. **`flame_loop` -15 -> -18 dB.** At -15 this was the fourth loudest thing in the game
   and **0.2 dB hotter than the horn** it would have had to be heard over in the Furnace.
   Its file RMS is -7.9 dBFS, the hottest in the catalogue: a trim chosen on peak was
   always going to land it too loud. It runs for a whole round, so it matters.

### AMBIENCE_HOT_DB 4 -> 3

G6 chose +4 dB against a bed whose loudest 200 ms reached -35 dBFS. That bed is now
10 dB hotter, so +3 is the same size of step it was meant to be.

---

## 2. The movement layer

`Arena/fx/machine_audio.gd`. Five sounds per machine, each from a different physical
cause, all positional (`AudioStreamPlayer3D`, the mixer's existing pooled/loop voices),
all presentation: it only ever **reads** velocity, the last input and the drive's
catalogue numbers, and it runs in `FightFx._process`, outside the physics tick.
`determinism_test.gd` is green with all of it in place.

| | sound | driven by |
|---|---|---|
| whine | `drive_whine_loop.wav` | pitch from road speed (45 % throttle), level from throttle |
| roll | `roll_wheel_loop` / `track_clatter_loop` / `roll_omni_loop` | road speed |
| skid | `skid_loop.wav` | scrub, measured and commanded |
| scrape | `scrape_loop.wav` | hull against a wall, or on its back |
| thud | `chassis_thud_1..3.wav` | landing after a flip or a throw |

### Pitch is the shaft; level is the current

The one decision worth arguing about. A single throttle-driven parameter has a machine
**screaming at full revs while pinned against the boards going nowhere**. So pitch
follows road speed (with 45 % of the throttle mixed in, because wheels really do spin up
when they lose the floor) and level follows throttle. A machine flat out against a wall
is therefore loud and low — it bogs down, which is what a real one does. Measured in a
real fight the whine moves over 1.10 - 1.69 in pitch and -20 to -36 dB in level, where
the first build sat pinned at 1.75 - 1.80 whatever was happening.

### Per drive, and why they are not one sound with a filter on it

| drive | whine pitch | whine dB | roll | roll pitch | skid gain |
|---|---|---|---|---|---|
| 2wd | 1.10 - 2.00 | -20 - 0 | tyre | 0.85 - 1.60 | 1.25 |
| 4wd | 1.00 - 1.80 | -20 - 0 | tyre | 0.80 - 1.45 | 1.00 |
| 6wd | 0.88 - 1.52 | -18 - +1.5 | tyre | 0.72 - 1.25 | 0.80 |
| tracks | 0.80 - 1.34 | -18 - 0 | **clatter** | 0.70 - 1.30 | 0.70 |
| omni | 1.25 - 2.10 | -20 - -1 | **rollers** | 0.95 - 1.70 | 0.85 |

Tracks get their own file because a tracked machine's noise is the **links**: an impulse
train at the road speed, not a tyre pitched down. An omni gets its own because its tyre
is a ring of little free rollers, so it patters where a tyre rolls. The skid gains come
from the catalogue `traction` (2WD 0.8 lets go, tracks 1.8 never do).

### The skid has two causes and the louder wins

1. **The slip it is doing**: sideways velocity (a wheel cannot go sideways, so all of it
   is scrub — except an omni, whose whole reason to exist is that its rollers can) plus
   `yaw_rate * track_half`, which is the scrub two sides must do to yaw at all.
2. **The slip being asked for**: the stick that far off the nose at that much throttle.
   This fires on the frame the stick goes over, ahead of the physics — "the heading
   changes faster than the drive can follow". Past `DriveBase.REVERSE_ANGLE` (135°) it
   does not count, because there the drive backs toward the stick instead of spinning
   for it, and backing up is not a scrub.
3. Plus a floor for a **pivot**: yawing hard while going nowhere is both sides scrubbing.

> **Measured and retuned.** The first build floored the skid at 0.55 m/s of scrub and it
> was audible on **60 % of frames**, because skid steering is always scrubbing a little:
> a 4WD cannot change direction without it. At 0.90 m/s the loop is what it is meant to
> be — the moment the machine loses the back end — and an ordinary turn is under it.

### The scrape had to learn a wall from the floor

The first build called any chassis contact with arena geometry a scrape, reasoning that
the hull rides `clearance_front` (0.04 m) above the deck. Measured in a real fight that
ran the scrape at **near full level on 55 % of frames**: a wedge is *supposed* to drag
its front lip along the floor, and so do a pyramid and a long-low. A constant grind is
worse than no grind.

`ArenaBase` puts floor slabs at `y = -FLOOR_THICKNESS/2` and every wall at
`y = wall_height/2`, so a colliding body whose own origin is above the wheels
(`WALL_MIN_Y` 0.15) is upright geometry — a wall, a pillar, a cage — and anything at or
under the deck is the floor. The floor still scrapes in the one case it should: **on its
back**, where the whole hull is dragging rather than a designed lip.

Result, same fight: 1671 scrape frames -> **63**.

### Voice budget, so a Rumble cannot blow it

- `MAX_MACHINES` 4 (a Rumble is three; the fourth is for an enforcer or house bot).
- Whine and roll are **always on** per machine and only ever re-pointed, never
  restarted, so going on and off the throttle makes no click.
- Skid and scrape are started on demand, held 0.45 s when they go quiet (a stuttering
  skid must not restart, which is a click per stutter) and then freed.
- `MAX_TRANSIENT_LOOPS` 4 across the whole arena. Measured with three machines all
  sliding at once: **3 transient loops**, 9 machine loops total.
- `chassis_thud` caps at 3 in `AudioMix.CAPS`. Forty landings in one frame leave 3.

### Measured in a real fight

`Arena/tests/_f2_movement_probe.gd` (leading underscore, so the suite skips it) boots a
real fight and prints what the mixer is actually playing. Flipper vs flipper, Drop Zone,
25 s:

```
at 3 s: 2 machines found, loops: whine+roll for player-1 and ai-1
[  4.0 s] player-1 thr 1.00 spd 2.61 m/s whine 1.68 @ -21.0 dB skid 0.00 scr 0.00
[ 10.0 s] player-1 thr 1.00 spd 1.31 m/s whine 1.53 @ -20.0 dB skid 0.09 scr 0.00
[ 18.0 s] player-1 thr 1.00 spd 0.16 m/s whine 1.37 @ -20.8 dB skid 0.05 scr 0.00
[ 26.0 s] ai-1     thr 0.00 spd 1.22 m/s whine 1.19 @ -32.0 dB skid 0.37 scr 0.32
10 landings, 1365 skid frames, 64 scrape frames, Ambience -10.00 dB, crowd loop running
```

Ten landings in 25 s is a flipper fight doing what a flipper fight does. If it is too
busy on the phone, `MachineAudio.LAND_MIN_MS` (1.40 m/s) is the dial.

---

## 3. The crowd

### The bed, rebuilt

The murmur is unchanged **in kind** — band-limited noise whose only movement is slow
amplitude modulation, no formant motion, nothing above a 4 Hz envelope, so it is
structurally incapable of containing words (`docs/audio-notes.md` §3) — and changed in
**placement and density**:

- the murmur band moved from 200-1800 Hz to 240-2600 Hz, with hall air out to 9 kHz;
- **a clap field went over it**, about 9 claps a second a side, swelling with the bed.
  A crowd's audible signature on a small speaker is hands, not voices, and the old bed
  had 2.9 % of its energy above 2 kHz;
- the whole bed is soft-clipped at the last few percent, so normalising to -3 dBFS peak
  is not set by two stray claps: RMS -21.00 -> **-17.15 dBFS**.

Claps are broadband transients, which is the furthest thing there is from speech-shaped
content, so the no-recognisable-words guarantee is if anything stronger than before.
Still exactly periodic (frequency-domain noise, whole numbers of cycles per loop, clap
kernels placed with a wrap, circular hall): measured wrap step 0.010 against a largest
interior step of 0.170.

### The reactions

Three new one-shots on the Ambience bus, same hall, same fader: `crowd_swell_1/2.wav`
(2.2 / 2.6 s, a variant pair) and `crowd_roar.wav` (3.4 s). All three import as **PCM,
not QOA** — a transient-dense broadband file is the other case QOA smears, and it also
lets `audio_test.gd` measure their loudness off the imported bytes.

| moment | cue | gap | hooked at |
|---|---|---|---|
| BIG HIT | swell | 4.5 s | `FightCommentary._say()` |
| FLIPPED | swell, pitch 0.94 | 4.0 s | `FightCommentary._say()` |
| KO count | roar, -2 dB | 6.0 s | `FightFx.on_ko_tick()` |
| the endgame | roar, pitch 0.98 | 6.0 s | `AudioMix.set_endgame(true)` |

A flip is made bigger than a hit by **dropping the pitch, not by adding dB**: a reaction's
`db` may never take it over its written trim, because that trim is what keeps the whole
crowd under the bell and the horn.

**The hook is one line in `commentary.gd`, in `_say()`**, and it is the only line of
that file wave F touches. The crowd reacts at the same instants the ticker does, off the
same edge detection G6 already built, so the roar and the caption can never disagree
about what just happened. The audio director decides *which* lines earn a reaction
(`AudioMix.SWELL_FOR_LINE`: BIG HIT and FLIPPED, nothing else) and how often, so no
policy lives in the commentary. PINNED, SPINNING UP and IN THE ZONE say nothing: a crowd
that roars at every caption is noise, not an audience.

> Note: `FightCommentary.enabled` is false in the test arena, in a Rumble and in the side
> events, so those get the bed and no reactions. That is G6's switch and wave F did not
> change it; the KO roar and the endgame roar do not go through it.

### The duck, and why it is on the voices and not the bus

`docs/audio-notes.md` §8 weakness 4 asked for a sidechain on Ambience keyed off SFX.
Godot has no sidechain, so `AudioMix.DUCKS` is the same idea in code: the bell (-6 dB,
1.4 s), the horn (-6 dB, 1.6 s) and the KO tick (-3 dB, 0.45 s) pull the crowd down and
let it back up at 9 dB/s. The crowd is 10 dB louder than it was in wave G; without this,
a roar landing on the knockout count would sit on the very tick it is reacting to.

**It ducks the voices, not the fader.** The Ambience bus belongs to two other things —
the player's `settings` message and the endgame lift — and a duck that borrowed it would
have to hand back a number it does not own. Every crowd voice this node started has its
own `volume_db`, which *is* this node's to move. So a reader of the bus level always
sees exactly "what the player asked for, plus the endgame", which is what
`commentary_test.gd` asserts and what anyone tuning the mix expects to see. A cue that
starts while the bell is ringing is born ducked rather than arriving over the top of it.

---

## 4. The bolt tick: metal in a bin, not a chime

The old `bolt_collect.wav` was six high, tightly damped modes starting at 1760 Hz with
**nothing below 900 Hz**: centroid 2596 Hz, 47 % of its energy above 2 kHz. That is a
triangle.

What makes a small piece of steel landing in a bin sound like one is that **you hear the
bin**: a big thin panel, struck off centre, ringing an octave and a half below the nut
itself. So there are three parts now — the tick (0.3 ms strike, still bright, because
the leading edge is what cuts through), the **nut** (high modes, 4 ms decay: the object
is small, so it is over almost at once) and the **panel** (a thin steel sheet at 380 Hz
with a plate's inharmonic mode set, 35 ms) — plus a second arrival 9 ms later into the
**same buffer**, so the modes still ringing from the first are added to by the second:
one nut bouncing, not two nuts.

| | old | new |
|---|---|---|
| centroid | 2596 Hz | **742 Hz** |
| energy above 2 kHz | 47.4 % | **3.1 %** |
| brightness (first-difference RMS over signal RMS) | -7.94 dB | **-17.26 dB** |
| length | 45 ms | 55 ms |

**The pitch spread is untouched.** `CollectAudio` still climbs a semitone per collect to
two octaves; this is a new sample under the same ramp, and at the top of the ramp the
panel sits at 1520 Hz, well inside where it still reads as metal.

---

## 5. Every new file

44.1 kHz, 16-bit, mono, -3.00 dBFS peak. `<200` is the share of energy a phone speaker
cannot reproduce; `700-8k` is the share it does its best work in.

| file | length | rms | <200 | 700-8k | built from |
|---|---|---|---|---|---|
| `drive_whine_loop.wav` | 1.0 s **loop** | -11.41 | 1.9 % | 21.5 % | gear mesh at 500 Hz + harmonics, warbling once a revolution; a **commutation** impulse train at the brush bar rate; a 55 Hz armature a tenth down, for headphones; bearing hash |
| `roll_wheel_loop.wav` | 1.0 s **loop** | -15.66 | 1.0 % | 44.6 % | tread blocks slapping (impulse train at the block rate), the contact patch's hiss, and **the floor**: both run through a modal bank at a steel plate's modes, because a big plate rings when you roll over it |
| `track_clatter_loop.wav` | 1.2 s **loop** | -16.06 | 0.9 % | 25.5 % | the links: a hard impulse train at 25/s through steel modes, the sprocket at half the link rate, belt rumble, grit |
| `roll_omni_loop.wav` | 1.0 s **loop** | -18.34 | 2.1 % | 52.7 % | 62 little hard roller contacts a second through high, very short modes; bearing hash |
| `skid_loop.wav` | 1.0 s **loop** | -17.67 | 0.0 % | 84.2 % | stick-slip: broadband noise through a periodic **gate** at 47 Hz (a gate, not a tremolo — a tremolo reads as a machine gun), a wandering squeal band, a mid body |
| `scrape_loop.wav` | 1.0 s **loop** | -16.05 | 0.0 % | 87.8 % | the same process with no rubber in it: faster chatter (83 Hz), no squeal, and **the wall rings** — its modes are excited continuously by the drag |
| `chassis_thud_1..3.wav` | 0.42 / 0.48 / 0.54 s | -23.4 / -18.2 / -19.6 | 8 / 53 / 3 % | 52 / 34 / 32 % | arrival crack, a saturated low-mid **frame** body (not a panel), the tyres' rubber slap, and the **rattle**: every loose panel arriving over the next 200 ms at a falling rate |
| `crowd_swell_1..2.wav` | 2.2 / 2.6 s | -15.0 / -15.5 | 0.1 % | 86 / 88 % | the murmur swelling hard with the clap density rising under it, in the same hall. Rise 160-220 ms, settle 0.55-0.70 s |
| `crowd_roar.wav` | 3.4 s | -14.68 | 0.4 % | 83.5 % | the same, longer and denser, plus the low wall of massed voices a full house has |

Rebuilt: `crowd_ambience_loop.wav` (§3), `bolt_collect.wav` (§4).

**All synthesised, and all should be replaced by recordings** if a licensed source turns
up (`docs/stage6-spec.md` §7). What to source is in `docs/audio-notes.md` §6, which now
has a row for each of these. No CC0 source was used and no third-party licence is
involved in anything in `Arena/audio`.

---

## 6. One change to the generator worth knowing about

`scripts/gen-sounds.py` used to be **one seeded generator consumed in call order**,
which made it reproducible and made it a trap: changing any sound changed the draws
every sound after it got, so a one-line edit to the ambience rewrote the two endgame
cues as well. G6 worked around it by appending its two builds at the end of `build_all`
and leaving a comment saying so.

Wave F had to rebuild `bolt_collect` and `crowd_ambience_loop`, which sit in the
**middle**, so the trap was removed instead of worked around. `build(name, fn, ...)`
re-seeds `RNG` per file name, from `STREAM_SEED` and a CRC of the name. A file's bytes
now depend on its own builder and nothing else, sounds can be added or changed anywhere
in the list, and a re-run is still byte identical.

**One-time cost, paid here:** every file's noise realisation changed once, because the
stream each draws from is a different one. Nothing about the *design* of any of them
changed, and the peaks, lengths, loop seams and spectra were all re-measured afterwards
(every loop still seamless, every file still -3.00 dBFS).

---

## 7. THE ONE-NUMBER TRIMS FOR THE PHONE TEST

Everything below is a single number in one file. Change it, re-run
`sh scripts/test-arena.sh audio_test.gd`, rebuild.

### "Still can't hear the crowd"

| dial | file | now | try |
|---|---|---|---|
| the whole crowd | `Arena/fx/audio_bus_layout.tres`, `bus/3/volume_db` | **-10.0** | -7.0 |
| just the bed | `AudioMix.LEVELS["crowd_ambience_loop"]` | **-4.0** | -2.0 |
| the reactions | `AudioMix.LEVELS["crowd_swell"]` / `["crowd_roar"]` | **-4.0 / -3.0** | -2.0 / -1.0 |
| the endgame lift | `AudioMix.AMBIENCE_HOT_DB` | **3.0** | 4.0 |

### "The crowd is on top of the bell / the horn"

| dial | file | now |
|---|---|---|
| how far the announcements push it down | `AudioMix.DUCKS` (depth dB, hold s) | bell `[6, 1.4]`, horn `[6, 1.6]`, KO `[3, 0.45]` |
| how fast it comes back | `AudioMix.DUCK_RELEASE_DB_S` | **9.0** dB/s |

### "The machines are too loud / too quiet"

| dial | now |
|---|---|
| the whole movement bed | `AudioMix.LEVELS["drive_whine_loop"]` **-20.0** and the three roll loops **-15 / -15 / -13** |
| skids only | `AudioMix.LEVELS["skid_loop"]` **-7.0** |
| scrapes only | `AudioMix.LEVELS["scrape_loop"]` **-8.0** |
| landings only | `AudioMix.LEVELS["chassis_thud"]` **-6.0** |

### "It skids / scrapes / thuds too often"

| dial | file | now |
|---|---|---|
| skid threshold | `MachineAudio.SKID_FLOOR_MS` | **0.90** m/s of scrub |
| scrape threshold | `MachineAudio.SCRAPE_MIN_MS` | **0.35** m/s |
| smallest landing worth a thud | `MachineAudio.LAND_MIN_MS` | **1.40** m/s of fall |
| shortest flight that counts as one | `MachineAudio.AIR_MIN_S` | **0.20** s |

### "The crowd roars at the wrong things"

`AudioMix.SWELL_FOR_LINE` maps a commentary line to a reaction, and `AudioMix.SWELLS`
holds each one's level, pitch and minimum gap. Adding IN THE ZONE is one dictionary
entry.

---

## 8. Tests

```
sh scripts/test-arena.sh audio_test.gd fx_test.gd determinism_test.gd commentary_test.gd
```

- `audio_test.gd`: **93 checks, 0 failures** (was 42). New: the crowd bed's measured RMS
  and brightness, the bolt tick's brightness ceiling, the mix ordering in both measures,
  the duck on the voices with the fader untouched, the reaction gaps and cap, and a
  whole `MachineAudio` section — the whine's pitch and level tracking speed and throttle
  in a headless run, the loop being re-pointed and never restarted, the right roll file
  per drive, a pivot making a skid, a stick the drive cannot follow scrubbing before the
  physics catches up, the voice being handed back, a landing thud sized by its fall,
  three machines sliding at once staying inside `MAX_TRANSIENT_LOOPS`, and forty
  landings in a frame staying inside the thud cap.
- `fx_test.gd` (104), `commentary_test.gd` (82), `determinism_test.gd` (42): green.
  `determinism_test` is the one that actually proves the hard rule: the same seed and
  the same input log re-simulate to the same result with the whole movement layer
  running.
- **Full suite: 24 of 26 green, and no script errors anywhere.** The two that are not
  are other agents' in-flight work, not wave F's: `ai_test.gd` (2 failures in
  `opponent_ai.gd`, which F2 may not edit) and one flaky check in `fx_test.gd`
  ("haptic messages never exceeded 30 in any one second", worst 31). That check is
  nondeterministic independently of any change here — three consecutive runs of the
  same build reported 75, 72 and 74 messages sent — and it passes 3/3 when the machine
  is not running a dozen Godots at once. Nothing in wave F sends a haptic.
- `Arena/tests/_f2_movement_probe.gd`: not a test (leading underscore), the real-fight
  measurement §2 quotes.

---

## 8a. Two bugs the suite caught, worth recording

Both were invisible in `audio_test.gd` and both showed up only in a full run, which is
the argument for running the whole suite rather than your own file.

**A freed machine cannot even be PASSED to a typed parameter.** A bot is eliminated, or a
world is torn down, and `MachineAudio`'s list is only rebuilt every `RESCAN_S`. GDScript
checks an argument's class *before* the function body runs, so
`_step_machine(machine: Object, ...)` threw "the Object-derived class of argument 1
(previously freed) is not a subclass of the expected argument class" and the
`is_instance_valid` guard on the first line never got a chance to answer. The same is
true of assignment: `var machine: Object = st.get("bot")` throws "Trying to assign
invalid previously freed instance". Both are now `Variant` with the check at the call
site, and `audio_test.gd` frees a bound machine mid-run to hold it there.

**A global transform on a detached Node3D is an engine error.** `AudioMix.start_loop`
wrote `p3.global_position` before `add_child`, then again after. The second one is the
one that works; the first is "Condition '!is_inside_tree()' is true" out of
`get_global_transform`, once per positional loop. It had been harmless since agent AU
wrote it because almost nothing started positional loops; wave F starts two per machine
per fight, which turned it into several hundred lines of log per run. It is now a plain
`position` before the add and the same `global_position` after.

---

## 9. What is owed

1. **Nobody has heard any of it.** Every judgement here is a spectrum, a peak, an RMS or
   a mixer flag. The owner's ear is the gate and §7 is the dial board for that pass.
2. **Everything is still synthesised.** §5, and `docs/audio-notes.md` §6 for what to
   source.
3. **`FightFx.set_motor_state()` is now dead code** and is documented as superseded in
   place. It is kept because it is part of the Stage 3 contract; a caller that used it
   would get `motor_loop` on a different key from MachineAudio's, so the two would stack
   rather than fight. Deleting it is a one-liner whenever somebody is confident the
   shell never calls it.
4. **`motor_loop.wav` is now unused** (71 % of its energy is below 200 Hz, which is why
   it was replaced rather than re-levelled). It is still in the catalogue and still
   tested; it could be deleted with `set_motor_state`.
5. **The scrape cannot tell a wall from a house bot's cage**, and does not need to: both
   are upright steel and both want the same sound. It also cannot tell a wall from a
   pit's raised leaf, which is the one case where the geometry rule could be wrong.
6. **No listener, no placement.** With no `Camera3D` in the viewport every movement loop
   falls back to non-positional, which is correct for tests and silent in a scene that
   forgets its camera (`audio-notes.md` §8 weakness 7, unchanged).
7. **The reaction is 2 dB over the bed at its loudest.** That is a texture change as
   much as a level change (the claps are at 2.4 kHz against the bed's 1.3 kHz centroid).
   If it reads small on the phone, `crowd_swell` / `crowd_roar` in §7 is the dial.
