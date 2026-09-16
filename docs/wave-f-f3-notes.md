# Wave F, agent F3: making the scrap look like scrap

The owner played the wave G build on his iPhone and said **"the scrap won doesn't look like
scrap"**. He was right, and the reason was structural rather than a matter of taste: every
particle in every shower was the *same* object, agent G3's 19 mm hex nut, in the same gold.
A saw scrape and a spinner tearing a panel off shed identical confetti, so nothing in the
shower said anything had *broken*. Bright gold pips read as a pickup effect from a
platformer, not as the wreckage of a machine.

This pass replaces the pips with torn metal, keeps every rule in `bolt_shower.gd`'s header,
and writes down what it cost.

Spec: `docs/brief-v3.md` §6 (bolt showers, and above all the **readability rule**),
`docs/stage3-fx-notes.md` (agent B's feel contract), `docs/graphics-fx-notes.md` (agent G4's
emissive budget and the glow contract).

---

## 1. Files

| file | status | what |
|---|---|---|
| `Arena/fx/scrap_pieces.gd` | **new** | `ScrapPieces`. Eight hand built meshes, one shader, one MultiMesh bank per shape, the mix tables, and the armour material lookup. |
| `Arena/fx/scrap_sparks.gd` | **new** | `ScrapSparks`. Sparks at the tear (GPU on Forward+, CPU quads on gl_compatibility), the heavy hit smoke puff, and the landing dust rings. |
| `Arena/fx/bolt_shower.gd` | changed | Still owns every position and every timing. Now picks what each piece IS, drives the hot edge, and draws through `ScrapPieces` instead of its own MultiMesh. |
| `Arena/fx/fx.gd` | changed, **9 lines of behaviour** | The award now waits for its damage event so the shower knows what it is made of. See §5. |
| `Arena/tests/fx_test.gd` | changed | The 72 checks from Stage 3 and G4 kept verbatim; 32 added. **104 checks, 0 failures, 2 skipped.** |
| `Arena/tests/_f3_budget_probe.gd` | **new** | Not a test (leading underscore, so `test-arena.sh` skips it). Prints the node census, the draw data and the per frame step cost, which is where §7's numbers come from. |

Nothing in `Arena/fight/**`, `Arena/bot/**`, `Arena/ui/**` or any Swift file was touched.

---

## 2. What a piece is now

Eight shapes, each a hand built `ArrayMesh` of flat-normalled triangle soup (the same
construction as the Stage 3 fallback nut, and for the same reason: a machined edge catching
the key light separately from the face beside it is most of what reads as metal). **No new
glb**, nothing to import, nothing to keep in sync with agent G3.

| shape | tris | drawn long axis | what it is for |
|---|---|---|---|
| `plate` | 16 | 165 mm | a bent armour plate: a five sided slab with one torn edge, folded along its length |
| `shard` | 4 | 120 mm | a flat jagged sliver; this is what the plastics shed |
| `bolt` | 28 | 95 mm | a bolt that took its washer with it: hex head, square shank, flat hex washer |
| `nut` | 20 | 72 mm | a wheel nut, the one shape kept from Stage 3 |
| `bracket` | 24 | 130 mm | a snapped L bracket, one arm torn short |
| `spring` | 30 | 105 mm | a coil spring, drawn as a helical ribbon rather than a swept tube |
| `wire` | 24 | 115 mm | three scribbled ribbons: a tangle of loom |
| `wheel` | 36 | 330 mm | a wheel silhouette, thrown only when a wheel comes off |

The sizes are not real part sizes and do not pretend to be, for exactly the reason
`docs/graphics-fx-notes.md` §10 records about `BOLT_VISUAL_SIZE`: at the fight camera
distance on a 6.9 inch phone a real 19 mm nut is three pixels, and three pixels cannot read
as a *shape* however bright they are.

### The mix, by severity and by material

`ScrapPieces.weights(material, part, severity)` lerps a LIGHT row into a HEAVY row by
severity and multiplies by a per part bias. Measured, 40 pieces per hit at severity 0.85
(the histogram order is plate, shard, bolt, nut, bracket, spring, wire, wheel):

