# Wave P, agent D1: the six new weapons

2026-09-21. Brief v5 section 9.5's six weapons, at the ids and kinds fixed in
`docs/wave-p-contracts.md` (row "D1 weapons"). They were already on the Level ladder and
already listed in B2's shop under "Still to come"; they are now real parts that assemble,
fight, price themselves and pass the career self test.

Nothing here deviates from the contract, so there is no "Amended by D1" paragraph in the
contracts file. One thing the contract did not decide is written up under "What the
contract left open" below, with what was done about it.

## What was built

| File | What it is |
|---|---|
| `Arena/bot/weapons/shock_prod.gd` | new, welded contact prod (kind `prod`) |
| `Arena/bot/weapons/tesla_arc.gd` | new, charging coil (kind `arc`) |
| `Arena/bot/weapons/drill_lance.gd` | new, lance on a forward-axis hinge (kind `drill`) |
| `Arena/bot/weapons/twin_saw.gd` | new, two discs on one arbor (kind `saw`) |
| `Arena/bot/weapons/napalm_cannon.gd` | new, mortar plus the `FirePatch` it throws (kind `flame`) |
| `Arena/bot/weapons/vortex_spinner.gd` | new, `extends full_body_spinner.gd` (kind `fbs`) |
| `Arena/tests/weapons_p_test.gd` | new, 61 checks, headless, deterministic |
| `Shared/parts.json` + `Arena/data/parts.json` | six `weapon` rows, and `vortex_spinner` added to the Shell's `weapons_allowed` |
| `Arena/bot/damage.gd` | one new section: the three new damage sources and `pierce_factor` |
| `Arena/bot/bot.gd` | three lines in `take_direct_damage`: the pierce factor branch |
| `Arena/bot/chassis/shell.gd` | `has_own_ring()` now tests the catalogue KIND, not the id |
| `Arena/ai/opponent_ai.gd` | three new rows in `PROFILES`, a new `PROFILES_BY_ID`, `_weapon_id`, one branch in `_profile` |
| `Arena/ui/controls.gd` | `WEAPON_WORDS`, `WEAPON_HOLDS` and `SPIN_UP_KINDS` rows for `prod`, `arc` and `drill` |
| `Arena/tests/ui_test.gd`, `Arena/tests/assembly_test.gd` | the two counts that said "ten weapons", and the Shell's weapon list sentence |

`Shared/parts.json` was edited with a JSON-aware script (key order and the one-space indent
preserved, byte-identical round trip verified before any edit) and copied byte for byte to
`Arena/data/parts.json`; the script is idempotent, because agent D2 was writing to the same
file at the same time.

## The catalogue rows, and why these numbers

Price is `economy.price_factor.weapon` (12) times the weight, so **weight is the price
lever** and it is the first column below. Every one of the six is dearer and heavier than
the one below it on the ladder, and `weapons_p_test` fails if that ever stops being true.

| id | L | kg | scrap | reach | the rest |
|---|---|---|---|---|---|
| `shock_prod` | 35 | 13 | 156 | 0.28 | `dps` 0.035, `disrupt_s` 1.2, `reset_s` 2.5, `arm_s` 0.12 |
| `tesla_arc` | 60 | 17 | 204 | 0.75 | `dps` 0.09 a discharge, `disrupt_s` 1.6, `spin_up_s` 1.6, `reset_s` 2.2 |
| `drill_lance` | 65 | 19 | 228 | 0.45 | `dps` 0.075, `spin_up_s` 1.0, `knockback` 0.04 |
| `twin_saw` | 75 | 21 | 252 | 0.38 | `dps` 0.13 shared over `blades` 2, `spin_up_s` 0.6, `knockback` 0.05 |
| `napalm_cannon` | 80 | 23 | 276 | 1.35 | `dps` 0.03, `fuel_s` 6 a patch, `patch_radius` 0.45, `charges` 5, `reset_s` 2.0, `ranged` |
| `vortex_spinner` | 95 | 32 | 384 | 0.48 | `impulse` 250, `spin_up_s` 3.2, `control_penalty` 0.55, `lift` 0.45 |

The six add 1500 scrap to the shop's total bill. A campaign won every match banks about
10,880 (base plus half the damage bonus plus survivor), and the whole shop now costs well
under that, which is the self test's "a won campaign can clear the whole shop" check.

