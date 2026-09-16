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
mode `fight`; Rumble stays 90; side events keep their own clocks. Endgame exists only for
`rules.mode == "fight"`; never for rumble or events.

**Amended 2026-09-16 by G1 while building it.** The line above used to end "`ArenaHost.clockSeconds`
default becomes 180". It does not, and must not: the only `clockSeconds` in `ArenaHost.swift` is the
default argument of `startEvent(...)`, which is a SIDE EVENT's clock, and brief v4 §2 and §10 item 3
both say the side events are untouched (every real caller passes `EventCatalogue.clockSeconds`
anyway). The host's half of the fight duration lives in `FightConfigFixture.fightDurationS` (180) and
`CareerFightView.fightDurationS` (180) instead, and `ArenaHost` gained `fightPhase` as agreed.

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
- `hud.gd`: `func set_zone_warning(on: bool, name: String)`. BUILT, plus `show_zone_coach()` (the one coach line), `zone_step(delta)`, `zone_warning_visible()`, `zone_warning_name()`, `zone_coach_visible()` for the headless test. It draws on its own overlay, so nothing else in `hud.gd` moved.
- BUILT beyond the above: `CornerZone.centre(y) -> Vector3` (the mark), `zone_state()`, `marking_colour()`, static `rect_in_corner(corner, half_extent) -> Rect2`; `Fight.enforcer_heading_step(previous, want, speed, delta) -> Vector2`, the pure speed limiter (drive and turn, never the weapon). `rules_test.gd`'s `_test_enforcer()` now asks for `"enforcer_mode": "idle_only"`, which is what that mode is for.
- Swift: `CareerEngine.houseBot(tier: CareerTier, arena: String) -> (id: String, speed: Double)` per brief §3 and §10; `CareerFightView` (G5) puts it in the rules dict. `QuickFight` gets a house bot toggle defaulting to on above Scrapyard.
- The house bot's damage is credited to the last toucher inside `Rules.TOUCH_CREDIT_S` (existing rule), so it must report damage events like a hazard does.

## AI (G3)

