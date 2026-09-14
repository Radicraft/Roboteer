extends Node3D
## The fight orchestrator (docs/stage3-spec.md §8). Owns the state machine, the shared
## RandomNumberGenerator, the four win conditions, the judges' tallies, the AI opponent,
## the replay log and the single FightResult that leaves over the bridge.
##
## Determinism discipline (spec §7):
##   - Everything that can change the outcome happens in _physics_process, or in a signal
##     handler that P emits from inside its own _physics_process.
##   - The player's controls are sampled ONCE per tick into an input record, applied to the
##     bot and appended to the replay log. The AI's record is regenerated from the seed.
##   - Presentation (HUD strings, FX forwarding, camera) happens in _process, reading state
##     the physics tick already wrote. It never writes back.
##
## The scene runs with agent P's, C's and B's scenes present or absent: every scene is
## loaded by path behind ResourceLoader.exists and every call into them is guarded, so a
## bare checkout still starts, counts down, times out and sends a result.

const Rules := preload("res://fight/rules.gd")
const ResultBuilder := preload("res://fight/result_builder.gd")
const Recorder := preload("res://fight/replay_recorder.gd")
const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const BossAIScript := preload("res://ai/boss_ai.gd")

const SCHEMA := 1
const FIXTURE_PATH := "res://fight/fixtures/stage3_config.json"

## Scenes owned by the other Stage 3 agents. Missing ones are warned about, not fatal.
const WORLD_SCENE := "res://fight/fight_world.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
## Six arenas, brief §7. The id comes from `config.arena`; the career tier to id mapping
## lives in Swift, not here, because this file only reads the id it is handed.
const ARENA_SCENES := {
	"yard": "res://arena/yard.tscn",
	"grinder": "res://arena/grinder.tscn",
	"drop_zone": "res://arena/drop_zone.tscn",
	"furnace": "res://arena/furnace.tscn",
	"crush": "res://arena/crush.tscn",
	"coliseum": "res://arena/coliseum.tscn",
}
const DEFAULT_ARENA := "yard"
const TEST_ARENA_SCENE := "res://arena/test_arena.tscn"
const STAGE_SCENE := "res://workshop/stage.tscn"
const TEST_OVERLAY_SCRIPT := "res://ui/test_overlay.gd"

## Stage 4 messages (docs/stage4-swift-notes.md). `workshop_config` is answered by the
## stage itself with `workshop_ready`; this file only does the mode switch.
## Host -> arena: {"action": "pause" | "resume" | "quit"} (docs/bridge-spec.md,
## "Fight control (v2 additions)"). Arena -> host: the pad's START button asking for a
## pause, which the shell answers with a `fight_control`.
const MSG_FIGHT_CONTROL := "fight_control"
const MSG_PAUSE_REQUESTED := "pause_requested"

## Host -> arena: a camera gesture the SHELL captured, {"orbit": [dx, dy]} and/or
## {"pinch": factor}, in screen points. Stage screens only: on them the SwiftUI
## navigation container swallows every touch before the Godot view sees it.
const MSG_STAGE_CAMERA := "stage_camera"

const MSG_WORKSHOP_CONFIG := "workshop_config"
const MSG_WORKSHOP_READY := "workshop_ready"
const MSG_TEST_RESET := "test_reset"
## Settings, sent after arena_ready and again on every change (docs/stage4-swift-notes.md).
## Presentation only: nothing here may touch the simulation.
const MSG_SETTINGS := "settings"
## Replays (docs/stage6-spec.md §2). A replay is the same fight re-simulated from the same
## seed and the same input log, so it is the fight, not a recording of it.
const MSG_REPLAY_STATE := "replay_state"
const MSG_REPLAY_CONTROL := "replay_control"
const REPLAY_STATE_EVERY := 10          # ticks between progress messages
## Seeking runs the simulation forward as fast as the engine will take steps, with the
## picture switched off. See _tick_seek for what that costs.
const SEEK_TIME_SCALE := 24.0
const SEEK_MAX_STEPS := 32
const REPLAY_SPEEDS := [0.25, 0.5, 1.0]
const CONTROLS_SCENE := "res://ui/controls.tscn"
const HUD_SCENE := "res://ui/hud.tscn"
const CAMERA_RIG_SCENE := "res://ui/camera_rig.tscn"
const FX_SCENE := "res://fx/fx.tscn"

## Spec §14: with no host attached after this many frames, run the desktop QA fixture.
const AUTOSTART_FRAMES := 60

## The centre spike patch clock, mirrored from spec §5 so the AI can dodge and the judges
## can score control even when the yard scene has not landed yet. If the yard exposes
## `spike_rise_in_s()` that is used instead, because the yard is authoritative.
const SPIKE_PERIOD_S := 6.0
const SPIKE_UP_S := 1.2

## What the arena is showing. The Swift shell keeps ONE Godot process alive from launch
## (docs/stage4-swift-notes.md), so the arena is whatever message it was last sent:
## `fight_config` puts the fight up, `workshop_config` puts the stage up.
const VIEW_FIGHT := "fight"
const VIEW_WORKSHOP := "workshop"
const VIEW_MENU := "menu"
## Not a camera mode of its own: the scouting report is the workshop camera with the
## turntable turning, so the viewer can read a machine they cannot touch.
const VIEW_SCOUT := "scout"

## `rules.mode` (docs/stage4-spec.md §6). The test arena has no clock and no way to lose.
const RULES_FIGHT := "fight"
const RULES_TEST := "test"
## Rumble (docs/stage6-spec.md §4, brief §10): three machines, last one still moving wins.
const RULES_RUMBLE := "rumble"
## The five side events (brief §10, docs/stage6-spec.md §4). Each is one file in
## `Arena/fight/events/`, loaded by that path and nothing else, so adding an event is
## adding a file. Agent E6 writes the subclasses against `event_rules.gd`.
const RULES_EVENTS := ["sumo", "gauntlet", "pinball", "football", "wall_smash"]
const EVENT_DIR := "res://fight/events/%s.gd"
const MSG_EVENT_RESULT := "event_result"
## Weapons whose sound is a spin-up loop rather than a one shot, so the FX is fed their
## readiness every tick (docs/audio-notes.md).
const SPINNING_KINDS := ["spinner", "drum", "fbs", "saw", "flame"]
## Agent G1's pooled decal projector. Presentation only, and a no-op on the compatibility
## tier, so it is fed from the _process drain and never from the physics tick.
const DECALS_SCRIPT := "res://render/damage_decals.gd"
const SCRATCH_MIN_M := 0.08
const SCRATCH_MAX_M := 0.25
const MAX_BOTS := 3
## A bot that leaves the test arena is put back rather than losing.
const TEST_REPLACE_S := 2.0

## The inactivity enforcer (brief §8, docs/stage5-spec.md §4). Two machines circling each
## other for a quarter of a minute is not a fight, so the arena sends something in.
const ENFORCER_IDLE_S := 15.0       # no contact for this long and the gate opens
const ENFORCER_CALM_S := 3.0        # contact back for this long and it withdraws
const ENFORCER_CONTACT_M := 1.2     # chassis centres this close counts as contact
const ENFORCER_HOME_M := 0.8        # this close to its gate and it leaves the floor
const ENFORCER_ID := "enforcer-1"

enum State { LOADING, COUNTDOWN, FIGHTING, RESULT }

## Damage awarded scrap. B listens for this to spawn the bolt shower; the scrap itself is
## already banked in _scrap by the time this fires (brief §6: bolts visualise, never grant).
signal scrap_awarded(bot_id: String, amount: int, position: Vector3)
## Emitted on every state change, for anything inside the scene that wants to react.
signal state_changed(state_name: String)

var state: int = State.LOADING

var _config: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _recorder := Recorder.new()
var _ai: OpponentAI = null
## QA and, later, the async ladder: when set, the player bot is driven by an AI too
## (a ghost build fighting the opponent). `debug.player_ai`, off by default.
var _player_ai: OpponentAI = null

var _stage_container: SubViewportContainer = null
var _world: SubViewport = null
## Agent C2's workshop turntable. Instantiated once and kept for the life of the process,
## reparented into each new fight world so it always lives in the world the camera sees.
var _workshop_stage: Node = null
var _test_overlay: Node = null
var _decals: Node = null
var _arena: Node = null
var _bots_holder: Node3D = null
var _debris: Node3D = null
var _camera_rig: Node = null
var _hud: Node = null
var _fx: Node = null
var _controls: Node = null

## How many machines are in this fight: two, or three in a Rumble. Every per bot array
## below is this long, and every rule loops to it. Two is the whole of the career, so the
## two bot path has to stay exactly what it was: `_fill(value)` of length 2 is the same
## array the literals used to be, and `for i in _bot_count` is the same loop.
var _bot_count: int = 2
var _bots: Array = [null, null]          # index 0 player, then the opponents
var _bot_ids: Array = ["", ""]
var _bot_names: Array = ["", ""]
var _tallies: Array = [Rules.empty_tally(), Rules.empty_tally()]
var _scrap: Array = [0, 0]
var _ko_count: Array = [0.0, 0.0]
var _last_touch_by: Array = ["", ""]     # per victim index: which bot id last touched it
var _last_touch_at: Array = [-999.0, -999.0]
var _last_fire_at: Array = [-999.0, -999.0]
var _fire_hit_counted: Array = [true, true]
var _spawn_y: Array = [0.25, 0.25]
var _ooa_flag: Array = [false, false]
## The heading each bot was actually given this tick, so the knockout count can tell a
## pinned bot (driving, going nowhere) from a dead one.
var _last_heading: Array = [Vector2.ZERO, Vector2.ZERO]

var _tick: int = 0
var _fight_time: float = 0.0
var _time_left: float = FightTypes.FIGHT_DURATION_S
var _ko_count_s: float = FightTypes.KO_COUNT_S
var _countdown_time: float = 0.0
var _spike_phase_s: float = 0.0

var _frames: int = 0
var _ready_sent: bool = false
var _started: bool = false
var _result_sent: bool = false
var _autostarted: bool = false

var _ticks_msec_at_config: int = 0
var _pending_fx: Array = []
var _countdown_step: int = -1
var _result_shown: bool = false
var _pending_weapon_fires: Array = []
var _hud_banner: String = ""
var _hud_winner: String = ""
var _ko_haptic_step: Array = [0, 0]
## Per bot, whether its knockout count actually moved this tick. A frozen count is not a
## count and the HUD must not show it.
var _ko_advancing: Array = [false, false]
## Has the player asked for any drive yet in this fight? A pure fact about the recorded
## input stream, so it arms the knockout count identically in a fight and in its replay.
var _player_has_driven: bool = false
var _warned: Dictionary = {}
var _fights_run: int = 0
var _view: String = VIEW_FIGHT
var _rules_mode: String = RULES_FIGHT
var _arena_id: String = DEFAULT_ARENA
## Per bot, the fight time at which a bot that left the test arena gets put back.
var _replace_at: Array = [-1.0, -1.0]
var _bot_configs: Array = [{}, {}]
## Rumble: ids in the order they went out, oldest first. Empty in an ordinary fight.
var _eliminated: Array = []
## Rumble: extra drivers, one per opponent past the first, seeded off the fight seed.
var _rumble_ai: Array = []
## The side event running this fight, or null. It owns the clock and the win condition;
## `fight.gd` still owns everything else.
var _event: RefCounted = null
## The inactivity enforcer. It is a third body on the floor, not a third competitor: it
## takes no scrap, scores no judges' points and cannot win or lose the fight.
var _enforcer_id: String = ""
var _enforcer: Node = null
var _enforcer_ai: BossAI = null
var _enforcer_gate: Vector3 = Vector3.ZERO
var _enforcer_withdrawing: bool = false
var _last_contact_s: float = 0.0
var _contact_since_s: float = -1.0
## The last settings the shell sent. Kept because a fight builds a new world, and a new
## world means a new CameraRig and a new FX: they have to be told again or the player's
## choices quietly revert on the second fight.
var _settings: Dictionary = {}

## Replay playback state. `_replaying` is the whole switch: a replay runs the ordinary
## fight tick, because re-simulating is what a replay IS, and only the reporting differs.
## The simulation clock is stopped. Presentation keeps running; the fixed tick does not.
var _paused: bool = false

var _replaying: bool = false
var _replay_total: int = 0
var _replay_paused: bool = false
var _replay_speed: float = 1.0
var _seek_to: int = -1
var _replay_last_sent: int = -1


# ---------------------------------------------------------------- lifecycle

func _ready() -> void:
	_stage_container = $Stage
	# Pausing stops the SceneTree, and with it PhysicsServer3D. Everything that has to
	# keep running while the simulation is frozen says so: this node (its _process is
	# the presentation drain), the HUD, the controls and the Bridge, which must still be
	# able to deliver the `fight_control` that resumes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ...and PROCESS_MODE_ALWAYS is INHERITED, so the fight world underneath has to opt
	# back out explicitly. Without this the bots, the arena hazards and the FX keep
	# running their _physics_process while the physics server is off: their timers age
	# without a single body moving, and a paused fight ends a metre and a half from where
	# the same fight ended unpaused (measured; tests/pause_test.gd is what caught it).
	_stage_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	var bridge := get_node_or_null("/root/Bridge")
	if bridge != null:
		bridge.process_mode = Node.PROCESS_MODE_ALWAYS
	_wire_ui()
	_build_world()
	# Built before the bridge is connected, because WorkshopStage subscribes to the same
	# `workshop_config` message and would miss the very first one if it were created
	# lazily inside the handler for it.
	_ensure_workshop_stage()
	Bridge.message_received.connect(_on_message_received)
	if Bridge.is_attached():
		_send_arena_ready()
	_set_state(State.LOADING)


