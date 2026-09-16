# Wave G contracts

The shared surface between the six gameplay agents of brief v4 (`docs/brief-v4-playtest.md` §8).
An agent may ADD to the surface it owns; it may not change a name or a type here without
writing the change into this file first. Everything else an agent touches is in its own files.

## Ownership

| Agent | Owns outright | Owns a SECTION of a shared file |
|---|---|---|
| G1 fight shape | `Arena/fight/fight_types.gd`, `Arena/fight/rules.gd`, every `Arena/arena/*.gd` and `.tscn`, `Arena/tests/rules_test.gd`, `Arena/tests/arenas_test.gd`, Swift `FightConfigFixture.swift`, `ArenaHost.swift` (duration default + `fightPhase`), `Arena/tests/fight_shape_test.gd` (new) | `fight.gd`: the clock, `_set_state`, phase plumbing, the endgame moment; `hud.gd`: clock and the ENDGAME sting |
| G2 house bots | `Arena/ai/boss_ai.gd`, `Arena/arena/corner_zone.gd` (new), `Arena/tests/enforcer_test.gd` (new or existing), Swift `QuickFight.swift` toggle, `CareerEngine.houseBot(...)` + its self-test case | `fight.gd`: the enforcer section (`# --- the enforcer` to the end of its functions); `hud.gd`: zone warning |
| G3 AI | `Arena/ai/opponent_ai.gd`, `Arena/tests/ai_test.gd`, `Shared/parts.json` (`temperament` keys only), `Arena/ai/novice_driver.gd` (new, test-only) | nothing shared |
| G4 camera | `Arena/ui/camera_rig.gd`, `Arena/tests/stage_camera_test.gd`, `Arena/tests/camera_track_test.gd` (new) | nothing shared; G1 calls `endgame_reveal()` |
| G5 career | `CareerHomeView.swift`, `BracketView.swift`, `ScoutingView.swift`, `CareerFightView.swift`, `ResultSheet.swift`, `CareerStore.swift`, `CareerSelfTest.swift` (adds cases), `CareerModels.swift` if needed | `CareerEngine.swift` (G2 adds one static; coordinate through this file) |
| G6 commentary and cues | the audio director script (find it: `grep -rln AudioStreamPlayer Arena --include='*.gd'`), new cue assets under `Arena/audio/`, `Arena/tests/commentary_test.gd` (new) | `hud.gd`: commentary section; `fight.gd`: a commentary hooks section that only CALLS into G6's own script from existing damage/rules event points |

Shared files (`fight.gd`, `hud.gd`, `CareerEngine.swift`): edit with small targeted replacements
only, re-read the region right before each edit, never rewrite the file, never reformat or
reorder anything outside your section. Two agents editing the same file at once is expected.

## Constants (G1 owns, everyone reads) in `FightTypes`

```
const FIGHT_DURATION_S := 180.0      # default when rules.duration_s is absent
const ENDGAME_AT_S := 120.0          # fight time at which the endgame begins
const PHASE_OPEN := "open"
const PHASE_ENDGAME := "endgame"
```

The fight duration ALSO comes from the host: `fight_config.rules.duration_s` (Swift sends it from
`CareerFightView.swift` rules dict and `FightConfigFixture.swift`). G1 changes those to 180 for
mode `fight`; Rumble stays 90; side events keep their own clocks. `ArenaHost.clockSeconds`
default becomes 180. Endgame exists only for `rules.mode == "fight"`; never for rumble or events.

## Phase (G1)

- `fight.gd`: `func fight_phase() -> String` (PHASE_OPEN until `ENDGAME_AT_S`, then PHASE_ENDGAME; PHASE_OPEN outside FIGHTING).
- `fight.gd`: `signal phase_changed(phase: String)`, emitted once when FIGHTING starts (open) and once at the endgame tick. Deterministic: derived from `_tick`, never from wall time.
- Bridge: every `fight_state` send carries `"phase"`; the endgame tick sends `{"state": "fighting", "phase": "endgame"}` once. Swift `ArenaHost` publishes `fightPhase: String`.
- At the endgame tick G1 does, in this order: `_arena.call("set_phase", PHASE_ENDGAME)`, `_camera_rig.call("endgame_reveal")` if it has the method, `_hud.call("show_endgame_sting")`, emit `phase_changed`. Haptic heavy transient through the existing haptics path. G6 connects to `phase_changed` for the horn and the music cue; G2 for the release.
- `ArenaBase.set_phase(phase: String) -> void`: base implementation stores `_phase` and exposes `func phase() -> String`; each arena overrides to escalate per brief §2. Seeded timers from `_seed_hazards` keep running in the open phase; the escalation replaces them at the endgame.
- Judges: `JUDGE_AGGRESSION_FULL_S` 90, `JUDGE_CONTROL_FULL_S` 30.

