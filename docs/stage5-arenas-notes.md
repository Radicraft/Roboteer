# Stage 5 arenas (agent A5)

Six arenas, one base class, one test file. `docs/stage5-spec.md` §3, brief §7 (two-way hazards,
floor plans that fit a phone screen at the default framing) and §3 (no copied layouts or floor
markings).

| file | class | id | size | signature hazard |
|---|---|---|---|---|
| `Arena/arena/arena_base.gd` | `ArenaBase` | - | - | the shared floor, walls, render setup, OOA, markings kit and hazard kit |
| `Arena/arena/yard.gd` | `Yard` | `yard` | 10 x 10 | centre spike patch (Stage 3, unchanged) |
| `Arena/arena/grinder.gd` | `GrinderArena` | `grinder` | 10 x 10 | two floor grinders, always live |
| `Arena/arena/drop_zone.gd` | `DropZoneArena` | `drop_zone` | 10 x 10 | 2.4 m pit, cover retracts at a seeded 30 to 60 s |
| `Arena/arena/furnace.gd` | `FurnaceArena` | `furnace` | 10 x 10 | six wall flame jets plus a 2 m conveyor |
| `Arena/arena/crush.gd` | `CrushArena` | `crush` | 10 x 10 | two 0.9 m wall rams |
| `Arena/arena/coliseum.gd` | `ColiseumArena` | `coliseum` | 12 x 12 | spikes + grinders + flame + two turntables |

`Arena/tests/arenas_test.gd` is the suite: 108 checks, all green, and it is picked up automatically
by `scripts/test-arena.sh`. The rest of the project's suite is green with the refactor in place
(bridge 39, rules 181, ai 86, ui 121, fx 72, physics 23, determinism 28, render 97), with one
exception noted at the end of this file.

## What fight.gd has to change (agent R owns the file)

Five edits. Nothing else in `fight.gd` needs to move, and every arena already answers the whole of
the existing contract (`body_out`, `setup(rng)`, `spawn_position`, `spawn_facing`, `spikes_risen`,
`seconds_to_spike_rise`, `spike_patch_centre`), so a fight that never makes these edits still runs
in The Yard exactly as it does today.

**1. Select the scene by `config.arena`.** Replace the single `YARD_SCENE` constant (line 30) with
a table, and pick from it in `_build_world()` (line 223).

```gdscript
# was:  const YARD_SCENE := "res://arena/yard.tscn"
const ARENA_SCENES := {
    "yard": "res://arena/yard.tscn",
    "grinder": "res://arena/grinder.tscn",
    "drop_zone": "res://arena/drop_zone.tscn",
    "furnace": "res://arena/furnace.tscn",
    "crush": "res://arena/crush.tscn",
    "coliseum": "res://arena/coliseum.tscn",
}
const DEFAULT_ARENA := "yard"
```

`_build_world()` runs before `_config` is read in `start_fight()`, so the id has to be lifted the
same way `_rules_mode` already is:

```gdscript
# in start_fight(), beside the _rules_mode lines (about line 620)
_arena_id = str(config.get("arena", DEFAULT_ARENA))
if not ARENA_SCENES.has(_arena_id):
    _warn_once("arena", "unknown arena '%s'; falling back to the Yard" % _arena_id)
    _arena_id = DEFAULT_ARENA

# in _build_world() (line 223)
_arena = _swap_in(_world, "Arena",
    TEST_ARENA_SCENE if _rules_mode == RULES_TEST else ARENA_SCENES[_arena_id])
```

Career tiers map to ids per spec §2: Scrapyard `yard`, Regional `grinder`, National `drop_zone`,
Championship `furnace` / `crush` alternating, Masters `coliseum`. That mapping belongs in Swift,
not here: `fight.gd` only reads the id it is handed.

**2. Fit the camera to the arena that was built, not to the constant.** Two sites, lines 237-238
and 437-438:

```gdscript
# was:  _camera_rig.call("fit_arena", FightTypes.ARENA_SIZE)
var size := FightTypes.ARENA_SIZE
if _arena != null and _arena.has_method("arena_size"):
    size = float(_arena.call("arena_size"))
_camera_rig.call("fit_arena", size)
```

The Coliseum is 12 x 12 and everything else is 10 x 10. Without this the championship arena is
framed 20 % too tight and the walls sit outside the screen.

