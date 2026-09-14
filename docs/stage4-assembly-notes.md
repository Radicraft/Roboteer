# Stage 4 assembly notes (agent P2)

What the catalogue-driven Bot is, what it is made of, and the things that will bite
you. Owned files: `Arena/bot/**` (except the nine weapon scripts W1 and W2 write),
`Arena/tests/physics_test.gd`, `Arena/tests/assembly_test.gd`, this file.

Test commands, all headless, all must exit 0:

```bash
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/physics_test.gd    # 21 checks
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/assembly_test.gd   # 23 checks
scripts/test-arena.sh                                                                                   # the lot
# feel probe (not part of the suite): fires >= 3 each, damage events >= 5, opponent peak >= 0.5 m
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/_feel_probe.gd -- --pai=normal --oai=normal --secs=45
```

After adding any script with a `class_name`, run `Godot --headless --path Arena --import`
once or the global class cache will not know about it and every test will fail to
resolve the name.

## 1. Module map

`bot.gd` no longer knows what a wedge is. It owns the body list, the damage model,
the queries and the signals, and it loads three modules by catalogue id:

| file | class | what it owns |
|---|---|---|
| `bot/bot.gd` | `Bot` | assembly order, `register_part`, damage intake and flush, detach, queries, `build_summary` |
| `bot/build_rules.gd` | `BuildRules` | the weight formula and the legality sentences (mirrored in Swift) |
| `bot/catalogue.gd` | `PartsCatalogue` | `res://data/parts.json` and the model manifest, both cached in statics |
| `bot/part_visuals.gd` | `PartVisuals` | .glb instancing, socket read-back, material binding by slot name, debris tint |
| `bot/part_meshes.gd` | `BotMeshes` | the Stage 3 wedge, plus lofts (a stack of rectangular rings) for the other hulls |
| `bot/chassis/chassis_base.gd` + 6 | `ChassisBase` | collision shapes, hull visual, every socket, mass, centre of mass, inverted behaviour |
| `bot/drive/drive_base.gd` + 5 | `DriveBase` | wheel bodies, hinges, the arcade steering, per drive degradation |
| `bot/weapons/weapon_base.gd` | `WeaponBase` | the weapon contract (W1 and W2 write against it) |
| `bot/weapons/flipper.gd` | | the Stage 3 flipper, moved, unchanged, as the reference weapon |
| `bot/weapons/inert_weapon.gd` | | the fallback for a weapon id with no script yet |
| `bot/damage.gd` | `BotDamage` | condition bookkeeping, impulse and direct damage, thickness scaled thresholds |
| `bot/part_body.gd` | `BotPart` | one rigid body, summing contact impulses per collider inside the step |

Assembly order in `setup()`, and it matters: chassis module, utility effects that
change the hull (skirts lower the clearance, the counterweight moves the centre of
mass), chassis body, joints root, drive, damage, weapon, armour, utility visuals,
collision exclusions, initial damage.

A missing module is never fatal. No chassis script falls back to `ChassisBase`
(a plain box from the catalogue footprint); no drive script falls back to
`DriveBase`; no weapon script fits `inert_weapon.gd`, a plate of the right weight
in the right place, and logs one arena-style warning. A config can always name a
part this build of the game does not have.

## 2. THE MASS SCALE, the one number to understand

The catalogue's kilograms are the DESIGN budget: 100 kg buys the build, and that is
the number the player sees in the workshop. **The simulation runs at 0.52 of them**
(`Bot.MASS_SCALE`).

That is not a fudge, it is a measurement. Stage 3's signed-off wedge simulated at
42.8 kg and prices at 81.5 kg in the catalogue; its all-steel opponent simulated at
48.0 kg and prices at 92.6 kg. Both ratios are 0.52 to within one percent, so
running the catalogue numbers raw would have doubled every contact impulse (the
`FightTypes.BREAK_MIN` / `BREAK_MAX` table is calibrated against the Stage 3 masses)
and left the 115 N s pneumatic throw lifting a 93 kg bot by 78 mm instead of 780 mm.
The scale is uniform, so a heavy build is still heavy relative to a light one, which
is the only property the game trades on.

Everything passed to `register_part(body, key, kind, mass_kg)` is in CATALOGUE
kilograms; the scale is applied there and nowhere else. `assembly_test` asserts the
sum of the body masses is within 10 percent of `BuildRules.total_weight * MASS_SCALE`
for all 232 legal combinations.

## 3. Sockets