func _process(delta: float) -> void:
	if not _started:
		_frames += 1
		if _frames >= AUTOSTART_FRAMES and not Bridge.is_attached():
			_autostart()
	if _seek_to >= 0:
		_tick_seek()
	_update_presentation(delta)


func _physics_process(delta: float) -> void:
	if _view != VIEW_FIGHT:
		return
	# Paused: not one tick runs, so no tick can be skipped or doubled and the recorded
	# input stream is bit for bit what an unpaused run of the same seed produces.
	if _paused:
		return
	if _replaying and _replay_paused and _seek_to < 0:
		return
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.FIGHTING:
			_tick_fight(delta)
		_:
			pass


# ---------------------------------------------------------------- scene wiring

## The parts of the scene that live for the whole process: the HUD and the touch
## controls. They are wired once, in _ready, and survive every fight.
func _wire_ui() -> void:
	_hud = _swap_in(self, "HUD", HUD_SCENE)
	_controls = _swap_in(self, "Controls", CONTROLS_SCENE)
	for node in [_hud, _controls]:
		if node != null:
			node.process_mode = Node.PROCESS_MODE_ALWAYS
	# The pad's START button asks the shell for a pause; the shell puts its own overlay
	# up and answers with a `fight_control`. Nothing here decides what a pause looks
	# like, only that one was asked for.
	if _controls != null and _controls.has_signal("pause_requested") \
			and not _controls.is_connected("pause_requested", _on_pause_requested):
		_controls.connect("pause_requested", _on_pause_requested)


## Build a brand new 3D world for one fight and throw the previous one away.
##
## Every fight gets its own SubViewport with `own_world_3d`, which means its own World3D
## and its own physics space. That is not tidiness: two fights run back to back in one
## space do not reproduce each other (see docs/stage3-rules-notes.md), and the shipping
## app runs fight after fight in a single never restarted Godot process, so a replay would
## never match the fight it replays. A fresh world per fight is what makes the replay and
## the async ladder in brief section 10 possible at all.
func _build_world() -> void:
	# The workshop stage outlives every world, so lift it out before the old one is freed.
	if _workshop_stage != null and _workshop_stage.get_parent() != null:
		_workshop_stage.get_parent().remove_child(_workshop_stage)
	if _world != null:
		# Remove first, then queue_free: removing takes every body out of the physics
		# space this frame, rather than at the end of it.
		if _world.get_parent() != null:
			_world.get_parent().remove_child(_world)
		_world.queue_free()
		_world = null

	var packed := _load_scene(WORLD_SCENE)
	if packed == null:
		_warn_once("world", WORLD_SCENE + " is missing; the fight has nowhere to happen")
		return
	_world = packed.instantiate() as SubViewport
	_stage_container.add_child(_world)

	_bots_holder = _world.get_node("Bots") as Node3D
	_debris = _world.get_node("Debris") as Node3D
	# The test arena is the Yard with the hazard taken out (spec §6), so a build behaves
	# in the workshop exactly as it will in a fight.
	var arena_path: String = ARENA_SCENES[_arena_id]
	if _rules_mode == RULES_TEST:
		arena_path = TEST_ARENA_SCENE
	elif _event != null and str(_event.call("arena_scene_path")) != "":
		# An event that needs its own floor plan says so; one that is happy anywhere
		# returns "" and gets the arena the configuration asked for.
		arena_path = str(_event.call("arena_scene_path"))
	_arena = _swap_in(_world, "Arena", arena_path)
	_camera_rig = _swap_in(_world, "CameraRig", CAMERA_RIG_SCENE)
	_fx = _swap_in(_world, "FX", FX_SCENE)
	if _workshop_stage != null:
		_world.add_child(_workshop_stage)
	_build_decals()

	_bots = [null, null]
	_connect_ooa_sensor()
	if _fx != null and _fx.has_method("on_scrap_awarded"):
		scrap_awarded.connect(Callable(_fx, "on_scrap_awarded"))
	if _fx != null and _fx.has_method("bind"):
		_fx.call("bind", _hud, Callable(self, "bot_position_by_id"))
	if _camera_rig != null:
		if _camera_rig.has_method("fit_arena"):
			_camera_rig.call("fit_arena", _arena_size())
		if _camera_rig.has_method("bind_controls") and _controls != null:
			_camera_rig.call("bind_controls", _controls)
	# One connection covers all six arenas: every one emits hazard_fx(kind, active, at).
	# `hazard_fx(kind, active, position)` matches ArenaBase's signal exactly. Both handlers
	# are connected when both exist: `on_hazard_fx` is the audio pass's name for it and
	# `on_arena_hazard` the earlier one, and neither is a superset of the other.
	if _arena != null and _fx != null and _arena.has_signal("hazard_fx"):
		for handler in ["on_hazard_fx", "on_arena_hazard"]:
			if _fx.has_method(handler) and not _arena.is_connected("hazard_fx", Callable(_fx, handler)):
				_arena.connect("hazard_fx", Callable(_fx, handler))
	# Hazard flame scorches the floor it plays over. The arena's own signal is the exact
	# source for that, which the damage event is not: a damage_event carries no `source`,
	# so a burn and a spike hit are indistinguishable in it.
	if _arena != null and _arena.has_signal("hazard_fx") \
			and not _arena.is_connected("hazard_fx", _on_hazard_decal):
		_arena.connect("hazard_fx", _on_hazard_decal)
	# The rig and the FX in this world have never been told what the player chose.
	_reapply_settings()


## One decal projector per fight world, so the scratches and scorches of the last fight
## are thrown away with the world they were made in.
func _build_decals() -> void:
	_decals = null
	if not ResourceLoader.exists(DECALS_SCRIPT):
		return
	var script: GDScript = load(DECALS_SCRIPT)
	if script == null:
		return
	_decals = script.new()
	_decals.name = "DamageDecals"
	_world.add_child(_decals)


## Replace a placeholder holder with the real scene when its owner has landed it. The
## holder keeps the spec's node name either way, so `Debris` and friends stay findable.
func _swap_in(parent: Node, holder_name: String, scene_path: String) -> Node:
	var holder: Node = parent.get_node_or_null(NodePath(holder_name))
	var packed := _load_scene(scene_path)
	if packed == null:
		_warn_once(holder_name, "%s is missing; keeping the %s placeholder" % [scene_path, holder_name])
		return holder
	var instance: Node = packed.instantiate()
	instance.name = holder_name
	var index := holder.get_index() if holder != null else parent.get_child_count()
	if holder != null:
		parent.remove_child(holder)
		holder.queue_free()
	parent.add_child(instance)
	parent.move_child(instance, index)
	instance.owner = null
	return instance


func _load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	return res as PackedScene


## The yard's out-of-arena sensor (spec §5): an Area3D on layer 5. Found by name first,
## then by layer, so P can call it whatever reads best.
func _connect_ooa_sensor() -> void:
	if _arena == null:
		return
	# The yard emits body_out for anything its layer 5 sensor swallows. That is the
	# contract; the Area3D search below is only a fallback for a yard without it.
	if _arena.has_signal("body_out"):
		if not _arena.is_connected("body_out", _on_ooa_body_entered):
			_arena.connect("body_out", _on_ooa_body_entered)
		return
	var area := _find_ooa_area(_arena)
	if area == null:
		_warn_once("ooa", "no out-of-arena Area3D found in the yard; using the positional rule only")
		return
	if not area.body_entered.is_connected(_on_ooa_body_entered):
		area.body_entered.connect(_on_ooa_body_entered)


func _find_ooa_area(node: Node) -> Area3D:
	if node is Area3D:
		var area := node as Area3D
		if node.name in ["OOA", "OutOfArena", "OutOfArenaSensor"] \
				or (area.collision_layer & FightTypes.LAYER_OOA) != 0:
			return area
	for child in node.get_children():
		var found := _find_ooa_area(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------- bridge

func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"bridge_attached":
			_ready_sent = false
			_send_arena_ready()
		FightTypes.MSG_FIGHT_CONFIG:
			_on_fight_config(payload)
		MSG_WORKSHOP_CONFIG:
			show_workshop(payload)
		MSG_TEST_RESET:
			test_reset()
		MSG_SETTINGS:
			apply_settings(payload)
		MSG_REPLAY_CONTROL:
			replay_control(payload)
		MSG_FIGHT_CONTROL:
			fight_control(payload)
		MSG_STAGE_CAMERA:
			stage_camera(payload)
		_:
			Bridge.send(FightTypes.MSG_ARENA_LOG, {
				"level": "warn", "text": "unknown message type: " + type,
			})


func _send_arena_ready() -> void:
	if _ready_sent:
		return
	_ready_sent = true
	Bridge.send(FightTypes.MSG_ARENA_READY, {
		"schema": SCHEMA,
		"godot_version": Engine.get_version_info()["string"],
		"ticks_msec": Time.get_ticks_msec(),
	})


func _on_fight_config(config: Dictionary) -> void:
	_ticks_msec_at_config = Time.get_ticks_msec()
	var problem := _validate_config(config)
	if problem != "":
		Bridge.send(FightTypes.MSG_ARENA_LOG, {"level": "error", "text": problem})
		return
	# Re arming (docs/stage3-swift-notes.md): the shell keeps ONE Godot process and sends a
	# fresh fight_config every time the player taps Fight, including straight after a
	# result. A config arriving in LOADING or RESULT starts a new fight. A config arriving
	# mid fight is the shell's defensive resend, and two sends of the same configuration
	# must never produce two fights, so it is logged and dropped.
	if state == State.COUNTDOWN or state == State.FIGHTING:
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "warn",
			"text": "fight_config arrived during %s; a fight is already running, ignored"
				% _state_name(state),
		})
		return
	Bridge.send(FightTypes.MSG_ARENA_LOG, {"level": "info", "text": "config received"})
	start_fight(config)


## Schema validation. Returns "" when the config is usable, otherwise the reason.
func _validate_config(config: Dictionary) -> String:
	if int(config.get("schema", 0)) != SCHEMA:
		return "unsupported FightConfig schema: " + str(config.get("schema", 0))
	var bots: Variant = config.get("bots", null)
	if not (bots is Array) or (bots as Array).size() < 2:
		return "FightConfig needs two bots"
	for bot_variant in (bots as Array):
		if not (bot_variant is Dictionary):
			return "FightConfig bots must be objects"
		if str((bot_variant as Dictionary).get("id", "")) == "":
			return "every bot needs an id"
	if str(config.get("arena", "")) == "":
		return "FightConfig needs an arena"
	return ""


# ---------------------------------------------------------------- side events

## Load `res://fight/events/<mode>.gd` and hand it the fight. Returns null for an ordinary
## fight and for an event whose file has not landed, which is warned about rather than
## fatal: a missing event runs as an ordinary fight instead of failing to start.
func _load_event(mode: String) -> RefCounted:
	if not mode in RULES_EVENTS:
		return null
	var path := EVENT_DIR % mode
	if not ResourceLoader.exists(path):
		_warn_once("event_" + mode, "%s is missing; running an ordinary fight" % path)
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "warn", "text": "event '%s' is not built yet" % mode,
		})
		_rules_mode = RULES_FIGHT
		return null
	var script: GDScript = load(path)
	if script == null:
		_rules_mode = RULES_FIGHT
		return null
	var event: RefCounted = script.new()
	event.call("setup", self, _config)
	return event


## An event sends `event_result`, not `fight_result`: it has no winner, no loser and no
## judges' card, and a result sheet built for a fight would have to invent all three.
func _finish_event() -> void:
	if _result_sent:
		return
	_result_sent = true
	var payload: Dictionary = _event.call("result")
	var message := {
		"mode": _rules_mode,
		"score": int(payload.get("score", 0)),
		"cleared": bool(payload.get("cleared", false)),
		"time_s": _fight_time,
		"details": payload.get("details", {}),
	}
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot != null and bot.has_method("freeze"):
			bot.call("freeze")
	_set_state(State.RESULT)
	Bridge.send(MSG_EVENT_RESULT, message)


# ---------------------------------------------------------------- the public seam events use

## Everything `EventRules` reads off the fight. Public on purpose and deliberately small:
## an event that needs more than this is probably a rule, not an event.
func bots() -> Array:
	return _bots.duplicate()


func arena() -> Node:
	return _arena


func fight_time() -> float:
	return _fight_time


func rng() -> RandomNumberGenerator:
	return _rng


func bot_id(index: int) -> String:
	return str(_bot_ids[index]) if index >= 0 and index < _bot_ids.size() else ""


# ---------------------------------------------------------------- replays

## docs/stage6-spec.md §2. A replay is not a recording: it is the same fight, re-simulated
## from the same seed and the same input log, in a world built the same way every fight's
## world is built. That is only possible because of the two things Stage 3 and Stage 4
## settled (a fresh World3D per fight, and the AI drawing from the shared rng on a fixed
## cadence), and it is why `replay.inputs` carries only the PLAYER's record: the opponent
## is regenerated, not stored.
##
## The whole of the difference from an ordinary fight is reporting. The simulation runs
## exactly as it did, so a replay that diverges is a determinism bug and the right thing
## for it to do is show it.
func _tick_replay() -> void:
	if _tick - _replay_last_sent < REPLAY_STATE_EVERY:
		return
	_replay_last_sent = _tick
	Bridge.send(MSG_REPLAY_STATE, {"tick": _tick, "total": _replay_total})