**3. The positional out-of-arena rule has to know the size.** `Rules.is_out_of_arena()` (rules.gd
line 90) hardcodes `FightTypes.ARENA_SIZE * 0.5`, so **in the Coliseum a bot at x = 5.5 is inside
the walls and is declared out of the arena**. This is the one change that is a bug, not a feature,
and it is in agent R's file:

```gdscript
# rules.gd
static func is_out_of_arena(chassis_position: Vector3, half_extent: float = -1.0) -> bool:
    if chassis_position.y < FightTypes.OUT_OF_ARENA_Y:
        return true
    var half := half_extent if half_extent > 0.0 else FightTypes.ARENA_SIZE * 0.5
    return absf(chassis_position.x) > half or absf(chassis_position.z) > half
```

and at both call sites in fight.gd (lines 1126 and 1316):

```gdscript
Rules.is_out_of_arena(_chassis_position(bot), _arena_half_extent())
```

with

```gdscript
func _arena_half_extent() -> float:
    if _arena != null and _arena.has_method("arena_half_extent"):
        return float(_arena.call("arena_half_extent"))
    return FightTypes.ARENA_SIZE * 0.5
```

The default argument keeps every existing `rules_test.gd` call green.

**4. Give the AI the arena's own read of the danger.** `_ai_context()` (line 890) still only
carries the spike clock, which is "never" in four of the six arenas. One extra key:

```gdscript
func _ai_context() -> Dictionary:
    var ctx := {
        "tick": _tick,
        "spike_centre": _spike_centre(),
        "spike_rise_in_s": _spike_rise_in_s(),
    }
    if _arena != null and _arena.has_method("hazard_helpers"):
        var h: Dictionary = _arena.call("hazard_helpers")
        ctx["hazard"] = h
        # `hazards` is the key agent B5's boss_ai.gd already reads (its own comment says
        # "fight.gd fills it from the arena's hazard_helpers()"), so fill it here and
        # CINDER's throw-them-at-the-nastiest-thing behaviour works in all six arenas.
        ctx["hazards"] = h.get("danger_positions", [])
    return ctx
```

`hazard_helpers()` returns `{next_danger_in_s: float, danger_positions: Array[Vector3],
safe_positions: Array[Vector3]}` on every arena (the Coliseum adds `spike_rise_in_s` and
`flame_in_s` for a driver that wants to time two clocks at once). `OpponentAI` can keep its current
spike avoidance and simply widen it to every entry in `danger_positions`; nothing breaks if either
driver ignores the keys entirely, because `boss_ai.nearest_hazard()` already falls back to the
spike patch when `ctx.hazards` is empty.

**5. Optional, for agent G4: the FX hook.** Every arena emits
`hazard_fx(kind: String, active: bool, position: Vector3)` with kind in
`spikes | grinder | flame | pit | ram`. `FightFx.on_spikes(risen, position)` already exists and is
not currently connected by fight.gd at all; one connection covers all six arenas:

```gdscript
# in _build_world(), after _fx is swapped in
if _arena != null and _fx != null and _arena.has_signal("hazard_fx"):
    _arena.connect("hazard_fx", Callable(_fx, "on_arena_hazard"))
```

The arenas draw their own sparks (simple `GPUParticles3D`) and reuse G4's `FlameCone` for the jets;
the signal is for sound and for anything G4 wants to add on top.

## The floor plans

All six are laid out so the default camera framing (`fit_arena`) holds the whole floor on a phone
screen, and so that the layout is a 180 degree rotation of itself about the centre: whatever is
near your spawn is near theirs. Every hazard is an `Area3D` that reads `BotPart.owner_bot` and
calls that bot's own `hazard_hit`, so "two-way" is not a promise about placement, it is the only
code path there is.

### The Yard (unchanged)

```
 -5                  0                 +5
-5 +--------------------------------------+
   |  P                                   |   1 m seam grid
   |                                      |   P  (-3.2, -3.2)
 0 |              [spikes]                |   O  ( 3.2,  3.2)
   |                                      |
   |                                  O   |
+5 +--------------------------------------+
```

### The Grinder

```
 -5                  0                 +5
-5 +--------------------------------------+
   |  P                       .-.         |   G  grinder, r = 0.55, flush
   |                         ( G )        |      discs at (3.3, -1.1)
 0 |            \  cut lane  /            |      and (-3.3, 1.1)
   |          .-.                         |   markings: keep-out ring,
   |         ( G )                    O   |      broken outer ring,
+5 +--------------------------------------+      cut lane bar, centre cross
```

