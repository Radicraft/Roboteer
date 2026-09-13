# Stage 3 FX notes (agent B: bolts, audio, sparks, haptics)

What `Arena/fx/**`, `Arena/audio/**` and `scripts/gen-sounds.py` actually do, as built.
Spec: `docs/stage3-spec.md` §0, §1, §3, §6, §7, §11 and `docs/brief-v3.md` §6.

Everything in here is **presentation**. It runs in `_process`, it never touches physics
state, and nothing it does can feed back into the fight. Deleting the whole FX subtree
must produce the same result JSON, and the headless tests are written so that stays true.

## Files

| file | what |
|---|---|
| `Arena/fx/fx.tscn` | the node R instantiates: `FX` (FightFx) with `BoltShower` and `CollectAudio` children. The particle pool, the SFX voices and the motor voices are built in code, so there is no scene to keep in sync. |
| `Arena/fx/fx.gd` | `FightFx`. Public API, the presentation clock, the scrap ledger, impact/weapon/countdown/bell/spike sounds, the drive hum. |
| `Arena/fx/bolt_shower.gd` | `BoltShower`. MultiMeshInstance3D pool of 120 hex-nut bolts, launch, bounce, scatter delay, magnet, collect. |
| `Arena/fx/collect_audio.gd` | `CollectAudio`. The semitone pitch ramp and its six rotating voices. |
| `Arena/fx/haptics.gd` | `FightHaptics`. Rate-limited `haptic` bridge messages. |
| `Arena/fx/impact_particles.gd` | `FightParticles`. Pooled one-shot spark and dust emitters plus the continuous spike emitter. |
| `Arena/audio/*.wav` | eleven placeholder sounds, plus their `.import` files. |
| `scripts/gen-sounds.py` | regenerates every wav, deterministically. |
| `Arena/tests/fx_test.gd` | the headless feel test. |

## API as implemented

```gdscript
class_name FightFx extends Node3D

signal bolts_landed(bot_id: String, amount: int)   # one bolt landed, HUD already bumped

func bind(hud: Object, get_bot_position: Callable) -> void
func on_scrap_awarded(bot_id: String, amount: int, position: Vector3) -> void
func on_damage_event(info: Dictionary) -> void     # P's payload, spec §6
func on_weapon_fired(bot_id: String) -> void
func on_ko_tick(seconds_left: int) -> void
func on_countdown(step: int) -> void               # 3, 2, 1, then 0 for FIGHT
func on_bell() -> void
func set_motor_state(bot_id: String, throttle: float) -> void   # throttle 0..1
func on_spikes(risen: bool, position: Vector3) -> void
func set_haptics_enabled(on: bool) -> void
func stop_all_audio() -> void                      # call on teardown
```

Wiring from the fight orchestrator:

```gdscript
var fx: FightFx = preload("res://fx/fx.tscn").instantiate()
add_child(fx)
fx.bind(hud, func(bot_id: String) -> Vector3: return _bots[bot_id].chassis.global_position)
```

Two deliberate departures from the literal signature in the spec, neither of which changes
how R calls it:

- `bind(hud: Object, ...)` rather than `hud: Node`. A Node is an Object, so C's HUD passes
  unchanged; typing it as Object lets the test bind a RefCounted fake instead of a Node it
  would then have to free. `FightFx` only ever calls `bump(amount)`, guarded by `has_method`.
- `BoltShower.spawn(origin, count, bot_id, target_getter)` takes the bot id as well as the
  getter, because `collected` has to say which bot the scrap belongs to.

`get_bot_position` is called **once per bot per frame**, not once per bolt: the magnet
re-reads the live position every frame, and the per-frame cache keeps that to one call.

### The scrap ledger

`on_scrap_awarded` never decides scrap, it only shows scrap the rules already awarded, and
the HUD must end up bumped by exactly that amount. The shower may spawn fewer bolts than
the award (pool cap), so `FightFx` keeps a per-bot FIFO of `{amount, bolts}` and hands each
landing bolt a ceilinged share. A 500 scrap award spawns 120 bolts and still bumps the HUD
by exactly 500. If the pool is completely full the amount is banked immediately rather than
dropped: earned scrap is never lost.

The same rule drives the `MAX_LIFE_S = 8 s` safety net in `BoltShower`: a bolt that has
somehow not arrived is force collected so the ledger always drains.

## The magnet constant k, and how it was tuned

`MAGNET_K = 45.0`, used as `acceleration = k / max(distance, 0.3)` toward the live target,
speed capped at 12 m/s, arrival at 0.25 m. Tuned by simulating the exact integrator at
1/60 s before writing it, then confirmed against the headless test.

Time from the magnet engaging to arrival, by distance:

| k | 0.5 m | 1 m | 2 m | 3.5 m | 5 m | 7 m |
|---|---|---|---|---|---|---|
| 30 | 0.08 | 0.20 | 0.43 | 0.78 | 1.13 | 1.58 |
| **45** | **0.07** | **0.17** | **0.37** | **0.65** | **0.93** | **1.32** |
| 70 | 0.05 | 0.13 | 0.30 | 0.53 | 0.77 | 1.08 |
| 90 | 0.05 | 0.12 | 0.27 | 0.48 | 0.68 | 0.98 |

