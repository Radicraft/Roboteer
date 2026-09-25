# Weapons gauntlet

2026-09-25, weapons QA lead. The owner asked: "have you tested the different weapons on the
robots yet? I'm just seeing flippers." Until today, no: every weapon had headless unit tests,
but nobody had watched each one fight, and every capture used the wedge + flipper hero. This
file is that test: all 16 weapons, 144 real AI fights, plus frames of each one firing.

Visual contact sheet: `docs/look/weapons-gauntlet.html` (frames in `docs/look/weapons/`).

## How it was run

- Harness: `Arena/qa/weapons_gauntlet.gd` (headless, not part of the suite). Reproduce any row:

      Godot --headless --fixed-fps 60 --path Arena --script qa/weapons_gauntlet.gd -- \
          --weapons=<id> --seeds=<n> --opps=plain|w:flipper|w:horizontal_spinner --secs=150 \
          [--hull=<chassis>] [--drive=<drive>] [--trace=30] [--out=file.jsonl]

  `--trace=N` prints position, speed, AI input, readiness, KO count, AI intent, wheel spin and
  what the chassis touches every N ticks.
- Each weapon goes on the first legal machine from a fixed hull list (4wd, heaviest armour that
  passes `BuildRules`), as bots[0] with `debug.player_ai = normal`, `ai_skill national`,
  `temperament brawler`, so the player side genuinely attacks.
- Three opponents, three seeds each (11, 22, 33), the Yard, 150 s, KO count 10 s:
  **plain** = box / 4wd / ram / steel 2 (no moving weapon); **w:flipper** = the hero wedge / 4wd /
  flipper; **w:horizontal_spinner** = box / 4wd / bar spinner. Opponents drive `regional`,
  `technician`.
- Per fight: `weapon_fired` count and how many landed (foe damaged or thrown within 0.6 s), blows
  (damage events more than 0.25 s apart), condition removed and taken, parts knocked off, throws
  (foe chassis crossing 0.45 m), inversions both ways, seconds stalled (speed under 0.05 m/s with
  the foe over 1.5 m away), weapon jammed at the end, and every one-shot sound and loop the mixer
  started for the subject (numeric only; no audio was played).
- Build snapshot: working tree on top of `8e46e53` with the other agents' uncommitted work in
  place (the combat engineer's `opponent_ai.gd`, the kit lead's Yard). Numbers can move when those land.

Note on "fires": for the spinner family, saws, drill, arc, prod and napalm, `weapon_fired` means
"reached speed" or "discharged", not "swung". The crusher, lifter and ram never emit it by
design (so 0 there is expected). Continuous weapons (saw, crusher, drill, flame) are judged on
blows and damage, not fires.

## Verdicts

| weapon | verdict | one line of evidence |
|---|---|---|
| horizontal_spinner | **OVERPOWERED** | 8-1 as the subject; as the OPPONENT (weaker AI tier) only 12 of 48 subjects beat it, and most that lost ended with their own weapon jammed |
| vertical_spinner | **BROKEN on the wedge** (strong on box/pyramid) | wedge: 2-7, stalls dead with wheels spinning (bug 1), KO'd at 14 to 33 s; the same drum on a box went 5-1 and on a pyramid 4-2 |
| flipper | **WORKS** | 9.7 throws a fight, 55 % of fires lift the foe, ring-out in 15 s; 0 damage by design; loses the mirror |
| lifter | **BROKEN** | 1-8, 0.14 condition removed, lifts almost nothing (0.4 throws), turned over 36 times a fight by its own srimech loop (bug 4) |
| crusher | **WORKS** | 6-3, 5 kills, steady 2.6 condition a fight; clamp sound on every grip |
| axe | **WEAK** | 3-6; AI never swings in a nose-to-nose shove (bug 3), 0 presses in 145 s of contact |
| saw | **WORKS** | 6-3, 22 blows and 2.4 condition a fight; loses to the bar spinner only |
| ram | **BROKEN** | 0 damage in 9 fights, 8 losses, 7 by KO; stalls in place from about 2 s (bug 1) |
| flamethrower | **WEAK** | 2-7, never a stoppage win, 1.0 condition a fight; 20 s of fuel is gone in the first minute |
| full_body_spinner | **WORKS** (strong) | 7-2, 6 stoppages, 4.1 condition a fight, 2 parts off |
| shock_prod | **BROKEN** | 0-9, 0.9 zaps a fight, stalled 13 s a fight (bug 1 on the wedge) |
| tesla_arc | **WORKS** (low damage) | 4-5, 15 of 19 discharges land, but 0.09 a hit: never removes a part, wins on points only |
| drill_lance | **WORKS** | 5-4, 4 stoppages, 3.0 condition a fight; loses one fight it was winning to bug 2 |
| twin_saw | **WEAK** | 4-5, 1.5 condition a fight: less than the cheaper single saw (2.4) it outranks on the ladder |
| napalm_cannon | **WEAK** | 4-5, 5 shells then empty for the rest of the fight; 0.02 to 0.26 condition against the ram |
| vortex_spinner | **OVERPOWERED** | 9-0, 7 stoppages, ring-outs at 4.4 s, 5.8 s, 11 s; one bite throws a machine out of the arena |

