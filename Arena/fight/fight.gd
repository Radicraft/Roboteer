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

const SCHEMA := 1
const FIXTURE_PATH := "res://fight/fixtures/stage3_config.json"

## Scenes owned by the other Stage 3 agents. Missing ones are warned about, not fatal.
const WORLD_SCENE := "res://fight/fight_world.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
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

var _stage: SubViewportContainer = null
var _world: SubViewport = null
var _arena: Node = null
var _bots_holder: Node3D = null
var _debris: Node3D = null
var _camera_rig: Node = null
var _hud: Node = null
var _fx: Node = null
var _controls: Node = null

var _bots: Array = [null, null]          # index 0 player, 1 opponent
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
var _warned: Dictionary = {}
var _fights_run: int = 0


# ---------------------------------------------------------------- lifecycle

func _ready() -> void:
	_stage = $Stage
	_wire_ui()
	_build_world()
	Bridge.message_received.connect(_on_message_received)
	if Bridge.is_attached():
		_send_arena_ready()
	_set_state(State.LOADING)


func _process(delta: float) -> void:
	if not _started:
		_frames += 1
		if _frames >= AUTOSTART_FRAMES and not Bridge.is_attached():
			_autostart()
	_update_presentation(delta)


func _physics_process(delta: float) -> void:
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


## Build a brand new 3D world for one fight and throw the previous one away.
##
## Every fight gets its own SubViewport with `own_world_3d`, which means its own World3D
## and its own physics space. That is not tidiness: two fights run back to back in one
## space do not reproduce each other (see docs/stage3-rules-notes.md), and the shipping
## app runs fight after fight in a single never restarted Godot process, so a replay would
## never match the fight it replays. A fresh world per fight is what makes the replay and
## the async ladder in brief section 10 possible at all.
func _build_world() -> void:
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
	_stage.add_child(_world)

	_bots_holder = _world.get_node("Bots") as Node3D
	_debris = _world.get_node("Debris") as Node3D
	_arena = _swap_in(_world, "Arena", YARD_SCENE)
	_camera_rig = _swap_in(_world, "CameraRig", CAMERA_RIG_SCENE)
	_fx = _swap_in(_world, "FX", FX_SCENE)

	_bots = [null, null]
	_connect_ooa_sensor()
	if _fx != null and _fx.has_method("on_scrap_awarded"):
		scrap_awarded.connect(Callable(_fx, "on_scrap_awarded"))
	if _fx != null and _fx.has_method("bind"):
		_fx.call("bind", _hud, Callable(self, "bot_position_by_id"))
	if _camera_rig != null:
		if _camera_rig.has_method("fit_arena"):
			_camera_rig.call("fit_arena", FightTypes.ARENA_SIZE)
		if _camera_rig.has_method("bind_controls") and _controls != null:
			_camera_rig.call("bind_controls", _controls)


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
	_config = config
	_started = true
	_tick = 0
	_fight_time = 0.0
	_result_sent = false
	_recorder.clear()
	if not scripted_inputs.is_empty():
		_recorder.play(scripted_inputs)

	_fights_run += 1

	# A brand new World3D for every fight, including the first, so fight 1 and fight 7 are
	# built exactly alike and a replay lands on the same physics space the fight did.
	_build_world()

	var seed_value := int(ResultBuilder.as_number(config.get("seed", 0)))
	_rng.seed = seed_value
	_spike_phase_s = fposmod(float(absi(seed_value) % 600) / 100.0, SPIKE_PERIOD_S)

	var rules: Dictionary = config.get("rules", {}) as Dictionary
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
	_ai = OpponentAIScript.new(_rng, str(debug.get("opponent_ai", OpponentAIScript.MODE_NORMAL)))
	_player_ai = _make_player_ai(str(debug.get("player_ai", OpponentAIScript.MODE_OFF)))

	_apply_presentation(config.get("presentation", {}) as Dictionary)
	_spawn_bots(config)

	_tallies = [Rules.empty_tally(), Rules.empty_tally()]
	_scrap = [0, 0]
	_ko_count = [0.0, 0.0]
	_last_touch_by = ["", ""]
	_last_touch_at = [-999.0, -999.0]
	_last_fire_at = [-999.0, -999.0]
	_fire_hit_counted = [true, true]
	_ooa_flag = [false, false]
	_last_heading = [Vector2.ZERO, Vector2.ZERO]
	_ko_haptic_step = [0, 0]

	_countdown_time = 0.0
	_countdown_step = -1
	_result_shown = false
	if _hud != null and _hud.has_method("set_bot_names"):
		_hud.call("set_bot_names", str(_bot_names[0]), str(_bot_names[1]))
	if _camera_rig != null and _camera_rig.has_method("set_targets"):
		_camera_rig.call("set_targets", _chassis(_bots[0]), _chassis(_bots[1]))
	_set_state(State.COUNTDOWN)


func _apply_presentation(presentation: Dictionary) -> void:
	var safe_area: Dictionary = presentation.get("safe_area_px", {}) as Dictionary
	for target in [_hud, _controls, _camera_rig]:
		if target != null and target.has_method("set_safe_area"):
			target.call("set_safe_area", safe_area)


