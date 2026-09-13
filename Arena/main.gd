extends Node3D
## Stage 1 spike arena: a grey cube on a grey floor, lit, framed isometrically,
## plus the FightConfig -> FightResult round trip described in docs/bridge-spec.md.

const SCHEMA := 1
const HOP_HEIGHT := 0.6
const HOP_TIME := 0.35
const CUBE_GREYS: Array[Color] = [
	Color(0.75, 0.75, 0.76),
	Color(0.62, 0.62, 0.64),
	Color(0.88, 0.88, 0.89),
]
## Frames to wait for a host before assuming there is not one. The embedded host
## adds its bridge node within a frame or two of start; a desktop or headless run
## never will, and must still run the scene and log the warning.
const HOST_WAIT_FRAMES_HEADLESS := 2
const HOST_WAIT_FRAMES_WINDOWED := 180

@onready var _cube: MeshInstance3D = $Cube
@onready var _label: Label = $Hud/Label

var _cube_material: StandardMaterial3D
var _grey_index: int = 0
var _cube_rest_y: float = 0.5
var _hop_tween: Tween = null
var _ready_sent: bool = false
var _frames: int = 0
var _ticks_msec_at_config: int = 0


func _ready() -> void:
	_cube_material = _cube.material_override as StandardMaterial3D
	_cube_rest_y = _cube.position.y
	Bridge.message_received.connect(_on_message_received)
	get_viewport().size_changed.connect(_update_label)
	_update_label()
	# Handle both orders: the host may attach before or after this scene loads.
	if Bridge.is_attached():
		_send_arena_ready()


func _process(_dt: float) -> void:
	if _ready_sent:
		set_process(false)
		return
	_frames += 1
	var limit := HOST_WAIT_FRAMES_WINDOWED
	if DisplayServer.get_name() == "headless":
		limit = HOST_WAIT_FRAMES_HEADLESS
	if _frames >= limit and not Bridge.is_attached():
		# No host in this process (desktop editor or headless run). Send anyway so
		# the scene exercises the same path; Bridge will warn and drop it.
		_send_arena_ready()


func _unhandled_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		tapped = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tapped = true
	if tapped:
		_hop_cube()
		get_viewport().set_input_as_handled()


func _hop_cube() -> void:
	_grey_index = (_grey_index + 1) % CUBE_GREYS.size()
	if _cube_material != null:
		_cube_material.albedo_color = CUBE_GREYS[_grey_index]
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	_cube.position.y = _cube_rest_y
	_hop_tween = create_tween()
	_hop_tween.set_trans(Tween.TRANS_SINE)
	_hop_tween.tween_property(_cube, "position:y", _cube_rest_y + HOP_HEIGHT, HOP_TIME * 0.5) \
		.set_ease(Tween.EASE_OUT)
	_hop_tween.tween_property(_cube, "position:y", _cube_rest_y, HOP_TIME * 0.5) \
		.set_ease(Tween.EASE_IN)


func _update_label() -> void:
	var size := get_viewport().get_visible_rect().size
	var version: String = Engine.get_version_info()["string"]
	_label.text = "Roboteer arena, Godot %s\n%d x %d" % [version, int(size.x), int(size.y)]


func _on_message_received(type: String, payload: Dictionary) -> void:
	match type:
		"bridge_attached":
			# A host-less run may already have sent (and dropped) arena_ready; the
			# host must always get one, so resend when the bridge attaches late.
			_ready_sent = false
			_send_arena_ready()
		"fight_config":
			_on_fight_config(payload)
		_:
			Bridge.send("arena_log", {
				"level": "warn",
				"text": "unknown message type: " + type,
			})


func _send_arena_ready() -> void:
	if _ready_sent:
		return
	_ready_sent = true
	set_process(false)
	Bridge.send("arena_ready", {
		"schema": SCHEMA,
		"godot_version": Engine.get_version_info()["string"],
		"ticks_msec": Time.get_ticks_msec(),
	})


func _on_fight_config(config: Dictionary) -> void:
	_ticks_msec_at_config = Time.get_ticks_msec()
	var schema := int(config.get("schema", 0))
	if schema != SCHEMA:
		Bridge.send("arena_log", {
			"level": "error",
			"text": "unsupported FightConfig schema: " + str(schema),
		})
		return
	Bridge.send("arena_log", {"level": "info", "text": "config received"})
	Bridge.send("fight_result", _build_fight_result(config))


## Stage 1 placeholder result: no simulation runs, but the shape is the real v1
## FightResult and diagnostics.echo proves the config arrived intact.
func _build_fight_result(config: Dictionary) -> Dictionary:
	var bots: Array = config.get("bots", []) as Array
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	var duration_s: float = float(rules.get("duration_s", 0.0))

	var first: Dictionary = bots[0] if bots.size() > 0 else {}
	var second: Dictionary = bots[1] if bots.size() > 1 else {}
	var winner := str(first.get("id", ""))
	var loser := str(second.get("id", ""))

	var judges := {}
	var damage := {}
	var scrap := {}
	for bot_variant in bots:
		var bot: Dictionary = bot_variant as Dictionary
		var id := str(bot.get("id", ""))
		judges[id] = {"damage": 0, "aggression": 0, "control": 0}
		damage[id] = bot.get("damage", {})
		scrap[id] = 0

	return {
		"schema": SCHEMA,
		"outcome": {
			"type": "judges",
			"winner": winner,
			"loser": loser,
			"at_s": duration_s,
		},
		"duration_s": duration_s,
		"judges": judges,
		"damage": damage,
		"scrap": scrap,
		"replay": {
			"seed": _as_number(config.get("seed", 0)),
			"tick_hz": 60,
			"inputs": [],
		},
		"diagnostics": {
			"ticks_msec_at_config": _ticks_msec_at_config,
			"ticks_msec_at_result": Time.get_ticks_msec(),
			"physics_ticks": Engine.get_physics_frames(),
			"echo": {
				"arena": str(config.get("arena", "")),
				"bot_count": bots.size(),
				"seed": _as_number(config.get("seed", 0)),
			},
		},
	}


## JSON parsing can hand back a float for a whole number. Keep whole numbers
## whole so the seed survives the round trip as an integer on the Swift side.
func _as_number(value: Variant) -> Variant:
	if value is float and value == floor(value) and absf(value) < 9.0e15:
		return int(value)
	return value