## The gauntlet: 9 fights per weapon (3 opponents x 3 seeds)

| weapon | machine | W-L (KO/ring-out/kill wins) | mean end s | fires (landed) | blows | dmg out | dmg in | parts off foe | throws | foe inverted | self inverted | stuck s | jammed | weapon sound/fx seen |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| horizontal_spinner | box/4wd/steel1 | 8-1 (2) | 141 | 8.9 (1.3) | 9.1 | 3.78 | 0.50 | 1.7 | 0.0 | 0.0 | 3.3 | 5.2 | 2/9 | loop weapon 107.8 |
| vertical_spinner | wedge/4wd/steel1 | 2-7 (1) | 49 | 1.9 (0.0) | 3.6 | 1.43 | 0.37 | 0.6 | 5.1 | 5.6 | 0.0 | 11.6 | 0/9 | loop weapon 46.3 |
| flipper | wedge/4wd/steel2 | 4-5 (1) | 117 | 10.2 (5.6) | 0.2 | 0.05 | 1.41 | 0.1 | 9.7 | 7.3 | 9.2 | 6.5 | 2/9 | flipper_fire 14.4 |
| lifter | wedge/4wd/steel2 | 1-8 (1) | 102 | 0.0 (0.0) | 0.8 | 0.14 | 1.90 | 0.0 | 0.4 | 0.4 | 36.1 | 6.1 | 2/9 | none |
| crusher | box/4wd/steel1 | 6-3 (5) | 98 | 0.0 (0.0) | 4.6 | 2.61 | 0.25 | 1.7 | 0.0 | 0.0 | 15.9 | 0.2 | 0/9 | crusher_clamp 3.0 |
| axe | box/4wd/steel1 | 3-6 (3) | 74 | 7.0 (3.7) | 4.6 | 1.21 | 1.24 | 0.6 | 0.0 | 0.0 | 8.3 | 3.8 | 0/9 | axe_swing 7.0, axe_hit 4.6 |
| saw | box/4wd/steel2 | 6-3 (1) | 113 | 3.6 (0.1) | 21.9 | 2.40 | 1.47 | 1.0 | 0.0 | 0.0 | 3.3 | 1.1 | 2/9 | loop weapon 103.3 |
| ram | wedge/4wd/steel2 | 1-8 (1) | 61 | 0.0 (0.0) | 0.0 | 0.00 | 0.11 | 0.0 | 0.0 | 0.0 | 2.2 | 9.2 | 1/9 | none |
| flamethrower | box/4wd/steel2 | 2-7 (0) | 115 | 0.0 (0.0) | 9.1 | 0.98 | 1.82 | 0.0 | 0.0 | 0.0 | 4.1 | 1.4 | 3/9 | loop weapon 25.5 |
| full_body_spinner | shell/4wd/hdpe1 | 7-2 (6) | 94 | 2.8 (0.3) | 10.4 | 4.08 | 0.96 | 2.0 | 0.1 | 0.0 | 0.0 | 0.6 | 3/9 | loop weapon 64.3 |
| shock_prod | wedge/4wd/steel2 | 0-9 (0) | 87 | 0.9 (0.9) | 1.3 | 0.15 | 1.14 | 0.1 | 0.0 | 0.0 | 13.3 | 13.1 | 2/9 | prod_zap 0.9 |
| tesla_arc | box/4wd/steel2 | 4-5 (0) | 115 | 18.6 (15.2) | 15.6 | 1.36 | 1.98 | 0.0 | 0.0 | 0.0 | 9.4 | 2.3 | 3/9 | loop wp:arc 55.4, arc_discharge 18.6 |
| drill_lance | box/4wd/steel1 | 5-4 (4) | 91 | 2.7 (0.3) | 13.9 | 2.98 | 1.85 | 1.1 | 0.0 | 0.0 | 2.6 | 1.8 | 3/9 | loop wp:drill 73.1 |
| twin_saw | wedge/4wd/steel1 | 4-5 (1) | 113 | 2.7 (0.2) | 16.8 | 1.51 | 1.43 | 0.6 | 0.0 | 0.0 | 4.3 | 1.2 | 2/9 | loop wp:saw 215.0 |
| napalm_cannon | box/4wd/steel1 | 4-5 (2) | 116 | 5.0 (2.7) | 2.3 | 1.74 | 1.02 | 0.3 | 0.1 | 0.0 | 1.7 | 1.4 | 0/9 | loop wp:patch 30.1, napalm_launch 5.0 |
| vortex_spinner | shell/4wd/hdpe1 | 9-0 (7) | 56 | 1.0 (0.1) | 2.6 | 1.32 | 0.28 | 0.2 | 12.6 | 10.1 | 0.0 | 1.8 | 2/9 | loop wp:vortex 40.7, vortex_throw 0.2 |

