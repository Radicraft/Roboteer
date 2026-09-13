class_name Bot extends Node3D
## A fighting robot: a chassis rigid body with wheels, a flipper arm and four
## armour faces hung off it by joints. Damage is joint failure (brief §6), so
## every part is a real body and "destroyed" means the joint goes away.
##
## API contract: docs/stage3-spec.md §4. R calls `setup`, then `apply_input`
## once per physics tick BEFORE the step, and reads `condition()` and the
## signals. C reads `weapon_height_band()` / `front_edge_height()` for the HUD.
##
## AXES (the one convention everyone needs). The bot's local frame is
##   +X forward (the wedge lip), +Y up, +Z the bot's right-hand side.
## `heading` is a world XZ vector: Vector2(x, z), length 0..1. Desired world
## direction is Vector3(heading.x, 0, heading.y); the bot turns toward it.
##
## API DEVIATION from the spec text, on instruction: `opponent_relative` is a
## plain Dictionary VAR that R writes each tick, not a method. Read it as
## `bot.opponent_relative["distance"]`. `opponent_relative_dict()` returns the
## same thing for callers that prefer a call.

signal damage_event(info: Dictionary)
signal part_detached(part: String)
signal inverted_changed(is_inverted: bool)
signal weapon_fired()

# ---------------------------------------------------------------------------
# Layout constants. Chassis local space, origin on the wheel-axle plane, which
# rides RIDE_HEIGHT above the floor when the bot is level.
# ---------------------------------------------------------------------------
const RIDE_HEIGHT := 0.11                   # = WHEEL_RADIUS: local y 0 is the axle plane
const WHEEL_X_FRONT := 0.24
const WHEEL_X_REAR := -0.30
const WHEEL_Z := 0.35
const WHEEL_Y := 0.0
const TRACK_HALF := WHEEL_Z

## Flipper. Long and wide, resting along the wedge slope so that once the lip is
## under an opponent the arm is already beneath it. Low friction so it skates
## rather than grabs when it does touch down.
## atan2(LIP_TOP - BODY_TOP, HALF_LEN - SLOPE_START_X) = atan2(-0.145, 0.35)
const SLOPE_ANGLE := -0.39289
## The arm rests ALONG the slope. Lengthening it to 0.44 already drops its tip's
## lower corner to 0.025 m off the floor: under an opponent's 0.033 m underside,
## above the wedge lip's 0.015 m, and clear of the ground so it never scrapes.
## (Hanging it lower than this was measured and is a trap: the arm becomes a
## third ground contact, lifts the front wheels and the bot pogos.)
const FLIPPER_REST_ANGLE := SLOPE_ANGLE
const FLIPPER_PIVOT := Vector3(0.1115, 0.0977, 0.0)
const FLIPPER_LEN := 0.44
const FLIPPER_THICK := 0.03
const FLIPPER_WIDTH := 0.52                 # nearly the full body width: a bigger catch
const FLIPPER_FRICTION := 0.08
const FLIPPER_LIMIT_UPPER := deg_to_rad(80.0)
const FLIPPER_FIRE_S := 0.12
const FLIPPER_RETURN_S := 0.45
## The sweep is now presentation plus a scoop; the throw itself is the impulse
## pair below, so this stays modest and no longer torques the wielder over.
const FLIPPER_FIRE_VEL := 12.0
const FLIPPER_RETURN_VEL := -8.0
## MEASURED: Godot 4.6.3 + Jolt ignores PARAM_MOTOR_MAX_IMPULSE on a hinge (the
## sweep is identical at 110 and at 2600). Kept for the day it is honoured.
const FLIPPER_FIRE_IMPULSE := 1200.0
const FLIPPER_HOLD_IMPULSE := 60.0

## A real flipper is a pneumatic ram: the gas throws whatever is sitting on the
## arm and pushes the wielder DOWN into the floor. Modelling it as an impulse
## pair instead of pure hinge-motor velocity is the whole reason the wielder no
## longer launches itself (docs/stage3-physics-notes.md).
const FLIPPER_LAUNCH_IMPULSE := 115.0       # N s straight up into the target
const FLIPPER_LAUNCH_FORWARD := 12.0        # N s along the wielder's forward
const FLIPPER_LAUNCH_SPIN := 8.0           # N m s, tumbles the target away
## The reaction is spread across the fire window as a force, not dumped as one
## impulse: a single 210 N s hit into the floor would read as damage on the
## wielder's own wheels.
const FLIPPER_REACTION_SCALE := 1.0
## Sensor box over the arm: what "on the wedge" means.
const WEDGE_SENSOR_HEIGHT := 0.30
const WEDGE_SENSOR_BACK := 0.12

const ARMOUR_FRONT_SIZE := Vector3(0.16, 0.022, 0.56)
const ARMOUR_FRONT_SLOPE_S := 0.30          # metres along the slope from the deck
const ARMOUR_SIDE_SIZE := Vector3(0.30, 0.10, 0.03)
const ARMOUR_SIDE_POS := Vector3(-0.03, 0.0, 0.298)
const ARMOUR_REAR_SIZE := Vector3(0.03, 0.12, 0.52)
const ARMOUR_REAR_POS := Vector3(-0.465, 0.0, 0.0)
const ARMOUR_TOP_SIZE := Vector3(0.46, 0.035, 0.50)
const ARMOUR_TOP_POS := Vector3(-0.18, 0.0875, 0.0)

