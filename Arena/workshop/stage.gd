class_name WorkshopStage extends Node3D
## The AAA menu and workshop stage: the player's own bot, centre stage, on a dark
## floor under three moving stage lights with visible haze and dry ice.
##
## Spec: docs/stage4-spec.md section 5, docs/stage2-art-direction.md "Owner decision
## 2026-09-13: menus are AAA cinematic". This is the live backdrop behind every
## SwiftUI menu screen as well as the builder turntable, so it has to be cheap: four
## lights, one shadow caster, three particle emitters, and no volumetrics (the mobile
## renderer has no FogVolume, so the beams are additive cone meshes).
##
## Presentation only. Nothing here is read by the fight simulation and the bot on the
## stage is frozen static so physics can never roll it off the disc.
##
## Everything below the root is built in code, so `WorkshopStage.new()` works as well
## as instancing `stage.tscn` and the headless test needs no display server.

## Emitted after every show_bot(), carrying bot_summary().
signal ready_for_host(summary: Dictionary)

const BOT_SCENE := "res://bot/bot.tscn"
const DEFAULT_CONFIG := "res://fight/fixtures/stage3_config.json"
const ARG_WORKSHOP := "--roboteer-workshop"

## Bridge contract (docs/stage4-spec.md section 5).
const MSG_WORKSHOP_CONFIG := "workshop_config"
const MSG_WORKSHOP_READY := "workshop_ready"

## Geometry, metres.
const STAGE_RADIUS := 1.5          # a 3 m disc
const STAGE_HEIGHT := 0.12         # the raised lip the bot stands on
const FLOOR_SIZE := 16.0
const BACKDROP_DISTANCE := 7.0
const BACKDROP_HEIGHT := 6.0

## Idle turntable rotation, degrees per second (spec section 5).
const AUTO_ROTATE_DEG_PER_S := 8.0

## Colours, calibrated against Art/direction/menu-stage.png: the key art is mostly
## BLACK. The floor, the disc and the backdrop are all near zero and every visible
## value on screen is put there by a light, not by an albedo or by ambient.
const COL_FLOOR := Color(0.028, 0.030, 0.035)
const COL_STAGE := Color(0.042, 0.044, 0.050)    # dark charcoal, as in the key art
const COL_RING := Color(0.11, 0.115, 0.13)
const COL_EDGE := Color(0.95, 0.80, 0.45)        # the thin light edge, warm white
const COL_BACKDROP := Color(0.006, 0.009, 0.016) # effectively black
const COL_AMBER := Color(1.0, 0.66, 0.28)
const COL_BLUE := Color(0.38, 0.66, 1.0)
const COL_KEY := Color(0.86, 0.92, 1.0)          # cold white key on the bot
const COL_RIM := Color(1.0, 0.74, 0.45)          # warm rim from behind

## Light budget: 3 movers + a key and a rim on the bot. Only the key casts a shadow.
const MOVER_ENERGY := 2.6
## HALF angle. The key art's shafts are narrow; 16 degrees filled the whole frame.
const MOVER_ANGLE_DEG := 8.0
## Peak alpha of a beam cone at the lens, falling to zero at the floor. Additive, so
## two crossing beams must still read as translucent.
const BEAM_ALPHA := 0.06
const BEAM_FADE_POWER := 2.2
const KEY_ENERGY := 3.6
const KEY_AT := Vector3(-0.45, 1.95, 2.60)       # front left of the workshop camera
const KEY_ANGLE_DEG := 22.0
const RIM_ENERGY := 2.4
const RIM_AT := Vector3(0.70, 1.70, -2.50)       # behind the bot, warm
const RIM_ANGLE_DEG := 24.0

## One entry per mover: colour, mount position, and the sine path it sweeps (yaw and
## pitch amplitude in degrees, period in seconds, phase in turns). Independent periods
## so the three never lock up. Each beam cone is cut to the distance from its mount to
## the stage, so no shaft ever passes through the floor and out the far side.
const MOVERS := [
	{"colour": COL_AMBER, "at": Vector3(-2.4, 3.5, 2.0),
		"yaw_amp": 10.0, "pitch_amp": 4.0, "period": 17.0, "phase": 0.0, "energy": 1.0},
	{"colour": COL_BLUE, "at": Vector3(1.9, 3.6, 1.1),
		"yaw_amp": 8.0, "pitch_amp": 5.0, "period": 23.0, "phase": 0.37, "energy": 0.9},
	{"colour": COL_BLUE, "at": Vector3(0.3, 3.8, -2.6),
		"yaw_amp": 13.0, "pitch_amp": 6.0, "period": 29.0, "phase": 0.61, "energy": 0.75},
]