## The picture during a replay: no HUD, no driving controls, and a camera the viewer owns.
## Nothing is asked of agent C that it may not have: "replay" if the rig knows the mode,
## otherwise the fight camera with the director cut turned off so it stops easing back to
## the default pose while the viewer is looking at something.
func _enter_replay_view() -> void:
	_show_fight_ui(false)
	if _camera_rig == null:
		return
	if _camera_rig.has_method("set_mode"):
		var modes: Variant = _camera_rig.get("MODES")
		var has_replay := modes is Array and (modes as Array).has("replay")
		_camera_rig.call("set_mode", "replay" if has_replay else VIEW_FIGHT)
	if _camera_rig.has_method("set_director_cut"):
		_camera_rig.call("set_director_cut", false)


## `replay_control` from the shell: {action, value}.
##   play / pause      stop and start the simulation
##   speed  value      0.25, 0.5 or 1. The PHYSICS TICK RATE never changes; only the rate
##                     the engine is asked for steps does, so the simulation is identical
##                     at every speed and slow motion is not a different fight.
##   restart           rebuild the world and run it again from tick 0
##   seek   value      rebuild and fast forward to that tick
func replay_control(payload: Dictionary) -> void:
	if not _replaying:
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "warn", "text": "replay_control with no replay running; ignored",
		})
		return
	var action := str(payload.get("action", ""))
	match action:
		"play":
			_replay_paused = false
		"pause":
			_replay_paused = true
		"speed":
			_set_replay_speed(float(payload.get("value", 1.0)))
		"restart":
			_restart_replay()
		"seek":
			_seek_replay(int(payload.get("value", 0)))
		_:
			Bridge.send(FightTypes.MSG_ARENA_LOG, {
				"level": "warn", "text": "unknown replay_control action: " + action,
			})


## 0.25, 0.5 or 1, and nothing else: an arbitrary multiplier would let a viewer run a
## replay at a speed the engine cannot keep steps up with, and the picture would drift from
## the numbers even though the simulation had not.
func _set_replay_speed(value: float) -> void:
	var chosen := 1.0
	var best := INF
	for candidate in REPLAY_SPEEDS:
		var d := absf(float(candidate) - value)
		if d < best:
			best = d
			chosen = float(candidate)
	_replay_speed = chosen
	Engine.time_scale = chosen


func _restart_replay() -> void:
	var config := _config.duplicate(true)
	_seek_to = -1
	Engine.time_scale = _replay_speed
	start_fight(config)


## Seek by re-simulating, because there is nothing else to seek: the fight only exists as
## the sum of its ticks. So it rebuilds the world and runs the simulation forward with the
## picture switched off.
##
## What that costs, measured on this Mac with two bots: the engine takes up to
## SEEK_MAX_STEPS (32) physics steps per frame at SEEK_TIME_SCALE (24), which is roughly
## 1400 ticks a second, so seeking to the end of a 90 second fight (5400 ticks) takes about
## four seconds and seeking ten seconds in takes under half of one. It is linear in the
## distance sought and it always starts from tick 0, so seeking backwards costs the same as
## seeking forwards. A phone will be slower. If that ever matters the answer is keyframes
## (a snapshot of every body every few seconds), not a faster loop.
func _seek_replay(tick: int) -> void:
	var target := clampi(tick, 0, maxi(_replay_total, 0))
	_restart_replay()
	if target <= 0:
		return
	_seek_to = target
	_replay_paused = false
	Engine.max_physics_steps_per_frame = SEEK_MAX_STEPS
	Engine.time_scale = SEEK_TIME_SCALE
	if _world != null:
		_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Bridge.send(FightTypes.MSG_ARENA_LOG, {
		"level": "info", "text": "seeking to tick %d" % target,
	})


## Called from _process while a seek is running. The simulation is doing the work; this
## only watches for the target and puts the picture back.
func _tick_seek() -> void:
	if _seek_to < 0:
		return
	if _tick < _seek_to and state != State.RESULT:
		return
	_seek_to = -1
	Engine.max_physics_steps_per_frame = 8
	Engine.time_scale = _replay_speed
	if _world != null:
		_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Bridge.send(MSG_REPLAY_STATE, {"tick": _tick, "total": _replay_total})


# ---------------------------------------------------------------- settings

## Route the shell's settings to the nodes that own each one. Presentation only: none of
## this is allowed to reach the simulation, so a replay is unaffected by what the player
## has turned on.
##
## Every key is optional and every target is guarded, because the shell sends whatever it
## knows and the nodes are three other agents'. An unknown key is ignored rather than
## warned about: the shell is allowed to grow the message.
## Merged, not replaced. The shell sends the whole struct today, but a partial update is
## a reasonable thing for it to start doing, and a partial update that silently cleared
## every other setting would be a bug nobody would look for.
# ---------------------------------------------------------------- pause and quit

## `fight_control` from the host: {"action": "pause" | "resume" | "quit"}.
##
## Pause freezes the SIMULATION and nothing else. The SceneTree is paused, which stops
## every _physics_process and PhysicsServer3D with it, while this node, the HUD and the
## controls run on regardless (PROCESS_MODE_ALWAYS), so the arena is still drawn and the
## shell's overlay has something behind it. No tick runs while paused, so resuming picks
## up on the tick that would have been next: the recorded input stream and the result of
## a paused fight are bit for bit those of an unpaused one (tests/pause_test.gd).
func fight_control(payload: Dictionary) -> void:
	var action := str(payload.get("action", "")).strip_edges().to_lower()
	match action:
		"pause":
			_set_paused(true)
		"resume":
			_set_paused(false)
		"quit":
			_set_paused(false)
			_abandon_fight()
			_teardown_fight()
			_show_fight_ui(false)
		_:
			Bridge.send(FightTypes.MSG_ARENA_LOG, {
				"level": "warn", "text": "fight_control: unknown action '%s'" % action,
			})


func _set_paused(on: bool) -> void:
	if on == _paused:
		return
	# Only a fight can be paused. Pausing the menus would freeze the shell's backdrop.
	if on and _view != VIEW_FIGHT:
		return
	_paused = on
	if is_inside_tree():
		get_tree().paused = on
	if _controls != null and _controls.has_method("set_enabled"):
		_controls.call("set_enabled", not on and state == State.FIGHTING)
	_hud_call("set_paused", [on])
	Bridge.send(FightTypes.MSG_FIGHT_STATE, {"state": "paused" if on else "resumed"})
	state_changed.emit("paused" if on else "resumed")


func is_paused() -> bool:
	return _paused


## Belt and braces before every fight and every return to the arena: put the clock, the
## step budget and the picture back to normal WITHOUT asking whether this node is the one
## that moved them.
##
## `_set_paused(false)` alone is not enough, because it early-returns when its own flag is
## already false; anything else that paused the tree, slowed the clock or switched the
## SubViewport off (a replay seek that never finished, the shell, a future caller) would
## then leave a fight that draws one frozen frame and never ticks. That failure looks
## exactly like a hung game, so it is cleared unconditionally rather than diagnosed.
func _force_running() -> void:
	if is_inside_tree() and get_tree().paused:
		get_tree().paused = false
	_paused = false
	# NOT Engine.time_scale: start_fight already puts that back to 1 for an ordinary
	# fight, and a replay restart deliberately carries its slow motion in through here.
	_seek_to = -1
	Engine.max_physics_steps_per_frame = 8
	if _world != null and is_instance_valid(_world):
		_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_hud_call("set_paused", [false])


## The pad's START button. The arena never decides what a pause means; it reports the
## request and waits for the `fight_control` that answers it.
func _on_pause_requested() -> void:
	if _view != VIEW_FIGHT or (state != State.FIGHTING and state != State.COUNTDOWN):
		return
	Bridge.send(MSG_PAUSE_REQUESTED, {"tick": _tick})


## A fight nobody watched has no result worth recording: say so and record nothing.
## Shared by `fight_control` quit and by walking out into the workshop.
func _abandon_fight() -> void:
	if state != State.COUNTDOWN and state != State.FIGHTING:
		return
	Bridge.send(FightTypes.MSG_FIGHT_STATE, {"state": "abandoned"})
	state_changed.emit("abandoned")
	_result_sent = true
	state = State.LOADING


func apply_settings(settings: Dictionary) -> void:
	for key in settings.keys():
		_settings[key] = settings[key]
	_reapply_settings()


## Called again after every _build_world, because the rig and the FX are new each fight.
func _reapply_settings() -> void:
	if _settings.is_empty():
		return
	if _settings.has("scheme") and _controls != null and _controls.has_method("set_scheme"):
		_controls.call("set_scheme", str(_settings["scheme"]))
	if _settings.has("director_cut") and _camera_rig != null \
			and _camera_rig.has_method("set_director_cut"):
		_camera_rig.call("set_director_cut", bool(_settings["director_cut"]))
	if _settings.has("haptics") and _fx != null and _fx.has_method("set_haptics_enabled"):
		_fx.call("set_haptics_enabled", bool(_settings["haptics"]))
	if (_settings.has("controller_connected") or _settings.has("controller_kind")) \
			and _hud != null and _hud.has_method("set_controller_hints"):
		_hud.call("set_controller_hints", bool(_settings.get("controller_connected", false)),
			str(_settings.get("controller_kind", "")))
	if _settings.has("volume"):
		# 0 is silence, not minus infinity decibels: linear_to_db(0) is -inf, which some
		# audio drivers take badly, so silence is expressed as the mute flag instead.
		var volume := clampf(float(_settings["volume"]), 0.0, 1.0)
		AudioServer.set_bus_mute(0, volume <= 0.0)
		if volume > 0.0:
			AudioServer.set_bus_volume_db(0, linear_to_db(volume))


# ---------------------------------------------------------------- the workshop view

## `workshop_config` arrived: put the stage up and take the fight down.
##
## The shell sends this while the player is in the menus, on every builder edit (debounced
## 150 ms), and again when the player leaves a fight, so it can land in ANY state. Landing
## mid fight means the player walked out: the fight is abandoned silently, with no result,
## because a fight nobody watched has no result worth recording.
##
## The bot itself is not shown from here. `WorkshopStage` listens to the same bridge
## message and answers `workshop_ready` with its own build summary, so doing it here as
## well would assemble the bot twice and send the answer twice.
func show_workshop(payload: Dictionary) -> void:
	_set_paused(false)
	_abandon_fight()

	_teardown_fight()
	_ensure_workshop_stage()

	# "menu" is the backdrop behind the SwiftUI chrome; "scout" is the scouting report
	# looking at somebody else's machine, which is the workshop camera with the turntable
	# running so the viewer can read it without touching anything (agent S3).
	var want := str(payload.get("mode", ""))
	_view = VIEW_MENU if want == VIEW_MENU else VIEW_WORKSHOP
	if _workshop_stage != null:
		if _workshop_stage.has_method("set_active"):
			_workshop_stage.call("set_active", true)
		if _workshop_stage.has_method("set_auto_rotate"):
			_workshop_stage.call("set_auto_rotate", want == VIEW_SCOUT or want == VIEW_MENU)
		if _camera_rig != null and _camera_rig.has_method("set_workshop_centre") \
				and _workshop_stage.has_method("stage_centre"):
			_camera_rig.call("set_workshop_centre", _workshop_stage.call("stage_centre"))
	if _camera_rig != null and _camera_rig.has_method("set_mode"):
		_camera_rig.call("set_mode", _view)
	# `frame` says where across the screen the stage centre should land, so a SwiftUI
	# panel can own one side and the bot still be framed in what is left. Absent means
	# centred, which is what every screen that says nothing gets.
	if _camera_rig != null and _camera_rig.has_method("set_frame_bias"):
		_camera_rig.call("set_frame_bias", float(payload.get("frame", 0.5)))
	_show_fight_ui(false)
	_set_ambience(false)

	if _workshop_stage == null:
		# Nothing here can assemble a bot, but the shell is waiting on an answer and an
		# empty summary is a documented, expected reply.
		_warn_once("stage", STAGE_SCENE + " is missing; answering workshop_ready empty")
		Bridge.send(MSG_WORKSHOP_READY, {})


## `stage_camera` from the host: a camera gesture the SHELL captured and forwarded,
## because on the workshop and menu screens the SwiftUI navigation container swallows
## every touch before the embedded Godot view ever sees it.
##
##   {"orbit": [dx, dy]}   drag in screen POINTS, +x right, +y down
##   {"pinch": 1.08}       factor, above 1 moves in
##
## Stage screens only. A fight routes its own touches through FightControls and a replay
## has its own scrub controls, so both ignore this: a host that sends it mid fight must
## not be able to swing the camera out from under a player's thumbs. The rig's own
## `_unhandled_input` workshop path is untouched and is still what desktop QA uses. The
## menu camera is a cinematic drift and the rig ignores gestures there by design; the
## message is still routed, so nothing has to know that but the rig.
func stage_camera(payload: Dictionary) -> void:
	if _camera_rig == null or not is_instance_valid(_camera_rig):
		return
	if _replaying or (_view != VIEW_WORKSHOP and _view != VIEW_MENU):
		return
	var raw_orbit: Variant = payload.get("orbit", null)
	if raw_orbit is Array:
		var raw: Array = raw_orbit as Array
		if raw.size() >= 2 and _camera_rig.has_method("orbit"):
			_camera_rig.call("orbit", _points_to_pixels(
				Vector2(float(raw[0]), float(raw[1]))))
	if payload.has("pinch") and _camera_rig.has_method("pinch"):
		var factor := float(payload.get("pinch", 1.0))
		if factor > 0.0:
			_camera_rig.call("pinch", factor)