Per opponent, subject wins out of 3:
| weapon | vs box ram | vs wedge flipper | vs box horizontal spinner |
|---|---|---|---|
| horizontal_spinner | 3/3 (W judges 150s, W judges 150s, W judges 150s) | 3/3 (W kill 120s, W judges 150s, W judges 150s) | 2/3 (W judges 150s, W kill 95s, L judges 150s) |
| vertical_spinner | 2/3 (L ko 68s, W judges 150s, W kill 25s) | 0/3 (L ko 14s, L ko 18s, L ko 27s) | 0/3 (L ko 85s, L ko 22s, L ko 33s) |
| flipper | 3/3 (W ring-out 15s, W judges 150s, W judges 150s) | 0/3 (L judges 150s, L judges 150s, L judges 150s) | 1/3 (L ko 39s, W judges 150s, L kill 96s) |
| lifter | 1/3 (W ring-out 84s, L ring-out 35s, L judges 150s) | 0/3 (L judges 150s, L judges 150s, L judges 150s) | 0/3 (L kill 96s, L ring-out 60s, L kill 42s) |
| crusher | 3/3 (W kill 99s, W kill 130s, W kill 110s) | 2/3 (L judges 150s, W judges 150s, W kill 106s) | 1/3 (W kill 95s, L kill 20s, L kill 19s) |
| axe | 2/3 (W kill 29s, L judges 150s, W kill 20s) | 1/3 (L kill 57s, W kill 139s, L ko 46s) | 0/3 (L ko 46s, L kill 33s, L judges 150s) |
| saw | 3/3 (W judges 150s, W judges 150s, W judges 150s) | 3/3 (W judges 150s, W judges 150s, W kill 99s) | 0/3 (L kill 39s, L kill 32s, L kill 95s) |
| ram | 0/3 (L ko 29s, L ko 64s, L ko 42s) | 0/3 (L ko 12s, L judges 150s, L ko 62s) | 1/3 (W ko 25s, L judges 150s, L ko 14s) |
| flamethrower | 1/3 (L judges 150s, L judges 150s, W judges 150s) | 1/3 (W judges 150s, L judges 150s, L judges 150s) | 0/3 (L kill 37s, L kill 43s, L kill 53s) |
| full_body_spinner | 1/3 (L judges 150s, L judges 150s, W kill 134s) | 3/3 (W kill 43s, W ko 44s, W kill 82s) | 3/3 (W kill 33s, W kill 60s, W judges 150s) |
| shock_prod | 0/3 (L ko 80s, L ko 59s, L ko 77s) | 0/3 (L judges 150s, L judges 150s, L judges 150s) | 0/3 (L ko 13s, L kill 70s, L kill 37s) |
| tesla_arc | 3/3 (W judges 150s, W judges 150s, W judges 150s) | 1/3 (W judges 150s, L kill 84s, L kill 132s) | 0/3 (L kill 90s, L kill 64s, L kill 67s) |
| drill_lance | 2/3 (L ko 44s, W kill 86s, W kill 59s) | 3/3 (W kill 92s, W judges 150s, W kill 122s) | 0/3 (L kill 131s, L kill 49s, L kill 89s) |
| twin_saw | 2/3 (L ko 71s, W judges 150s, W judges 150s) | 2/3 (L judges 150s, W ko 137s, W judges 150s) | 0/3 (L kill 23s, L kill 50s, L kill 139s) |
| napalm_cannon | 1/3 (L judges 150s, L judges 150s, W ko 141s) | 2/3 (W judges 150s, L judges 150s, W judges 150s) | 1/3 (L kill 41s, W ko 35s, L kill 76s) |
| vortex_spinner | 3/3 (W ring-out 22s, W ring-out 4s, W ring-out 14s) | 3/3 (W ring-out 25s, W judges 150s, W ko 121s) | 3/3 (W judges 150s, W ring-out 6s, W ring-out 11s) |