const SRIMECH_IMPULSE := 150.0
const SRIMECH_TORQUE := 60.0

## Drive model. HINGE = motorised HingeJoint3D wheels (spec's first choice).
## FORCE = the documented fallback: free-rolling wheels on the same hinges plus
## drive and grip forces applied to the chassis at the wheel positions.
enum { DRIVE_HINGE, DRIVE_FORCE }
const DRIVE_MODEL := DRIVE_HINGE
const WHEEL_MOTOR_IMPULSE := 120.0
const FORCE_DRIVE_GAIN := 260.0
const FORCE_DRIVE_MAX := 200.0
const FORCE_GRIP_GAIN := 220.0

const WHEEL_FRICTION := 1.2
const CHASSIS_FRICTION := 0.35
const PANEL_FRICTION := 0.5

## Arcade drive: past this yaw error the bot reverses toward the stick instead
## of spinning on the spot, so the player and the AI can back off a wall.
const TURN_SCRUB_GAIN := 2.4
const REVERSE_ANGLE := deg_to_rad(135.0)

## See _configure_wheel_joints: Jolt's hinge sign is opposite to the joint's +Z.
const JOLT_HINGE_FLIP := Basis(Vector3.RIGHT, PI)

# ---------------------------------------------------------------------------
# Public state (spec §4)
# ---------------------------------------------------------------------------
var bot_id: String = ""
var team: int = 0
var chassis: RigidBody3D = null
var gas_charges: int = FightTypes.FLIPPER_CHARGES
var livery: Color = FightTypes.LIVERY_PLAYER
## Filled by R every physics tick: {"position": Vector3, "distance": float}
var opponent_relative: Dictionary = {"position": Vector3.ZERO, "distance": 0.0}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
var damage: BotDamage = null
var _rng: RandomNumberGenerator = null
var _config: Dictionary = {}
var _materials: Dictionary = {}             # face -> material name

var _wheels: Array[BotPart] = []            # index matches FightTypes.PART_WEAPONS order
var _wheel_keys: Array[String] = []
var _wheel_joints: Array[HingeJoint3D] = []
var _wheel_local: Array[Vector3] = []
var _flipper: BotPart = null
var _flipper_joint: HingeJoint3D = null
var _wedge_sensor: Area3D = null
var _reaction_force := 0.0
var _panels: Dictionary = {}                # "armour_front" -> Array[BotPart]
var _panel_joints: Dictionary = {}          # body -> Generic6DOFJoint3D
var _parts: Array[BotPart] = []
var _joints_root: Node3D = null
var _core_mesh: MeshInstance3D = null
var _srimech_mesh: MeshInstance3D = null

var _frozen := false
var _weapon_jammed := false
var _flip_phase := 0                        # 0 idle, 1 firing, 2 returning
var _flip_timer := 0.0
var _flip_cooldown := 0.0
var _srimech_cooldown := 0.0
var _was_inverted := false
var _speed_window: PackedFloat32Array = PackedFloat32Array()
var _speed_head := 0
var _speed_filled := false
var _last_input: Dictionary = FightTypes.empty_input()
var _dt := 1.0 / float(FightTypes.TICK_HZ)
## Largest contact impulse this bot has seen, for tuning only. Never gameplay.
var debug_max_impulse := 0.0
var debug_contacts := false


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func setup(bot_config: Dictionary, team_index: int, rng: RandomNumberGenerator) -> void:
	_config = bot_config
	_rng = rng
	team = team_index
	bot_id = str(bot_config.get("id", "bot-%d" % team_index))
	livery = FightTypes.LIVERY_PLAYER if team_index == 0 else FightTypes.LIVERY_OPPONENT
	gas_charges = FightTypes.FLIPPER_CHARGES

	var armour_cfg: Dictionary = bot_config.get("armour", {}) as Dictionary
	for face in BotDamage.ARMOUR_FACES:
		var entry: Dictionary = armour_cfg.get(face, {}) as Dictionary
		_materials[face] = str(entry.get("material", "steel"))

	var wheel_count := _wheel_count_for(str(bot_config.get("drive", "4wd")))
	damage = BotDamage.new()
	damage.setup(bot_config.get("damage", {}) as Dictionary, wheel_count)

	var window := int(round(FightTypes.IMMOBILE_WINDOW_S * FightTypes.TICK_HZ))
	_speed_window = PackedFloat32Array()
	_speed_window.resize(maxi(window, 1))
	_speed_window.fill(99.0)

	_joints_root = Node3D.new()
	_joints_root.name = "Joints"

	_build_chassis()
	_build_wheels(wheel_count)
	_build_flipper()
	_build_armour()
	add_child(_joints_root)

	_configure_wheel_joints()
	_configure_flipper_joint()
	_configure_panel_joints()
	_exclude_internal_collisions()

	# Parts detached before the fight (a carried-over damaged bot) never appear.
	_apply_initial_damage()
	set_physics_process(true)


func _wheel_count_for(drive: String) -> int:
	match drive:
		"2wd":
			return 2
		"6wd":
			return 6
		_:
			return 4


