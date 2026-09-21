class_name DriveBase extends RefCounted
## One drive module per catalogue id (docs/stage4-spec.md section 3). It owns the
## wheel bodies, their hinges and the arcade steering that turns an input heading
## into per side wheel speeds.
##
## The steering maths is Stage 3's, unchanged (docs/stage3-physics-notes.md section
## 3): heading direction sets the desired yaw and magnitude sets throttle, forward
## effort fades as the yaw error grows so the bot pivots first and drives second,
## past REVERSE_ANGLE it backs toward the stick instead of spinning, and `secondary`
## stops the inside track dead. What Stage 4 adds is that every number in it now
## comes from the catalogue: `top_speed`, `turn_rate`, `push_force` and `traction`
## per drive, and `turn_rate_factor` per chassis.
##
## Wheel keys are derived from the slot POSITIONS, not from the order the catalogue
## or the .glb happens to list them in, so `condition["wheels"]` always reads
## front left, front right, middle, rear whatever the source.

## Stage 3 constants that are not in the catalogue because they are model
## parameters rather than design choices.
## Wheels must scrub sideways to pivot, so the achieved yaw rate is well under the
## commanded one and the command is scaled up to land on the catalogue turn rate.
## RE-MEASURED for Stage 4: Stage 3 used 2.4 with the wheels 0.35 m off the centre
## line, and the catalogue (and the models) put the wedge's at 0.30 m, which is
## 14 percent less leverage. 2.8 puts a wedge back on its Stage 3 0.7 s for a 90
## degree turn.
const TURN_SCRUB_GAIN := 2.8
const REVERSE_ANGLE := deg_to_rad(135.0)
const WHEEL_FRICTION := 1.2
const WHEEL_MOTOR_IMPULSE := 120.0
## The catalogue push_force that WHEEL_MOTOR_IMPULSE was measured against (4WD).
const REFERENCE_PUSH := 1.5
## Jolt's hinge sign is opposite to the joint's +Z (measured, Stage 3).
const JOLT_HINGE_FLIP := Basis(Vector3.RIGHT, PI)

var bot: Node = null
var hull: ChassisBase = null
var spec: Dictionary = {}
var id := ""
var radius := FightTypes.WHEEL_RADIUS

var wheels: Array[BotPart] = []
var joints: Array[HingeJoint3D] = []
var wheel_local: Array[Vector3] = []
var wheel_key: Array[String] = []
var condition_keys: Array[String] = []

var _dt := 1.0 / float(FightTypes.TICK_HZ)


func setup(owner: Node, chassis_module: ChassisBase, drive_spec: Dictionary,
		drive_id: String) -> void:
	bot = owner
	hull = chassis_module
	spec = drive_spec
	id = drive_id
	radius = maxf(FightTypes.WHEEL_RADIUS, hull.wheel_radius_min())


# ---------------------------------------------------------------------------
# Catalogue readings
# ---------------------------------------------------------------------------
func top_speed() -> float:
	return float(spec.get("top_speed", FightTypes.TOP_SPEED_4WD))


func turn_rate() -> float:
	return float(spec.get("turn_rate", FightTypes.TURN_RATE_4WD)) * hull.turn_rate_factor()


func traction() -> float:
	return float(spec.get("traction", 1.0))


func push_force() -> float:
	return float(spec.get("push_force", REFERENCE_PUSH))


## How many wheel bodies. Tracks put three road wheels a side, which is also the
## six wheel body budget, so the brief's cap holds for every drive.
func wheel_count() -> int:
	return int(spec.get("wheels", 4))


## The slot id the chassis should be asked for.
func slot_drive_id() -> String:
	return id


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func build() -> void:
	var slots := hull.wheel_slots(slot_drive_id())
	var rows := _row_names(slots)
	var order := []
	for i in range(slots.size()):
		var pos: Vector3 = slots[i]
		order.append({"pos": pos, "key": _key_for(pos, rows)})
	order.sort_custom(_by_layout)
	for entry_variant in order:
		var entry: Dictionary = entry_variant
		_add_wheel(entry["pos"] as Vector3, str(entry["key"]))
	_collect_condition_keys()
	_build_skins()