Every chassis .glb carries 22 socket empties (agent G3, `docs/graphics-models-notes.md`).
`PartVisuals.read_sockets()` reads them off the instantiated scene into a name to
position dictionary; `ChassisBase.socket_point(name, fallback)` uses them when they
are there and a number computed from the catalogue footprint when they are not, so a
bot assembles with no art at all. `assembly_test` checks all 161 sockets read back
within 0.5 mm of the manifest.

| accessor | socket | notes |
|---|---|---|
| `weapon_socket(kind)` | `socket_weapon_front` / `_top` / `_shell` | asking for a mount the hull does not have falls back to its catalogue `mount_weapon` |
| `wheel_slots(drive_id)` | `socket_wheel_2wd_*`, `_4wd_*`, or the 6wd row | falls back to the catalogue `wheel_slots` rows, which are `[x, z]` pairs in the same frame |
| `armour_socket(face)` | `socket_armour_front|rear|sides_l|sides_r|top` | returns `{transform, transforms, size, thickness, thickness_m}`; `transforms` has two entries for the sides |
| `utility_socket(i)` | `socket_utility_0|1` | 0 is the rear deck, 1 is front and low |
| `srimech_socket()` | `socket_srimech` | |

**Where the weapon mounts** is decided by the weapon first and the hull second. A
floor-band weapon goes on the nose even on a Tall Tank, because a flipper mounted
370 mm up cannot get under anything; a high-band weapon or a crusher takes the deck
wherever there is one; the full body spinner takes the shell's spin axis.

**The wedge ruling** (`docs/graphics-models-notes.md` section 8): on a ramped hull
the armour plate bolts to the ramp first and the weapon rides on top of it, so
`ChassisBase.weapon_socket("front")` lifts the socket along the ramp normal by
`front_armour_stack()` (thickness x 12 mm, plus the plate's 13 mm raised step, plus
4 mm of air), and `flipper.gd` pitches its MODEL back by 6.5 degrees because the
model is authored with its own base plate already sloping.

**The wedge's own pivot is pinned**, deliberately, to Stage 3's measured
`(0.1115, 0.0977)`. The general rule lands at `(0.086, 0.096)` for the signed-off
three-unit steel front: the same height to two millimetres. It is pinned rather than
computed because the rule moves with armour thickness, and a one-unit front plate
would drop the arm 22 mm, which is exactly the measured pogo trap (an arm that
reaches the floor becomes a third ground contact, lifts the front wheels and the bot
bounces around the arena). The whole flipper tuning is signed off against that point.

## 4. Material binding

Match by `resource_name`, never by surface index: the exporter drops slots a part
does not use, so index 0 is `steel` on one part and `livery` on the next.
`PartVisuals.bind(node, livery, overrides)` walks every `MeshInstance3D` and sets a
per-instance **surface override** (never `surface_set_material`, which would mutate
the shared mesh resource for every bot in the fight).

