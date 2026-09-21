extends WeaponBase
## Drill lance (brief v5 section 9.5, Level 65, wave P agent D1).
##
## A lance on a hinge along the bot's FORWARD axis, so it turns about its own
## length like a drill rather than sweeping like a saw. `pressed` brings it to
## speed over `spin_up_s` and it then chews whatever its flutes are against, at
## `dps` a second, with almost no knockback.
##
## WHAT MAKES IT DIFFERENT FROM THE SAW, and the only reason to spend 19 kg on one
## when a saw costs 12: it reports its damage as "pierce", and
## `Bot.take_direct_damage` resolves that source through `BotDamage.pierce_factor`,
## which takes the plate's own `cut` factor halfway to 1.0. Steel's 0.4 becomes
## 0.7 and HDPE's 1.6 becomes 1.3. A saw is the best weapon in the game against
## HDPE and the worst against steel, a four fold spread; the lance's spread is
## under two fold, so it is the weapon you fit when you do not know what you are
## about to meet. Against HDPE a saw still wins.
##
## GEOMETRY. The lance is a cylinder lying along +X, hung far enough forward that
## its point stands proud of the hull's own nose (the measured lesson in `ram.gd`)
## and high enough off the floor that it never becomes a third ground contact
## (the pogo trap in `flipper.gd`). The hinge turns about the JOINT's local Z, so
## the joint's basis rotates Z onto the bot's +X.
##
## The spin speed is 18 rad/s, not the 30 the first cut used. `saw.gd` measured
## the trap: a motor driven hinge cannot be stalled (Jolt ignores
## PARAM_MOTOR_MAX_IMPULSE), so a fast body held against a plate resolves as an
## enormous contact impulse EVERY step, and the lance, which is a real part on the
## "weapon" BREAK row, grinds its own condition away in seconds. A lance is meant
## to be leant on for the whole fight, so it turns slowly and hurts through `dps`.

const LANCE_LENGTH := 0.30
const LANCE_RADIUS := 0.075
const LANCE_FRICTION := 0.12
const MAX_OMEGA := 18.0
const MOTOR_IMPULSE := 500.0
const COAST_S := 1.6
## The cutting sleeve is the lance plus a couple of millimetres, so a plate
## resting against the flutes is inside it.
const AREA_MARGIN := 0.016
const GROUND_CLEAR := 0.012
## How far past the hull's own nose the point stands.
const NOSE_PROUD := 0.16
## Below this the lance is turning too slowly to bite.
const MIN_CUT_SPIN := 0.05

var lance: BotPart = null
var joint: HingeJoint3D = null
var cutter: Area3D = null
var pivot := Vector3.ZERO

var _spin := 0.0
var _pressed := false
var _announced := false
## Seconds of unbroken contact, for the readout and the notes' numbers.
var _cutting_s := 0.0


