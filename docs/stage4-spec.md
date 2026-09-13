# Stage 4 spec: the builder

Brief §15 Stage 4: "Weight budget, all chassis, all drives, all weapons, armour per face, utility slots,
mount-socket assembly, the test arena. Verify three different builds genuinely play differently against
the same opponent. Decide on Rumble." Read `docs/brief-v3.md` §5, §9 (garage), §10 (Workshop Test
Arena), §11 (workshop camera), §13 (mount sockets), then `docs/stage3-spec.md`, the Stage 3 notes
(`docs/stage3-*-notes.md`) and the code they describe. Stage 3 is the working baseline: preserve it
(brief §12 "preserve working gameplay over adding sophistication").

## 1. The catalogue is the contract

`Shared/parts.json` (authored here) is copied by `scripts/export-pck.sh` to `Arena/data/parts.json`
(committed too; a test asserts the two are byte-identical). Swift reads `Shared/parts.json` as a bundle
resource; Godot reads `res://data/parts.json`. Every part id, weight, stat and blurb lives there and
nowhere else. A bot config (bridge-spec `FightConfig.bots[i]`) references ids only:

```json
{ "id": "player-1", "name": "Tinribs", "controller": "player|ai|dummy",
  "chassis": "wedge", "drive": "4wd", "weapon": "flipper", "utility": ["srimech", "spare_battery"],
  "armour": { "front": {"material": "steel", "thickness": 3}, "sides": {...}, "rear": {...}, "top": {...} },
  "livery": "#3358a0",
  "damage": { ...as before... } }
```

### Weight and validity rules (implemented twice, Swift for the UI and GDScript `BuildRules` for the arena)

- total = chassis.weight + drive.weight + weapon.weight + sum(utility.weight)
  + sum over faces of thickness * material.kg_per_unit_area * face.area. Must be <= 100.
- utility: at most 2, no duplicates. `srimech` required unless chassis.invertible.
- `full_body_spinner` requires chassis `shell`; `shell` allows only `weapons_allowed`.
- `omni` is `late_unlock` (Stage 5 gates it; Stage 4 allows everything).
- thickness 1..4 per face; every face must have a material.
- Errors are plain sentences for the UI ("Over the weight budget by 6 kg.", "A Wedge needs a srimech.",
  "The Shell only takes a full body spinner or a ram."). No em dashes.

## 2. Ownership and waves

Wave 1 (concurrent): **P2** generalises the bot assembly; **S2** builds the Swift builder; **C2** builds
the workshop turntable and the test-arena overlay. Wave 2 (after P2 lands): **W1** and **W2** implement the
nine remaining weapons against `Arena/bot/weapons/weapon_base.gd`; **R2** generalises the AI per weapon,
adds test mode, the three-builds test and the Rumble measurement.

| owner | path |
|---|---|
| P2 | `Arena/bot/**` except `weapons/` (but P2 MOVES the Stage 3 flipper into `weapons/flipper.gd` as the reference implementation of WeaponBase), `Arena/tests/physics_test.gd`, `Arena/tests/assembly_test.gd` |
| W1 | `Arena/bot/weapons/{horizontal_spinner,vertical_spinner,full_body_spinner,saw}.gd`, `Arena/tests/weapons_a_test.gd` |
| W2 | `Arena/bot/weapons/{lifter,crusher,axe,ram,flamethrower}.gd`, `Arena/tests/weapons_b_test.gd` |
| C2 | `Arena/workshop/**`, `Arena/ui/test_overlay.gd`, `Arena/ui/camera_rig.gd` (workshop mode), `Arena/tests/workshop_test.gd` |
| R2 | `Arena/fight/**`, `Arena/ai/**`, `Arena/arena/test_arena.tscn`, `Arena/tests/{rules,ai,determinism,builds}_test.gd` |
| S2 | `Roboteer/**`, `Roboteer.xcodeproj` |

## 3. Assembly (P2)

`bot.gd` becomes catalogue-driven. `setup(bot_config, team, rng)` loads `res://data/parts.json` (cached
in a static), validates with `BuildRules`, then:

- **Chassis** from `Arena/bot/chassis/<id>.gd` (six scripts, one per chassis, each `extends ChassisBase`):
  builds hull mesh + convex shape(s) (a Tall Tank is two stacked boxes, a Pyramid four sloped faces, a Shell
  a low cylinder with a ring, Long and Low a stretched wedge with a rear ramp), sets mass and centre of mass
  from `com_height`, and exposes **sockets**: `weapon_socket(kind) -> Transform3D` (front / top / shell per
  `mount_weapon`), `wheel_slots(drive_id) -> Array[Vector3]` from the catalogue, `armour_socket(face) ->
  {transform, size}` (four plates that FIT this hull; the sides pair shares a condition), `utility_socket(i)`,
  `srimech_socket()`. Inverted behaviour per catalogue: `invertible` chassis drive normally when upside
  down (wheels protrude both ways: wheel radius > half height), `flip_resistance` and `tip_resistance`
  scale the srimech/flip impulses, `drive_fragility` scales wheel damage.
- **Drive** from `Arena/bot/drive/<id>.gd`: 2wd/4wd/6wd wheels on motorised hinges at the chassis slots;
  **tracks** = 4 hidden wheels per side under a track skin mesh, traction 1.8, turn rate 1.8, and a single
  "track" condition per side that a spinner hit can zero (the track skin detaches and that side free-wheels);
  **omni** = 4 wheels with lateral free-roll (friction anisotropy via per-wheel side force) and a strafe:
  heading magnitude drives motion in the heading direction without turning; `secondary` while upright
  pivots instantly. Drive stats (top_speed, turn_rate, push_force, traction) come from the catalogue and
  scale the motor targets and friction.
- **Weapon** via `WeaponBase` (see §4). P2 ports the Stage 3 flipper to `weapons/flipper.gd` unchanged in
  behaviour and adds `register_part()`, `weapon_socket` and the input plumbing so W1/W2 have a reference.
- **Armour** per face from `armour_socket(face)`, material colour rules as Stage 3; thickness scales plate
  mass (catalogue formula) and its break thresholds (BREAK_MIN/MAX * (0.7 + 0.3 * thickness)).
- **Utility**: `srimech` as Stage 3; `rear_wedge` adds a rear sloped plate body and multiplies damage taken
  on the rear face by 0.6; `skirts` add thin side/front skirt bodies that lower clearance by 0.02 (opponents
  cannot get under) at the cost of the bot's own front lip clearance; `magnets` apply a constant downforce
  (1.5 x weight) and scale top speed by 0.8; `scoop` replaces the front plate with a wide curved scoop mesh
  (control tool: it herds, no damage bonus); `spare_battery` multiplies weapon spin-up time by 0.7 and adds 4
  flipper charges; `counterweight` shifts the centre of mass rearward by 0.08 m and adds 8 kg.
- Livery colour from `livery` (hex) else team default.
- The Bot API from Stage 3 is unchanged for R (signals, apply_input, condition, weapon_height_band, etc.),
  plus: `func register_part(body: RigidBody3D, part_key: String, part_kind: String, mass: float)`,
  `func weapon_status() -> String`, `func weapon_readiness() -> float`, `func build_summary() -> Dictionary`
  (weights per category, total, clearance, com height) for the workshop overlay.
- `condition()` keeps the FightConfig damage shape; `wheels` length equals the drive's wheel count
  (tracks: 2 entries, one per side).
- `Arena/tests/assembly_test.gd`: every chassis x drive x weapon combination that BuildRules allows
  assembles headless without errors, with the expected body count (chassis + wheels + weapon bodies + 4 to
  5 panels + utility bodies) within brief §12's cap (chassis + 6 wheels + weapon + 4 panels; tracks count as
  wheels), total mass within 10 % of the catalogue total, and the bot drives straight 3 m in 2 s and turns.
  Also: parts.json and Shared/parts.json are identical.

## 4. Weapons (W1, W2) against `weapon_base.gd`

Each weapon is one script `extends WeaponBase`, mechanically distinct (brief §5.3), built from primitives,
registering its bodies with `bot.register_part(...)`, part_kind "weapon". Use the catalogue numbers
(`impulse`, `reach`, `spin_up_s`, `dps`, `charges`, `reset_s`, `fuel_s`, `disrupt_s`, `clamp_force`).

