# Stage 3 physics notes (agent P)

What was built, what was measured, and what the other agents need to know. Owned files:
`Arena/bot/**`, `Arena/arena/**`, `Arena/tests/physics_test.gd`, this file.

Test command (must exit 0):

```
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/physics_test.gd
```

21 checks, all passing on Godot 4.6.3-stable with Jolt at 60 Hz.

## 1. The one convention everyone needs: axes

A bot's local frame is **+X forward (the wedge lip), +Y up, +Z its right-hand side**.

`heading` in the input record is a **world XZ vector**: `Vector2(x, z)`, length 0 to 1. The desired
world direction is `Vector3(heading.x, 0, heading.y)`. So "drive north-east" is `Vector2(1, -1).normalized()`.
`Bot.place_at(origin, facing)` takes a world facing vector and does the yaw maths; use it rather
than setting the root transform, and it is safe to call before or after `setup()` (it re-anchors
every joint). R already calls it that way.

## 2. Node tree

`res://bot/bot.tscn` is one `Bot` (Node3D, `bot.gd`); everything below is built in `setup()`.
Bodies are siblings under the root (a RigidBody3D must never parent another), joints live in a
`Joints` node so nothing has to walk the body list to find them.

```
Bot (Node3D, bot.gd)
├── Chassis   (BotPart/RigidBody3D, 22.0 kg)  ├── Hull (ArrayMesh wedge) ├── Core (emissive box)
├── WheelFL / WheelFR / WheelRL / WheelRR     (BotPart, 2.5 kg each, CylinderMesh + CylinderShape)
├── Flipper   (BotPart, 4.0 kg)               the arm, a flat box along the wedge slope
│     └── WedgeSensor (Area3D)               what "on the wedge" means, for the throw and the AI
├── PanelFront / PanelSidesL / PanelSidesR / PanelRear / PanelTop   (BotPart, mass by material)
│     └── PanelTop/Srimech (MeshInstance3D, visual only: it leaves with the plate)
└── Joints (Node3D)
      ├── JointWheelFL..RR   HingeJoint3D, motor on
      ├── JointFlipper       HingeJoint3D, limits 0..80 degrees, motor on
      └── JointPanel*        Generic6DOFJoint3D, all six limits locked to zero
```

Eleven bodies per bot, 22 for a fight, inside brief §12's cap. Total mass 42.8 kg for the player
build (steel front / hdpe sides / polycarbonate rear / titanium top) and 48.0 kg for the all-steel
opponent, against the spec's "about 45 kg". Side plates carry HALF the material mass each so the
`sides` PAIR weighs one plate's worth, which is what keeps the totals near 45.

