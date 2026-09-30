# Audio (agent AU)

What every sound in Roboteer is made of, how the mix is wired, and exactly where a
licensed recording drops in to replace a synthesised one.

Scope: `scripts/gen-sounds.py`, `Arena/audio/**`, `Arena/fx/audio_mix.gd`,
`Arena/fx/audio_bus_layout.tres`, the sound-playing parts of `Arena/fx/fx.gd`,
`Arena/tests/audio_test.gd`. Everything here is **presentation** (spec §7): it runs
outside the physics tick, it never reads the fight's seeded RNG, and deleting the FX
subtree still produces the same result JSON.

---

## 0. The short version

- **42 files**, 44.1 kHz 16-bit. Mono except the ambience bed.
  (28 from agent AU; wave G's two endgame cues are §9; wave F's twelve are §10.)
- **Everything is synthesised**, but by physical modelling, not by oscillators: modal
  resonator banks for metal, a driven waveguide (Karplus-Strong) for the bandsaw,
  transient + body + thump layering for impacts, circular convolution for the hall.
- **Nothing here is recorded, and recorded replacements are the plan** (spec §7 of
  `docs/stage6-spec.md`). §6 below is the drop-in table.
- **Mix**: Master -> Music, SFX, Ambience, UI. Reverb on SFX, hard limiter on Master.
  The Ambience bus is at **-10 dB** since wave F (§10); it was -14.
- **Tests**: `Arena/tests/audio_test.gd`, 93 checks, 0 failures.

Regenerate:

```
python3 scripts/gen-sounds.py
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
python3 scripts/gen-sounds.py --patch-imports      # loop flags and PCM on the loops
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/audio_test.gd
```

The generator is seeded, so a re-run is byte identical and Godot does not re-import
for nothing. Since wave F it seeds **per file name** rather than running one stream in
call order, so a file's bytes depend only on its own builder: sounds can now be added or
changed anywhere in `build_all` without rewriting everything after them (§10). The
`--patch-imports` step is only needed when a **new** file has been imported for the
first time; the `.import` files are committed.

---

## 1. Why this is not a bag of sine blips

The Stage 3 placeholders were sums of decaying sines. That is the right way to prove
timing and the wrong way to make something sound like metal, because a sum of sines
has no excitation: the attack is a step, every mode starts at full amplitude at the
same instant, and two hits 40 ms apart are two separate events rather than one object
being hit twice.

Everything in `gen-sounds.py` is built as **excitation into a resonator** instead.

**`modal(exc, freqs, amps, taus)`** is a bank of two-pole filters,

```
y[n] = 2 r cos(w) y[n-1] - r^2 y[n-2] + sin(w) x[n],   r = exp(-1 / (tau * SR))
```

one per mode, summed. Each one is a damped oscillator, so its impulse response is a
decaying sine — but because it is a *filter*, the input decides what it sounds like:

| excitation | what you hear |
|---|---|
| 0.4 ms band-limited noise click | a struck plate |
| 1.8 ms low click | a blunt, heavy arrival |
| continuous friction noise | something being ground or sawn |
| a second click 40 ms later | one object bouncing, not two objects |

That last row is the whole reason `wheel_off` and `panel_off` sound like a single
part falling: the strikes go into **one buffer**, so the modes still ringing from
bounce 1 are added to by bounce 2. Five separately rendered hits pasted together
never does that.

**`steel_modes(f0)`** gives the mode set. Real plate modes are inharmonic and climb
faster than a harmonic series (roughly n^1.35 with jitter), and that inharmonicity is
precisely what the ear reads as "metal". A harmonic stack at the same pitches sounds
like a toy xylophone.

**`waveguide(exc, freq, loop_gain, brightness)`** is Karplus-Strong: a delay line of
`SR/freq` samples with a one-pole lowpass in the feedback path. Struck with a burst
it is a plucked string; **driven with continuous noise it is friction against a
resonant body**, which is exactly what a bandsaw blade in a cut is. The saw's whine
is therefore slightly unstable in pitch and breathy in a way an oscillator cannot be.

**`circular_reverb(x, decay_s)`** convolves with a decaying noise tail using an FFT,
*circularly*. The tail that runs off the end of the buffer wraps into the start,
which is what a genuinely continuous recording would have had there — so a reverb can
be baked into a loop without creating a seam. That is how the 8 s ambience bed has a
hall on it and still loops to the sample.

---

## 2. Every sound, and what it is made of

### Feedback

| file | length | built from |
|---|---|---|
| `bolt_collect.wav` | 0.055 s | **Rebuilt in wave F** (§10): the tick, the nut's own high modes, and **the bin** — a thin steel panel at 380 Hz with a plate's inharmonic modes — struck twice into one buffer 9 ms apart, so it is one nut bouncing. The first build was six modes starting at 1760 Hz with nothing below 900 Hz, which measured a 2596 Hz centroid: a chime. |
| `impact_light_1..3.wav` | 0.130 / 0.142 / 0.154 s | transient + a small panel body (f0 486 / 612 / 398 Hz) + a bright scrape band + a hint of thump at 152 Hz. The three differ in the panel's fundamental, its damping and the transient's colour: a corner, a flat and an edge. |
| `impact_heavy_1..3.wav` | 0.440 / 0.500 / 0.560 s | three layers in this order: a 3 ms broadband **crack** (two surfaces arriving), a saturated **modal body** (f0 232 / 288 / 196 Hz, six modes, taus out to 230 ms), and a **thump** whose pitch falls a third of an octave (128 / 146 / 108 Hz). Saturation is deliberate: a plate driven past linearity really does generate harmonics. |