Both grinders are 2.1 m from the nearest spawn and off the charge diagonal: a grinder is something
you push someone onto, not something the opening drive lands you on. Always live, so
`next_danger_in_s` is always 0 and the arena is about *where*, never *when*.

### Drop Zone

```
 -5                  0                 +5
-5 +--------------------------------------+
   |  P    \      +=========+      /      |   +=+  amber warning strip,
   |        \     | | PIT | |     /       |        blinks 3 s before
 0 |              | |2.4m | |             |   ||   two cover leaves,
   |        /     +=========+     \       |        retract E and W
   |       /                       \   O  |   \ /  approach lines
+5 +--------------------------------------+
```

Pit 2.4 m square, 2.8 m deep, dead centre on the charge diagonal. The cover is a floor for the
first 30 to 60 seconds, which is exactly why it works: the habit both drivers build is the trap.

### Furnace

```
 -5   -3             0                 +5
-5 +====+------------------------------------+
   |belt|   ^      ^         ^                |  ^  north jets at x = -1.0, 1.2, 3.4
   | || |                                     |  v  south jets at x = -3.4, -1.2, 1.0
 0 | || | P                    O              |  P  (-2.5, -1.6)  O  (2.5, 1.6)
   | || |          |      |         |         |  || conveyor, 2 m wide, 1.2 m/s south
   | vv |          v      v         v         |     jet reach 2.5 m, radius 0.55
+5 +====+------------------------------------+
```

The belt discharges into the south jet at x = -3.4. Spawns are NOT the Yard's corner marks: the
Furnace's corners are all hazard, so both bots start in the jet-free middle band (|z| < 2.4) and
clear of the belt.

### The Crush

```
 -5                  0                 +5
-5 +--------------------------------------+
   |####|  P                              |   #### west ram, 3.2 m, z = -1.2
   |####|      >>>>           <<<<        |        stroke 0.9 m east
 0 |####|                                 |   east ram, 3.2 m, z = +1.2
   |    |                    |####|       |        stroke 0.9 m west
   |    |                O   |####|       |   >>>> chevrons, lit 2 s ahead
+5 +--------------------------------------+
```

The rams are offset along Z from each other, so the safe ground is a diagonal corridor rather than
a middle stripe: there is always a way out, but not by driving straight.

### Coliseum (12 x 12)

```
 -6                    0                  +6
-6 +----------------------------------------+
   |  P            ^ jet             .-.    |   T  turntable, r = 2.0, 0.6 rad/s
   |   .-.                          ( T )   |      at (-2.9, 2.9) and (2.9, -2.9),
 0 |  ( G )        [spikes]          `-'    |      opposed spin
   |   `-'                            .-.   |   G  grinder at (-4.6, -1.5)
   |    .-.                          ( G )  |      and (4.6, 1.5)
   |   ( T )              jet v       `-'   |   jets at x = -1.2 (N) and 1.2 (S)