"stuck s" is seconds a fight at under 0.05 m/s with the foe more than 1.5 m away. "self
inverted" counts the subject landing upside down for any reason (a flipper opponent does
most of it; the lifter does it to itself). "weapon sound/fx seen" is the average a fight of the
subject's own weapon one-shots and seconds of weapon loop that the mixer started.

### Second hull for the three wedge-stall weapons (box / 4wd, same opponents and seeds)

| weapon | wins | condition removed a fight | stuck s a fight | notes |
|---|---|---|---|---|
| ram | 0 of 9 | 0.05 | 1.4 | no stall, still no damage (bug 3) |
| shock_prod | 4 of 9 | 1.41 | 3.4 | 18 to 28 zaps a fight against the flipper, all three won |
| lifter | 2 of 9 | 0.21 | 11.4 | 0 lifts of the ram, still turned over 0 to 20 times |
| vertical_spinner (box) | 5 of 6 | 3.95 | 4.8 | against the flipper and the spinner only; pyramid 4 of 6 |

## Bugs, ranked by severity

Every repro below is the harness command with the named flags; `tick` is the fight's physics tick
(60 a second) from `--trace`.

### 1. HIGH: machines with a heavy front weapon on the Wedge stall dead on open floor

`--weapons=ram --opps=w:flipper --seeds=11 --trace=30` (wedge / 4wd / ram / steel 2). From tick
~120 (2.0 s) the machine sits at (-1.55, -2.23), 4.6 m from the opponent, AI asking for full
drive, all four wheels spinning at 24 to 28 rad/s (about 2.7 m/s of tread speed) and the chassis
moving at 0.00 to 0.02 m/s. Upright (`basis.y . UP` 1.00), every wheel reports floor contact, the
chassis body also reports contact with `Floor`. It is counted out: KO at 12.2 s without being
touched. Same pattern, vertical spinner: `--weapons=vertical_spinner --opps=w:flipper --seeds=22`,
stalled from tick ~200 at (1.42, -0.97), KO 18.5 s, 0 damage taken.

- Affects the wedge builds only: vertical spinner (stalled 11.6 s a fight, 7 of 9 lost, 6 by KO),
  ram (8 of 9 lost, 7 by KO), shock prod (13.1 s stalled a fight, 0 of 9). Flipper, lifter and
  twin saw on the same wedge stall less (1 to 6 s a fight).
