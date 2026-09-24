extends WeaponBase
## The Stage 3 flipper, moved out of bot.gd unchanged, as the reference
## implementation of WeaponBase for agents W1 and W2.
##
## EVERY NUMBER HERE IS SIGNED OFF. It was measured, not guessed
## (docs/stage3-physics-notes.md section 5): with the old motor driven throw the
## opponent reached 0.21 m and the wielder launched ITSELF to 0.65 m; modelling the
## flipper as what it actually is, a pneumatic ram, put the opponent at 0.78 m and
## the wielder at 0.29 m. Do not "tidy" these constants.
##
## The shape of a weapon module, for W1 and W2:
##   _build()                 make bodies and joints, register every body
##   apply_input(p, f, dt)    the button, level and edge
##   physics_tick(dt)         motors, timers, held forces
##   readiness() status_text() height_band() reach()
##   set_jammed() freeze() state()
## A weapon never touches the scene tree outside its bot, never reads the other
## bot directly, and draws randomness only from the rng it was handed.

## The arm rests ALONG the chassis' front slope. Lengthening it to 0.44 puts its
## tip's lower corner 0.025 m off the floor: under an opponent's 0.033 m underside,
## above the wedge lip's 0.015 m, and clear of the ground so it never scrapes.
## TRAP, measured: hanging it lower makes the arm a third ground contact, lifts the
## front wheels and the bot pogos around the arena.
const FLIPPER_LEN := 0.44
const FLIPPER_THICK := 0.03
const FLIPPER_WIDTH := 0.52
const FLIPPER_FRICTION := 0.08
const FLIPPER_LIMIT_UPPER := deg_to_rad(80.0)
const FLIPPER_FIRE_S := 0.12
const FLIPPER_RETURN_S := 0.45
## The sweep is presentation plus a scoop; the throw is the impulse pair below.
const FLIPPER_FIRE_VEL := 12.0
const FLIPPER_RETURN_VEL := -8.0
## MEASURED: Jolt ignores PARAM_MOTOR_MAX_IMPULSE on a hinge (the sweep is identical
## at 110 and at 2600). Kept for the day it is honoured.
const FLIPPER_FIRE_IMPULSE := 1200.0
const FLIPPER_HOLD_IMPULSE := 60.0

## The pneumatic throw: the gas throws whatever sits on the arm and pushes the
## wielder DOWN into the floor.
const FLIPPER_LAUNCH_IMPULSE := 115.0       # N s straight up into the target
const FLIPPER_LAUNCH_FORWARD := 12.0        # N s along the wielder's forward
const FLIPPER_LAUNCH_SPIN := 8.0            # N m s, tumbles the target away
## The reaction is spread across the fire window as a force, not dumped as one
## impulse: a single 210 N s hit into the floor reads as damage on our own wheels.
const FLIPPER_REACTION_SCALE := 1.0
## Sensor box over the arm: what "on the wedge" means.
const WEDGE_SENSOR_HEIGHT := 0.30
const WEDGE_SENSOR_BACK := 0.12

## THE THROW IS APPLIED TO THE VICTIM'S CHASSIS BODY, not to the whole machine, so
## how far it goes depends on the chassis' SHARE of the bot's mass: the chassis
## leaves at J / m_chassis and then drags its wheels and plates up through their
## joints, against the floor. Stage 3 hard coded a 22.0 kg chassis in a 48.0 kg bot
## (46 percent) and the throw was tuned against that split. Stage 4 takes the split
## from the catalogue, where a wedge's hull is 30 kg of a 96 kg build and the arm
## alone is 16 kg, so the chassis is nearer 35 percent, the same impulse drags half
## again as much dead weight, and the measured peak fell from 0.78 m to 0.46 m.
##
## So the impulse is normalised by the victim's chassis fraction. A bot built like
## Stage 3's gets exactly 115 N s; one carrying more of its mass outside the hull
## gets proportionally more, and the throw stays the signed off throw whatever the
## builder bolts on. Heavier bots are still harder to flip: mass is in the
## denominator either way, and `flip_resistance` still divides on top.
const REFERENCE_CHASSIS_FRACTION := 22.0 / 48.0
const LAUNCH_SCALE_MIN := 0.75
## 1.5 is the practical maximum a legal build reaches (a hull carrying only 30
## percent of its own mass); the clamp is there so a future part cannot turn the
## ram into a catapult.
const LAUNCH_SCALE_MAX := 1.5
## Stage 3's mass for the arm, which is the catalogue weight at the simulation's
## mass scale. Taken from the Bot so every part scales together.

var arm: BotPart = null
var joint: HingeJoint3D = null
var sensor: Area3D = null
var pivot := Vector3.ZERO
var rest_angle := 0.0

var _phase := 0                             # 0 idle, 1 firing, 2 returning
var _timer := 0.0
var _cooldown := 0.0
var _reaction_force := 0.0


