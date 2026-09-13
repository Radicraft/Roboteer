# Stage 3 rules notes (agent R)

What the fight orchestrator does, what it assumed about the other agents' code, and how to
run it. Companion to `docs/stage3-spec.md` §7, §8, §9 and §14, which stay the authority.

Files: `Arena/fight/fight.tscn` + `fight.gd`, `rules.gd`, `result_builder.gd`,
`replay_recorder.gd`, `placeholder_hud.gd`, `fixtures/stage3_config.json`,
`Arena/ai/opponent_ai.gd`, `Arena/tests/{rules,ai,determinism}_test.gd`,
`Arena/project.godot`, `scripts/test-arena.sh`.

## The state machine

`LOADING` -> `COUNTDOWN` -> `FIGHTING` -> `RESULT`, one way, no going back.

| state | what runs | what leaves over the bridge |
|---|---|---|
| LOADING | `Bridge.message_received` connected; `arena_ready` sent as soon as a host attaches; frames counted for the desktop auto start | `arena_ready` |
| COUNTDOWN | 3 s. Both bots get an empty input every tick so they settle but cannot drive. The controls' edge triggered fire is drained each tick so a tap during "3, 2, 1" does not fire on the bell. FX gets `on_countdown(step)`. | `fight_state {"state":"countdown"}` |
| FIGHTING | the whole tick order below, 90 s or until a win condition lands | `fight_state {"state":"fighting"}` |
| RESULT | both bots frozen, controls disabled, camera rig told to orbit the loser's wreckage, FX rings the bell | `fight_state {"state":"result"}` then `fight_result` once |

`fight_result` is sent exactly once per fight; `_result_sent` guards it.

### Re-arming, and the duplicate send

The shell keeps ONE Godot process for the life of the app and sends a fresh `fight_config`
on every tap of "Fight", including straight after a result (`docs/stage3-swift-notes.md`).
It also resends the same configuration once if no `fight_state` came back within 3 s, and
**two sends of one configuration must never produce two fights**.

| state when `fight_config` arrives | what happens |
|---|---|
| LOADING | starts the fight |
| RESULT | tears the previous fight down and starts the new one |
| COUNTDOWN or FIGHTING | ignored, with an `arena_log` warn naming the state |

`start_fight` sets the state to COUNTDOWN synchronously, so two configs arriving in the
same frame cannot race: the second one already sees COUNTDOWN. A config that fails schema
validation is refused without disturbing a fight that is already running. `_fights_run`
counts the fights this process has started, and `rules_test.gd` drives all of this through
the real `Bridge.inject_from_host` seam.

### A fresh World3D for every fight

`start_fight` calls `_build_world()` first, every time, including for the first fight.
That frees the previous `SubViewport` and instantiates `res://fight/fight_world.tscn`,
which is a `SubViewport` with `own_world_3d = true` holding `Arena`, `Bots`, `Debris`,
`CameraRig` and `FX`. So every fight gets its own `World3D` and its own physics space, and
fight 1 and fight 7 are built exactly alike.

The scene tree is therefore:

    Fight (Node3D, fight.gd)          lives for the process
    +-- Stage (SubViewportContainer)  full rect, stretch, mouse_filter ignore
    |   +-- World (SubViewport)       REBUILT for every fight, own_world_3d
    |       +-- Arena, Bots, Debris, CameraRig, FX
    +-- HUD (CanvasLayer)             lives for the process
    +-- Controls (Control)            lives for the process

`Stage` has `mouse_filter = ignore` and the `SubViewport` has `handle_input_locally =
false`, so the container never swallows or re-routes a touch. `FightControls` reads raw
`_input` on the root viewport and keeps working untouched; the camera rig, which lives
inside the world, gets its gestures from the controls' `camera_pinch` / `camera_orbit`
signals through `bind_controls`, not from raw input, so nothing has to cross the viewport
boundary. The HUD is a `CanvasLayer` and draws over the stage.

### The FIGHTING tick, in order

Everything below happens inside `_physics_process`, which Godot calls **before** it
integrates the step, which is what we want: the inputs applied this tick are the inputs the
step runs with.

1. `_tick += 1`, `_fight_time += delta`
2. `_fill_opponent_relative()` on both bots (so the bot and the AI see this tick's geometry)
3. sample the player's controls **once** into one input record (or read the row back from
   the replay recorder when a scripted list is playing)
4. `OpponentAI.think()` for the opponent's record
5. `apply_input` on both bots
6. append the player's record to the replay log
7. `_time_left -= delta`
8. update the judges' tallies
9. win conditions, in order: out of the arena, component kill, knockout, then the bell

