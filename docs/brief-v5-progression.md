# Roboteer brief v5: the career progression system

Received 2026-09-17 from the owner as the Claude Doc "Roboteer, Career Progression System Brief"
(all its design questions resolved by him). Sections 1 to 8 are that brief, as written. Section 9
is how it maps onto the game that exists (brief v4 and everything built on 2026-09-16), decided
by the coordinator so nine agents can build it in one wave without asking. Where v5 and v4
disagree, v5 wins. Where v5 is silent, v4 stands.

## 1. Production bar

This ships at AAA mobile-game quality and depth, not a prototype. Every spec in this brief
(progression depth, damage modelling, UI polish, itemisation breadth) is a floor, not a target.
Implementation should aim for high-fidelity 3D models and materials, particle- and sound-rich
damage feedback, polished screen transitions and UI, and full content depth. No placeholder art or
stub systems in the shipped build.

## 2. Core loop

Two progression tracks run side by side: **Scrap** (spendable currency) and **Level** (one
continuous career bar, no separate ranks or tiers). They gate different things: Scrap buys a part
your Level already allows; Level decides which parts you are allowed to buy at all.

1. Fight a match in the arena. Scrap is earned during the match but only banked if you win. Lose,
   and that match's Scrap is forfeited.
2. Match Report: result and robot condition, shown immediately.
3. Rewards screen: reached only on a win, showing Scrap banked and Level points earned. A loss
   skips straight from the Match Report to a retry prompt instead, replaying that same match.
4. Optionally spend Scrap to repair damaged parts before the next match.
5. Spend Scrap in the shop on any part your current Level allows.

Example: Level 5 unlocks the Saw, Level 40 unlocks the Flamethrower. Level rises by playing
through Series. Each Series is 4 matches, and five Series ship at launch, each with its own look
and feel.

## 3. Scrap economy

**Earning Scrap**, tallied live during the match, all stacking:

| Source | When it applies |
|---|---|
| Base payout | Every match |
| Damage-dealt bonus | Scaled to damage inflicted on the opponent |
| Survivor bonus | Finished the match with most of your own health intact |
| Flawless bonus | Won without losing any part |

None of it banks on a loss: the whole match's Scrap total is forfeited unless you win.

**Spending Scrap:** new parts, once your Level allows them; repairing damaged parts between
matches, cost scaling with how damaged the part is; purchases are permanent, no sell-back.

## 4. Series structure

Five Series ship at launch, each with its own look and feel: arena theme, opponent roster and
presentation. Each Series is 4 matches long. Finishing Series matches feeds the player's Level
bar. The five launch Series are played in strict order; each one unlocks the next.

## 5. Post-match report

Shown the moment a match ends, before any rewards: a quick, factual tally, not a celebration.

- **Result**: Win / Loss / Draw
- **Match duration** and hits landed vs taken
- **Robot condition**: per-part health as a percentage (Flipper 40 %, Left armour 10 %)
- **Parts destroyed or disabled** during the fight

Condition carries into the next match unless repaired: a robot that goes in with a cracked
flipper fights the next match with a cracked flipper.

## 6. Rewards screen

Reached only on a win; this is the payoff screen. A loss skips it entirely and goes straight to a
retry prompt.

- **Scrap banked**: a running tally (base plus each bonus line)
- **Level points earned**
- **Series progress**, for example "Series 1: 2/4 matches"

Level accrues only on a win, the same as Scrap; a loss earns neither.

## 7. Level gating

Level is one continuous bar, not ranks or tiers. Specific items unlock at specific Level numbers,
independent of which Series you are playing.