### Parts coming off

| file | length | built from |
|---|---|---|
| `wheel_off.wav` | 0.620 s | four strikes into one buffer at 0 / 195 / 305 / 372 ms — gaps shortening geometrically, which is what a real bounce does — with a **lot** of fast-decaying low noise on each, because that is what kills the metal ring and makes it read as rubber. Then the tyre rolling away. |
| `panel_off.wav` | 0.720 s | the same, but a big flat plate: long modes (90 ms), a bright tear at the start, and three diminishing slaps as it flips over. |

### Weapons

| file | length | built from |
|---|---|---|
| `flipper_fire.wav` | 0.400 s | **valve click** (a 35 ms solenoid tick at 1420 Hz), then **120 ms of gas** — noise through a nozzle formant at 2.4 to 5.2 kHz that swells in and stops *dead* when the ram reaches the end of its stroke — then the **arm thud** at 122 ms: a steel stop with the rubber bump under it. |
| `axe_swing.wav` | 0.340 s | a whoosh: three noise bands crossfaded so the centre frequency sweeps up and back down as the head passes, plus the servo under it. Fired on the weapon's edge; the landing is a damage event. |
| `axe_hit.wav` | 0.520 s | duller and heavier than `impact_heavy`: less ring, more thump at 104 Hz, plus a short knock from the shaft taking the shock. |
| `ram_hit.wav` | 0.460 s | blunt: almost no bright content, a 1.8 ms strike into a 214 Hz body, a scuff band, and the victim's frame ringing low. |
| `crusher_clamp.wav` | 0.900 s | the pump loading (74 to 100 Hz, saturated), then **stick-slip creak** — a burst train whose rate falls from 46 Hz to 9 Hz, rung through a 820 Hz body. That falling rate is the whole sound; a steady tremolo reads as a machine gun. Then the relief valve sighing and the jaw seating. |

### Loops