`res://arena/yard.tscn` is one `Yard` (Node3D, `yard.gd`): `WorldEnvironment`, `KeyLight`, `Floor`,
`Grid`, `Walls/Wall{North,South,West,East}` each with a `Chevron` strip, `SpikePatch/Spike00..22`
plus `SpikePatch/SpikeHazard` (Area3D), `OutOfArena` (Area3D, signal `body_out(body)`), and the
`SpawnPlayer` / `SpawnOpponent` markers. `setup(rng)` takes the spike phase from the seed.
Helpers for R: `spawn_position(i)`, `spawn_facing(i)`, `spikes_risen()`, `seconds_to_spike_rise()`,
`spike_patch_centre()` (the AI's "avoid" behaviour needs the last two).

## 3. Drive model: motorised hinges (the spec's first choice, no fallback needed)

Each wheel is a RigidBody3D on a `HingeJoint3D` with the motor enabled; `apply_input` converts the
arcade heading into a per-side target wheel speed and writes it to the motors. The documented
fallback (drive forces on the chassis at the wheel points) IS implemented, in `_apply_drive_forces`,
behind `const DRIVE_MODEL := DRIVE_HINGE` — flip it to `DRIVE_FORCE` and the wheels go free-rolling
on the same joints. It is not needed: hinge motors are stable under Jolt at 60 Hz and the whole
test suite passes on them.

Arcade rules, all in `Bot._drive`:

- heading direction sets the desired yaw, magnitude sets throttle up to `TOP_SPEED_4WD`;
- the yaw error drives a differential (`v_left`/`v_right`), forward effort fades out as the error
  grows so the bot pivots first and then drives;
- past `REVERSE_ANGLE` (135 degrees) the bot **reverses** toward the stick instead of spinning.
  The AI's "rock off a wall in reverse" needs this and nothing else in the spec provides it;
- `secondary` while upright stops the inside track dead: that is the handbrake pivot;
- each lost wheel scales both drive force and turn rate by `alive/total`, and the `drive` condition
  value scales them again.

## 4. Measured Godot 4.6.3 + Jolt facts (all of these cost time; do not re-derive them)

1. **ArrayMesh winding.** For a front face, `cross(b - a, c - a)` points **against** the outward
   normal. Probed against `BoxMesh.get_mesh_arrays()`. `BotMeshes._face()` enforces it, so callers
   pass a polygon in any order plus a rough outward hint.
2. **Hinge motor sign.** A positive `PARAM_MOTOR_TARGET_VELOCITY` rotates node_b about the joint's
   **negative** Z, and the limits are measured the same way round. Wheels want that sign (positive
   target = forward), so their joints use an identity basis. The flipper wants the opposite, so
   `JointFlipper`'s frame is turned 180 degrees about X (`JOLT_HINGE_FLIP`) and then the spec's
   "limits 0 to 80 degrees, fire at +25 rad/s" reads the right way up.
3. **`PARAM_MOTOR_MAX_IMPULSE` is ignored by Jolt on a hinge.** The flipper throw was byte-identical
   at 110 and at 2600. The only tuning knob is the target velocity. The constants are still set for
   the day it is honoured (or for Godot Physics).
4. **`get_contact_impulse` is per contact POINT, not per blow.** A box landing flat gives four
   impulses of roughly a quarter each, so an unsummed reading sits below every threshold in
   `FightTypes.BREAK_MIN`. `BotPart._integrate_forces` now sums per collider before the damage model
   sees it. This is what makes the FightTypes numbers work unchanged.
5. **`PhysicsDirectBodyState3D` has no `get_contact_position`** — it is `get_contact_local_position`.
6. **`StandardMaterial3D.specular` does not exist in Godot 4** (it is a 3.x remap that logs a warning).
7. **Jolt is not bit-deterministic across worlds inside one process.** Two identical seeded runs in
   the same process diverge at the FIRST step (about 0.6 mm), because the solver walks bodies in
   body-ID order and the second world gets recycled IDs in a different order. Across **fresh
   processes** it is exact: 0.000000000 over 24 transform components at tick 600. The test therefore
   runs each seeded simulation in a child process via `OS.execute` and compares. **R should do the
   same in `determinism_test.gd`**: comparing two runs inside one process will fail for reasons that
   have nothing to do with our code, and replays always start a fresh process anyway.

## 5. Tuned numbers (everything not listed comes straight from `FightTypes`)

| constant | value | why |
|---|---|---|
| `Bot.FLIPPER_LAUNCH_IMPULSE` | **115 N s** | the pneumatic throw (see below). Peaks a 48 kg bot at about 0.78 m from a 0.10 m rest, which is the spec's "about 0.6 m" of rise. |
| `Bot.FLIPPER_LAUNCH_FORWARD` / `SPIN` | 12 N s / 8 N m s | throws the target away and tumbles it onto its back rather than straight up |
| `Bot.FLIPPER_FIRE_VEL` | 12.0 rad/s (spec said 25) | the hinge sweep is now presentation plus a scoop, not the throw. Anything faster torques the wielder over. |
| `Bot.FLIPPER_FIRE_IMPULSE` | 1200 | inert under Jolt, kept for the contract |
| `Bot.WHEEL_MOTOR_IMPULSE` | 120 | enough torque that the wheels reach their target speed against floor friction |
| `Bot.TURN_SCRUB_GAIN` | 2.4 | four wheels must scrub sideways to pivot, so the achieved yaw rate is well under the commanded one. Over-commanding by 2.4 lands the bot on `TURN_RATE_4WD` in practice (90 degrees in about 0.7 s). |
| `Bot.SRIMECH_IMPULSE` / `SRIMECH_TORQUE` | 150 N s / 60 N m s | rights an inverted wedge within two presses |
| `Yard.HAZARD_IMPULSE` / `HAZARD_PERIOD_TICKS` | 26.0 every 15 ticks | an Area3D creates no contact impulse, so the hazard supplies one. A bot parked dead centre through one full 1.2 s spike cycle loses about 1.15 of its 11 condition points: painful, not fatal. |
| `Bot.CHASSIS_FRICTION` / `PANEL_FRICTION` | 0.35 / 0.5 | wheels are 1.2 and the floor 0.6 as specified; the hull is slippery so the wedge slides rather than grabs |

### The flipper is a pneumatic ram, not a motor (the Stage 3 gate)

Driving the throw with hinge-motor velocity alone **does not work in a real fight**, and that was
measured, not guessed. With `--pai=charge --oai=normal --secs=45`:

| | before | after |
|---|---|---|
| opponent max chassis height | **0.21 m** | **0.78 m** |
| distinct opponent launches over 0.45 m | **0** | **3** |
| wielder's own max chassis height | **0.65 m** (it launched itself) | **0.29 m** |
| gas spent | 8 of 8, all on nothing | 4 fires, 1 charge spent |
| outcome | none in 45 s | `out_of_arena`, player wins at 5.2 s |

In isolation the old model looked fine because the test started with the arm already under the other
chassis. In a fight the arm meets a slope, a plate or a wheel, and a motor pushing against 48 kg
simply throws the lighter thing: the wielder.

The fix is to model what a flipper actually is. On `fire`:

- `_wedge_target()` asks the arm's `WedgeSensor` (an Area3D standing on the arm's top face) for the
  nearest foreign chassis sitting on it, picked by distance so the choice never depends on the order
  Jolt reports overlaps in;