- `OpponentAI.new(rng, mode, skill: String = "regional", temperament: String = "brawler")`. The shell sends `bots[i].ai_skill` and `bots[i].temperament` in the fight config (G3 documents the two keys here; G5 sends them for career fights, `QuickFight` sends the tier's skill).
- Skill ids = the tier ids: `scrapyard, regional, national, championship, masters`. Temperaments: `brawler, technician, bully, opportunist, showboat`.
- The rng draw ORDER per tick is unchanged (player driver first, then opponent). Any new randomness draws from the same rng in a fixed place. Replays stay bit-exact (determinism_test must pass).
- `ctx` (from `_ai_context()`) gains, from G2: `house_bot_position: Vector3`, `zone_rect: Rect2`, `phase: String`. G3 reads them if present and tolerates their absence.

**The two fight-config keys (G3, landed 2026-09-16).** Both live on the bot entry, beside
`controller` and `build`, and both are optional:

```
bots[i].ai_skill     String, one of the five tier ids. Absent or unknown -> "regional".
bots[i].temperament  String, one of the five temperament ids. Absent, "" or "random" ->
                     the driver DRAWS one from the shared rng at construction, which is
                     what a career filler gets. A rival sends its own, for life.
```

`Shared/parts.json` now carries a fixed `"temperament"` on each of the eight rivals
(beside their existing `"personality"` prose): clatterbox showboat, penny_dread bully,
scuttle technician, hob_nail brawler, cold_snap opportunist, brass_neck bully, marrow
technician, tollgate brawler. `Arena/data/parts.json` is the byte-identical copy
(`assembly_test` checks it). G5 reads the key for career fights; anything that does not
send it gets a drawn temperament, which is deterministic per seed.

`fight.gd` (G1's file, two lines changed by G3 with a targeted edit): `_make_driver` takes
a third argument, the bot's config dictionary, and `_arm` passes `bot_config_at(config, 1)`
for the opponent and `bot_config_at(config, 0)` for the player ghost.

**Two more `ctx` keys (G3), added to `_ai_context()` after G2's three:**

```
time_left_s    float, always present: the fight clock, for the last-twenty-seconds switch
judge_points   Dictionary bot_id -> float, present ONLY while time_left_s <= 20.0:
               Rules.score_total(Rules.judge_scores(tally)) per bot
```

Both are derived from state fight.gd already keeps, so neither draws from the rng and
neither costs anything outside the last twenty seconds. A driver tolerates their absence
(it falls back to comparing the two machines' condition).

## Camera (G4)

- `MODE_FIGHT` tracks the player per brief §5. `func endgame_reveal() -> void`: 0.6 s pull-back to the arena fit, 0.8 s return, no input needed. `set_targets(a, b)` keeps its signature: `a` is the player.
- Headless test: player driving a square with the opponent 6 m away stays inside the centre 60 % of the frame.

**Amended 2026-09-16 by G4 while building it.** Nothing above changed; these are the additions and
the one removal, so nobody is surprised by a name that moved.

- New on `CameraRig`, all presentation-only and safe to call from anywhere: `is_revealing() -> bool`,
  `reveal_blend() -> float` (0 tracking, 1 the full pull-back) and `look_lead() -> float` (the metres
  of lead the aim is carrying, never above `LOOK_LEAD_MAX_M`). `endgame_reveal()` is a no-op outside
  `MODE_FIGHT` and restarts rather than stacks, so G1 may call it without guarding.
- New constants: `LOOK_LEAD_FRACTION` 0.25, `LOOK_LEAD_MAX_M` 1.2, `PLAYER_FRAME_LIMIT` 0.30 (the
  brief's rule), `PLAYER_LEASH_LIMIT` 0.25 (what the aim is actually held to, the slack covering the
  chassis height and the impact shake), `TRACK_PAIR_RANGE_M` 4.0, `REVEAL_OUT_S` 0.6, `REVEAL_BACK_S` 0.8.
- **Removed:** `CameraRig.PLAYER_LOOK_WEIGHT`. Brief v4 §5 replaces the weighted-midpoint aim with
  player-plus-lead, so the constant had no meaning left. Its only two users outside the rig were two
  checks in `Arena/tests/ui_test.gd` (`_test_bot_framing`), which G4 rewrote in place to assert the
  lead rule instead. `look_weight()` stays and now reports the player's share of the aim derived from
  the lead actually used (1.0 down to 1 - `LOOK_LEAD_FRACTION`). `ui_test.gd` belongs to V2 in wave V;
  no wave-G agent owns it, and nothing else in the repo referenced the constant.
- `is_player_floored()` keeps its name and its meaning for the HUD ("the opponent may be off the edge
  of the frame, draw the arrow"), but it is now true whenever the camera is HOLDING: either the
  opponent is past `TRACK_PAIR_RANGE_M` or the `PLAYER_MIN_FRACTION` floor is binding, which is the same
  thing it always meant to the HUD. `docs/bridge-spec.md`'s "Default fight framing" section described the
  old midpoint aim as current, so G4 corrected that paragraph in place (and the stale "yaw 45" in it).

## Commentary and cues (G6)

- `hud.gd`: `func push_commentary(text: String) -> void`, one plain outlined line above the names for now, 1.6 s hold, 0.25 s fade, a queue that drops lines older than 2 s, nothing during the countdown.
- Lines and triggers per brief §10 item 2. Triggers come from existing points in `fight.gd` (damage events, pin detection, zone entry via G2's `set_zone_warning`, pit open via `set_phase`, house bot release via G2, flips via the inversion check, spin-up via the weapon state). G6 adds a small `_commentary_hooks` section in `fight.gd` that calls its own `Commentary` script; it does not restructure anything.
- Audio: an endgame horn (one shot) and a music cue switch at `phase_changed("endgame")`; the countdown and bell are untouched. NO audio is played on this Mac during development: numeric checks only (stream loaded, player started, bus levels).

**Built 2026-09-16 by G6. The surface, for V2 (who redraws `hud.gd`) and for anyone adding a line.**

- `hud.gd`: `push_commentary(text)`, `commentary_step(delta)` (driven from the HUD's own `_process`), `clear_commentary()`, and for tests `commentary_text()`, `commentary_visible()`, `commentary_alpha()`, `commentary_queued()`. Constants `COMMENTARY_HOLD_S` 1.6, `COMMENTARY_FADE_S` 0.25, `COMMENTARY_GAP_S` 2.0, `COMMENTARY_STALE_S` 2.0. The label is built on demand and places itself (`_place_commentary`), so it adds nothing to the shared `_relayout()`. It sits on the third row under the clock: today the names are a TOP band, so "above the names" is impossible; when wave V moves them to lower thirds this strap is the ticker above them.
- `Arena/fight/commentary.gd`: `class_name FightCommentary extends RefCounted`. `bind(hud, audio_mix)`, `reset(arena_id, bots)`, `note_damage(info)`, `note_pin(index, pinned)`, `note_zone(on, name)`, `note_house_bot_out()`, `on_phase_changed(phase)`, `step(delta, facts)`, plus `said()` / `said_count(line)` for tests. To add a line: a `LINE_` constant, a `REPEAT_S` entry, and a trigger. **`note_house_bot_out()` is the hook G2 owns**: it is already called from `_release_house_bot` and from the Stage 5 `_send_in_enforcer` entrance.
- `Arena/fx/audio_mix.gd`: `play_endgame_horn()`, `set_endgame(on)` (drone on the Music bus + Ambience `AMBIENCE_HOT_DB` hotter, reversible to whatever level it found), `endgame_active()`. New sounds `endgame_horn` and `endgame_drone_loop`; `stop_all()` now clears the endgame first.
- BIG HIT is `FightFx.IMPACT_HEAVY_SEVERITY` **by reference**, so the line can never disagree with the impact sample the player just heard. Measured rates and the rest: `docs/wave-g-g6-notes.md`.

## Rules for every agent

- Read `docs/brief-v4-playtest.md` in full and your section of this file before touching anything.
- Headless only. No Godot windows (`--headless` always), no Simulator, no `open`, no `afplay`, no `say`, no sound of any kind: the owner is working at this Mac.
- Run `scripts/test-arena.sh <your test files>` often and the whole suite before you finish; it must be green. Add tests for everything you add.
- Swift compiles are serialised through `scripts/build-device.sh` (it takes a lock; it may wait for another agent). Do not run `xcodebuild` any other way and never delete DerivedData or touch `~/Build`.
- Do not commit. Do not run `git stash`, `git checkout`, or anything that changes another agent's files. Before your final report run `find . -name '* 2.*' -not -path './.git/*'` and delete any iCloud duplicates you caused.
- Determinism is a hard rule: no `randf()`/`randi()` outside the passed rng, no wall-clock in simulation code.
- Write `docs/wave-g-<agent>-notes.md`: what you built, what you measured, what you could not verify without a phone.
- Your final report: the files you changed, the tests you added and their result, the exact list of things the owner should feel on the phone, and anything left undone.