All eight (the seven below plus wave G's `endgame_drone_loop.wav`, §9) are verified
seamless twice: in the generator before the file is written, and in `audio_test.gd`
against what Godot actually imported.

| file | length | built from |
|---|---|---|
| `motor_loop.wav` | 1.000 s | **two layers, as the brief asks**: a saturated 55 Hz series (a brushed DC motor under load, not a sine) and a **gearbox whine** at 440 Hz with harmonics, amplitude modulated at the shaft rate so it has a once-per-revolution warble. Plus brush hash and a 3/7 Hz loading wobble. `pitch_scale` follows throttle 0.72 to 1.45. |
| `spin_up_loop.wav` | 1.000 s | a spinner's weapon motor, written **at the bottom of its range** (fundamental 180 Hz, eight harmonics, saturated) with a broad air roar gated by the blade-passing rate. Low on purpose: fx pitches it 0.55 to 2.10 by `readiness()`, and anything already bright turns into a whistle when pitched up. One file covers the whole rev, so there is no handover seam between a spin-up sample and a spinning sample. |
| `saw_cut_loop.wav` | 1.200 s | a **driven waveguide** at 612 Hz (plus a second at 1477 Hz) fed continuous friction noise: the blade. Over it, the grind — noise amplitude modulated at the 94 Hz tooth rate — and the motor loading underneath. Seamless by crossfade, because a waveguide is not exactly periodic over any convenient length. |
| `flame_loop.wav` | 2.000 s | a jet burner. Real fire is broadband noise whose **envelope** is low-frequency noise (the flame front moving), so the rumble band is modulated by a slow random envelope, the mid band by a faster one, and the nozzle hiss is nearly steady. A modal nozzle resonance on top is what makes it a jet rather than wind. |
| `grinder_loop.wav` | 1.500 s | a 40 Hz induction motor (saturated), the disc's own modes rung quietly by the bearing hash, and housing rumble. |
| `disc_spin_loop.wav` | 1.000 s | a heavy **free**-spinning disc: almost all air and bearing, very little motor, because nothing is driving it. |
| `crowd_ambience_loop.wav` | 8.000 s, **stereo** | see §3. **Rebuilt in wave F**; the description there is current. |

### Arena hazards

| file | length | built from |
|---|---|---|
| `spikes.wav` | 0.440 s | ram air, then the floor plate resonating as the shaft drags through it (six overlapping modal windows whose resonance rises as more shaft shows), then the tips hitting their top stop. |
| `pit_open.wav` | 1.100 s | hydraulic groan sliding from 52 to 82 Hz, steel leaves sliding on steel (broadband scrape through a moving resonance), then **two** heavy leaves hitting their end plates 32 ms apart. |
| `flame_jet.wav` | 0.700 s | ignition: the gas valve click, a **whump** as the gas volume catches all at once, then the roar arriving over 90 ms. `flame_loop` takes over underneath it. |
| `ram_crush.wav` | 0.850 s | the Crush arena's wall stroke. The only sound in the game with a real sub layer (66 Hz), plus a 162 Hz body, a crack, and a **rattle tail**: everything not bolted down, as a burst train decaying from 70 Hz to 14 Hz. |

### Fight and UI

| file | length | built from |
|---|---|---|
| `countdown_tick.wav` | 0.090 s | a small resonant body struck at 880 Hz, not a sine. FIGHT plays it at pitch 1.5, and a sine at 1320 Hz is a beep where this is still a tick. |
| `ko_tick.wav` | 0.140 s | low body with the top rolled off, so that fx's 3.5 %-per-second rise (about 0.6 of a semitone) tightens it rather than making it sparkle. |
| `bell.wav` | 2.600 s | ten partials on a 523 Hz prime, **each with a detuned twin** (the two degenerate modes of any nearly-axisymmetric shell) — that pair is what produces the slow warble a real bell has. The hum note an octave below the prime is what makes it read as heavy metal rather than a chime. Driven by a hammer click through the bank, so the strike noise is coloured *by* the bell rather than pasted on top. |

---

## 3. The ambience bed, and the "no recognisable words" guarantee

`crowd_ambience_loop.wav` is 8 s of stereo arena hall: distant crowd murmur and PA
room tone, at -6 dB trim on a bus that is itself at -14 dB, so it sits under
everything and is only noticed when it stops.

It is **structurally incapable of containing words**, which matters because a
placeholder crowd that seems to say something is worse than no crowd at all. The
crowd layer is band-limited noise (200 to 1800 Hz at -3 dB/octave, because the
average of several hundred voices is pink rather than white) whose only movement is
amplitude modulation at 0.25 to 2.5 Hz. There is no formant motion, no spectral
sweep, and nothing above a 4 Hz envelope — so there is no speech-shaped content for
the ear to resolve into language.

Three layers: the murmur; two broad swells per loop at 1/8 and 2/8 Hz so the hall
breathes; and PA room tone, which is 50 Hz mains hum and its harmonics 40 dB down
plus the preamp hiss of a live system with nothing going through it.

**Seamless by construction, not by crossfade.** Every layer is frequency-domain noise
or a whole number of cycles per loop, and the hall is applied by circular convolution
(§1), so the file is exactly periodic. Measured wrap step 1246 against a largest
interior step of 3153 (left) and 186 against 3229 (right).

**Stereo** is two independent noise fields sharing one envelope, which decorrelates
the sides into a wide hall; the two are then re-correlated below 220 Hz so it does not
sound like two different rooms, and stays mono-compatible.

---

## 4. The mix

### The bus layout (`Arena/fx/audio_bus_layout.tres`)

```
Master  <- Music     -4 dB   (wave G's endgame drone plays here, §9; the bus was
                              built empty so a track could be added without a mix rewrite)
        <- SFX        0 dB   AudioEffectReverb
        <- Ambience -10 dB   (-14 until wave F, §10: the crowd was 41 dB down)
        <- UI        -3 dB
Master: AudioEffectHardLimiter, ceiling -0.8 dB, release 120 ms
```

**The reverb is on SFX and nowhere else.** The ambience bed already has its own hall
baked in, and the UI must stay outside the fiction; reverberating either again puts
the menu inside the arena and the arena inside two rooms.

**It is 12 % wet, room size 0.32, damping 0.62, predelay 14 ms.** This is a steel
shed, not a cathedral. The reverb's job is to stop thirty dry one-shots sounding like
thirty separate files; past about 15 % wet the impacts stop being impacts and start
being splashes.

**The limiter is the only thing between the mix and the DAC.** Twelve simultaneous
voices each peaking at -3 dBFS will clip a phone's output stage without it, and a
clipped transient on a small speaker is the single ugliest thing a game can do.

The layout is applied **at runtime** by `AudioMix.apply_bus_layout()` rather than
through a project setting, so the project still starts on Godot's default single bus
if the FX subtree is deleted. Applying it **preserves the master volume and mute**,
because agent R's `settings` message writes those on bus 0 and may have arrived
first; `AudioServer.set_bus_layout()` would otherwise silently reset the volume to
0 dB and un-mute a player who had asked for silence. `audio_test.gd` checks that.

### Levels

Every file is normalised to **-3 dBFS peak**, which is right for the encoder and
wrong for the mix: normalised peaks mean a bolt tick and a ram landing arrive at the
same level. The actual balance of the game is `AudioMix.LEVELS`, a per-sound dB trim,
and **it is the first place to go when something is too loud**:

| sound | trim | sound | trim |
|---|---|---|---|
| `ram_crush` | -2 dB | `flipper_fire` | -7 dB |
| `impact_heavy` | -3 dB | `ko_tick` | -7 dB |
| `axe_hit` | -4 dB | `spikes`, `countdown_tick` | -8 dB |
| `bell` | -4 dB | `impact_light`, `crusher_clamp`, `flame_jet` | -9 dB |
| `ram_hit`, `pit_open` | -5 dB | `axe_swing`, `bolt_collect` | -12 / -13 dB |
| `panel_off` | -6 dB | the loops | -15 to -20 dB |
| ambience | -4 dB | the movement loops | -13 to -20 dB |

**The full measured table is in `docs/wave-f-f2-notes.md` §1**, with every sound's file
RMS, its loudest 200 ms and what it comes to at the master. That table is the one to
read before moving anything here, because peaks lie: every file is normalised to -3 dBFS,
so comparing peaks says every sound in the game is the same size. It is how wave G's
horn ended up 2.6 dB quieter than the bell it was written to out-announce.

### Polyphony caps

`AudioMix.CAPS`. Past the cap the **oldest** voice of that name is stopped, so a new
hit is never dropped and an old one never blocks it.

`bolt_collect` is **6**: the tick is 45 ms and bolts land about 25 ms apart, so six is
two and a bit ticks of overlap — enough that the ramp is a stream rather than a
stutter, few enough that a 120 bolt shower cannot become a wall. `impact_heavy` is
**3**, because a fourth simultaneous heavy hit is not information, it is mud. `bell`,
`ko_tick` and `pit_open` are **1**, because two of any of those is a bug.

The old `FightFx` pool was ten `AudioStreamPlayer`s rotated round-robin. That has no
idea what it is cutting off: a 30 bolt shower would silently murder the bell. Voice
stealing here is per name and always takes the longest-running voice, never "whatever
is next in the ring".

### Variants

`impact_light` and `impact_heavy` are groups of three files. `play("impact_heavy")`
picks one, **never the one it played last**, which is a coin flip between the other
two. A plain uniform pick repeats about a third of the time, and a repeated sample at
a repeated interval is the most obvious "this is a game" tell there is.

The picker uses **`AudioMix`'s own `RandomNumberGenerator`**, never the fight's seeded
RNG: a presentation node drawing from the shared generator would move the fight's
random sequence and desync a replay. It is seeded with a constant (`RNG_SEED`), so a
headless run is still reproducible; the variation that matters is between consecutive
hits inside one fight, not between one run and the next. `FightFx._jitter()` routes
the pitch jitter that used to be `randf_range()` through the same generator, for the
same reason.

### Positional audio

Anything with a place in the arena plays on an `AudioStreamPlayer3D`:
`ATTENUATION_INVERSE_DISTANCE`, `unit_size` 5 m, `max_distance` 26 m,
`panning_strength` 0.7, Doppler off. At the fight framing the arena is about 8 m
across, so 5 m puts the far corner roughly 4 dB down: placed, but never so quiet the
player misses a hit that mattered.

`AudioMix.NON_POSITIONAL` lists what stays centred regardless: the countdown, the
bell, the KO count (the announcer's, not an object's), `bolt_collect` (it is the
player's own feedback), and the ambience (it is the room). The drive hums, which
Stage 3 deliberately left non-positional, now follow their bots.

If there is no `Camera3D` or `AudioListener3D` in the viewport — which is the case in
every headless test — `AudioMix` falls back to the 2D pool rather than failing.

### Phone-speaker balance

Measured and tuned, not guessed. A phone speaker is effectively gone below ~400 Hz,
so a sound that spends most of its energy under 200 Hz just sounds quiet. The first
build of `ram_hit` had **90 %** of its energy below 200 Hz and `ram_crush` 84 %; both
were retuned by raising the modal body's fundamental and cutting the sub layer, to
37 % and 53 %. `ram_crush` is the one sound still allowed a real sub: the Crush wall
must *sound* the heaviest, and it is one event per stroke.

The same pass found a **DC offset of -0.077** (11 % of full scale) on `motor_loop`,
caused by soft-clipping a harmonic stack: `tanh` is an odd function, but a sum of
harmonics with fixed phases is not amplitude-symmetric in time, so clipping it
produces real DC. `saturate()` now subtracts its own mean.

---

## 5. How the game plays it

`FightFx`'s public API is **unchanged** for everything agent R already calls. The
Stage 3 contract (`docs/stage3-fx-notes.md`) holds: `on_scrap_awarded`,
`on_damage_event`, `on_weapon_fired`, `on_ko_tick`, `on_countdown`, `on_bell`,
`set_motor_state`, `on_spikes`, `set_haptics_enabled`, `stop_all_audio`, and
`FightFx.SOUNDS` (now an alias for `AudioMix.SOUNDS`).

What changed inside: `_play()` is three lines that call `AudioMix.play()`, the ten
voice pool is gone, and the motors are mixer loop keys. Impacts, detaches and spikes
now pass their world position so they are placed.

**Four new entry points**, all optional — nothing breaks if R never calls them:

```gdscript
fx.on_weapon_fired(bot_id, kind)        # kind defaults to "flipper" (Stage 3 call is unchanged)
fx.on_weapon_state(bot_id, kind, active, readiness)
fx.on_hazard_fx(kind, active, position) # connect ArenaBase.hazard_fx straight to this
fx.set_ambience(true)
fx.set_master_volume(linear)            # same operation as fight.gd's bus 0 write
```

`on_weapon_state` is meant to be called **every frame** while a spinner, saw or
flamethrower is running: the loop is re-pitched, never restarted, so feeding it
`weapon.readiness()` continuously is the intended use and costs nothing.

`on_hazard_fx` matches `ArenaBase`'s signal exactly, so the wiring is one line in
`fight.gd`:

```gdscript
arena.hazard_fx.connect(fx.on_hazard_fx)
```

A grinder's loop **starts when the arena does, not when it hurts you**, and `active`
only moves its level (-9 dB idle to 0 dB in contact). A hazard that is silent until
it damages you is a lie the player cannot learn from.

### Owed wiring (not agent AU's files)

- `fight.gd` connects `arena.hazard_fx` to `fx.on_hazard_fx`, and calls
  `fx.set_ambience(true)` when the fight world is built.
- Whoever drives the weapons calls `fx.on_weapon_state(...)` for spinners, the saw and
  the flamethrower, and passes `weapon.kind` to `fx.on_weapon_fired(...)`.
- Nothing above changes any existing call site; until it is done, those sounds simply
  do not play and everything else is unaffected.

---

## 6. Replacing these with recordings

**These are synthesised and nobody should ship them if a licensed source is
available** (`docs/stage6-spec.md` §7). The layering, the lengths and the mix are the
part worth keeping; the timbre is the part to replace.

To drop in a real recording: put the file in `Arena/audio/` **under exactly the name
below**, run the Godot import, then `python3 scripts/gen-sounds.py --patch-imports`
to restore the loop flags, then the import again. Nothing in code needs to change —
`AudioMix.SOUNDS` is keyed by name, not by how the file was made. Then delete that
sound's function from `gen-sounds.py` (or leave it; the script only overwrites files
it is asked to write, so remove the `write(...)` call for anything replaced).

Specs every replacement must meet:

- 44.1 kHz, 16-bit PCM WAV, mono (stereo only for `crowd_ambience_loop.wav`)
- normalised to **-3 dBFS peak**, top and tailed with no silence at the head
- loops must be **genuinely seamless** and are imported as PCM, not QOA;
  `audio_test.gd` measures the wrap step against the largest interior step and fails
  the build if it is bigger
- **Wave C size pass (2026-09-28, `docs/wave-c-size-notes.md`):** 16 files now import as
  QOA after a numeric codec gate (SNR >= 30 dB against the source, peak within 0.1 dB,
  worst error round the peak <= -28 dB, and for a loop no click the PCM does not have,
  measured on the stream decoded through Godot's own playback). Tonal loops (drone, motor,
  spin-up, whine, disc spin, fire patch) and the transient-dense broadband files (crowd
  roar and swells, arc, zaps, saws, drill, scrape, clatter, skirt, cook warning, bolt tick)
  failed it and stay PCM. `audio_test.gd` checks a QOA loop's seam on the decoded stream
  and measures levels on the source wav.
- keep the lengths close to the table below: the timings are tuned against the
  animation and the haptics, and a `flipper_fire` twice as long lands after the arm

| name | file | length | what to source |
|---|---|---|---|
| bolt collect | `bolt_collect.wav` | 0.045 s | a single small nut or washer dropped onto steel, close-mic'd. Must survive being pitched up two octaves. |
| light impact | `impact_light_1..3.wav` | 0.13 to 0.16 s | three different glancing blows on sheet steel |
| heavy impact | `impact_heavy_1..3.wav` | 0.44 to 0.56 s | three different sledge-on-plate hits, distinct bodies |
| wheel off | `wheel_off.wav` | 0.62 s | a tyre and hub dropped and rolling |
| panel off | `panel_off.wav` | 0.72 s | a sheet steel panel dropped flat and flipping |
| flipper | `flipper_fire.wav` | 0.40 s | a pneumatic ram firing against a stop, one take with the valve in it |
| axe swing | `axe_swing.wav` | 0.34 s | a weighted arm swung past the mic |
| axe hit | `axe_hit.wav` | 0.52 s | a hardened head into armour plate |
| ram hit | `ram_hit.wav` | 0.46 s | a blunt steel mass into a steel frame |
| crusher | `crusher_clamp.wav` | 0.90 s | a hydraulic press closing on scrap, with the creak |
| drive hum | `motor_loop.wav` | 1.0 s, **loop** | a brushed DC motor under load, gearbox audible, recorded long and looped |
| spinner | `spin_up_loop.wav` | 1.0 s, **loop** | a weapon motor at its **lowest** steady speed, so pitching up covers the rev |
| saw | `saw_cut_loop.wav` | 1.2 s, **loop** | a bandsaw mid-cut, steady |
| flame | `flame_loop.wav` | 2.0 s, **loop** | a propane burner running |
| grinder | `grinder_loop.wav` | 1.5 s, **loop** | a large angle grinder or bench disc, free running |
| free disc | `disc_spin_loop.wav` | 1.0 s, **loop** | a heavy disc coasting, air and bearing only |
| spikes | `spikes.wav` | 0.44 s | a pneumatic shaft rising through a plate to a stop |
| pit | `pit_open.wav` | 1.10 s | heavy hydraulic doors opening and stopping |
| flame ignite | `flame_jet.wav` | 0.70 s | a burner lighting, with the whump |
| ram crush | `ram_crush.wav` | 0.85 s | a hydraulic wall slamming, with the room's rattle |
| countdown | `countdown_tick.wav` | 0.090 s | a dry hard tick; must not turn into a beep at pitch 1.5 |
| KO count | `ko_tick.wav` | 0.140 s | a dull low knock |
| bell | `bell.wav` | 2.60 s | a struck ring bell with a long decay, recorded dry |
| endgame horn | `endgame_horn.wav` | 1.80 s | a real air horn, one take with the valve in it |
| endgame drone | `endgame_drone_loop.wav` | 4.0 s, **loop** | a low room tone or engine bed, recorded long and looped |
| ambience | `crowd_ambience_loop.wav` | 8.0 s, **loop, stereo** | an indoor arena bed. **No recognisable words**, no chants, no individual voices, no clearances to chase. |
| crowd reaction | `crowd_swell_1..2.wav` | 2.2 / 2.6 s | a crowd reacting to one thing and settling. Same rule: no words, no chants. Applause is ideal. |
| crowd roar | `crowd_roar.wav` | 3.4 s | the same, bigger, for a knockout count. |
| drive whine | `drive_whine_loop.wav` | 1.0 s, **loop** | a brushed motor and reduction box under load, recorded CLOSE and at a steady middling speed, so it can be pitched 0.8 to 2.1 |
| tyre roll | `roll_wheel_loop.wav` | 1.0 s, **loop** | a rubber tyre rolling on a steel plate, steady, mid speed |
| tracks | `track_clatter_loop.wav` | 1.2 s, **loop** | a tracked machine at a walking pace: the LINKS have to be audible, not a hum |
| omni roll | `roll_omni_loop.wav` | 1.0 s, **loop** | small hard rollers on steel; a patter, not a roll |
| skid | `skid_loop.wav` | 1.0 s, **loop** | a rubber tyre scrubbing sideways on steel, steady |
| scrape | `scrape_loop.wav` | 1.0 s, **loop** | a steel edge dragged along a steel wall, steady, with the wall ringing |
| landing | `chassis_thud_1..3.wav` | 0.42 to 0.54 s | a heavy steel frame dropped flat onto a steel floor, three takes, with its own rattle |

The music bus is no longer empty: wave G's endgame drone plays on it (§9). A further
track dropped onto `Music` needs nothing from this file except a `play()` on that bus.

---

## 7. The tests

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/audio_test.gd
```

42 checks, 0 failures, 0.2 s. It needs no renderer, no physics world and no FX scene,
so it cannot be broken by anything outside `Arena/audio` and `Arena/fx/audio_*`.

1. Every sound in `AudioMix.SOUNDS` imports, loads as an `AudioStreamWAV`, is 44.1 kHz,
   has the loop mode it is supposed to have, and has the right channel count.
2. Every loop imported as **16-bit PCM, not QOA** — the import step is where a seam
   gets destroyed and nothing upstream would know — and is seamless by the numeric
   test, **per channel**, run against the bytes Godot actually produced.
3. Variant picking never repeats twice running, uses all three, and the polyphony caps
   really cap (24 heavy impacts in one frame leave 3 voices; 40 collect ticks leave 6).
4. The loop API does not restart a running loop, re-points it instead, and frees it.
5. `set_master_volume` maps to bus 0 and mutes rather than writing -inf dB at zero.
6. The collect ramp's maths: `SEMITONE_RATIO^12` is exactly an octave, the reset window
   is the locked 380 ms, a gap inside the window keeps climbing and a gap past it
   resets, the cap is `BOLT_MAX_SEMITONES`, and `step()` expires a ramp that never
   gets another collect.
7. The bus layout loads, installs the five buses in order with the right sends, has a
   reverb on SFX at a small-room setting and a limiter on Master, and **does not
   trample** a master volume and mute that were already set.

`fx_test.gd` is unchanged and still passes: 72 checks, 0 failures, 2 skipped.

---

## 8. Known weaknesses

1. **Nothing has been heard.** Every judgement in this file is from spectra, peak/RMS
   measurements and the design. The owner's ear is the gate and that pass is owed.
   Expect the `LEVELS` table to move first; it is one dictionary.
2. **Synthesised is synthesised.** The modal and waveguide models are a large step up
   from decaying sines and they are still not a recording. §6 exists for that reason.
3. **The saw and the grinder are the weakest.** Continuous friction is the hardest
   thing to model convincingly, and both are loops the player hears for seconds at a
   time, which is exactly when the ear starts finding the period.
4. ~~**No ducking.**~~ **FIXED in wave F** (§10): `AudioMix.DUCKS` pulls the crowd down
   under the bell, the horn and the KO tick. It ducks the crowd's VOICES rather than the
   Ambience bus, because that fader belongs to the player's settings and to the endgame
   lift. The fight's own loops are still not ducked and do not need to be.
5. **No music.** The `Music` bus is wired and empty.
6. **The collect ramp is still global, not per bot** (Stage 3 weakness 4, unchanged).
7. **Positional audio needs a listener.** With no `Camera3D` in the viewport every
   sound falls back to non-positional. That is correct behaviour for tests, but it
   means a scene that forgets its camera loses the stereo image silently.
8. **Loop pitch and loop length interact.** `spin_up_loop` at pitch 2.1 is a 0.48 s
   loop; it holds because every layer is periodic within the file, but pitching any
   loop far beyond its written range will eventually expose the period.

---

## 9. Wave G addition: the endgame cues (agent G6, 2026-09-16)

Two files and one switch, added for brief v4 §2 and §10 item 2. Full write-up in
`docs/wave-g-g6-notes.md`; this section is the catalogue entry.

| file | length | bus | trim | built from |
|---|---|---|---|---|
| `endgame_horn.wav` | 1.80 s | UI | -3 dB, cap 1 | a reed buzz (1/k harmonic stack soft clipped) through two bore formants, two tones a fourth apart (F3 / A#3) so they beat, a 7 % pitch scoop over 25 ms as the air column catches, the reservoir sagging 14 % after the blast, and the valve's own metal tick under the attack. 8.6 % of its energy below 200 Hz: the formants cut the fundamentals, which is what a real horn does and what survives a phone speaker (§4). |
| `endgame_drone_loop.wav` | 4.0 s, **loop**, PCM | **Music** | -22 dB | a drone on a fifth at 110 Hz with one pulse a second. Exactly periodic by construction (every partial a whole number of cycles per loop, the pulse at 1 Hz starting from zero, frequency-domain noise, the lowpass run circularly): no crossfade, no seam. Written at 110 rather than 55 Hz after the first build measured 98.3 % of its energy below 200 Hz, which is an endgame cue nobody on a phone would ever hear; now 62 % below 200 with the weight on the 220 / 330 / 440 partials. |

`AudioMix.play_endgame_horn()` and `AudioMix.set_endgame(on)` are the whole API.
`set_endgame(true)` starts the drone and lifts the **Ambience** bus by `AMBIENCE_HOT_DB`
(+4 dB: the crowd gets hotter rather than getting a second recording); `set_endgame(false)`
puts back the level it found, never a number from this file, because the player's
`settings` message writes that bus too. `stop_all()` calls it, and so does `AudioMix._exit_tree()` — the lift is a
setting on a global bus and this node is not global, so a fight whose world is torn down
mid-endgame would otherwise leave the crowd 4 dB hot into the next fight and 8 dB into
the one after that.

The countdown and the bell are untouched. Neither cue has variants, so neither touches
the variant picker's generator.

---

## 10. Wave F addition: the movement layer and the crowd (agent F2, 2026-09-16)

The owner played wave G on his iPhone: *"I can't hear the crowd properly, there are no
movement noises"*. Twelve new files, two rebuilt, four levels moved and one new node.
Full write-up with every number in **`docs/wave-f-f2-notes.md`**; this section is the
catalogue entry and the two findings.

### The two findings

1. **There were no movement sounds at all.** `FightFx.set_motor_state()` has existed
   since Stage 3 and nothing in the game has ever called it — the only callers in the
   repo are `fx_test.gd`, which is why the test passed. `Arena/fx/machine_audio.gd`
   replaces it with a node that **finds the machines itself** (they are `World/Bots`,
   FX is `World/FX`) and reads their drive state every presentation frame, so it cannot
   fall out of the wiring again. `set_motor_state` and `motor_loop.wav` are now dead;
   both are kept and documented as superseded.
2. **The crowd was 41 dB down** with 2.9 % of its energy above 2 kHz. About 10 dB of
   that was level (`LEVELS` -6 -> -4 and the Ambience bus -14 -> -10) and the rest was
   placement: the bed is rebuilt with its murmur band moved up, hall air out to 9 kHz
   and **a clap field** over it, because a crowd's audible signature on a small speaker
   is hands, not voices. RMS -21.0 -> -17.15 dBFS; 700 Hz - 8 kHz share 22 % -> 65.5 %.
   It is still structurally word-free: claps are broadband transients, the murmur still
   has no formant motion and nothing above a 4 Hz envelope (§3).

   A third thing fell out of checking the mix: `collect_audio.gd` had its six voices on
   the **Master** bus at 0 dB, skipping both the SFX bus and `LEVELS`, so every collect
   tick was 13 dB hotter than the catalogue says and a bolt shower sat on the master
   limiter. Two lines, now asserted in `audio_test.gd`.

### The files

| file | length | bus | trim | built from |
|---|---|---|---|---|
| `drive_whine_loop.wav` | 1.0 s **loop** | SFX | -20 dB | gear mesh at 500 Hz with harmonics, warbling once a shaft revolution; a **commutation** impulse train at the brush bar rate; a 55 Hz armature a tenth down for headphones; bearing hash. 1.9 % below 200 Hz, because a movement layer written as rumble is one nobody on a phone will hear. |
| `roll_wheel_loop.wav` | 1.0 s **loop** | SFX | -15 dB | tread blocks slapping (an impulse train at the block rate), the contact patch's hiss, and **the floor**: both are run through a modal bank at a steel plate's modes, because a big plate rings when something rolls over it. |
| `track_clatter_loop.wav` | 1.2 s **loop** | SFX | -15 dB | the links. 25 hard impulses a second through steel modes, the sprocket at half the link rate, belt rumble and grit. Tracks are a clatter; a pitched-down tyre is not tracks. |
| `roll_omni_loop.wav` | 1.0 s **loop** | SFX | -13 dB | 62 little hard roller contacts a second through high, very short modes, plus bearing hash. A patter, not a roll. |
| `skid_loop.wav` | 1.0 s **loop** | SFX | -7 dB | stick-slip: broadband noise through a periodic **gate** at 47 Hz, not a tremolo (a tremolo reads as a machine gun), a wandering squeal band and a mid body. |
| `scrape_loop.wav` | 1.0 s **loop** | SFX | -8 dB | the same process with no rubber in it: faster chatter at 83 Hz, no squeal, and the wall's own modes rung continuously by the drag. |
| `chassis_thud_1..3.wav` | 0.42 / 0.48 / 0.54 s | SFX | -6 dB, cap 3 | arrival crack, a saturated low-mid **frame** body (not a panel), the tyres' rubber slap, and the **rattle**: every loose part arriving over the next 200 ms at a falling rate. |
| `crowd_swell_1..2.wav` | 2.2 / 2.6 s | Ambience | -4 dB, cap 2 | the murmur swelling hard with the clap density rising under it, in the same hall. Rise 160-220 ms, settle 0.55-0.70 s. PCM, not QOA: a transient-dense broadband file is the other case a lossy codec smears. |
| `crowd_roar.wav` | 3.4 s | Ambience | -3 dB, cap 1 | the same, longer and denser, plus the low wall of massed voices a full house has. |

Rebuilt: `crowd_ambience_loop.wav` and `bolt_collect.wav` (§2, §3).

### The API

```gdscript
mix.crowd_reaction("BIG HIT")            # or a SWELL_* key; unknown moments say nothing
mix.crowd_reaction(AudioMix.SWELL_KO)
machines.bind(mix)                       # MachineAudio; then it finds the bots itself
machines.step(delta)                     # FightFx drives it; it has no _process of its own
machines.stop_all()
```

`AudioMix.SWELL_FOR_LINE` maps a `FightCommentary` line to a reaction (BIG HIT and
FLIPPED, and nothing else — a crowd that roars at every caption is noise), and
`AudioMix.SWELLS` holds each one's level, pitch and minimum gap. The hook is **one line
in `commentary.gd`'s `_say()`**, so the roar and the caption can never disagree about
what just happened. The KO roar hangs off `FightFx.on_ko_tick` and the endgame roar off
`AudioMix.set_endgame(true)`.

### The duck (weakness 4, fixed)

`AudioMix.DUCKS` pulls the crowd down under the bell (-6 dB, 1.4 s hold), the horn
(-6 dB, 1.6 s) and the KO tick (-3 dB, 0.45 s), releasing at 9 dB/s. **It ducks the
crowd's voices, not the Ambience bus**: that fader belongs to the player's `settings`
message and to the endgame lift, and a duck that borrowed it would have to hand back a
number it does not own. A reader of the bus level therefore always sees exactly "what
the player asked for, plus the endgame". A cue that starts while the bell is ringing is
born ducked rather than arriving over the top of it.

`AMBIENCE_HOT_DB` went 4 -> 3, because the bed it lifts is now 10 dB hotter than the one
G6 chose +4 against.

### The generator

`build(name, fn, ...)` re-seeds `RNG` per file name (from `STREAM_SEED` and a CRC of the
name), so a file's bytes depend only on its own builder. That removes the trap G6 worked
around by appending its two builds at the end of `build_all`: sounds can now be added or
changed anywhere in the list. One-time cost, paid in wave F: every file's noise
realisation changed once. Every loop was re-verified seamless and every file re-measured.

---

## 11. Wave A addition: the hazard wind-ups (arena hazards engineer, 2026-09-24)

The shared hazard warning language (`docs/wave-a-hazards-notes.md`) plays each timed
hazard's OWN wind-up exactly 1.25 s (`ArenaBase.WARN_LEAD_S`) before it acts, once per
hazard group, placed at the hazard. Every file is 1.20 s and is built to END on the
activation, so the hazard's existing one-shot takes over on the beat.

| file | length | bus | trim | built from |
|---|---|---|---|---|
| `warn_spikes.wav` | 1.20 s | SFX | -7 dB, cap 1 | a compressor pumping up: valve clicks through a steel modal bank, their rate rising 6 to 22 a second, over rising air and a plate body swelling at 210 to 270 Hz |
| `warn_flame.wav` | 1.20 s | SFX | -3 dB, cap 2 | the supply valve thunk, a gas hiss rising in level, and a piezo igniter snapping faster and faster (4 to 18 a second) until `flame_jet`'s whump |
| `warn_ram.wav` | 1.20 s | SFX | -14 dB, cap 2 | a hydraulic pump spinning up (fundamental 220 to 520 Hz, three harmonics, saturated), relief-valve chatter and a housing groan |
| `warn_pit.wav` | 1.20 s | SFX | -12 dB, cap 1 | a reed klaxon: 1/k harmonic buzz soft clipped through two bore formants, three blasts on 311 / 440 / 311 Hz, the last held into the slide |

Measured (file RMS, energy below 200 Hz): spikes -21.1 dBFS / 0 %, flame -24.8 / 0 %,
ram -10.5 / 0 %, pit -11.8 / 0 %. The first ram build put 97 % of its energy under 200 Hz
(an 88 Hz groan on long modal decays), which a phone speaker cannot play at all; it was
moved up an octave and a half. With the trims the wind-ups sit 1 to 3 dB under the
activation that follows them (spikes -28, flame -28, ram -24.5, pit -24 dBFS at the bus),
so the warning is heard and the hit is still the bigger event.

**Licence.** All four are synthesised by `scripts/gen-sounds.py` from code in this repo
(seeded per file name, byte-identical on a re-run). No third-party recording, sample or
preset is involved, so there is nothing to attribute and no licence obligation; they are
the project's own work. If a recorded replacement is sourced later it must be CC0 (or the
owner's approved free sources: Sonniss GDC bundles, Freesound CC0) and recorded in §6.

**Also changed:** the Drop Zone no longer plays `pit_open` at the start of its warning.
Its warning is now `hazard_fx("pit_warning")`, and `("pit", true)` fires once, as the
leaves start to slide, which is what `pit_open` describes.