func _build_chassis() -> void:
	chassis = BotPart.new()
	chassis.name = "Chassis"
	chassis.owner_bot = self
	chassis.part_key = "chassis"
	chassis.part_kind = "chassis"
	chassis.material_name = str(_materials.get("top", "steel"))
	chassis.mass = FightTypes.BOT_MASS_CHASSIS
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = Vector3(-0.08, -0.05, 0.0)   # low and slightly rearward
	chassis.continuous_cd = true
	chassis.physics_material_override = _make_material(CHASSIS_FRICTION)
	_prepare_body(chassis)

	var shape := CollisionShape3D.new()
	shape.shape = BotMeshes.wedge_shape()
	chassis.add_child(shape)

	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = BotMeshes.wedge_mesh()
	hull.material_override = _flat_material(livery)
	chassis.add_child(hull)

	# The control core: dark, emissive, only visible once the top plate is gone.
	_core_mesh = MeshInstance3D.new()
	_core_mesh.name = "Core"
	_core_mesh.mesh = BotMeshes.flat_box_mesh(Vector3(0.16, 0.07, 0.20))
	_core_mesh.position = Vector3(-0.18, 0.04, 0.0)
	var core_mat := _flat_material(Color(0.12, 0.13, 0.15))
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.10, 0.45, 0.30)
	core_mat.emission_energy_multiplier = 0.8
	_core_mesh.material_override = core_mat
	chassis.add_child(_core_mesh)

	add_child(chassis)
	_parts.append(chassis)


func _build_wheels(count: int) -> void:
	var layout: Array[Vector3] = []
	var keys: Array[String] = []
	if count == 2:
		layout = [Vector3(WHEEL_X_REAR, WHEEL_Y, -WHEEL_Z), Vector3(WHEEL_X_REAR, WHEEL_Y, WHEEL_Z)]
		keys = ["wheel_rl", "wheel_rr"]
	else:
		layout = [
			Vector3(WHEEL_X_FRONT, WHEEL_Y, -WHEEL_Z), Vector3(WHEEL_X_FRONT, WHEEL_Y, WHEEL_Z),
			Vector3(WHEEL_X_REAR, WHEEL_Y, -WHEEL_Z), Vector3(WHEEL_X_REAR, WHEEL_Y, WHEEL_Z),
		]
		keys = ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
		if count == 6:
			layout.insert(2, Vector3(-0.03, WHEEL_Y, -WHEEL_Z))
			layout.insert(3, Vector3(-0.03, WHEEL_Y, WHEEL_Z))
			keys.insert(2, "wheel_ml")
			keys.insert(3, "wheel_mr")

	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = FightTypes.WHEEL_RADIUS
	wheel_mesh.bottom_radius = FightTypes.WHEEL_RADIUS
	wheel_mesh.height = FightTypes.WHEEL_WIDTH
	wheel_mesh.radial_segments = 16
	wheel_mesh.rings = 1
	var tyre := _flat_material(Color(0.11, 0.11, 0.12))

	for i in range(layout.size()):
		var wheel := BotPart.new()
		wheel.name = "Wheel" + keys[i].substr(6).to_upper()
		wheel.owner_bot = self
		wheel.part_key = keys[i]
		wheel.part_kind = "wheel"
		wheel.mass = FightTypes.BOT_MASS_WHEEL
		wheel.physics_material_override = _make_material(WHEEL_FRICTION)
		_prepare_body(wheel)
		wheel.position = layout[i]

		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = FightTypes.WHEEL_RADIUS
		cyl.height = FightTypes.WHEEL_WIDTH
		shape.shape = cyl
		shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # cylinder axis Y -> Z
		wheel.add_child(shape)

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = wheel_mesh
		mi.material_override = tyre
		mi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		wheel.add_child(mi)

		add_child(wheel)
		_wheels.append(wheel)
		_wheel_keys.append(keys[i])
		_wheel_local.append(layout[i])
		_parts.append(wheel)


func _build_flipper() -> void:
	_flipper = BotPart.new()
	_flipper.name = "Flipper"
	_flipper.owner_bot = self
	_flipper.part_key = FightTypes.PART_WEAPON
	_flipper.part_kind = "weapon"
	_flipper.mass = FightTypes.BOT_MASS_FLIPPER
	_flipper.physics_material_override = _make_material(FLIPPER_FRICTION)
	_prepare_body(_flipper)

	var size := Vector3(FLIPPER_LEN, FLIPPER_THICK, FLIPPER_WIDTH)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_flipper.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(size)
	mi.material_override = _flat_material(Color(0.30, 0.33, 0.38))
	_flipper.add_child(mi)

	# What counts as "on the wedge": a box standing on the arm's top face, a
	# little longer than the arm at the back so a bot riding up the slope counts.
	_wedge_sensor = Area3D.new()
	_wedge_sensor.name = "WedgeSensor"
	_wedge_sensor.collision_layer = 0
	_wedge_sensor.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	_wedge_sensor.monitorable = false
	var sensor_shape := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(FLIPPER_LEN + WEDGE_SENSOR_BACK, WEDGE_SENSOR_HEIGHT,
		FLIPPER_WIDTH + 0.04)
	sensor_shape.shape = sensor_box
	sensor_shape.position = Vector3(-WEDGE_SENSOR_BACK * 0.5,
		(WEDGE_SENSOR_HEIGHT + FLIPPER_THICK) * 0.5, 0.0)
	_wedge_sensor.add_child(sensor_shape)
	_flipper.add_child(_wedge_sensor)

	var basis := Basis(Vector3.BACK, FLIPPER_REST_ANGLE)
	var dir := basis.x
	var up := basis.y
	_flipper.transform = Transform3D(basis,
		FLIPPER_PIVOT + dir * (FLIPPER_LEN * 0.5) + up * (FLIPPER_THICK * 0.5))
	add_child(_flipper)
	_parts.append(_flipper)