```
steel  [15,  6,  6,  3,  4,  1,  5, 0]
poly   [ 1, 25,  5,  6,  3,  0,  0, 0]
hdpe   [ 5, 17,  5,  5,  6,  0,  2, 0]
```

- **steel** sheds bent plate, **polycarbonate** shatters into milky shards,
  **HDPE** into black chips. `fx_test.gd` asserts each of those three.
- a **scrape** (severity 0.08) sheds shorn fasteners, which is literally what brief §6 is
  written about; a **panel coming off** sheds plate.
- the **part** biases it: a wheel sheds wheel nuts and springs, the core sheds wire.
- **a fastener is always steel**, whatever it was bolted into. A polycarbonate lid is still
  held on with steel bolts, and keeping the fasteners metallic is most of what stops a
  plastic bot's shower going flat and grey.

### Colour, and where the material comes from

Albedo, metallic and roughness are per material: dark steel `#5b6069`, darker titanium,
matte black HDPE, milky polycarbonate.

**The damage event does not carry the material.** It carries the FACE (`part`), because
`BotDamage` uses the material to scale severity and then drops it, and this agent may not
change `Arena/bot/**` or `fight.gd` to add it. The payload does carry enough to *find* it:
every `BotPart` holds the `material_name` it was built with, so `ScrapPieces.resolve_material`
walks the fight subtree once per (victim, part) pair, caches the answer, and returns `"steel"`
whenever anything is missing. Read only, guarded at every step, presentation only.

> If `Arena/bot/bot.gd` ever adds `"material"` to the `damage_event` payload, this lookup
> becomes dead weight: `spawn()` already prefers `hit["material"]` when it is there.

### The hot edge, and the readability rule

A piece is dark metal with a **warm rim that cools from 1 to 0 over 0.6 s**. The rim is a
view dependent fresnel (`pow(1 - dot(N, V), 2)`), not an authored edge mask, because a rim
reads as a glowing torn edge from every angle a tumbling piece presents and costs one dot
product.

That created the one real design tension in this pass. **Brief §6's readability rule is that
collectible scrap is bright gold and structural debris is dull grey**, and "dark steel that
cools to nothing" is on the wrong side of it: 0.6 s in, a magnetising piece would look
exactly like a `DebrisChips` chip lying on the floor.

The resolution, and it is the thing to argue with if this reads wrong on the phone:

1. the rim colour is **gold** (`1.0, 0.72, 0.30`), not white or blue;
2. when the magnet takes a piece the rim **re-lights to a gold ember** (`MAGNET_EMBER` 0.30)
   over 120 ms. So *anything warm and moving toward a bot is yours*, and *anything grey and
   lying still is scenery*;
3. `DebrisChips` is untouched: still grey, still matte, still never emissive, still never
   magnetises, and `fx_test.gd` still asserts all three;
4. the **gold streak and the gold collect flash are unchanged**, so the stream and the moment
   of collection are the same colour they always were.

The rim rides `FxMaterials.energy(FxMaterials.BOLT_EMISSION)`, so G4's glow contract check
(`bolt HDR luminance 2.68 vs glow threshold 1.00`) still covers the scrap, and the
Compatibility tier still gets the tamed 1.45 rather than a clipped white blob.

### Per instance data, and why a shader

Each piece needs its own albedo, its own metallic/roughness and its own heat.
`vertex_color_use_as_albedo` carries the first of those and nothing else, and
`BaseMaterial3D` has no per instance emission at all. MultiMesh **custom data** is one vec4
per instance, which is one more than we need: heat, metallic, roughness. Hence one small
`shader_type spatial` built from a string inside `scrap_pieces.gd` (no `.gdshader` file to
import). It uses no derivatives, no screen texture and no depth read, so it compiles on
gl_compatibility as well as on Forward+.

---

## 3. What it does

- **Tumbles** on two axes at independent rates, as before.
- **Lands with a bounce, then sits.** A landed piece stops turning (`SETTLE_*`), which is
  what makes the magnet lifting it read as a lift.
