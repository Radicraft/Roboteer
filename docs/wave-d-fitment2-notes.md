# Wave D fitment pass 2 notes (branch `wave-d-fitment2`)

Brief: implement decisions 2026-09-30 §9 (docs/aaa/decisions-2026-09-30.md), visual only
wherever possible, flag every collider move. Base: main 616b881, main merged twice since
(24c5741, the fight.gd duplicate-function fix). Harness: wave C's `Arena/qa/fitment_dump.gd`
+ `Tools/fitment/fitment_check.py`, same 4,939 machines. Page: `docs/look/fitment.html`
"Pass 2" section (images `docs/look/fitment/pass2/`). Table: `docs/qa/fitment-pass2.md`.

## Per call

1. **Rings (full body, vortex)**: drawn BIGGER, never raised. `Bot._fit_ring` measures
   everything the machine draws inside the ring's height band (hull, drive, deck parts, the
   srimech, and the armour on a hull that keeps its bodywork) and pushes every vertex of
   the ring model out along its radius until the bore clears all of it by 12 mm. The
   vortex's spider (arms + hub inside r 0.2) is dropped as whole connected pieces (a
   triangle-level drop left open shells that the voxel checker filled). On the Shell and
   the Apex (hulls that hand their bodywork to the ring) the plates are narrowed into the
   bore instead; the scoop, rear wedge and skirts are pulled into it. Two static roller
   brackets fore and aft (`WeaponSupport` bars) carry the ring from the hull, 2 mm inside
   its bore. A raised ring was rejected: wheels reach 0.11 m above the axle plane, so a
   ring clear of them works 0.12 m above its collider.
   **PHYSICS (flagged)**: (a) `ChassisBase.weapon_socket("shell")` on a hull with no shell
   socket returns the hull centre (was the front socket: a box's vortex collider was a disc
   centred on the NOSE while the ring was drawn round the middle; the Apex's 0.425 m
   apart); (b) the ring's collision disc grows with the drawn ring (radius 0.64 on the
   Shell, 0.66 box, 0.72 pyramid, up to 0.83 on the Long and Low; was 0.45 / 0.48). The
   catalogue `reach` (shop number, AI approach distance) is NOT changed (tests assert it).
   Moves every fight with a full body spinner or a vortex.
2. **Drum**: carried forward on its forks until its drawn teeth clear the drawn nose and
   front plate by 8 mm, at the floor (`vertical_spinner.gd _clear_the_nose`). Raising it
   was measured: 0.15 to 0.40 m of lift. **PHYSICS (flagged)**: every drum fight (the drum
   stands 0.13 to 0.22 m further out).
   **Bar spinner: NOT changed, on evidence.** Clearing the nose needs 0.22-0.26 m of lift on
   box/pyramid/apex/wedge and 0.43 m on the Tall Tank (underside 0.33-0.53 m off the
   floor). Gauntlet, box bar raised 0.26 m (`--tune=horizontal_spinner.fit_lift=0.26`, a
   measuring aid left in, absent = 0): 13-5 vs 14-4 but half the damage (2.57 vs 4.53),
   and it would miss low machines outright. Shortening cannot clear either. Needs a design
   call (a bar on a mast ahead of the nose, or accept it).
3. **Flippers and lifters on flat noses**: `DrawnHinge` (Arena/bot/drawn_hinge.gd), a
   presentation node like AxeWindup: the arm MODEL turns about a drawn hinge in front of
   the nose (the shift solved per hull so the drawn arm clears the drawn hull and front
   plate over the whole stroke) by exactly the angle the physics arm has turned. A limited
   stroke was measured and does not help (the Box's arm meets its plate in the first 4
   degrees). The lifter's screw actuator is split off the forks (`mount` node in
   lifter.glb, hung on the chassis). Physics untouched. The dump writes the drawn hinge
   (`draw_pivot` on the joint row) and the checker sweeps about it.