Presentation never runs here. HUD strings, FX forwarding, controls enable/disable and the
camera all happen in `_process`, reading state the physics tick already wrote. Damage
events are queued in the physics tick and flushed to FX in `_process`; `scrap_awarded` is
the one signal emitted from the physics tick, because agent B's FX connects to it and the
spec asks for it there.

## Win conditions

1. **Knockout.** `bot.is_immobile()` accumulates `_ko_count[i]`; any moving tick resets it
   to zero. At `rules.ko_count_s` (10 s from the config) the other bot wins. The HUD shows
   the remaining count and FX plays a `ko_tick` per whole second.
   **A pinned bot is not knocked out.** While a bot is within 1.0 m of its opponent and
   asking for drive (heading length above 0.2), its count **freezes**: it does not advance
   and it does not reset (`FightRules.is_pinned`, and the `pinned` argument to
   `ko_count_next`). A shoving match is a bot being held, not a bot that has stopped
   fighting, and the desktop QA build was showing "KNOCKOUT COUNT 8" over a bot whose
   wheels were turning the whole time. An **inverted** bot is never pinned, because spec
   §8 says an inverted bot that cannot self-right counts down too, and a bot stuck on its
   back beside its opponent is exactly what that rule is for. `fight.gd` remembers the
   heading each bot was actually given (`_last_heading`) so the rule sees the real input,
   not the stick.
2. **Out of the arena.** The yard's `body_out` signal is authoritative. A positional
   fallback (`FightRules.is_out_of_arena`) runs every tick as well, so a bot that clears the
   sensor at speed, or a run with no yard scene, still resolves. Immediate.
3. **Judges.** At 0:00, `FightRules.judge_scores` turns each bot's tally into a card of
   three whole numbers 0..10 using `FightTypes.JUDGE_*`. Higher total wins, tie goes to
   damage, then to aggression. Two further tiebreaks keep it deterministic rather than
   arbitrary: the unrounded totals, then config order. Scores are integers because
   `docs/bridge-spec.md`'s FightResult example shows integers and Swift decodes them as such.
4. **Component kill.** `condition().core <= 0`.

`outcome.type` is `ko | out_of_arena | judges | component_kill`. `timeout` exists in the
result builder as the default but nothing produces it.

## The tallies, and attribution

Per bot: `damage_removed`, `aggression_s`, `weapon_hits`, `control_s`
(`FightRules.empty_tally`).

- **damage_removed** accumulates the `severity` of every `damage_event` credited to that
  bot. It is not a before/after diff of `condition()`, because a diff cannot say who did it.
- **aggression_s** accumulates a tick of `delta` whenever the bot is inside 1.5 m of its
  opponent and its flat velocity is closing on it (`FightRules.is_aggressive`).
  `weapon_hits` adds 1 (worth one second) per weapon fire that produced damage within
  0.35 s, counted once per fire rather than once per contact that fire caused.
- **control_s** accumulates while the opponent is airborne, inverted or standing on the
  spike patch, and this bot touched it less than 2 s ago (`FightRules.is_controlling`).

### The last toucher

Hazard damage arrives with `attacker: "arena"`. `FightRules.hazard_credit` gives it to
whichever bot last touched the victim inside 2 s, and to nobody after that. The "touch"
fact is written from two places: any `damage_event` where the attacker is a bot, and any
tick where the two chassis are within 2 m of each other. The proximity half matters
because a clean shove onto the spikes produces no damage event of its own, and that shove
is exactly the play the control score is meant to reward.

Scrap uses the same credited attacker: `FightTypes.scrap_for(severity, detached)`, banked
into `_scrap[i]` and announced as `scrap_awarded(bot_id, amount, position)`. The bolt
shower only visualises scrap that is already banked (brief §6).

## The AI

`Arena/ai/opponent_ai.gd`, spec §9: hold off, circle for an angle, dart in, strike, back
off, recover, avoid the spikes, jitter.

**Movement.** Outside 1.75 m it closes on a 1.4 m ring around the opponent, aiming at the
flank it has chosen rather than at their nose. On the ring it checks its approach angle:
more than 50 degrees off the opponent's facing is a side or rear attack and it darts
straight in, otherwise it drives tangentially around the ring, correcting the radius, until
the angle comes good. A dart is committed to (it is not re-decided every tick) until the
angle is lost past 78 degrees or the range opens past 2.2 m, so it does not dither on the
way in. The flank side is held until the bot is well past the opponent's midline, so it
commits to a lap instead of flip-flopping across their nose.