## Screen points to viewport pixels. The rig's orbit() is quoted in viewport pixels, the
## same units a touch drag arrives in, so a forwarded gesture has to be scaled the way
## the canvas_items stretch scales a real one or it would feel wrong on every device.
func _points_to_pixels(points: Vector2) -> Vector2:
	var size := FightControls.REF_SIZE_PT
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			var rect := vp.get_visible_rect().size
			if rect.x > 1.0 and rect.y > 1.0:
				size = rect
	var scale := minf(size.x / FightControls.REF_SIZE_PT.x,
		size.y / FightControls.REF_SIZE_PT.y)
	return points * maxf(scale, 0.0001)


func _ensure_workshop_stage() -> void:
	if _workshop_stage != null and is_instance_valid(_workshop_stage):
		return
	var packed := _load_scene(STAGE_SCENE)
	if packed == null:
		return
	_workshop_stage = packed.instantiate()
	_workshop_stage.name = "WorkshopStage"
	if _world != null:
		_world.add_child(_workshop_stage)
	else:
		add_child(_workshop_stage)
	# Dark and idle until something asks for it: the fight must not be lit by the stage.
	if _view == VIEW_FIGHT and _workshop_stage.has_method("set_active"):
		_workshop_stage.call("set_active", false)


## Show the fight again: the stage off, the camera back to the arena, the HUD and the
## controls back. Called at the top of every start_fight, including the desktop QA path.
func _show_fight_view() -> void:
	_force_running()
	_view = VIEW_FIGHT
	_set_ambience(true)
	if _workshop_stage != null and _workshop_stage.has_method("set_active"):
		_workshop_stage.call("set_active", false)
	if _camera_rig != null:
		if _camera_rig.has_method("set_mode"):
			_camera_rig.call("set_mode", VIEW_FIGHT)
		if _camera_rig.has_method("fit_arena"):
			_camera_rig.call("fit_arena", _arena_size())
	_show_fight_ui(true)


## The arena's own room tone: on in a fight or an event, off on the workshop stage, which
## has its own.
func _set_ambience(on: bool) -> void:
	if _fx != null and _fx.has_method("set_ambience"):
		_fx.call("set_ambience", on)


## The HUD and the driving controls belong to the fight and to nothing else.
func _show_fight_ui(on: bool) -> void:
	if _hud != null and "visible" in _hud:
		_hud.set("visible", on)
	if _controls != null:
		if _controls.has_method("set_enabled"):
			_controls.call("set_enabled", on)
		if "visible" in _controls:
			_controls.set("visible", on)


## Free everything that belonged to a fight: the bots, the debris and the arena, so the
## Yard's own lighting is not left burning behind the workshop stage.
func _teardown_fight() -> void:
	_ai = null
	_player_ai = null
	_enforcer = null
	_enforcer_ai = null
	_bots = [null, null]
	_replace_at = [-1.0, -1.0]
	if _bots_holder != null and is_instance_valid(_bots_holder):
		for child in _bots_holder.get_children():
			child.queue_free()
	if _debris != null and is_instance_valid(_debris):
		for child in _debris.get_children():
			child.queue_free()
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	_clear_test_overlay()


# ---------------------------------------------------------------- test mode

## `test_reset`: put both machines back on their marks in one piece (spec §6). The bots
## are rebuilt from the configuration the fight started with rather than repaired in
## place, which is the only way to be sure nothing carries over: a bent joint, a detached
## panel sitting in the debris, a spent gas bottle.
func test_reset() -> void:
	if _config.is_empty():
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "warn", "text": "test_reset with no fight configured; ignored",
		})
		return
	if _debris != null and is_instance_valid(_debris):
		for child in _debris.get_children():
			child.queue_free()
	_spawn_bots(_config)
	_tallies = [Rules.empty_tally(), Rules.empty_tally()]
	_scrap = [0, 0]
	_ko_count = [0.0, 0.0]
	_replace_at = [-1.0, -1.0]
	_ooa_flag = [false, false]
	_fight_time = 0.0
	_bind_test_overlay()
	Bridge.send(FightTypes.MSG_ARENA_LOG, {"level": "info", "text": "test arena reset"})


func _ensure_test_overlay() -> void:
	if _rules_mode != RULES_TEST:
		_clear_test_overlay()
		return
	if _test_overlay != null and is_instance_valid(_test_overlay):
		_bind_test_overlay()
		return
	if not ResourceLoader.exists(TEST_OVERLAY_SCRIPT):
		_warn_once("overlay", TEST_OVERLAY_SCRIPT + " is missing; no test readout")
		return
	var script: Script = load(TEST_OVERLAY_SCRIPT)
	_test_overlay = script.new()
	_test_overlay.name = "TestOverlay"
	add_child(_test_overlay)
	if _test_overlay.has_signal("reset_requested"):
		_test_overlay.connect("reset_requested", test_reset)
	_bind_test_overlay()


func _bind_test_overlay() -> void:
	if _test_overlay == null or not is_instance_valid(_test_overlay):
		return
	if _test_overlay.has_method("bind"):
		_test_overlay.call("bind", _bots.duplicate(), _fight_camera())


func _clear_test_overlay() -> void:
	if _test_overlay != null and is_instance_valid(_test_overlay):
		_test_overlay.queue_free()
	_test_overlay = null


func _fight_camera() -> Camera3D:
	if _camera_rig != null and _camera_rig.has_method("camera"):
		return _camera_rig.call("camera") as Camera3D
	if _world != null:
		return _world.get_camera_3d()
	return null


# ---------------------------------------------------------------- desktop QA auto-start

func _autostart() -> void:
	if _started or _autostarted:
		return
	_autostarted = true
	var config := _read_fixture()
	if config.is_empty():
		_warn_once("fixture", "no host attached and " + FIXTURE_PATH + " could not be read")
		return
	var debug: Dictionary = config.get("debug", {}) as Dictionary
	var override := _cmdline_value("--roboteer-ai=")
	if override != "":
		debug["opponent_ai"] = override
	var player_override := _cmdline_value("--roboteer-player-ai=")
	if player_override != "":
		debug["player_ai"] = player_override
	config["debug"] = debug
	print("Fight: no host attached, running the desktop QA fixture (opponent_ai=%s, player_ai=%s)"
		% [str(debug.get("opponent_ai", "normal")), str(debug.get("player_ai", OpponentAIScript.MODE_OFF))])
	_ticks_msec_at_config = Time.get_ticks_msec()
	var problem := _validate_config(config)
	if problem != "":
		_warn_once("fixture_schema", "fixture is invalid: " + problem)
		return
	start_fight(config)


func _read_fixture() -> Dictionary:
	var text := ""
	if FileAccess.file_exists(FIXTURE_PATH):
		text = FileAccess.get_file_as_string(FIXTURE_PATH)
	if text == "" and ResourceLoader.exists(FIXTURE_PATH):
		var res: Resource = load(FIXTURE_PATH)
		if res is JSON and (res as JSON).data is Dictionary:
			return (res as JSON).data as Dictionary
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Reads `--roboteer-ai=` and `--roboteer-player-ai=` from the user args after a bare `--`,
## and from the plain command line as a convenience when running the binary directly.
## Only the four known driver names are accepted; anything else is ignored, not guessed at.
func _cmdline_value(prefix: String) -> String:
	var args: Array = []
	args.append_array(OS.get_cmdline_user_args())
	args.append_array(OS.get_cmdline_args())
	const ALLOWED := [
		OpponentAIScript.MODE_OFF, OpponentAIScript.MODE_IDLE,
		OpponentAIScript.MODE_CHARGE, OpponentAIScript.MODE_NORMAL,
	]
	for arg_variant in args:
		var arg := str(arg_variant)
		if arg.begins_with(prefix):
			var value := arg.substr(prefix.length())
			if value in ALLOWED:
				return value
	return ""


# ---------------------------------------------------------------- start

## Entry point for a validated config, from the bridge or the desktop fixture.
## `scripted_inputs` replays a recorded input list instead of reading the controls; the
## determinism test uses it, nothing else should.
func start_fight(config: Dictionary, scripted_inputs: Array = []) -> void:
	_set_paused(false)
	_force_running()
	_config = config
	_started = true
	_tick = 0
	_fight_time = 0.0
	_result_sent = false
	_recorder.clear()
	if not scripted_inputs.is_empty():
		_recorder.play(scripted_inputs)

	_fights_run += 1

	var rules_in: Dictionary = config.get("rules", {}) as Dictionary
	# The mode has to be known before the world is built: the test arena is a different
	# scene from the Yard.
	_rules_mode = str(rules_in.get("mode", RULES_FIGHT))
	if not _rules_mode in [RULES_TEST, RULES_RUMBLE] and not _rules_mode in RULES_EVENTS:
		_rules_mode = RULES_FIGHT
	# NOTE: this runs BEFORE _build_world, so an event's `setup` sees no arena and no bots
	# (agent E6's point 4). Events therefore arm on their first physics tick rather than in
	# setup, which is what the five already do; `arena_scene_path()` is the one thing read
	# from the event before the world exists, and it is a constant.
	_event = _load_event(_rules_mode)
	# A Rumble is three machines; everything else is two, whatever the config carries.
	var configured: Array = config.get("bots", []) as Array
	_bot_count = clampi(configured.size(), 2, MAX_BOTS) if _rules_mode == RULES_RUMBLE else 2
	_bot_ids = _fill("", _bot_count)
	_bot_names = _fill("", _bot_count)
	_bots = _fill(null, _bot_count)
	_bot_configs = _fill({}, _bot_count)
	_spawn_y = _fill(FightTypes.SPAWN_PLAYER.y, _bot_count)
	# The arena id has to be lifted here too: _build_world runs before _config is read.
	_arena_id = str(config.get("arena", DEFAULT_ARENA))
	if not ARENA_SCENES.has(_arena_id):
		_warn_once("arena_" + _arena_id, "unknown arena '%s'; falling back to the Yard" % _arena_id)
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "warn", "text": "unknown arena '%s'; running the Yard" % _arena_id,
		})
		_arena_id = DEFAULT_ARENA

	# A brand new World3D for every fight, including the first, so fight 1 and fight 7 are
	# built exactly alike and a replay lands on the same physics space the fight did.
	_build_world()

	# A replay is a fight_config carrying the input log the fight recorded. It re-simulates
	# rather than plays back a recording, so everything below is the ordinary fight path.
	var replay: Dictionary = config.get("replay", {}) as Dictionary
	var replay_inputs: Array = replay.get("inputs", []) as Array
	if scripted_inputs.is_empty() and not replay_inputs.is_empty():
		scripted_inputs = replay_inputs
		_recorder.play(scripted_inputs)
	_replaying = not replay_inputs.is_empty()
	_replay_total = scripted_inputs.size()
	_replay_paused = false
	_replay_last_sent = -1
	_seek_to = -1
	if not _replaying:
		_set_replay_speed(1.0)

	var seed_value := int(ResultBuilder.as_number(config.get("seed", 0)))
	_rng.seed = seed_value
	_spike_phase_s = fposmod(float(absi(seed_value) % 600) / 100.0, SPIKE_PERIOD_S)

	var rules: Dictionary = config.get("rules", {}) as Dictionary
	# The test configuration carries no duration_s at all, which is fine: nothing in test
	# mode reads the clock.
	_time_left = float(rules.get("duration_s", FightTypes.FIGHT_DURATION_S))
	_ko_count_s = float(rules.get("ko_count_s", FightTypes.KO_COUNT_S))

	# Fixed order of RNG consumers, because the order IS the seed: the yard takes its
	# spike phase first, then the AI, then each bot's setup.
	if _arena != null and _arena.has_method("setup"):
		_arena.call("setup", _rng)

	# Both drivers are built here and think in a FIXED order every tick (player first,
	# then opponent), because the order they draw from the shared rng in is part of the
	# seed. A driver that is off draws nothing at all, which is fine: what must not change
	# between a fight and its replay is the order of the drivers that DO draw.
	var debug: Dictionary = config.get("debug", {}) as Dictionary
	# A `dummy` opponent is assembled and then left alone: it is a crash test bot, there to
	# be driven into. An explicit debug.opponent_ai still overrides that and wakes it up.
	var opponent_mode := str(debug.get("opponent_ai", OpponentAIScript.MODE_NORMAL))
	if _controller_of(config, 1) == "dummy" and opponent_mode == OpponentAIScript.MODE_NORMAL:
		# The shell sends `debug.opponent_ai` on every configuration, defaulting to
		# "normal" (docs/stage4-swift-notes.md), so "normal" cannot be told apart from the
		# default and the controller has to win. An explicit `charge` or `idle` still
		# overrides, which is what spec §6's "debug.opponent_ai may still make it fight"
		# is for: `-opponentAI charge` wakes the crash test bot up.
		opponent_mode = OpponentAIScript.MODE_OFF
	_ai = _make_driver(opponent_mode, "--roboteer-ai=")
	_player_ai = _make_driver(str(debug.get("player_ai", OpponentAIScript.MODE_OFF)),
		"--roboteer-player-ai=")
	# A Rumble's extra machines each get their OWN RandomNumberGenerator, derived from the
	# fight seed, rather than drawing from the shared one. Two reasons. They would
	# otherwise interleave draws with the first two drivers and change every existing two
	# bot fight that happens to be replayed at three; and three drivers sharing one stream
	# behave identically to each other in the same situation, which looks scripted, which
	# is the thing the jitter exists to avoid.
	_rumble_ai = []
	for i in range(2, _bot_count):
		var own := RandomNumberGenerator.new()
		own.seed = seed_value + i * 7919      # a prime, so the streams do not line up
		var mode := str(debug.get("rumble_ai", OpponentAIScript.MODE_NORMAL))
		var boss_mode := BossAIScript.resolve(str((bot_configs_of(config, i)).get("boss", "")))
		if boss_mode != "":
			_rumble_ai.append(BossAIScript.new(own, boss_mode))
		else:
			_rumble_ai.append(OpponentAIScript.new(own, mode))

	_apply_presentation(config.get("presentation", {}) as Dictionary)
	_spawn_bots(config)

	_tallies = _fill(Rules.empty_tally(), _bot_count)
	_scrap = _fill(0, _bot_count)
	_ko_count = _fill(0.0, _bot_count)
	_last_touch_by = _fill("", _bot_count)
	_last_touch_at = _fill(-999.0, _bot_count)
	_last_fire_at = _fill(-999.0, _bot_count)
	_fire_hit_counted = _fill(true, _bot_count)
	_ooa_flag = _fill(false, _bot_count)
	_last_heading = _fill(Vector2.ZERO, _bot_count)
	_ko_haptic_step = _fill(0, _bot_count)
	_ko_advancing = _fill(false, _bot_count)
	_player_has_driven = false
	_eliminated = []

	_replace_at = _fill(-1.0, _bot_count)
	_enforcer_id = str(rules.get("enforcer", ""))
	_enforcer = null
	_enforcer_ai = null
	_enforcer_withdrawing = false
	_last_contact_s = 0.0
	_contact_since_s = -1.0
	_enforcer_gate = _gate_position()
	_countdown_time = 0.0
	_countdown_step = -1
	_result_shown = false
	_ensure_test_overlay()
	# The pad has to earn the screen again in every fight, and every coach callout is
	# owed again.
	if _controls != null:
		if _controls.has_method("reset_pad_activity"):
			_controls.call("reset_pad_activity")
		if _controls.has_method("reset_input_usage"):
			_controls.call("reset_input_usage")
	# `coach` on the configuration turns the how-to-play callouts on; the test arena
	# always has them, because that IS the place you go to learn what the controls do.
	_hud_call("set_coach", [bool(config.get("coach", false)) or _rules_mode == RULES_TEST])
	_hud_call("set_test_mode", [_rules_mode == RULES_TEST])
	if _hud != null and _hud.has_method("set_bot_names"):
		_hud.call("set_bot_names", str(_bot_names[0]), str(_bot_names[1]))
	if _camera_rig != null and _camera_rig.has_method("set_targets"):
		_camera_rig.call("set_targets", _chassis(_bots[0]), _chassis(_bots[1]))
	_show_fight_view()
	if _replaying:
		_enter_replay_view()
	_set_state(State.COUNTDOWN)