4. **Axe and crusher**: towers split into a `mount` node in the .glb (axe: tower, pin,
   spring; crusher: tower, pin, anvil bed, ram cylinder) and stood upright on the deck under
   the hinge; stretched down onto the deck when their foot is up to 30 mm clear; posts
   (overlapping the tower's cheeks) where it is further. The FRONT plate is drawn with a
   notch under the crusher's bed (`_notch_boxes`, front panel only). Physics untouched.
5. **Pyramid side plates**: `plate_pyramid_sides[_hdpe|_reactive].glb`, tiles cut to the
   hexagonal flank in two bands either side of the axle bosses, seven columns, each its own
   `seg_*` node; `Bot._clear_plate_tiles` hides the tiles a wheel or track stands over; the
   left flank's model is mirrored (scale z -1) so tiles pair with the right's. On 6wd and
   tracks the wheels cover the whole flank and no tile shows. Visual only.
6. **Scoop plus a front weapon**: `Bot._fit_scoop_under_weapon` scales the scoop about the
   middle of its back edge on the floor, lower first, narrower second, shorter last, until
   no sampled point of it (surface samples every 10 mm) comes within 10 mm of the weapon's
   drawn stroke (a solid of revolution per hinge, from surface samples; static mounts as
   they stand). Where nothing fits (the Long and Low flipper) the drawn scoop is left out;
   the plate's box is still its collision. Visual only.
7. **Wedge reactive plate**: `plate_wedge_top_reactive.glb`, the steel lid's pods with
   twelve cassettes on the pod facets in place of the upper pressing (14.1k tris, budget
   14.5k). `_fitted_plate_id` takes `<chassis>_<face>_reactive` when a model exists.
   Visual only.

## Balance (weapons gauntlet, 18 fights a build, seeds 11-99, plain ram + weapon foe)

| build | before | after, no retune | shipped |
|---|---|---|---|
| drum, wedge | 15-3 | 9-9 | 12-6 (part_toughness 2.0) |
| drum, box | 15-3 | 12-6 | 16-2 (2.0) |
| full body spinner, shell | 16-2 | 15-3 | 15-3 |
| vortex, shell | 16-2 | 13-5 | 17-1 (1.5) |
| vortex, apex | 5-13 | 2-16 | 10-8 (1.5) |

`part_toughness` added to vertical_spinner (2.0) and vortex_spinner (1.5), both parts.json
copies. (Gauntlets ran on the pass 2 code before the main merges; the ring's collider has
not changed since.)

## Fitment check, before / after (same 4,939 machines, same checker)

| call (findings in its categories) | before | after |
|---|---|---|
| 1 rings through hull, wheels, plates, deck parts | 5,021 | 18 (scoop touching the ring: Shell on legs, wedge vortex) |
| 2 drum through nose / plate | 735 | 0 |
| 2 bar spinner over nose / deck | 1,044 | 997 (not changed, see above) |
| 3 flipper / lifter through a flat nose | 1,182 (Apex 208) | 0 |
| 4 axe / crusher through plate, deck, hull (rest + swing) | 4,058 (at rest 1,458) | 0 |
| 5 pyramid side plates off the slopes | 3,238 | 0 |
| 6 scoop against the front weapon | 748 | 18 |
| 7 wedge reactive lid floating | 4 | 0 |
| all findings / machines with any | 23,940 / 4,361 | 8,476 / 2,519 |

Went UP (explained, flagged on the page): Shell front wheels "floating" +332 (the plates
narrowed into the bore no longer sit near them; wave C already noted the Shell's wheels
stand off its hub), scoop / rear wedge pulled into the Shell's bore partly inside the hub
+116. Everything else went down. Table: docs/qa/fitment-pass2.md.

## Tests

Full suite `HEADLESS=1 JOBS=6 scripts/test-arena.sh` on the branch after merging main
3a3b23a: **51 test files, 0 failures**. determinism 42/0. hazard_determinism 16/0 with
every golden equal to main's (yard c814ec9e2c1a3b19, grinder 948cea0b512e1375, furnace
fa79709c3fddc315, crush 29b028f7726a2f2f, drop_zone ba6a58ff2e2a9c78 = main's pin-rule
re-record, 3c8a0a72052ca8cf with the rule off, coliseum 7c37e036b6df6957): no golden
moved here (those fixtures are wedge flippers; a ramped nose keeps its drawing and physics).
boost_test's reference fight (a box drum spiral) had no damage events once the drum moved
out; per its own comment BOOST_EVERY was re-picked (200 -> 175, 2 events). Hashes that DO
move (nothing records them): every fight with a drum, a full body spinner or a vortex.

## Where I stopped (2026-10-01, coordinator's three calls in progress)

Built and committed: bar spinner forward mount (overhead boom, part_toughness 1.5), ring
collision capped at 0.72 m (inner furniture dropped, the machine shortened inside the band
where it would need more), Shell fixes (axle stubs, scoop and rear wedge pulled in about
their inner end). Still to do: merge main, re-dump and re-check, page and notes, full suite.