## Front before middle before rear, left before right: the Stage 3 order.
func _by_layout(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	if absf(pa.x - pb.x) > 0.001:
		return pa.x > pb.x
	return pa.z < pb.z


## Distinct X positions, front to rear, so three rows read f / m / r and two f / r.
func _row_names(slots: Array) -> Dictionary:
	var xs: Array[float] = []
	for slot_variant in slots:
		var p: Vector3 = slot_variant
		var found := false
		for x in xs:
			if absf(x - p.x) < 0.001:
				found = true
				break
		if not found:
			xs.append(p.x)
	xs.sort()
	xs.reverse()
	var names := {}
	for i in range(xs.size()):
		var label := "r"
		if xs.size() >= 2:
			if i == 0:
				label = "f"
			elif i == xs.size() - 1:
				label = "r"
			else:
				label = "m"
		names[xs[i]] = label
	return names


func _key_for(pos: Vector3, rows: Dictionary) -> String:
	var row := "r"
	for x in rows.keys():
		if absf(float(x) - pos.x) < 0.001:
			row = str(rows[x])
			break
	return "wheel_%s%s" % [row, "l" if pos.z < 0.0 else "r"]


func _add_wheel(at: Vector3, key: String) -> void:
	var wheel := BotPart.new()
	wheel.name = "Wheel" + key.substr(6).to_upper() + str(wheels.size())
	wheel.part_key = key
	wheel.part_kind = "wheel"
	wheel.material_name = "rubber"
	wheel.physics_material_override = _friction_material()

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = FightTypes.WHEEL_WIDTH
	shape.shape = cylinder
	shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # cylinder axis Y to Z
	wheel.add_child(shape)
	_add_wheel_visual(wheel)

	wheel.position = at
	bot.register_part(wheel, key, "wheel", wheel_mass())
	wheels.append(wheel)
	wheel_local.append(at)
	wheel_key.append(key)
	_add_joint(wheel, at)


func wheel_mass() -> float:
	var count := maxi(wheel_count(), 1)
	return maxf(float(spec.get("weight", 16.0)) / float(count), 0.5)


func model_id() -> String:
	return "wheel_standard"


func _add_wheel_visual(wheel: BotPart) -> void:
	var model := PartVisuals.instantiate(model_id())
	if model != null:
		var scale := radius / FightTypes.WHEEL_RADIUS
		model.scale = Vector3(scale, scale, 1.0)
		wheel.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = FightTypes.WHEEL_WIDTH
	mesh.radial_segments = 16
	mesh.rings = 1
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mesh_instance.material_override = PartVisuals.slot_material("rubber", bot.livery)
	wheel.add_child(mesh_instance)


func _add_joint(wheel: BotPart, at: Vector3) -> void:
	var joint := HingeJoint3D.new()
	joint.name = "Joint" + wheel.name
	joint.position = at
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(wheel)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
		WHEEL_MOTOR_IMPULSE * push_force() / REFERENCE_PUSH)
	joint.exclude_nodes_from_collision = true
	joints.append(joint)


func _friction_material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = WHEEL_FRICTION * traction()
	material.bounce = 0.05
	return material


func _collect_condition_keys() -> void:
	condition_keys.clear()
	for key in wheel_key:
		if not condition_keys.has(key):
			condition_keys.append(key)


## Tracks hang a skin over their road wheels. Nothing else has one.
func _build_skins() -> void:
	pass


# ---------------------------------------------------------------------------
# Driving
# ---------------------------------------------------------------------------
## `turn` is the optional pure pivot (-1..1): with a short heading it spins the bot
## on the spot and drives it nowhere. Positive is nose to the bot's LEFT, the same
## direction a positive heading error turns it. Each drive pivots at its own
## catalogue `turn_rate`, so tracks are slow at it and omni is instant.
const PIVOT_HEADING_MAX := 0.25
const PIVOT_DEAD_ZONE := 0.02


## Returns the drive scale actually used, for the readouts.
func drive(heading: Vector2, secondary: bool, dt: float, turn: float = 0.0) -> void:
	_dt = dt
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	var scale := power_scale()
	if scale <= 0.0:
		set_targets(0.0, 0.0)
		return
	var throttle := clampf(heading.length(), 0.0, 1.0)
	if absf(turn) > PIVOT_DEAD_ZONE and throttle <= PIVOT_HEADING_MAX:
		pivot(turn, scale)
		return
	if throttle < 0.05:
		set_targets(0.0, 0.0)
		return

	var want := Vector3(heading.x, 0.0, heading.y).normalized()
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT

	var yaw_now := atan2(-fwd.z, fwd.x)
	var yaw_want := atan2(-want.z, want.x)
	var err := wrapf(yaw_want - yaw_now, -PI, PI)
	var reverse := absf(err) > REVERSE_ANGLE
	if reverse:
		err = wrapf(err - PI, -PI, PI)

	var rate := turn_rate() * scale
	var turn_cmd := clampf(err / maxf(_dt * rate * 6.0, 0.001), -1.0, 1.0)
	var align := clampf(1.0 - absf(err) / (PI * 0.5), 0.0, 1.0)
	var v_fwd: float = throttle * top_speed() * float(bot.speed_factor()) * align \
		* (-1.0 if reverse else 1.0)
	var v_turn := turn_cmd * rate * track_half() * TURN_SCRUB_GAIN

	var v_left: float = v_fwd - v_turn
	var v_right: float = v_fwd + v_turn
	if secondary and not bot.is_inverted():
		if v_turn > 0.0:
			v_left = 0.0
		elif v_turn < 0.0:
			v_right = 0.0
	set_targets(v_left, v_right)


