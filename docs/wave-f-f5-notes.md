# Wave F agent F5 notes: the three bot-assembly bugs from the phone playtest

2026-09-16. The owner drove a machine on his iPhone for the first time and reported
three faults in the machines themselves. All three reproduce headless, all three are
fixed, and each one now has a permanent gate.

Owned files: `Arena/bot/**` (except `part_visuals.gd`), `Arena/workshop/*`,
`Arena/tests/{builds,physics,assembly_bugs,weapons}_test.gd`, this file.

```bash
sh scripts/test-arena.sh assembly_bugs_test.gd weapons_test.gd    # the two new gates
sh scripts/test-arena.sh                                          # the lot
```

---

## 1. "Robot always loses armour when driving off at the start of the match"

### Root cause

`Bot._apply_initial_damage()` called `_detach_part()` on every part whose CARRIED
condition was already zero.

Damage persists between fights. `ResultSheet.swift` writes the arena's reported
condition back into `BotBuild.damageJSON`, and only the workshop's **Repair** button
clears it, so a machine that lost its top plate in one fight sends
`"armour": {"top": 0.0}` in the `fight_config` of every fight after that. The arena
then:

1. built the plate as a real rigid body, inside the hull, in `_build_armour`;
2. detached it one line later with `tint = false`, so it was not even greyed as
   debris and still wore the machine's own armour material;
3. reparented it under `Debris` and let gravity have it.

Measured, wedge / 4wd / flipper carrying `armour.top = 0` and `wheels[0] = 0`,
spawned and driven three seconds off the mark:

```
LOOSE WheelFL0   at (2.45, 0.11, -4.14)   1.46 m from the machine, visible true
LOOSE PanelTop   at (-3.38, 0.00, -3.20)  7.13 m from the machine, visible true
```

The plate is lying on the spawn mark and the machine has driven away from it. That
is the report, word for word, and it is deterministic: every fight, for as long as
the damage is carried.

### The fix

`Bot._retire_part()` (bot.gd). A part at zero condition is **not fitted to this
fight at all**: its joint is freed, it is frozen static, its `collision_layer` and
`collision_mask` go to zero, it is hidden, and it is never reparented to `Debris`
and never tinted. `BotPart.retired` records the state so a test can tell a part that
was never fitted from one this fight knocked off.

The body object stays in `_parts` rather than being freed, because `DriveBase`
indexes `wheels[i]` by slot position and reads `wheels[i].detached` without an
`is_instance_valid` guard. It weighs nothing (`total_mass()` skips detached parts),
so the machine really is lighter for what it has lost: 40.04 kg against 44.45 kg
whole.

A retired top plate takes the srimech with it, which is Stage 3's rule ("it rides on
the top plate so it leaves with the plate") working as written.

### The gate, and what it rules out

`assembly_bugs_test.gd`:

* section 1 drives **48 builds** (six chassis x four armour materials x thickness 1
  and 4) plus **all five drives**, three seconds from the player spawn, and asserts
  nothing detaches and no damage event is recorded at all. Nothing sheds. So there is
  no second cause hiding behind this one: a pristine machine does not lose parts;
* section 2 is the bug itself: a machine carrying a dead plate and a dead wheel has
  to have nothing loose in the world, nothing under `Debris`, exactly two parts
  missing, the carried damage still readable, and a lower simulated mass.

---

## 2. "The weapons are not all responding or working once built in the workshop"

`weapons_a_test` and `weapons_b_test` each prove their own five weapons on a hull
chosen to suit them. Nobody was testing the other thirty combinations the builder
offers. Three separate faults, all geometry, all measured.

### 2a. A mid-band weapon on the Tall Tank could not reach anything in the game

`Bot._mount_for()` had a rule: "a mid height weapon on a hull built for overhead
mounting uses the deck, that is the Tall Tank's whole character." The Tall Tank's
`socket_weapon_top` is at **0.405 m** in bot space. Measured spans above the arena
floor, and the tallest machine in the catalogue is the Tall Tank's own 0.48 m roof:

| weapon on tall_tank | body spanned | could it touch anything |
|---|---|---|
| horizontal_spinner | 0.672 to 0.732 m | no |
| saw | 0.565 to 0.875 m | no |
| flamethrower (nozzle + cone) | 0.657 to 0.747 m | no |

All three read READY, span up to 100 %, sweep all fight and removed **0.0000**
condition in a five second engagement. The rule is deleted: only a `high` band
weapon (the axe, which works downward) or the crusher takes a deck. Everything mid
or floor band goes on the nose, on every hull.