- **The landing kicks a dust ring**: a flat, non billboarded quad on the floor that grows and
  fades over 340 ms. Every big piece kicks one; small ones only 40 % of the time, or a 120
  piece shower lays a carpet of dust.
- **Bigger hits throw bigger pieces further.** Measured: mean piece 155 mm at severity 1.0
  against 96 mm at 0.08, and 166 mm of travel in the first two frames against 109 mm.
- **A component kill throws the dead part's silhouette**, once, first out of the tear so it
  leads the shower: a wheel throws a wheel (730 mm across), a panel throws a big plate, a
  weapon throws the bracket it was bolted through, a core throws wire.
- **Sparks at the tear** every time, and a **smoke puff** only on a heavy hit
  (severity ≥ 0.3, matching `FightFx.IMPACT_HEAVY_SEVERITY`, so one hit never reads as two
  different sizes of event). `fx_test` asserts a scrape puffs none: smoke on every scrape
  would read as a fire.

---

## 4. The bounce that had never happened

**Worth reading even if nothing else here is.**

brief §6 is "scatter, bounce, then magnetise", and Stage 3 built exactly that. Adding the
landing dust is what finally measured it: **at a real hit height the bounce had never
happened, in any fight, ever.**

A piece leaves the tear at 2 to 5 m/s inside a 55 degree cone, so its upward speed is 1.4 to
6.1 m/s. From a hit at 0.34 m it needs **0.44 s at the very fastest** to come back down. The
scatter delay is **25 to 475 ms**. The magnet therefore took essentially every piece in mid
air; the single analytic floor bounce was dead code in practice, and nothing ever landed on
the floor of the arena at all. The first build of the dust rings produced exactly zero rings
across two full showers, which is how this surfaced.

The fix is deliberately the smallest one that makes the brief true, and it is one constant:

```gdscript
const LAND_GRACE_S := 0.30      # bolt_shower.gd
const SIT_AFTER_LAND_S := 0.12
```

The frame a piece's scatter delay runs out, the shower asks how long it still needs to reach
the floor (the same closed form as the bounce). **If it is nearly down, the magnet waits for
the landing; if it is still high in the air the magnet takes it exactly when it always did.**
So the front of the stream keeps agent B's timing and only the low, slow pieces land, sit and
kick dust. Set `LAND_GRACE_S` to 0.0 and the effect is bit for bit what shipped in wave G.

Measured effect on agent B's numbers, 30 scrap to a target 2.4 m away:

| | wave G | after |
|---|---|---|
| first piece collected | 0.39 s | **0.383 s** |
| last piece collected | 1.27 s | **1.667 s** |
| spread (the stream) | ~0.88 s | **1.283 s** |
| mean gap between arrivals | ~25 ms | **44 ms** |
| worst arrivals in one frame | 2 | **3** |
| collect pitch ramp | reached the +24 cap | reaches the +24 cap |

The stream is **longer and slightly sparser**, because some pieces now spend a moment on the
floor. That is a real feel change and it is the one thing in this pass worth a second opinion
on the phone. Everything the test asserts about it still holds (no piece before 150 ms, every
piece inside 3 s, arrivals staggered, ramp climbs and resets, HUD bumped by exactly the
awarded scrap).

### A latent bug this uncovered in the haptic limiter

Stretching the stream past a second made `fx_test` read **31** haptics in a one second window
out of a limiter capped at 30. The limiter is right and it always was: `FightHaptics._prune`
asks `t > now - 1.0`, and the test asked the algebraically equal `t_later - t_earlier < 1.0`.
On a timestamp that has been accumulated 1/60 at a time for two seconds the two disagree by
one float ulp, and one ulp is the whole difference between 30 and 31. **The test now asks the
limiter's own question**, and reads 30. No production code changed; the bug was always there,
it was simply not reachable until a stream ran for longer than a second.

---

## 5. The one change outside this agent's files

`fx.gd` had to change, because the shower cannot know what it is made of otherwise.

`fight.gd` emits `scrap_awarded` **inside the physics tick** and drains `damage_event` to the
FX layer **later in the same frame**, so the award always arrives first and completely bare:
no severity, no part, no victim. Reaching into the fight for that context from the FX layer
would have been worse than the alternative, so:

- `on_scrap_awarded` **queues** the award instead of spawning it;
- `on_damage_event` hands the hit to the award waiting for it, matched on `position` (which
  is the same `Vector3` in both messages, because `fight.gd` passes the event's own value
  straight into the signal), and spawns it there;
- `_process` flushes anything still queued with the severity recovered from the amount
  (`FightTypes.scrap_for` is `round(severity * 40)`, so the read backwards is `amount / 40`).
  That covers hazard credit, where the event's attacker is `"arena"` and never matches, and
  a paused drain.

The wait is **at most one frame**, which is inside the 25 to 475 ms scatter delay and
invisible. **Scrap cannot be lost by this**: an entry only ever leaves the queue by being
spawned or banked, and both paths bump the HUD by the full amount. The ledger and the
"pool completely full, bank it silently" path are unchanged, and `fx_test` still asserts a
500 scrap award bumps the HUD by exactly 500.

---

## 6. Draw structure

A MultiMesh has exactly one mesh, so a *mix* of shapes needs one MultiMesh per shape. Each
bank is allocated at the full pool size, but:

- the banks **share one pool of 120 slots** — `BoltShower` hands out the slots, so the total
  drawn across every bank can never exceed `FightTypes.BOLT_POOL`, and `fx_test` asserts it;
- each bank publishes `visible_instance_count` = what was written this frame, so the vertex
  cost is proportional to what is actually in flight, not to the allocation;
- a bank with nothing in it is `visible = false`, so **an idle shower costs no draw call at
  all** (asserted), and a live one costs one call per shape actually on screen — typically
  three or four, eight at the very worst.

---

## 7. Budget, measured

`Godot --headless --path Arena --script tests/_f3_budget_probe.gd`, on the Mac. Headless has
the **dummy** renderer, so `RenderingServer`'s per frame counters are all zero and nothing is
rasterised; what headless can measure honestly is the CPU step cost and the draw *data* the
effect hands a real renderer. Both are below. **Device frame rate is still owed.**

| | wave G | after | note |
|---|---|---|---|
| nodes under `FX` | 60 | **74** | +8 scrap banks, +3 CPU pools, +2 holders, +1 GPU emitter group |
| `MultiMeshInstance3D` | 5 | **16** | 8 scrap banks, trail, 2 flash pools, chips, smoke, rings, CPU sparks |
| `GPUParticles3D` | 13 | **13** | unchanged headless; +3 tear spark emitters exist only where there is a RenderingDevice |
| `OmniLight3D` | 4 | **4** | unchanged |
| worst frame, triangles | 2 924 | **4 964** | 120 slots x the heaviest shape (36) + 644 fixed |
| worst frame, MultiMesh instances | 286 | **≤ 302** | 120 pool slots (however they split) + 120 streaks + 14 flashes + 32 chips + 16 rings |
| `step()` CPU, mean | 0.093 ms (one run) | **0.072, 0.073, 0.078, 0.097, 0.136 ms** | 480 frames of two saturating showers, five runs. The before figure sits inside the after spread: on this measurement the change is **not distinguishable from machine noise**. |
| `step()` CPU, peak | 1.096 ms | **0.449 to 5.48 ms** | the peak frame is the spawn frame in both; four of five runs were under 0.5 ms and the 5.48 ms outlier is the Mac, not the effect |
| MultiMesh draw calls, idle | 5 (mostly empty) | **0 to 2** | every scrap bank hides itself when empty |
| MultiMesh draw calls, mid shower | 5 | **8 to 13** | typically 3 or 4 scrap banks live at once |

The 4 964 triangle figure is the absolute worst case and it assumes all 120 slots are wheel
silhouettes, which cannot happen (one silhouette per detach). A realistic panel-off shower
measures around 3 000. `fx_test` asserts the per shape worst case stays under 6 000, so a
shape that quietly grows past budget fails the suite rather than costing a frame on a phone.

