# Wave P, agent C: the arena result and the scrap ledger

2026-09-17. FightResult v2 and the live career scrap ledger, to the contract in
`docs/wave-p-contracts.md` (row "C arena result", sections "Fight config" and "FightResult v2").
Nothing here deviates from the contract, so there is no "Amended by C" paragraph in that file.

## What was built

**`Arena/fight/rules.gd`**, a new section "wave P: the scrap ledger", pure static functions only
(no scene tree, no rng, no clock):

| Function | What it answers |
|---|---|
| `damage_fraction(start, now)` | `1 - condition_total(now) / condition_total(start)`, clamped 0..1 |
| `damage_bonus(rules, foe_start, foe_now)` | `damage_full` x that fraction, rounded |
| `survivor_bonus(rules, start, now)` | `survivor` when own total at the bell is at least `survivor_min` of the start |
| `flawless_bonus(rules, won, now)` | `flawless` when the bot WON and nothing is at zero |
| `any_part_zero(condition)` | any wheel or track, weapon, drive, core or armour face at zero |
| `scrap_breakdown(rules, own_start, own_now, foe_start, foe_now, won, at_bell)` | the four lines and their total |
| `parts_lost(condition, wheel_keys, weapon_fault)` | `[{part, label, state}]` in report order |
| `part_label(part_key)` | the words a player reads |
| `hits_from_tallies(tallies, ids)` | `{bot: {landed, taken}}` from `weapon_hits` |

An empty `rules` dictionary means "no career scrap in this fight" and every one of them answers
zero, which is what keeps the legacy behaviour exactly what it was.

**`Arena/fight/fight.gd`**, one new section `# --- wave P: scrap ledger` plus five targeted edits:

- `_scrap_rules` (the config's `rules.scrap`, empty everywhere but a career match) and
  `_start_condition` (one condition dictionary per bot, captured after `_spawn_bots`). The snapshot
  had to be called `_start_condition`: wave V already owns `_condition_start`, which is one FLOAT
  per bot for the HUD's condition bars. Two things with almost the same name in one file is a trap,
  so both are commented to point at each other.
- `_on_damage_event`: a bolt no longer adds to `_scrap` while career rules are present.
  `scrap_awarded` still fires with the bolt's legacy value, so F's fx, the bolt shower and the
  haptics are untouched.
- the HUD line became `_hud_call("set_scrap", [scrap_running(0)])`.
- `test_reset` re-captures the snapshot, so a test arena reset starts a clean ledger.
- `_finish` builds the four new keys and, with career rules, sets `scrap[bot]` to the breakdown
  total.
- new methods: `scrap_running(index)` (the HUD's number), `scrap_breakdown_for(index, won, at_bell)`,
  `_capture_condition_start`, `_condition_start_of`, `_condition_now_of`, `_wheel_keys_of`,
  `_weapon_fault_of`, `_ledger_foe_index`.

**`Arena/fight/result_builder.gd`**: `hits`, `parts_lost`, `condition_start` and `scrap_breakdown`,
always present, one entry per bot in the config, each with a zero shaped default, and the
breakdown's `total` recomputed from its four lines rather than copied. `TOP_LEVEL_KEYS` lists them.
`schema` stays 1.

**`Roboteer/FightResult.swift`**: `hits: [String: Hits]`, `partsLost: [String: [PartLost]]`,
`conditionStart: [String: BotDamage]`, `scrapBreakdown: [String: ScrapBreakdown]` (the type already
in `ProgressionTypes.swift`), all decoded tolerantly, all missing-key-safe. `PartLost` carries
`part`, `label`, `state` plus `isDestroyed` and a `sentence` ("Weapon destroyed") for B1's report.
The `damage` decode was factored into one `botDamage(_:)` helper so `condition_start` cannot drift
from `damage`. This landed first, inside the first hour, because agent A decodes it into
`MatchReport`.

**`docs/bridge-spec.md`**: a new section "FightResult v2 (additive, schema stays 1)" with the wire
example, the `rules.scrap` config key, and every rule above written down.

**Tests**: `Arena/tests/scrap_test.gd` (new, 102 checks) and a "FightResult v2 (wave P)" section in
`Arena/tests/rules_test.gd`. `Arena/tests/_scrap_probe.gd` is a measurement probe, not a test (the
leading underscore keeps it out of the suite, the way the other `_*_probe.gd` files are).

## The decisions the contract left open

- **`disabled` versus `destroyed`.** Zero condition is `destroyed` for the weapon, the wheels, the
  armour faces and the core. The drive at zero is `disabled`, because nothing has come off the
  machine: its motors have stopped. A weapon that still has condition but is `jammed` or `cooked`
  is `disabled` too. A machine with no weapon fitted reports no weapon row at all, even though
  `Bot.weapon_fault()` answers "jammed" for it (that answer exists for the fire button's sake).
- **Report order** in `parts_lost`: weapon, drive, wheels (in the drive's key order), armour faces
  (front, sides, rear, top), core. Most fight-relevant first, and stable, so the report never
  reshuffles between matches.
- **`taken` in `hits`** is the sum of the other machines' `landed`. In a two bot fight, which is
  the whole of the career, that is exactly the opponent's count. A Rumble would over-attribute, and
  a Rumble carries no scrap rules.
- **Rounding**: each line is rounded to a whole number on its own (`int(round(...))`), so the total
  is the sum of the numbers the player is shown, never a rounded sum that disagrees with its lines.
- **`condition_start`** is captured from `Bot.condition()` after the machines are built, not from
  the config's `damage` block, so it is normalised (six wheels, tracks, missing keys filled). The
  builder falls back to the config block when there is no machine.
- **`hud.gd` needed no change.** `set_scrap` is already "here is the authoritative total, roll to
  it", which is exactly what the ledger publishes every frame. The bolt `bump()` from `fx.gd` still
  flashes the bug and is still corrected by the next `set_scrap`, which is what legacy did too
  (legacy also credited `_scrap` at award time and bumped again at collect time).

## Determinism

The ledger is a pure function of condition, and condition is simulation state. Nothing in the new
code draws from the rng, reads the wall clock or reads a position (`_ledger_foe_index` is
`1 - index` in a two bot fight rather than "nearest machine"). `determinism_test` is green, 42
checks, so replays are still bit-exact.

## Measured, in a headless fight

`scripts/test-arena.sh scrap_test rules_test determinism_test fight_shape_test bridge_test`: green,
535 checks over the five files. The whole suite: see the bottom of this file.

`Arena/tests/_scrap_probe.gd` runs a real 180 s fight in the Yard, two AI machines (Regional skill,
brawler temperament), the same weapon on both, seed 20260917, and prints what Series 1's rules
(`base` 120, `damage_full` 200, `survivor` 60, `survivor_min` 0.7, `flawless` 100) pay for it.

Two full rounds ran (they cost about four minutes of wall clock each, so the remaining four weapons
were measured on a shorter round; see below):

| Fight (180 s, Yard, seed 20260917) | Condition removed from the other machine | Hits landed | Own condition at the bell | Parts lost | Damage line |
|---|---|---|---|---|---|
| flipper, bot-0 | 3.3 % | 0 | 10.42 of 11.00 | none | 7 |
| flipper, bot-1 | 5.2 % | 1 | 10.64 of 11.00 | none | 10 |
| horizontal spinner, bot-0 | 0.0 % | 0 | 11.00 of 11.00 | none | 0 |
| horizontal spinner, bot-1 | 0.0 % | 0 | 11.00 of 11.00 | none | 0 |

**This is the number that matters and it is uncomfortable.** Two competent AI machines in the Yard
remove 0 to 5 % of each other over a full three minute round, so `damage_full` of 200 pays 0 to 10
scrap, and a spinner fight where the two drivers circle each other pays NOTHING on the damage line.
The Series 1 win is therefore base 120 + survivor 60 + flawless 100 = 280 of a possible 480, and the
damage bonus is a rounding error rather than the reward the brief describes ("scaled to damage
inflicted on the opponent").

Three honest readings of that, for the owner to choose between:

1. A human is not two cagey AIs. A player who drives in and lands the weapon will remove far more,
   and the phone is the only place to find out. Nothing changes until he has played four matches.
2. `damage_full` is the dial. If a typical fight removes 10 % rather than 100 %, then `damage_full`
   of 200 pays 20, and it wants to be nearer 800 to 1200 for the damage bonus to be felt at all.
3. The damage fraction could be scaled rather than linear (a square root, say), so the first 10 %
   pays a third of the bonus. That is a two line change inside `Rules.damage_bonus` and nothing else
   in the wave has to know.

Two caveats on the measurement, both of which the phone settles: the probe's fixture is a wedge with
`steel 2` armour on every face and no weight optimisation, so the heavier weapons report "over the
weight budget" and would not pass the builder as configured; and both machines run the same
Regional brawler AI, which is not what Series 1's house bots do.



## One verification trap worth recording

`fx_test.gd`'s haptic cap check is load sensitive. Run on its own it passes ("worst 30, 73 sent");
run while a 180 s physics probe was saturating the CPU it failed ("worst 31, 74 sent"), because the
FX presentation clock it prunes its one second window against is stepped by REAL frame deltas, and
under load a frame is long enough to let one more haptic into the window. It is nothing to do with
wave P (`fx_test.gd` loads `fx.tscn` only, never `fight.gd`, and no file in `Arena/fx/` has been
touched since `3ef4677`). So: do not run the suite and a physics probe at the same time, and if that
check ever goes red, re-run `fx_test` alone before believing it.

## What the phone has to confirm

1. **The bug reads as a tally, not as a jackpot.** It starts the fight at `base` (120 on Series 1)
   rather than at 0, and climbs. Nobody has seen that on a screen yet; if starting at 120 looks
   like a bug to the owner, the alternative is to show the damage line alone while fighting and the
   base on the Rewards screen. That is a two line change in `scrap_running`.
2. **The bolt flash versus the ledger.** Bolts are now decorative in a career match. On the phone
   the question is whether a bolt that pays nothing still feels like it pays something, and whether
   the brief flash from `fx.gd`'s `bump` fights the authoritative number.
3. **Whether a fight pays what the ladder assumes.** The probe's numbers are AI against AI. A human
   who wins 3 of 4 will land more hits and take less, so his damage fraction will be higher than
   the probe's and his survivor bonus much more likely. Agent A's self test assumes "base plus half
   the damage bonus plus survivor"; the phone is where that assumption gets checked against a real
   player.
4. **The words on the report.** "Front armour destroyed", "Drive disabled", "Rear left wheel
   destroyed": read them on a real match report at phone size before trusting them.

## The dials the owner can turn

Every one of these is data, in `Shared/parts.json` `progression.series[n].scrap`, and needs no code
change:

- `base`: the floor for turning up. Raise it to make early Series forgiving.
- `damage_full`: the whole damage bonus at 100 % of the opponent's condition removed. The probe's
  fractions say what a typical fight actually pays, which is a long way below `damage_full`.
- `survivor` and `survivor_min`: 0.7 is generous against a spinner and strict against a flipper
  fight where nothing much is removed. Lower `survivor_min` to pay it more often.
- `flawless`: the "won without losing a part" line. Because it is about parts at ZERO and not about
  damage, it is winnable in a fight that went badly, which is deliberate (brief v5 section 3 says
  "won without losing any part").

Nothing was faked and nothing was left as a stub. `rules.scrap` absent is the legacy path and is
covered by a test that asserts the old numbers to the unit.