| Item | Level required |
|---|---|
| Flipper | Starting loadout |
| Saw | 5 |
| Reinforced Armour | 10 |
| Tracked Wheels | 15 |
| Ram Plow | 20 |
| Spinner Blade | 25 |
| Hydraulic Legs | 30 |
| Shock Prod | 35 |
| Flamethrower | 40 |
| Reactive Armour | 45 |
| Crusher Claw | 50 |
| Hover Thrusters | 55 |
| Tesla Arc | 60 |
| Drill Lance | 65 |
| Titanium Armour | 70 |
| Twin Saw | 75 |
| Napalm Cannon | 80 |
| Adaptive Tracks | 85 |
| Overcharge Core | 90 |
| Vortex Spinner | 95 |
| Apex Chassis | 100 |

Cosmetic paint jobs are Level-gated too, but unlocked free at milestones, not bought with Scrap.
Art assets for these are produced with Recraft. First-pass ladder: 21 parts across weapons,
armour, mobility and utility, spread to Level 100. Thresholds and specific parts are open to
balancing once matches are timed and tested. Some higher-Level parts carry cosmetic flair
alongside their stats; which ones is an art-pass call.

## 8. Status (owner)

All design questions resolved. The item-by-Level ladder above is a first pass, open to
balancing once matches are timed and tested.

## 9. How it maps onto the game (coordinator, 2026-09-17)

Everything below is data in `Shared/parts.json` under a new `progression` block, so a number can
be tuned without touching code. Agents read the block; nothing invents a number.

### 9.1 Series = the five circuits

The five Series are the five tiers that already exist (`scrapyard`, `regional`, `national`,
`championship`, `masters`): their arenas, backdrops, house bots, rivals and AI skill ARE the
"own look and feel" per Series. The ids stay (Gates, rivals, bosses and the AI all key on them).
On screen a tier is now "Series 1: Scrapyard" and so on; the words "tier", "circuit" and "season"
leave every user-facing string.

- A Series is **four matches in a fixed order** (`progression.series[n].matches`), the fourth
  being the Series final against that Series' headline rival. Fillers are drawn by the existing
  deterministic filler generator from the career seed.
- **Strict order.** Match 2 opens when match 1 is won. Series 2 opens when Series 1's final is
  won. The full-game wall stays where it is: Series 1 and 2 are free, Series 3 to 5 need the unlock
  (`Gates`), exactly as the tiers did.
- **No entry fees, no purses, no bracket, no blueprint drip.** The bracket of eight, the seeded
  draw, the AI-simulated ties and the `SeasonTally` are retired from the career flow (types may
  stay for old-save decoding). Money comes only from section 3. Parts come only from the shop.
- **Losing** does not end anything: the retry prompt replays the same match (same opponent, same
  arena; the seed changes per attempt so the fight is not identical). Attempts are counted.
- **After the campaign** (Series 5 final won) any won match can be replayed from its Series
  screen; a replay pays `replay_scale` of the scrap and Level points. That is how Level 100 and
  the last few parts stay reachable and why the shop never goes dead.
- The house bot per Series and the corner zone rule are v4 §3 unchanged. AI skill = the Series id,
  temperaments unchanged.

### 9.2 Level

- `levelPoints` on the career. Level = 1 + floor(points / `points_per_level`), capped at
  `level_cap` (100). New career = Level 1.
- A win pays `series[n].win_points` (350, 450, 500, 550, 625). Four wins in each of five Series =
  9,900 points = Level 100 on the last final. A **flawless** win pays `flawless_points_bonus`
  (+25 %) on top, so Level 100 can arrive earlier.
- `level_required[part_id]` for EVERY part in the catalogue (the brief's 21 at the brief's numbers,
  the rest slotted between them so the ladder has something new every two to three Levels).
  Starting loadout (Level 1): wedge, box, 2wd, 4wd, flipper, steel, hdpe, srimech.
- Paint jobs: `progression.paint_jobs`, ten of them, one per ten Levels, free at the milestone.

### 9.3 Scrap

- The fight config carries `rules.scrap = {base, damage_full, survivor, survivor_min, flawless}`
  from `series[n].scrap`. The arena tallies live and reports `scrap_breakdown` (v5 fields in
  `docs/wave-p-contracts.md`); the HUD's scrap bug shows base plus the running damage bonus.
