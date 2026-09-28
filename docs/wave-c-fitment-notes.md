# Wave C fitment notes (branch `wave-c-fitment`)

Owner report 2026-09-28: "I added an extra battery to a box robot and that battery was floating
in mid air. I added a saw to a robot and that was poking through the 3d render at the front."
Plus, mid-wave, the hero (Tinribs) close-up: flipper plate wider than the hull, front tyre on the
plate edge, plate hovering over the ramp.

## The harness

* `Arena/qa/fitment_dump.gd` assembles every chassis x every legal weapon x every drive, every
  weapon at armour 1 and 4 and with the scoop, every legal utility fit in both orders against
  every weapon and every drive, every armour material x thickness 1-4, the stage slice bots and
  the owner's two cases: **4,939 machines**, built with `Bot.setup` exactly as fight and garage
  build them, and dumps every drawn mesh, collider and hinge in bot space.
  `Godot --headless --path Arena --script res://qa/fitment_dump.gd -- OUT_DIR [sweep]`
* `Tools/fitment/fitment_check.py OUT_DIR --md docs/qa/fitment.md --json X.json` voxelises every
  mesh as a solid (3 mm, winding-number columns on three axes) and reports per part: floating
  (air to its mount > 5 mm), buried, clash with another part, weapon swept volume (spin a full
  turn, or swing through the hinge limits) through hull/plates/drive/utilities, below the floor,
  mirror twin, deck overhang, and a collider-vs-drawn table. ~15 min with 3 workers.
* `Arena/qa/fitment_render.gd/.tscn` renders contact sheets (3/4, side, front, top, nose, and a
  "spin" pose with every hinged weapon body turned about its hinge).
* `Tools/fitment/seat_utilities.py` writes the deck heights in `Arena/data/fitment.json`.

Tables: `docs/qa/fitment.md` (after) and `docs/qa/fitment-before.md` (before). Images:
`docs/look/fitment/*-before-after.jpg`, `contact-before.jpg`, `contact-after.jpg`.
The page `docs/look/fitment.html` was NOT written yet (see Where I stopped).

## Before / after (same 4,939 machines, same checker)

| check (count of machine x part findings) | before | after |
|---|---|---|
| wheel through armour plate | 15,077 | 900 |
| track/roller through plate | 862 | 60 |
| drive unit (tracks/legs/hover) through plate | 628 | 118 |
| two utility parts in one place | 832 | 44 |
| deck utility buried (battery/counterweight/core) | 2,126 | 0 |
| deck utility overhanging | 1,634 | 187 |
| saw through hull / plates / drive (rest + spin) | 890 | 0 |
| twin saw through hull / plates / drive (rest + spin) | 1,644 | 108 (72 cm3 max) |
| magnets/skirts/rear wedge below the floor | 843 | 0 |
| shock prod / drill / axe floating off the machine | 240 | 0 (axe 6 mm) |
| srimech / skirts buried | 304 | 0 |

Machines with any finding: 4,935 -> 4,655 (most remaining rows are the open items below).

## The owner's cases

1. **Battery floating** = the hero WEDGE (`docs/look/fitment/wedge_battery-*`). Deck utilities
   took `utility_socket(0)` from the .glb, 0.224 m up, and the hull pass lowered the wedge's deck
   under it: 99 mm of air. On the box/pyramid/tall tank/apex/long low the same socket put the
   battery INSIDE the srimech base; a second deck part went to the BELLY socket, inside the hull.
   Fix: deck parts take slots from `Arena/data/fitment.json` (two per hull, either side of the
   srimech line), heights measured off the drawn hull + plates by `seat_utilities.py`. Presentation
   only. `box_battery-dq-before-after.jpg`, `wedge_battery-q/s-before-after.jpg`.
2. **Saw poking through the front** (`box_saw-*`, `long_low_saw-*`). Two causes: (a) saw.glb was
   one mesh, so the guard, belt covers and motor were children of the SPINNING blade body and went
   round with the disc through the nose and deck; (b) the pivot rule put the blade centre inside
   the hull on every chassis (125 mm inside on the long low). Fix: saw.glb split into `body` (disc)
   and `mount` (static, handed to the chassis like the flipper's gas system; guard shortened, back
   plate removed), and the blade stands proud of the armour with 20 mm in a slot cut in the front
   plate. Twin saw: same rule + a drawn axle and boom.