Each one against the part it outranks:

- **shock_prod (35)** over the lifter (32). Lighter than the lifter and does less damage than
  a Level 5 saw. You do not buy it for damage: every touch cuts the other machine's DRIVE
  for 1.2 s, which is how you hold something over the spikes without a claw.
- **tesla_arc (60)** over the crusher (50). Cheaper and lighter than the claw, and it does not
  need to be ON them: 0.75 m from a coil at the nose is roughly a chassis length. It stalls
  weapon AND drive at once, which nothing else in the game does.
- **drill_lance (65)** over the arc. Damage per second between the saw's and the twin saw's,
  and the only weapon whose damage barely cares what the plate is made of (see below).
- **twin_saw (75)** over titanium armour (70) and the lance. 0.13 dps against the saw's 0.06,
  0.38 m of reach against 0.30, two bodies so losing one leaves half a weapon. 21 kg against
  12 is most of a wedge's spare budget: it is a machine built around the saws.
- **napalm_cannon (80)** over the twin saw. Less damage per second than anything near it, and
  the only weapon in the game that fights where its wielder is not.
- **vortex_spinner (95)** over the overcharge core (90) and the full body spinner (78).
  `impulse` 250 against 200, a shorter wind-up, a shade more of your driving left, and the
  bite goes 45 percent upward instead of flat.

## The mechanics, and the five decisions inside them

**1. Three new damage sources, in `damage.gd` beside the rule they feed.** `SOURCE_SHOCK`
and `SOURCE_ARC` have no row in any material's `factor` table, so every material takes them
at 1.0. That is the ruling `flamethrower.gd` made for "burn", and the right one here: the
plate you fit is the answer to spinners and saws, and it is not the answer to electricity.

**2. "Ignores half the armour's factor" is `BotDamage.pierce_factor`.** `SOURCE_PIERCE` reads
the material's own `cut` factor and moves it halfway to 1.0: steel 0.4 becomes 0.7, HDPE 1.6
becomes 1.3. The saw's spread across the four materials is 4.0 to 1; the lance's is 1.86 to
1. It is applied in `Bot.take_direct_damage` and nowhere else, because that is the only
place that knows the victim's material (and that remaps a chassis hit onto the top plate).
There is deliberately no `armour_pierce` key in the catalogue: one number, `PIERCE_IGNORE`,
in `damage.gd`.

**3. The twin saw shares its `dps` between its blades.** Each disc applies `dps / blades`, so
the number in the shop is what the weapon does with both discs in the work, and one disc
alone (0.065) still beats the whole Level 5 saw (0.06). Each blade registers half the
catalogue weight, so the build's simulated mass still matches the shop to a tenth of a
percent (`assembly_test` checks it to 10 percent, `weapons_p_test` to 2).

**4. The fire patch is not part of the bot.** `napalm_cannon.gd`'s inner `FirePatch` is a
Node3D in the fight world with its own `_physics_process`, so it stays where it was thrown,
keeps burning after the machine that lit it has driven off or been flipped, and frees itself
after `fuel_s`. It is an Area3D, not a body, so nothing can push it or damage it. The charge
does NOT fly as a rigid body: the landing point and the parabola are worked out at the
moment of firing and stepped one physics tick at a time, so two runs of one seed put the
fire in the same place to the millimetre.

Two deliberate softenings, both one line if the owner wants them back:
- the patch only burns the OTHER machine (`Bot.opponent_damage_tick` refuses to damage its
  own bot). A patch that cooked its owner would be unusable in the clinch, which is where
  phone-sized fights actually happen. The dial is in `FirePatch._burn`.
- the patch cuts the DRIVE only after a second of exposure, never the weapon, and needs no
  rng to decide which (the flamethrower alternates off the shared rng; a floor fire cooking
  the motors is the one that reads).

**5. The vortex is the full body spinner with one vector changed.** It `extends
full_body_spinner.gd` rather than copying 400 lines of it, and overrides exactly two things:
`_tangential` (the bite leaves along the tangent AND upward, in the catalogue's `lift`
proportion) and `_shield` (see below). Measured: it throws a parked machine 1.8 m off the
floor, where a flat full body spinner bats it sideways.

## What the contract left open, and what was done

