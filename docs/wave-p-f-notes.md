# Wave P, agent F: feedback, fx and audio

2026-09-21. Wave P's thirteen parts all landed working and SILENT, and most of them
landed invisible with it. D1 wrote it plainly: "the arc has no visible bolt yet". D2
wrote the other half: "a walker that sounds like a 4WD is wrong". This pass is the
feedback for all of them: twenty new sounds, three new pools, one new node that
cannot be left unwired, and a cue for every part in the wave.

Nothing in `fight.gd` was touched, as the contract requires. Everything below hangs
off an accessor a part already publishes, off a signal that already fires, or off the
`FightFx` damage drain that already runs.

## What was built

| File | What it is |
|---|---|
| `Arena/fx/weapon_fx.gd` | **new**, `WeaponFx`: every wave P cue. Finds the machines itself, reads them every presentation frame |
| `Arena/fx/arc_bolt.gd` | **new**, `ArcBolt`: a pooled jagged emissive bolt, deterministic, 4 bolts of 7 spans |
| `Arena/fx/glow_pool.gd` | **new**, `FxGlowPool`: sustained additive glows in numbered slots (the core's heat, the hover's pods, the fire) |
| `Arena/fx/fx_emitters.gd` | **new**, `FxEmitters`: 14 aimable particle emitters taken out by name and handed back, in five flavours |
| `scripts/gen-sounds.py` | 20 new recipes and one new primitive (`_arc_train`), plus three recipes RE-BALANCED (see "the crest factor trap") |
| `Arena/audio/**` | 20 new wavs, 9 of them seamless loops, all 44.1 kHz 16-bit, all PCM |
| `Arena/fx/audio_mix.gd` | registration only: 20 `SOUNDS` rows, 4 `VARIANTS` sets, 7 `CAPS`, 20 `LEVELS` |
| `Arena/fx/machine_audio.gd` | the three `DRIVES` rows D2 asked for, plus two optional keys (see "Amended by F") |
| `Arena/fx/fx.gd` | six short `# --- wave P` insertions: build it, step it, forward the damage event, let it claim its own weapon loops, stop it, expose it |
| `Arena/tests/fx_test.gd` | 104 checks -> **188**, and six test doubles |
| `Arena/tests/audio_test.gd` | 93 checks -> **117**, a new `_window_db` loudness measure, and the 9 new loops in `EXPECTED_LOOPS` |

## The cues, and what each one hangs off

Every reading below is an accessor D1 or D2 already published. Nothing was added to a
weapon, a drive or a bot to make this work, and nothing here can change a fight:
`WeaponFx` only reads, and it runs in `_process` on `FightFx`'s clock.

| Part | What the player sees and hears | Read from |
|---|---|---|
| `tesla_arc` | a crackle that climbs with the charge, a glow on the electrode, a **jagged bolt** from E's `socket_spark` to the part it earthed through, a flash at both ends, sparks where it lands, a crack | `readiness()`, `arcs()`, `last_target()` |
| `shock_prod` | a spark stream while it is held against something, a little arc across its own prongs when it bites, a zap | `contact_seconds()`, `shocks()`, `head` |
| `drill_lance` | a grind that follows the spin, a spark stream out of the hole aimed BACK at the machine boring it, a curl of swarf every 0.18 s | `spin()`, `boring_seconds()`, `lance` |
| `twin_saw` | two voices an octave apart, a spark line off each disc, and one line when a disc comes off | `spin()`, `cutting_seconds()`, `blades[]`, `blade.detached` |
| `napalm_cannon` | a mortar thump and smoke out of E's `socket_muzzle`, a smoke tail and a glow on the charge in flight, then flame (the weapon's own `FlameCone`) plus smoke, embers, a floor glow, a fire loop and **a scorch decal that outlives the fire** | `shots_fired()`, `patches()`, `patch.lit()` |
| `vortex_spinner` | an air-heavy spin-up, and a **lift throw**: dust off the floor and a rising whoop when its bite lands | `readiness()`, and the damage event |
| `legs` | a footfall as each diagonal pair lands, with dust, at agent E's own stride length | chassis velocity and yaw |
| `hover` | skirt dust under the hull, thrown backward, which stops when the drive dies. The thruster pods are agent E's model, not this | `hover_height()`, `power_scale()` |
| `adaptive_tracks` | a finer, busier belt clatter than a plain track | `MachineAudio.DRIVES` |
| `overcharge_core` | a heat glow on the core that rises with the cook, a warning tick that tightens as it climbs, a smoke wisp near the limit, and **it all cools when the weapon idles** | `_cook_rate`, `weapon_readiness()` |
| `reactive` plate | a flash, a shove of smoke outward and a clang, on a blow and never on a cut | the damage event's `impulse` and the victim's `_materials` |
| any stalled drive | a small arc walking round the hull, six times a second, until it comes back | `is_disrupted("drive")` |

