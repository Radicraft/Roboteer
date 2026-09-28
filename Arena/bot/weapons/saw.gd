extends WeaponBase
## Saw (docs/stage4-spec.md section 4, agent W1).
##
## A 0.155 m disc on a hinge along the bot's +Z at the front socket. It is the one
## weapon in W1's set that is NOT an impulse weapon: `pressed` brings it to speed
## in 0.4 s and it then does continuous contact damage for as long as it is held
## against something, with near-zero knockback. Winning with it means staying
## latched on, which is what spec section 6 asks the saw AI to do.
##
## HOW THE DAMAGE IS DELIVERED. A small Area3D rides on the blade and is read once
## per physics tick. For every foreign part inside it:
##
##     bot.opponent_damage_tick(victim_part, dps * dt * spin, "cut")
##
## and the Bot's own `take_direct_damage` multiplies that by the victim material's
## catalogue `cut` factor (steel 0.4, titanium 0.7, polycarbonate 1.0, HDPE 1.6),
## so HDPE comes off four times faster than steel.
##
## DELIBERATE DEVIATION from the brief for W1, worth knowing: the spec text says to
## pass `dps * dt * cut_factor`, but `Bot.take_direct_damage` ALREADY resolves the
## material factor from the catalogue for a direct-damage source. Passing it as
## well would square it, and a squared table runs from 0.16 to 2.56, a sixteen-fold
## spread that would make a steel plate immune and an HDPE one vanish. The factor
## is applied once, by the Bot, which is also the only place that knows the
## victim's material.
##
## Knockback is a per-tick impulse of `knockback * spin` N s (0.05 at full speed,
## which is 3 N s per second of contact) along the blade's tangential velocity.
## That is far below `BREAK_MIN`, so a saw never scores an impact hit; it is there
## so a sawn part visibly shudders.
##
## THE BLADE IS LIFTED off the socket for the same reason the drum is: a 0.155 m
## blade hung on a wedge's front socket would be cutting the floor, and a part that
## reaches the floor becomes a third ground contact and the bot pogos (the measured
## trap in flipper.gd).

const BLADE_RADIUS := 0.155
const BLADE_THICK := 0.022
const BLADE_FRICTION := 0.15
## Constant working speed once up to it, rad/s. MEASURED and lowered from 30: a
## motor driven hinge cannot be stalled (Jolt ignores PARAM_MOTOR_MAX_IMPULSE, see
## flipper.gd), so a fast blade held against a plate resolves as an enormous contact
## impulse EVERY step, and the blade body, which is a real part on the "weapon"
## BREAK row, chewed its own condition to zero in ten seconds of contact. At 14
## rad/s the blade survives a long grind, which is the whole point of the weapon.
## The saw's damage is `dps`, not tip speed, so nothing else changes.
const MAX_OMEGA := 14.0
const MOTOR_IMPULSE := 400.0
## The catalogue has no spin_up_s for the saw; spec section 4 says 0.4 s.
const SPIN_UP_S := 0.4
const COAST_S := 1.2
## The cutting area is the blade plus a couple of millimetres, so a part resting
## against the teeth is inside it.
const AREA_MARGIN := 0.018
const GROUND_CLEAR := 0.010
## See vertical_spinner.gd: a wedge's front socket is the flipper's pinned pivot,
## 0.36 m behind the nose, so a disc mounted there never leaves the hull.
## Wave C fitment (PHYSICS, flagged in docs/wave-c-fitment-notes.md): the blade stands
## proud of the front armour with only its back SLOT_BITE in a slot cut in the front plate.
## The old rule (the teeth NOSE_PROUD past the nose) left the blade's centre inside the
## hull on every chassis, 0.125 m inside on the Long and Low: the disc, its guard and its
## drive arm came out through the deck (the owner's "the saw pokes through the front"),
## and the teeth reached 0.03 to 0.12 m past the nose against a catalogue reach of 0.30
## from the socket. Now the teeth reach 0.29 m past the armour on every hull.
const SLOT_BITE := 0.020
## Below this the blade is turning too slowly to cut.
const MIN_CUT_SPIN := 0.05

var blade: BotPart = null
var joint: HingeJoint3D = null
var cutter: Area3D = null
var pivot := Vector3.ZERO

var _spin := 0.0
var _pressed := false
var _announced := false
## Seconds of continuous contact, for the readout and for the notes' numbers.
var _cutting_s := 0.0