## Dry ice. In the key art the bank is a low billow at the disc rim and below it, in
## the bottom quarter of the frame, and it never touches the bot. So: a ring just
## outside the 1.5 m rim, nothing over the stage centre, small quads (the workshop
## camera sits 2.4 m away, where a 1 m billboard covers the whole screen height), and
## everything under 0.2 m. Measured against the menu camera (4.8 m, pitch 18, aimed at
## 0.28 m): fog at radius 1.5 to 1.9 lands 87 to 100 % down the frame, and anything
## behind the bot is depth tested against it rather than veiling it.
const DRY_ICE = [
	{"at": Vector3(0.90, 0.035, 1.56), "extents": Vector3(1.05, 0.02, 0.55),
		"amount": 14, "scale": 0.45, "alpha": 0.05},
	{"at": Vector3(-1.75, 0.035, 0.60), "extents": Vector3(0.5, 0.02, 1.05),
		"amount": 11, "scale": 0.42, "alpha": 0.045},
	{"at": Vector3(0.60, 0.035, -1.75), "extents": Vector3(1.05, 0.02, 0.5),
		"amount": 11, "scale": 0.42, "alpha": 0.04},
]
## Beam dust: only inside the cones, where they cross above the stage. Nothing else
## floats in the air (the key art has none).
const DUST_AT := Vector3(0.0, 1.05, 0.0)
const DUST_EXTENTS := Vector3(0.55, 0.55, 0.55)

var _turntable: Node3D = null
var _bot: Node3D = null
var _summary: Dictionary = {}
var _world_env: WorldEnvironment = null
var _environment: Environment = null
var _movers: Array[Node3D] = []
var _emitters: Array[GPUParticles3D] = []
var _bridge: Node = null
var _active := true
var _auto_rotate := true
var _t := 0.0
var _built := false


func _ready() -> void:
	_build()
	_connect_bridge()
	_read_qa_arguments()
	set_process(true)


# ---------------------------------------------------------------- public API

## Free whatever is on the turntable, assemble `config` (a FightConfig bot entry),
## stand it on the stage centre and freeze it. Emits ready_for_host afterwards.
func show_bot(config: Dictionary) -> void:
	_build()
	_clear_bot()
	if config.is_empty():
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	var scene: PackedScene = load(BOT_SCENE)
	if scene == null:
		push_error("WorkshopStage: cannot load " + BOT_SCENE)
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	var bot := scene.instantiate() as Node3D
	if bot == null:
		push_error("WorkshopStage: " + BOT_SCENE + " root is not a Node3D")
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	bot.name = "ShowBot"
	_turntable.add_child(bot)
	_bot = bot
	if bot.has_method("setup"):
		bot.call("setup", config, 0, RandomNumberGenerator.new())
	if bot.has_method("place_at"):
		bot.call("place_at", _turntable.global_position, Vector3.RIGHT)
	# Bot.freeze() kills the motors as well, which stops a flipper twitching on the
	# stand. The explicit sweep afterwards is the guarantee the spec asks for: every
	# rigid body under the bot is static, whatever the assembly built.
	if bot.has_method("freeze"):
		bot.call("freeze")
	_freeze_bodies(bot)

	_summary = bot_summary()
	emit_signal("ready_for_host", _summary)


## Visibility and processing. Off also stops the particles and releases the
## environment, so the fight's own WorldEnvironment is never fought over.
func set_active(on: bool) -> void:
	_build()
	_active = on
	visible = on
	set_process(on)
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.emitting = on
	if _world_env != null:
		_world_env.environment = _environment if on else null


func is_active() -> bool:
	return _active


## The build numbers for the host, from the Bot itself. Empty until P2's
## build_summary() lands, which is exactly what the Swift side must tolerate.
func bot_summary() -> Dictionary:
	if _bot != null and is_instance_valid(_bot) and _bot.has_method("build_summary"):
		var out: Variant = _bot.call("build_summary")
		if out is Dictionary:
			return out as Dictionary
	return {}