30 is too slow: a bolt shed at the far wall takes over 1.5 s and the stream outlives the
moment that caused it. 90 is too fast: a bolt shed at the attacker's feet is gone in 0.12 s,
which reads as a vacuum cleaner rather than a magnet, exactly the failure the brief warns
about. 45 keeps every distance in the arena inside a 0.17 to 1.35 s band, so near bolts
still have a visible arc and far ones still arrive inside the same beat.

### The orbit bug, and MAGNET_ALIGN

Pure central attraction that falls off as `1/d` is a **logarithmic potential**, and it has
stable orbits. The first build lost bolts exactly that way: 30 spawned, 12 collected, the
rest circling the bot forever until the 8 s safety net swept them up. Measured, a bolt
launched with 5 m/s of tangential velocity orbits from *every* starting distance.

The fix is `MAGNET_ALIGN = 6.0` per second: before adding the pull, the magnet also steers
the speed the bolt already has toward the target (`v = v.lerp(dir * v.length(), align*dt)`).
That is angular damping, not extra force, so the bolts still accelerate as they close. With
it, every launch direction lands in 0.08 to 1.05 s. It also looks better: bolts curve in
rather than spiralling.

### Other bolt tuning (all from brief §6, locked there)

- scatter delay 250 ms randomised ±90 %, so 25 to 475 ms per bolt
- launch 2 to 5 m/s in a 55 degree cone around +Y
- one analytic floor bounce at y = 0, restitution 0.4, horizontal speed x 0.72
- spin 7 to 16 rad/s about a random axis
- pool 120; an oversized shower spawns as many as are free at scale 1.6
- bolt 0.05 m across the flats, gold `#f2c14e`, emission 0.85, lightly shaded, shadows off

Measured in the test: a 30 bolt shower starts landing at about 0.39 s and finishes by about
1.27 s, mean gap about 25 ms, pitch ramp reaching the +24 cap.

## Sounds

`python3 scripts/gen-sounds.py` (python3 here is 3.9.6 with numpy 2.0.2 / scipy 1.13.1).
44.1 kHz, 16-bit mono, seeded RNG so re-running produces identical files. Every file is
normalised to -3 dBFS peak with short fades so nothing clicks.

**These are placeholders for Stage 3 feel testing only.** They are synthesised, they are
not final audio, and recorded or sampled sounds replace them later (brief §11). They exist
so the timing, layering and rate limits can be judged now.

| file | length | what |
|---|---|---|
| `bolt_collect.wav` | 0.040 s | bright metallic tick, FM around 1.8 kHz, 7.5 ms decay |
| `impact_light.wav` | 0.130 s | small metallic body plus a bright scrape |
| `impact_heavy.wav` | 0.480 s | low thud pitch-dropping 115 to 58 Hz, plus an inharmonic ring |
| `flipper_fire.wav` | 0.360 s | pneumatic hiss for 120 ms, then the clunk of the arm hitting its stop |
| `wheel_off.wav` | 0.520 s | rubbery thump plus two settling bounces |
| `panel_off.wav` | 0.620 s | five metallic hits at irregular spacings, a clatter |
| `motor_loop.wav` | 1.000 s | drive hum, **seamless**, looped forward |
| `countdown_tick.wav` | 0.090 s | dry 880 Hz blip; played at pitch 1.5 for FIGHT |
| `bell.wav` | 1.500 s | struck bell, nine inharmonic partials on a 520 Hz prime, detuned twins for the beat |
| `ko_tick.wav` | 0.140 s | dull 300 Hz knock; pitch rises 3.5 % per second of the count |
| `spikes.wav` | 0.420 s | air, a rising scrape 180 to 620 Hz, then the top stop |

### The loop seam

`motor_loop.wav` is built entirely from components whose period divides one second:
integer-Hz harmonics of 55 Hz, a 440 Hz whine, 3 and 7 Hz wobble, and noise synthesised in
the frequency domain (`irfft` of a random-phase band, which is exactly periodic over the
buffer). It is deliberately **not faded**, because a fade would put a dip at the seam.
`gen-sounds.py` asserts the wrap-around sample step is no larger than the largest step
inside the file and fails the build if it is not; measured 0.005 against 0.021.

Its `.import` is set to `edit/loop_mode=2` (Forward) and `compress/mode=0` (PCM, not the
default lossy QOA, so the seam survives). Playback pitch follows throttle from 0.72 to 1.45
and the level from -34 to -11 dB, smoothed at 6 per second; the loop never restarts, so
going on and off the throttle makes no click.

