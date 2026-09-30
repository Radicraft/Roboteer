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

## Session 2 (2026-09-30)

* Merged local main 0317511 into the branch (`f84b222`, no conflicts; the stray `.uid` files and
  the untracked menus capture copies were moved out of the worktree first).
* **Full suite: 47 test files, 0 failures** (HEADLESS=1 JOBS=6), run on the merged branch and again on the final state (after the saw toughness and wedge deck changes), including
  `hazard_determinism` with all six goldens unchanged (c814ec9e2c1a3b19, 948cea0b512e1375,
  fa79709c3fddc315, 29b028f7726a2f2f, 3c8a0a72052ca8cf, 7c37e036b6df6957), `determinism` 42/0
  and `builds` 12/0 (its opponent is a box saw; it asserts behaviour, not hashes).
* **No golden moved, so none was re-recorded.** The only recorded fight hashes are the six
  hazard goldens, whose machines are wedge flippers. Fights WITH a saw or twin saw do change
  (blade position, and the saw's `part_toughness`), but nothing records their hashes.

### Saw balance (weapons gauntlet, 18 fights a weapon: seeds 11-99 x plain ram + hero flipper)

| build | won | vs ram / vs flipper | dmg out | dmg in | blade condition at the end vs ram |
|---|---|---|---|---|---|
| saw, before (main) | 15-3 | 9-0 / 6-3 | 3.60 | 0.89 | 0.4 |
| saw, blade moved out | 10-8 | 3-6 / 7-2 | 2.56 | 1.43 | 0.0 in 6 of 9 |
| saw, slot bite 60 mm / 100 mm (vs ram only) | 4-5 / 4-5 | | 2.26 / 2.55 | | 0.2 |
| saw, part_toughness 1.6 / 2.4 on break thresholds only (vs ram) | 3-6 / 3-6 | | | | 0.1 |
| saw, part_toughness 2.0 / 3.0 incl. direct damage (vs ram) | 7-2 / 7-2 | | 3.61 / 3.55 | | 0.5 / 0.6 |
| **saw, shipped: moved out + part_toughness 2.0** | **15-3** | **8-1 / 7-2** | **3.43** | **0.88** | 0.5 |
| twin saw, before | 13-5 | 9-0 / 4-5 | 2.99 | 0.35 | |
| twin saw, after | 14-4 | 8-1 / 6-3 | 3.63 | 0.67 | |

The exposed blade was being knocked off by the ram's direct-damage blows (ram.gd hands its blow to
whatever part it strikes; a weapon part takes it at factor 1). New catalogue key `part_toughness`
(saw row only, both copies of parts.json): scales the weapon's break thresholds AND divides the
direct damage the weapon part takes (`Bot._build_damage`, `Bot.take_direct_damage`). Absent = 1.0,
so every other weapon is untouched. `saw.gd` reads `slot_bite` from the row too (default 0.02) so
`--tune=saw.slot_bite=` works. Twin saw left alone (noise; it was already the top of the table).

### Wedge deck slots

Moved into the channel between the pods, behind the flipper's gas bottle (x -0.285, z +-0.115,
scale 0.62, seated on the channel floor at y 0.051 via the slot's `seat_percentile` 50). Under a
GENERIC top plate (reactive armour: the flat cassette plate over the whole deck) the slot's
`y_generic_top` (0.219) is used: `seat_utilities.py` now seats per top-plate kind and `Bot._deck_slot`
picks the matching height. Overhang 187 -> 33, floating 0; the parts sit up to 21 mm into the
channel walls on some drives (102 "buried" rows, 42 % max).

### Final numbers (same 4,939 machines, final checker; docs/qa/fitment*.md)

Machines with any finding 4,877 -> 4,361; all findings 46,795 -> 23,940 (half of what is left is
the full body / vortex rings). Wheels through plates 15,077 -> 900; tracks 862 -> 60; deck parts
buried 2,126 -> 102, overhanging 1,634 -> 33, floating 152 -> 0; two utilities in one place
832 -> 44; saw 977 -> 4; twin saw 1,754 -> 108; below the floor 949 -> 47; srimech/skirts buried
304 -> 0.

### Page

`docs/look/fitment.html` (images in `docs/look/fitment/`): owner's two cases, the Tinribs close-up
(menu shop view + fight camera), the summary table, the saw balance table, the owner's-eye list.

## Where I stopped (2026-09-30)

Done: everything above. Open for the owner (on the page): full body / vortex rings through the
machine; bar spinner and drum over the nose; flipper/lifter at full stroke through flat noses (Apex
worst); axe/crusher arm through the box/pyramid front plate at rest; pyramid side plates off its
slopes; scoop vs a front weapon; reactive armour on the wedge is a flat lid.
Known small leftovers, flagged on purpose: scoop's back half inside the nose, rear wedge into the
tail, shell wheels 20-28 mm off the hull, Long and Low flipper tip 21 mm under the floor line at
thickness 1 (signed-off rest angle), axe/crusher posts 6 mm short, wedge deck parts into the
channel walls by up to 21 mm, saw with the scoop on the wedge floats 48 mm (no front plate slot).
Not done: phone check; merging into main (not asked).