func _build() -> void:
	pivot = socket_transform().origin
	pivot.y = maxf(pivot.y,
		float(bot.chassis_module.floor_y()) + GROUND_CLEAR + LANCE_RADIUS)
	pivot.x = maxf(pivot.x, _nose() + NOSE_PROUD - LANCE_LENGTH * 0.5)
	pivot.z = 0.0

	lance = BotPart.new()
	lance.name = "DrillLance"
	lance.part_key = FightTypes.PART_WEAPON
	lance.part_kind = "weapon"
	lance.material_name = "steel"
	lance.physics_material_override = _material()
	lance.continuous_cd = true

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = LANCE_RADIUS
	cylinder.height = LANCE_LENGTH
	shape.shape = cylinder
	shape.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))   # cylinder axis Y to X
	lance.add_child(shape)

	# What "the lance is against it" means. Monitorable off: nothing needs to find
	# this area, it only asks.
	cutter = Area3D.new()
	cutter.name = "Flutes"
	cutter.collision_layer = 0
	cutter.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	cutter.monitorable = false
	var cut_shape := CollisionShape3D.new()
	var cut_cylinder := CylinderShape3D.new()
	cut_cylinder.radius = LANCE_RADIUS + AREA_MARGIN
	cut_cylinder.height = LANCE_LENGTH + AREA_MARGIN * 2.0
	cut_shape.shape = cut_cylinder
	cut_shape.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	cutter.add_child(cut_shape)
	lance.add_child(cutter)

	_add_visual()

	lance.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.register_part(lance, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointLance"
	# The hinge turns about the JOINT's local Z, so Z has to point along the bot's
	# forward: a quarter turn about Y takes (0, 0, 1) to (1, 0, 0).
	joint.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(lance)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "drill_lance")))
	if model != null:
		var offset := Vector3(LANCE_LENGTH * 0.5, 0.0, 0.0)
		var sockets := PartVisuals.read_sockets(model)
		if sockets.has("socket_pivot"):
			offset = sockets["socket_pivot"]
		model.position = -offset
		lance.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = LANCE_RADIUS * 0.25            # a point, not a stub
	mesh.bottom_radius = LANCE_RADIUS
	mesh.height = LANCE_LENGTH
	mesh.radial_segments = 14
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(0.0, 0.0, deg_to_rad(-90.0))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	lance.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = LANCE_FRICTION
	material.bounce = 0.0
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	var alive := lance != null and is_instance_valid(lance) and not lance.detached
	var winding := _pressed and not jammed and alive \
		and not bool(bot.is_disrupted("weapon"))
	if winding:
		_spin = minf(_spin + dt / maxf(spin_up_s(), 0.01), 1.0)
	else:
		_spin = maxf(_spin - dt / COAST_S, 0.0)
	_drive_motor()
	_bore(dt)
	if _spin >= 1.0 and not _announced:
		_announced = true
		bot.emit_weapon_fired()
	elif _spin < 0.5:
		_announced = false


func spin_up_s() -> float:
	return float(spec.get("spin_up_s", 1.0)) * float(bot.spin_up_factor())


func _drive_motor() -> void:
	if not is_instance_valid(joint):
		return
	if jammed:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, MAX_OMEGA * _spin)


## Everything inside the flutes takes `dps * dt * spin` this tick, reported as
## "pierce". Overlaps are sorted by instance id before anything is applied,
## because the order an Area reports them in is not part of the contract.
func _bore(dt: float) -> void:
	if jammed or cutter == null or lance == null or not is_instance_valid(lance) \
			or lance.detached or _spin < MIN_CUT_SPIN or not cutter.is_inside_tree():
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
	var amount := float(spec.get("dps", 0.075)) * dt * _spin
	var knock := float(spec.get("knockback", 0.04)) * _spin
	for victim in victims:
		bot.opponent_damage_tick(victim, amount, BotDamage.SOURCE_PIERCE)
		if knock > 0.0:
			victim.apply_central_impulse(_thrust() * knock)


## The lance pushes along its own length, which is the bot's forward. A drill
## does not throw anything sideways, so the nudge is there to make a bored plate
## shudder and nothing more.
func _thrust() -> Vector3:
	if lance == null or not is_instance_valid(lance):
		return Vector3.ZERO
	var forward := lance.global_basis.x
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		return Vector3.ZERO
	return forward.normalized()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or lance == null or not is_instance_valid(lance) or lance.detached:
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func boring_seconds() -> float:
	return _cutting_s


## How much of the plate's material stops counting. One number, in `damage.gd`
## beside the rule it feeds, because the Bot is the only thing that can apply it
## (only the victim knows what its own plate is made of). The test reads it.
func armour_pierce() -> float:
	return BotDamage.PIERCE_IGNORE


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "DRILL %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	if lance == null or not is_instance_valid(lance) or lance.detached:
		return -1.0
	return maxf(lance.global_position.y, 0.0)


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