### Import

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
```
Godot writes `Arena/audio/*.wav.import` (committed) and the `.sample` binaries into
`Arena/.godot/imported/` (gitignored, regenerated by the export). `fx_test.gd` asserts every
path loads as an `AudioStreamWAV` and that `motor_loop.wav` came back as `LOOP_FORWARD`.

## Haptics

One message type, `haptic`, payload `{"kind": ...}`, as in spec §3. Kinds sent:

| kind | when |
|---|---|
| `tick` | one per bolt collected |
| `impact_light` | `damage_event` with severity below 0.3 |
| `impact_heavy` | `damage_event` with severity 0.3 or above |
| `flip` | `on_weapon_fired` |
| `ko_tick` | each second of the knockout count |
| `bell` | `on_bell` |

All six go through one sliding one-second window capped at `FightTypes.HAPTIC_MAX_PER_S`
(30). Overflow is **dropped, never queued**: a late tick is worse than no tick. A 120 bolt
stream measured 65 sent and 90 dropped, with a worst case of exactly 30 in any one second.
`set_haptics_enabled(false)` stops all of them (this is what Swift's
`presentation.haptics: false` should drive).

`FightHaptics` looks the Bridge autoload up through the scene tree rather than using the
global `Bridge` identifier. That is not style: a headless run started with `--script`
compiles the FX scripts **before** autoloads are registered, and the global identifier fails
to resolve with "Identifier not found: Bridge", which then poisons every script that depends
on it. `Arena/tests/bridge_test.gd` avoids the same trap the same way.

## Particles

`FightParticles` builds 8 one-shot spark emitters (24 particles, 0.3 s, additive unshaded
streak quads, white-hot to orange ramp), 4 dust emitters (14 particles, 0.75 s, grey, alpha
blended) and one continuous 12 particle emitter for risen spikes. Severity scales the spark
emitter's `amount_ratio`, initial velocity and particle scale, through the emitter's own
process material rather than the node scale (with `local_coords` off, a scaled node distorts
where particles are emitted).

The art direction rule is protected: sparks are warm but last 0.3 s, and the only persistent
saturated warm in the frame stays the gold of the bolts. Dust is deliberately the same grey
family as detached debris.

## Test

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/fx_test.gd
```
32 checks, exit 0 on pass. `scripts/test-arena.sh` auto-discovers everything in
`Arena/tests/`, so it picks `fx_test.gd` up with no change needed (that file is R's).

The test drives `fx.tscn` with `fixed_delta_override = 1/60`, so four simulated seconds run
in 240 frames with no wall-clock waiting. It checks the scatter pause is real, that all 30
bolts become visible and all 30 are collected inside 3 s, that `hud.bump` totals exactly the
awarded scrap, that the arrivals are a stream rather than a burst, that the pitch ramp
climbs past +5 and resets afterwards, that a 500 scrap award spawns 120 fatter bolts worth
500 in total, that the pool is fully returned, and that haptics never exceed 30 per second.
Ran eight times in a row without a flake.

## Known weaknesses

1. **No visual verification.** Nothing in `Arena/fx/**` has been seen on a screen. The
   bolt mesh, the gold material, the spark ramp, the streak quad size and the dust are all
   judged from numbers and the art direction render. The desktop window (spec §14) is the
   feel gate and that pass is still owed: expect to re-tune bolt scale, emission energy and
   spark quad size the first time it is looked at.
2. **Headless cannot verify particles or the MultiMesh buffer.** GPUParticles3D never
   simulates without a renderer, so those checks are skipped. The dummy renderer also does
   not keep the MultiMesh instance buffer, so `multimesh.get_instance_transform()` returns
   identity for every slot; `visible_instance_count()` therefore counts the transforms the
   pool *wrote* rather than reading them back. That still catches a retired slot that was
   never parked, but it cannot catch a renderer-side mistake.
3. **Point-blank showers barely pause.** The locked ±90 % jitter allows a 25 ms scatter
   delay, so a bolt shed 0.5 m from the attacker can land about 0.1 s after the hit. That is
   fine mid-fight but it is the case where the effect is weakest. If it reads badly on
   screen, put a floor on the delay rather than raising the base, so the spread survives.
4. **The collect ramp is global, not per bot.** Two simultaneous showers to different bots
   share one semitone counter, so the opponent's collects push the player's pitch up. In a
   two bot fight this is rare and arguably reads fine; it would need a counter per bot if
   the AI's scrap ever becomes audible.
5. **`on_countdown` is typed `int`.** 3, 2, 1, then 0 for FIGHT. If R wants to pass the
   literal string "FIGHT" the signature has to change.
6. **Sounds are placeholders.** Synthesised, functional, and nobody should ship them. The
   layering and the lengths are the part worth keeping.
7. **The spike emitter is a single instance.** One spike patch exists in The Yard, so one
   emitter is enough; a second hazard would need a pool.
8. **Motor voices are non-positional.** `AudioStreamPlayer`, not `AudioStreamPlayer3D`, so
   both bots' hums come from the same place. Positional audio was not worth the mobile cost
   at this camera distance, but it is a one-line change if the fight sounds flat.
