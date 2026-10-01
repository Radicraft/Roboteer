# Power train builder (wave D design spec)

Status: design and mockups only, owner decision 3 of `docs/aaa/decisions-2026-09-30.md`. Nothing
here is built. Mockups and the pick: `docs/look/power-train.html`. Every number on the mockups
comes from `docs/look/power-train/build_mockups.py`, which implements sections 2 to 4 below.

## 1. What changes, in one paragraph

Today the drive is one bundled part (2WD, 4WD, tracks and the rest), each with a fixed speed,
turn and push, and top speed ignores how heavy the machine is. After this wave the **layout**
stays the part you pick first (the eight rows keep their names and roles), and under it the player
chooses a **motor** (described in feel words), **gears** (sprint, balanced, grunt), a **battery**
that the drive, the weapon and boost all draw from, and on wheeled layouts a **wheel size** and a
**tyre**. The builder shows whole-machine numbers worked out from the real mass: top speed, 0 to
top, push against its own weight, quarter turn time and run time, plus a fight clock that shows
when a greedy light pack sags. The two rules from the research hold everything together: every
choice must visibly change the fight, and the player reads feel words and whole-machine results,
never part numbers.

## 2. The model

### 2.1 Layout (the existing eight drive rows)

`2wd, 4wd, 6wd, tracks, omni, legs, hover, adaptive_tracks` keep `top_speed`, `turn_rate`,
`push_force`, `traction` and every wave P key as their **base** numbers. Their `weight` drops by
4 kg (the Mower pair they used to include, see 6). Which sub-choices a layout offers:

| Layout | Motor | Gears | Battery | Wheel size | Tyre |
|---|---|---|---|---|---|
| 2WD, 4WD, 6WD | yes | yes | yes | yes | yes |
| Omni | yes | yes | yes | no (rollers) | no |
| Tracks, adaptive tracks | yes | yes | yes | no (road wheels) | no (the belt is the tyre) |
| Hydraulic legs | yes (drives the pump) | yes | yes | no | no |
| Hover thrusters | yes (drives the fans) | yes (fan pitch, same three words) | yes, plus a hover draw | no | no |

### 2.2 Motor (one a side; mass is the pair)

| id | Name | Feel words (what the player reads) | Speed | Torque | Draw | kg | Level |
|---|---|---|---|---|---|---|---|
| hobby | Hobby motor | Nippy, lazy off the line, weak shove | 1.15 | 0.70 | 0.70 | 2 | 1 |
| mower | Mower motor | Strong and steady. Start here | 1.00 | 1.00 | 1.00 | 4 | 1 |
| wiper | Wiper motor | Slow and brutal, barely sips | 0.72 | 1.35 | 0.65 | 3 | 6 |
| starter | Starter motor | Fast and strong, drinks the pack | 1.20 | 1.25 | 1.80 | 5 | 18 |
| forklift | Forklift motor | Enormous shove, heavy, thirsty | 0.85 | 1.70 | 1.40 | 8 | 38 |
| hub | Hub motor | Fast and frugal, hates wheel hits | 1.18 | 1.15 | 0.90 | 3 | 58 |

The Mower is the reference: a migrated machine on a Mower drives exactly as its layout does today
at the reference mass. The Hub motor's catch is real in the fight: wheel damage bleeds into
`condition["drive"]` at 1.5 times the normal rate. Names are generic sources, never brands.

### 2.3 Gears

| Setting | Speed | Torque | Level |
|---|---|---|---|
| Sprint | x1.2 | x0.8 | 5 |
| Balanced | x1 | x1 | 1 |
| Grunt | x0.8 | x1.25 | 5 |

### 2.4 Battery

| id | Name | Capacity (units) | kg | Weapon spin-up | Extra flipper charges | Level |
|---|---|---|---|---|---|---|
| pocket | Pocket pack | 220 | 2 | x1.15 (slower) | 0 | 1 |
| standard | Standard pack | 360 | 5 | x1 | 0 | 1 |
| big | Big pack | 480 | 8 | x0.7 | 4 | 3 |
| twin | Twin pack | 620 | 12 | x0.65 | 6 | 48 |

The Big pack replaces the Spare battery utility and carries its exact effects (spin-up 0.7, four
extra charges), so a machine that had one fights the same.

**Draw per second**, deterministic, from the recorded input only (replay safe):

- drive: `motor.draw x effort x tyre.draw`, where effort is the stick throttle (0 to 1) raised to
  1 while the wheels are pushing against another machine or a wall; legs x1.2 (the pump);
  hover adds a constant `0.5 x motor.draw` while it is upright (the fans hold it up);
- weapon: spinners and drums `0.5` while spun up plus `2` per spin-up from rest; saws, drills,
  prods and arcs `0.3` while firing; axe, lifter and crusher `2` per stroke; flipper `0.3` per
  shot (the valve); flame and napalm `0` (gas);
- boost: `4` per dash; boost is refused below 10 % charge.