+6 +----------------------------------------+   P (-4.2, -4.2)  O (4.2, 4.2)
```

Spike patch widened to 2.0 m to suit the bigger floor. The turntables do no damage at all: they
take away the one thing a driver relies on, which is that the floor stays where they left it.
Walls 0.95 m (the others are 0.65 m) with 32 banner meshes above them, two livery colours
alternating, no text and no crest (brief §3).

## Hazard timings and damage, as measured

Every hazard runs on the physics tick with its phase drawn in `setup(rng)`; no hazard reads
`_fight_time` or a wall clock.

| hazard | period | live for | impulse | rate | measured on a parked fixture bot |
|---|---|---|---|---|---|
| Yard / Coliseum spikes | 6 s (seeded phase) | 1.2 s | 26 | 4 Hz | -0.28 condition over 7 s |
| Grinder disc | always | always | 30 | 2 Hz | a bot PARKED on a disc loses 4.2 of 11 condition in 2.5 s (its four wheels); a graze costs a fraction of that |
| Flame jet | 8 to 12 s (seeded per bank) | 2 s | 30 | 2 Hz | -3.3 condition for standing through one full 2 s burst, plus `disrupt("drive", 0.9)` after 1 s in it |
| Conveyor | always | always | - | - | carries a bot 3.0 m in 2.5 s (1.2 m/s, as specified) |
| Pit cover | opens once at a seeded 30 to 60 s, shut again 15 s later, reopens 45 s after that | - | - | - | falling in is `body_out`, immediately |
| Crush ram | 10 to 14 s (seeded per ram) | 1.5 s press, 0.6 s hold, 1.0 s retract | 58 | 2.5 Hz plus 0.05 top-face | -3.1 condition per full press |
| Turntable | always | always | - | - | sweeps a bot 1.8 rad in 3 s (0.6 rad/s) |

RNG draw order per arena, which IS the seed (`fight.gd` draws the arena first, then the AI, then
each bot): Yard 1 draw (spike phase), Grinder 1 (disc visual phase), Drop Zone 1 (open tick),
Furnace 4 (north period, north phase, south period, south phase), Crush 4 (west cycle, west phase,
east cycle, east phase), Coliseum 4 (spike phase, jet period, jet phase, disc phase). Each arena
draws the same number of times on every run whether or not the hazard is built, so the draw count
cannot drift with a build.

## Refactor: yard.gd now extends arena_base.gd

`yard.gd` went from 580 lines to 37. Everything it used to hold is in `ArenaBase` with the same
node names (`Floor`, `Walls`, `WallNorth`..`WallEast`, `SpikePatch`, `Spike00`..`Spike22`,
`SpikeHazard`, `OutOfArena`, `SpawnPlayer`, `SpawnOpponent`, `WorldEnvironment`, `KeyLight`,
`FillLight`, `FloorProbe`, `Grid`), the same constants, the same spawn marks, the same spike
cadence and the same render tuning. `fight/test_arena.gd` still subclasses `Yard` and still reaches
for `_built`, `_spikes`, `_spike_area`, `_flat` and `HALF`, all of which it now inherits through
`Yard` from `ArenaBase`. The full suite is green.

**There is no behavioural difference, and that took a measurement to get right.** Stage 3's
`yard.gd` incremented `_ticks` in the middle of `_physics_process` and tested the INCREMENTED value
for the damage cadence; the subclasses here increment after the whole tick. The first version of
this refactor let that stand, reasoning that a one tick shift in a modulo cadence is invisible. It
is not: `builds_test.gd` went from 6 flipper throws in 60 seconds to 0. A fight is chaotic, and a
hazard that fires one tick earlier is a different fight. `_tick_spikes()` therefore tests
`(_ticks + 1) % HAZARD_PERIOD_TICKS`, which reproduces Stage 3 exactly, and the throws came back.
Anyone refactoring a hazard tick in this project should assume the same and prove it with
`builds_test.gd`, not with reasoning.

## Traps found while building this

1. **A flush turntable does nothing.** The floor is one box under the whole arena, so a disc whose
   top face is coplanar with it lets the solver rest the bot on the static floor instead. Measured:
   0.15 rad swept in 3 s flush, 1.8 rad with the disc 0.04 m proud. Same trap waits for anyone
   adding a moving floor panel.
2. **Jolt does honour `constant_linear_velocity` and `constant_angular_velocity` on a
   `StaticBody3D`.** Measured headless before any of this was built: a 20 kg box on a belt reached
   1.16 m/s of a commanded 1.2, and a box at r = 1.2 on a 0.6 rad/s disc swept 0.57 rad/s. The
   surface has to have friction near 1.0; at the floor's 0.6 the bot slips and never reaches belt
   speed.
3. **A hazard that covers the whole bot hits every part at once.** The first tuning (6 Hz on the
   grinder) took a full fixture bot from 11 condition to 6 in under three seconds, because all four
   wheels are inside a 0.63 m radius and a wheel's `BREAK_MIN` is only 18. Rate, not impulse, is
   the dial: 2 Hz gives the same per-part rate as the Yard's spikes at their peak. These are still
   punchy (4.2 of 11 for 2.5 s parked on a grinder, 3.3 for a full flame burst) and they are one
   constant each to retune: `GRINDER_PERIOD_TICKS`, `FLAME_PERIOD_TICKS`, `CRUSH_PERIOD_TICKS` in
   `arena_base.gd` and `crush.gd`. Nothing else has to move.
4. **`hazard_hit` on a chassis part does nothing while the top plate is on.**
   `DamageModel.apply_impulse_damage` refuses a chassis hit unless `core_exposed`. The Crush's
   "flattening" therefore goes through `Bot.take_direct_damage(chassis_part, amount, "hazard",
   "arena")`, which maps a chassis hit onto `armour_top` while the plate is there and onto the core
   once it is gone. That IS top-face damage; `hazard_hit` is not.
5. **`var id := bot.get_instance_id()` will not compile** when `bot` came out of an untyped Array:
   GDScript cannot infer the type and the whole script fails to parse, which then reads downstream
   as "Could not resolve class ArenaBase" in every subclass. Annotate it.
6. **The class cache is not the problem when a global class will not resolve.** The cache had
   `ArenaBase` in it the whole time; the base script simply failed to parse, and a base that fails
   to parse takes every subclass with it. `--check-only --script <the base>` names the real line.
7. **`_physics_process` can be driven by hand.** `set_physics_process(false)` then calling
   `arena._physics_process(1.0 / 60.0)` in a loop runs 90 seconds of hazard timeline in no wall
   clock at all. That is how the determinism check and the "wind the clock to just before the
   event" helpers in `arenas_test.gd` avoid a five minute test.

## Weaknesses, owed, and what I did not do

- **Nothing has been looked at.** Every frame of this is headless. The per-arena tints, the flame
  cone, the banner colours and the emissive warning strips are reasoned against
  `docs/graphics-render-notes.md` and the reference render, not shot. The Furnace's ambient tint in
  particular (1.28, 0.98, 0.76) is the largest departure from G1's measured exposure and is the
  first thing to check in a frame.
- **The grinder sparks are a placeholder.** `_spark_emitter` is a plain `GPUParticles3D` with no
  trail and no authored texture. The FLAME is not a placeholder: the jets use agent G4's
  `FlameCone` (`res://fx/flame_cone.gd`, three layers plus a flicker), driven from the arena's
  physics tick with `external_clock = true` so the flicker is part of the seeded timeline and a
  replay looks like its fight. The hand-rolled cone is still in `_add_flame_jet` as the fallback
  for a checkout without `res://fx/`, and nothing but that path uses `_flame_emitter` now.
  `hazard_fx` is there so G4 can add to any of it without touching an arena file.
