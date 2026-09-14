extends WeaponBase
## The crusher claw (docs/stage4-spec.md section 4): a hinged jaw over the nose
## that closes with `clamp_force`, and once it has held an opponent's part for
## longer than PIN_S it PINS them: the victim's drive is fought while the jaw
## chews `dps` off whatever is between the teeth.
##
## HOW THE PIN IS DONE, because the spec offers two ways and this file picks one:
## BOTH, and deliberately.
##   1. `victim.disrupt("drive", DISRUPT_REFRESH_S)` re-applied every tick while
##      clamped. That is the gameplay half: the Bot's own drive disruption path
##      (bot.gd `apply_input`) stops the victim's motors instead of driving them,
##      which is exactly "the other bot's drive is fought by the clamp", and it
##      uses machinery P2 already exposes rather than a second private one. It
##      lapses 0.2 s after the jaw lets go, so a released bot drives away almost
##      at once.
##   2. A grip force between the clamped body and the jaw, with the equal and
##      opposite force on our own chassis. That is the physics half: without it
##      the victim is still free to be shoved out of the jaw by a third party or
##      by its own momentum, and the claw would look like a magnet that stops
##      wheels rather than a hand that holds a robot. The force is capped at the
##      catalogue `clamp_force` (at the simulation's mass scale), so the number in
##      the shop is the number in the fight.
## Only one of the two would read as a bug: disruption alone is an invisible hand,
## and a grip alone lets a 6WD bot walk out of the claw.
##
## Jolt ignores PARAM_MOTOR_MAX_IMPULSE on a hinge (measured, flipper.gd), so the
## closing motor is a velocity constraint and `clamp_force` could not have been
## the jaw's motor strength even if we wanted it to be. It is the grip cap.

## The jaw, in its own frame: +X runs from the hinge to the teeth.
const JAW_LEN := 0.33                        # hinge to teeth, from the model
const JAW_THICK := 0.075
const JAW_WIDTH := 0.17
const JAW_FRICTION := 0.9                    # teeth, not skids

## The model is authored CLOSED: its socket_pivot is 0.19 above the mount and its
## socket_tip 0.30 forward and 0.145 below the pivot, i.e. the jaw sits 25.8
## degrees nose down (Arena/assets/parts/manifest.json). That authored pose is the
## closed angle here so the model and the body agree without a fudge factor.
const PIVOT_LIFT := 0.19
const JAW_CLOSED := -0.4504                  # atan2(-0.145, 0.30)
const JAW_OPEN_SWEEP := deg_to_rad(48.0)
## How far back from the nose the hinge sits. The catalogue mounts a crusher on
## the deck, and on a hull like the wedge the deck socket is near the CENTRE of
## the bot, which would leave a 0.30 m jaw closing on the wielder's own lid. The
## weapon decides its own business end (docs/stage4-assembly-notes.md section 3:
## "the WEAPON decides first and the hull second"), so the hinge moves forward to
## the front of the deck and the claw hangs over the nose, which is where every
## real crusher puts it.
const JAW_SETBACK := 0.12

const CLOSE_SPEED := 3.2                     # rad/s, a fast bite
const OPEN_SPEED := 2.4
const MOTOR_IMPULSE := 600.0

## A contact has to be held this long before it counts as a pin, so brushing past
## a bot with the jaw shutting does not lock it.
const PIN_S := 0.3
## Re-applied every tick while clamped; long enough to survive a tick where the
## sensor blinks, short enough that letting go frees the victim at once.
const DISRUPT_REFRESH_S := 0.2
## The grip: a spring and damper between the clamped body and the jaw's bite
## point, capped at the catalogue clamp force. Damping does most of the work
## (killing the relative motion IS the pin); the spring only stops a slow drift.
const GRIP_SPRING := 900.0                   # N per metre
const GRIP_DAMP := 420.0                     # N per m/s
const GRIP_REACH := 0.35                     # past this the part has escaped

var jaw: BotPart = null
var joint: HingeJoint3D = null
var bite: Area3D = null
var pivot := Vector3.ZERO

var _closing := false
var _hold := 0.0
var _clamped: BotPart = null
var _clamp_force := 900.0
var _dps := 0.08


func _build() -> void:
	var at := socket_transform().origin
	_clamp_force = maxf(float(spec.get("clamp_force", 900.0)), 1.0)
	_dps = maxf(float(spec.get("dps", 0.08)), 0.0)
	pivot = Vector3(maxf(at.x, bot.chassis_module.half_len() - JAW_SETBACK),
		at.y + PIVOT_LIFT, 0.0)

	jaw = BotPart.new()
	jaw.name = "CrusherJaw"
	jaw.part_key = FightTypes.PART_WEAPON
	jaw.part_kind = "weapon"
	jaw.material_name = "steel"
	jaw.physics_material_override = _material(JAW_FRICTION)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(JAW_LEN, JAW_THICK, JAW_WIDTH)
	shape.shape = box
	jaw.add_child(shape)
	_add_visual()

	# What "in the jaw" means: the gap under the teeth, between the claw and the
	# hull it closes onto. Generous on purpose, because a bite that only registers
	# on a perfect contact never registers in a fight.
	bite = Area3D.new()
	bite.name = "BiteSensor"
	bite.collision_layer = 0
	bite.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	bite.monitorable = false
	var bite_shape := CollisionShape3D.new()
	var bite_box := BoxShape3D.new()
	bite_box.size = Vector3(0.24, 0.20, 0.24)
	bite_shape.shape = bite_box
	bite.add_child(bite_shape)
	# The OFFSET GOES ON THE AREA, not on its shape: `bite.global_position` is the
	# anchor the grip pulls the victim onto, and an Area sitting at the jaw's
	# centre with only its shape moved out to the teeth would drag whatever it
	# caught 0.19 m back into the hinge. Measured: it threw the victim around at
	# 0.4 m/s while the claw claimed to be pinning it.
	bite.position = Vector3(JAW_LEN * 0.5 - 0.08, -0.11, 0.0)
	jaw.add_child(bite)

	var basis := Basis(Vector3.BACK, JAW_CLOSED)
	jaw.transform = Transform3D(basis, pivot + basis.x * (JAW_LEN * 0.5))
	bot.register_part(jaw, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointCrusher"
	joint.transform = Transform3D(Basis(Vector3.BACK, JAW_CLOSED) * _jolt_flip(), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(jaw)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -0.02)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, JAW_OPEN_SWEEP)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, OPEN_SPEED)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