After: horizontal spinner 1.00, saw 0.348, flamethrower 0.456 condition removed on
the same engagement.

### 2b. The crusher clamped a Box and nothing else

Three things, all in `crusher.gd`:

1. **Working height came from the wielder, not from the opponent.** The pivot was
   `socket.y + PIVOT_LIFT`, so the gap hung at whatever height that hull's deck
   happened to be: 0.32 m on a Pyramid and 0.50 m on a Tall Tank, against machines
   that are 0.16 m (Long/Low) to 0.48 m (Tall Tank) tall. Now `BITE_HEIGHT` = 0.20 m
   above the ARENA FLOOR, and the pivot is derived from it and from the jaw's own
   geometry (`bite_offset()`), so the same claw bites the same way on every hull.
2. **The gap was behind its own nose.** `JAW_SETBACK` 0.12 left the bite gap
   0.057 m proud of the hull, and the wielder's own front armour stands 0.022 m
   proud on top of that, so the hull met the opponent before the claw got round it.
   0.06 puts the gap 0.117 m proud on every hull in the catalogue.
3. **A shut jaw fought its own limit for ever.** The closing motor was commanded at
   `CLOSE_SPEED` for as long as the button was down, including against the closed
   limit with nothing in the jaw, and that reaction torque is a permanent nose-down
   moment. A Pyramid holding the button crept **backwards 0.3 m in five seconds** of
   full throttle; the same build with the button up covered 5.83 m in two. The motor
   now lets go once `open_angle()` is inside `JAW_SHUT_EPS`. With something in the
   jaw the victim stops it short of the limit, so the squeeze and the pin are
   unchanged and `weapons_b_test` is still 38 of 38.

Held contact time on a target, before and after, five hulls:

| hull | before | after |
|---|---|---|
| box | 1.75 s | 3.52 s |
| wedge | 0.17 s | 3.53 s |
| pyramid | 0.00 s | 3.52 s |
| long_low | 0.00 s | 3.60 s |
| tall_tank | 0.70 s | 3.53 s |

(The pin needs 0.30 s.)

### 2c. The flipper and the lifter could not get under anything on a flat-nosed hull

Both took their rest angle straight from `chassis_module.weapon_rest_angle()`, which
is the hull's front RAMP angle and is **zero on a hull with no ramp**. The arm then
lay level at whatever height the .glb put the front socket:

| hull | arm underside | opponent's underside |
|---|---|---|
| wedge (ramped) | 0.025 m | 0.02 to 0.06 m |
| long_low (ramped) | low | ditto |
| box | 0.105 m | ditto |
| tall_tank | 0.150 m | ditto |
| pyramid | 0.185 m | ditto |

Five seconds of driving into a machine with the button held threw it **0.00 m** on
the Box, the Pyramid and the Tall Tank, against 1.22 m on a wedge.