## Corner zone and house bot (G2)

- `rules.enforcer` (existing): the boss id, or "" for none. New: `rules.enforcer_mode`: `"zone"` (default when `enforcer` is set: guards the zone, idle rule, released at the endgame), `"idle_only"` (the old behaviour, for existing tests), `"off"`. New: `rules.enforcer_speed`: float, default 1.0, Scrapyard 0.5.
- `Arena/arena/corner_zone.gd`: a Node3D the enforcer section adds under the arena node. `func zone_rect() -> Rect2` (floor XZ, metres), `func contains(position: Vector3) -> bool`, `func set_zone_state(state: String)` with `"idle" | "alert" | "released"` changing the marking colour. Position: the existing `_gate_position()` corner, 2.2 m square, inset from the walls by 0.3 m.
- Release rule, targeting, no-KO, self-righting: brief §3.
- `hud.gd`: `func set_zone_warning(on: bool, name: String)`.
- Swift: `CareerEngine.houseBot(tier: CareerTier, arena: String) -> (id: String, speed: Double)` per brief §3 and §10; `CareerFightView` (G5) puts it in the rules dict. `QuickFight` gets a house bot toggle defaulting to on above Scrapyard.
- The house bot's damage is credited to the last toucher inside `Rules.TOUCH_CREDIT_S` (existing rule), so it must report damage events like a hazard does.

## AI (G3)

- `OpponentAI.new(rng, mode, skill: String = "regional", temperament: String = "brawler")`. The shell sends `bots[i].ai_skill` and `bots[i].temperament` in the fight config (G3 documents the two keys here; G5 sends them for career fights, `QuickFight` sends the tier's skill).
- Skill ids = the tier ids: `scrapyard, regional, national, championship, masters`. Temperaments: `brawler, technician, bully, opportunist, showboat`.
- The rng draw ORDER per tick is unchanged (player driver first, then opponent). Any new randomness draws from the same rng in a fixed place. Replays stay bit-exact (determinism_test must pass).
- `ctx` (from `_ai_context()`) gains, from G2: `house_bot_position: Vector3`, `zone_rect: Rect2`, `phase: String`. G3 reads them if present and tolerates their absence.

## Camera (G4)

- `MODE_FIGHT` tracks the player per brief §5. `func endgame_reveal() -> void`: 0.6 s pull-back to the arena fit, 0.8 s return, no input needed. `set_targets(a, b)` keeps its signature: `a` is the player.
- Headless test: player driving a square with the opponent 6 m away stays inside the centre 60 % of the frame.

## Commentary and cues (G6)

- `hud.gd`: `func push_commentary(text: String) -> void`, one plain outlined line above the names for now, 1.6 s hold, 0.25 s fade, a queue that drops lines older than 2 s, nothing during the countdown.
- Lines and triggers per brief §10 item 2. Triggers come from existing points in `fight.gd` (damage events, pin detection, zone entry via G2's `set_zone_warning`, pit open via `set_phase`, house bot release via G2, flips via the inversion check, spin-up via the weapon state). G6 adds a small `_commentary_hooks` section in `fight.gd` that calls its own `Commentary` script; it does not restructure anything.
- Audio: an endgame horn (one shot) and a music cue switch at `phase_changed("endgame")`; the countdown and bell are untouched. NO audio is played on this Mac during development: numeric checks only (stream loaded, player started, bus levels).

## Rules for every agent

- Read `docs/brief-v4-playtest.md` in full and your section of this file before touching anything.
- Headless only. No Godot windows (`--headless` always), no Simulator, no `open`, no `afplay`, no `say`, no sound of any kind: the owner is working at this Mac.
- Run `scripts/test-arena.sh <your test files>` often and the whole suite before you finish; it must be green. Add tests for everything you add.
- Swift compiles are serialised through `scripts/build-device.sh` (it takes a lock; it may wait for another agent). Do not run `xcodebuild` any other way and never delete DerivedData or touch `~/Build`.
- Do not commit. Do not run `git stash`, `git checkout`, or anything that changes another agent's files. Before your final report run `find . -name '* 2.*' -not -path './.git/*'` and delete any iCloud duplicates you caused.
- Determinism is a hard rule: no `randf()`/`randi()` outside the passed rng, no wall-clock in simulation code.
- Write `docs/wave-g-<agent>-notes.md`: what you built, what you measured, what you could not verify without a phone.
- Your final report: the files you changed, the tests you added and their result, the exact list of things the owner should feel on the phone, and anything left undone.