- the target takes `FLIPPER_LAUNCH_IMPULSE` up, `FLIPPER_LAUNCH_FORWARD` along the wielder's nose and
  `FLIPPER_LAUNCH_SPIN` about the wielder's right axis, applied at its centre of mass;
- the wielder takes the equal reaction **downward**, which is what plants it. It is applied as a
  force held across the 0.12 s fire window rather than as one impulse: dumping 115 N s into the floor
  in a single step reads as damage on the wielder's own wheels.

The hinge motor still sweeps the arm, at a much lower speed, for the look and for the scoop.

### Getting under: chassis and arm profile

The spec's wedge (flat bottom, lip 0.02 m up, a front armour block on the nose) **cannot get under
another copy of itself**, which was measured: two bots just shove each other. Three changes make the
weapon possible at all:

- the lip bottom sits at local `-0.095` while the body floor sits at `-0.07`, so a bot has **0.015 m
  of clearance at the lip and 0.033 to 0.04 m under its body**. A wedge gets under any flank or rear
  it can reach, and under nothing head-on (both lips are at the same height), which is the real sport;
- the front armour plate lies **ON** the slope near the lip, angled to match, never below it. A nose
  block would blunt the wedge and nothing could ever get under anything;
- the arm is 0.44 long and 0.52 wide (nearly the full body width) and rests along the slope, which
  puts its tip's lower corner 0.025 m off the floor: under an opponent's underside, above the lip,
  and clear of the ground. Its friction is 0.08 so it skates when it does touch down.

**Trap, measured:** hanging the arm lower still, so it scrapes the floor at rest, is worse than
useless. It becomes a third ground contact, lifts the front wheels off the floor and the bot pogos
around the arena at 1.5 m. `FLIPPER_REST_ANGLE` must stay at or above `SLOPE_ANGLE`.

**Consequence worth a decision:** a spec-height throw (0.78 m peak) clears the spec's 0.45 m walls, so
a clean flip usually ends the fight by `out_of_arena` rather than leaving the loser on its back. That
is brief §5.3 working as written ("wins by throwing bots out or onto their backs"), but if 5 s fights
are not wanted, the lever is the WALL HEIGHT, not the flipper: dropping the throw far enough to stay
inside puts it back under the spec's 0.6 m.

## 6. Damage model

Contact impulses come out of `BotPart._integrate_forces` (summed per collider, see 4.4) and go to
`BotDamage.apply_impulse_damage`, which is pure bookkeeping. Detachment, reparenting and signals all
happen in `Bot._physics_process` on the next tick, because a joint cannot be freed mid-step. Payload
shape is exactly spec §6, `tick` is `Engine.get_physics_frames()`.

Two deliberate generalisations of spec §6, both documented in the code:

1. **Chassis hits are credited to the armour face they came through.** A thin plate lets a fast heavy
   blow reach the hull in a single step, and crediting the hull would silently lose the damage.
   `Bot.face_for_contact()` maps a world contact point to `front|sides|rear|top`; while that face's
   plate is alive the blow lands on the plate (armour thresholds, that face's material), and only
   once the plate is gone does it reduce `core`. The spec states this rule for the top plate; this is
   the same rule on all four faces, and it is what brief §6 ("the core, reachable only once armour is
   gone") describes.
2. **All parts of one bot are mutually collision-excluded** (`add_collision_exception_with`, dropped
   on detach). Plates, arm and wheels overlap the hull by design; without this every internal
   overlap would read as damage.

Detachment: joint freed, exceptions dropped, layer set to `LAYER_DEBRIS` / `MASK_DEBRIS`,
`contact_monitor` off, reparented under `/root/Fight/Debris` when it exists (else the bot's parent),
every mesh tinted `FightTypes.DEBRIS_TINT`. The flipper **jams** instead (motor disabled, cannot
fire). Wheel damage also bleeds `drive` at `DRIVE_BLEED` 0.25 per condition point.

## 7. API notes for the other agents

- **`opponent_relative` is a VAR, not a method** (instructed deviation from the spec text). Read
  `bot.opponent_relative["distance"]`, write it with `bot.set_opponent_relative(pos, dist)`.
  `bot.opponent_relative_dict()` exists for callers that prefer a call. R already handles both.
- **`opponent_on_wedge()` and `flipper_ready()`** are for the AI: fire only when a throw would land.
  Related deviation from spec §4: **a gas charge is spent only when the ram has something to throw.**
  A dry fire still sweeps the arm, still emits `weapon_fired` and still takes the cooldown, but keeps
  the charge. Without it an AI that fires on proximity empties the bottle on thin air and the weapon
  never lands once.
- Extra public API beyond spec §4, all safe to call: `Bot.place_at(origin, facing)`,
  `Bot.weapon_jammed()`, `Bot.weapon_tip_height()`, `Bot.attached_parts()`, `Bot.face_for_contact()`,
  `Bot.damage` (the `BotDamage`), and `Bot.debug_contacts` / `debug_max_impulse` for tuning only.
- `weapon_height_band()` bands on the arm tip: floor under 0.10 m, mid under 0.30 m, high above.
  `front_edge_height()` is the wedge lip, clamped at 0.

## 8. project.godot settings (R applies these; already done as of 2026-09-13)

Confirmed present and correct: `physics/common/physics_ticks_per_second=60`,
`physics/3d/physics_engine="Jolt Physics"`, layer names 1 arena / 2 bot / 3 debris / 4 hazard /
5 ooa, `input_devices/pointing/emulate_touch_from_mouse=true`, the landscape viewport. Nothing
further is needed from P's side. Jolt's own defaults are all left alone.

## 9. Known weaknesses

1. **Head-on flips are impossible between two wedges.** By construction, and arguably correct, but a
   player who only ever drives straight at the opponent will never land a flip. The HUD height
   readout and the AI's flanking are the teaching affordances; if playtesting says it is too hard,
   the knob is `BotMeshes.LIP_BOTTOM` against `BODY_BOTTOM`, not the flipper power.
2. **Hinge limits are soft.** The flipper overshoots its 80 degree limit under a full-power fire.
   Cosmetic, and it returns.
3. **The throw is an impulse, so it cannot be stalled.** A heavier opponent goes up exactly as far as
   a lighter one minus its own mass term, and nothing about being pinned or off-centre reduces it.
   The only gate is `opponent_on_wedge()`.
4. **A fight can end in five seconds.** The throw clears the 0.45 m walls; see the wall-height note
   above. `--pai=charge --oai=normal` resolves `out_of_arena` at 5.2 s, so the 45 s feel probe is
   really sampling the first 5 s.
5. **`Arena/tests/_feel_probe.gd` reads `fight.get("_state")`**, but R's variable is `state`, so the
   probe never breaks on RESULT and keeps counting height and airborne ticks on frozen bodies. Worth
   fixing in that file (not mine) before trusting its post-result numbers.
6. **Nothing models sustained-push drive-motor wear.** `drive` only degrades from wheel damage.
   Brief §6 also wants it to fall under sustained pushing and flame damage; there is no flamethrower
   in Stage 3 and no push timer yet.
7. **`can_sleep` is false on every attached part** so bodies never doze. 22 always-awake bodies is
   fine on the desktop and was not profiled on the phone; if the tick budget bites, sleeping the
   loser's debris is the first thing to try (detached parts already sleep).
8. **The spike hazard is an Area3D plus kinematic spikes**, so its "impulse" is a made-up constant
   rather than a real contact. Tuned by feel against one parked bot.
9. **Not yet seen on screen.** Every result here is headless. Winding, material colours, the chevron
   strip and the grid are all argued from measurement, not looked at. The desktop window run
   (spec §14) is the gate that is still owed.
