# Wave P, agent D2: mobility, hull, armour, utility

The seven parts of brief v5 section 9.5 that are not weapons. Written 2026-09-21, against
`docs/brief-v5-progression.md` and `docs/wave-p-contracts.md`.

All seven are in `Shared/parts.json` (copied byte identical to `Arena/data/parts.json`), on the
Level ladder the coordinator wrote, and covered by `Arena/tests/mobility_p_test.gd` (43 checks,
green). They leave the shop's "Still to come" list and become priced rows the moment the catalogue
rows exist, which they now do, with no other code change.

| id | Kind | Level | Weight | Price | What it is |
|---|---|---|---|---|---|
| `reinforced` | armour material | 10 | 3.4 kg per unit area | 49 | Reinforced steel: the best plate in the game against hazards and cuts, the heaviest, and only fair against a spinner |
| `legs` | drive | 30 | 30 | 240 | Hydraulic legs: slowest, immense push, steps over floor hazards |
| `reactive` | armour material | 45 | 2.6 kg per unit area | 37 | Reactive armour: the best plate against impacts, and it shoves the attacker back. Poor against saws |
| `hover` | drive | 55 | 24 | 192 | Hover thrusters: fastest in the arena, no push, floats over floor hazards, flips easily |
| `adaptive_tracks` | drive | 85 | 32 | 256 | Track grip with a 4WD's steering, and belts that cannot be torn off |
| `overcharge_core` | utility | 90 | 9 | 54 | Faster spin up, 25 per cent harder blows, and it cooks the machine's own core |
| `apex` | chassis | 100 | 48 | 480 | Every weapon fits, hardest hull to flip or tip, and half the weight budget |

## 1. What was built

**Three drives.** `Arena/bot/drive/legs.gd`, `hover.gd`, `adaptive_tracks.gd`, plus one shared
base, `Arena/bot/drive/bodiless_drive.gd` (`class_name BodilessDrive`), for the two that have no
wheels. No registry line was needed: `Bot._build_drive` already loads `res://bot/drive/<id>.gd` by
catalogue id.

- `adaptive_tracks` extends the Stage 4 `tracks.gd` and changes two things: `side_alive()` is
  always true and `sheds_visual()` is false (the belt is segmented, so it never comes off and the
  skin stays on the machine), and `power_scale()` lerps from the catalogue `belt_floor` (0.4) to
  1.0 on the average belt condition instead of killing a side. A chewed side slows the machine; it
  never takes the steering away. Turning "like wheels" is not code: it is a catalogue `turn_rate`
  of 3.2 against the plain track's 1.8.
- `legs` and `hover` build no wheel bodies at all. That was the design decision with the widest
  blast radius, so section 3 explains it.

**One chassis.** `Arena/bot/chassis/apex.gd`: a four level lofted profile whose bottom ring pulls
IN under the waist, so the lowest edge is an undercut rather than a ramp (`hard_to_get_under`).
Flat deck on top for an overhead weapon, the lowest centre of mass in the catalogue (0.065 m),
`flip_resistance` 1.9 and `tip_resistance` 1.5. It carries no `weapons_allowed` row, which is what
"every weapon fits" means and what lets D1's `vortex_spinner` onto it for nothing.

**Two armour materials**, catalogue rows only, plus one correction in `damage.gd`: the impulse
path read `FightTypes.MATERIAL_FACTOR`, a constant table with the four Stage 4 materials in it, so
both new plates would silently have been factor 1.0 against everything and worse than steel. It
now reads `PartsCatalogue.material_factor`, which reads the catalogue and falls back to that same
table, so the four old materials are unchanged to the decimal (`damage.gd` is the one file D1 and
I both edited; this is the "material factor reading" line of the contract).

**One utility**, `overcharge_core`, `effect: "overcharge"`, resolved in `Bot._resolve_utility`.

## 2. The numbers, and why

Prices are `economy.price_factor` times weight, so **weight is the only balance lever** and every
number below was picked to make the part clearly better than what it outranks without making it a
must buy.

- **`reinforced` 3.4 kg per unit area.** Heavier than steel (3.0), more than twice titanium (1.6).
  Factors: impact 0.9, hazard 0.45, cut 0.3. Best in the game on two of the three rows and the
  worst weight in the game, and it is still only fair against a spinner, which is what the fights
  actually turn on. At Level 10 it is the first real armour decision: 3 units on the front is
  12.2 kg against steel's 10.8 and titanium's 5.8.