func set_auto_rotate(on: bool) -> void:
	_auto_rotate = on


func auto_rotate() -> bool:
	return _auto_rotate


## Where the camera should look. The stage top, not the floor.
func stage_centre() -> Vector3:
	return global_position + Vector3(0.0, STAGE_HEIGHT, 0.0)


func turntable() -> Node3D:
	_build()
	return _turntable


func turntable_angle_deg() -> float:
	_build()
	return rad_to_deg(_turntable.rotation.y)


func bot() -> Node3D:
	return _bot if (_bot != null and is_instance_valid(_bot)) else null


func last_summary() -> Dictionary:
	return _summary


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _auto_rotate and _turntable != null:
		_turntable.rotation.y = wrapf(
			_turntable.rotation.y + deg_to_rad(AUTO_ROTATE_DEG_PER_S) * delta, -TAU, TAU)
	_sweep_movers()


## Each mover aims at the stage centre plus a slow independent sine wander, which is
## what sells "moving heads" without any animation data.
func _sweep_movers() -> void:
	for i in _movers.size():
		var node := _movers[i]
		if not is_instance_valid(node):
			continue
		var spec: Dictionary = MOVERS[i]
		var period: float = maxf(float(spec["period"]), 0.001)
		var phase: float = TAU * (_t / period + float(spec["phase"]))
		var yaw_off: float = sin(phase) * float(spec["yaw_amp"])
		var pitch_off: float = sin(phase * 0.63 + 1.1) * float(spec["pitch_amp"])
		var aim := stage_centre() + Vector3(0.0, 0.22, 0.0)
		node.look_at_from_position(global_position + (spec["at"] as Vector3), aim, Vector3.UP)
		node.rotate_object_local(Vector3.UP, deg_to_rad(yaw_off))
		node.rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch_off))


# ---------------------------------------------------------------- bridge and QA

## The autoload is reached by node rather than by its `Bridge` global identifier. A
## `--script` test run compiles this file as a dependency of the test script, which is
## before the autoload globals are registered, and the global would not resolve.
func _connect_bridge() -> void:
	if not is_inside_tree():
		return
	_bridge = get_tree().root.get_node_or_null("Bridge")
	if _bridge != null and not _bridge.is_connected("message_received", _on_bridge_message):
		_bridge.connect("message_received", _on_bridge_message)


func _on_bridge_message(type: String, payload: Dictionary) -> void:
	if type != MSG_WORKSHOP_CONFIG:
		return
	var bot_config: Dictionary = payload.get("bot", {}) as Dictionary
	show_bot(bot_config)
	if _bridge != null and is_instance_valid(_bridge):
		_bridge.call("send", MSG_WORKSHOP_READY, _summary)


## `--roboteer-workshop` or `--roboteer-workshop=/abs/path.json`. Desktop only, so a
## device build can never be posed by an argument. The file may be a whole FightConfig
## (bots[0] is used) or a bare bot config.
func _read_qa_arguments() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg != ARG_WORKSHOP and not arg.begins_with(ARG_WORKSHOP + "="):
			continue
		var path := DEFAULT_CONFIG
		if arg.length() > ARG_WORKSHOP.length() + 1:
			path = arg.substr(ARG_WORKSHOP.length() + 1)
		var config := load_bot_config(path)
		if config.is_empty():
			push_warning("WorkshopStage: no bot config in " + path)
			return
		show_bot(config)
		return


## Reads a bot config from a res:// or absolute path. Accepts a FightConfig (first bot)
## or a bare bot entry. Returns {} when there is nothing usable.
static func load_bot_config(path: String) -> Dictionary:
	var text := ""
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			return {}
		var res := FileAccess.open(path, FileAccess.READ)
		if res == null:
			return {}
		text = res.get_as_text()
	else:
		if not FileAccess.file_exists(path):
			return {}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		text = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var dict: Dictionary = parsed as Dictionary
	if dict.has("chassis"):
		return dict
	var bots: Array = dict.get("bots", []) as Array
	if bots.size() > 0 and bots[0] is Dictionary:
		return bots[0] as Dictionary
	return {}


# ---------------------------------------------------------------- construction

func _clear_bot() -> void:
	if _bot != null and is_instance_valid(_bot):
		_turntable.remove_child(_bot)
		_bot.queue_free()
	_bot = null
	_summary = {}