func _spawn_bots(config: Dictionary) -> void:
	for child in _bots_holder.get_children():
		child.queue_free()
	_bots = [null, null]
	var bot_configs: Array = config.get("bots", []) as Array
	var packed := _load_scene(BOT_SCENE)
	for i in 2:
		var bot_config: Dictionary = bot_configs[i] as Dictionary
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
		return _arena.call("spawn_position", index) as Vector3
	return FightTypes.SPAWN_PLAYER if index == 0 else FightTypes.SPAWN_OPPONENT


## World direction the bot's nose points at spawn.
func _spawn_facing(index: int) -> Vector3:
	if _arena != null and _arena.has_method("spawn_facing"):
		return _arena.call("spawn_facing", index) as Vector3
	var from := _spawn_origin(index)
	var to := _spawn_origin(1 - index)
	return (Vector3(to.x, 0.0, to.z) - Vector3(from.x, 0.0, from.z)).normalized()


func _connect_bot(bot: Node, index: int) -> void:
	if bot.has_signal("damage_event"):
		bot.connect("damage_event", _on_damage_event)
	if bot.has_signal("weapon_fired"):
		bot.connect("weapon_fired", _on_weapon_fired.bind(index))
	if bot.has_signal("part_detached"):
		bot.connect("part_detached", _on_part_detached.bind(index))


# ---------------------------------------------------------------- state machine

func _set_state(next: int) -> void:
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
	for i in 2:
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
	_apply_input(0, player_input)
	_apply_input(1, ai_input)

	if not _recorder.is_playing():
		_recorder.record(_tick, player_input)
	else:
		_recorder.rows.append(FightTypes.replay_row(_tick, player_input))

	_time_left = maxf(0.0, _time_left - delta)

	_update_tallies(delta)
	_check_win_conditions(delta)


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
		if _controls.has_method("consume_fire"):
			fire = bool(_controls.call("consume_fire"))
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
	return {"heading": heading, "fire": fire, "secondary": secondary}


## Keep the edge-triggered fire from queueing up outside FIGHTING.
func _drain_controls_fire() -> void:
	if _controls != null and _controls.has_method("consume_fire"):
		_controls.call("consume_fire")


func _ai_input() -> Dictionary:
	if _ai == null:
		return FightTypes.empty_input()
	return _ai.think(_bots[1], _bots[0], _ai_context())


func _ai_context() -> Dictionary:
	return {
		"tick": _tick,
		"spike_centre": _spike_centre(),
		"spike_rise_in_s": _spike_rise_in_s(),
	}


## `debug.player_ai` is off unless asked for. `--roboteer-player-ai=` overrides it on the
## desktop the same way `--roboteer-ai=` overrides the opponent.
func _make_player_ai(mode: String) -> OpponentAI:
	var chosen := mode
	var override := _cmdline_value("--roboteer-player-ai=")
	if override != "":
		chosen = override
	if chosen == "" or chosen == OpponentAIScript.MODE_OFF:
		return null
	return OpponentAIScript.new(_rng, chosen)


func _apply_input(index: int, input_record: Dictionary) -> void:
	var bot: Node = _bots[index]
	if bot != null and bot.has_method("apply_input"):
		bot.call("apply_input", input_record)