Four of those deserve a paragraph.

**The stall stutter is the only thing on screen that says the prod, the arc or the
fire did anything.** All three cut the other machine's DRIVE, and the effect of that
is an opponent that has inexplicably parked. D1 flagged it: "whether the prod's stall
is legible (the other machine simply stops, with no effect of its own yet)". It is
legible now.

**The reactive plate is read out of the damage event and out of the victim.** The
payload carries no material and no source, so the shove is decided from three facts
that are in it: `impulse > 0` (which is zero for every direct-damage event, a cut, a
burn, the core cooking itself, and non-zero only for a blow, which is exactly the
case `Bot._queue_knockback` fires on), the part key naming an armour face, and that
face's material on the victim being `reactive`. A saw on a reactive plate makes no
clang, and `fx_test` proves it.

**The heat shimmer was already paid for.** The brief asked for it "if cheap", and it
is: `fx/flame_cone.gd` carries a haze layer (a broad faint additive glow that breathes,
rather than a screen space refraction, which would cost a full screen texture read per
pixel on a phone), and the fire patch instantiates that same cone stood on its end. So
a lit patch has shimmer for nothing. What it did NOT have is everything around the
fire, which is what was added: smoke standing off it, embers off the top, a glow on
the floor under it and a scorch that outlives it.

**The walker's stride is not in the simulation, so it is taken from the ANIMATION.**
D2's legs are four collision shapes on the hull with no gait (their notes, section 3),
so there is no footfall phase to read. Agent E's `PartAnim` in STRIDE mode is what a
player actually sees: each leg swings through one cycle per `STRIDE_LENGTH` (0.60 m)
of travel, and `legs.gd` hands the four legs the phases of a TROT, two diagonal pairs
half a cycle apart. A pair therefore plants twice a cycle, so `WeaponFx.STRIDE_M` is
**E's constant, halved**, and not a number of this agent's own: a footfall spacing
chosen here would have walked out of step with the legs on screen inside a second.
The phase also advances with yaw, because a machine pivoting on the spot is still
putting feet down. `fx_test` asserts both the rate and that it is still E's number.

**Two things wave P's models do that this node therefore does NOT do.** E's notes
landed while this was being built and moved two items off it:

- **The hover's thruster pods are E's.** Their model carries a `glow` mesh in each of
  the four fan throats and `PartAnim` in HOVER mode brightens it with the work the
  fans are doing (`HOVER_GLOW_MIN/MAX`). This node drew a pair of additive glows under
  the hull for a while, which would have been two pulses at two rates on one machine.
  They are gone; the skirt dust, which the model cannot do, stayed.
- **Two effects now leave from E's socket empties**, not from the weapon's mount
  point: the bolt from `socket_spark` at the coil's electrode tip and the launch smoke
  from `socket_muzzle` at the mortar's mouth. Both fall back to the mount point, so a
  part still drawing its primitive fallback is never wrong, only approximate.

