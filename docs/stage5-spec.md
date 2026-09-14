# Stage 5 spec: career and stable

Brief §15 Stage 5: "Five tiers, six arenas, five bosses, rivals with persistent history, garage capacity
growth, scrap economy, repair and write-off costs, blueprints, SwiftData persistence." Read
`docs/brief-v3.md` §4, §7, §8, §9, §10 (Career), §14 (where the free wall sits; the wall itself is
Stage 6, but the free portion's content is decided here), then `docs/stage4-spec.md` and the Stage 4
notes. Landscape, AAA chrome (docs/stage2-art-direction.md final sections), no em dashes.

## 1. Data (Swift, SwiftData) and the catalogue

`Shared/parts.json` gains `career` (tiers, entry fees, purses, garage capacity, blueprint drip),
`bosses` (five, with their builds and personalities), `rivals` (eight named AI roboteers with a starting
build, a livery, a voice line set and an upgrade path per tier), `arenas` already exist. New @Models:
- `CareerState`: tier (scrapyard|regional|national|championship|masters), bracket JSON (current
  tournament: 8 entrants, rounds, results), scrap balance, blueprints [String], garageCapacity,
  fightsPlayed, wins, championshipsWon, currentSeasonSeed.
- `RivalRecord` (id, name, build JSON, tier, wins/losses vs the player, grudge lines, lastMet).
- `BotBuild` gains `damageJSON` (already), `isWrittenOff`, `killedBy`, `retiredAt`.
- `FightLog` (date, tier, round, opponent id, outcome, scrap earned, repair cost, arena, replay JSON path).

## 2. Loop (Swift)

Garage -> Bracket (the tier's 8-entrant single elimination; the player is one entrant; rivals fill the
rest with builds at the tier's power band) -> Scouting report (the opponent's build read from its config,
a stage view of THEIR bot: `workshop_config` with `"mode": "scout"`, the brief's "orbit the opponent's
bot") -> pick which stable bot to send -> Fight (arena by tier: Scrapyard = Yard, Regional = Grinder,
National = Drop Zone, Championship = Furnace and Crush alternating, Masters = Coliseum) -> Damage
assessment sheet: repair bill per part (scrap = condition lost x part price factor from the catalogue),
write-off when repair > 70 % of the build's value (offer scrap-for-parts), scrap and blueprints earned,
rival grudge line -> back to the garage. Losing costs the entry fee and repairs; re-enter the bracket.
Winning the final advances the tier, raises garage capacity per §9, unlocks blueprints per the drip.

## 3. Arenas (Godot, agent A5) `Arena/arena/{grinder,drop_zone,furnace,crush,coliseum}.tscn`

Each per brief §7 with a genuinely two-way signature hazard, built on the Yard's conventions (floor,
walls, OOA sensor, spawn markers, `setup(rng)`, hazards on the physics tick): Grinder = two floor-mounted
angle grinders on the flanks (spinning discs, continuous cut damage, sparks); Drop Zone = a central pit
whose cover retracts at a seeded time mid-fight (falling in = out of the arena); Furnace = wall flame
jets on timers (flame damage plus disruption) and a conveyor floor strip; Crush = descending wall rams
on the sides that pin and flatten (heavy impulse); Coliseum = spikes + grinders + flame + spinning floor
discs. Arena id selects the scene in fight.gd.

## 4. Bosses (Godot + catalogue, agent B5)

Five originals per brief §8 as builds the assembler can make plus one signature part each (modelled by
G3's pipeline): THRESHER (long_low, 6wd, crusher, lifting arm), GRUDGE (box, tracks, flamethrower),
BANDSAW (wedge, 2wd, saw, fast), ANVIL (tall_tank, 4wd, axe, a wall-like front), CINDER (box, 6wd, huge
scoop-flipper). Boss AI personalities as OpponentAI modes. Bosses appear in gauntlet events (Stage 6) and
to punish inactivity: in career fights, if both bots are idle (no contact) for 15 s the boss enters from a
gate and attacks whoever is nearest until contact resumes. Silhouette test per brief §3.

## 5. Rivals (Swift + AI)

Eight named roboteers with persistent bots that upgrade in parallel with the player: each tier they get
the tier's blueprint drip applied by a simple upgrade policy (heavier weapon, better armour), keep their
build across seasons, remember results ("You knocked me out of the Regional semi. Not this time."),
shown on the scouting screen and the pre-fight card. Names and bots are original (invented, IP-safe).

## 6. Economy numbers (first pass, tuned in play)

Entry fee per tier 50/120/250/500/900 scrap; purse per win 120/260/520/1000/1800 and x3 for the final;
fight scrap from damage as today; repair cost = sum over parts of condition lost x part price (chassis
price 10x weight, weapon 12x weight, drive 8x, armour 6x per face, utility 6x); write-off threshold 70 %;
blueprint drip: Scrapyard grants 2 weapons + 1 chassis over 3 wins, Regional 2 weapons + 1 chassis + 2
drives over 4 wins (the free portion must reach "three or four weapons and two chassis", brief §14);
National and up unlock the rest across wins and side events.

## 7. Persistence and QA

SwiftData in the app group container; every fight logs a FightLog with the result and the replay input
log (JSON, for Stage 6 replays); a `-career <state.json>` launch argument loads a fixture state for QA
(mid-Regional, three bots, one written off); the pre-fight card, bracket, garage and assessment screens
in the AAA chrome; the bracket layout is a lit tournament board (data-driven, all 8 slots).