func _build_armour() -> void:
	var slope := Basis(Vector3.BACK, SLOPE_ANGLE)
	var start := BotMeshes.slope_start()
	var front_pos := Vector3(start.x, start.y, 0.0) \
		+ slope.x * ARMOUR_FRONT_SLOPE_S + slope.y * (ARMOUR_FRONT_SIZE.y * 0.5)
	_add_panel("armour_front", "front", ARMOUR_FRONT_SIZE,
		Transform3D(slope, front_pos), 1.0)
	_add_panel("armour_sides", "sides", ARMOUR_SIDE_SIZE,
		Transform3D(Basis.IDENTITY, ARMOUR_SIDE_POS), 0.5)
	_add_panel("armour_sides", "sides", ARMOUR_SIDE_SIZE,
		Transform3D(Basis.IDENTITY,
			Vector3(ARMOUR_SIDE_POS.x, ARMOUR_SIDE_POS.y, -ARMOUR_SIDE_POS.z)), 0.5)
	_add_panel("armour_rear", "rear", ARMOUR_REAR_SIZE,
		Transform3D(Basis.IDENTITY, ARMOUR_REAR_POS), 1.0)
	_add_panel("armour_top", "top", ARMOUR_TOP_SIZE,
		Transform3D(Basis.IDENTITY, ARMOUR_TOP_POS), 1.0)

	# Srimech: a visual arm riding on the top plate. It goes with the plate.
	var tops: Array = _panels.get("armour_top", [])
	if not tops.is_empty():
		var plate: BotPart = tops[0]
		_srimech_mesh = MeshInstance3D.new()
		_srimech_mesh.name = "Srimech"
		_srimech_mesh.mesh = BotMeshes.flat_box_mesh(Vector3(0.26, 0.025, 0.07))
		_srimech_mesh.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(-14.0)),
			Vector3(-0.09, 0.028, 0.0))
		_srimech_mesh.material_override = _flat_material(Color(0.52, 0.54, 0.58))
		plate.add_child(_srimech_mesh)


func _add_panel(key: String, face: String, size: Vector3, at: Transform3D,
		mass_scale: float) -> void:
	var material_name := str(_materials.get(face, "steel"))
	var panel := BotPart.new()
	var node_name := "Panel" + key.substr(7).capitalize()
	if key == "armour_sides":
		node_name += "R" if at.origin.z > 0.0 else "L"
	panel.name = node_name
	panel.owner_bot = self
	panel.part_key = key
	panel.part_kind = "armour"
	panel.material_name = material_name
	panel.mass = maxf(float(FightTypes.MATERIAL_MASS_KG.get(material_name, 2.0)) * mass_scale, 0.2)
	panel.physics_material_override = _make_material(PANEL_FRICTION)
	_prepare_body(panel)
	panel.transform = at

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	panel.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(size)
	mi.material_override = _panel_material(material_name)
	panel.add_child(mi)

	add_child(panel)
	if not _panels.has(key):
		_panels[key] = []
	(_panels[key] as Array).append(panel)
	_parts.append(panel)


func _prepare_body(body: BotPart) -> void:
	body.collision_layer = FightTypes.LAYER_BOT
	body.collision_mask = FightTypes.MASK_BOT
	body.contact_monitor = true
	body.max_contacts_reported = 6
	body.can_sleep = false


func _make_material(friction: float) -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.05
	return pm


func _flat_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.75
	mat.metallic = 0.0
	return mat


## Panel colour is the material, so the build reads at a glance (spec §4).
func _panel_material(material_name: String) -> StandardMaterial3D:
	var colour: Color = FightTypes.MATERIAL_COLOUR.get(material_name, Color.WHITE)
	if material_name == "hdpe":
		colour = livery
	var mat := _flat_material(colour)
	if material_name == "polycarbonate":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.6)
		mat.roughness = 0.25
	elif material_name == "titanium":
		mat.metallic = 0.55
		mat.roughness = 0.5
	elif material_name == "steel":
		mat.metallic = 0.35
		mat.roughness = 0.55
	return mat


