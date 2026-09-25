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

## Next steps
1. Run weapons_test, weapons_a/b/p_test, builds_test, parts_p_test, ai_test, fx_test in the
   repo; weapons_a "horizontal spinner hit lurches its own chassis" failed at impulse 130
   (4.155 vs 3.791) - check at 115 / destabilise 0.9.
2. Targeted gauntlet re-run of changed weapons (scratch runner: one godot per weapon,
   `--seeds=11,22,33 --opps=plain,w:flipper,w:horizontal_spinner --secs=150`).
3. Add the "after" table to docs/qa/weapons-gauntlet.md; recapture frames.
Note: the "plain" opponent is a box ram, so it now does real damage (2-3 a fight);
before/after rows against "plain" are not like for like.