func _add_visual() -> void:
	var model := PartVisuals.instantiate("crusher")
	if model != null:
		# The model's origin is its MOUNT, which is PIVOT_LIFT below the hinge, and
		# its arm is authored at JAW_CLOSED. The body's +X is the arm, so undo the
		# authored angle and then put the model's pivot on the body's hinge end.
		var fix := Basis(Vector3.BACK, -JAW_CLOSED)
		model.transform = Transform3D(fix,
			Vector3(-JAW_LEN * 0.5, 0.0, 0.0) + fix * Vector3(0.0, -PIVOT_LIFT, 0.0))
		jaw.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(JAW_LEN, JAW_THICK, JAW_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	jaw.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.0
	return material


func _jolt_flip() -> Basis:
	return Basis(Vector3.RIGHT, PI)


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL: hold to bite and keep holding to stay latched, which is what the AI
## ("saw/crusher latch and stay") and the player both want from a claw.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_closing = pressed


func physics_tick(dt: float) -> void:
	if jammed or jaw == null or jaw.detached:
		_hold = 0.0
		_clamped = null
		return
	if is_instance_valid(joint):
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
			-CLOSE_SPEED if _closing else OPEN_SPEED)

	if not _closing:
		_hold = 0.0
		_clamped = null
		return

	var target := _bite_target()
	if target == null:
		_hold = 0.0
		_clamped = null
		return
	if target != _clamped:
		_clamped = target
		_hold = 0.0
	_hold += dt
	if _hold < PIN_S:
		return
	_pin(target, dt)


## Everything the clamp does once it has actually got hold of something.
func _pin(part: BotPart, dt: float) -> void:
	var victim := part.owner_bot
	if victim != null and victim.has_method("disrupt"):
		victim.call("disrupt", "drive", DISRUPT_REFRESH_S)
	_grip(part, dt)
	bot.opponent_damage_tick(part, _dps * dt, "cut")


## The hand. A spring and damper pulling the clamped body onto the bite point,
## capped at the catalogue clamp force, with the reaction on our own chassis so
## the pair does not manufacture momentum out of nothing.
func _grip(part: BotPart, _dt: float) -> void:
	if bot.chassis == null or bite == null:
		return
	var chassis: RigidBody3D = bot.chassis
	var anchor := bite.global_position
	var offset := anchor - part.global_position
	if offset.length() > GRIP_REACH:
		return
	var relative := part.linear_velocity - chassis.linear_velocity
	var force := offset * GRIP_SPRING - relative * GRIP_DAMP
	var cap := _clamp_force * Bot.MASS_SCALE
	if force.length() > cap:
		force = force.normalized() * cap
	part.apply_central_force(force)
	chassis.apply_central_force(-force)


## The nearest foreign body in the jaw gap. Nearest, not first, because the order
## Jolt reports overlaps in depends on recycled RIDs and would put the determinism
## test on a knife edge.
func _bite_target() -> BotPart:
	if bite == null or jaw == null or jaw.detached or not bite.is_inside_tree():
		return null
	var here := bite.global_position
	var best: BotPart = null
	var best_distance := INF
	for body in bite.get_overlapping_bodies():
		var other := body as BotPart
		if other == null or other.detached or other.owner_bot == bot:
			continue
		if other.owner_bot == null:
			continue
		var d := here.distance_squared_to(other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## True while the claw is holding an opponent. The AI's "latch and stay" test.
func is_clamped() -> bool:
	return _clamped != null and _hold >= PIN_S


func clamped_part() -> BotPart:
	return _clamped if is_clamped() else null


## Radians open, measured off the live jaw.
func open_angle() -> float:
	if jaw == null or jaw.detached or bot.chassis == null or not jaw.is_inside_tree():
		return 0.0
	var chassis: RigidBody3D = bot.chassis
	var local: Vector3 = chassis.global_basis.inverse() * jaw.global_basis.x
	return wrapf(atan2(local.y, local.x) - JAW_CLOSED, -PI, PI)


func open_fraction() -> float:
	return clampf(open_angle() / JAW_OPEN_SWEEP, 0.0, 1.0)


## A claw is "ready" when it is holding, or when it is open enough to take a bite.
## A closed jaw with nothing in it is the one state the AI should back out of.
func readiness() -> float:
	if jammed or jaw == null or jaw.detached:
		return 0.0
	if is_clamped():
		return 1.0
	return 0.4 + 0.6 * open_fraction()


func status_text() -> String:
	if jammed:
		return "JAMMED"
	if is_clamped():
		return "CLAMP"
	if _closing:
		return "BITE"
	return "OPEN"


func set_jammed() -> void:
	jammed = true
	_closing = false
	_hold = 0.0
	_clamped = null
	if is_instance_valid(joint):
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"clamped": is_clamped(), "open": open_fraction()}