# ---------------------------------------------------------------------------
# Joints
# ---------------------------------------------------------------------------
func _configure_wheel_joints() -> void:
	for i in range(_wheels.size()):
		var joint := HingeJoint3D.new()
		joint.name = "Joint" + _wheels[i].name
		# Hinge axis is the joint's local Z, already the bot's axle axis. MEASURED
		# on Godot 4.6.3 + Jolt: a positive motor target velocity here rolls the
		# bot FORWARD, so wheel targets are +v / WHEEL_RADIUS with no flip.
		joint.position = _wheel_local[i]
		_joints_root.add_child(joint)
		joint.node_a = joint.get_path_to(chassis)
		joint.node_b = joint.get_path_to(_wheels[i])
		joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, DRIVE_MODEL == DRIVE_HINGE)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, WHEEL_MOTOR_IMPULSE)
		joint.exclude_nodes_from_collision = true
		_wheel_joints.append(joint)


func _configure_flipper_joint() -> void:
	_flipper_joint = HingeJoint3D.new()
	_flipper_joint.name = "JointFlipper"
	_flipper_joint.transform = Transform3D(
		Basis(Vector3.BACK, FLIPPER_REST_ANGLE) * JOLT_HINGE_FLIP, FLIPPER_PIVOT)
	_joints_root.add_child(_flipper_joint)
	_flipper_joint.node_a = _flipper_joint.get_path_to(chassis)
	_flipper_joint.node_b = _flipper_joint.get_path_to(_flipper)
	_flipper_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	_flipper_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -0.02)
	_flipper_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, FLIPPER_LIMIT_UPPER)
	_flipper_joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, FLIPPER_RETURN_VEL)
	_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, FLIPPER_HOLD_IMPULSE)
	_flipper_joint.exclude_nodes_from_collision = true


func _configure_panel_joints() -> void:
	for key in _panels.keys():
		for panel_variant in (_panels[key] as Array):
			var panel: BotPart = panel_variant
			var joint := Generic6DOFJoint3D.new()
			joint.name = "Joint" + panel.name
			joint.transform = panel.transform
			_joints_root.add_child(joint)
			joint.node_a = joint.get_path_to(chassis)
			joint.node_b = joint.get_path_to(panel)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			# Fully locked: every limit zero width.
			for p in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
					Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
					Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
					Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
				joint.set_param_x(p, 0.0)
				joint.set_param_y(p, 0.0)
				joint.set_param_z(p, 0.0)
			joint.exclude_nodes_from_collision = true
			_panel_joints[panel] = joint


## Parts of one bot never collide with each other: the plates, the arm and the
## wheels all overlap the hull by design and internal contacts would otherwise
## register as damage.
func _exclude_internal_collisions() -> void:
	for i in range(_parts.size()):
		for j in range(i + 1, _parts.size()):
			_parts[i].add_collision_exception_with(_parts[j])


func _apply_initial_damage() -> void:
	for i in range(_wheels.size()):
		if damage.value_for(_wheel_keys[i]) <= 0.0:
			_detach_part(_wheels[i], false)
	for key in _panels.keys():
		if damage.value_for(key) <= 0.0:
			for panel_variant in (_panels[key] as Array):
				_detach_part(panel_variant, false)
	if damage.value_for(FightTypes.PART_WEAPON) <= 0.0:
		_weapon_jammed = true


# ---------------------------------------------------------------------------
# Input and drive
# ---------------------------------------------------------------------------
func apply_input(inp: Dictionary) -> void:
	_last_input = inp
	if _frozen:
		return
	var heading: Vector2 = inp.get("heading", Vector2.ZERO)
	var secondary := bool(inp.get("secondary", false))
	_drive(heading, secondary)
	if bool(inp.get("fire", false)):
		_try_fire()
	if secondary:
		_try_secondary()


## Arcade drive. Heading is a world XZ direction; the bot turns toward it at
## TURN_RATE_4WD by running the two sides at different speeds. Each lost wheel
## takes a quarter off both the drive force and the turn rate.
func _drive(heading: Vector2, secondary: bool) -> void:
	var alive := _alive_wheel_count()
	if alive == 0 or chassis == null:
		_set_wheel_targets(0.0, 0.0)
		return
	var scale := float(alive) / float(maxi(_wheels.size(), 1))
	scale *= clampf(float(damage.condition["drive"]), 0.15, 1.0)

	var throttle := clampf(heading.length(), 0.0, 1.0)
	if throttle < 0.05:
		_set_wheel_targets(0.0, 0.0)
		return

	var want := Vector3(heading.x, 0.0, heading.y).normalized()
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.RIGHT
	fwd = fwd.normalized()

	var yaw_now := atan2(-fwd.z, fwd.x)
	var yaw_want := atan2(-want.z, want.x)
	var err := wrapf(yaw_want - yaw_now, -PI, PI)

	var reverse := absf(err) > REVERSE_ANGLE
	if reverse:
		err = wrapf(err - PI, -PI, PI)

	var turn_rate := FightTypes.TURN_RATE_4WD * scale
	var turn_cmd := clampf(err / maxf(_dt * turn_rate * 6.0, 0.001), -1.0, 1.0)
	# Four wheels have to scrub sideways to pivot, so the achieved yaw rate is
	# well under the commanded one. Over-command to land on TURN_RATE_4WD
	# (measured headless; see docs/stage3-physics-notes.md).
	# Forward effort falls away when the bot is pointing the wrong way, so it
	# pivots first and then drives.
	var align := clampf(1.0 - absf(err) / (PI * 0.5), 0.0, 1.0)
	var v_fwd := throttle * FightTypes.TOP_SPEED_4WD * align * (-1.0 if reverse else 1.0)
	var v_turn := turn_cmd * turn_rate * TRACK_HALF * TURN_SCRUB_GAIN

	var v_left := v_fwd - v_turn
	var v_right := v_fwd + v_turn

	# Handbrake pivot: while upright, `secondary` stops the inside track dead.
	if secondary and not is_inverted():
		if v_turn > 0.0:
			v_left = 0.0
		elif v_turn < 0.0:
			v_right = 0.0

	if DRIVE_MODEL == DRIVE_HINGE:
		_set_wheel_targets(v_left / FightTypes.WHEEL_RADIUS, v_right / FightTypes.WHEEL_RADIUS)
	else:
		_apply_drive_forces(v_left, v_right, scale)