func _build() -> void:
	pivot = socket_transform().origin
	# The ramp angle on a wedge or a Long/Low, unchanged; on a flat nosed hull the
	# angle that puts the arm's tip the same 0.025 m off the floor, because a level
	# arm at the socket height cannot get under anything (WeaponBase).
	rest_angle = ground_rest_angle(FLIPPER_LEN)

	arm = BotPart.new()
	arm.name = "Flipper"
	arm.part_key = FightTypes.PART_WEAPON
	arm.part_kind = "weapon"
	arm.material_name = "steel"
	arm.physics_material_override = _material(FLIPPER_FRICTION)

	var size := Vector3(FLIPPER_LEN, FLIPPER_THICK, FLIPPER_WIDTH)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	arm.add_child(shape)
	_add_visual(size)

	# What counts as "on the wedge": a box standing on the arm's top face, a little
	# longer at the back so a bot riding up the slope counts.
	sensor = Area3D.new()
	sensor.name = "WedgeSensor"
	sensor.collision_layer = 0
	sensor.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	sensor.monitorable = false
	var sensor_shape := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(FLIPPER_LEN + WEDGE_SENSOR_BACK, WEDGE_SENSOR_HEIGHT,
		FLIPPER_WIDTH + 0.04)
	sensor_shape.shape = sensor_box
	sensor_shape.position = Vector3(-WEDGE_SENSOR_BACK * 0.5,
		(WEDGE_SENSOR_HEIGHT + FLIPPER_THICK) * 0.5, 0.0)
	sensor.add_child(sensor_shape)
	arm.add_child(sensor)

	var basis := Basis(Vector3.BACK, rest_angle)
	arm.transform = Transform3D(basis,
		pivot + basis.x * (FLIPPER_LEN * 0.5) + basis.y * (FLIPPER_THICK * 0.5))
	bot.register_part(arm, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointFlipper"
	joint.transform = Transform3D(Basis(Vector3.BACK, rest_angle) * _jolt_flip(), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(arm)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -0.02)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, FLIPPER_LIMIT_UPPER)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, FLIPPER_RETURN_VEL)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, FLIPPER_HOLD_IMPULSE)
	joint.exclude_nodes_from_collision = true


## The arm model hinges at its socket_pivot, which is the model's own origin, so it
## hangs off the pivot end of the body rather than the body's centre.
## THE WEDGE RULING (docs/graphics-models-notes.md section 8): the arm rides ON TOP
## of the front armour plate, and the flipper model is authored with its own base
## plate already sloping 6.5 degrees, so mounting it at the full ramp angle drives
## the model through the armour and out of the bottom of the hull. The body sits at
## the ramp angle (that is the Stage 3 collision geometry, which is signed off);
## the MODEL is pitched back by this bias so the visible arm lies on the ramp.
const MODEL_PITCH_BIAS := deg_to_rad(6.5)


func _add_visual(size: Vector3) -> void:
	var model := PartVisuals.instantiate("flipper")
	if model != null:
		model.transform = Transform3D(Basis(Vector3.BACK, MODEL_PITCH_BIAS),
			Vector3(-size.x * 0.5, -size.y * 0.5, 0.0))
		arm.add_child(model)
		PartVisuals.bind(model, bot.livery)
		# Wave A (models): the gas system (bottle, regulator, line, valve block) is
		# its own node in flipper.glb, authored in the bot's orientation relative to
		# the pivot, because a gas bottle is bolted to the hull, not to the arm.
		# Presentation only: it has no body, no shape and no mass.
		var mount := model.get_node_or_null("mount") as Node3D
		if mount != null and bot.chassis != null:
			model.remove_child(mount)
			mount.owner = null
			mount.name = "FlipperMount"
			mount.transform = Transform3D(Basis.IDENTITY, pivot)
			bot.chassis.add_child(mount)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(size)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	arm.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.05
	return material


func _jolt_flip() -> Basis:
	return Basis(Vector3.RIGHT, PI)


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## Stage 3 read the button LEVEL and let the cooldown gate repeats, so that is
## what this does. W1 and W2's edge triggered weapons use `fired` instead.
func apply_input(pressed: bool, fired: bool, _dt: float) -> void:
	if pressed or fired:
		_try_fire()


func physics_tick(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	if _phase == 0:
		return
	# The ram's reaction, held down through the fire window. Forces are cleared
	# every step, so this has to be re-applied each tick.
	if _phase == 1 and _reaction_force > 0.0 and bot.chassis != null:
		bot.chassis.apply_central_force(Vector3.DOWN * _reaction_force)
	_timer -= dt
	if _timer > 0.0:
		return
	if _phase == 1:
		_phase = 2
		_timer = FLIPPER_RETURN_S
		_reaction_force = 0.0
		_set_motor(FLIPPER_RETURN_VEL, FLIPPER_HOLD_IMPULSE)
	else:
		_phase = 0


func _set_motor(velocity: float, impulse: float) -> void:
	if not is_instance_valid(joint):
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, velocity)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, impulse)


func _try_fire() -> void:
	if not ready():
		return
	_phase = 1
	_timer = FLIPPER_FIRE_S
	_set_motor(FLIPPER_FIRE_VEL, FLIPPER_FIRE_IMPULSE)
	_cooldown = FightTypes.FLIPPER_COOLDOWN_S
	# DEVIATION from spec section 4, deliberate and measured: the gas charge is
	# spent only when the ram actually has something to throw. Without it an AI
	# that fires on proximity burns every charge on thin air.
	if _launch_from_wedge():
		bot.gas_charges -= 1
	bot.emit_weapon_fired()


