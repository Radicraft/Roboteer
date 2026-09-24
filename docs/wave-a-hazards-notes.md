# Wave A: arena hazards and the shared warning language

Arena gameplay-presentation engineer, 2026-09-24. Brief: the arena quick wins from
`docs/aaa/arenas.md`, ONE hazard warning language across all six arenas, proper hazard
meshes, and proof that none of it moves the simulation. Contracts with the other wave A
leads: `docs/wave-a-contracts.md` §4. Audio catalogue entry: `docs/audio-notes.md` §11.

Owner decisions this builds to: one shared warning language, each arena with its own
sounds and props; warnings make the unwarned hazards fairer (accepted); no simulation
number changes; the fight camera is not touched here (the camera move is the combat
engineer's); warnings start at least as early as the AI can perceive the hazard.

## 1. The warning language

One node per arena, `HazardTelegraph` (`Arena/arena/hazard_telegraph.gd`), built by
`ArenaBase.build()`. It reads `hazard_schedule()` every frame and paints the same stages on
every hazard, whatever it is:

| stage | when | floor | light and lamps | sound | camera and hand |
|---|---|---|---|---|---|
| IDLE | otherwise | dim amber outline round the footprint, always on | lamps at rest | hazard idle loop if any | none |
| ARMED | from the arena's own longer window (spikes 3.5 s, pit 3.0 s, rams 2.0 s) to 1.25 s | amber outline pulsing at 2 Hz | lamps pulse at half | none | none |
| WARNING | the last **1.25 s**, identical everywhere | outline pulses 3 Hz rising to 10 Hz, amber to red; hazard stripes light; a wash fills the footprint from the edge in, full on the frame it acts | a light over the zone and the hazard's own lamps (spike bezel, nozzle bezel, ram lamp bar, pit rim strip) pulse with it | the hazard's OWN wind-up starts, once per group | none |
| ACTIVE | acting | solid red with a flash | lamps solid red | the existing activation sound | camera trauma by kind; haptic if the player's machine is within 1.5 m |
| AFTER | 0.5 s | fades back to IDLE | fades | tail | none |

Always-on hazards (the grinders) have no clock, so they speak the same colours by
PROXIMITY: the ring warms and pulses faster as any machine comes within 1.2 m, and goes
red on contact (with a light kick and a haptic for the player). Turntables do no damage
and keep only the idle outline and their rim lamps.

The wind-ups: `warn_spikes` (a compressor pumping up), `warn_flame` (gas hiss and an
igniter clicking faster), `warn_ram` (a hydraulic pump spinning up), `warn_pit` (a
klaxon). Synthesised in `scripts/gen-sounds.py`, 1.20 s each, built to end on the hit.

### The lead time: 1.25 s, and why

- **What the player has to do in it.** See it (about 0.25 s for a visual onset: simple
  visual reaction time is 0.2 to 0.25 s), turn (a wedge takes about half a second to
  come round, measured in `opponent_ai.gd`'s notes), then drive out. The widest footprint
  is the Coliseum's 2 m spike patch: from the middle that is 1 m plus half a machine,
  about 1.3 m, which is 0.4 s at the 4WD top speed of 3.5 m/s. 0.25 + 0.5 + 0.4 = 1.15 s.
  1.25 s leaves a tenth of a second of slack and no more.
- **Fighting and action game practice.** A move a trained player can react to on sight
  has a startup of roughly 15 to 20 frames (0.25 to 0.33 s) in a fighting game, but that
  is for a READ, not for leaving a place. Games that telegraph an area the player has to
  get out of (boss AoE rings, Fall Guys tiles, Rocket League's floor cues, Insomniac's
  hazards) sit at roughly 0.8 to 1.5 s, the length of "notice, commit, move". The short
  end is for a skilled audience and a small step; this is a phone game with a half-second
  turn, so it sits at the long end, but under 1.5 s so a hazard stays a threat you have
  to respect rather than a timer you can ignore until the last moment.
- **One fixed rhythm.** The same 1.25 s everywhere is what makes it a language: the sound
  always starts the same distance before the hit, the pulse always reaches the same speed,
  so a player who learns one hazard has learnt all of them. Hazards that already warned
  earlier (Drop Zone 3 s, Crush 2 s) keep their longer ARMED stage in front of it.
- **The AI rule.** The owner's rule is that no warning starts later than the AI can see
  the hazard. OpponentAI reads the spike clock up to 3.5 s ahead (Masters `danger_s` 1.5 +
  `HAZARD_LEAD_S` 2.0; it starts leaving at `SPIKE_AVOID_LEAD_S` 2.4), so the spike patch
  ARMS 3.5 s out. The pit joins the AI's danger list only when its 3 s warning starts, and
  jets, rams and grinders are on the AI's list at every tick with no clock, which the
  always-on idle outline matches. `hazard_warning_test.gd` re-derives the AI's horizon from
  `opponent_ai.gd` and fails if it ever grows past the warnings.

## 2. What changed, per arena

**Every arena.** The warning layer; hazard strike shake and haptics; per-arena wall
tint; hazard material slots (below).

**The Yard.** Spike patch: a real spike (collar, eight-sided shaft, point) instead of the
six-sided grey cone, a bezel with a dark recess plate, bored holes and lamp dashes. The
patch now warns: it arms 3.5 s out and runs the shared 1.25 s warning with `warn_spikes`.
Walls: own tint (2.2, a touch warm), no longer the shared default.

**The Grinder.** Disc: a machined dish with 24 teeth, relief slots and a bolted steel hub
(the flat 18-sided cylinder at metallic 0.85 reflected the empty sky and read as a black
hole); a spin-blur card over it (concentric streaks, so it reads as spinning at any frame
rate instead of strobing); a constant idle spark trickle off the cutting edge; a raised
safety collar and a ring of lamp dashes on the well, driven by proximity. Walls 2.3-2.6 ->
1.22-1.46, cold blue-grey (they blew out to white).

**Drop Zone.** Floor tint 0.72 -> 2.1 (the concrete albedo is 0.025 linear, so the old
floor was near black); still the darkest floor in the game. Walls 1.9 -> 1.2 cold slate.
The open pit GLOWS: an emissive floor far down and a red shaft light that comes on with
the cover. Cover leaves toned down from a pale blue square. The shared warning over the
existing 3 s window (the rim strip now runs the shared rhythm) with `warn_pit` (klaxon).
`pit_open` now plays as the leaves start to slide, not at the start of the warning.

**Furnace.** The belt MOVES: a shader draws the slats and the direction chevrons and
scrolls them at the belt's surface speed, read back every frame, so the endgame doubling
shows. Burn fans are soot, not maroon rugs. Nozzles: a housing, a lathed barrel, a bezel
at the mouth that heats amber to red in the warning, a fuel line up the wall. The jets now
warn (they had none): the shared warning per bank with `warn_flame`. Walls 2.7 -> 1.78/1.42/1.14.

**The Crush.** Floor tint 0.88 -> 2.55 (it was unreadable on a phone). Walls 2.35 -> 1.6,
warm. Ram: a cast head (bevelled, ribbed, a steel frame and bolt heads round the striped
face) in painted grey-blue with two chrome piston rods running back into a housing behind
the wall, which slide into view as it presses (it was a blank white block). The shared
warning over the existing 2 s window, with `warn_ram` and a heavy camera kick on the press.

**Coliseum.** Turntables: a darker plate under a top that TURNS at the body's own rate
(the old one never visibly moved), with a painted edge band, four direction arrows and rim
lamps. Walls 2.45 -> 1.2/1.3/1.62, championship blue. Spikes, grinders and jets as above;
the two jets are one warning group.

## 3. Determinism

Rules kept: every new visual runs in `_process` or on the GPU; nothing new has collision;
nothing reads the shared RNG; every collision shape, hazard area and timing is untouched
(new visual nodes are added AFTER the bodies in each builder, so the tree order the
physics sees is unchanged); `hazard_schedule()` only reads.

Proof, `Arena/tests/hazard_determinism_test.gd`: the desktop QA fixture
(`stage3_config.json`, the one `determinism_test` uses) is fought in each of the six
arenas through the real Fight scene; every 30 ticks the chassis transforms, `condition()`,
`hazard_helpers()` and the scrap tallies are serialised with `var_to_bytes` (bit exact) and
hashed. The goldens were recorded on `ac12e1e`, BEFORE any wave A change, and recorded
twice in parallel to prove they are stable:

| arena | ticks | golden (pre-change) | with wave A |
|---|---|---|---|
| yard | 900 | 01f00fa80e15b33a | 01f00fa80e15b33a |
| grinder | 900 | f36c6b2acd67bc11 | f36c6b2acd67bc11 |
| furnace | 1500 | 5c5287aba7cef437 | 5c5287aba7cef437 |
| crush | 507 (KO) | db73cce412bf9a58 | db73cce412bf9a58 |
| drop_zone | 3700 (pit opens at 3027) | 1f7e437398725105 | 1f7e437398725105 |
| coliseum | 1199 (result) | 1b7251eb2acbbd5c | 1b7251eb2acbbd5c |

The Coliseum is then fought again with `HazardTelegraph.enabled = false` and hashes the
same. `Arena/tests/hazard_warning_test.gd` (headless, fast) adds: the schedule is
read-only (a timeline read ten times a tick for 90 s is identical to one never read),
every clock runs down one tick per tick and reads 0 as its hazard acts, the AI rule
above, the telegraph adds no collision object, and its switch works. The existing
`determinism_test`, `arenas_test` (154 checks) and `events_test` (101) stay green.

The goldens are for this Mac's Jolt build (macOS arm64, Godot 4.6.3). A different CPU or
engine may legitimately differ; `-- --record` prints fresh ones, which must be recorded on
a tree without the change under test.

## 4. Hazard meshes and material slots

`Arena/arena/hazard_meshes.gd` builds the spike, spike bezel, grinder disc and well,
flame nozzle, turntable top and ram head as ArrayMeshes in code (parametric and a few
hundred triangles each), with normals and metre UVs, one surface per material slot. They
are render only: every CollisionShape3D and Area3D is built exactly as before.

Material slots, picked up automatically when the materials lead drops a file with the
name (until then each falls back to the current library, tuned not to blow out or sink):

| slot file | used for | fallback |
|---|---|---|
| `assets/materials/hazard_steel.tres` | disc face, spike shafts, nozzle barrel, turntable plate, ram bolts | brushed steel on the mesh UVs, metallic 0.55 |
| `assets/materials/hazard_dark.tres` | housings, collars, wells, recess plates, ram body | flat dark steel / painted grey-blue |
| `assets/materials/hazard_chrome.tres` | ram piston rods | metallic 0.9, roughness 0.14 |
| `assets/materials/hazard_paint.tres` | safety-yellow collars, bezels, turntable arrows | flat safety yellow |

The lamps (bezels, dashes, the ram bar, the pit strip) are plain emissive materials the
telegraph drives; they are not slots.

## 5. Evidence

All in `docs/aaa/img/wave-a/arenas-qw/`, windowed desktop Godot, Forward+:

- `compare_<arena>.jpg`: before (on `ac12e1e`) and after from real fixture fights through
  `Arena/qa/arena_capture.tscn`, plus a frame mid-warning and one at the hit where the
  fight camera caught them (`--roboteer-capture-warn=DIR`, new).
- `warning_language_all_arenas.jpg`: every arena's first timed hazard at the FIGHT camera's
  distance and angle (7 m, yaw -135, pitch 50, 28 degrees), 0.5 s before it acts and just
  after, from `Arena/qa/hazard_closeup.tscn` (new, QA only), which winds each arena's
  clock by hand to the moment.
- `hazard_meshes_closeup.jpg` and `closeup/`: each hazard's new mesh close up.
- `before/` and `after/`: the raw frames.

## 6. Weaknesses and owed

- **Nothing has been heard on a phone.** The wind-ups were measured (level, energy under
  200 Hz) and checked against the mix trims, not listened to on the device. A pass on the
  iPhone 18 Pro Max is owed, and a recorded replacement (CC0) would beat any of the four.
- **Device frame time is owed.** The layer adds one unshaded additive quad per hazard
  (seven in the Coliseum), up to three unshadowed omni lights while warning, and one
  idle spark emitter per grinder. Small, but not measured on the phone.
- **The Crush floor chevrons are one mesh for both rams**, so they still light on the
  arena's own rule (either ram warning), not per ram in the shared rhythm. Splitting the
  mesh per ram is a small follow-up.
- **The ram's striped face is the old chevron BoxMesh**, kept because it reads; a proper
  decal from the materials lead's `assets/textures/decals/` would be better.
- **Grinder contact haptics go to the player only when the player's machine is within
  1.5 m**, which is right for a grinder under the player but will also buzz when the
  opponent is on a disc the player is touching. Acceptable; noted.
- **The telegraph finds the FX and the bots through the World** (`../FX`, `../Bots`),
  which is how fight.gd names them today. If fight.gd renames either, the warnings still
  paint but the wind-ups, shake and haptics go quiet. `hazard_determinism_test` checks the
  node exists, not that it found the FX.
- `fight.gd` was not edited: the existing `hazard_fx` connection and the new
  `../FX` lookup cover everything.