## Amended by F (the shared surface)

`Arena/fx/machine_audio.gd`, beyond the three `DRIVES` rows, takes **two optional row
keys**, both read with a default so every row written before wave P is untouched to
the decimal:

- **`whine`** names the motor loop. The walker has a hydraulic pack and the hover has
  an impeller; neither has the electric motor `drive_whine_loop` is. Absent means
  `drive_whine_loop`, which is what all five old rows get.
- **`whine_throttle`** is how much of the whine's PITCH is the throttle rather than
  the road speed. Absent means `MachineAudio.WHINE_FROM_THROTTLE` (0.45), which is
  what all five old rows get. The hover is 0.85, because a fan answers the throttle
  almost instantly where a gearbox bogs down: a hover leaning on the boards at full
  throttle screams, and `audio_test` measures that it sits 85 % up its rev where a
  4WD in the same place sits at 45 %.

The walker's row has `"roll": ""`, which is a sound the mixer does not have; it
answers with silence and starts no voice at all. That is deliberate and it is what
"a walker has no roll" means: its contact with the floor is a footfall, which is a
one shot at the stride rate and belongs in `WeaponFx`, not in a loop.

`Arena/fx/fx.gd`'s `on_weapon_state` now asks `WeaponFx.claims_loop(bot_id)` before
it starts a weapon loop. That is a **bug fix as well as a hand-off**: the Stage 3
table maps a weapon's KIND to one of five loops, and three of the six wave P weapons
share a kind with an older weapon and do not share its sound. The napalm cannon is
kind `flame`, so holding the button would have started the flamethrower's BURNER on a
machine lobbing mortar shells; the twin saw would have taken the single saw's cut and
the vortex the plain spinner's rev. `claims_loop` answers off the MACHINE when
`WeaponFx` has not stepped yet, because `fight.gd`'s `_process` runs before the FX
tree's (parent before child) and an answer that waited for the first step would let
the burner sound for one frame of every fight.

## The sounds

Twenty files, every one built the way the object makes its noise, the rule the rest of
`gen-sounds.py` follows. The electric family is the new primitive: an arc is not a buzz
and it is not noise, it is a very fast train of tiny restrikes whose RATE the ear calls
the pitch, so `_arc_train` is that process and the prod (88 restrikes a second, slow
enough to rattle), the coil (702, fast enough to fizz) and the discharge (1400, falling
away as the plasma cools) are the same generator at three time scales.

| File | s | What it is |
|---|---|---|
| `arc_crackle_loop` | 1.50 | 60 Hz driver hum, corona restrikes, ozone hiss |
| `arc_discharge_1/2` | 0.55 | crack, collapsing channel, the plate it terminated on |
| `prod_zap_1/2` | 0.32 | a stun gun's rattle, the prongs ringing, a buzz |
| `drill_grind_loop` | 1.20 | driven waveguide (the shaft), flute chatter at 18 Hz, the motor bogging |
| `twin_saw_loop` | 1.20 | one disc, played twice an octave apart |
| `napalm_launch` | 0.45 | a pressure event in a pipe: falling thump, tube ring, exhaust |
| `fire_patch_loop` | 2.00 | a puddle, not a burner: heavy slow roll, little top, pops |
| `vortex_spin_loop` | 1.00 | blade-rate gated air, the motor UNDER it rather than over it |
| `vortex_throw` | 0.60 | a steel bite and an air whoop that RISES, because the machine is leaving the floor |
| `footfall_1/2` | 0.34 | the ram's hiss, a damped thud, the linkage taking up its slack |
| `hover_fan_loop` | 1.00 | blade passing rate, gated air, bearing |
| `hover_skirt_loop` | 1.00 | the only contact sound in the game with no impulses in it |
| `leg_servo_loop` | 1.00 | a piston pump at 27 Hz, a relief valve, fluid |
| `adaptive_track_loop` | 1.00 | 58 links a second against the plain track's 26, every slap smaller |
| `cook_warning` | 0.20 | a steel casing ticking as it expands. Not a beep |
| `reactive_clang_1/2` | 0.75 | the charge, the plate thrown against its mounts, the mounts |

