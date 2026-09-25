# Weapons pass notes (weapons engineer, 2026-09-25)

Status: WIP. Balance and AI changes committed; final full gauntlet re-run and
docs/qa/weapons-gauntlet.md "after" table still owed.

## What changed
- Ram (ram.gd, catalogue `damage_per_ms` 0.06, `damage_min_ms` 0.8): every blow now takes
  condition priced on closing speed above 0.8 m/s (once per blow, "impact", capped 0.30).
  AI profile `runup` 1.4: after ~10 ticks in contact it backs off 1.4 m and charges again.
  weapons_b_test checks the pricing and that a bent ram prices nothing.
- AI profile keys (opponent_ai.gd, all optional): `face` (turn nose to them in the clinch;
  axe, ram, lifter, flame), `sensed` (press only when the weapon's own sensor says so;
  lifter forks, flame cone), `runup` (ram), `reserve`/`resume` (flame burst latch),
  `min_range` (napalm lobs only where the shell lands; standoff 1.6, engage 1.2).
  Axe bug was the drive reversing tail first into the foe (dot -0.98), not the range.
- Flamethrower: `fuel_regen` 0.25 s/s after 1 s off; opponent_on_wedge = something in cone;
  visible flame 1.45x reach, girth 1.5.
- Napalm: `reload_s` 15, one shell back into the rack while below the starting rack.
- Twin saw: the arbor's whole dps goes to whichever discs are biting (was dps/blades each).
  On a Box it goes 6-3 and out-damages the saw; on the harness's Wedge it is held back by
  the wedge stall (combat engineer).
- Lifter: ForkArm body notes foreign contacts in the step; opponent_on_wedge() for the AI.
  (A sensor Area on the arm changed the lift physics: weapons_test lifter failed, so no.)
  Still 0 lifts until the combat engineer's self-flip fix lands.
- Horizontal spinner: impulse 180->115, spin_up 2.5->4.2, self_destabilise 0.6->0.9.
- Vortex: impulse 250->140, lift 0.45->0.2, spin_up 3.2->3.8, control_penalty 0.55->0.5.
  Both stay inside "2-3 clean hits a part" on steel 1/2 (cap 0.5 per bite).
- Tesla arc: decision = stall/points weapon by design, no damage change (see gauntlet doc).
- FX (weapon_fx.gd, flame_cone.gd, committed 8094748): blue arc burn, violet prod, ram blow
  dust+sparks+ram_crush, lifter clunk+amber light, spinner blur disc+rim, fatter flame.

## Where I stopped (2026-09-25, weekly limit)
Committed: 8094748 (fx), c4e7e5a (WIP balance/AI), acf0479 (final spinner numbers:
horizontal 120 N s / 2.6 s / destabilise 1.0; vortex 110 N s / 4.5 s / control 0.4;
builds_test ram check vs spinner only). Tests on HEAD: weapons_test, weapons_a, weapons_b,
weapons_p, builds, parts_p, ai, fx all pass (lifter test passes with the combat engineer's
uncommitted lifter hold-down edit in the tree too). The horizontal spinner spin-up must stay
near 2.5 s: weapons_a's lurch check spins for 160 ticks and needs the bar above the 0.6
destabilise gate at first contact. A full "after" gauntlet was running in the worktree
/Volumes/RoboteerBuild2/Code/wx-head (scratch results in the session scratchpad); if it was lost:
## Next steps
1. Re-run the gauntlet on HEAD (all 16, seeds 11,22,33, opps plain,w:flipper,w:horizontal_spinner).
   The tree moved a lot today (new wedge, wheel sink), so also re-run a "before" with
   c4e7e5a^ weapon files for a like-for-like comparison.
2. Add the "after" table to docs/qa/weapons-gauntlet.md; recapture frames for arc, prod,
   ram, lifter, horizontal spinner, vortex, full body spinner, flamethrower.
3. Lifter: still 0 lifts pending the combat engineer's self-flip fix; the AI side
   (`face` + `sensed` via ForkArm contacts) is in.
Note: the "plain" opponent is a box ram, so it now does real damage (2-3 a fight);
before/after rows against "plain" are not like for like.
