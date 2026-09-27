# Weapons pass notes (weapons engineer, 2026-09-25; second pass 2026-09-27)

Status: 2026-09-27 pass committed; see "Where I stopped" at the end. The "What changed"
list below is the 2026-09-25 pass; several of its numbers were changed again on 09-27.

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

## Where I stopped (2026-09-27)

Commits today: 8a979cb (weapons_a lurch check), 900f15e (balance + three test fixes), 6c038c9
(flipper end-on lift), 9f8fb32 (shop Hit pips), a9e0e79 (contact sheet frames), and the docs
commit with this file. Nothing pushed. Tree tests green on HEAD: weapons_test, weapons_a, _b,
_p, builds, parts_p, ai, fx, ui, physics, determinism, pause, bridge, hitstop.

Done:
1. weapons_a "spinner lurches its own chassis": the check read the peak over 4 s, which the bar
   knocking the wall set (8 rad/s a tick with or without the reaction). It now reads the 0.25 s
   after the first bite: 5.5 with the reaction, 2.0 without. The reaction was always there.
2. Balance (900f15e): bar 100 N s / 3.6 s / destabilise 1.4 / bite cost 0.80; drum 75 N s /
   launch 0.6 / 2.4 s / bite cost 0.50 / cooldown 0.30 s; vortex 85 N s / control 0.35; twin saw
   dps 0.065. Tuning aids: `bite_spin_cost` (all three spinners), `bite_cooldown_s` and
   `max_omega` (drum), `end_on_lift` (flipper) catalogue overrides; gauntlet `--tune=` and
   `--subject-skill=`.
3. Flipper (6c038c9, the hull engineer's item 2): 0.7 of the lift on a machine caught end on
   (|cos|^4 blend). Head-on flips of the hero 79 % -> 35 % of clean throws, flank 64 %.
4. builds_test ram check (the hull engineer's item): ram.gd reports its blows' momentum
   (`blow_impulse_total`), builds_test adds it (a ram blow's damage_event carries impulse 0).
   weapons_p twin-saw check reads the shared-arbor model. hitstop_test (combat's file, one
   hunk): same-tick events compare as a set (two wheels landing on one tick swapped order in
   the 0.25x replay once the drum fixture fight had 17 events instead of 1).
5. Gauntlet 2026-09-27 table + even-tier run + raw rows in docs/qa/weapons-gauntlet.md.
6. Contact sheet: arc, prod, ram, lifter, bar, vortex, FBS, flame recaptured on 6c038c9
   (windowed `qa/weapons_capture.tscn`, lifter on seed 33: seed 11 never lifts in 45 s).
7. Shop Hit pips = catalogue `damage_per_fight` (mean dmg_out over the 18 fights of 09-27);
   `CareerEngine.power` keeps the impulse pip (`powerHitPips`). Flipper shows 1 pip now.

Not reached / open:
- "No weapon over ~65 %" is not measurable in this harness: the subject (brawler) beats the
  technician opponent 59 to 79 % of all fights whatever the weapon. Twin saw and FBS are the
  consistent top (17-1 each on seeds 44-99) and did not respond to any number tried (see the
  gauntlet doc). Next step for real balance numbers: give the harness `--subject-temperament=`
  (technician both sides) or run weapon-vs-weapon round robins, 6 seeds, then retune twin saw
  and FBS. The bar is still the strongest OPPONENT (58 of 96 on the lower tier).
- Direct damage on a chassis body always lands on the top plate (`Bot.take_direct_damage`);
  finding for combat in the gauntlet doc. An opt-in face mapping was measured and reverted.
- Weak: flamethrower (11 %), ram (28 %).
- Goldens NOT re-recorded. hazard_determinism (6 arenas) already fails from the hull; the
  flipper end-on lift (6c038c9) and the drum / bar numbers (900f15e) move any golden whose
  fixture has a flipper throwing an end-on machine or a spinner (hitstop's drum fixture moved:
  17 events, was 1; it self-compares, so it stays green). Re-record from 6c038c9 or later.
- The white-out bloom still covers most hits in the new frames (bar, FBS, vortex, ram, arc).
- Worktree /Volumes/RoboteerBuild2/Code/wx-weap was removed at the end.