## Spin on the spot: the two sides run equal and opposite, no forward term.
func pivot(turn: float, scale: float) -> void:
	var v := clampf(turn, -1.0, 1.0) * turn_rate() * scale * track_half() * TURN_SCRUB_GAIN
	set_targets(-v, v)


## Half the track width, which is what converts a yaw rate into a wheel speed
## difference. Measured from the slots rather than assumed.
func track_half() -> float:
	var total := 0.0
	for p in wheel_local:
		total += absf(p.z)
	return maxf(total / maxf(float(wheel_local.size()), 1.0), 0.05)


## Metres per second per side, converted to wheel angular velocity.
func set_targets(v_left: float, v_right: float) -> void:
	var left := v_left
	var right := v_right
	# Inverted, a wheel touches the floor on its far side, so the same motor sign
	# drives the bot backwards. Only an invertible chassis ever gets here usefully.
	if bot.is_inverted():
		var swap := -left
		left = -right
		right = swap
	for i in range(wheels.size()):
		if wheels[i].detached or not is_instance_valid(joints[i]):
			continue
		var target := left if wheel_local[i].z < 0.0 else right
		if not side_alive(wheel_key[i]):
			target = 0.0
			joints[i].set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		joints[i].set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, target / radius)


func stop() -> void:
	set_targets(0.0, 0.0)


func freeze() -> void:
	for joint in joints:
		if is_instance_valid(joint):
			joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


## Alive wheels as a fraction, times the drive condition. Stage 3's rule.
func power_scale() -> float:
	var alive := alive_count()
	if alive == 0:
		return 0.0
	var condition: Dictionary = bot.damage.condition
	return alive_fraction() * clampf(float(condition["drive"]), 0.15, 1.0)


func alive_count() -> int:
	var n := 0
	for i in range(wheels.size()):
		if not wheels[i].detached and side_alive(wheel_key[i]):
			n += 1
	return n


func alive_fraction() -> float:
	return float(alive_count()) / float(maxi(wheels.size(), 1))


## A track side that has lost its belt free wheels. Wheeled drives always true.
func side_alive(_key: String) -> bool:
	return true


## Called by the Bot when a condition key hits zero.
func on_key_zero(_key: String) -> void:
	pass


## True when this drive strafes (omni). The AI and the HUD read it.
func strafes() -> bool:
	return bool(spec.get("strafe", false))


# ---------------------------------------------------------------------------
# Wave P hooks (docs/wave-p-d2-notes.md). Every one reads a catalogue key with the
# old behaviour as its default, so the five Stage 4 drives are unchanged to the
# last decimal and the three new ones are tuned from `Shared/parts.json` rather
# than from code.
# ---------------------------------------------------------------------------
## Multiplies arena hazard damage: the spikes, the grinder, the flame jet, the
## press. A hover rides over a floor hazard (0.0) and a walker steps over most of
## one (0.3). Everything on wheels takes the hazard in full.
func hazard_factor() -> float:
	return float(spec.get("hazard_factor", 1.0))


## Multiplies the hull's flip and tip resistance. A hover has nothing holding it
## down, so it goes over easily; a walker is planted.
func flip_factor() -> float:
	return float(spec.get("flip_factor", 1.0))


## Fraction of a hull hit that bleeds into the drive's condition. A drive with
## wheel bodies takes its punishment through them (BotDamage.DRIVE_BLEED); a drive
## with no wheels has to take it here or it would be invulnerable.
func hull_bleed() -> float:
	return float(spec.get("hull_bleed", 0.0))


## True when a condition key reaching zero takes its visual off the machine with
## it. The adaptive tracks' belts are segmented and stay on.
func sheds_visual(_key: String) -> bool:
	return true


## True when this drive builds no wheel bodies at all and carries its own weight
## on the hull instead (the walker and the hover).
func bodiless() -> bool:
	return false


func wheel_contacts() -> Array[bool]:
	var out: Array[bool] = []
	var floor_y := radius + 0.03
	for wheel in wheels:
		out.append(not wheel.detached and wheel.global_position.y <= floor_y)
	return out