| slot | material |
|---|---|
| `steel` / `titanium` / `polycarbonate` / `rubber` | agent G2's `.tres` PBR sets |
| `hdpe` | G2's moulded HDPE tinted 85 percent toward the bot's livery (Stage 3's rule: HDPE is the colourable plastic) |
| `livery` | painted metal: the livery colour, roughness 0.42, metallic 0.25, clear coat |
| `dark_metal` | brushed steel darkened to 0.10 and metallic 0.85 |
| `core_glow` | emissive teal, energy 1.6 |

Armour plates bind the FACE material onto the plate model's `steel` surface, which
is why `plate_flat` works for steel, titanium and polycarbonate. An `hdpe` face uses
`plate_flat_hdpe` instead (a moulded part, not a cut one); the front face uses
`plate_sloped`; a scoop utility replaces the front plate's model with `scoop.glb`.

Materials are cached in statics, per slot and per livery colour, so 232 bots in one
test process build a handful of materials rather than two thousand.

## 5. The body budget, and what is NOT a body

Brief section 12 caps a bot at chassis + six wheels + weapon + four panels. The
armour is five plates (the sides pair shares one condition), so the real cap the
test enforces is `1 + wheels + 5 + 2`.

To stay inside it, **every utility part is a visual plus extra collision on the hull,
never a body of its own**: the skirts and the rear wedge add a `CollisionShape3D` to
the chassis body, the magnets, the spare battery and the counterweight are meshes
plus an effect, and the srimech rides on the top plate (so it leaves with the plate,
as in Stage 3). Their catalogue weight is added to the chassis body's mass. The cost
is that a skirt cannot be knocked off; the alternative was four more rigid bodies per
bot and 45 bodies in a three-bot rumble.

**Tracks are three road wheels a side, not four.** The spec text says four, and the
spec's own body count test says tracks count inside the six wheel allowance; three a
side satisfies both and the belt is a visual on the chassis rather than a body. When
a side's condition reaches zero the belt is hidden, that side's motors are switched
off and the bot circles, which is the catalogue's promise for tracks.

## 6. Drive

`DriveBase.drive()` is Stage 3's arcade steering with every number now read from the
catalogue: `top_speed`, `turn_rate`, `push_force` and `traction` per drive, and
`turn_rate_factor` per chassis. Wheel friction is `1.2 * traction`, the hinge motor
impulse is `120 * push_force / 1.5` (Jolt ignores it on a hinge, kept for the
contract), and the wheel keys are derived from the slot POSITIONS, so
`condition["wheels"]` always reads front-left, front-right, middle, rear whatever
order the catalogue or the .glb lists them in.

**`TURN_SCRUB_GAIN` was re-measured: 2.4 became 2.8.** Stage 3 put the wedge's wheels
0.35 m off the centre line; the catalogue and the models put them at 0.30, which is
14 percent less leverage, and the turn check failed at 20.9 degrees until the gain
was raised. A wedge is back on its Stage 3 0.7 s for a 90 degree turn (5.9 degrees
closest approach in the test).

**The input record gained an optional `turn` field** (-1..1, default 0) for agent C's
twin-stick tank scheme, which cannot express a pure pivot with a heading vector
alone. With `turn` non-zero and the heading short (under 0.25), the drive runs its
two sides equal and opposite at `turn * turn_rate` and adds no forward term at all;
each drive pivots at its own catalogue rate, so tracks are slow at it and omni
commands the yaw rate directly on its rollers. Positive `turn` is nose to the bot's
LEFT (increasing yaw), the same direction a positive heading error turns it, so a
controller mapping a right stick to it should negate.

Three minimal edits in R's files went with it, and they are R's to keep or change:
`FightTypes.empty_input()` carries `"turn": 0.0`; `FightTypes.replay_row()` always
writes a sixth column (so every row is six wide and a replay reproduces a pivot);
`replay_recorder.input_for()` reads it, tolerating five-wide rows recorded before it
existed; and `rules_test`'s row-shape assertion was widened to match.

Per drive: 2WD circles when it loses a wheel (it falls out of the model, nothing is
special cased); 6WD has two wheels of redundancy before its power scale falls at all;
tracks free-wheel a dead side; omni STRAFES (the heading drives the bot sideways
without turning, as a force on the chassis because Jolt hinges have no anisotropic
friction) and pivots on `secondary`.

Inverted, an invertible hull's motor signs and sides are swapped, because a wheel
upside down touches the floor on its far side. The Pyramid asks for a 0.17 m wheel
(the catalogue's own `invertible` rule: the wheel radius must clear the half height,
and the exported hull reaches 0.162 m), so the whole bot rides that much higher;
`Bot.ride_height()` is the live number and `place_at` uses it.

## 7. Damage

Unchanged in shape from Stage 3, with four additions:

1. **Thickness scales the thresholds.** `BREAK_MIN` and `BREAK_MAX` for a plate are
   multiplied by `0.7 + 0.3 * thickness`, so a four-unit plate shrugs off what a
   one-unit plate loses a corner to.
2. **`rear_wedge`** multiplies damage taken on the rear face by 0.6, and the hull's
   `drive_fragility` (the Shell's 1.6) multiplies wheel damage.
3. **`opponent_damage_tick(part, amount, source)`**, called on the ATTACKER's Bot with
   one of the victim's bodies, is the continuous damage path for the saw, the crusher
   and the flame. It bypasses the impulse thresholds (there is no impulse), resolves
   the material factor from the catalogue (`armour.material.<m>.factor.cut`, which
   `FightTypes` does not carry), records an ordinary damage event with the attacker's
   id, and routes a chassis hit through the top plate while the top plate lives.
4. **`disrupt(kind, seconds)`** cuts this bot's weapon or drive for the duration.

`max_contacts_reported` is **24**, not Stage 3's 6. The cap is not a budget: above it
the engine reports an arbitrary subset of the contacts and which ones depends on
recycled RIDs, which is a determinism hazard (flagged by R2). `_integrate_forces`
sums per collider anyway, so the higher cap costs a few additions.

## 8. How W1 and W2 add a weapon

One script, `Arena/bot/weapons/<catalogue id>.gd`, `extends WeaponBase`. The Bot
finds it by id, sets `mass_kg` to the catalogue weight and calls
`build(bot, socket, spec, rng)`. `flipper.gd` is the worked example.

```gdscript
extends WeaponBase

func _build() -> void:
    var body := BotPart.new()
    body.name = "Bar"
    # ... collision shape, and a visual from PartVisuals.instantiate("<part id>")
    body.transform = Transform3D(Basis.IDENTITY, socket_transform().origin)
    bot.register_part(body, FightTypes.PART_WEAPON, "weapon", mass())   # catalogue kg
    var joint := HingeJoint3D.new()
    bot.add_joint(joint)              # joints live under the bot's Joints node
    joint.node_a = joint.get_path_to(bot.chassis)
    joint.node_b = joint.get_path_to(body)
    # bot.weld(body) instead, for a weapon with no moving parts
```

What the Bot gives you: `bot.chassis`, `bot.chassis_module` (sockets, hull
dimensions, `weapon_rest_angle()`), `bot.livery`, `bot.gas_charges`,
`bot.spin_up_factor()` (0.7 with a spare battery, ALREADY resolved, multiply your
`spin_up_s` by it), `bot.speed_factor()`, `bot.opponent_relative`,
`bot.emit_weapon_fired()`, `bot.register_part`, `bot.add_joint`, `bot.weld`,
`bot.register_visual(condition_key, node)`, `bot.opponent_damage_tick(part, amount)`
and, on the victim, `bot.disrupt(kind, seconds)`, `flip_resistance()` and
`tip_resistance()` (the flipper divides its launch impulse and its tumble torque by
those, and your weapon should too).

Rules, all of them load-bearing:

- register EVERY body you build, with `part_kind` "weapon". The Bot then owns
  detach, damage, freeze and the collision exclusions for it, and a weapon that
  reaches zero condition JAMS (dead weight) rather than falling off;
- `apply_input(pressed, fired, dt)` is called before the step, `physics_tick(dt)`
  after it. `pressed` is the level, `fired` the rising edge. The flipper reads the
  LEVEL because Stage 3 did and its cooldown gates repeats; an axe wants the edge;
- forces are cleared every step, so anything held (the flipper's reaction, a
  crusher's clamp) must be re-applied every tick;
- never touch the other bot directly. Read `bot.opponent_relative`, use your own
  Area3D, and damage through `opponent_damage_tick`;
- draw randomness only from `rng`, or the determinism test will find you;
- set `bot.debug_weapon = true` in a probe and print what each press did. That flag
  is how the 2026-09-13 launch regression in section 10 was found, and a weapon that
  cannot tell you why it did nothing is a weapon you will be debugging by eye;
- `readiness()`, `status_text()`, `height_band()` and `reach()` are the AI's and the
  HUD's only view of the weapon. `weapon_readiness()` on the Bot returns 0 while the
  weapon is jammed or disrupted, so you do not have to handle that.

The Shell's `ring` mesh is waiting for `full_body_spinner.gd`: while that script does
not exist, `chassis/shell.gd` keeps the ring as part of the hull (a shell with no
ring would have an open flank). Once the script is there the hull hides its ring and
shrinks its collision to the hub, and the weapon owns a ring body on a vertical
hinge. Nothing else needs changing.

## 9. `build_summary()` (what the workshop shows)

```
{name, chassis, drive, weapon, utility[],
 weights: {chassis, drive, weapon, utility, armour, armour_faces{front,sides,rear,top}},
 total, budget, simulated_mass, clearance, com_height, wheels, bodies,
 weapon_reach, weapon_band, errors[], valid}
```

Weights are catalogue kilograms (what the player buys); `simulated_mass` is what
Jolt sees. `errors` is `BuildRules.validate()` on the config the bot was actually
built from, so an illegal build still assembles and still says why it is illegal.

## 10. The throw, and the mass-distribution trap (fixed 2026-09-13)

**Symptom.** After R's AI change to a 1.15 m standoff with a 2 s commit, the feel
probe stopped launching anything: `--pai=charge` gave an opponent peak of 0.46 m
against Stage 3's 0.78 m sign-off, and `--pai=normal` gave 0.45 / 0.38 with zero
airborne ticks. Fires and damage events were normal and the gas bottle emptied, so
the ram WAS finding a target and firing: it just was not throwing anything.

**Cause, and it is worth understanding before touching this weapon.** The throw is
applied to the victim's CHASSIS BODY, not to the machine. The chassis leaves at
`J / m_chassis` and then drags its wheels and plates up through their joints against
the floor, so how high the bot goes depends on the chassis' SHARE of the total mass.
Stage 3 hard coded a 22.0 kg chassis in a 48.0 kg bot: 46 percent. Stage 4 takes the
split from the catalogue, where the hull is 30 kg, the flipper arm alone is 16 kg and
a steel armour set is another 30, so the chassis is nearer 35 percent. The same
impulse now drags half again as much dead weight. Instrumented per fire (`Bot.debug_weapon`
makes the flipper print what each press did), every launch found the opponent's
chassis, and every launch peaked at 0.46 m.

It did not show in `physics_test` because the scripted throw there catches the victim
squarely on the arm from behind, which is the best case; in a fight the victim is
caught nose on with its rear wheels planted, which is the worst, and the margin the
Stage 3 numbers had was spent.

**Fix.** `flipper.gd` normalises the launch impulse by the victim's chassis fraction:

```
scale = clamp(REFERENCE_CHASSIS_FRACTION / (m_chassis / m_total), 0.75, 1.5)
```

with `REFERENCE_CHASSIS_FRACTION = 22.0 / 48.0`. A bot built like Stage 3's takes
exactly 115 N s; one carrying more of its mass outside the hull takes proportionally
more, and the signed off throw survives whatever the builder bolts on. Heavier bots
are still harder to throw (mass is in the denominator either way) and
`flip_resistance` still divides on top of it. The wielder's reaction scales with the
throw, as an equal and opposite should, and it is still spread across the 0.12 s fire
window rather than dumped in one step.

The catalogue's wedge build lands on scale 1.30. Numbers before and after, same seed:

| probe | before | after |
|---|---|---|
| `--pai=charge` opponent peak | 0.46 m | **2.21 m** (airborne ticks 7 to 298) |
| `--pai=normal` peaks | 0.45 / 0.38, 0 airborne ticks | **0.99 / 1.22**, 195 / 480 airborne ticks |
| `--pai=charge` damage events | 7 | 38 |
| `physics_test` scripted throw | 0.81 m peak (rise 0.69) | 1.00 m peak (rise 0.89) |
| `physics_test` wielder peak | 0.13 m | 0.13 m |

The cost, stated plainly: the best case scripted throw is now 29 percent hotter than
the Stage 3 sign-off (1.00 m against 0.78 m) because the correction is applied to
every throw, not only to the bad poses. That buys a weapon that works in the fight
the AI actually plays. If it proves too hot on screen the lever is
`REFERENCE_CHASSIS_FRACTION`, not the 115 N s, which is still the signed off impulse.

## 11. Known weaknesses

1. **Bots spend less time locked together than in Stage 3.** "Ticks within 1 m" with
   `--pai=normal` is 142 against Stage 3's 1454, on bots that are heavier at the nose
   and now get thrown clear rather than shoved. Every gate still passes (fires 6 and
   3, 39 damage events, both bots launched over 0.9 m), and R2 owns the AI's standoff
   distance, which is the thing that actually sets this number.
2. **Armour thickness is mass and protection, not silhouette.** Plates grow INWARD
   from the hull surface: their outer face stays 22 mm proud whatever the thickness.
   A thick plate that grew outward would lift a wedge's ramp above an opponent's
   underside and the weapon could no longer get under anything.
3. **Utility parts cannot be knocked off** (section 5), and the scoop is a mesh swap
   on the front plate rather than a shaped collision.
4. **The Shell inverted rests on its dome**, where its 0.11 m wheels do not reach the
   floor. Rather than give it absurd wheels, an invertible chassis may fire the
   righting impulse with `secondary` even with no srimech fitted, which is how a real
   shell bot rights itself. The Pyramid does not need this: its wheels protrude both
   ways by construction.
5. **`face_for_contact` is a box test** in the hull's own frame (top above 79 percent
   of the height, front ahead of 0.4 of the half length, rear behind 0.73). It is
   Stage 3's rule generalised, and it is approximate on the Pyramid and the Shell.
6. **The fallback hulls are lofts**, so the no-art path draws the Shell as a box.
   Only reachable by deleting `Arena/assets/parts`, and the collision is a real
   cylinder either way.
7. **`wheel_contacts()` is a height test**, not a real contact query. It is for the
   test overlay's readout, not for gameplay.
8. **Nothing here has been seen on screen.** Every result in this file is headless:
   231 model bindings, 161 socket read-backs and 232 assemblies are argued from
   measurement. The desktop window pass over the six hulls and ten weapons is still
   owed, and it is where a livery that reads wrong or a plate that floats will show.