All nine loops are seamless by the generator's own numeric test (the wrap-around
sample step is no larger than the largest interior step) and again by `audio_test`'s
independent repeat of it off the imported bytes. Every one of the twenty is PCM, never
QOA: the loops because a lossy codec smears the seam, the one shots because they are
transient-dense (the case QOA smears) and because it lets `audio_test` measure their
loudness off the imported bytes rather than taking a peak on trust.

### The crest factor trap, and the three recipes it cost

**Peak normalisation throws away a file whose peak is one needle.** Every file in this
script is normalised to -3 dBFS peak, which means a sound whose loudest sample is a
0.2 ms spike has its whole BODY pushed down to make room for the spike. Measured on
the first build of `arc_discharge`: peak -3 dBFS, loudest 200 ms **-29.4 dBFS**, a
crest factor of 26 dB against a heavy impact's 10. At its catalogue trim it arrived
12 dB under a reactive clang, and the ear says nothing of the kind.

Three files had it and all three were rebuilt rather than trimmed around:

- `_arc_train`'s restrike kernel decayed over 77 microseconds. Every click was a
  needle. Now 0.7 of the stated millisecond, which raised `arc_crackle_loop` with it.
- `arc_discharge`'s crack was six times everything else and decayed in 6 ms. Now 1.9
  times, over 14 ms, with the channel, the plate and the low end raised under it.
  Loudest 200 ms: **-21.0 dBFS**, crest 18 dB, which is what a spark should be.
- `prod_zap` and `cook_warning` had the same shape (20 and 21 dB of crest). Longer
  decays, more body, and `cook_warning` shortened from 300 ms to 200: a file that is
  mostly silence measures as mostly silence.

**This is why `audio_test` now measures one shots in a 200 ms window** and only loops
by whole-file RMS. A whole-file RMS is right for something stationary and wrong for a
bang: it said `arc_discharge` (a 550 ms file with its event in the first 40) was 12 dB
under `reactive_clang` (which has a long plate ring), which is an artefact of file
length and not a fact about either sound. 200 ms is about the ear's integration time
and it is the measure the wave F notes used on the horn and the bell.

### The mix, measured

Every number below is off the imported bytes: file loudness + the `AudioMix.LEVELS`
trim + the bus. Nothing was judged by ear: the owner is at the Mac and nothing was
played at any point.

**One shots**, loudest 200 ms at the master:

| | dB | | dB |
|---|---|---|---|
| vortex throw | -21.6 | prod zap | -28.0 |
| arc discharge | -23.0 | footfall | -29.2 |
| reactive clang | -24.1 | cook warning | -26.3 |
| napalm launch | -24.1 | | |
| *for scale:* chassis thud | -15.1 | bolt tick | -37.0 |

The three big ones (the throw, the discharge, the shove) are the three that change
what is happening in the fight, and all three outrank the three small ones (the prod
bite, a foot landing, the warning tick), which `audio_test` asserts. None of them
passes a heavy impact's headroom (-6.0).

**Loops**, RMS at the master:

| | dB | | dB |
|---|---|---|---|
| vortex spin | -30.3 | hover fan | -31.4 |
| fire patch (two of them) | -26.0 | hover skirt | -31.2 |
| drill grind | -32.2 | leg servo | -32.1 |
| twin saw (the pair) | -31.1 | adaptive track | -32.2 |
| arc crackle | -39.0 | | |
| *for scale:* saw cut | -31.8 | burner | -25.9 |
| *wave F movement:* whine | -31.4 | roll -30.7, track -31.1 |