The contract fixes `vortex_spinner` as having **no** `requires_chassis`, with the Shell and
the Apex listing it in `weapons_allowed`. But `BuildRules` only restricts a hull that
declares a list, and the Wedge, Box, Pyramid, Long/Low and Tall Tank declare none, so **the
vortex spinner is currently legal on every hull in the game**. That is the rules as written
and it plays fine (measured: it works on all six, throwing 1.2 to 1.6 m and pushing 4 to 6
m), but it created one real hole, which is closed:

`full_body_spinner.gd` takes the armour panels out of the collision world above 30 percent
spin, because on a Shell the ring genuinely IS the bodywork. Inherited unchanged, that would
have handed a 30 kg Wedge the Shell's unreachable flanks for the price of a weapon.
`vortex_spinner.gd` overrides `_shield` so the faces only leave the world on a hull that has
actually given up its own ring to this weapon (`chassis_module.has_own_ring()` is false).
Everything else the weapon costs, the 32 kg, the 3.2 s wind-up and the control penalty, is
paid whatever it is bolted to.

**If the owner wants the vortex restricted to the Shell and the Apex**, that is one rule in
D2's `build_rules.gd` and its Swift twin: a `requires_chassis_any: ["shell", "apex"]` key
beside the existing `requires_chassis`. It is NOT `requires_chassis`, which takes one id, and
it is not `weapons_allowed`, which is permissive (the ram is listed on the Shell and is legal
everywhere). Left undone deliberately: `build_rules.gd` is D2's file and the contract does
not ask for the restriction.

Also worth one line for D2: `Arena/bot/chassis/shell.gd`'s `has_own_ring()` now tests the
catalogue KIND rather than the weapon id, so any `fbs` weapon takes the ring over. If the
**Apex** is meant to hand its bodywork to a full body spinner the same way, it needs its own
`has_own_ring()`; without one it keeps its hull and the vortex builds a ring at its front
socket, which works and does not shield.

## The AI

`PROFILES` gained `prod`, `arc` and `drill`. A new `PROFILES_BY_ID`, checked before the kind
table, carries a row for each of the six, because two of them do not fight like their kind:

- `napalm_cannon` is kind `flame`, whose row closes to contact and holds the button. A mortar
  wants the opposite: `standoff` 1.25 and `engage` 0.8 of a 1.35 m reach, so it throws fire
  while the other machine is still coming, and `orbit` so it circles its own patch rather
  than driving through it.
- `vortex_spinner` holds a wider ring than the full body spinner and will not close below
  `READY_ENGAGE`: 3.2 s is a long wind-up to waste.

`_weapon_id` is duck typed like everything else in that file (it reads `weapon.spec.id`),
so a fake bot in `ai_test` with no weapon at all still resolves to the flipper default.
`weapons_p_test` proves every weapon in the catalogue, old and new, resolves to a row with
all seven columns.

## Words on screen