## Every RigidBody3D under the bot goes static. A frozen static body still follows its
## parent transform, which is what lets the turntable carry the whole assembly round.
func _freeze_bodies(node: Node) -> void:
	var body := node as RigidBody3D
	if body != null:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	for child in node.get_children():
		_freeze_bodies(child)


func _build() -> void:
	if _built:
		return
	_built = true
	_build_environment()
	_build_floor()
	_build_stage()
	_build_backdrop()
	_build_lights()
	_build_haze()


func _build_environment() -> void:
	_world_env = get_node_or_null("Environment") as WorldEnvironment
	if _world_env == null:
		_world_env = WorldEnvironment.new()
		_world_env.name = "Environment"
		add_child(_world_env)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	# Black, not "dark blue": in the key art the background and the top third of the
	# frame are zero, and everything visible is put there by a light.
	_environment.background_color = Color(0.0, 0.0, 0.0)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.30, 0.40, 0.60)
	# 0.05, not 0.35. Ambient is what made the first build a milky grey wash: it lifts
	# every surface in the frame at once, which is the opposite of stage lighting.
	_environment.ambient_light_energy = 0.05
	# Glow is the one post effect the mobile renderer keeps. Only the edge strip and
	# the lamp heads are above the threshold, so it never blooms the haze.
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.35
	_environment.glow_bloom = 0.05
	_environment.glow_hdr_threshold = 1.1
	_world_env.environment = _environment


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_FLOOR
	# Low roughness plus a little metal is what gives the wet stage sheen under the
	# beams without any screen space reflection, which mobile does not have.
	mat.roughness = 0.22
	mat.metallic = 0.55
	mat.metallic_specular = 0.6
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = plane
	floor_node.material_override = mat
	floor_node.position = Vector3.ZERO
	add_child(floor_node)


func _build_stage() -> void:
	var root := Node3D.new()
	root.name = "Stage"
	add_child(root)

	var disc := CylinderMesh.new()
	disc.top_radius = STAGE_RADIUS
	disc.bottom_radius = STAGE_RADIUS * 1.02
	disc.height = STAGE_HEIGHT
	disc.radial_segments = 48
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = COL_STAGE
	# Matte, as in the key art: the disc is a dark charcoal plate, not a mirror. The
	# sheen belongs to the floor around it.
	disc_mat.roughness = 0.6
	disc_mat.metallic = 0.15
	var disc_node := MeshInstance3D.new()
	disc_node.name = "Disc"
	disc_node.mesh = disc
	disc_node.material_override = disc_mat
	disc_node.position = Vector3(0.0, STAGE_HEIGHT * 0.5, 0.0)
	root.add_child(disc_node)

	# The turntable ring: a raised rim the bot sits inside, as in bot-in-workshop.png.
	var ring := TorusMesh.new()
	ring.inner_radius = STAGE_RADIUS * 0.90
	ring.outer_radius = STAGE_RADIUS * 0.97
	ring.rings = 32
	ring.ring_segments = 12
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = COL_RING
	ring_mat.roughness = 0.4
	ring_mat.metallic = 0.7
	var ring_node := MeshInstance3D.new()
	ring_node.name = "Ring"
	ring_node.mesh = ring
	ring_node.material_override = ring_mat
	ring_node.position = Vector3(0.0, STAGE_HEIGHT, 0.0)
	root.add_child(ring_node)

	# The thin light edge. Unshaded and above 1.0 so the glow catches it.
	var edge := TorusMesh.new()
	edge.inner_radius = STAGE_RADIUS * 1.005
	edge.outer_radius = STAGE_RADIUS * 1.03
	edge.rings = 48
	edge.ring_segments = 8
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.albedo_color = COL_EDGE
	edge_mat.emission_enabled = true
	edge_mat.emission = COL_EDGE
	edge_mat.emission_energy_multiplier = 2.2
	var edge_node := MeshInstance3D.new()
	edge_node.name = "EdgeLight"
	edge_node.mesh = edge
	edge_node.material_override = edge_mat
	edge_node.position = Vector3(0.0, STAGE_HEIGHT * 0.55, 0.0)
	root.add_child(edge_node)

	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.position = Vector3(0.0, STAGE_HEIGHT, 0.0)
	root.add_child(_turntable)