- **`reactive` 2.6 kg, impact 0.4** (best; hdpe is 0.5 at 1.0 kg), hazard 1.0, cut 1.4, and
  `knockback` 90. HDPE stays the light anti spinner answer; reactive is the heavy one that hits
  back. `knockback` is newton seconds per unit of condition the blow took off, so a glancing hit
  is a nudge and a spinner's bite is a throw: measured, a 140 N s blow on a 2 unit reactive front
  moved the attacker away at 0.66 m/s.
- **`legs`: top speed 2.0** (slowest), `turn_rate` 1.6 (slowest), `push_force` 3.2 (highest),
  `traction` 2.2, weight 30. It is outrun by everything and it cannot be shoved off a line.
- **`hover`: top speed 5.2** (the 2WD, previously the fastest, is 4.2), `turn_rate` 4.4,
  `push_force` 0.3, `traction` 0.35, weight 24, `flip_factor` 0.55.
- **`adaptive_tracks`: 2.9 / 3.2 / 2.6 / 1.9**, weight 32, the dearest drive on the ladder. It is
  a plain track that has been fixed: a little faster, a lot better steering, and it cannot be
  disabled by having a belt torn off. It pays 6 kg and 48 scrap over the plain one.
- **`apex` 48 kg.** Half the weight budget before a drive, a weapon, a srimech or a gram of
  armour. An Apex on adaptive tracks with a horizontal spinner is over the budget and the builder
  says so; an Apex with a heavy weapon runs thin armour. That is the whole cost of "every weapon
  fits", and it is why a Pyramid (invertible, no srimech needed) is still worth owning at
  Level 100.
- **`overcharge_core` 9 kg**, the heaviest utility. `spin_up_factor` 0.55 (the spare battery is
  0.7), `hit_factor` 1.25, `cook_rate` 0.004 of core condition per second while the weapon reads
  full. Three minutes of a spinner held at full costs 0.72 of a core that started at 1.0: the
  survivor bonus gone and a component kill within reach of anything else that gets at the hull.
  Let the weapon idle and it stops cooking. On a ram, which always reads full, it is a pure trade
  of core condition for damage.

**Affordability.** The self test's rule is "affordable within two wins of reaching its Level". A
campaign won on base plus half the damage bonus plus survivor banks 10,880 scrap; the dearest of
these seven is the Apex at 480, reached on the last match of the campaign. The whole shop,
including D1's six weapons, clears well inside one campaign.

## 3. The decision behind the two new drives: no wheel bodies

A walker and a hovercraft have nothing that rolls, so neither has a hinge motor to command. Both
are driven as forces on the hull by `BodilessDrive`: a yaw rate the machine holds, thrust along
its nose capped at the catalogue `thrust_g`, a lateral grip term whose authority is the catalogue
`traction`, and a support term (the walker's hydraulics, the hover's cushion). Four consequences,
all deliberate:

1. **They report no wheel rows.** `condition["wheels"]` is empty, which is exactly what Swift's
   `Catalogue.Drive.conditionCount` promises for `wheels: 0, tracks: 0`. This is why the match
   report and the repair bill never print "Front left wheel" for a fan or a foot: there is one
   Drive line, named "Hover thrusters" or "Hydraulic legs", and nothing else to lose. It also
   means no Swift change was needed (`ProgressionEngine.wheelLabels` has no vocabulary for legs or
   thrusters, and it belongs to agent A).
2. **Their mobility damage goes through the hull.** A wheeled drive bleeds its drive condition
   with its wheels (`BotDamage.DRIVE_BLEED`); these two would have been invulnerable, so
   `Bot._bleed_drive_from_hull` sends a fraction of every hull and plate hit into the drive at the
   catalogue's `hull_bleed` (legs 0.18, hover 0.22). Drive at zero is a dead machine, so they can
   still be immobilised, which is how most fights end. The bleed deliberately raises no damage
   event of its own: the blow that caused it has already raised one, and a second would be counted
   twice in the attacker's tally and sparked twice by the fx. It shows up where it should, in the
   condition the match report and the scrap ledger read.
3. **Their catalogue kilograms go on the hull** (`Bot.add_hull_mass`), the same way a utility
   part's do, so the assembly test's mass check still holds to within a percent.
4. **The feet and the skirt are collision and visuals on the hull**, never bodies, so the brief's
   body budget (section 12) is untouched: a legged machine is 6 bodies against a 4WD's 10.

**Two measured traps, both now in the code comments.**

- **Force at the hull's centre of mass is wrong.** Plates and weapon are welded bodies, so the
  assembly's centre of mass sits forward of the hull's. Gravity pulls at the assembly's, lift
  applied at the hull's made a couple, and a hover with a ram sat at a steady 18 degrees nose down
  for ever with nothing to stand on. `BodilessDrive.apply_at_com` works out the assembly's centre
  of mass every tick and applies lift, thrust and braking there. With that fixed, the hover holds
  0.200 m under a cushion asked for 0.200 m, dead level.