func _apply_presentation(presentation: Dictionary) -> void:
	var safe_area: Dictionary = presentation.get("safe_area_px", {}) as Dictionary
	for target in [_hud, _controls, _camera_rig]:
		if target != null and target.has_method("set_safe_area"):
			target.call("set_safe_area", safe_area)


func _spawn_bots(config: Dictionary) -> void:
	for child in _bots_holder.get_children():
		child.queue_free()
	_bots = _fill(null, _bot_count)
	var bot_configs: Array = config.get("bots", []) as Array
	var packed := _load_scene(BOT_SCENE)
	for i in _bot_count:
		var bot_config: Dictionary = bot_configs[i] as Dictionary
		_bot_configs[i] = bot_config
		_bot_ids[i] = str(bot_config.get("id", ""))
		_bot_names[i] = str(bot_config.get("name", _bot_ids[i]))
		if packed == null:
			continue
		var bot: Node = packed.instantiate()
		bot.name = "Bot%d" % i
		var spawn := _spawn_transform(i)
		_spawn_y[i] = spawn.origin.y
		if bot is Node3D:
			(bot as Node3D).transform = spawn
		_bots_holder.add_child(bot)
		if bot.has_method("setup"):
			bot.call("setup", bot_config, i, _rng)
		# place_at is P's own placement path: it moves the chassis and every part body,
		# which setting the root transform alone cannot do once the joints exist.
		if bot.has_method("place_at"):
			bot.call("place_at", spawn.origin, _spawn_facing(i))
		elif bot is Node3D and (bot as Node3D).global_position.length() < 0.01:
			(bot as Node3D).global_transform = spawn
		_connect_bot(bot, i)
		_bots[i] = bot
	if packed == null:
		_warn_once("bot_scene", BOT_SCENE + " is missing; the fight will run empty to a judges' result")


func _spawn_transform(index: int) -> Transform3D:
	var origin := _spawn_origin(index)
	var facing := _spawn_facing(index)
	var look := Transform3D(Basis(), origin)
	return look.looking_at(origin + facing, Vector3.UP)


func _spawn_origin(index: int) -> Vector3:
	if _arena != null and _arena.has_method("spawn_position"):
		var from_arena: Vector3 = _arena.call("spawn_position", index) as Vector3
		# The arenas only know two marks, and they answer the second one for anything
		# past it, so a Rumble's third machine would start inside the second. Only trust
		# the arena for a mark it actually has.
		if index < 2 or (from_arena.distance_to(_spawn_origin(0)) > 0.5
				and from_arena.distance_to(_spawn_origin(1)) > 0.5):
			return from_arena
	if index == 0:
		return FightTypes.SPAWN_PLAYER
	if index == 1:
		return FightTypes.SPAWN_OPPONENT
	# A Rumble's third machine goes on the corner the two bot diagonal leaves free, so all
	# three start the same distance apart and nobody begins the fight in a corner with two
	# machines already on them.
	return Vector3(FightTypes.SPAWN_OPPONENT.x, FightTypes.SPAWN_PLAYER.y,
		FightTypes.SPAWN_PLAYER.z)


## World direction the bot's nose points at spawn.
func _spawn_facing(index: int) -> Vector3:
	if _arena != null and _arena.has_method("spawn_facing"):
		return _arena.call("spawn_facing", index) as Vector3
	var from := _spawn_origin(index)
	# Everyone faces the middle, which with two machines is each other and with three is
	# the only fair answer.
	var to := Vector3.ZERO if _bot_count > 2 else _spawn_origin(1 - index)
	var flat := Vector3(to.x, 0.0, to.z) - Vector3(from.x, 0.0, from.z)
	return flat.normalized() if flat.length() > 0.0001 else Vector3.RIGHT


func _connect_bot(bot: Node, index: int) -> void:
	if bot.has_signal("damage_event"):
		bot.connect("damage_event", _on_damage_event)
	if bot.has_signal("weapon_fired"):
		bot.connect("weapon_fired", _on_weapon_fired.bind(index))
	if bot.has_signal("part_detached"):
		bot.connect("part_detached", _on_part_detached.bind(index))


# ---------------------------------------------------------------- state machine

func _set_state(next: int) -> void:
	# The "drive to stop the count" pulse belongs to a running fight and nothing else.
	if next != State.FIGHTING and _controls != null \
			and _controls.has_method("set_drive_prompt"):
		_controls.call("set_drive_prompt", false)
	state = next
	var name_for_wire := _state_name(next)
	if name_for_wire != "":
		Bridge.send(FightTypes.MSG_FIGHT_STATE, {"state": name_for_wire})
		state_changed.emit(name_for_wire)


func _state_name(value: int) -> String:
	match value:
		State.COUNTDOWN:
			return "countdown"
		State.FIGHTING:
			return "fighting"
		State.RESULT:
			return "result"
		_:
			return ""


func _tick_countdown(delta: float) -> void:
	_countdown_time += delta
	# Bots are frozen through the countdown: zero input, no timer, no tallies.
	for i in _bot_count:
		_apply_input(i, FightTypes.empty_input())
	# The controls' edge-triggered fire is still drained so a pre-countdown tap does not
	# fire the instant the fight starts.
	_drain_controls_fire()
	var step := int(ceil(maxf(0.0, FightTypes.COUNTDOWN_S - _countdown_time)))
	if step != _countdown_step:
		_countdown_step = step
		if _fx != null and _fx.has_method("on_countdown"):
			_fx.call("on_countdown", step)
	if _countdown_time >= FightTypes.COUNTDOWN_S:
		_set_state(State.FIGHTING)


func _tick_fight(delta: float) -> void:
	_tick += 1
	_fight_time += delta

	_fill_opponent_relative()

	# Fixed rng order: the player's driver thinks first, then the opponent's.
	var player_input := _player_input()
	var ai_input := _ai_input()

	_last_heading[0] = player_input.get("heading", Vector2.ZERO)
	_last_heading[1] = ai_input.get("heading", Vector2.ZERO)
	# Read off the input record, not off the controls, so a replay arms the knockout
	# count on exactly the tick the fight did.
	if not _player_has_driven and (_last_heading[0] as Vector2).length_squared() > 0.0:
		_player_has_driven = true
	_apply_input(0, player_input)
	_apply_input(1, ai_input)
	# The Rumble machines think last, each from its own stream, so the two bot path above
	# is bit for bit what it was.
	for i in range(2, _bot_count):
		var record := _rumble_input(i)
		_last_heading[i] = record.get("heading", Vector2.ZERO)
		_apply_input(i, record)

	if not _recorder.is_playing():
		_recorder.record(_tick, player_input)
	else:
		_recorder.rows.append(FightTypes.replay_row(_tick, player_input))

	if _rules_mode != RULES_TEST:
		_time_left = maxf(0.0, _time_left - delta)

	_update_tallies(delta)
	_tick_enforcer(delta)
	_check_win_conditions(delta)
	_report_weapon_state()
	if _event != null:
		_event.call("physics_tick", delta)
		if bool(_event.call("is_over")):
			_finish_event()
	if _replaying:
		_tick_replay()


# ---------------------------------------------------------------- input

## The player bot's input record for this tick: the AI ghost when `debug.player_ai` is on
## (QA now, the async ladder later), the controls or the replay script otherwise.
func _player_input() -> Dictionary:
	if _player_ai == null:
		return _sample_player_input()
	# The controls are still drained so a queued tap does not survive into a human fight.
	_drain_controls_fire()
	return _player_ai.think(_bots[0], _bots[1], _ai_context())


func _sample_player_input() -> Dictionary:
	if _recorder.is_playing():
		_drain_controls_fire()
		return _recorder.input_for(_tick)

	var heading := Vector2.ZERO
	var fire := false
	var secondary := false

	if _controls != null:
		var control_heading: Variant = _controls.get("heading")
		if control_heading is Vector2:
			heading = control_heading
		# The record's `fire` is the LEVEL, not the tap edge: bot.apply_input derives
		# the edge itself (`fire and not _fire_was`) and hands the weapon both. Nine of
		# the ten weapons are worked by holding the button (a spinner spins up, a
		# crusher closes, a flamethrower burns), and reading only consume_fire() meant
		# a held thumb reached them for exactly one tick and no spinner ever span.
		# consume_fire() is still drained every tick so the tap edge is never lost.
		if _controls.has_method("consume_fire"):
			fire = bool(_controls.call("consume_fire"))
		if _controls.has_method("primary_held") and bool(_controls.call("primary_held")):
			fire = true
		var control_secondary: Variant = _controls.get("secondary")
		if control_secondary != null:
			secondary = bool(control_secondary)

	# Desktop QA keyboard (spec §14). C's FightControls already folds WASD, the arrows,
	# Space and Shift into heading/consume_fire/secondary, so this only runs when
	# controls.tscn is absent and the scene would otherwise be undriveable.
	if _controls == null and OS.has_feature("pc"):
		var keys := Input.get_vector(
			"roboteer_drive_left", "roboteer_drive_right",
			"roboteer_drive_up", "roboteer_drive_down")
		if keys.length() > 0.0:
			heading = keys if keys.length() <= 1.0 else keys.normalized()
		if Input.is_action_just_pressed("roboteer_fire"):
			fire = true
		if Input.is_action_pressed("roboteer_secondary"):
			secondary = true

	if heading.length() > 1.0:
		heading = heading.normalized()
	# The stick is screen space (+x right, +y down) and the drive wants a world XZ
	# direction, so rotate by the camera's yaw here, BEFORE the record is written: what
	# the recorder keeps is the world heading, so a replay is exact whatever the camera
	# did. Without this "up" on the stick meant world -Z, which at the default 45 degree
	# yaw is a diagonal on screen, and the owner reported a bot that "just drives
	# forward" and would not steer.
	heading = _heading_to_world(heading)
	_diag_input(heading)
	return {"heading": heading, "fire": fire, "secondary": secondary}


## Owner-reported "the bot drives itself": one line a second for the opening 20 s of a
## fight, through arena_log, so the shell's file log shows what feeds the drive on a
## device. Presentation only; nothing here touches the record.
const DIAG_SECONDS := 20.0
var _diag_next_tick: int = 0