- **horizontal_spinner** (W1): a 0.55 m bar on a vertical hinge at the front socket, motorised; `pressed`
  spins up over `spin_up_s` (angular velocity ramps; energy = readiness); contact impulses scale with spin
  fraction; **self-destabilise**: on a hit above 60 % spin, apply a reaction torque to the chassis
  (`self_destabilise` factor) so the wielder lurches; the bar is a real body so it can be bent (condition).
- **vertical_spinner** (W1): a drum (cylinder, axis along Z) at the front socket spinning "up" at the
  front; contacts get an upward impulse (`launch`); safer for the wielder (small reaction).
- **full_body_spinner** (W1): the Shell chassis' ring body spins (the ring is a separate body on a vertical
  hinge, registered as the weapon); spin-up 3.5 s; while spinning, drive input is scaled by
  `control_penalty`; no exposed weak side because the ring covers all faces (the ring is the armour: hits
  reduce the ring's condition and the faces are unreachable until the ring stops).
- **saw** (W1): a disc on the front socket spinning at constant speed once `pressed` (instant, 0.4 s spin);
  continuous contact damage `dps` per second of contact on whichever part it touches (via a small Area3D
  on the blade reporting overlaps each tick: apply `bot.opponent_damage_tick(part, dps * dt)` which P2
  exposes on the Bot, cutting through hdpe fast and steel slowly using MATERIAL_FACTOR "cut" from the
  catalogue), near-zero knockback (tiny impulses).
- **lifter** (W2): a hinged forks arm at the front; `pressed` raises it at `lift_rate` rad/s toward 70
  degrees, released lowers it; strong motor, no launch; carrying an opponent means their chassis rests on the
  forks (pure physics).
- **crusher** (W2): a jaw on a top-front hinge; `pressed` closes with `clamp_force`; when the jaw contact
  holds an opponent part for > 0.3 s the bot is "pinned" (the other bot's drive is fought by the clamp) and
  `dps` applies to the clamped part; releasing opens.
- **axe** (W2): an overhead arm at the top socket; `fired` swings from rest (-70 degrees) to +60 in 0.15 s
  with `impulse` scaled by `top_bonus` when it hits a top face; `reset_s` to return; while reset the arm is
  dead weight.
- **ram** (W2): no moving parts; a spike wedge mesh on the front; contact impulses from the ram body are
  multiplied by `impulse_bonus` on the victim; weight saved goes elsewhere (the catalogue already prices it).
- **flamethrower** (W2): nozzle at the front; `pressed` burns fuel (`fuel_s` total); a cone Area3D of `reach`
  applies `dps` per second to every part inside and, after 1 s of continuous exposure, **disrupts** the victim:
  `bot.disrupt(kind, seconds)` which P2 exposes and which cuts either the victim's weapon or drive for
  `disrupt_s` (alternating, decided by the shared rng); visual: GPUParticles3D flame cone (presentation).
- Tests: `weapons_a_test.gd` / `weapons_b_test.gd` headless: each weapon builds on a wedge (or shell for
  fbs), readiness rises as specified, a scripted contact with a target bot produces a damage_event on the
  target with the expected part, the saw's cut factor removes hdpe faster than steel, the flamethrower's
  fuel runs out at `fuel_s`, the axe returns after `reset_s`, the crusher pins, the lifter raises and lowers.

## 5. Workshop turntable and test overlay (C2)

- `Arena/workshop/workshop.tscn` + `workshop.gd`: a lit turntable (a disc on a dark floor, warm key light,
  matching `Art/direction/bot-in-workshop.png`), one Bot assembled from a `workshop_config` bridge message
  `{ "bot": {...bot config...} }`; re-assembles on every new message (the builder sends on each change,
  debounced); `Bridge.send("workshop_ready", build_summary)` after each assembly so Swift can show the real
  numbers; camera: full turntable orbit (one-finger drag orbits here, since there are no driving controls),
  pinch zoom 0.4 to 1.5, tilt clamp 5 to 85 degrees; idle auto-rotate 8 degrees per second. Desktop QA: mouse
  drag orbits, `--roboteer-workshop=<json path>` loads a bot config at start.
- The mode switch lives in R2's fight.gd (`fight_config` shows the fight, `workshop_config` shows the
  workshop); C2 exposes `Workshop.show_bot(config)` and `Workshop.set_active(on)`.
- `Arena/ui/test_overlay.gd`: physics debug overlay for the test arena (brief §10): a CanvasLayer drawing,
  per bot, the centre of mass marker, the front lip clearance in mm, the weapon reach arc and height band,
  wheel contact states, current speed, and the last damage event; a "Reset" button (calls back into R2's
  `test_reset`) and a toggle. Only shown when `rules.mode == "test"`.

## 6. Test arena, AI generalisation, three-builds proof, Rumble (R2)

- `rules.mode = "test"` in FightConfig: no timer, no judges, no KO count, no out-of-arena loss (a bot that
  leaves is re-placed after 2 s), opponent `controller: "dummy"` (assembled from its config but never driven;
  `debug.opponent_ai` may still make it fight). `test_reset` message re-places and repairs both bots.
  `Arena/arena/test_arena.tscn`: The Yard without the spike hazard plus a wall-mounted dummy target pad.
- AI per weapon kind (`ai/opponent_ai.gd`): spinners spin up before engaging and disengage to re-spin;
  flipper/lifter/drum bots attack the flanks and fire under; axe waits until it sits on the opponent's top;
  saw/crusher latch and stay; ram charges; flame keeps `reach` distance and sweeps; fbs orbits. Uses
  `weapon_readiness()`/`reach()` only. Rivals later reuse this.
- `Arena/tests/builds_test.gd`: AI vs AI (player_ai on), same seed and the same opponent (box, 4wd, saw,
  all steel) against three builds: (a) wedge/4wd/flipper hdpe sides, (b) box/6wd/horizontal_spinner steel,
  (c) long_low/tracks/ram titanium. Assert over 60 s the outcomes and the tallies differ materially:
  (b) removes at least one panel, (a) produces airtime for the opponent above 0.4 m at least twice, (c) has
  the highest push-distance metric and the lowest damage_removed; and no build exceeds 100 kg.
- **Rumble measurement**: a headless run with a third AI bot for 30 s; record the mean and worst physics
  step time (`Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)`) for 2 bots and 3 bots and write
  both to `docs/stage4-rumble-decision.md` with a recommendation (keep if 3 bots stay under 8 ms worst case
  on this Mac, which is a proxy; the final call is made on the phone).

## 7. Swift builder (S2)

- SwiftData: `BotBuild` (@Model): name, chassis, drive, weapon, utilities [String], armour (four faces of
  material + thickness), livery hex, damage state (JSON string of the FightConfig damage dictionary),
  record (fights, wins, kos, killedBy), createdAt. `Catalogue` loaded from `Shared/parts.json` once.
- Screens (GBC chrome: four greens, chunky face, dot-matrix texture; see `docs/stage2-art-direction.md`
  and `Art/direction/bracket-screen.png`): **Workshop** (list of builds, capacity 1 in Stage 4, "New bot",
  the selected bot fights); **Builder** with a weight bar (used of 100, red when over), pickers for chassis,
  drive, weapon (each row: name, weight, two or three stat pips from the catalogue, the blurb), utility (two
  slots), armour face grid (front/sides/rear/top: material segmented + thickness stepper, weight per face),
  livery colour choice (6 presets, never gold), name field, validation sentences, and the live 3D preview
  region hosting the Godot view (sends `workshop_config` debounced 150 ms; on the simulator shows the
  placeholder with the `workshop_ready` numbers); **Test in the arena** button (FightView with
  `rules.mode = "test"` and the overlay) and **Fight** (the Stage 3 fight with the selected build).
- `BuildRules` in Swift mirrors §1 exactly; unit test target not required, but a debug assertion that the
  Stage 3 fixture validates.
- Keep every Stage 3 QA flag. Add `-build <name>` to select a build by name at launch and `-autoWorkshop`.

## 8. Acceptance (main session)

1. `scripts/test-arena.sh` green including assembly, weapons, builds, workshop tests.
2. Desktop window: each of the six chassis and ten weapons assembles and reads distinctly at the fight
   camera (frames reviewed); three builds fight the same opponent differently (builds test + frames).
3. Simulator: builder edits change the weight bar and validation; the selected build reaches the arena
   (headless) and the result sheet shows its parts; `workshop_ready` numbers arrive.
4. Rumble decision written.