- Damage bonus = `damage_full` x the fraction of the opponent's total condition removed (0 to 1).
  Survivor = `survivor` when the player's own condition total at the end is at least
  `survivor_min` (0.7) of what it started with. Flawless = `flawless` when the player won and no
  part reached zero condition (no wheel, weapon, drive, core or armour face at 0).
- Banked on a win only. On a loss or a draw the whole total is forfeited and the Rewards screen is
  skipped.
- Prices stay the existing `economy.price_factor` x weight formula. Repair cost stays condition
  lost x price per part (it already scales with the damage). Purchases are permanent.
- A `Quick Fight`, a side event, the test arena and the ladder send no `rules.scrap`; they keep
  the bolt scrap they have and bank nothing into the career.

### 9.4 The screens

Order after every career match: **Match Report** (section 5) -> on a win **Rewards** (section 6)
-> on a loss or draw **Retry prompt** (Retry, Repair and retry for N, Back to the garage) -> the
Series screen. Repairs are the existing repair sheet reached from the Series screen and from the
retry prompt. The **Shop** is new: every part in the catalogue grouped by kind, each row showing
name, weight, the stat pips, the price, and either BUY, OWNED, or "Level N" when locked; a part
whose Level is reached but which is behind the full-game wall says so. Bought parts appear in the
builder exactly as blueprints did (`CareerState.blueprints` is now the owned list).

The Series screen replaces the season screen: the Level bar, the Series title, a strip of the four
matches with results, the next-match card with FIGHT inside it, and Garage / Repair / Shop as
links. Design-system §8 rules hold: one hero, at most two panels, money as a sentence.

Owner's standing rule since 2026-09-16: mockups and options before UI builds. Each UI agent
writes an HTML options page in `docs/look/` first and builds the option it recommends; the owner
can veto after seeing it on the phone.

### 9.5 New parts (13), so the ladder has what the brief names

| id | Kind | Level | One line |
|---|---|---|---|
| `reinforced` | armour material | 10 | Reinforced steel: heavier than titanium, best against hazards and cuts |
| `legs` | drive | 30 | Hydraulic legs: a four-leg walker, slow, immense push, steps over floor hazards |
| `shock_prod` | weapon | 35 | Contact prod that disrupts the target's drive for a moment |
| `reactive` | armour material | 45 | Reactive armour: shrugs impacts and shoves the attacker back |
| `hover` | drive | 55 | Hover thrusters: fastest thing in the arena, no push, floats over spikes, flips easily |
| `tesla_arc` | weapon | 60 | Short arc that jumps to the nearest opponent part and stalls its weapon and drive |
| `drill_lance` | weapon | 65 | Spinning lance that ignores half the armour's factor |
| `twin_saw` | weapon | 75 | Two saws, wider reach, higher damage |
| `napalm_cannon` | weapon | 80 | Lobs a burning charge that leaves a patch of fire |
| `adaptive_tracks` | drive | 85 | Tracks that turn like wheels and cannot be torn off |
| `overcharge_core` | utility | 90 | Faster spin-up and harder hits, and the core cooks while the weapon is at full |
| `vortex_spinner` | weapon | 95 | A full-body spinner with angled teeth that throw as well as hit |
| `apex` | chassis | 100 | The best hull in the game: every weapon fits, hardest to flip or tip |

Existing parts renamed on screen only: `ram` reads "Ram plow", `horizontal_spinner` reads
"Spinner blade", `tracks` reads "Tracked wheels". Ids do not change.

### 9.6 Old saves

A career saved before this wave (tier + bracket + scrap + blueprints) migrates on first read:
Series = its tier, match index = its bracket wins in that season (0 to 3), Level points = the
points its lifetime wins would have paid at Series 1, scrap and owned parts kept. Nothing is
lost and nothing crashes; the self test covers it.