func _diag_input(world_heading: Vector2) -> void:
	if _tick < _diag_next_tick or float(_tick) * (1.0 / float(FightTypes.TICK_HZ)) > DIAG_SECONDS:
		return
	_diag_next_tick = _tick + int(round(1.0 / (1.0 / float(FightTypes.TICK_HZ))))
	var pads := Input.get_connected_joypads()
	var names: Array = []
	for id in pads:
		names.append("%d:%s" % [id, Input.get_joy_name(id)])
	var raw := Vector2.ZERO
	var present := false
	var active := false
	if _controls != null:
		var h: Variant = _controls.get("heading")
		if h is Vector2:
			raw = h
		if _controls.has_method("pad_present"):
			present = bool(_controls.call("pad_present"))
		if _controls.has_method("pad_active"):
			active = bool(_controls.call("pad_active"))
	var speed := 0.0
	if _bots.size() > 0 and _bots[0] != null and _bots[0].get("chassis") != null:
		speed = (_bots[0].chassis as RigidBody3D).linear_velocity.length()
	Bridge.send(FightTypes.MSG_ARENA_LOG, {"level": "info", "text":
		"diag t=%.1f pads=%s pad_present=%s pad_active=%s lx=%.2f ly=%.2f stick=(%.2f,%.2f) world=(%.2f,%.2f) speed=%.2f" % [
			float(_tick) * (1.0 / float(FightTypes.TICK_HZ)), str(names), str(present), str(active),
			Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y),
			raw.x, raw.y, world_heading.x, world_heading.y, speed]})


## Screen space stick vector -> world XZ heading, relative to the fight camera. Screen up
## is the camera's forward projected onto the floor, screen right is the camera's right.
## Length is preserved (it is the throttle). Without a camera the mapping is identity.
func _heading_to_world(screen: Vector2) -> Vector2:
	if screen == Vector2.ZERO:
		return screen
	var cam := _fight_camera()
	if cam == null:
		return screen
	var basis := cam.global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	var right := basis.x
	right.y = 0.0
	if fwd.length_squared() < 1e-6 or right.length_squared() < 1e-6:
		return screen
	fwd = fwd.normalized()
	right = right.normalized()
	var world := right * screen.x + fwd * (-screen.y)
	return Vector2(world.x, world.z)


## Keep the edge-triggered fire from queueing up outside FIGHTING.
func _drain_controls_fire() -> void:
	if _controls != null and _controls.has_method("consume_fire"):
		_controls.call("consume_fire")


func _ai_input() -> Dictionary:
	if _ai == null:
		return FightTypes.empty_input()
	var foe_index := _foe_index(1)
	return _ai.think(_bots[1], _bots[foe_index] if foe_index >= 0 else _bots[0], _ai_context())


## One Rumble machine's input. Its target is whoever is nearest, so three machines in a
## Rumble converge on whoever is losing rather than politely pairing off.
func _rumble_input(index: int) -> Dictionary:
	var slot := index - 2
	if slot < 0 or slot >= _rumble_ai.size() or _is_eliminated(index):
		return FightTypes.empty_input()
	var foe_index := _foe_index(index)
	if foe_index < 0:
		return FightTypes.empty_input()
	return _rumble_ai[slot].think(_bots[index], _bots[foe_index], _ai_context())


func _ai_context() -> Dictionary:
	var ctx := {
		"tick": _tick,
		"spike_centre": _spike_centre(),
		"spike_rise_in_s": _spike_rise_in_s(),
	}
	# The spike clock says "never" in four of the six arenas, so the arena's own read of
	# what is dangerous goes in beside it. `hazards` is the key boss_ai.gd already reads,
	# which is what makes CINDER throw people at the nastiest thing in any arena.
	if _arena != null and _arena.has_method("hazard_helpers"):
		var helpers: Variant = _arena.call("hazard_helpers")
		if helpers is Dictionary:
			ctx["hazard"] = helpers
			ctx["hazards"] = (helpers as Dictionary).get("danger_positions", [])
	return ctx


## One driver, or none. `off` (and a `dummy` controller, which defaults to off) means no
## OpponentAI is built at all rather than one that returns nothing: a driver that does not
## exist draws nothing from the shared rng, which is the documented rule.
func _make_driver(mode: String, cmdline_prefix: String) -> OpponentAI:
	var chosen := mode
	var override := _cmdline_value(cmdline_prefix)
	if override != "":
		chosen = override
	if chosen == "" or chosen == OpponentAIScript.MODE_OFF:
		return null
	return OpponentAIScript.new(_rng, chosen)


## An array of `size` copies of `value`. Used to size every per bot array to the number of
## machines actually in the fight.
static func _fill(value: Variant, size: int) -> Array:
	var out: Array = []
	for i in size:
		out.append(value.duplicate(true) if value is Dictionary or value is Array else value)
	return out


static func bot_config_at(config: Dictionary, index: int) -> Dictionary:
	var bots: Array = config.get("bots", []) as Array
	return bots[index] as Dictionary if index < bots.size() else {}


func bot_configs_of(config: Dictionary, index: int) -> Dictionary:
	return bot_config_at(config, index)


func _controller_of(config: Dictionary, index: int) -> String:
	var bots: Array = config.get("bots", []) as Array
	if index >= bots.size():
		return ""
	return str((bots[index] as Dictionary).get("controller", ""))


func _apply_input(index: int, input_record: Dictionary) -> void:
	var bot: Node = _bots[index]
	if bot != null and bot.has_method("apply_input"):
		bot.call("apply_input", input_record)


## The weapon's kind, off the bot's own weapon object. "" when it has none.
func _weapon_kind(index: int) -> String:
	var bot: Node = _bots[index] if index >= 0 and index < _bots.size() else null
	if bot == null:
		return ""
	if bot.has_method("weapon_kind"):
		return str(bot.call("weapon_kind"))
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).get("kind") != null:
		return str((weapon as Object).get("kind"))
	return ""


## Presentation: the spin-up loop needs readiness every tick to pitch itself, so the FX is
## told what each weapon is doing. Read only; nothing here changes the fight.
func _report_weapon_state() -> void:
	if _fx == null or not _fx.has_method("on_weapon_state"):
		return
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null or _is_eliminated(i):
			continue
		var kind := _weapon_kind(i)
		if not kind in SPINNING_KINDS:
			continue
		var readiness := 1.0
		if bot.has_method("weapon_readiness"):
			readiness = float(bot.call("weapon_readiness"))
		var last: Dictionary = bot.get("_last_input") if bot.get("_last_input") != null else {}
		_fx.call("on_weapon_state", str(_bot_ids[i]), kind,
			bool(last.get("fire", false)), readiness)


## Spec §4: R fills each bot's opponent_relative every tick, before apply_input.
func _fill_opponent_relative() -> void:
	for i in _bot_count:
		var bot: Node = _bots[i]
		var foe_index := _foe_index(i)
		var foe: Node = _bots[foe_index] if foe_index >= 0 else null
		if bot == null or foe == null:
			continue
		var foe_position := _chassis_position(foe)
		var distance := _chassis_position(bot).distance_to(foe_position)
		if bot.has_method("set_opponent_relative"):
			bot.call("set_opponent_relative", foe_position, distance)
		elif bot.get("opponent_relative") != null:
			bot.set("opponent_relative", {"position": foe_position, "distance": distance})
		else:
			_warn_once("opponent_relative",
				"Bot exposes neither set_opponent_relative() nor an opponent_relative property")


# ---------------------------------------------------------------- tallies

func _update_tallies(delta: float) -> void:
	for i in _bot_count:
		var me: Node = _bots[i]
		var foe_index := _foe_index(i)
		var foe: Node = _bots[foe_index] if foe_index >= 0 else null
		if me == null or foe == null:
			continue
		var my_position := _chassis_position(me)
		var foe_position := _chassis_position(foe)

		# Contacts feed hazard attribution as well as damage events do: a shove that
		# puts them on the spikes leaves no damage_event of its own.
		if my_position.distance_to(foe_position) <= Rules.CONTROL_RANGE_M:
			_last_touch_by[foe_index] = _bot_ids[i]
			_last_touch_at[foe_index] = _fight_time

		if Rules.is_aggressive(my_position, _chassis_velocity(me), foe_position):
			_tallies[i]["aggression_s"] += delta

		var since_contact := _fight_time - float(_last_touch_at[foe_index])
		if _last_touch_by[foe_index] != _bot_ids[i]:
			since_contact = 999.0
		if Rules.is_controlling(
				_is_airborne(foe, foe_index), _is_inverted(foe),
				Rules.is_on_spike_patch(foe_position), since_contact):
			_tallies[i]["control_s"] += delta


func _on_damage_event(info: Dictionary) -> void:
	var victim := str(info.get("victim", ""))
	var victim_index := _index_of(victim)
	var attacker := str(info.get("attacker", ""))
	var severity := float(info.get("severity", 0.0))
	var detached := bool(info.get("detached", false))
	var position: Vector3 = info.get("position", Vector3.ZERO)

	if victim_index >= 0:
		if attacker != "" and attacker != "arena" and attacker != victim:
			_last_touch_by[victim_index] = attacker
			_last_touch_at[victim_index] = _fight_time
		elif attacker == "arena":
			# Hazard damage is credited to whoever put them there, inside the 2 s window.
			var since := _fight_time - float(_last_touch_at[victim_index])
			attacker = Rules.hazard_credit(str(_last_touch_by[victim_index]), since)

	var attacker_index := _index_of(attacker)
	if attacker_index >= 0 and attacker_index != victim_index:
		_tallies[attacker_index]["damage_removed"] += severity
		# A weapon fire that produced damage this soon "made contact" (spec §8). Counted
		# once per fire, not once per contact the fire caused.
		if not bool(_fire_hit_counted[attacker_index]) \
				and _fight_time - float(_last_fire_at[attacker_index]) <= Rules.WEAPON_HIT_WINDOW_S:
			_fire_hit_counted[attacker_index] = true
			_tallies[attacker_index]["weapon_hits"] += 1

		var amount := FightTypes.scrap_for(severity, detached)
		if amount > 0:
			_scrap[attacker_index] += amount
			scrap_awarded.emit(_bot_ids[attacker_index], amount, position)

	_pending_fx.append(info)
	if _test_overlay != null and is_instance_valid(_test_overlay) \
			and _test_overlay.has_method("note_damage_event"):
		_test_overlay.call("note_damage_event", info)


func _on_weapon_fired(index: int) -> void:
	_last_fire_at[index] = _fight_time
	_fire_hit_counted[index] = false
	_pending_weapon_fires.append([str(_bot_ids[index]), _weapon_kind(index)])


func _on_part_detached(part: String, index: int) -> void:
	Bridge.send(FightTypes.MSG_ARENA_LOG, {
		"level": "info", "text": "%s lost %s" % [str(_bot_ids[index]), part],
	})


func _on_ooa_body_entered(body: Node) -> void:
	var index := _bot_index_for_body(body)
	if index >= 0:
		_ooa_flag[index] = true


# ---------------------------------------------------------------- win conditions

func _check_win_conditions(delta: float) -> void:
	# The test arena is a sandbox (brief §10), not a fight. Nothing in it can be won or
	# lost: no clock, no judges, no knockout count, and a bot that goes over the wall is
	# put back rather than beaten (spec §6). Component kill is disabled for the same
	# reason the other three are, even though the spec lists only three: a result sheet
	# in the middle of testing a build would end the session the player is in the middle
	# of. They leave the test arena from the shell, which sends workshop_config.
	if _rules_mode == RULES_TEST:
		_replace_strays()
		return

	# A side event owns its own win condition. The ordinary four would end a Sumo the
	# moment somebody was pushed out, which is the opposite of the point.
	if _event != null:
		return

	# 2. Out of the arena, immediate. In a Rumble it eliminates rather than ending the
	#    fight: the other two carry on (docs/stage6-spec.md §4).
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null or _is_eliminated(i):
			continue
		if bool(_ooa_flag[i]) or Rules.is_out_of_arena(_chassis_position(bot), _arena_half_extent()):
			if _rules_mode == RULES_RUMBLE:
				_eliminate(i, "out_of_arena")
				return
			_finish("out_of_arena", _foe_index(i), i)
			return

	# 4. Component kill.
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null or _is_eliminated(i) or not bot.has_method("condition"):
			continue
		if Rules.is_component_kill(bot.call("condition") as Dictionary):
			if _rules_mode == RULES_RUMBLE:
				_eliminate(i, "component_kill")
				return
			_finish("component_kill", _foe_index(i), i)
			return

	# 1. Knockout: immobile for the full count, movement resets it, a shoving match
	#    freezes it (a pinned bot is being held, not knocked out).
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null or _is_eliminated(i):
			continue
		# The player's count does not start until the player has driven, or ten seconds
		# after the countdown, whichever comes first (Rules.ko_count_armed). Losing by
		# knockout before you have found the controls is not a fight.
		if _is_human_player(i) and not Rules.ko_count_armed(_player_has_driven, _fight_time):
			_ko_count[i] = 0.0
			_ko_advancing[i] = false
			_ko_haptic_step[i] = 0
			continue
		var immobile := bot.has_method("is_immobile") and bool(bot.call("is_immobile"))
		var foe: Node = _bots[_foe_index(i)] if _foe_index(i) >= 0 else null
		var separation := 999.0
		if foe != null:
			separation = _chassis_position(bot).distance_to(_chassis_position(foe))
		var pinned := Rules.is_pinned(separation, (_last_heading[i] as Vector2).length(),
			_is_inverted(bot))
		_ko_advancing[i] = immobile and not pinned
		_ko_count[i] = Rules.ko_count_next(float(_ko_count[i]), immobile, delta, pinned)
		var step := int(floor(float(_ko_count[i])))
		if step > int(_ko_haptic_step[i]):
			_ko_haptic_step[i] = step
			if _fx != null and _fx.has_method("on_ko_tick"):
				_fx.call("on_ko_tick", int(ceil(_ko_count_s - float(_ko_count[i]))))
		elif step == 0:
			_ko_haptic_step[i] = 0
		if Rules.is_knockout(float(_ko_count[i]), _ko_count_s):
			if _rules_mode == RULES_RUMBLE:
				_eliminate(i, "ko")
				return
			_finish("ko", _foe_index(i), i)
			return

	# 3. Judges, on the bell.
	if _time_left <= 0.0:
		_finish("judges", -1, -1)