- **A soft velocity controller never reaches the catalogue speed.** It settles where the machine's
  own friction balances it: a walker rated 2.0 m/s held 1.12. `THRUST_REACH_S` is 0.06, the feet
  run a friction of 0.25 (the lateral grip and the braking are already modelled as forces, so
  physical friction is a second helping of the same thing and comes out of the thrust), and the
  walker now holds 1.84 m/s.

**The landing.** Four rigid feet bolted to the hull credit the whole landing impulse to an armour
face: 58 N s against an armour break threshold of 24, measured, which is a plate damaged for
nothing every time the machine is set down. `legs.support()` opposes downward velocity over the
last `leg_travel` (0.12 m) of the drop and levels the body as it does it, so the feet touch down at
walking pace. It only ever opposes a fall, so a walker cannot hop and cannot fly.

## 4. Fit rules: none were added, and that is deliberate

`build_rules.gd` and `BuildRules.swift` are unchanged. Nothing in these seven needs a new rule:
the Apex takes every weapon (no `weapons_allowed` row, which the existing rule already reads as
"anything"), both plates fit every face, and all three drives fit every hull (the adaptive track
uses the 6WD slot row, which every chassis including the Apex carries).

The one rule I considered and rejected was "ground clearance skirts do not fit hover thrusters".
It is true in fiction (a skirt hangs a lip below a hull that is not near the floor) but Swift's
`Catalogue.Drive` has no field that would let `BuildRules.swift` see it, and `Catalogue.swift`
belongs to agent A. A rule in one of the two rule sets and not the other is worse than no rule:
the builder would call a build legal and the arena would log it as illegal. Skirts on a hover are
3 kg of nothing, which the blurbs already tell the player, and the same is true of a counterweight
on a machine that does not need one.

## 5. Mesh requests for agent E

Nothing here touches `part_meshes.gd` or `part_visuals.gd`. Four parts render on fallbacks today:

- **`legs`** (`Model_legs`, or four `Model_leg` instances). Four legs, one per
  `ChassisBase.wheel_slots("4wd")` point, in bot space: the mount is on the hull underside at
  `floor_y()` and the foot reaches the floor at `y = -0.14` (the catalogue `stance_height`), so the
  leg is 0.07 to 0.10 m tall depending on the hull, about 0.16 m fore and aft and 0.12 m across.
  The hull rides 0.14 m up rather than the usual 0.11, so it stands visibly taller. **What moves:**
  a stride. The drive can drive it: `DriveBase.wheel_contacts()` reports feet down, and the road
  speed is `chassis.linear_velocity` along the nose, so a phase per leg off distance travelled
  would read right. Today they are four plain struts.
- **`hover`** (`Model_hover`). A skirt ring around the hull's footprint, about 0.05 m deep, sitting
  just under `floor_y()`, plus four thruster pods. **What moves:** a glow and a downward blur that
  tracks the lift, which is strongest at the moment the machine is set down or knocked upward. The
  hull rides 0.20 m up, so there is a visible gap under it: the skirt is what fills it. Today it is
  one plain ring.
- **`apex`** (`Model_apex`). Footprint 1.0 by 0.7, height 0.22, and the profile is in `apex.gd`:
  a bottom ring 0.04 m narrower than the waist (the undercut, which is the hull's whole defensive
  idea and has to read on screen), a full width waist, and a deck 0.42 by 0.30 on top. Sockets:
  `socket_weapon_front`, `socket_weapon_top`, the four armour anchors, two utility mounts, a
  srimech mount, and the 2wd/4wd/6wd wheel rows already written into the catalogue.
- **`overcharge_core`** (`Model_overcharge_core`). A utility part on a deck mount, roughly
  0.2 by 0.1 by 0.12, and it should read hot: it is the part that cooks the machine. There is no
  model at all today, so nothing is drawn for it.
- **The two plates.** `reinforced` and `reactive` currently take a flat colour from
  `FightTypes.MATERIAL_COLOUR` (I added the two rows: a darker grey for reinforced steel, a warm
  matt block for reactive) on the existing `plate_flat` model. Reactive armour wants cassette
  blocks rather than a flat sheet, and a scorch where a charge has fired.

## 6. Requests for agent F (audio)

`MachineAudio.DRIVES` has no row for `legs`, `hover` or `adaptive_tracks`, so all three fall back
to the default wheel roll. It does not crash and nothing fails, but a walker that sounds like a
4WD is wrong: the walker wants a footfall per stride (the same phase the mesh uses), the hover
wants a fan whine that tracks `thrust` rather than wheel speed and a skirt hiss, and the adaptive
track wants the existing track clatter. `DriveBase.wheel_contacts()` is already answered by the
walker and left empty by the hover, which is the hook the landing thud uses.