- The same weapons on a Box do not stall: vertical spinner box 5-1 and pyramid 4-2 (against 0-6
  on the wedge versus weapon opponents), shock prod box 4-5 (against 0-9), ram box stalled 0 to
  4.6 s.
- Reading of it (not verified in code): wheel centres sit at y 0.07 to 0.09 with a 0.11 m wheel
  radius and the wedge hull always touches the floor; with a heavy nose load the hull's friction
  beats the wheels' traction once the machine slows down. This is the owner's "I'm just seeing
  flippers" in another form: three weapons on the starter hull cannot reach the fight.

### 2. HIGH: the knockout count runs on a machine that is latched on and attacking

`--weapons=drill_lance --opps=plain --seeds=11 --trace=60` (box / 4wd / drill / steel 1). From
tick 2033 (33.9 s) the drill has the ram pinned against the wall, AI at full throttle with fire
held, the two chassis 1.04 to 1.06 m apart. `Rules.is_pinned` needs 1.0 m or less
(`PIN_RANGE_M`), so the drill's own KO count runs and it LOSES by KO at 43.5 s while winning.
The lance, a saw or a prod holds the two hulls further apart than 1.0 m. Seen in: drill (1 loss),
twin saw (`--weapons=twin_saw --opps=plain --seeds=11`, KO at 71.3 s, 0 damage taken), shock prod
on box vs ram (KO at 143.9 s). Fix is a rule change (range, or "touching its opponent" instead of
centre distance), for the combat engineer.

### 3. HIGH: the Ram does no damage at all

Ram subject, 18 fights (9 on the wedge, 9 on a box): 0.00 condition removed in every fight against
the box ram and the flipper, 0.04 to 0.19 against the spinner; 1 win in 18. On the box it
stays in contact for 56 to 137 s a fight (`--weapons=ram --hull=box --opps=plain --seeds=11`:
136.6 s within 1.2 m, 0 blows). The AI profile for `ram` has standoff 0 and latch true, so it
drives on and shoves at walking pace and never makes a run-up; the ram's damage is an impulse
bonus, which needs a closing speed. Either the AI needs a run-up (back off, charge) or the ram's
push needs a damage path of its own. No `ram_hit` sound was ever started for the player's ram.

### 4. HIGH: the Lifter turns its own machine over and never lifts anything useful

`--weapons=lifter --opps=plain --seeds=33 --trace=15` (wedge / 4wd / lifter / steel 2). Tick 989
to 1019 (16.5 to 17.0 s): driving at the box ram with fire NOT pressed, the lifter's chassis
climbs to 1.25 m and lands inverted. The srimech then fires, the machine goes up to 0.6 to 0.8 m
and lands inverted again, six times between 17 and 26 s. Over 9 fights: 36 self-inversions a
fight (against 0 to 17 for any other wedge weapon), 0.4 throws, 0.14 condition removed, 1 win.
On a box (`--hull=box`) it no longer self-flips as often (0 to 20) but still removes 0.00 against
the ram in all three fights and lifts the ram 0 times. Frame `lifter_b.jpg` on the contact sheet
shows the lifter standing on its tail against a box ram. The lifter also has no sound or effect
of its own (0 weapon sounds, 0 loops in 9 fights).

### 5. MEDIUM: the AI never swings the axe in a nose-to-nose shove

`--weapons=axe --opps=plain --seeds=22 --trace=300` (box / 4wd / axe / steel 1). From tick 299
the axe and the ram are nose to nose, chassis 0.95 to 0.99 m apart, axe ready (1.00), AI intent
`close`, and fire is never pressed: 0 presses in 150 s with 146 s in contact. Judges loss. The
same build with seeds 11 and 33 swings 7 to 11 times and wins by kill in 20 to 29 s, so the axe
itself works; the AI's strike test fails at this range and angle. Across 9 fights the axe was
3-6.

### 6. MEDIUM: Vortex spinner is overpowered (ring-outs in seconds)