func _build_backdrop() -> void:
	var wall := PlaneMesh.new()
	wall.size = Vector2(FLOOR_SIZE * 1.4, BACKDROP_HEIGHT)
	wall.orientation = PlaneMesh.FACE_Z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_BACKDROP
	mat.roughness = 1.0
	mat.metallic = 0.0
	var node := MeshInstance3D.new()
	node.name = "Backdrop"
	node.mesh = wall
	node.material_override = mat
	node.position = Vector3(0.0, BACKDROP_HEIGHT * 0.5 - 0.4, -BACKDROP_DISTANCE)
	add_child(node)


func _build_lights() -> void:
	var movers := Node3D.new()
	movers.name = "Movers"
	add_child(movers)
	_movers.clear()
	var aim := Vector3(0.0, STAGE_HEIGHT + 0.22, 0.0)
	for i in MOVERS.size():
		var spec: Dictionary = MOVERS[i]
		var colour: Color = spec["colour"]
		var at: Vector3 = spec["at"]
		# The shaft stops at the stage. A fixed 9 m cone shot through the floor and
		# out the far side of the frame, which is what read as a solid wedge.
		var length: float = at.distance_to(aim)
		var mount := Node3D.new()
		mount.name = "Mover%d" % i
		movers.add_child(mount)

		var spot := SpotLight3D.new()
		spot.name = "Spot"
		spot.light_color = colour
		spot.light_energy = MOVER_ENERGY * float(spec["energy"])
		spot.spot_range = length + 1.2
		spot.spot_angle = MOVER_ANGLE_DEG
		spot.spot_angle_attenuation = 0.9
		spot.spot_attenuation = 1.2
		# No shadows on the movers: three moving shadow casters is the whole phone
		# budget and the key light already grounds the bot.
		spot.shadow_enabled = false
		mount.add_child(spot)

		var cone := MeshInstance3D.new()
		cone.name = "Beam"
		cone.mesh = _beam_mesh(length, MOVER_ANGLE_DEG)
		cone.material_override = _beam_material(colour, BEAM_ALPHA * float(spec["energy"]), length)
		cone.rotate_x(deg_to_rad(-90.0))
		cone.position = Vector3(0.0, 0.0, -length * 0.5)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(cone)

		# The lamp head itself, as in the key art: a small bright disc at the top of
		# the frame that tells the eye where each shaft comes from.
		var head := MeshInstance3D.new()
		head.name = "Head"
		var head_mesh := CylinderMesh.new()
		head_mesh.top_radius = 0.085
		head_mesh.bottom_radius = 0.105
		head_mesh.height = 0.09
		head_mesh.radial_segments = 12
		head.mesh = head_mesh
		var head_mat := StandardMaterial3D.new()
		head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		head_mat.albedo_color = colour
		head_mat.emission_enabled = true
		head_mat.emission = colour
		head_mat.emission_energy_multiplier = 2.4
		head.material_override = head_mat
		head.rotate_x(deg_to_rad(-90.0))
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(head)

		_movers.append(mount)

	# The key: a cold white spot from the front left of the workshop camera. This is
	# what makes the bot's plates read instead of sitting in the haze as a silhouette,
	# and it is the one shadow caster on the stage.
	var key := SpotLight3D.new()
	key.name = "KeyLight"
	key.light_color = COL_KEY
	key.light_energy = KEY_ENERGY
	key.spot_range = 7.0
	key.spot_angle = KEY_ANGLE_DEG
	key.spot_angle_attenuation = 1.0
	key.spot_attenuation = 1.0
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	add_child(key)
	key.look_at_from_position(KEY_AT, Vector3(0.0, STAGE_HEIGHT + 0.18, 0.0), Vector3.UP)

	# The warm rim from behind, which separates the bot from the black backdrop.
	var rim := SpotLight3D.new()
	rim.name = "RimLight"
	rim.light_color = COL_RIM
	rim.light_energy = RIM_ENERGY
	rim.spot_range = 7.0
	rim.spot_angle = RIM_ANGLE_DEG
	rim.spot_angle_attenuation = 1.1
	rim.shadow_enabled = false
	add_child(rim)
	rim.look_at_from_position(RIM_AT, Vector3(0.0, STAGE_HEIGHT + 0.14, 0.0), Vector3.UP)