The twin saw's PAIR lands within 1 dB of the single saw, which is the point: a player
who has heard the Level 5 saw knows how big a saw is. Two fire patches land within
0.1 dB of one flamethrower. The four new drive loops all sit inside the wave F
movement family. `audio_test` asserts each of those relationships rather than the
absolute numbers, so a future file change fails the suite instead of the mix.

## The effects, and the budget

| | before | after |
|---|---|---|
| nodes under `FX` | 74 | **92** (+1 WeaponFx, +3 pools, +14 emitters) |
| `MultiMeshInstance3D` | 16 | **18** (the bolts, the glows) |
| `GPUParticles3D` | 13 | **27** (the emitter pool; every one idle until something asks) |
| `OmniLight3D` | 4 | **4** (unchanged: wave P throws NO new lights) |
| worst frame, new triangles | | **~820** (336 bolt spans + 32 glows + ~450 particle quads) |

Measured peaks over `fx_test`'s wave P phase, which drives every cue in the wave:
**8 emitters of 14, 2 glows of 16, 1 bolt of 4**, and **nothing was ever refused**.

Three deliberate decisions behind those numbers:

1. **No new lights.** `FxLightPool` is capped at four shadowless omnis for the whole
   fight and wave P adds none: the core's heat, the hover's pods and the fire's floor
   glow are all additive billboards in `FxGlowPool`, which is one draw call for
   sixteen slots and costs nothing when they are dark. A real light per machine per
   effect is the one thing in this pass that would have shown up on a phone.
2. **The pool IS the cap.** A hold that cannot get an emitter is refused and returns
   false. A busy frame is quieter, never slower.
3. **Everything sweeps.** A loop, a glow or an emitter that was not asked for THIS
   frame is handed back at the end of it, so a machine that is eliminated mid grind
   cannot leave a saw running or a slot lit. It is the same discipline `MachineAudio`
   uses for its transients and it is what `fx_test`'s teardown check proves.

**Determinism.** Nothing in `Arena/fx/**` added here calls `randf()`, `randi()` or the
wall clock. The bolt's jag is an integer avalanche hash of (strike number, span), the
pitch variation on the one shots is a hash of the world position, and the hover's pod
pulse is two sines on the presentation clock. `fx_test` throws two bolts from two
pools at the same strike number and asserts they are identical to the millimetre.

## The damage decals: not owed, already wired