`WeaponBase.ground_rest_angle(arm_length)` now owns the rule: on a ramped hull it
returns the ramp angle and **nothing changes** (the wedge's signed off flipper tuning
is untouched, and `physics_test`'s throw numbers are unmoved); on a flat nosed hull
it returns the angle that puts the arm's tip at Stage 3's measured `ARM_TIP_CLEAR`
0.025 m off the floor, which is under an opponent's underside and above the pogo
trap. `flipper.gd` and `lifter.gd` each call it with their own arm length.

After: the flipper throws 1.01 m on a Box, 0.94 m on a Pyramid, 0.81 m on a Long/Low
and 0.24 m on a Tall Tank; the lifter lifts on all five hulls.

### Not bugs, recorded so they are not re-reported

* **The ram's button does nothing.** Brief section 5.3, and the coach callout says so
  ("RAM tap (passive weapon; the button does nothing)"). `weapons_test` asserts it
  reads READY and shoves, rather than asserting the button does something.
* **The axe fires on the EDGE**, so a held thumb gives exactly one swing and then
  nothing until the button is released. That is the design (the coach says "SWING
  tap"). Worth a look on the phone all the same: a touch button and a held thumb is
  a very easy way to conclude the axe is broken. Changing it would be a design call,
  not a fix, so it is left alone.

### The gate

`Arena/tests/weapons_test.gd`, 17 checks:

1. every legal (weapon, chassis) pair assembles with a registered weapon body at the
   catalogue reach;
2. **the matrix**: all 41 legal pairs engage a machine parked in front of them and
   have to do their job. A lifter or a flipper has to LIFT it (they take no
   condition at all), the ram has to SHOVE it, everything else has to take condition
   off it;
3. every spun weapon reaches ready over `spin_up_s` and coasts down;
4. the lifter raises and lowers; the crusher clamps and chews **on every hull**; the
   axe swings, goes dead, and cocks again; the flamethrower burns gas and burns the
   target; the ram is passive;
5. the secondary: a srimech rights an inverted machine, an invertible hull rights
   itself with no srimech, a spare battery adds the catalogue's extra gas charges and
   a landed throw spends one;
6. a config round trip through JSON builds the identical machine (every part key,
   kind, material and mass, the weapon's socket and reach, the build total) and the
   weapon still runs; the workshop stage rebuilds the whole machine on every edit;
7. the same weapons work in the workshop **test arena** (`rules.mode = "test"`),
   which is the room the owner judges a build in.

---

## 3. "Building screen customisations are not all showing"

### Every builder field, traced end to end

The builder has six tabs and `BotBuild.toBotConfig` puts **all of them** on the wire
(`chassis`, `drive`, `weapon`, `utility`, `armour` as `{material, thickness}` per
face, `livery`, plus `damage`). `BuilderView.sendToStage` debounces 150 ms and sends
that as `workshop_config`; `WorkshopStage.show_bot` hands it straight to `Bot.setup`,
which is the same call the fight makes.

| builder field | reaches the machine as | shows |
|---|---|---|
| chassis | `chassis/<id>.gd` + `<id>.glb` hull, its collision and all 22 sockets | yes |
| drive | one wheel body per catalogue `wheels`, each with its own model (`wheel_standard` / `wheel_omni`), tracks additionally hang a `track_unit` belt skin per side | yes |
| weapon | the weapon module's own bodies and model, mounted per `_mount_for` | yes (see section 2 for where it was mounted WRONG) |
| utility slot 1 | srimech on the top plate, rear wedge and skirts as a visual plus hull collision, scoop as a model swap on the front plate, everything else a model on a utility socket | yes |
| utility slot 2 | as above | **was broken, fixed** |
| armour material, per face | the face material bound onto the plate model's `steel` surface (an `hdpe` face uses `plate_flat_hdpe` instead, a front face `plate_sloped`, a scoop `scoop.glb`) | yes |
| armour thickness, per face | the plate model's X scale and the plate's collision box X, both `PLATE_BASE_THICKNESS + 0.010 * (units - 1)` | yes |
| livery | the `livery` and `hdpe` slots on every part, plus the plate's painted face | yes |

### The one Godot-side omission, and the fix

`Bot._build_utility()` sent every "generic" utility part (spare battery,
counterweight) to `utility_socket(0)` and the downforce magnets and the skirts to
`utility_socket(1)`. Fit two parts from the same group and they came out at the
**identical point**: measured, a wedge with a spare battery and a counterweight put
both models at `(-0.27, 0.20, 0)`, one wholly inside the other, so a player who
fitted two utility parts saw one. Skirts plus magnets collided the same way on
socket 1.

`Bot._claim_utility_socket(preferred)` now hands out each mount once, preferring the
rear deck for everything except the magnets (low and forward, which is where
downforce belongs) and falling through to the other socket when the preferred one is
taken. Measured after: battery at `(-0.27, 0.20, 0)`, counterweight at
`(0.247, 0.05, 0)`, 0.648 m apart on a Tall Tank build.

### Swift fields owed

**None.** Every field the builder edits is already in `toBotConfig` and already
arrives. Nothing needs changing on the Swift side for bug 3.

### Measured, and handed over rather than changed

1. **A plate is mostly painted, not mostly material.** Surface area per slot,
   measured off the .glb: `plate_flat` is 73 % `steel` (the face material), 17 %
   `livery`, 10 % `dark_metal`; `plate_sloped` 72 / 17 / 11; `plate_flat_hdpe` 77 %
   `hdpe`, 22 % livery. So a material change genuinely does show, on about three
   quarters of each plate. If the owner still says the material is hard to read, that
   is a call for G3's plate models or V4's material binding, not for the assembler.
2. **`socket_utility_1` is front and low on every hull**, so a counterweight fitted
   alongside a battery now sits at the nose rather than on the deck. Physically it is
   fine (the counterweight's effect is `com_shift`, applied in `_resolve_utility`,
   not taken from where the model sits), but whether a counterweight reads right
   hanging off the nose is a socket-placement question for G3.
3. **Utility parts still cannot be knocked off** (assembly notes section 5). Unchanged.

---

## 4. Verification traps, all paid for in this wave

1. **Driving from the player spawn toward the centre crosses the yard's spike
   patch** (1.6 m square on the origin, phase from the seed). Every "the armour took
   damage" reading on that line is the hazard: it arrives as exactly **J = 26.0 every
   15 ticks**, which is `Yard.HAZARD_IMPULSE` / `HAZARD_PERIOD_TICKS`. Both new tests
   run their lanes clear of it (z = 3 for the weapons, along the south wall for the
   assembly).
2. **The fastest build covers 8.1 m in three seconds** from the spawn, which reaches
   the east wall at 5 m. A Shell's ring takes a 49 N s contact off it. That is a real
   hit on a machine that ran out of room, not a part falling off, so
   `assembly_bugs_test` stops a run at `WALL_STANDOFF`.
3. **Holding the primary from the first tick measures nothing for a lifter**: the
   forks are already up when it arrives, so it drives at the target with a shelf on
   the front. A flipper is nearly as bad (it cycles all the way in). Both are worked
   by closing with the arm DOWN and then working the button, which is what a player
   does, and `weapons_test.UNDER_WORKED` encodes it.
4. **A parse error in `part_visuals.gd` is silent and total.** Every
   `PartVisuals.instantiate` call fails, every hull falls back to a procedural loft,
   no .glb socket is read and every socket-derived number changes. It shows only as
   `Nonexistent function 'instantiate' in base 'GDScript'` in the middle of a wall of
   backtraces. Grep the run for `Parse Error` before believing any assembly
   measurement.
5. **Rolling the CHASSIS body to test the srimech tears every joint on the machine.**
   Set the bot ROOT transform before `setup` so the whole assembly is built inverted,
   which is what `physics_test._check_srimech` does and what `weapons_test`
   `_spawn_inverted` now does.
6. **A GDScript lambda captures locals by value.**
   `bot.weapon_fired.connect(func(): fired += 1)` never increments `fired`. Use a
   one-element Array.
7. **The top plate carries the srimech as a second model child**, so a probe that
   reads "the plate's model scale" by walking children finds the srimech's 1.0 and
   reports that a thickness change does nothing. Take the first non-collision child.
8. **`readiness()` is not comparable across weapons.** A crusher reads
   `0.4 + 0.6 * open_fraction`, so holding the button DROPS it to 0.4 and a peak of
   1.0 means it clamped something. Reading readiness alone would have said the
   crusher was fine on every hull.

---

## 5. What was changed

| file | change |
|---|---|
| `Arena/bot/bot.gd` | `_retire_part()` and `_apply_initial_damage` (bug 1); `_mount_for` deck rule deleted (bug 2a); `_claim_utility_socket()` and `_build_utility` / `_fit_skirts` (bug 3) |
| `Arena/bot/part_body.gd` | `retired` flag |
| `Arena/bot/weapons/crusher.gd` | `BITE_HEIGHT`, `BITE_LOCAL`, `bite_offset()`, `JAW_SETBACK` 0.12 to 0.06, `JAW_SHUT_EPS` and the closing motor |
| `Arena/bot/weapons/weapon_base.gd` | `ARM_TIP_CLEAR`, `ARM_MAX_PITCH`, `ground_rest_angle()` |
| `Arena/bot/weapons/flipper.gd` | rest angle from `ground_rest_angle(FLIPPER_LEN)` |
| `Arena/bot/weapons/lifter.gd` | rest angle from `ground_rest_angle(FORK_LEN)` |
| `Arena/tests/assembly_bugs_test.gd` | new, 15 checks |
| `Arena/tests/weapons_test.gd` | new, 17 checks |

No Swift file was touched. No constant in `flipper.gd`'s signed off tuning table was
touched: the wedge and the Long/Low take exactly the path they always took.

### What else moved, and what did not

* `physics_test`'s flipper numbers are **unchanged to the centimetre** (throw peak
  1.01 m, rise 0.90 m, wielder peak 0.13 m, a dry fire keeps its charge, a landed
  throw spends one). That is the proof that `ground_rest_angle` leaves the wedge
  alone.
* `builds_test` went from **1 failure to 0**. Its last red, "the ram build removes no
  more condition than the others", was reading 1.33 against 1.01 and 3.02; the ram
  build now removes 0.00, which is section 2.3 of the weapons B notes working as
  designed. The spinner build's fixture and R2's AI also moved this wave, so the
  credit is shared.
* `weapons_b_test` is still **38 checks, 0 failures** after the crusher changes, and
  `weapons_a_test` still 12 of 12.
* `determinism_test` is green, so none of this introduced an order dependency.
* `scripts/test-arena.sh` on 2026-09-16 with all of it landed: **29 test files, 0
  failures**, including `assembly_bugs_test` 15 of 15 and `weapons_test` 17 of 17.