# ---------------------------------------------------------------- the enforcer

## Brief §8: the bosses are "arena enforcers ... they appear in gauntlet events and to
## punish inactivity". A career fight can name one with `rules.enforcer`, and if the two
## machines go fifteen seconds without touching each other, it comes in from its gate,
## attacks whoever is nearest, and withdraws once they are fighting again.
##
## It is deliberately NOT a third competitor. It takes no scrap, scores no judges' points,
## and no win condition looks at it: it is a hazard with wheels, and a fight it ended would
## be a fight the arena won. It is the third body the Rumble measurement priced
## (docs/stage4-rumble-decision.md), so it stays inside brief §12's cap.
func _tick_enforcer(delta: float) -> void:
	if _rules_mode != RULES_FIGHT or _enforcer_id == "":
		return

	var touching := _bots_in_contact()
	if touching:
		_last_contact_s = _fight_time
		if _contact_since_s < 0.0:
			_contact_since_s = _fight_time
	else:
		_contact_since_s = -1.0

	if _enforcer == null or not is_instance_valid(_enforcer):
		if _fight_time - _last_contact_s >= ENFORCER_IDLE_S:
			_send_in_enforcer()
		return

	# On the floor. Contact back for three seconds and it goes home.
	if not _enforcer_withdrawing and _contact_since_s >= 0.0 \
			and _fight_time - _contact_since_s >= ENFORCER_CALM_S:
		_enforcer_withdrawing = true
		Bridge.send(FightTypes.MSG_ARENA_LOG, {
			"level": "info", "text": "%s withdraws" % _enforcer_id,
		})

	var chassis := _chassis(_enforcer)
	var at := chassis.global_position if chassis != null else Vector3.ZERO
	if _enforcer_withdrawing:
		var home := Vector3(_enforcer_gate.x - at.x, 0.0, _enforcer_gate.z - at.z)
		if home.length() <= ENFORCER_HOME_M:
			_remove_enforcer()
			return
		_apply_enforcer_input({
			"heading": BossAIScript.heading_from_world_dir(home),
			"fire": false, "secondary": false,
		})
		return

	var target := _nearest_bot_to(at)
	if target == null:
		_remove_enforcer()
		return
	_apply_enforcer_input(_enforcer_ai.think(_enforcer, target, _enforcer_context()))


func _bots_in_contact() -> bool:
	if _bots[0] == null or _bots[1] == null:
		return true          # nothing to be idle about
	return _chassis_position(_bots[0]).distance_to(_chassis_position(_bots[1])) <= ENFORCER_CONTACT_M


## The gate: the corner of the arena opposite both spawns. The Stage 3 spawns sit on the
## -X-Z to +X+Z diagonal, so the other diagonal is clear, and its +X-Z end is 7.6 m from
## each of them: far enough that the enforcer's entrance is an entrance and not an ambush.
func _gate_position() -> Vector3:
	var inset := FightTypes.ARENA_SIZE * 0.5 - 0.7
	return Vector3(inset, FightTypes.SPAWN_PLAYER.y, -inset)


func _send_in_enforcer() -> void:
	var packed := _load_scene(BOT_SCENE)
	if packed == null or _bots_holder == null:
		return
	var config := BossAIScript.build_for(_enforcer_id, ENFORCER_ID)
	var bot: Node = packed.instantiate()
	bot.name = "Enforcer"
	_bots_holder.add_child(bot)
	if bot.has_method("setup"):
		bot.call("setup", config, 1, _rng)
	if bot.has_method("place_at"):
		bot.call("place_at", _enforcer_gate, Vector3(-1.0, 0.0, 0.0))
	# Its damage events still reach the overlay and the FX, but nothing scores them: it is
	# not in `_bot_ids`, so `_index_of` returns -1 for it and no tally or scrap is credited.
	if bot.has_signal("damage_event"):
		bot.connect("damage_event", _on_damage_event)
	_enforcer = bot
	_enforcer_ai = BossAIScript.new(_rng, _enforcer_id)
	_enforcer_ai.gate = _enforcer_gate
	_enforcer_withdrawing = false
	Bridge.send(FightTypes.MSG_ARENA_LOG, {
		"level": "info",
		"text": "%s enters: no contact for %0.f s" % [_enforcer_id, ENFORCER_IDLE_S],
	})


func _remove_enforcer() -> void:
	if _enforcer != null and is_instance_valid(_enforcer):
		_enforcer.queue_free()
	_enforcer = null
	_enforcer_ai = null
	_enforcer_withdrawing = false
	_last_contact_s = _fight_time


func _apply_enforcer_input(record: Dictionary) -> void:
	if _enforcer != null and _enforcer.has_method("apply_input"):
		_enforcer.call("apply_input", record)


func _enforcer_context() -> Dictionary:
	var ctx := _ai_context()
	ctx["hazards"] = _hazards()
	return ctx


## Where the arena would like things thrown. CINDER aims at the nearest of these.
func _hazards() -> Array:
	var ctx := _ai_context()
	var hazards: Variant = ctx.get("hazards", [])
	if hazards is Array and not (hazards as Array).is_empty():
		return hazards as Array
	return [_spike_centre()]


## The machine bot `index` is fighting right now. With two bots that is always the other
## one, which is exactly what `1 - i` used to mean; with three it is the nearest one still
## in the fight, so a Rumble is scored against whoever is actually on you.
func _foe_index(index: int) -> int:
	var best := -1
	var best_d := INF
	var at := _chassis_position(_bots[index])
	for j in _bot_count:
		if j == index or _bots[j] == null or _is_eliminated(j):
			continue
		var d := at.distance_to(_chassis_position(_bots[j]))
		if d < best_d:
			best_d = d
			best = j
	return best


func _is_eliminated(index: int) -> bool:
	return _eliminated.has(str(_bot_ids[index]))


## Still in the fight: built, not eliminated.
func _live_indices() -> Array:
	var live: Array = []
	for i in _bot_count:
		if _bots[i] != null and not _is_eliminated(i):
			live.append(i)
	return live


func _nearest_bot_to(at: Vector3) -> Node:
	var best: Node = null
	var best_d := INF
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null:
			continue
		var d := _chassis_position(bot).distance_to(at)
		if d < best_d:
			best_d = d
			best = bot
	return best


## Rumble: a machine that is knocked out, destroyed or thrown out is done, and the fight
## carries on without it. The last one still moving wins.
func _eliminate(index: int, how: String) -> void:
	var id := str(_bot_ids[index])
	if id == "" or _eliminated.has(id):
		return
	_eliminated.append(id)
	var bot: Node = _bots[index]
	if bot != null and bot.has_method("freeze"):
		bot.call("freeze")
	Bridge.send(FightTypes.MSG_ARENA_LOG, {
		"level": "info", "text": "%s is out: %s" % [id, how],
	})
	var live := _live_indices()
	if live.size() <= 1:
		_finish(how, live[0] if live.size() == 1 else -1, index)


## Test mode only: a bot that leaves the arena is set back on its mark after two seconds,
## in whatever condition it left in. Two seconds so the player sees where it went.
func _replace_strays() -> void:
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot == null:
			continue
		var gone := bool(_ooa_flag[i]) or Rules.is_out_of_arena(_chassis_position(bot), _arena_half_extent())
		if gone and float(_replace_at[i]) < 0.0:
			_replace_at[i] = _fight_time + TEST_REPLACE_S
		if float(_replace_at[i]) >= 0.0 and _fight_time >= float(_replace_at[i]):
			_replace_at[i] = -1.0
			_ooa_flag[i] = false
			_replace_bot(i)


func _replace_bot(index: int) -> void:
	set_down(_bots[index], _spawn_origin(index), _spawn_facing(index))


## Put a machine back on a mark, upright and still, after it has already simulated.
##
## NOT `Bot.place_at`, which is an initial placement: it sets the root transform, and once
## a machine has been fighting its part bodies have drifted from their assembled offsets,
## so setting the root moves the whole assembly by a delta instead of onto the mark.
## Measured by agent E6: a bot at x 4.41 sent to a 2.5 mark landed at 3.71.
##
## So this computes the rigid transform that carries the CHASSIS onto the mark and applies
## that same transform to every part, which moves the machine as one object however bent it
## has become. Generalised from E6's `sumo.gd._set_down`, including its trap: moving the
## root already drags every child's global transform by `fix`, so each part's target has to
## be computed BEFORE the root moves and applied after, or `fix` lands twice (E6 measured a
## machine asked for (-4.00, 0.62, 1.25) arriving at (-8.09, 1.09, -0.71), which is exactly
## `fix` squared).
func set_down(bot: Node, mark: Vector3, facing: Vector3) -> void:
	if bot == null:
		return
	var chassis: Variant = bot.get("chassis")
	if not (chassis is RigidBody3D) or not (bot is Node3D):
		if bot.has_method("place_at"):
			bot.call("place_at", mark, facing)
		return
	var body: RigidBody3D = chassis
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.RIGHT
	flat = flat.normalized()
	var ride := float(bot.call("ride_height")) if bot.has_method("ride_height") else 0.11
	var want := Transform3D(Basis(Vector3.UP, atan2(-flat.z, flat.x)),
		Vector3(mark.x, maxf(mark.y, ride), mark.z))
	var now := body.global_transform
	now.basis = now.basis.orthonormalized()
	var fix := want * now.affine_inverse()

	var parts: Array = bot.call("attached_parts") if bot.has_method("attached_parts") else []
	var targets: Array[Transform3D] = []
	for part_variant in parts:
		targets.append(fix * (part_variant as Node3D).global_transform)
	(bot as Node3D).global_transform = fix * (bot as Node3D).global_transform
	for i in range(parts.size()):
		var part: RigidBody3D = parts[i] as RigidBody3D
		if part == null or not is_instance_valid(part):
			continue
		part.global_transform = targets[i]
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


func _finish(outcome_type: String, winner_index: int, loser_index: int) -> void:
	if _result_sent:
		return
	_result_sent = true

	var judges: Dictionary = {}
	for i in _bot_count:
		judges[_bot_ids[i]] = Rules.judge_scores(_tallies[i])

	if outcome_type == "judges":
		# Two bots: the Stage 3 rule, unchanged. Three: every machine still in the fight is
		# scored on its own card and the best card wins, with the same tiebreaks. An
		# eliminated machine cannot win on points, which is the whole reason to survive.
		var contenders := _live_indices() if _rules_mode == RULES_RUMBLE else [0, 1]
		if contenders.is_empty():
			contenders = [0, 1]
		winner_index = int(contenders[0])
		for entry in contenders:
			var candidate := int(entry)
			if candidate == winner_index:
				continue
			if Rules.judges_winner_index(_tallies[candidate], _tallies[winner_index]) == 0:
				winner_index = candidate
		loser_index = _foe_index(winner_index)
		if loser_index < 0:
			loser_index = 1 - winner_index if _bot_count == 2 else -1

	var damage: Dictionary = {}
	var scrap: Dictionary = {}
	var config_bots: Array = _config.get("bots", []) as Array
	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot != null and bot.has_method("condition"):
			damage[_bot_ids[i]] = bot.call("condition")
		elif i < config_bots.size():
			damage[_bot_ids[i]] = (config_bots[i] as Dictionary).get("damage", {})
		scrap[_bot_ids[i]] = int(_scrap[i])

	var result := ResultBuilder.build({
		"config": _config,
		"outcome_type": outcome_type,
		"winner": _bot_ids[winner_index] if winner_index >= 0 else "",
		"loser": _bot_ids[loser_index] if loser_index >= 0 else "",
		"at_s": _fight_time,
		"duration_s": _fight_time,
		"judges": judges,
		"damage": damage,
		"scrap": scrap,
		"replay_inputs": _recorder.to_inputs(),
		"ticks_msec_at_config": _ticks_msec_at_config,
		"ticks_msec_at_result": Time.get_ticks_msec(),
		"physics_ticks": _tick,
		"eliminated": _eliminated.duplicate(),
	})

	_hud_banner = Rules.banner_for(outcome_type)
	_hud_winner = str(_bot_names[winner_index]) if winner_index >= 0 else ""

	for i in _bot_count:
		var bot: Node = _bots[i]
		if bot != null and bot.has_method("freeze"):
			bot.call("freeze")
	if _controls != null and _controls.has_method("set_enabled"):
		_controls.call("set_enabled", false)
	if _camera_rig != null and _camera_rig.has_method("begin_wreckage_orbit") and loser_index >= 0:
		_camera_rig.call("begin_wreckage_orbit", _chassis(_bots[loser_index]))
	if _fx != null and _fx.has_method("on_bell"):
		_fx.call("on_bell")

	_set_state(State.RESULT)
	if _replaying:
		# A replay produces no result: the fight it is replaying already produced one, and
		# a second one would be written into the machine's record as a second fight.
		Bridge.send(MSG_REPLAY_STATE, {
			"tick": _tick, "total": _replay_total, "finished": true,
		})
	else:
		Bridge.send(FightTypes.MSG_FIGHT_RESULT, result)