## Spec §4: R fills each bot's opponent_relative every tick, before apply_input.
func _fill_opponent_relative() -> void:
	for i in 2:
		var bot: Node = _bots[i]
		var foe: Node = _bots[1 - i]
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
	for i in 2:
		var me: Node = _bots[i]
		var foe: Node = _bots[1 - i]
		if me == null or foe == null:
			continue
		var my_position := _chassis_position(me)
		var foe_position := _chassis_position(foe)

		# Contacts feed hazard attribution as well as damage events do: a shove that
		# puts them on the spikes leaves no damage_event of its own.
		if my_position.distance_to(foe_position) <= Rules.CONTROL_RANGE_M:
			_last_touch_by[1 - i] = _bot_ids[i]
			_last_touch_at[1 - i] = _fight_time

		if Rules.is_aggressive(my_position, _chassis_velocity(me), foe_position):
			_tallies[i]["aggression_s"] += delta

		var since_contact := _fight_time - float(_last_touch_at[1 - i])
		if _last_touch_by[1 - i] != _bot_ids[i]:
			since_contact = 999.0
		if Rules.is_controlling(
				_is_airborne(foe, 1 - i), _is_inverted(foe),
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


func _on_weapon_fired(index: int) -> void:
	_last_fire_at[index] = _fight_time
	_fire_hit_counted[index] = false
	_pending_weapon_fires.append(str(_bot_ids[index]))


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
	# 2. Out of the arena, immediate.
	for i in 2:
		var bot: Node = _bots[i]
		if bot == null:
			continue
		if bool(_ooa_flag[i]) or Rules.is_out_of_arena(_chassis_position(bot)):
			_finish("out_of_arena", 1 - i, i)
			return

	# 4. Component kill.
	for i in 2:
		var bot: Node = _bots[i]
		if bot == null or not bot.has_method("condition"):
			continue
		if Rules.is_component_kill(bot.call("condition") as Dictionary):
			_finish("component_kill", 1 - i, i)
			return

	# 1. Knockout: immobile for the full count, movement resets it, a shoving match
	#    freezes it (a pinned bot is being held, not knocked out).
	for i in 2:
		var bot: Node = _bots[i]
		if bot == null:
			continue
		var immobile := bot.has_method("is_immobile") and bool(bot.call("is_immobile"))
		var foe: Node = _bots[1 - i]
		var separation := 999.0
		if foe != null:
			separation = _chassis_position(bot).distance_to(_chassis_position(foe))
		var pinned := Rules.is_pinned(separation, (_last_heading[i] as Vector2).length(),
			_is_inverted(bot))
		_ko_count[i] = Rules.ko_count_next(float(_ko_count[i]), immobile, delta, pinned)
		var step := int(floor(float(_ko_count[i])))
		if step > int(_ko_haptic_step[i]):
			_ko_haptic_step[i] = step
			if _fx != null and _fx.has_method("on_ko_tick"):
				_fx.call("on_ko_tick", int(ceil(_ko_count_s - float(_ko_count[i]))))
		elif step == 0:
			_ko_haptic_step[i] = 0
		if Rules.is_knockout(float(_ko_count[i]), _ko_count_s):
			_finish("ko", 1 - i, i)
			return

	# 3. Judges, on the bell.
	if _time_left <= 0.0:
		_finish("judges", -1, -1)


func _finish(outcome_type: String, winner_index: int, loser_index: int) -> void:
	if _result_sent:
		return
	_result_sent = true

	var judges: Dictionary = {}
	for i in 2:
		judges[_bot_ids[i]] = Rules.judge_scores(_tallies[i])

	if outcome_type == "judges":
		winner_index = Rules.judges_winner_index(_tallies[0], _tallies[1])
		loser_index = 1 - winner_index

	var damage: Dictionary = {}
	var scrap: Dictionary = {}
	var config_bots: Array = _config.get("bots", []) as Array
	for i in 2:
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
	})

	_hud_banner = Rules.banner_for(outcome_type)
	_hud_winner = str(_bot_names[winner_index]) if winner_index >= 0 else ""

	for i in 2:
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
	Bridge.send(FightTypes.MSG_FIGHT_RESULT, result)


# ---------------------------------------------------------------- presentation (never gameplay)

func _update_presentation(_delta: float) -> void:
	for info_variant in _pending_fx:
		var info: Dictionary = info_variant as Dictionary
		if _fx != null and _fx.has_method("on_damage_event"):
			_fx.call("on_damage_event", info)
	_pending_fx.clear()
	for fired_id in _pending_weapon_fires:
		if _fx != null and _fx.has_method("on_weapon_fired"):
			_fx.call("on_weapon_fired", str(fired_id))
	_pending_weapon_fires.clear()

	if _controls != null and _controls.has_method("set_enabled"):
		_controls.call("set_enabled", state == State.FIGHTING)
	if _controls != null and _controls.has_method("set_state") and _bots[0] != null:
		var player: Node = _bots[0]
		var gas: Variant = player.get("gas_charges")
		_controls.call("set_state", _is_inverted(player), int(gas) if gas != null else 0)

	if _hud == null:
		return
	match state:
		State.COUNTDOWN:
			var remaining := FightTypes.COUNTDOWN_S - _countdown_time
			_hud_call("show_countdown", ["FIGHT" if remaining <= 0.0 else str(int(ceil(remaining)))])
		State.FIGHTING:
			_hud_call("hide_countdown", [])
			_hud_call("set_time_left", [_time_left])
			_hud_call("set_scrap", [int(_scrap[0])])
			var ko_index := 0 if float(_ko_count[0]) >= float(_ko_count[1]) else 1
			var ko_seconds := float(_ko_count[ko_index])
			if ko_seconds > 0.0:
				_hud_call("show_ko_count", [int(ceil(_ko_count_s - ko_seconds)), str(_bot_names[ko_index])])
			else:
				_hud_call("hide_ko_count", [])
			_hud_call("set_height_readout", [height_readout()])
		State.RESULT:
			if not _result_shown:
				_result_shown = true
				_hud_call("hide_countdown", [])
				_hud_call("hide_ko_count", [])
				_hud_call("show_result", [_hud_banner, _hud_winner])
		_:
			pass


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


func _spike_centre() -> Vector3:
	if _arena != null and _arena.has_method("spike_patch_centre"):
		return _arena.call("spike_patch_centre") as Vector3
	return Vector3.ZERO


func _index_of(bot_id: String) -> int:
	if bot_id == "" or bot_id == "arena":
		return -1
	for i in 2:
		if _bot_ids[i] == bot_id:
			return i
	return -1


func _bot_index_for_body(body: Node) -> int:
	var node: Node = body
	while node != null:
		for i in 2:
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