9 wins in 9, 7 stoppages, ring-outs at 4.4 s (`--weapons=vortex_spinner --opps=plain --seeds=22`),
5.8 s and 11.0 s. One bite (0.50 severity) with the 45 % upward throw sends a 30 to 40 kg machine
over the wall. 12.6 throws a fight. The owner's two-or-three-hits rule holds for parts, but
the throw ends the fight before parts matter.

### 7. MEDIUM: Horizontal spinner is overpowered as a matchup

As the subject 8-1. As the opponent, on the lower AI tier, only 12 of 48 subjects beat it, and 21
of the 36 that lost ended with their own weapon jammed (1.9 parts knocked off them on average).
Saw, twin saw, drill, tesla arc, flamethrower, lifter, shock prod and axe all went 0-3 against it.

### 8. MEDIUM: Flamethrower and napalm cannon run dry and spend the rest of the fight unarmed

Flamethrower: `fuel_s` 20; the burner loop ran 14.7 s and then never again in
`--weapons=flamethrower --opps=plain --seeds=11` (28 presses). 2-7 over 9 fights, never a
stoppage, 1.0 condition a fight. Napalm: 5 charges, all gone by mid fight, then nothing;
0.02 / 0.26 / 0.00 condition against the box ram. Both are WEAK rather than broken; the fix is
balance (fuel, regen or charges), not code.

### 9. LOW: twin saw is weaker than the single saw it outranks

Twin saw (ladder 75, 21 kg) removed 1.51 condition a fight and went 4-5; the single saw (12 kg)
removed 2.40 and went 6-3 against the same opponents. The twin saw's per-blade split
(`dps / blades`) plus the wedge's lower mount means one disc is usually in the cut.

### 10. LOW: Tesla arc lands but cannot finish

15 of 19 discharges land, 0.09 a hit, never removes a part in 9 fights; wins only on the judges.

## What reads on screen (from the frames)