func _build() -> void:
	pivot = socket_transform().origin
	pivot.y = maxf(pivot.y, -float(bot.ride_height()) + GROUND_CLEAR + BLADE_RADIUS)
	pivot.x = maxf(pivot.x, _nose() + BLADE_RADIUS - SLOT_BITE)

	blade = BotPart.new()
	blade.name = "SawBlade"
	blade.part_key = FightTypes.PART_WEAPON
	blade.part_kind = "weapon"
	blade.material_name = "steel"
	blade.physics_material_override = _material(BLADE_FRICTION)
	blade.continuous_cd = true

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = BLADE_RADIUS
	cylinder.height = BLADE_THICK
	shape.shape = cylinder
	shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # cylinder axis Y to Z
	blade.add_child(shape)

	# What "the saw is touching it" means. Monitorable off: nothing needs to find
	# this area, it only asks.
	cutter = Area3D.new()
	cutter.name = "Cutter"
	cutter.collision_layer = 0
	cutter.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	cutter.monitorable = false
	var cut_shape := CollisionShape3D.new()
	var cut_cylinder := CylinderShape3D.new()
	cut_cylinder.radius = BLADE_RADIUS + AREA_MARGIN
	cut_cylinder.height = BLADE_THICK + AREA_MARGIN * 2.0
	cut_shape.shape = cut_cylinder
	cut_shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	cutter.add_child(cut_shape)
	blade.add_child(cutter)

	_add_visual()

	blade.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.register_part(blade, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointSaw"
	joint.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(blade)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


## The saw model's `socket_pivot` is at [0.145, 0.055, 0] in its own frame, so the
## model has to slide back by that much for its arbor to land on the blade body's
## centre, which is where the hinge is.
func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "saw")))
	if model != null:
		var offset := Vector3(0.145, 0.055, 0.0)
		var sockets := PartVisuals.read_sockets(model)
		if sockets.has("socket_pivot"):
			offset = sockets["socket_pivot"]
		model.position = -offset
		blade.add_child(model)
		PartVisuals.bind(model, bot.livery)
		# Wave C fitment: the guard, belt covers and motor are the model's `mount` node,
		# bolted to the hull; only the disc turns with the blade body. Presentation only
		# (no body, no shape, no mass), exactly as the flipper's gas system.
		var mount := model.get_node_or_null("mount") as Node3D
		if mount != null and bot.chassis != null:
			model.remove_child(mount)
			mount.owner = null
			mount.name = "SawMount"
			mount.transform = Transform3D(Basis.IDENTITY, pivot - offset)
			bot.chassis.add_child(mount)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = BLADE_RADIUS
	mesh.bottom_radius = BLADE_RADIUS
	mesh.height = BLADE_THICK
	mesh.radial_segments = 20
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	blade.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.0
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	var alive := blade != null and is_instance_valid(blade) and not blade.detached
	var winding := _pressed and not jammed and alive \
		and not bool(bot.is_disrupted("weapon"))
	if winding:
		_spin = minf(_spin + dt / maxf(spin_up_s(), 0.01), 1.0)
	else:
		_spin = maxf(_spin - dt / COAST_S, 0.0)
	_drive_motor()
	_cut(dt)
	if _spin >= 1.0 and not _announced:
		_announced = true
		bot.emit_weapon_fired()
	elif _spin < 0.5:
		_announced = false


func spin_up_s() -> float:
	return float(spec.get("spin_up_s", SPIN_UP_S)) * float(bot.spin_up_factor())


func _drive_motor() -> void:
	if not is_instance_valid(joint):
		return
	if jammed:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, MAX_OMEGA * _spin)


## Everything inside the blade's area takes `dps * dt * spin` this tick. Overlaps
## are sorted by instance id before anything is applied, because the order an Area
## reports them in is not part of the contract and the damage events would land in
## a different order between two runs of the same seed.
func _cut(dt: float) -> void:
	if jammed or cutter == null or blade == null or not is_instance_valid(blade) \
			or blade.detached or _spin < MIN_CUT_SPIN:
		_cutting_s = 0.0
		return
	var victims: Array[BotPart] = []
	for body in cutter.get_overlapping_bodies():
		var part := body as BotPart
		if part == null or part.detached or part.owner_bot == null \
				or part.owner_bot == bot:
			continue
		victims.append(part)
	if victims.is_empty():
		_cutting_s = 0.0
		return
	victims.sort_custom(func(a: BotPart, b: BotPart) -> bool:
		return a.get_instance_id() < b.get_instance_id())

	_cutting_s += dt
	var amount := float(spec.get("dps", 0.06)) * dt * _spin
	var knock := float(spec.get("knockback", 0.05)) * _spin
	for victim in victims:
		bot.opponent_damage_tick(victim, amount, "cut")
		if knock > 0.0:
			victim.apply_central_impulse(_tangential(victim.global_position) * knock)


func _tangential(point: Vector3) -> Vector3:
	var v := blade.linear_velocity + blade.angular_velocity.cross(
		point - blade.global_position)
	if v.length_squared() < 0.01:
		return Vector3.ZERO
	return v.normalized()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or blade == null or not is_instance_valid(blade) or blade.detached:
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func cutting_seconds() -> float:
	return _cutting_s


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "SAW %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	if blade == null or not is_instance_valid(blade) or blade.detached:
		return -1.0
	return maxf(blade.global_position.y, 0.0)


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_cutting_s = 0.0
	if is_instance_valid(joint):
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()
	_spin = 0.0


func state() -> Dictionary:
	return {"spin": snappedf(_spin, 0.001)}