**Sag**. Charge `c` from 1 to 0. At or above a quarter nothing changes. Below a quarter the
machine sags: `sag = 0.45 + 0.55 x c / 0.25`. At zero it is **flat**: the drive limps at 0.35,
battery weapons stop (spinners coast down, strokes refuse), gas weapons still fire. Sag multiplies
top speed, push, turn, boost and weapon spin speed and impulse. It is visible and audible: the
HUD's battery bar turns red, the machine's lights dim, the motor whine drops in pitch, and the
commentary gets lines for it.

**Tuning rule**, enforced by the gauntlet (section 7): a sensible build (the layout's reference
motor on a Standard pack, any weapon) finishes a 3 minute fight with at least a quarter left and
never sags; a greedy light pack on a thirsty machine sags inside the endgame (from 2:00, when the
house bot comes out). The reference Tinribs (Mower, Standard, flipper) ends at 51 %; Starter on a
Pocket pack slows from 1:53 and is flat at 2:31; a horizontal spinner on a Pocket pack slows from
1:55.

### 2.5 Wheels and tyres (wheeled layouts)

| Wheel size | Radius | Speed | Torque | Ride height | kg | Level |
|---|---|---|---|---|---|---|
| Small | x0.85 | x0.85 | x1.18 | lower (harder to get under, can beach) | -0.5 | 12 |
| Standard | x1 | x1 | x1 | as drawn | 0 | 1 |
| Big | x1.2 | x1.2 | x0.83 | higher (easier to get under, rides over lips) | +1 | 12 |

Radius is relative to the hull's own wheel (`wheel_radius_min`), and the hull's clearances move by
the radius change. Small wheels are refused where the front clearance would drop under 12 mm (the
wedge, long and low, apex): the builder says "Small wheels would drag this hull's nose".

| Tyre | Grip | Turn | Draw | Level |
|---|---|---|---|---|
| Grippy | x1.25 | x0.9 | x1.05 | 9 |
| All-round | x1 | x1 | x1 | 1 |
| Slick | x0.8 | x1.15 | x1 | 14 |

## 3. How it maps onto the physics that exists

A new composer (`Arena/bot/drive/power_train.gd`, mirrored by a Swift `PowerTrain` for the
readouts, both reading the same `Shared/parts.json` rows) turns layout plus choices into the
**same keys the drive modules already read**, so `drive_base.gd`, the tracks, omni, legs and hover
modules keep their code:

| Existing number | Where it is used today | Composed as |
|---|---|---|
| `top_speed` | hinge `PARAM_MOTOR_TARGET_VELOCITY = v / radius` | `layout.top_speed x motor.speed x gear.speed x wheel.speed x mass derate` |
| `push_force` | hinge `PARAM_MOTOR_MAX_IMPULSE = 120 x push / 1.5 x hull torque scale` | `layout.push x motor.torque x gear.torque x wheel.torque` |
| `traction` | wheel `PhysicsMaterial.friction = 1.2 x traction` | `layout.traction x tyre.grip` |
| `turn_rate` | steering, times `hull.turn_rate_factor` | `layout.turn_rate x tyre.turn` |
| `radius` | wheel collision and visual scale | `hull.wheel_radius_min x wheel.radius` |
| `thrust_g` (legs, hover) | hull thrust | `layout.thrust_g x motor.torque x gear.torque` |
| weapon `spin_up_s` | `Bot.spin_up_factor()` | `x pack.spin_up`, divided by sag while sagging |
| boost | `BOOST_ACCEL x boost_factor` | x sag; 4 units a dash |

**Mass derate** (new, the fix for "top speed ignores weight"): with load
`L = (mass / 90) / (push / 1.5)`, `v = v0 x (1 - 0.12 L) / 0.88`, capped at `v0`. The reference
4WD at 90 kg is unchanged; a heavy machine on a weak motor slows, a light one on a strong motor
reaches its free speed. The hinge's max impulse is fixed, so acceleration already falls with mass
in the simulation; the derate is the top speed half of the same truth.

**Sag at run time**: `Bot` owns a `Battery` (charge, draw per tick). `DriveBase.power_scale()`
multiplies in `sag`, and each wheel joint's max impulse is re-applied from it while `c < 0.25`
(nothing to do above that). All float maths on the tick, no rng: replays and fight hashes stay
deterministic.

## 4. Whole-machine readouts (what the builder shows)

All from the real total mass, the same maths on the Swift side as the composer:

| Readout | Player wording | Formula |
|---|---|---|
| Top speed | `4.2 m/s` | derated `v` above |
| 0 to top | `0.92 s` | `0.9 x (mass / 90) x (v0 / 3.5) / (push / 1.5)` |
| Push vs weight | `1.18x`, or "wheels slip" | `min((push / 1.5) x (90 / mass), 1.2 x traction x grip)`; "wheels slip" when the motor out-pushes the tyres |
| Quarter turn | `0.70 s` | today's 0.7 s at `3.2 x 0.85`, scaled by the composed turn rate |
| Run time | `4:07` | `capacity / typical draw`; typical = drive at 0.6 effort + the weapon's average + a boost every 12 s |
| At the bell | `27 % left` | `1 - 180 x draw / capacity` |
| Fight clock | charge line over 0:00 to 3:00, endgame marked, sag hatched red, flat hatched grey | the draw model above |