## 7. The dials the owner can turn

Every one of these is a catalogue key in `Shared/parts.json`, so none of them needs a build.

| Dial | Now | What it does |
|---|---|---|
| `legs.thrust_g` | 1.9 | The push. Measured: a walker shoves a braked 4WD 3.04 m in two seconds where a 6 wheel manages 0.03 m. If that reads as a bulldozer on the phone, 1.5 is a sensible first cut |
| `legs.contact_grip` | 1.0 | The other half of the same dial: how much thrust survives while leaning on another machine |
| `legs.hazard_factor` | 0.3 | How much of a floor hazard a walker takes. 0.0 would be "steps over it completely" |
| `legs.stance_height` / `leg_travel` | 0.14 / 0.12 | How tall it stands and how much of a drop the hydraulics can swallow |
| `hover.top_speed` | 5.2 | Fastest in the game by a metre a second |
| `hover.contact_grip` | 0.15 | "No pushing power". Measured: 0.00 m of shove against the 6 wheel's 0.03 |
| `hover.hover_height` | 0.2 | The cushion. Held to the millimetre. Raising it puts the weapon out of reach of a low opponent, which is the tall tank trap of 2026-09-16 |
| `hover.flip_factor` | 0.55 | Multiplies the hull's flip and tip resistance. Lower is easier to throw |
| `adaptive_tracks.belt_floor` | 0.4 | What is left when both belts are chewed to nothing |
| `reactive.knockback` | 90 | Newton seconds per unit of condition a blow takes off |
| `overcharge_core.cook_rate` | 0.004 | Core condition per second at full. 0.006 makes it genuinely dangerous over a three minute fight |
| `overcharge_core.hit_factor` | 1.25 | How much harder every weapon on the machine hits |
| any `weight` | | The price is the weight times `economy.price_factor`, so weight is the balance lever and the price follows |

## 8. What this touched outside my own files

Small, targeted edits, each one inside the section the contracts file gives D2:

- `bot.gd`: the overcharge case in `_resolve_utility`; `add_hull_mass`, `hit_factor`;
  `flip_resistance` and `tip_resistance` now multiply by the drive's `flip_factor`; the hazard
  factor, the attacker's hit factor, the hull bleed and the reactive knockback queue in
  `report_contact` and `hazard_hit`; `_bleed_drive_from_hull`, `_queue_knockback`,
  `_flush_knockbacks` and `_cook_core`; `sheds_visual` in `_handle_zero`.
- `damage.gd`: the catalogue material factor, the static `reactive_knockback` helper and
  `bleed_drive`. D1 was editing the same file for the pierce source; both sets of changes are in.
- `drive_base.gd`: five hooks (`hazard_factor`, `flip_factor`, `hull_bleed`, `sheds_visual`,
  `bodiless`), each reading a catalogue key whose default is the old behaviour, so the five Stage 4
  drives are unchanged.
- `fight_types.gd`: two rows in `MATERIAL_COLOUR` so the new plates are not both default grey.
- `assembly_test.gd`: the catalogue count is now seven chassis and eight drives; the
  `condition()["wheels"]` check reads `tracks` then `wheels` from the row rather than special
  casing the id, which matches Swift's `conditionCount` exactly; and the model check asks for a
  hull's .glb only when the manifest has one, which is what the same function has always done for
  a weapon. The Apex has no model yet, so it wears the lofted profile in `apex.gd` (which is also
  its collision) until agent E's lands, and the gate re-arms itself when it does.

## 9. What is not verified

- **No device or Simulator play.** The owner is at the Mac, so everything here is headless. How a
  walker and a hovercraft FEEL under a thumb is the one thing these tests cannot answer, and it is
  the reason section 7 is a list of dials rather than a list of settled numbers.
- **The hover's cushion measures height above world y = 0**, which is the arena floor in all six
  arenas. Anything a machine could drive onto that stands more than 0.2 m proud would leave it
  sitting rather than hovering; nothing in the catalogue of arenas does (the spinning table is
  0.04 m). If an arena ever gains a raised deck, the cushion should read the floor under it with a
  ray rather than assuming zero.
- **The spikes still stand in a hover's way.** `hazard_factor` 0.0 means a floor hazard does it no
  damage; the spike bodies can still bump a low riding hull about. That is the intended reading of
  "floats over", but it is worth watching on the phone: a hover punted by a spike it took no damage
  from may look like a bug even though it is the rule working.