**The strike, and the bug it replaced.** It fires when the opponent's chassis centre is
within 1.1 m (0.9 m nose on nose, plus 0.2 m of slack so the flipper starts its sweep as
the wedge bites) and within 45 degrees of its own nose, or whenever `opponent_on_wedge()`
says the opponent is already on the wedge. It used to fire when its *front edge* was within
0.45 m of the opponent's chassis, and that test **inverts in a clinch**: at 0.3 m apart the
front edge is already past the opponent's centre, the vector from edge to chassis points
backwards, and the facing check fails exactly when the two bots are locked together.
Measured: 2322 ticks inside 1 m over 45 seconds and not one shot fired by either bot.

**After a shot** it gives ground until it has opened 0.6 m, or for 0.75 s, whichever comes
first, then re-approaches. Without that the whole tank of gas goes into one clinch.

`opponent_on_wedge()`, `flipper_ready()`, `weapon_jammed()` and `gas_charges` are all read
through `has_method` / `get` with geometry and a local cooldown as the fallback, so the AI
works against whatever version of the Bot API is on disk.

Two things make it deterministic:

- It draws from the shared RNG at a **fixed cadence**: once every 30 ticks, before any
  branching, in every mode including `idle`, and before the movement state machine is
  consulted. No branch can change how many numbers it consumes, so the RNG stream never
  drifts between a fight and its replay.
- It reads only `bot.chassis` transforms and `bot.is_inverted()`. No clock, no frame
  counter, no second RNG.

`debug.opponent_ai` is `normal | idle | charge`.

### Driving the player bot with the AI

`debug.player_ai` is `off` (the default), `normal` or `charge`. When it is not `off`,
`fight.gd` builds a second `OpponentAI` targeting the opponent and uses its record as the
player's input instead of reading the controls. The replay log still records whatever the
player bot actually received, so an AI against AI fight replays like any other.

This is a QA lever now (leave a fight running and watch it, or produce a win condition
without driving) and it is the shape the **async ladder** in brief section 10 needs later:
a ghost build driven by AI against the player, or two ghosts against each other. Both
drivers share the one seeded RNG and think in the fixed order above.

## RNG order

One `RandomNumberGenerator`, seeded from `config.seed`, consumed in a fixed order:

1. the yard (`Yard.setup(rng)`, one draw for the spike phase)
2. the drivers are constructed (no draw)
3. each bot's `setup(bot_config, team_index, rng)`, player then opponent
4. thereafter, every tick, the **player's** driver thinks first and the **opponent's**
   second, each drawing once every 30 physics ticks

Changing this order changes every seeded fight, so treat it as part of the contract.
`ai_test.gd` asserts it by running the same duel with the order swapped and checking the
result differs.

## Desktop QA (spec §14)

With no host attached after 60 frames, `fight.gd` loads
`res://fight/fixtures/stage3_config.json` and runs it exactly as if it had arrived over the
bridge. The fixture is the bridge-spec FightConfig with both bots wedge / 4wd / flipper /
srimech, player armour steel front, hdpe sides, polycarbonate rear, titanium top, opponent
all steel, plus `presentation.safe_area_px` all zero and `debug.opponent_ai: "normal"`.
`debug.player_ai` is absent, which means `off`.

    ~/Applications/Godot.app/Contents/MacOS/Godot --path Arena
    ~/Applications/Godot.app/Contents/MacOS/Godot --path Arena -- --roboteer-ai=idle
    ~/Applications/Godot.app/Contents/MacOS/Godot --path Arena -- --roboteer-ai=charge
    ~/Applications/Godot.app/Contents/MacOS/Godot --path Arena -- --roboteer-player-ai=normal

`--roboteer-ai=idle|charge|normal` overrides `debug.opponent_ai` and
`--roboteer-player-ai=off|idle|charge|normal` overrides `debug.player_ai`, so
`-- --roboteer-player-ai=normal` is a hands off AI against AI fight. Both are read from
`OS.get_cmdline_user_args()` (after a bare `--`) and also from the plain command line.
Only the four known driver names are accepted; anything else is ignored rather than
guessed at.

Keyboard driving is agent C's: `FightControls` folds WASD / arrows / Space / Shift into
`heading`, `consume_fire()` and `secondary` on desktop, so `fight.gd` reads the controls
and nothing else. The keyboard block in `_sample_player_input` only runs when
`controls.tscn` is absent, purely so a bare checkout is still driveable.

