# Wave D fitment pass 2 notes (branch `wave-d-fitment2`)

Brief: implement decisions 2026-09-30 §9 (docs/aaa/decisions-2026-09-30.md), visual only
wherever possible, flag every collider move. Base: main 616b881. Harness: wave C's
`Arena/qa/fitment_dump.gd` + `Tools/fitment/fitment_check.py` (same 4,939 machines).

## Per call

1. **Rings (full body, vortex)**: drawn BIGGER, never raised. `Bot._fit_ring` measures
   everything the machine draws inside the ring's height band (hull, drive, deck parts, the
   srimech, and the armour on a hull that keeps its bodywork) and pushes every vertex of
   the ring model out along its radius until the bore clears all of it by 12 mm. The
   vortex's spider (arms + hub inside r 0.2) is dropped as whole pieces (the hull fills
   the bore now). On the Shell and the Apex (hulls that hand their bodywork to the ring)
   the plates are narrowed into the bore instead; the scoop, rear wedge and skirts are
   pulled into it. A raised ring was rejected: wheels reach 0.11 m above the axle plane,
   so a ring clear of them works 0.12 m above its collider.
   **PHYSICS**: (a) `ChassisBase.weapon_socket("shell")` on a hull with no shell socket
   now returns the hull centre (was the front socket: a box's vortex collider was a disc
   centred on the NOSE while the drawn ring orbited through the machine); (b) the ring's
   collision disc grows with the drawn ring and `spec.reach` with it (a blow lands where
   the teeth are drawn). Moves every fight with a full body spinner or a vortex.
2. **Bar spinner and drum**: drum carried forward on its forks until its drawn teeth
   clear the drawn nose and front plate by 8 mm, at the floor (`vertical_spinner.gd
   _clear_the_nose`). Raising it was measured: 0.15 to 0.40 m of lift, not a drum any more.
   **PHYSICS**: moves every drum fight (the drum stands 0.13 to 0.22 m further out).
   Bar spinner: NOT changed yet (see Where I stopped).
3. **Flippers and lifters on flat noses**: `DrawnHinge` (Arena/bot/drawn_hinge.gd), a
   presentation node like AxeWindup: the arm MODEL turns about a drawn hinge standing in
   front of the nose (the shift is solved per hull so the drawn arm clears the drawn hull
   and the front plate over the whole stroke), by exactly the angle the physics arm has
   turned. A limited stroke was measured and does not help (the Box's arm meets its plate
   in the first 4 degrees). The lifter's screw actuator is split off the forks (`mount`
   node in lifter.glb, hung on the chassis). Physics untouched. The dump writes the drawn
   hinge (`draw_pivot`) and the checker sweeps about it.
4. **Axe and crusher**: their towers (axe: tower, pin, spring; crusher: tower, pin, anvil
   bed, ram foot) are split into a `mount` node in the .glb and stood upright on the deck
   under the hinge (they used to lean with the arm through the front plate and the deck).
   The front plate is drawn with a notch under the crusher's bed. Posts carry the tower
   down to the deck where its foot is clear of it. Physics untouched.
5. **Pyramid side plates**: `plate_pyramid_sides[_hdpe|_reactive].glb`, tiles cut to the
   pyramid's hexagonal flank in two bands either side of the axle bosses, seven columns;
   `Bot._clear_plate_tiles` hides the tiles a wheel or track stands over. Visual only.
6. **Scoop plus a front weapon**: `Bot._fit_scoop_under_weapon` scales the scoop about the
   middle of its back edge on the floor, lower first, narrower second, shorter last, until
   no point of it comes within 10 mm of the weapon's drawn stroke (solid of revolution per
   hinge; static mounts as they stand). Where nothing fits (the Long and Low flipper, whose
   tip rests on the floor line) the drawn scoop is left out; the plate's box is still the
   scoop's collision. Visual only.
7. **Wedge reactive plate**: `plate_wedge_top_reactive.glb`, the steel lid's pods with
   twelve reactive cassettes on the pod facets in place of the upper pressing (14.1k tris,
   budget 14.5k). `_fitted_plate_id` now takes `<chassis>_<face>_reactive` when a model
   exists. Visual only.

## Balance (weapons gauntlet, 18 fights a weapon, seeds 11-99, plain ram + weapon foe)

| build | before | after, no retune | after + part_toughness (shipped) |
|---|---|---|---|
| drum, wedge | 15-3 | 9-9 | 12-6 (2.0) |
| drum, box | 15-3 | 12-6 | 16-2 (2.0) |
| full body spinner, shell | 16-2 | 15-3 | (unchanged) |
| vortex, shell | 16-2 | 13-5 | 17-1 (1.5) |
| vortex, apex | 5-13 | 2-16 | 10-8 (1.5) |

The drum out in front took the ram's blows the hull used to (the saw's wave C story).
`part_toughness` added to the vertical_spinner (2.0) and vortex_spinner (1.5) rows in both
parts.json copies.

## Where I stopped

WIP (2026-09-30, after the usage-limit restart): calls 1, 2 (drum), 3, 4, 5, 6, 7 built
and rendered; bar spinner not done; main not merged; full suite not run; page not written.