func _set_wheel_targets(w_left: float, w_right: float) -> void:
	for i in range(_wheels.size()):
		if _wheels[i].detached:
			continue
		var joint := _wheel_joints[i]
		if not is_instance_valid(joint):
			continue
		# local -Z is the bot's left-hand side
		var target := w_left if _wheel_local[i].z < 0.0 else w_right
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, target)


## Documented fallback drive (spec §4): forces on the chassis at the wheel
## positions, wheels left free-rolling on their hinges purely for detachment and
## the handling penalty.
func _apply_drive_forces(v_left: float, v_right: float, scale: float) -> void:
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := chassis.global_basis.z
	side.y = 0.0
	side = side.normalized()
	for i in range(_wheels.size()):
		if _wheels[i].detached:
			continue
		var local := _wheel_local[i]
		var offset := chassis.global_basis * (local - chassis.center_of_mass)
		var here := chassis.linear_velocity + chassis.angular_velocity.cross(offset)
		var want := v_left if local.z < 0.0 else v_right
		var f := clampf((want - here.dot(fwd)) * FORCE_DRIVE_GAIN * scale,
			-FORCE_DRIVE_MAX, FORCE_DRIVE_MAX)
		var grip := -here.dot(side) * FORCE_GRIP_GAIN * scale
		chassis.apply_force((fwd * f + side * grip) / float(_wheels.size()) * 4.0, offset)


func _alive_wheel_count() -> int:
	var n := 0
	for w in _wheels:
		if not w.detached:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Flipper and srimech
# ---------------------------------------------------------------------------
func _try_fire() -> void:
	if not flipper_ready():
		return
	_flip_phase = 1
	_flip_timer = FLIPPER_FIRE_S
	_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, FLIPPER_FIRE_VEL)
	_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, FLIPPER_FIRE_IMPULSE)
	_flip_cooldown = FightTypes.FLIPPER_COOLDOWN_S
	# DEVIATION from spec §4, deliberate: the gas charge is spent only when the
	# ram actually has something to throw. Without it an AI that fires on
	# proximity burns all eight charges on thin air and the weapon never lands.
	# `opponent_on_wedge()` is exposed so a smarter caller can gate it itself.
	if _launch_from_wedge():
		gas_charges -= 1
	emit_signal("weapon_fired")


## The pneumatic throw. Returns true when something was on the arm.
## Everything on the arm goes up and tumbles away; the wielder takes the equal
## reaction DOWNWARD, spread over the fire window by `_step_weapon`, which is
## what plants it on the floor instead of launching it.
func _launch_from_wedge() -> bool:
	var target := _wedge_target()
	if target == null:
		return false
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT
	var right := chassis.global_basis.z
	target.apply_impulse(Vector3.UP * FLIPPER_LAUNCH_IMPULSE + fwd * FLIPPER_LAUNCH_FORWARD,
		Vector3.ZERO)
	target.apply_torque_impulse(right * FLIPPER_LAUNCH_SPIN)
	_reaction_force = FLIPPER_LAUNCH_IMPULSE * FLIPPER_REACTION_SCALE / FLIPPER_FIRE_S
	return true


## The body a throw would act on: the nearest foreign chassis (or loose debris)
## sitting on the arm. Picked by distance so the choice never depends on the
## order Jolt happens to report overlaps in.
func _wedge_target() -> RigidBody3D:
	if _wedge_sensor == null or _flipper == null or _flipper.detached:
		return null
	var here := _flipper.global_position
	var best: RigidBody3D = null
	var best_distance := INF
	for body in _wedge_sensor.get_overlapping_bodies():
		var candidate: RigidBody3D = null
		if body is BotPart:
			var other: BotPart = body
			if other.owner_bot == self:
				continue
			if not other.detached and other.owner_bot != null:
				candidate = (other.owner_bot as Bot).chassis
			else:
				candidate = other
		elif body is RigidBody3D:
			candidate = body
		if candidate == null:
			continue
		var d := here.distance_squared_to((body as Node3D).global_position)
		if d < best_distance:
			best_distance = d
			best = candidate
	return best


## True when a throw right now would land on something. For the AI.
func opponent_on_wedge() -> bool:
	return _wedge_target() != null


## True when the flipper could fire this tick (not jammed, has gas, at rest).
func flipper_ready() -> bool:
	return not _weapon_jammed and gas_charges > 0 and _flip_phase == 0 \
		and _flip_cooldown <= 0.0 and _flipper != null and not _flipper.detached