- **The white-out is back on almost every weapon.** At the moment of contact a white bloom the
  size of a machine sits over both machines from the fight camera (spinners, drum, crusher, saw,
  twin saw, drill, full body, vortex, arc, and the flipper's own fire). The combat notes list
  S6 (flash pool dims past three young flashes) as "not yet checked by eye": checked, it is not
  enough. The contact point, the victim's reaction and the part coming off are all hidden.
- **Throws read well** when the flash is not on them: flipper throw, drum tip-up, lifter lift
  (box) and vortex lift all look like robot combat in the close frames.
- **Weapons are hard to see from the fight camera**: the bar spinner is a thin stick, the axe a
  thin pole with a small head, the shell and vortex look like plain grey boxes with no visible
  ring or teeth, the drill lance barely shows. Only the flipper, the drum and the twin saw's discs
  read as weapons at the fight distance.
- **Flame is a small orange puff** at the fight camera; the napalm patch is an orange glow disc;
  the tesla arc and the shock prod read as the same white flash as any hit, not as electricity.
- **Ram and lifter have no effect or sound of their own** (0 weapon sounds, 0 loops).
- Sound is present where expected: spin loops for every spinner, saw and drill; `axe_swing` and
  `axe_hit`; `crusher_clamp` on grip; `arc_discharge`, `prod_zap`, `napalm_launch`,
  `vortex_throw`; `flipper_fire` on every flipper fire.

## Fixes owned elsewhere

Nothing in this report was fixed by QA. Physics, AI, rules and balance items go to the combat
engineer (Arena/fight, Arena/ai, weapon scripts); the white-out and the weapon silhouettes go to the
FX and models leads.

## After the weapons pass (2026-09-25, weapons engineer)

Same harness, same 144 fights (16 weapons x plain / w:flipper / w:horizontal_spinner x seeds
11, 22, 33), run on HEAD 28d0887 plus acf0479's numbers. NOT like for like with the table
above: since then the wedge was rebuilt (new proportions, wheel sink fix, which cures bug 1),
the combat engineer changed hit-stop, the white-out and the lifter hold-down, the opponent
horizontal spinner is itself nerfed, and the "plain" box ram now does damage. Raw rows:
`docs/qa/data/weapons-gauntlet-after-2026-09-25.jsonl`. Details: `docs/wave-a-weapons-notes.md`.

| weapon | before W-L (stoppages) | after W-L (stoppages) | before dmg out | after dmg out | what changed |
|---|---|---|---|---|---|
| horizontal_spinner | 8-1 (2) | 8-1 (1) | 3.78 | 2.01 | impulse 180->120, destabilise 0.6->1.0 (spin-up 2.6) |
| vertical_spinner | 2-7 (1) | 8-1 (8) | 1.43 | 3.06 | none (wedge stall fixed by hull/combat) |
| flipper | 4-5 (1) | 4-5 (0) | 0.05 | 0.06 | none |
| lifter | 1-8 (1) | 2-7 (1) | 0.14 | 0.23 | AI: face + press only with a load on the forks (ForkArm contacts); self-flip fix is the combat engineer's |
| crusher | 6-3 (5) | 7-2 (5) | 2.61 | 2.83 | none |
| axe | 3-6 (3) | 4-5 (4) | 1.21 | 1.94 | AI turns its nose to them in the clinch (the drive was reversing tail first) |
| saw | 6-3 (1) | 4-5 (3) | 2.42 | 2.36 | none |
| ram | 1-8 (1) | 2-7 (0) | 0.00 | 1.38 | blow damage 0.06 per m/s over 0.8 m/s closing; AI run-up 1.4 m after each blow |
| flamethrower | 2-7 (0) | 2-7 (0) | 1.00 | 1.82 | fuel regen 0.25 s/s after 1 s off; AI presses only with them in the cone, bursts off a 20/45 % latch |
| full_body_spinner | 7-2 (6) | 7-2 (3) | 4.08 | 3.82 | none |
| shock_prod | 0-9 (0) | 6-3 (1) | 0.15 | 1.92 | none (wedge stall fixed by hull/combat) |
| tesla_arc | 4-5 (0) | 6-3 (0) | 1.36 | 2.30 | none by decision (stall/points weapon) |
| drill_lance | 5-4 (4) | 3-6 (3) | 2.98 | 2.39 | none |
| twin_saw | 4-5 (1) | 7-2 (7) | 1.56 | 4.26 | whole dps goes to whichever discs bite (was dps/2 per disc) |
| napalm_cannon | 4-5 (2) | 2-7 (2) | 1.74 | 3.58 | one shell reloads every 15 s; AI lobs only at 1.25 m to 2.27 m |
| vortex_spinner | 9-0 (7) | 8-1 (2) | 1.32 | 4.12 | impulse 250->110, lift 0.45->0.2, spin-up 3.2->4.5, control 0.55->0.4 |

After-run notes:
- Ram: 0.00 -> 1.38 condition a fight, 12.8 blows, 2 wins; still WEAK (6 of 9 ended with it bent).
- Axe: presses 12.3 a fight, swings nose to nose (the seed 22 box ram fight now has presses).
- Vortex: no ring-outs (0 throws a fight, was 12.6); still 8-1 but 6 of 8 wins on the judges.
  Horizontal spinner 8-1 on this tree (it measured 5-4 and 6-3 on intermediate trees); both
  remain the top of the table and are the next tuning target (target 55-65 %).
- Flame: burner runs all fight; 1.82 a fight but still 2-7. Napalm: 10 shells a fight, 3.58
  condition a fight, 2-7 (the lob misses a machine in the clinch).
- Twin saw 7-2, 4.26 a fight vs the saw's 2.36: it now earns its price.
- Tesla arc: kept as a stall/points weapon (0 parts off, 6-3 on points). 0.09 a discharge on
  one part, with 1.6 s of weapon AND drive stall, is the design: the damage is what you do
  in the 1.6 s. A part-removing arc would out-damage the saws while also stalling them.
- Lifter: 1.1 throws a fight, 2 wins (was 0.4 / 1), self-inversions 36 -> 2.4 on this tree.
- Readability fx (8094748): blue arc burn, violet prod, ram dust/sparks/crunch, lifter
  clunk and amber light, spinner blur disc and rim, fatter longer flame. Frames NOT recaptured yet.