`prod` reads **SHOCK**, `arc` reads **ARC**, `drill` reads **DRILL**; all three are held, not
tapped, and only the drill carries a spin-up ring (a prod's readiness is a cooldown and a
coil's is a charge, and a ring that meant either would be lying). The status readouts are
`PROD`, `ARC 64%`, `DRILL 100%`, `SAWS 100%`, `SHELLS 4` / `DRY`, `VORTEX 100%`.

All six are worked by HOLDING the button. A mortar or a coil worked by a tap would be a
timing test on a touchscreen with the muzzle out of shot, and the matrix test in
`weapons_test.gd` works every weapon the way a thumb does, so a tap weapon would also have
needed a line in its `TAP_WORKED` list.

Nothing user-facing uses an em dash, an exclamation mark, or the words tier, circuit, season
or bracket. `weapons_p_test` checks every name and blurb for the first two.

## What was measured

`weapons_p_test.gd`: **61 checks, 0 failures**. Every number below came out of it or out of
`weapons_test.gd`'s matrix, headless, on the seeds in the files.

| Measurement | Number |
|---|---|
| shock prod, 4 s of contact | 0.42 condition removed, 2 drive stalls, first at tick 36 |
| and the stall ends | gone 1.6 s after the prod comes away |
| tesla arc, coil full | exactly at `spin_up_s`, 1.6 s |
| one discharge | 0.13 removed, weapon AND drive stalled, both back within 2 s |
| drill lance on a steel plated machine | 0.50 removed in 2.85 s of boring |
| the same 0.1 of damage on steel | 0.07 as a pierce against 0.04 as a cut, 1.75 times |
| twin saw | 1.10 removed in 2.82 s, two blades, both at speed in 0.6 s |
| napalm, one shell, attacker never moves | 0.57 removed from 1.6 m away, alight at tick 28 |
| the patch goes out | 0 alight after `fuel_s` plus 1.5 s, and after the bell |
| vortex spinner on a Shell | 0.63 removed, target thrown 1.81 m off the floor |
| weapon bodies against the price | every one inside 2 percent of `weight x MASS_SCALE` |

`weapons_test.gd`'s matrix (every weapon on every hull the builder allows, 300 ticks each)
passes with all six in it: shock prod 0.21 to 0.32 removed, tesla arc 0.09 to 0.14, twin saw
0.98 to 1.21, napalm 1.5 to 1.9, vortex 0.55 to 0.95 plus a 1.2 to 1.6 m throw. For scale,
the Level 5 saw removes 0.47 to 0.59 on the same test and the Level 25 horizontal spinner
1.25.

## Dials the owner can turn

Everything in the table at the top is a catalogue number and takes effect with no rebuild of
anything but the byte copy (`cp Shared/parts.json Arena/data/parts.json`).

- **Price**: the `weight` column, times `economy.price_factor.weapon`. Raising a weight makes
  a part dearer AND harder to fit inside the 100 kg budget, which is the double lever.
- **How long a stall lasts**: `disrupt_s` on the prod, the arc and the cannon. How often:
  `reset_s` on the prod and the arc, and `arm_s` (how long the prod has to be held against
  something before it bites).
- **The napalm**: `charges` is how many shells, `fuel_s` how long one patch burns,
  `patch_radius` how wide it is, `reach` how far it is thrown, `reset_s` how fast it walks
  them out. Five shells of six seconds is 30 seconds of fire in a 180 second fight.
- **The vortex**: `lift` 0 is a flat full body spinner, 1 is a ring that only throws.
  `control_penalty` is how much of your driving survives the spin.
- **The lance's rule**: `BotDamage.PIERCE_IGNORE`, 0.5. At 1.0 the lance ignores armour
  material entirely; at 0.0 it is an ordinary saw.
- **The twin saw's spread**: `BLADE_GAP` in `twin_saw.gd`, 0.23 m centre to centre.

## What is NOT done, and what it needs

- **Meshes and textures are agent E's**, as the contract says. Until they land each of the
  six draws its own primitive fallback (a box, a cylinder, a tapered cylinder), the same
  pattern `saw.gd` and `ram.gd` have always used, so nothing is ever invisible. The requests
  are below.
- **Sound and fx are agent F's.** The napalm patch borrows `fx/flame_cone.gd`, the effect the
  flamethrower already ships, stood on its end, so a lit patch is real fire and not a
  placeholder. The arc has no visible bolt yet: `tesla_arc.gd` exposes `last_target()` and
  `arcs()`, which is everything a lightning effect needs, and it emits `weapon_fired` on
  every discharge.
- **Three button glyphs are undrawn.** The HUD's primary button is named for the weapon's
  PART id, so the three new kinds want `Art/ui/glyph_weapon_shock_prod.svg`,
  `glyph_weapon_tesla_arc.svg` and `glyph_weapon_drill_lance.svg` (the twin saw, the napalm
  cannon and the vortex spinner share their kind with an older weapon and already resolve to
  its glyph). Until they exist the button falls back to the word, which is SHOCK, ARC and
  DRILL, and `ui_test` reports "10 of 13 glyphs are drawn" rather than failing.
- **The `career-masters.json` QA fixture is a Level 100 career that owns nothing above
  `tracks`**, so `-autoShop` at the top of the ladder shows six weapons nobody has bought.
  That is agent A's fixture, not mine, and it is only worth a line: adding a few of the new
  ids to its `owned` list would make the shop's "owned" rows testable at Level 100.
- **No phone time.** Everything above is the headless simulator. The three things that need a
  real device are whether a fire patch reads at phone size, whether the prod's stall is
  legible (the other machine simply stops, with no effect of its own yet) and what four
  simultaneous patches cost in frame time.

## Mesh requests for agent E

All six mount on the front socket except the vortex, which takes the shell mount. Dimensions
are the collision bodies the gameplay already uses, so a model built to them lines up with
what actually hits. Each wants a `socket_pivot` empty at the point named, as the saw and the
ram already do.

1. **`shock_prod`** — a welded head, 0.10 deep x 0.14 high x 0.26 wide, sitting 0.18 m proud
   of the hull's nose at floor band height. Two or three insulated prongs on a ceramic
   stand-off, copper or brass tips, heavy cable running back into the bodywork. No moving
   parts. `socket_pivot` at the back face, on the centreline. It should read as electrical at
   a glance, because the player's only other clue is the other machine stopping.
2. **`tesla_arc`** — a coil, 0.14 x 0.18 x 0.22, at mid band on the nose, 0.06 m proud. A
   vertical drum wound with wire, a ball or horn electrode on top, ribbed insulator at the
   base. No moving parts, but F will want a socket empty at the electrode tip called
   `socket_spark` for the bolt to leave from. `socket_pivot` at the back face.
3. **`drill_lance`** — a tapered lance 0.30 long, 0.075 radius at the root and a point at the
   tip, lying along +X and SPINNING about its own length at up to 18 rad/s. Helical flutes so
   the rotation is visible from the side, a collar and a motor housing at the root that stays
   with the hull. `socket_pivot` at the centre of the shaft (the hinge is at the body's
   centre, not at the root).
4. **`twin_saw`** — ONE disc, instanced twice: 0.19 m radius, 0.020 thick, spinning about the
   bot's Z at up to 14 rad/s. The two are 0.23 m apart across the machine, so a shared arbor
   and guard would have to be a separate piece or part of the disc model repeated. Toothed
   rim, hub boss, `socket_pivot` at the centre of the disc. Read the saw's model: this is the
   same part at 1.23 times the size, and looking like a deliberately bigger version of it is
   the point.
5. **`napalm_cannon`** — a short mortar tube, 0.18 x 0.16 x 0.18, on the nose at mid band,
   0.04 m proud, canted up a few degrees. Ammunition visible somewhere (a five round rack or
   a drum) would sell the finite charges. No moving parts required. `socket_pivot` at the
   back face; a `socket_muzzle` at the mouth would let F put smoke in the right place.
   Separately, the patch itself wants a scorch decal mesh, a disc of `patch_radius` 0.45 m
   lying on the floor, to replace the plain emissive disc in `FirePatch._light`.
6. **`vortex_spinner`** — the Shell's ring again, 0.48 m radius, 0.14 to 0.16 m tall, spinning
   about the bot's Y. The difference from `full_body_spinner.glb` is the teeth: raked,
   scooped, angled up, so it visibly lifts what it hits rather than batting it. `socket_pivot`
   at the model's own origin, exactly as the full body spinner's, because it parents at
   identity on the hull's centre. It also has to look right on a hull that is NOT a Shell,
   since the rules allow that: a ring standing proud of a wedge's nose.

## Traps found on the way

- **A weapon that makes two bodies must split its mass.** `weapon.mass_kg` is the catalogue
  weight and `mass()` returns all of it; registering two blades with `mass()` each would have
  made every twin saw build 21 kg heavy and broken `assembly_test`'s 10 percent mass check on
  a test that never mentions the twin saw.
- **An inner class cannot be assumed to see its outer script's constants.** `FirePatch` keeps
  its own `FLIGHT_S`, `ARC_HEIGHT`, `DISRUPT_AFTER_S` and `EXPOSURE_GRACE_S` rather than
  reaching out of itself for them.
- **`var x := a if cond else null` will not compile** when `a` is a typed node reference:
  "cannot infer the type". Declare the type.
- **A new weapon breaks two counts nobody would think to look for**: `ui_test.gd`'s "the
  catalogue still carries ten weapons" and `assembly_test.gd`'s "six chassis, five drives and
  ten weapons". Both are updated. `assembly_test`'s Shell sentence changes too, because
  `BuildRules._list_names` now has three names to join.
- **Adding a weapon with a long reach rescales the shop's reach pips.** `Catalogue.swift`
  scores every weapon's pips against the catalogue's own min and max, so the napalm cannon's
  1.35 m pushed every melee weapon's reach bar down. It is one of the reasons the lob is 1.35
  and not the 1.8 it started at: 1.8 squashed the whole column.