## A hollow cone along +Y, narrow at the lens and wide at the far end, sized to the
## spot's own angle so the mesh and the light agree.
func _beam_mesh(length: float, angle_deg: float) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.height = length
	mesh.bottom_radius = 0.035                                  # at the lens
	mesh.top_radius = maxf(tan(deg_to_rad(angle_deg)) * length, 0.1)
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh


## The fake haze. The mobile renderer has no volumetric fog and no FogVolume, so a
## beam is an additive unshaded cone that fades along its length and brightens at the
## silhouette, which is what a real shaft does to the eye.
func _beam_material(tint: Color, strength: float, length: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.1;
uniform float half_length = 4.0;
uniform float fade_power = 2.2;

varying float along;

void vertex() {
	// 0 at the lens, 1 at the far end, whatever the mesh UV convention is.
	along = clamp((VERTEX.y + half_length) / max(half_length * 2.0, 0.0001), 0.0, 1.0);
}

void fragment() {
	float fade = pow(1.0 - along, fade_power);
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb;
	ALPHA = strength * fade * (0.35 + 0.65 * edge);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("half_length", length * 0.5)
	mat.set_shader_parameter("fade_power", BEAM_FADE_POWER)
	return mat


func _build_haze() -> void:
	_emitters.clear()
	for i in DRY_ICE.size():
		var spec: Dictionary = DRY_ICE[i]
		var node := _dry_ice_emitter("DryIce%d" % i, spec)
		add_child(node)
		_emitters.append(node)
	var dust := _dust_emitter()
	add_child(dust)
	_emitters.append(dust)


## Dry ice: a low billow at the disc rim and below it, drifting outward and away. The
## quads are SMALL on purpose: the workshop camera sits 2.4 m from the stage, where a
## 1 m billboard already covers the whole screen height, so metre scale blobs are what
## turned the first build into a milky wash. Cheap: 36 quads that never write depth.
func _dry_ice_emitter(node_name: String, spec: Dictionary) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = spec["extents"]
	process.direction = Vector3(0.0, 0.03, 0.0)
	process.spread = 88.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.15
	# No lift at all: dry ice sinks and spreads, it does not rise into the bot.
	process.gravity = Vector3(0.0, -0.004, 0.0)
	process.damping_min = 0.05
	process.damping_max = 0.14
	process.scale_min = float(spec["scale"]) * 0.7
	process.scale_max = float(spec["scale"]) * 1.3
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.color = Color(0.80, 0.86, 1.0, float(spec["alpha"]))
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = node_name
	node.amount = int(spec["amount"])
	node.lifetime = 9.0
	node.randomness = 0.7
	node.preprocess = 5.0
	node.process_material = process
	node.draw_pass_1 = quad
	node.material_override = _soft_quad_material(Color(0.82, 0.88, 1.0))
	node.position = spec["at"]
	# Wide enough that the blobs are not culled as they drift off the stage edge.
	node.visibility_aabb = AABB(Vector3(-4.0, -0.4, -4.0), Vector3(8.0, 1.0, 8.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The faint dust INSIDE the beams, where they cross above the stage: what makes the
## cones read as light in air rather than as glass. The key art has a few specks in the
## shafts and nothing else in the air, so this box is small and nothing floats outside
## it. Tiny, bright, and slow.
func _dust_emitter() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = DUST_EXTENTS
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 30.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.06
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.scale_min = 0.008
	process.scale_max = 0.018
	process.color = Color(1.0, 0.94, 0.86, 0.35)
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = "Dust"
	node.amount = 22
	node.lifetime = 9.0
	node.randomness = 0.9
	node.preprocess = 5.0
	node.process_material = process
	node.draw_pass_1 = quad
	node.material_override = _soft_quad_material(Color(1.0, 0.94, 0.85))
	node.position = DUST_AT
	node.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Alpha in and out over the particle's life, so nothing ever pops.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.25, Color(1, 1, 1, 1))
	gradient.add_point(0.65, Color(1, 1, 1, 0.85))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## One additive billboard material with a radial falloff texture, so a quad reads as a
## soft blob rather than a square. No shader: a 64 px gradient is cheaper than a branch.
func _soft_quad_material(tint: Color) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = tint
	mat.albedo_texture = texture
	# The particle colour and the colour ramp arrive as vertex colour.
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	return mat
