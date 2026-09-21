# Wave P contracts: the career progression system

The shared surface between the nine agents building `docs/brief-v5-progression.md`. An agent may
ADD to the surface it owns; it may not change a name or a type here without writing the change
into this file first (a short "Amended by X" paragraph, the way wave G did). Everything else an
agent touches is in its own files. Read the brief in full, then your section, then the files you
own, before touching anything.

## Ownership

| Agent | Owns outright | Owns a SECTION of a shared file |
|---|---|---|
| **A engine** | `Roboteer/ProgressionEngine.swift` (replaces the stub), `Roboteer/ProgressionTypes.swift` (compile fixes and additions only, never removals), `CareerEngine.swift`, `CareerModels.swift`, `CareerStore.swift`, `CareerCatalogue.swift`, `Catalogue.swift`, `CareerSelfTest.swift`, `Roboteer/Store/Gates.swift`, `Roboteer/Fixtures/*`, `QuickFight.swift` (skill from the Series only), `Roboteer/Ladder/*` and `Roboteer/Events/*` and `Roboteer/Replays/*` ONLY where they stop compiling | `Shared/parts.json`: the `progression` block and `career` block |
| **B1 post-match** | `MatchReportView.swift`, `RewardsView.swift`, `RetryPromptView.swift`, `DamageAssessmentView.swift` (retire or fold), `ResultSheet.swift`, `CareerFightView.swift`, `FightView.swift` (only if the quick fight adopts the report), `docs/look/postmatch-options.html` | `DesignSystem.swift`: a new `// MARK: - Wave P, post-match` section at the END of the file only |
| **B2 series and shop** | `CareerHomeView.swift` (root flow and the Series screen), `ShopView.swift`, `BracketView.swift` (becomes the campaign board), `ScoutingView.swift`, `MenuView.swift`, `CareerGarageView.swift` (Blueprints panel becomes "Owned parts"), `docs/look/series-options.html` | `DesignSystem.swift`: a new `// MARK: - Wave P, series` section at the END of the file only |
| **C arena result** | `Arena/fight/result_builder.gd`, `Arena/fight/rules.gd` (new pure helpers), `Arena/tests/scrap_test.gd` (new), `Arena/tests/rules_test.gd` (additions), `docs/bridge-spec.md` (FightResult v2 section), `Roboteer/FightResult.swift` (v2 fields), `Roboteer/ArenaHost.swift` (only if a new message needs it) | `fight.gd`: the scrap section (`_on_damage_event` scrap lines, `_scrap`, `_build_result`), one new `# --- wave P: scrap ledger` section; `hud.gd`: `set_scrap` and the scrap bug label; `fight_types.gd`: scrap constants |
| **D1 weapons** | `Arena/bot/weapons/shock_prod.gd`, `tesla_arc.gd`, `drill_lance.gd`, `twin_saw.gd`, `napalm_cannon.gd`, `vortex_spinner.gd` (new), `Arena/tests/weapons_p_test.gd` (new) | `Shared/parts.json` + `Arena/data/parts.json`: the six `weapon` entries; `Arena/bot/weapon_base.gd` and `bot.gd`: the weapon registry / kind switch lines only; `Arena/ai/opponent_ai.gd`: the per-weapon profile table only; `Arena/bot/damage.gd`: new damage types only |
| **D2 mobility, hull, armour, utility** | `Arena/bot/drive/legs.gd`, `hover.gd`, `adaptive_tracks.gd`, `Arena/bot/chassis/apex.gd` (new), `Arena/tests/mobility_p_test.gd` (new), `Arena/bot/build_rules.gd`, `Roboteer/BuildRules.swift` (only if a new fit rule needs Swift) | `Shared/parts.json` + `Arena/data/parts.json`: the `drive`, `chassis`, `armour.material`, `utility` entries for `legs`, `hover`, `adaptive_tracks`, `apex`, `reinforced`, `reactive`, `overcharge_core`; `bot.gd`: drive registry lines, hover/walker physics hooks, the utility effect switch; `damage.gd`: material factor reading and `reactive_knockback`; `Arena/bot/catalogue.gd` if it validates ids |
| **E models** | `Tools/blender/**`, `Arena/assets/parts/**`, `Arena/assets/textures/**` (new sets only), `Tools/textures/**`, `Arena/bot/part_meshes.gd`, `Arena/bot/part_visuals.gd` (all but the livery section), `docs/third-party-models.md` (new) | nothing shared |
| **F feedback fx and audio** | `Arena/fx/**` new files, `Arena/audio/**` new files, `scripts/gen-sounds.py`, `Arena/tests/fx_test.gd` and `audio_test.gd` (additions) | `Arena/fx/fight_fx.gd` (or whatever dispatches damage fx: find it): a `# --- wave P` section; `Arena/fx/audio_mix.gd` and `Arena/fx/machine_audio.gd`: registration of new sounds; `fight.gd`: NOTHING (F hooks through existing signals only) |
| **G paint jobs** | `Art/paint/**`, `Arena/assets/textures/paint/**`, `Roboteer/PaintJobs.swift` (replaces the stub), `Arena/bot/livery.gd` (new), `docs/paint-jobs.md` | `part_visuals.gd`: the livery section (`_livery_material` and `bind`'s livery lines); `BotBuild.swift`: a `paintID` field and its line in `toBotConfig`; `BuilderView.swift`: the livery section (`// MARK: - Livery`) only; `Shared/parts.json`: nothing (the `paint_jobs` list is already there; propose changes to the coordinator) |

Shared files (`fight.gd`, `hud.gd`, `bot.gd`, `damage.gd`, `opponent_ai.gd`, `part_visuals.gd`,
`DesignSystem.swift`, `parts.json`): small targeted edits only, re-read the region right before
each edit, never rewrite the file, never reformat or reorder anything outside your section. Two
agents editing the same file at once is expected. `Shared/parts.json` is authored, then copied
byte-identical to `Arena/data/parts.json` (`cp Shared/parts.json Arena/data/parts.json`; the
assembly test checks the copy). Edit it with a JSON-aware script that preserves key order and the
one-space indent, never by hand-pasting a block.

## The catalogue: `progression` (coordinator wrote it, A reads it, D1/D2 add the part entries)

`Shared/parts.json` now has a `progression` block: `points_per_level` 100, `level_cap` 100,
`free_level_cap` 33, `flawless_points_bonus` 0.25, `replay_scale` 0.5, `series[5]` (id, name,
index, number, arenas, `win_points`, `scrap {base, damage_full, survivor, survivor_min, flawless}`,
`matches[4] {opponent: rival id | "filler", final}`), `level_required {part id: level}` for all 45
parts, `display_names {ram, horizontal_spinner, tracks}`, `paint_jobs[10] {id, name, level}`.

The 13 new part ids and their kinds are fixed (brief §9.5): `reinforced`, `reactive` (armour
materials, with `factor {impact, hazard, cut}` and `kg_per_unit_area` like the others), `legs`,
`hover`, `adaptive_tracks` (drive), `apex` (chassis, with `wheel_slots` for 2wd/4wd/6wd, and
`weapons_allowed` absent = everything fits), `overcharge_core` (utility, `effect: "overcharge"`),
`shock_prod` (kind `prod`), `tesla_arc` (kind `arc`), `drill_lance` (kind `drill`), `twin_saw`
(kind `saw`, `blades: 2`), `napalm_cannon` (kind `flame`, `ranged: true`), `vortex_spinner` (kind
`fbs`, `lift: true`, `requires_chassis` absent but `weapons_allowed` on `shell` and `apex` list it).
Swift's `Catalogue` reads `kind`, weights, reach, `height_band`, `spin_up_s`, `reset_s`, `impulse`,
`impulse_bonus`, `dps`, `charges`, `fuel_s`, `disrupt_s`, `clamp_force`, `requires_chassis`,
`blurb` for weapons; `wheels`, `tracks`, `top_speed`, `turn_rate`, `push_force`, `traction`,
`wheel_loss`, `strafe`, `late_unlock`, `blurb` for drives; new keys are fine (Swift ignores what it
does not know) but every entry MUST carry the keys the existing entries of its kind carry.

## Series and Level (A)

`CareerState` gains stored properties with defaults (lightweight migration): `levelPoints: Int = 0`,
`seriesIndex: Int = 0`, `matchIndex: Int = 0`, `attempts: Int = 0`, `campaignComplete: Bool = false`,
`replaySeriesIndex: Int = -1`, `replayMatchIndex: Int = -1` (a replay in progress, else -1),
`paintJobsSeen: [String] = []`. Computed: `levelState: LevelState`, `seriesProgress: SeriesProgress`,
`level: Int`. `blueprints` stays the name of the OWNED list (starting loadout + purchases) so the
builder's `CareerUnlocks.held` keeps working. `tier` becomes a computed property derived from
`seriesIndex` (setter writes `seriesIndex`), so every existing caller keeps compiling.

Retired from the flow (types may remain for decoding old saves): entry fees, purses, the bracket,
`SeasonTally`, `NextFight` (replace its two callers, `MenuView` and `CareerHomeView`, with
`NextMatch`; `CareerFightView` takes `NextMatch`), blueprint drips, `winsThisTier`.

`CareerStore` (A) gains:

```
static func settleMatch(state:, bot:, next: NextMatch, result: FightResult?, resultJSON: String, in:) -> (report: MatchReport, rewards: Rewards?)
    // writes the FightLog, carries the damage home (win or lose), banks scrap + points on a win,
    // advances matchIndex / seriesIndex / campaignComplete, resets or bumps attempts, records the rival
static func buy(_ partID: String, state:, in:) -> Bool          // price + level + wall + scrap checks
static func startReplay(state:, seriesIndex:, matchIndex:, in:)   // campaign complete only
static func cancelReplay(state:, in:)
static func repair(_:bill:state:in:)                            // unchanged
```

`ProgressionEngine` (A, the stub's signatures are the contract) is pure; the self test
(`-careerSelfTest`) scripts a whole 20-match campaign through it and asserts: Level 100 on the
last final with no flawless wins; every ladder id exists in the catalogue (a WARNING, not a
failure, until D1/D2/E land, then a failure); a player who wins every match with base + half the
damage bonus + survivor can afford every brief-named part within two wins of reaching its Level;
a loss banks nothing and bumps attempts; the seed differs per attempt; old-save migration; the
free game cannot buy above `free_level_cap`; no em dash in any string.

## Fight config (B1 sends, C reads)

`rules.scrap` = `ScrapRules.asDictionary` (`base`, `damage_full`, `survivor`, `survivor_min`,
`flawless`) on every CAREER match. Absent on quick fights, events, the test arena and the ladder.
`seed` = `next.seed(careerSeed:)`. The rest of the config (enforcer, ai_skill, temperament,
duration_s 180) is unchanged from wave G.

## FightResult v2 (C builds, A decodes into `MatchReport`)

Additive on v1; `schema` stays 1 (Swift tolerates missing keys). New top-level keys, ALWAYS present:

```
"hits":            { bot_id: {"landed": int, "taken": int} }        # weapon hits, from the tallies
"parts_lost":      { bot_id: [ {"part": "wheel_2", "label": "Rear left wheel", "state": "destroyed" | "disabled"} ] }
"condition_start": { bot_id: condition dict as the config's damage block }
"scrap_breakdown": { bot_id: {"base", "damage", "survivor", "flawless", "total"} }   # all zero when rules.scrap absent
```

`scrap[bot_id]` (v1) = `scrap_breakdown[bot_id].total` when `rules.scrap` is present, else the
legacy bolt scrap, so every existing reader keeps working. Labels in `parts_lost` are the words a
player reads ("Weapon", "Front armour", "Drive", "Rear left wheel"); `state` is `destroyed` at zero
condition, `disabled` for a weapon jammed/cooked or a drive at zero while the part is still on.

Live tally (C): while `rules.scrap` is present the HUD scrap bug shows `base + damage so far`; the
survivor and flawless lines are decided at the bell. The damage fraction is
`1 - condition_total(opponent now) / condition_total(opponent at start)` clamped 0..1, using
`Rules.condition_total`. Bolts keep spawning and keep their legacy value in `scrap_awarded` for
the fx, but they no longer add to the tally when `rules.scrap` is present. Pure helpers in
`rules.gd`: `damage_fraction(start, now)`, `survivor_bonus(rules, start, now)`,
`flawless_bonus(rules, won, now)`, `scrap_breakdown(rules, ...)`; `scrap_test.gd` covers them
and a headless fight proves `scrap[bot] == breakdown.total`.

## Views (B1 builds, B2 wires)

The stubs in `MatchReportView.swift`, `RewardsView.swift`, `RetryPromptView.swift` and
`ShopView.swift` carry the exact initialisers. B2's `CareerRootView` (in `CareerHomeView.swift`)
owns the flow: fight -> `CareerStore.settleMatch` -> `MatchReportView` -> (`RewardsView` |
`RetryPromptView`) -> the Series screen. B1 never touches `CareerHomeView.swift`; B2 never touches
B1's three files. If either needs a parameter the other does not have, add it with a default value
and write it here.

## Paint (G)

`bots[i].paint`: a paint job id or absent. `Arena/bot/livery.gd` turns (livery colour, paint id)
into the material `part_visuals.gd`'s livery section applies. Textures: `Arena/assets/textures/
paint/<id>_albedo.png` (1024, tileable, greyscale-with-alpha overlay composited over the livery
colour, so one texture serves every colour) plus a normal map where the pattern is embossed.
Swift previews `Art/paint/<id>.png` (512 square). Unlock: `level >= paint_jobs[n].level`, free.

## Rules for every agent

- Read `docs/brief-v5-progression.md` in full, `docs/design-system.md` (UI agents), this file, and
  the notes files of the agent that last touched your area (`docs/wave-*-notes.md`) before editing.
- **Owner is at the Mac.** Headless only: `--headless` on every Godot run, never `open`, never
  `afplay`/`say`, never a Simulator window, never a sound. UI agents may take headless Simulator
  screenshots on `A18A1779-2368-4FFF-9195-1523D4ABA146` ONLY inside the mkdir lock
  `/tmp/roboteer-sim.lock` (boot, screenshot, `simctl shutdown`, release), volume forced to 0
  before every launch (`xcrun simctl spawn <udid> defaults write com.radicraft.roboteer settings.volume -float 0`),
  launch args `-godotDriver dummy -godotMethod dummy -godotDisplay headless`.
- Swift builds ONLY through `scripts/build-sim.sh` (Debug, simulator) or `scripts/build-device.sh`
  (Release, device); both take the shared lock and may wait. Never delete DerivedData, never touch
  `~/Build`, never run `xcodebuild` any other way. New Swift files need a `project.pbxproj` entry:
  copy the pattern of `ProgressionTypes.swift` (four lines, ids `AA000000000000000000Exx1/2`, pick an
  unused xx) with a script, never by hand.
- Godot suite: `scripts/test-arena.sh <your files>` often, the whole suite before you finish, green.
  Add tests for everything you add. Determinism is a hard rule: no `randf()`/`randi()` outside the
  passed rng, no wall clock in simulation code.
- Do not commit. No `git stash`, `git checkout`, no touching another agent's files. Before your
  final report run `find . -name '* 2.*' -not -path './.git/*'` and delete any iCloud duplicates.
- Every user-facing string: plain sentences, no em dashes, no exclamation marks, and the words
  "tier", "circuit", "season" and "bracket" never appear on screen (it is "Series N").
- Production bar (brief §1): no placeholder art, no stub systems, no TODO left in a shipped path.
  If something cannot be finished, say so in your notes file, do not fake it.
- Write `docs/wave-p-<agent>-notes.md`: what you built, what you measured, what you could not
  verify without a phone, and the dials the owner can turn.
