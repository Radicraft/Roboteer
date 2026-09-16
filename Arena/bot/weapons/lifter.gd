extends WeaponBase
## The lifter (docs/stage4-spec.md section 4): a pair of forks on a strong, slow
## hinge at the front socket. Held, it raises at the catalogue `lift_rate` toward
## 70 degrees; released, it lowers again at the same rate. There is no launch and
## no charge: carrying an opponent is pure physics, their hull resting on the
## tines, and the only way to hurt them with it is where you put them down.
##
## It is the flipper's geometry with the flipper's violence taken out, on purpose:
## the two weapons share a mount, a rest angle and a hinge, and the whole
## difference in the hand is that one throws in 0.12 s and this one carries at
## 1.2 rad/s. The trap the flipper records applies here word for word: an arm that
## reaches the floor becomes a third ground contact, lifts the front wheels and
## the bot pogos, so the tines hang exactly where the flipper's arm hangs and the
## length comes from the catalogue reach, never from "it looks short".

## Geometry. FORK_LEN is the catalogue reach (0.40) and the tines stop there.
const FORK_LEN := 0.40
const FORK_THICK := 0.026
const FORK_WIDTH := 0.46                     # outside to outside across both tines
const TINE_WIDTH := 0.13
const ROOT_LEN := 0.10                       # the cross bar the tines bolt to
## The forks GRIP, where the flipper's arm is deliberately slippery (0.08): a bot
## being carried must not slide off the moment the wielder turns.
const FORK_FRICTION := 0.6
const LIFT_LIMIT := deg_to_rad(70.0)
const LIFT_FLOOR := -0.02                    # a hair below rest, as the flipper has

## Jolt ignores PARAM_MOTOR_MAX_IMPULSE on a hinge (measured, see flipper.gd), so
## the motor is a velocity constraint and the lift is as strong as it needs to be.
## That is exactly the catalogue's promise for this weapon ("slow, controllable"),
## and the number is kept for the day the parameter is honoured.
const MOTOR_IMPULSE := 900.0

## The lifter model's own arm droops 3.6 degrees below its +X (socket_tip is 26 mm
## low at 414 mm, `Arena/assets/parts/manifest.json`), so the MODEL is pitched back
## by that much to lie along the body. Same fix as the flipper's 6.5 degrees, and
## the same reason: the body is the signed off collision geometry, the model is
## what you see.
const MODEL_PITCH_BIAS := deg_to_rad(3.6)

var arm: BotPart = null
var joint: HingeJoint3D = null
var pivot := Vector3.ZERO
var rest_angle := 0.0

var _raising := false
var _lift_rate := 1.2


func _build() -> void:
	pivot = socket_transform().origin
	# The flipper's rule, word for word (see WeaponBase.ground_rest_angle): the
	# ramp angle on a ramped hull, and on a flat nosed one the angle that drops the
	# tines to the same 0.025 m off the floor. Forks that ride at the socket height
	# are a shelf, not a lifter.
	rest_angle = ground_rest_angle(FORK_LEN)
	_lift_rate = maxf(float(spec.get("lift_rate", 1.2)), 0.05)

	arm = BotPart.new()
	arm.name = "LifterForks"
	arm.part_key = FightTypes.PART_WEAPON
	arm.part_kind = "weapon"
	arm.material_name = "steel"
	arm.physics_material_override = _material(FORK_FRICTION)

	# One body, three boxes: a cross bar at the hinge and two tines reaching out.
	var tine_len := FORK_LEN - ROOT_LEN
	_add_box(Vector3(ROOT_LEN, FORK_THICK, FORK_WIDTH),
		Vector3(-FORK_LEN * 0.5 + ROOT_LEN * 0.5, 0.0, 0.0))
	var tine_x := -FORK_LEN * 0.5 + ROOT_LEN + tine_len * 0.5
	var tine_z := (FORK_WIDTH - TINE_WIDTH) * 0.5
	_add_box(Vector3(tine_len, FORK_THICK, TINE_WIDTH), Vector3(tine_x, 0.0, tine_z))
	_add_box(Vector3(tine_len, FORK_THICK, TINE_WIDTH), Vector3(tine_x, 0.0, -tine_z))
	_add_visual()

	var basis := Basis(Vector3.BACK, rest_angle)
	arm.transform = Transform3D(basis,
		pivot + basis.x * (FORK_LEN * 0.5) + basis.y * (FORK_THICK * 0.5))
	bot.register_part(arm, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointLifter"
	joint.transform = Transform3D(Basis(Vector3.BACK, rest_angle) * _jolt_flip(), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(arm)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, LIFT_FLOOR)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, LIFT_LIMIT)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


func _add_box(size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	arm.add_child(shape)


func _add_visual() -> void:
	var model := PartVisuals.instantiate("lifter")
	if model != null:
		# The model's origin IS its mount socket, so it goes where the hinge is,
		# which in body space is the back end of the forks.
		model.transform = Transform3D(Basis(Vector3.BACK, MODEL_PITCH_BIAS),
			Vector3(-FORK_LEN * 0.5, -FORK_THICK * 0.5, 0.0))
		arm.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(FORK_LEN, FORK_THICK, FORK_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	arm.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.02
	return material


func _jolt_flip() -> Basis:
	return Basis(Vector3.RIGHT, PI)


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL, not the edge: this is a held control, which is the whole point of
## the weapon. `fired` is ignored.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_raising = pressed


func physics_tick(_dt: float) -> void:
	if jammed or joint == null or not is_instance_valid(joint):
		return
	if arm != null and arm.detached:
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
		_lift_rate if _raising else -_lift_rate)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## Radians above the rest angle, measured off the live arm rather than integrated
## from the motor command, so a fork jammed under a wall reads where it really is.
func lift_angle() -> float:
	if arm == null or arm.detached or bot.chassis == null or not arm.is_inside_tree():
		return 0.0
	var chassis: RigidBody3D = bot.chassis
	var local: Vector3 = chassis.global_basis.inverse() * arm.global_basis.x
	return wrapf(atan2(local.y, local.x) - rest_angle, -PI, PI)


func lift_fraction() -> float:
	return clampf(lift_angle() / LIFT_LIMIT, 0.0, 1.0)


func tip_height() -> float:
	if arm == null or arm.detached or not arm.is_inside_tree():
		return -1.0
	return maxf((arm.global_transform * Vector3(FORK_LEN * 0.5, 0.0, 0.0)).y, 0.0)


## Read off the live tine tip, the way the flipper reads its arm: the HUD asks
## every frame and the answer changes as the forks come up.
func height_band() -> String:
	var h := tip_height()
	if h < 0.0:
		return str(spec.get("height_band", "floor"))
	if h < 0.10:
		return "floor"
	if h < 0.30:
		return "mid"
	return "high"


## "Ready" for a lifter means "low enough to get under something", so it falls as
## the forks rise and never reaches zero: a raised lifter is still a working
## weapon, it just cannot scoop until it comes down.
func readiness() -> float:
	if jammed or arm == null or arm.detached:
		return 0.0
	return 1.0 - 0.7 * lift_fraction()


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "LIFT %d%%" % int(round(lift_fraction() * 100.0))


func set_jammed() -> void:
	jammed = true
	_raising = false
	if is_instance_valid(joint):
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"lift": lift_fraction()}