func _try_secondary() -> void:
	if _srimech_cooldown > 0.0 or not is_inverted():
		return
	_srimech_cooldown = FightTypes.SRIMECH_COOLDOWN_S
	var right := chassis.global_basis.z
	var lift := Vector3.UP * SRIMECH_IMPULSE
	var sign_roll := 1.0 if right.y > 0.0 else -1.0
	chassis.apply_impulse(lift, right * 0.28 * sign_roll)
	chassis.apply_torque_impulse(chassis.global_basis.x * SRIMECH_TORQUE * sign_roll)


func _step_weapon(delta: float) -> void:
	_flip_cooldown = maxf(_flip_cooldown - delta, 0.0)
	_srimech_cooldown = maxf(_srimech_cooldown - delta, 0.0)
	if _flip_phase == 0:
		return
	# The ram's reaction, held down through the fire window. Forces are cleared
	# every step, so this has to be re-applied each tick.
	if _flip_phase == 1 and _reaction_force > 0.0 and chassis != null:
		chassis.apply_central_force(Vector3.DOWN * _reaction_force)
	_flip_timer -= delta
	if _flip_timer > 0.0:
		return
	if _flip_phase == 1:
		_flip_phase = 2
		_flip_timer = FLIPPER_RETURN_S
		_reaction_force = 0.0
		_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, FLIPPER_RETURN_VEL)
		_flipper_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, FLIPPER_HOLD_IMPULSE)
	else:
		_flip_phase = 0


# ---------------------------------------------------------------------------
# Damage intake (called from BotPart._integrate_forces, inside the step)
# ---------------------------------------------------------------------------
func report_contact(part: BotPart, collider: Object, impulse: float, position: Vector3) -> void:
	if _frozen or damage == null or impulse <= 0.0:
		return
	debug_max_impulse = maxf(debug_max_impulse, impulse)
	if debug_contacts and impulse > 10.0:
		print("  [contact] tick=%d part=%s J=%.1f collider=%s" % [
			Engine.get_physics_frames(), part.part_key, impulse, collider])
	var attacker := "arena"
	var source := "impact"
	if collider is BotPart:
		var other: BotPart = collider
		if other.owner_bot == self:
			return
		if other.owner_bot != null and not other.detached:
			attacker = str((other.owner_bot as Bot).bot_id)
	elif collider is Node and (collider as Node).is_in_group("arena_hazard"):
		source = "hazard"

	# A blow landing on the chassis body actually landed on the armour face it
	# came through: thin plates let a fast, heavy hit reach the hull in one
	# step, and crediting the hull would silently lose the damage. Only once
	# that face's plate is gone does the blow reach the core (spec §6 states the
	# rule for the top plate; this is the same rule on all four faces).
	var key := part.part_key
	var kind := part.part_kind
	var material_name := part.material_name
	var core_exposed := false
	if kind == "chassis":
		var face := face_for_contact(position)
		var armour_key := "armour_" + face
		if damage.value_for(armour_key) > 0.0:
			key = armour_key
			kind = "armour"
			material_name = str(_materials.get(face, "steel"))
		else:
			core_exposed = true
	damage.apply_impulse_damage(key, kind, material_name,
		impulse, source, position, attacker, core_exposed)


## Which armour face a world-space contact point came through.
func face_for_contact(world_position: Vector3) -> String:
	var l := chassis.global_transform.affine_inverse() * world_position
	if l.y > 0.04:
		return "top"
	if l.x > 0.18:
		return "front"
	if l.x < -0.33:
		return "rear"
	return "sides"


## The yard's spike area calls this directly: an Area3D produces no contact
## impulse, so the hazard supplies its own (spec §5).
func hazard_hit(part: BotPart, impulse: float, position: Vector3) -> void:
	if _frozen or damage == null:
		return
	damage.apply_impulse_damage(part.part_key, part.part_kind, part.material_name,
		impulse, "hazard", position, "arena", _top_plate_gone())



func _top_plate_gone() -> bool:
	return damage.value_for("armour_top") <= 0.0


# ---------------------------------------------------------------------------
# Per-tick bookkeeping
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_dt = delta
	if not _frozen:
		_step_weapon(delta)
	_flush_damage()
	_update_speed_window()
	var inv := is_inverted()
	if inv != _was_inverted:
		_was_inverted = inv
		emit_signal("inverted_changed", inv)


func _flush_damage() -> void:
	if damage == null or damage.pending.is_empty():
		return
	var events := damage.pending.duplicate()
	damage.pending.clear()
	for ev_variant in events:
		var ev: Dictionary = ev_variant
		var part_key := str(ev["part"])
		var detached := false
		if bool(ev["zeroed"]):
			detached = _handle_zero(part_key)
		emit_signal("damage_event", {
			"attacker": ev["attacker"],
			"victim": bot_id,
			"part": part_key,
			"severity": ev["severity"],
			"position": ev["position"],
			"impulse": ev["impulse"],
			"detached": detached,
			"tick": ev["tick"],
		})
		if detached:
			emit_signal("part_detached", part_key)