`project.godot` also carries `roboteer_*` input actions (WASD and arrows, Space, Shift,
Q/E orbit, R/F tilt, `-`/`=` zoom). Nothing reads them today; they are there so the QA keys
can be rebound without editing code, and because `ui_*` action names are taken.

## Tests

    scripts/test-arena.sh                    every test in Arena/tests, in order
    scripts/test-arena.sh rules_test         one test
    GODOT=/path/to/Godot scripts/test-arena.sh

Individually:

    Godot --headless --path Arena --script tests/rules_test.gd          126 checks
    Godot --headless --path Arena --script tests/ai_test.gd               34 checks
    Godot --headless --path Arena --script tests/determinism_test.gd      28 checks, ~100 s

`rules_test` and `ai_test` need no scene and no physics: the AI is tested against small
duck typed fakes exposing `chassis` and `is_inverted()`. `determinism_test` loads the real
fight scene and prints SKIP, exit 0, if `res://bot/bot.tscn` is absent.

The runner runs the known tests in a fixed order (the bridge contract, the rules, the AI,
then agent C's `ui_test`, agent B's `fx_test`, agent P's `physics_test`, then determinism) and then anything else it finds in `Arena/tests/*.gd`
(files starting with `_` are treated as helpers), so a test cannot be added and silently
never run. Every test runs even when an earlier one fails; the exit code
is 0 only if all of them exited 0.

## Two traps worth keeping

### Two fights in one process did not reproduce each other, twice over

Measured 2026-09-13, and both halves are fixed.

**One: Jolt's body pair contact cache silently drops hits.**
`physics/jolt_physics_3d/simulation/body_pair_contact_cache_enabled` defaults to `true`.
It reuses a cached manifold for a body pair whose relative pose has barely changed, and a
contact served from that cache is **not reported to `_integrate_forces`**. Which contacts
get cached depends on the pair's identity in the physics server, and body RIDs are
recycled: the first fight in a process gets fresh ones, later fights get the first
fight's back. So the first fight in a process saw a different set of contacts from every
later fight. Over a 30 second scripted fight the first run produced 2 damage events and
the second and third produced 3, agreeing with each other but not with the first, while
every chassis transform stayed bit identical (the missing hit was armour damage, which
moves nothing).

It was never only a determinism bug. The cache was **losing real hits**: with it off the
same fight produces 5 damage events instead of 2, and scrap goes from 9 to 26. A player
would have seen a solid hit do nothing.

Fixed in `Arena/project.godot`:

    [physics]
    jolt_physics_3d/simulation/body_pair_contact_cache_enabled=false

Cost: Jolt rebuilds each pair's manifold every step instead of reusing it. With two bots
(about 22 bodies) that did not show up in the headless timings, but it is worth watching
on the phone, and it is the first thing to try turning back on if the physics budget gets
tight. Do not: the damage model would start dropping hits again.

**Two: a fight inherits the space the last fight dirtied.**
Even with the cache off, sharing one `World3D` across fights leaves the space's free lists
and broadphase in a state that depends on what ran before. The fix is structural rather
than a setting: `fight.gd` builds a **fresh `SubViewport` with `own_world_3d = true` for
every fight**, so no fight ever starts from another fight's leftovers. See the re-arming
section above.

`determinism_test.gd` now runs **three** fights on ONE `Fight` node, re-armed with a new
config each time, which is exactly what the shipping app does, and every transform,
condition, scrap tally, replay row and damage event count matches across all three. Three
runs and not two on purpose: every bug here was "the first fight in a process is
different", and two runs can agree by accident where three cannot.

### `class_name` globals need `.godot/global_script_class_cache.cfg`

`Arena/.godot/` is gitignored, and a non editor Godot run never writes that cache. On a
fresh clone every `class_name` global (`FightTypes`, `Bot`, `FightRules`, ...) fails to
resolve and `fight.gd` will not even parse. One `Godot --headless --path Arena --import`
fixes it permanently. `scripts/test-arena.sh` does this automatically when the file is
missing; a bare `Godot --path Arena` does not, so run the import first after cloning.

## Assumptions made about the other agents' APIs

Everything here is guarded (`has_method` / `has_signal` / `ResourceLoader.exists`), so a
wrong guess degrades to a warning rather than a crash. These are the places where the spec
did not say, and `fight.gd` had to choose.

| assumption | where | note |
|---|---|---|
| `Bot.set_opponent_relative(position: Vector3, distance: float)` takes two arguments | `_fill_opponent_relative` | spec §4 only says "filled by R each tick". Falls back to setting the `opponent_relative` property with a `{position, distance}` dictionary. |
| A heading of `Vector2(x, y)` asks for world direction `Vector3(x, 0, y)` | `OpponentAI.heading_from_world_dir` | the one place the mapping lives. If the drive ever reads the stick camera relatively, change that function and nothing else. |
| The bot's nose is `-Z` of `chassis.global_transform.basis` | `OpponentAI._forward` | Godot's usual forward; matches `Yard.spawn_facing` and `Bot.place_at`. |
| The front edge is 0.45 m ahead of the chassis centre | `OpponentAI.FRONT_EDGE_M` | half of the 0.9 m chassis from spec §0. |
| There is no `Bot.is_airborne()` | `Fight._is_airborne` | inferred from the chassis sitting more than 0.12 m above its spawn height. Uses `bot.is_airborne()` the moment P provides one. |
| The HUD readout names the player's **chassis** and the opponent's **weapon** | `Fight.height_readout` | "Your wedge: floor. Their flipper: mid." is spec §10's own example, and that is the only reading of it that produces those two words from this fixture. The bands come from `front_edge_height()` and `weapon_height_band()`. |
| Haptics belong to agent B | `Fight` sends none | `FightFx` owns `FightHaptics` and its 30/s window. The rules call `fx.on_ko_tick()` and `fx.on_bell()` rather than sending `haptic` themselves, so the cap is enforced in one place. |
| `FightFx.bind(hud, get_bot_position)` wants a bot id to position callable | `Fight.bot_position_by_id` | public on purpose; it is the only thing FX holds. |

### The one change made outside R's files

`Arena/bot/bot.gd`, `_debris_root()`. It looked up the absolute path
`/root/Fight/Debris`, which stopped resolving when the fight's 3D world moved inside a
per fight `SubViewport`. It now walks up from the bot for the nearest `Debris` sibling,
which finds the same node in the old layout and in the new one, and still falls back to
`get_parent()`. Nothing else in `Arena/bot`, `Arena/arena`, `Arena/ui` or `Arena/fx` was
touched.

`fight.tscn` ships placeholders for `Arena`, `CameraRig`, `HUD`, `FX` and `Controls`: a grey
floor with a light and an environment, a fallback `Camera3D` at the default 45/50 framing,
and `placeholder_hud.gd`, which answers to the same method names as C's `FightHud`. Each is
replaced at `_ready` by the real scene when its file exists, keeping the spec's node name,
so `/root/Fight/Debris` and the rest stay stable paths. With every other agent's directory
deleted the scene still starts, counts down, times out and sends a judges' result.

## Feel probe numbers (2026-09-13)

`Godot --headless --path Arena --script tests/_feel_probe.gd -- --pai=normal --oai=normal --secs=45`
(the main session's probe; `scripts/test-arena.sh` skips underscore files).

| measure | before the AI rework | after |
|---|---|---|
| weapon fires, player / opponent | 0 / 0 | **8 / 8** |
| damage events | 0 | **36** |
| scrap events / total | 0 / 0 | **35 / 179** |
| gas left | 8 / 8 | 0 / 0 |
| ticks within 1 m (of 2900) | 2322 | 1193 |
| max chassis height | 0.57 / 0.21 m | 1.54 / 1.66 m |
| airborne ticks above 0.45 m | 19 / 0 | 339 / 358 |

Both rear armour plates and one front plate reach 0.0 in 45 seconds, so the whole chain
from a flip through joint failure to detachment to scrap is running end to end. The drop
in "ticks within 1 m" is the point of the rework: the bots break off and come back round
instead of grinding nose to nose for the whole fight.

## Not mine, seen while testing (2026-09-13)

Agent P was still editing `Arena/bot/**` while these tests ran, so treat this as a pointer
rather than a verdict; re-run `scripts/test-arena.sh` once the other agents have settled.

- `Arena/tests/physics_test.gd` (agent P) failed four checks on the build I tested: turn
  rate ("closest 24.9 degrees" against a 15 degree bar), flipper throw height (0.00 m rise),
  top plate damage and top plate detachment.
- The last two came from `part_body.gd` calling `state.get_contact_position(i)`, which does
  not exist on `JoltPhysicsDirectBodyState3D` in 4.6. Every contact threw, so **no damage
  event fired at all** and scrap stayed at zero through a 30 second fight. P has since
  changed it to `get_contact_local_position`, and on the re-run the rules' damage, scrap and
  judges paths came alive: a 30 second scripted fight now banks scrap 9 to 19, identically
  in both determinism runs. The four physics_test failures above still want re-checking.