# ---------------------------------------------------------------- presentation (never gameplay)

func _update_presentation(_delta: float) -> void:
	# Paused: the HUD and the controls below still update (the shell draws its overlay
	# over a live picture), but the FX queues are NOT drained. They are simulation
	# events, and the FX layer answers them by putting debris bodies into the physics
	# space: spilling them into a frozen world moved the bots by a metre and a half over
	# the next twelve seconds, which is exactly what tests/pause_test.gd catches. They
	# wait, in order, for the tick that resumes.
	if _paused:
		_update_hud_and_controls()
		return
	for info_variant in _pending_fx:
		var info: Dictionary = info_variant as Dictionary
		if _fx != null and _fx.has_method("on_damage_event"):
			_fx.call("on_damage_event", info)
		_mark_damage(info)
	_pending_fx.clear()
	for entry in _pending_weapon_fires:
		var fired: Array = entry as Array
		if _fx != null and _fx.has_method("on_weapon_fired"):
			_fx.call("on_weapon_fired", str(fired[0]), str(fired[1]))
	_pending_weapon_fires.clear()

	# The camera frames the player and the nearest LIVE opponent, which after an
	# elimination or in a Rumble is not always bot 1.
	if _camera_rig != null and is_instance_valid(_camera_rig) \
			and _camera_rig.has_method("set_targets") and state != State.RESULT:
		var foe := _foe_index(0)
		if _bots[0] != null and foe >= 0 and foe < _bots.size() and _bots[foe] != null:
			_camera_rig.call("set_targets", _chassis(_bots[0]), _chassis(_bots[foe]))

	_update_offscreen_marker()
	_update_hud_and_controls()


## While the camera is holding the player-priority floor the opponent can be outside the
## frame. Work out which way it is from the fight camera and let the HUD draw an arrow at
## that edge. Presentation only, and never while the fight is not running.
func _update_offscreen_marker() -> void:
	if _hud == null or not _hud.has_method("set_offscreen_marker"):
		return
	var foe := _foe_index(0)
	var cam := _fight_camera()
	if _view != VIEW_FIGHT or state != State.FIGHTING or cam == null \
			or foe < 0 or foe >= _bots.size() or _bots[foe] == null:
		_hud.call("set_offscreen_marker", false, Vector2.ZERO, "")
		return
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if size.x <= 1.0 or size.y <= 1.0:
		_hud.call("set_offscreen_marker", false, Vector2.ZERO, "")
		return
	var at := _chassis_position(_bots[foe])
	var behind := cam.is_position_behind(at)
	var screen := cam.unproject_position(at)
	var centre := size * 0.5
	var direction := screen - centre
	if behind:
		# Behind the camera the projection is mirrored, so the honest direction is the
		# other way; without this the arrow points at the wrong edge.
		direction = -direction
	if direction.length_squared() < 1.0:
		direction = Vector2.UP
	var off_screen := behind or screen.x < 0.0 or screen.x > size.x \
		or screen.y < 0.0 or screen.y > size.y
	_hud.call("set_offscreen_marker", off_screen, direction.normalized(),
		str(_bot_names[foe]))


## The presentation that is safe to run whether or not the simulation is frozen: the
## touch controls' own state and the HUD. Nothing here queues anything into the world.
func _update_hud_and_controls() -> void:
	if _controls != null and _controls.has_method("set_enabled"):
		_controls.call("set_enabled", state == State.FIGHTING and not _paused)
	# The countdown DRAWS the furniture without taking input, so the coach callouts have
	# something to point at instead of empty corners until the bell.
	if _controls != null and _controls.has_method("set_preview"):
		_controls.call("set_preview", state == State.COUNTDOWN)
	if _controls != null and _bots[0] != null:
		var player: Node = _bots[0]
		if _controls.has_method("set_state"):
			var gas: Variant = player.get("gas_charges")
			_controls.call("set_state", _is_inverted(player), int(gas) if gas != null else 0)
		# The primary button names what the FITTED weapon does, and carries a spin-up
		# ring when the weapon's readiness really is a spin fraction.
		if _controls.has_method("set_weapon"):
			var readiness := -1.0
			if player.has_method("weapon_readiness"):
				readiness = float(player.call("weapon_readiness"))
			_controls.call("set_weapon", _weapon_kind(0), readiness)

	if _hud == null or _view != VIEW_FIGHT:
		return
	match state:
		State.COUNTDOWN:
			_hud_call("set_coach_phase", [FightHud.COACH_COUNTDOWN])
			var remaining := FightTypes.COUNTDOWN_S - _countdown_time
			_hud_call("show_countdown", ["FIGHT" if remaining <= 0.0 else str(int(ceil(remaining)))])
		State.FIGHTING:
			_hud_call("set_coach_phase", [FightHud.COACH_FIGHTING])
			_hud_call("hide_countdown", [])
			_hud_call("set_scrap", [int(_scrap[0])])
			if _event != null:
				var lines: Array = _event.call("hud_lines")
				_hud_call("set_height_readout", ["  ".join(lines)] if not lines.is_empty() else [""])
			else:
				_hud_call("set_height_readout", [height_readout()])
			if _rules_mode == RULES_TEST:
				# No clock and no count in the test arena, so the HUD shows neither.
				_hud_call("hide_ko_count", [])
			else:
				_hud_call("set_time_left", [_time_left])
				var readout := ko_count_display()
				var prompt := bool(readout["show"]) and bool(readout["is_player"]) \
					and not _player_has_driven
				if bool(readout["show"]):
					_hud_call("show_ko_count",
						[int(readout["seconds_left"]), str(readout["name"]),
						bool(readout["is_player"])])
				else:
					_hud_call("hide_ko_count", [])
				if _controls != null and _controls.has_method("set_drive_prompt"):
					_controls.call("set_drive_prompt", prompt)
		State.RESULT:
			if not _result_shown:
				_result_shown = true
				_hud_call("set_coach_phase", ["result"])
				_hud_call("hide_countdown", [])
				_hud_call("hide_ko_count", [])
				_hud_call("show_result", [_hud_banner, _hud_winner])
		_:
			pass


## Leave a mark where a machine was hit. Presentation, from the _process drain: a decal is
## a picture and must never be able to change a fight.
##
## The surface normal is not in the damage_event payload, so it is taken as the direction
## from the victim's chassis out through the hit, which on a hull of flat plates is the
## face that was struck. Up is the fallback, and a `normal` key is used if one ever arrives.
func _mark_damage(info: Dictionary) -> void:
	if _decals == null or not is_instance_valid(_decals):
		return
	var at: Vector3 = info.get("position", Vector3.ZERO)
	var severity := clampf(float(info.get("severity", 0.0)), 0.0, 1.0)
	var size := SCRATCH_MIN_M + (SCRATCH_MAX_M - SCRATCH_MIN_M) * severity

	if _is_burn(info):
		if _decals.has_method("add_scorch"):
			_decals.call("add_scorch", at, size)
		return
	if _decals.has_method("add_scratch"):
		_decals.call("add_scratch", at, _surface_normal(info, at), size)


## Burns scorch, blows scratch. A damage_event carries no source, so this reads the one
## thing that does say: the attacker's weapon. `source` is honoured if it ever appears.
func _is_burn(info: Dictionary) -> bool:
	var source := str(info.get("source", ""))
	if source in ["burn", "flame"]:
		return true
	return _weapon_kind(_index_of(str(info.get("attacker", "")))) == "flame"


func _surface_normal(info: Dictionary, at: Vector3) -> Vector3:
	var given: Variant = info.get("normal", null)
	if given is Vector3 and (given as Vector3).length() > 0.0001:
		return (given as Vector3).normalized()
	var victim := _index_of(str(info.get("victim", "")))
	if victim >= 0:
		var out := at - _chassis_position(_bots[victim])
		if out.length() > 0.01:
			return out.normalized()
	return Vector3.UP


## The arena's flame jets scorch the floor they play over.
func _on_hazard_decal(kind: String, active: bool, position: Vector3) -> void:
	if not active or kind != "flame" or _decals == null or not is_instance_valid(_decals):
		return
	if _decals.has_method("add_scorch"):
		_decals.call("add_scorch", position, SCRATCH_MAX_M)


## What the HUD should say about the knockout count, if anything. Public because it is the
## whole of the display rule and the test drives it directly rather than through a HUD.
##   {"show": bool, "seconds_left": int, "name": String}
## Bot slot `index` is the one a human is driving: slot 0, controlled by "player", and
## not handed to the debug AI ghost.
func _is_human_player(index: int) -> bool:
	return index == 0 and _player_ai == null and _controller_of(_config, 0) == "player"


## Whether the player has asked for any drive yet in this fight.
func player_has_driven() -> bool:
	return _player_has_driven


func ko_count_display() -> Dictionary:
	var index := 0 if float(_ko_count[0]) >= float(_ko_count[1]) else 1
	var seconds := float(_ko_count[index])
	return {
		"show": Rules.should_show_ko_count(seconds, bool(_ko_advancing[index])),
		"seconds_left": int(ceil(_ko_count_s - seconds)),
		"name": str(_bot_names[index]),
		# A count running on the player's own machine gets the "drive to stop it" line
		# and pulses the resting stick, because not knowing how to drive is exactly how
		# a player gets here.
		"is_player": _is_human_player(index),
	}


## "Your wedge: floor. Their flipper: mid." Plain sentences, no em dashes (brief §2).
func height_readout() -> String:
	var bots: Array = _config.get("bots", []) as Array
	var your_part := "wedge"
	var their_part := "weapon"
	if bots.size() > 0:
		your_part = str((bots[0] as Dictionary).get("chassis", "wedge"))
	if bots.size() > 1:
		their_part = str((bots[1] as Dictionary).get("weapon", "weapon"))
	var your_band := "floor"
	var their_band := "mid"
	var me: Node = _bots[0]
	var foe: Node = _bots[1]
	if me != null and me.has_method("front_edge_height"):
		your_band = Rules.height_band(float(me.call("front_edge_height")))
	if foe != null and foe.has_method("weapon_height_band"):
		their_band = str(foe.call("weapon_height_band"))
	return Rules.height_sentence(your_part, your_band, their_part, their_band)


func _hud_call(method: String, args: Array) -> void:
	if _hud != null and _hud.has_method(method):
		_hud.callv(method, args)


## Live chassis position by bot id. FightFx.bind() takes this so the bolt shower can
## magnetise toward a bot that is moving, without holding a reference to it.
func bot_position_by_id(bot_id: String) -> Vector3:
	var index := _index_of(bot_id)
	return _chassis_position(_bots[index]) if index >= 0 else Vector3.ZERO


# ---------------------------------------------------------------- small helpers

func _spike_rise_in_s() -> float:
	if _arena != null and _arena.has_method("seconds_to_spike_rise"):
		return float(_arena.call("seconds_to_spike_rise"))
	var phase := fposmod(_fight_time + _spike_phase_s, SPIKE_PERIOD_S)
	if phase < SPIKE_UP_S:
		return 0.0
	return SPIKE_PERIOD_S - phase


## The arena's own size, because they are not all 10 m across: the Coliseum is 12.
func _arena_size() -> float:
	if _arena != null and _arena.has_method("arena_size"):
		return float(_arena.call("arena_size"))
	return FightTypes.ARENA_SIZE


func _arena_half_extent() -> float:
	if _arena != null and _arena.has_method("arena_half_extent"):
		return float(_arena.call("arena_half_extent"))
	return _arena_size() * 0.5


func _spike_centre() -> Vector3:
	if _arena != null and _arena.has_method("spike_patch_centre"):
		return _arena.call("spike_patch_centre") as Vector3
	return Vector3.ZERO


func _index_of(bot_id: String) -> int:
	if bot_id == "" or bot_id == "arena":
		return -1
	for i in _bot_count:
		if _bot_ids[i] == bot_id:
			return i
	return -1


func _bot_index_for_body(body: Node) -> int:
	var node: Node = body
	while node != null:
		for i in _bot_count:
			if _bots[i] != null and node == _bots[i]:
				return i
		node = node.get_parent()
	return -1


func _chassis(bot: Node) -> Node3D:
	if bot == null:
		return null
	var chassis: Variant = bot.get("chassis")
	if chassis is Node3D:
		return chassis as Node3D
	return bot as Node3D


func _chassis_position(bot: Node) -> Vector3:
	var chassis := _chassis(bot)
	return chassis.global_position if chassis != null else Vector3.ZERO


func _chassis_velocity(bot: Node) -> Vector3:
	var chassis := _chassis(bot)
	if chassis is RigidBody3D:
		return (chassis as RigidBody3D).linear_velocity
	return Vector3.ZERO


## No is_airborne() in the Bot API, so it is inferred from the chassis clearance above its
## spawn height. Replaced by bot.is_airborne() the moment P provides one.
func _is_airborne(bot: Node, index: int) -> bool:
	if bot == null:
		return false
	if bot.has_method("is_airborne"):
		return bool(bot.call("is_airborne"))
	return _chassis_position(bot).y > float(_spawn_y[index]) + Rules.AIRBORNE_CLEARANCE_M


func _is_inverted(bot: Node) -> bool:
	return bot != null and bot.has_method("is_inverted") and bool(bot.call("is_inverted"))


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("Fight: " + message)
	print("Fight: ", message)