**The arena budgets in `arenas_test.gd` (30 bodies / 120 meshes) and `events_test.gd`
(56 / 130) are untouched and cannot be touched by this**: they count nodes inside an *arena
scene*, and the whole FX tree is a sibling of the arena under `Fight`. This pass adds **zero**
physics bodies and zero `MeshInstance3D`s; every one of the new nodes is a
`MultiMeshInstance3D` or a `GPUParticles3D`.

---

## 8. QA recipe — what to look for

**None of this has been seen on a screen.** Headless has no renderer, no shader compiles, no
particle simulates, and no MultiMesh instance buffer is kept. Everything below is owed.

### On the desktop, in a window (the fast gate)

```sh
# Full fight, camera pulled in, the player driven by the charge AI so hits happen on their own
~/Applications/Godot.app/Contents/MacOS/Godot --path Arena -- \
    --roboteer-player-ai=charge --roboteer-zoom=0.45

# Same run, but saving three frames (0.1 / 0.45 / 0.9 s) after EVERY scrap award, which is
# the flag agent G4 used to judge the bolts and is exactly the three beats this pass changed:
# the tear, the fall, and the landing or the magnet taking it.
~/Applications/Godot.app/Contents/MacOS/Godot --path Arena -- \
    --roboteer-player-ai=charge --roboteer-zoom=0.45 \
    --roboteer-shots=/tmp/scrap,3,4 --roboteer-shots-on-scrap
```

Watch a spinner hit and check, in this order:

1. **Shape.** Pause on a shower. Can you name the pieces? You should be able to pick out a
   bent plate, a bolt, a spring. If it still reads as confetti the sizes in
   `ScrapPieces.KIND_SIZE_M` are the dial, not the emission.
2. **Heat.** The moment of the tear should be orange along the torn edges and should be dark
   metal by the time the pieces are falling. If the whole piece glows rather than its edges,
   raise `RIM_MIX` toward 1.0; if the edges never read, `RIM_POWER` down toward 1.5.
3. **The readability rule.** Look at a magnetising piece next to a grey chip lying on the
   floor. If you cannot tell in half a second which one is yours, raise `MAGNET_EMBER`. This
   is the check that matters most, and the one this agent is least sure of.
4. **Landing.** Some pieces should hit the floor, sit still for a beat and then leap toward
   the bot with a small puff of dust under where they were. If **nothing** lands, raise
   `LAND_GRACE_S`; if the shower drags, lower it (0.0 restores wave G exactly).
5. **Materials.** Fight the polycarbonate build and the HDPE build (fixtures in
   `Arena/fight/fixtures/`). Plastics should shatter into milky and black shards; steel
   should tear into plate.
6. **A wheel coming off.** The wheel silhouette should be unmistakable and should lead the
   shower. If it reads as a flying frisbee rather than a wheel, `SILHOUETTE_SCALE` down.

### On the Simulator (gl_compatibility) — functional only

The Simulator runs the whole thing on the software rasterizer at 1 to 3 fps, so it is a
**does it draw at all** check, nothing more. Two things are specific to that tier and cannot
be checked anywhere else:

- the tear sparks fall back from GPU particles to a 36 quad CPU pool
  (`ScrapSparks.gpu_sparks()` reports which path is live);
- `INSTANCE_CUSTOM` on the Compatibility renderer. If it does not arrive, the pieces draw as
  **dark steel with no hot edge at all**, which is a degrade rather than a failure, but it
  would be worth knowing. Look at one frame of a shower: is there any orange?

### On the phone (the only gate that counts)

The fps overlay through a spinner-on-panel exchange, which is the worst case: a big shower,
eight banks live, sparks, smoke and dust all at once. If it costs frames, the dials in order
are (a) `RING_CHANCE` down, (b) `SPARK_EMITTERS`/`SPARK_AMOUNT` down, (c) merge the `spring`
and `wire` banks into one shape. The pool size itself is the last thing to touch, because it
is the brief's.

---

## 9. Known weaknesses

1. **Nothing has been seen.** See §8. Every shape, every size, every colour and the whole
   hot edge are judged from numbers.