The two constants (0.12, 0.9 s) are fitted to the drives gauntlet's measured straight-line runs
before the numbers ship, and a test holds every readout within 10 % of the measured value.

## 5. Quick build by target stats

Three sliders: **Speed** (m/s), **Push** (x weight), **Battery at the bell** (%), and the
parts the player already fitted elsewhere stay fixed. The solver enumerates every legal, unlocked,
affordable combination (at most 6 x 3 x 4 x 3 x 3 = 648, instant) and picks the nearest in
normalised stat space, with a small penalty for "wheels slip" and for kilograms used. The screen
shows the target dot and the ring the build actually reaches on each slider, the five parts it
changes, and one line naming the locked part that would close the gap ("1.4x push needs the
Forklift motor at Level 38"). "Fit these five" applies them; nothing changes until then.

## 6. Migration

- **Saved machines**: `BuildSpec` gains an optional `powerTrain` object
  (`motor, gears, battery, wheels, tyres`). Its decoder already uses `decodeIfPresent`, so an old
  save decodes to Mower, Balanced, Standard pack, Standard wheels, All-round.
- **Weight**: each layout row sheds the 4 kg Mower pair, the pack is new mass (Standard 5 kg), and
  the budget rises from 100 to **105 kg**. A migrated machine keeps its spare to the half kilo
  (Tinribs 89.5 of 100 becomes 94.5 of 105).
- **Spare battery**: a save with the Spare battery utility gets the Big pack instead and the
  utility slot comes free (net 1 kg lighter). The utility leaves the shop and the catalogue;
  anyone who owned it owns the Big pack. `Store/Gates.swift` and the career `starting_unlocks`
  swap `spare_battery` for `big` (battery). Its glyph and model become the battery's.
- **Rivals and fixtures**: every rival in `parts.json` gets a written power train that fits its
  personality (a speedster on Hobby and Sprint, a pusher on Wiper and Grunt with Grippy tyres).
  House bots keep their own fixed numbers. Fixtures (`career-regional`, `career-masters`,
  `FightConfigFixture`) are re-saved once.
- **Events and weight classes**: any kg cap moves up by 5 with the budget.

## 7. Balance and test plan

1. **Composer unit test** (Godot and Swift): the reference choices at 90 kg return each layout's
   catalogue numbers exactly; Swift readouts equal the Godot composer's numbers for every layout x
   motor x gears x pack (bridge test).
2. **Drives gauntlet** (`Arena/qa/drives_gauntlet.gd`) grows `--motor --gears --pack --wheels
   --tyres` and a **push bench** (shove a 90 kg block, measure) and a **battery bench** (a scripted
   3 minute duty cycle, charge at the bell). It fits the two readout constants; the new
   `power_train_test.gd` then holds readouts within 10 % of measured, and battery within 5 %.
3. **Weapons and pacing gauntlets** with the rivals' new builds: no motor wins more than 40 % of
   AI-vs-AI fights across the field; sensible builds never sag; at least half the greedy builds
   (thirsty motor or spinner on a Pocket pack) sag inside the endgame; stuck time and time to the
   first blow no worse than today's `docs/qa/pacing.md`.
4. **Goldens that move**: every fight hash with a wheeled or bodiless machine changes once (mass
   derate and the new masses), including the six hazard goldens and the replay goldens. They are
   re-baselined in **one** commit that lists each file and why, after the gauntlet passes; nothing
   else may move them. New goldens: a sag fight (Starter on a Pocket pack, flat at 2:31) and a
   flat machine limping to the bell.
5. **Migration test**: decode every fixture and a spread of saved garages, check mass, spare and
   the Spare battery conversion.
6. **Eye check on the phone**: the sag has to be seen and heard without reading the HUD.

## 8. Progression and IAP

Every power train part is bought with scrap at `economy.price_factor.drive x kg`, the Hub motor at
x3 and the Twin pack at x1.5. No new IAP and no coin-for-non-consumable path (the 3.1.1 lesson
stands). Unlock levels are in the tables: the core system (three motors, all gears, three packs,
wheels and tyres) sits at or under Level 33, the free game's cap, so the free game gets the whole
idea. Forklift (38), Twin pack (48) and Hub (58) are full-game rewards, and they are sidegrades
with a catch, never straight upgrades. Gears unlock at Level 5 with a one-line coach mark.

## 9. Open questions for the owner

1. A flat battery: limp at 35 % to the bell (my pick, a fight is never decided by a meter alone),
   or stop dead and get counted out?
2. Late motors above Level 33 (Forklift, Hub, Twin pack) in the full game only, as priced above?