The brief's coverage said "damage decals API exists, wiring to damage events OWED". It
is not owed: `fight.gd` feeds `DamageDecals` from the presentation drain
(`_mark_damage`, called for every event in `_pending_fx`), a burn scorches and a blow
scratches (`_is_burn`, off the attacker's weapon kind), the arena's flame jets scorch
the floor (`_on_hazard_decal`), and `rules_test.gd` covers all of it with six checks
that pass today. Nothing was changed there and nothing needed to be.

What wave P added is the one mark no damage event can describe: **a fire patch's
scorch**. The fire is not a hit, and it is not where the hit was, so `WeaponFx` places
it itself through the same public API, once per patch, the frame it lands, on the
floor under it. It outlives the fire, which is the whole reason the floor of a
fought-in arena reads as fought in. `fx_test` asserts it is placed once and not once a
frame.

Two things worth one line each for whoever picks this up:

- The core cooking itself is credited to the machine itself with source `"heat"`, and
  `_is_burn` only looks at `source in ["burn", "flame"]` and at the attacker's weapon
  kind, so an overcharge core currently leaves a SCRATCH on its own hull once a
  second. It is harmless and nearly invisible (the mark is on the chassis, under
  everything), but a `"heat"` case in `fight.gd`'s `_is_burn` would make it a scorch,
  which is what it is. That is one line in a file this agent may not touch.
- `damage_event` carries no `source` and no `normal`. Both are worked around here
  (`impulse` distinguishes a blow from a cut, the victim's own `_materials` gives the
  material), but a `source` key on the payload would make the reactive shove and the
  burn scorch exact rather than inferred. Also one line in `bot.gd`.

## The suite

`scripts/test-arena.sh`, all 34 files: **31 pass, 3 fail, and none of the three is
in this agent's area.**

| | |
|---|---|
| `fx_test` | **189 checks, 0 failures**, 2 skipped (particle emission, which headless cannot simulate) |
| `audio_test` | **117 checks, 0 failures** |
| `rules_test` | 318, 0 (it carries the damage decal checks) |
| `determinism_test` | 42, 0. The replay drifts **0.000000000 m** and matches condition, damage events and scrap exactly, which is the proof that none of this pass can reach the fight |
| `commentary_test` | 82 checks, **1 failure**: "and inside the ticker strip", a HUD rectangle |
| `stage_camera_test` | 14, **1**: "a forwarded orbit turns the workshop camera" |
| `test_arena_runs_test` | 24, **4**: a stick drag not reaching the controls, and the names and scrap counter rows |

All six failing checks are in `hud.gd`, `controls.gd` and the workshop stage, which
are agent H's files in this wave; this agent touched none of them. `commentary_test`'s
audio half, which is the part that could have been broken from here (the crowd, the
duck, the Ambience fader, the endgame), passes in full.

`rules_test`, `physics_test`, `determinism_test` and `ai_physics_test` were re-run
after the last edits, green, so the fight-level path is covered against the final tree
and not against an intermediate one.

## The pack

`scripts/build-sim.sh`, **BUILD SUCCEEDED**, warnings unchanged.

| | bytes |
|---|---|
| `arena.pck` at `566ddba` | 48 874 364 |
| `arena.pck` after wave P (E's models and textures, H's screens, this) | 55 896 528 |
| **this agent's share: the 20 new sounds' imported `.sample` payload** | **1 425 020 (1.36 MB)** |

The audio is the whole of my share, because every effect here is code: no new texture,
no new mesh, no new scene. 1.36 MB for twenty sounds is the price of PCM, and PCM is
not optional for any of them (the loops would tick once a revolution under QOA and the
one shots are transient-dense, which is the other case it smears). The lever if it ever
matters is the loop lengths: `fire_patch_loop` is 2 s and `arc_crackle_loop` 1.5 s, and
both would loop at 1 s for 40 % of the total.

## What needs the phone

Nothing here has been seen or heard. The headless simulator has no renderer (so no
particle ever simulates) and nothing was played at any point.

1. **Does the arc bolt read at phone size?** It is drawn as 7 boxes 22 mm across, on
   an additive HDR material at energy 7.0. It is sized to bloom on Forward+; on the
   Compatibility tier `FxMaterials.energy()` tames it to 1.45 and it may read as a
   thin white line instead of lightning. The dial is `ArcBolt.THICK_M`.
2. **Is the fire patch readable, and what do four of them cost?** D1 owed this
   already. There are now four layers on a lit patch (flame cone, smoke, embers,
   floor glow) plus a scorch decal, capped at four patches for fx and two for audio.
3. **Is the stall stutter legible?** Six small arcs a second on a machine that has
   stopped. It is the only cue for three different weapons, so if it is too subtle
   the prod, the arc and the fire patch all lose their effect at once.
4. **Does the hover's skirt dust read under the machine, or behind it?** It is thrown
   backward and slightly up from a point 0.9 of the ride height below the hull, and at
   a fixed 45 degree camera a hover is quite low in frame. `SKIRT_IDLE` is how much of
   it is there when the machine is standing still.
5. **The whole mix on a phone speaker.** Every level above is arithmetic. The numbers
   are right relative to each other; whether the fire loop under a crowd under a bell
   is right is an ear question on a small speaker.
6. **Frame time on the device.** 14 idle GPUParticles3D cost close to nothing; 8 live
   ones with trails on top of the scrap shower has never been measured on an A19.

## The dials

| Want | Turn |
|---|---|
| a fatter or thinner bolt | `ArcBolt.THICK_M` (0.022), `JAG` (0.17) for how wild it is |
| a longer or shorter bolt | `ArcBolt.LIFE_S` (0.11), `FLICKER_HZ` (90) for how hard it blinks |
| the core to warn sooner | `WeaponFx.COOK_WARN_AT` (0.22 of full heat, about 16 s of a weapon at full) |
| the warning to close in faster | `COOK_TICK_SLOW` / `COOK_TICK_FAST` (1.30 s to 0.34 s) |
| the core to stay hot longer | `WeaponFx.COOL_S` (6.0 s); `COOK_FULL` (0.30) is how much cooked condition counts as glowing red |
| more or fewer footfalls | `PartAnim.STRIDE_LENGTH` (0.60 m), because `WeaponFx.STRIDE_M` is half of it and must stay so |
| a busier or calmer stall | `WeaponFx.STALL_EVERY_S` (0.16) |
| more fire on the floor | `WeaponFx.MAX_PATCH_FX` (4) and `MAX_PATCH_VOICES` (2) |
| fewer effects at once | `FxEmitters.POOL` (14), `AMOUNTS` (the particles per flavour) |
| any sound louder or quieter | `AudioMix.LEVELS`, and re-run `audio_test`: it asserts the relationships, so it will tell you what you broke |
| a different sound entirely | the recipe in `scripts/gen-sounds.py`, then `--import`, then `--patch-imports`, then `--import` again |

## Traps found on the way

- **`MultiMesh.get_instance_transform` and `get_instance_color` do not return what was
  written under the dummy renderer.** A headless test that reads an instance back is
  testing the renderer, not the effect: every parked instance came back as identity,
  which made a jag check pass for the wrong reason and a span check return zero. Both
  pools now hand their own state out (`ArcBolt.last_points()`, `FxGlowPool.level_of()`)
  and the test asserts on that. This is worth knowing for any future FX test.
- **`var x := <anything Variant>` is a compile ERROR in this project**, not a warning:
  `Arena/project.godot` treats inference-from-Variant as an error, so `var bot :=
  _bot_by_id(id)` and `var full := machine.has_method(...) and ...` both have to be
  declared. A file with this in it fails to compile, `FightFx` then fails to compile,
  and `fx_test` reports fifteen unrelated failures with no obvious cause.
- **`ready` is a member of `Node`**, so a test double with `var ready := 0.0` is
  "Member redefined (original in native class 'Node3D')".
- **`boring_seconds()` and `cutting_seconds()` are counted in the PHYSICS tick and read
  in the PRESENTATION frame**, and the two are not locked together: a presentation
  frame that lands between two physics ticks sees no progress and would strobe the
  spark stream off and on. `WeaponFx.WORK_HOLD_S` (0.15 s) holds the sparks through
  the gap, which is also what a real shower of sparks does when the blade skips.
- **A `_ = value` discard is not GDScript.** Rename the parameter instead.
- **Half of "the fx for a part" may already be in the MODEL.** Two of the cues in this
  brief were built here and then removed, because agent E's parts carry them: the
  hover's pod glow is a `glow` mesh in each fan throat driven by `PartAnim`, and the
  walker's gait is a real trot with a phase. The rule that fell out of it is worth
  keeping: **read the model agent's notes before writing an effect that lives ON a
  part**, and when an effect has to stay in step with an animation, take the animation
  agent's constant rather than picking one (`WeaponFx.STRIDE_M` is
  `PartAnim.STRIDE_LENGTH * 0.5`, and a test asserts it still is).
- **`gen-sounds.py`'s per-name seeding held.** Twenty files were added in the middle of
  the list and not one existing wav changed a byte, which is exactly what wave F's
  `STREAM_SEED` rework was for. Verified with `git status` after the regeneration.