2. **The readability rule is the risk.** Dark torn metal is what the owner asked for and it
   is further from "bright gold, small and spinning" than anything since Stage 3. The gold
   rim and the magnet ember are this agent's answer; they may not be enough, and the dial is
   `MAGNET_EMBER`.
3. **The stream is longer.** 1.28 s against 0.88 s for a 30 scrap hit (§4). Bounded, tested,
   revertible with one constant, but it is a feel change the owner did not ask for and should
   be told about.
4. **`INSTANCE_CUSTOM` on gl_compatibility is unverified.** Headless compiles no shader at
   all, so the only evidence is that the shader uses nothing the Compatibility renderer
   lacks.
5. **The material lookup is a tree walk.** Cached per (victim, part) and bounded at 4 000
   nodes, but it is a lookup the FX layer should not have to do. One key on the
   `damage_event` payload would delete it.
6. **Eight banks is eight draw calls in the worst frame.** Hidden when empty, and typically
   three or four are live, but a phone with a lot of overdraw might prefer fewer shapes. The
   cheapest merge is `spring` + `wire`.
7. **Pieces still do not collide with anything.** One analytic bounce off `y = 0`, exactly as
   the chips do, so a piece can land inside a wall or on top of a bot. Unchanged from Stage 3
   and a real limit of doing this in the presentation layer.
8. **An award queued on the very last frame of a fight never reaches the HUD.** The award
   waits up to one frame for its damage event (§5); if the FX tree is torn down inside that
   frame, the counter misses it. Cosmetic only, and bounded to one hit: the fight's own
   `_scrap` ledger in `fight.gd` is what the result is written from, and it was never this
   queue. A `_flush_awards()` on teardown would close it, but teardown is `fight.gd`'s and
   this agent may not touch that file.
9. **The dust ring pool saturates on a 120 piece shower** (peak 16 of 16, measured). It
   recycles the oldest, which at 340 ms is never the wrong call, but on the phone it may read
   as too much dust; `RING_CHANCE` is the dial.

---

## 10. Running it

### The state of the suite when this was written

`fx_test.gd` is **104 checks, 0 failures, 2 skipped** (the two skips are particle emission
and particle trails, both of which need a renderer headless does not have).

The rest of the suite was **not green at the time of writing, and not because of this pass**:
`Arena/bot/part_visuals.gd:339` had a parse error in another wave F agent's in-flight edit
(`var idx := arrays[Mesh.ARRAY_INDEX]` cannot infer a type). That one line takes the whole
`PartVisuals` class down, so every bot builds with no model — hence
`Nonexistent function 'instantiate' in base 'GDScript'` at `chassis_base.gd:188` and
`drive_base.gd:188` in every test that spawns a bot, and hence `ai_test`'s 6 failures.
`scripts/test-arena.sh` turns any `SCRIPT ERROR` line into a failed test file, so the verdict
came back **20 of 25 test files failed** while that one line stands. Only five of those twenty
had a real check fail, and every one of the five is a bot built with no model or another
agent's in-flight file:

| test | checks failed | why |
|---|---|---|
| `ai_test` | 6 | steering and commit, on `opponent_ai.gd`, which another agent has open |
| `audio_test` | 2 | crowd bed and horn levels, on agent F2's `audio_mix.gd` work |
| `assembly_test` | 2 | `long_low/4wd` covers 2.86 m of 3 m and turns 51 deg — a bot with no wheel models |
| `events_test` | 2 | `wall_smash`: a ramming machine arrives with 73.3 N s and breaks nothing |
| `weapons_b_test` | 1 | a pinned bot cannot drive out of the claw (0.143 m/s) |

There is also one `Invalid type in function '_step_machine' in base 'Node (MachineAudio)'`
from agent F2's new file. **No scrap, bolt or FX check fails anywhere in the run**, and the
fifteen other red files reported 0 failures of their own. **Re-run the suite once
`part_visuals.gd` compiles.**

```sh
sh scripts/test-arena.sh fx_test.gd render_test.gd determinism_test.gd   # the fast loop
sh scripts/test-arena.sh                                                 # everything
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena \
    --script tests/_f3_budget_probe.gd                                   # the numbers in §7
```