- **The Furnace's spawn marks are 5.94 m apart**, against 9.05 m everywhere else, because the
  corners of that arena are all hazard. It is a tighter, hotter opening than the other five. Worth
  a play test before it is called correct.
- **`Rules.is_on_spike_patch` is still hardcoded** to a 1.6 m square at the origin, so the judges'
  control score reads the Coliseum's 2.0 m patch as if it were 1.6 m, and scores nothing at all in
  the four arenas that have no patch. That is agent R's file and it is not obviously wrong, only
  narrow: the general form is "is on a danger position".
- **No arena has an entry gate.** Stage 5 §4 wants a boss to enter from a gate when both bots idle
  for 15 s. There is nowhere for it to come from yet. When that lands it wants a `boss_gate()`
  marker on `ArenaBase` and a door mesh per arena.
- **The Drop Zone's cover can close on a bot that is half in the pit.** It will be pushed out by
  the leaf rather than sliced, because the leaf is an `AnimatableBody3D` with
  `sync_to_physics = false`. It looks odd rather than wrong; nobody has seen it happen yet because
  a bot in the pit is already out of the arena by then.
- **`builds_test.gd` still fails one check that is not the arena's:** "the spinner build removes at
  least one panel (0)". In that run the spinner bot got 2.4 seconds of contact in a 60 second fight
  and took 0.22 condition off without finishing a plate; the other two builds pass every check, and
  the flipper's throws came back as soon as the Yard's tick cadence was made bit-identical again
  (see the refactor section). It looks like a spinner or AI engagement problem, which is agents
  W1/W2's and B's ground, not the arena's, and the weapons files were being edited while this ran.
  Worth one re-run once those settle before anyone chases it.
- **The test fixture bot is 11.9 kg over the weight budget** (steel 3 mm on all four faces, chosen
  so every plate starts at 1.0 condition and the hazard numbers are readable). `Bot.setup` pushes a
  warning about it on every spawn in `arenas_test.gd`. Harmless: hazard damage is impulse
  threshold based and does not read the bot's mass. Worth trimming to a legal build next time
  anyone touches that file.
- **The Crush rams can push a bot into the opposite ram's stroke.** Deliberate, and the best thing
  in that arena, but it has not been play tested for the case where both rams fire together, which
  a seed can produce.