## Returns true when the part physically came off.
func _handle_zero(part_key: String) -> bool:
	if part_key == FightTypes.PART_WEAPON:
		if not _weapon_jammed:
			_weapon_jammed = true
			_flip_phase = 0
			if is_instance_valid(_flipper_joint):
				_flipper_joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return false
	if part_key == FightTypes.PART_CORE:
		return false
	var idx := _wheel_keys.find(part_key)
	if idx >= 0:
		if _wheels[idx].detached:
			return false
		_detach_part(_wheels[idx], true)
		return true
	if _panels.has(part_key):
		var any := false
		for panel_variant in (_panels[part_key] as Array):
			var panel: BotPart = panel_variant
			if not panel.detached:
				_detach_part(panel, true)
				any = true
		return any
	return false


func _detach_part(part: BotPart, tint: bool) -> void:
	if part.detached:
		return
	part.detached = true
	var joint: Node = null
	if _panel_joints.has(part):
		joint = _panel_joints[part]
		_panel_joints.erase(part)
	else:
		var idx := _wheels.find(part)
		if idx >= 0 and idx < _wheel_joints.size() and is_instance_valid(_wheel_joints[idx]):
			joint = _wheel_joints[idx]
	if joint != null and is_instance_valid(joint):
		joint.queue_free()

	for other in _parts:
		if other != part:
			part.remove_collision_exception_with(other)
	part.collision_layer = FightTypes.LAYER_DEBRIS
	part.collision_mask = FightTypes.MASK_DEBRIS
	part.contact_monitor = false
	part.can_sleep = true

	var debris := _debris_root()
	if debris != null and part.is_inside_tree():
		part.reparent(debris, true)
	if tint:
		_tint_debris(part)


func _debris_root() -> Node:
	# Walk up for the nearest "Debris" sibling rather than hard coding
	# "/root/Fight/Debris": agent R rebuilds the fight's 3D world inside a fresh
	# SubViewport for every fight, so Debris is no longer a child of /root/Fight.
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null("Debris")
		if found != null and found != self:
			return found
		node = node.get_parent()
	return get_parent()


func _tint_debris(part: Node) -> void:
	for child in part.get_children():
		if child is MeshInstance3D:
			var mat := _flat_material(FightTypes.DEBRIS_TINT)
			(child as MeshInstance3D).material_override = mat
		_tint_debris(child)


func _update_speed_window() -> void:
	if chassis == null:
		return
	_speed_window[_speed_head] = chassis.linear_velocity.length()
	_speed_head = (_speed_head + 1) % _speed_window.size()
	if _speed_head == 0:
		_speed_filled = true


# ---------------------------------------------------------------------------
# Queries (spec §4)
# ---------------------------------------------------------------------------
func is_inverted() -> bool:
	if chassis == null:
		return false
	return chassis.global_basis.y.dot(Vector3.UP) < 0.0


func is_immobile() -> bool:
	if not _speed_filled:
		return false
	for v in _speed_window:
		if v > FightTypes.IMMOBILE_SPEED:
			return false
	return true


func condition() -> Dictionary:
	return damage.snapshot() if damage != null else {}


func weapon_height_band() -> String:
	var h := weapon_tip_height()
	if h < 0.10:
		return "floor"
	if h < 0.30:
		return "mid"
	return "high"


func weapon_tip_height() -> float:
	if _flipper == null or _flipper.detached:
		return front_edge_height()
	return maxf((_flipper.global_transform * Vector3(FLIPPER_LEN * 0.5, 0.0, 0.0)).y, 0.0)


func front_edge_height() -> float:
	if chassis == null:
		return 0.0
	return maxf((chassis.global_transform * BotMeshes.wedge_lip_point()).y, 0.0)


## Same data as the `opponent_relative` var, for callers that prefer a call.
func opponent_relative_dict() -> Dictionary:
	return opponent_relative


func set_opponent_relative(position: Vector3, distance: float) -> void:
	opponent_relative["position"] = position
	opponent_relative["distance"] = distance


func weapon_jammed() -> bool:
	return _weapon_jammed


## Everything that is still bolted on, for R's judges and for the FX layer.
func attached_parts() -> Array[BotPart]:
	var out: Array[BotPart] = []
	for p in _parts:
		if not p.detached:
			out.append(p)
	return out


func freeze() -> void:
	_frozen = true
	if is_instance_valid(_flipper_joint):
		_flipper_joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
	for joint in _wheel_joints:
		if is_instance_valid(joint):
			joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
	for part in _parts:
		if is_instance_valid(part):
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
			part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			part.freeze = true


## Place the bot at a spawn marker: the whole assembly moves with the root, so
## this must run before the first physics step.
func place_at(origin: Vector3, facing: Vector3) -> void:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.RIGHT
	flat = flat.normalized()
	var yaw := atan2(-flat.z, flat.x)
	var at := Vector3(origin.x, maxf(origin.y, RIDE_HEIGHT), origin.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	for part in _parts:
		if is_instance_valid(part) and part.is_inside_tree():
			part.force_update_transform()
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
	# Everything moved rigidly, so the joint frames are unchanged, but force a
	# reconfigure so a joint can never keep a stale world-space anchor.
	if _joints_root != null:
		for joint_variant in _joints_root.get_children():
			var joint := joint_variant as Joint3D
			if joint == null:
				continue
			var a := joint.node_a
			joint.node_a = NodePath()
			joint.node_a = a