## The pneumatic throw. Returns true when something was on the arm.
func _launch_from_wedge() -> bool:
	var target := _wedge_target()
	if target == null:
		if bool(bot.debug_weapon):
			print("[flip] tick=%d %s dry fire" % [Engine.get_physics_frames(), bot.bot_id])
		return false
	var chassis: RigidBody3D = bot.chassis
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT
	var right := chassis.global_basis.z
	# Stage 4: a hull with a high `flip_resistance` takes less of the throw and one
	# with a low `tip_resistance` takes more of the tumble. A plain target (debris,
	# or a bot with no modifiers) sees exactly the Stage 3 numbers.
	var resist := 1.0
	var tip := 1.0
	var victim := _bot_of(target)
	var scale := _launch_scale(victim, target)
	if victim != null:
		resist = maxf(float(victim.call("flip_resistance")), 0.1)
		tip = maxf(float(victim.call("tip_resistance")), 0.1)
	var impulse := FLIPPER_LAUNCH_IMPULSE * scale
	target.apply_impulse(
		Vector3.UP * (impulse / resist) + fwd * FLIPPER_LAUNCH_FORWARD, Vector3.ZERO)
	target.apply_torque_impulse(right * (FLIPPER_LAUNCH_SPIN * scale / tip))
	# The wielder's reaction is the throw's equal and opposite, so it scales too,
	# spread across the fire window rather than dumped in one step.
	_reaction_force = impulse * FLIPPER_REACTION_SCALE / FLIPPER_FIRE_S
	if bool(bot.debug_weapon):
		print("[flip] tick=%d %s throws %s at %.1f N s (scale %.2f, chassis %.1f kg)" % [
			Engine.get_physics_frames(), bot.bot_id,
			"debris" if victim == null else str(victim.get("bot_id")),
			impulse, scale, target.mass])
	return true


## How much of the bot hangs off the chassis body the throw acts on. Loose debris
## and anything that is not a bot take the throw as authored.
func _launch_scale(victim: Node, target: RigidBody3D) -> float:
	if victim == null or target == null or target.mass <= 0.0:
		return 1.0
	var total: float = victim.call("total_mass")
	if total <= 0.0:
		return 1.0
	var fraction := target.mass / total
	if fraction <= 0.0:
		return 1.0
	return clampf(REFERENCE_CHASSIS_FRACTION / fraction, LAUNCH_SCALE_MIN, LAUNCH_SCALE_MAX)


func _bot_of(body: RigidBody3D) -> Node:
	if body is BotPart:
		var part: BotPart = body
		if part.owner_bot != null and part.owner_bot != bot:
			return part.owner_bot
	return null


## The body a throw would act on: the nearest foreign chassis (or loose debris)
## sitting on the arm. Picked by distance so the choice never depends on the order
## Jolt happens to report overlaps in.
func _wedge_target() -> RigidBody3D:
	if sensor == null or arm == null or arm.detached:
		return null
	var here := arm.global_position
	var best: RigidBody3D = null
	var best_distance := INF
	for body in sensor.get_overlapping_bodies():
		var candidate: RigidBody3D = null
		if body is BotPart:
			var other: BotPart = body
			if other.owner_bot == bot:
				continue
			if not other.detached and other.owner_bot != null:
				candidate = other.owner_bot.chassis
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


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## True when a throw right now would land on something. For the AI.
func opponent_on_wedge() -> bool:
	return _wedge_target() != null


## True when the flipper could fire this tick (not jammed, has gas, at rest).
func ready() -> bool:
	return not jammed and bot.gas_charges > 0 and _phase == 0 and _cooldown <= 0.0 \
		and arm != null and not arm.detached


func readiness() -> float:
	if jammed or arm == null or arm.detached:
		return 0.0
	if bot.gas_charges <= 0:
		return 0.0
	if _phase != 0 or _cooldown > 0.0:
		return clampf(1.0 - _cooldown / maxf(FightTypes.FLIPPER_COOLDOWN_S, 0.001), 0.0, 0.99)
	return 1.0


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "GAS %d" % maxi(bot.gas_charges, 0)


func tip_height() -> float:
	if arm == null or arm.detached:
		return -1.0
	return maxf((arm.global_transform * Vector3(FLIPPER_LEN * 0.5, 0.0, 0.0)).y, 0.0)


## Stage 3 banded on the LIVE arm tip, not on the catalogue row, and the HUD reads
## it every frame, so that behaviour is kept.
func height_band() -> String:
	var h := tip_height()
	if h < 0.0:
		return str(spec.get("height_band", "floor"))
	if h < 0.10:
		return "floor"
	if h < 0.30:
		return "mid"
	return "high"


func set_jammed() -> void:
	jammed = true
	_phase = 0
	if is_instance_valid(joint):
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"charges": maxi(bot.gas_charges, 0)}