3. **Hero close-up** (`hero-shop-before-after.jpg`, real `menus_a2_capture` arena/shop view).
   Flipper model (0.524 m) narrowed to clear the front tyres by 30 mm, the fitted front plate
   narrowed the same way, and the drawn arm laid on the ramp (model pitch bias 6.5 -> 4.5 deg on
   the wedge only). Body, box and joint untouched. Checked in the garage/stage render; the fight
   builds the same Bot so the fit is identical there.

## Other fixes (all presentation-only unless marked)

* Generic plates: no longer scaled by thickness/12 mm (a unit-4 plate drew 245 mm deep); drawn at
  the collider's outer face, growing inward 25 %/unit; split into pieces between wheels/tracks;
  slot for blades. Fitted (wedge) plates trimmed for 6wd/2wd wheels.
* Scoop lies level at the nose (was a 0.3 m upright blade on flat noses, 105 mm into the floor
  on the wedge). Skirts centred on their collision lip. Magnets and rear wedge lifted above the floor.
* Visual supports: posts under deck-hinged axe/crusher, forks for drums, boom for the drill,
  stand-off bars for the shock prod.
* **PHYSICS (flagged): saw + twin saw pivot** `x = nose + radius - 0.02` (was `nose + 0.03 - radius`).
  Changes every fight with a saw/twin saw (e.g. `builds_test` opponent box/saw, BANDSAW boss).
  Teeth now reach ~0.29 m past the armour (catalogue reach 0.30), was 0.03-0.12 m. Needs a balance
  look (saw was rated WORKS in the gauntlet).

## Hashes

* `determinism_test` 42/0 on this branch (twice).
* `hazard_determinism_test`: the 6 goldens fail on this branch AND on an untouched HEAD (39e0cd3)
  worktree with byte-identical hashes, so the fails were pre-existing and nothing here moved them
  (those fixtures are wedge/flipper). Main has since re-recorded them (1f0975c).
* Expected to move: anything with a saw or twin saw in it (builds_test saw opponent, BANDSAW).
  NOT yet run / re-recorded: see below.
* assembly_bugs 15/0, assembly_test 23/0, parts_p 167/0, texel_density 21/0, stage_seat 66/0,
  stage_build 38/0, workshop 88/0 (run before the last scoop/flipper-bias edit was committed;
  rerun).

## Where I stopped (2026-09-28, owner "stop and save")

Done and committed: harness, checker, renderer, all fixes above, before/after tables and images.

In progress, NOT done:
1. Wedge deck slot: the pods are ridges, so a counterweight/core at z +-0.25 overhangs (84-100 %)
   or floats 19 mm. Tried moving the slots into the centre channel (x -0.28, z +-0.125, scale 0.6)
   but the seat tool's footprint caught the pod walls (y 0.225): reverted. Next: seat on the
   channel floor (~0.051) with a footprint mask, or a small saddle.
2. Remaining open findings (by design or owner call):
   * full body / vortex spinner rings sweep through wheels, plates and hull everywhere (the ring
     encloses the machine; physics excludes self-collision). Owner call: accept or shrink.
   * horizontal spinner and drum sweep through the hull/plates: blades hang over the nose.
   * flipper/lifter swing through the hull at the top of the stroke on flat noses (apex worst).
   * axe/crusher arm clip the front plate at rest on box/pyramid (up to 394 cm3).
   * pyramid side plates stand 45-99 mm off the sloped waist; shell plates/wheels under the ring.
   * scoop clashes the front weapon (scoop + flipper/drum): needs a rule (lower the weapon or
     drop the scoop visual when a floor weapon is fitted).
   * mirror check flags single deck parts and adaptive-track rollers (checker false positives:
     exclude utility singletons and `spin_*` nodes).
3. Not run yet: merge main (1f0975c) into this branch, full suite (HEADLESS=1 JOBS=8), re-record
   the saw-affected goldens with this reason, a fight-camera capture of the hero, the
   `docs/look/fitment.html` page, and a saw balance check after the pivot move.
