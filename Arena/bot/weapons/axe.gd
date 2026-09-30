extends WeaponBase
## The axe (docs/stage4-spec.md section 4): an overhead arm on the top socket that
## does nothing at all for `reset_s` and then, on the edge of the button, throws
## the whole 130 degree sweep in 0.15 s. One hit, hard, and the catalogue's
## `top_bonus` makes it the answer to a bot with a thin lid.
##
## THE SIGN CONVENTION, because the spec's two numbers need one. The spec says the
## arm "swings from rest (-70 degrees) to +60". Measured the way this file does it
## (the angle of the arm, hinge to head, from the FORWARD horizontal, positive up)
## the rest is +60 and the strike is -70: cocked means head high and forward, and
## the strike drives the head DOWN in front of the nose. The spec's own signs put
## the rest position head down at the floor and the strike pointing at the sky,
## which is an axe running backwards. Same two numbers, same 130 degree sweep, the
## sign stated here once so nobody has to guess it again.
##
## THE FLOOR CLAMP. A 0.6 m arm on a low hull would drive its head through the
## floor at -70 and pole vault the wielder, so the strike stops where the head
## would reach the floor (STRIKE_CLEARANCE above it). On a wedge that is about -41
## degrees; on a tall tank, whose deck is 0.4 m up, the full -70 fits.
##
## WHAT THE BLOW IS. Two things, as the flipper's throw is:
##   the PHYSICAL half, an impulse into the victim's chassis along the head's
##   travel (down and forward), which slams them into the floor; and
##   the DAMAGE half, `bot.opponent_damage_tick` on the part the head found, which
##   is what produces the damage_event R's judges score.
## The physical half is a SHARE of the catalogue `impulse`, not all of it: the
## catalogue number is a design weight (the flipper's row says 260 and its
## measured, signed off throw is 115 N s), and 220 N s into a 15 kg chassis body is
## 14 m/s, which is a bot leaving the arena, not a bot being hit with an axe.

## Geometry. ARM_LEN is the catalogue reach.
const ARM_LEN := 0.60
const SHAFT_THICK := 0.05
const SHAFT_WIDTH := 0.07
const HEAD_LEN := 0.13
const HEAD_HEIGHT := 0.14
const HEAD_WIDTH := 0.09
const AXE_FRICTION := 0.4

## The hinge sits PIVOT_LIFT above the mount, from the model's socket_pivot
## (0, 0.225, 0), and the model's own arm is authored MODEL_ARM_ANGLE above its
## horizontal (socket_tip at 0.545, 0.506 is 0.281 above the pivot at 0.545 out).
const PIVOT_LIFT := 0.225
const MODEL_ARM_ANGLE := 0.4770               # atan2(0.281, 0.545), 27.3 degrees

const REST_DEG := 60.0
const STRIKE_DEG := -70.0
const STRIKE_CLEARANCE := 0.05                # the head stops this far off the floor
## How far back from the nose the hinge sits, for the same reason the crusher's
## does and with the same measurement behind it. On the wedge the deck socket is
## at x = 0.05, the middle of the bot: a 0.6 m arm hinged there passes an
## opponent's lid height (0.22 m) at x = 0.61, and two touching wedges have their
## centres 0.90 m apart, so the head would come down INSIDE the wielder's own nose
## and `top_bonus` could never be paid. Hinged at the front of the deck the same
## arm crosses 0.22 m at x = 0.91, which is an opponent's deck, nose to nose.
const PIVOT_SETBACK := 0.12
const STRIKE_S := 0.15
## The first third of the reset is dead weight: the motor is off, the arm hangs
## where it landed and the bot carries it. Then it winds back up. "Dead weight
## meanwhile" in the spec, and it is also what stops the arm springing straight
## back off a victim it is still resting on.
const RESET_LIMP_FRACTION := 0.35
const HOLD_IMPULSE := 400.0
const STRIKE_IMPULSE := 1400.0

## The physical share of the catalogue impulse (see the header).
const BLOW_SHARE := 0.27
## Condition removed per N s of the catalogue impulse. 220 N s is 0.22 of a plate,
## 0.35 with the top bonus, before the material's own impact factor: three clean
## overhead hits take a steel lid off, five take it off the side, and the reset
## means those three hits are five seconds apart.
const DAMAGE_PER_IMPULSE := 0.001
## The recoil, spread across the strike window as a FORCE rather than dumped as
## one impulse. The flipper measured what dumping does: a single hit into your own
## chassis reads as damage on your own wheels.
const REACTION_SHARE := 0.45

var arm: BotPart = null
var joint: HingeJoint3D = null
var head: Area3D = null
var pivot := Vector3.ZERO
var rest_angle := deg_to_rad(REST_DEG)
var strike_angle := deg_to_rad(STRIKE_DEG)

var _phase := 0                              # 0 cocked, 1 striking, 2 resetting
var _timer := 0.0
var _reset_left := 0.0
var _struck := false
var _reaction := Vector3.ZERO
var _impulse := 220.0
var _top_bonus := 1.6
## The last blow this axe landed: {part, amount, top, tick}. Empty until it hits
## something. The test reads it, and so could the FX layer.
var _last_strike: Dictionary = {}
## The visual wind-back on the press (Arena/bot/axe_windup.gd). Presentation only.
var windup: AxeWindup = null


func _build() -> void:
	var at := socket_transform().origin
	_impulse = maxf(float(spec.get("impulse", 220.0)), 0.0)
	_top_bonus = maxf(float(spec.get("top_bonus", 1.6)), 1.0)
	pivot = Vector3(maxf(at.x, bot.chassis_module.half_len() - PIVOT_SETBACK),
		at.y + PIVOT_LIFT, 0.0)

	# Where the head may stop: never through the floor. floor_y is the hull's
	# underside in bot space and the bot rides `ride_height` above the arena.
	var pivot_height: float = pivot.y + float(bot.ride_height())
	var reachable := clampf((pivot_height - STRIKE_CLEARANCE) / ARM_LEN, 0.0, 1.0)
	strike_angle = maxf(deg_to_rad(STRIKE_DEG), -asin(reachable))
	rest_angle = deg_to_rad(REST_DEG)

	arm = BotPart.new()
	arm.name = "AxeArm"
	arm.part_key = FightTypes.PART_WEAPON
	arm.part_kind = "weapon"
	arm.material_name = "steel"
	arm.physics_material_override = _material(AXE_FRICTION)

	var shaft_len := ARM_LEN - HEAD_LEN
	_add_box(Vector3(shaft_len, SHAFT_THICK, SHAFT_WIDTH),
		Vector3(-ARM_LEN * 0.5 + shaft_len * 0.5, 0.0, 0.0))
	_add_box(Vector3(HEAD_LEN, HEAD_HEIGHT, HEAD_WIDTH),
		Vector3(ARM_LEN * 0.5 - HEAD_LEN * 0.5, 0.0, 0.0))
	_add_visual()

	# The head's own volume: what the swing is allowed to hit.
	head = Area3D.new()
	head.name = "HeadSensor"
	head.collision_layer = 0
	head.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	head.monitorable = false
	var sensor_shape := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(0.22, 0.26, 0.26)
	sensor_shape.shape = sensor_box
	head.add_child(sensor_shape)
	# The OFFSET GOES ON THE AREA, not on its shape: `head.global_position` is
	# where the blow is reported to have landed, and `face_for_contact` reads it.
	# An Area at the arm's centre with only its shape moved out would say the axe
	# hit a bot 0.25 m behind where the head actually is.
	head.position = Vector3(ARM_LEN * 0.5 - 0.05, 0.0, 0.0)
	arm.add_child(head)

	var basis := Basis(Vector3.BACK, rest_angle)
	arm.transform = Transform3D(basis, pivot + basis.x * (ARM_LEN * 0.5))
	bot.register_part(arm, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointAxe"
	joint.transform = Transform3D(Basis(Vector3.BACK, rest_angle) * _jolt_flip(), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(arm)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	# Hinge angle 0 is the cocked rest; the strike runs NEGATIVE, down to the
	# sweep the hull has room for.
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, strike_angle - rest_angle)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 0.02)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, HOLD_IMPULSE)
	joint.exclude_nodes_from_collision = true


func _add_box(size: Vector3, at: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	arm.add_child(shape)


func _add_visual() -> void:
	var model := PartVisuals.instantiate("axe")
	if model != null:
		# Undo the model's authored arm angle so its shaft lies along the body's
		# +X, then drop its origin (the MOUNT, PIVOT_LIFT below the hinge) onto the
		# body's hinge end.
		var fix := Basis(Vector3.BACK, -MODEL_ARM_ANGLE)
		model.transform = Transform3D(fix,
			Vector3(-ARM_LEN * 0.5, 0.0, 0.0) + fix * Vector3(0.0, -PIVOT_LIFT, 0.0))
		arm.add_child(model)
		PartVisuals.bind(model, bot.livery)
		_stand_mount_on_deck(model, "AxeMount")
		windup = AxeWindup.new()
		windup.name = "AxeWindup"
		windup.configure(model, Vector3(-ARM_LEN * 0.5, 0.0, 0.0))
		arm.add_child(windup)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(ARM_LEN, SHAFT_THICK, SHAFT_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	arm.add_child(mesh_instance)


## Fitment pass 2 (docs/wave-d-fitment2-notes.md, decisions 2026-09-30 §9: "axe and
## crusher rest above the front plate"). The tower, its pin and the spring return are
## their own node in axe.glb, `mount`: bolted to the deck, upright, under the hinge. Carried
## on the arm (as it was) the tower leaned 33 degrees with the cocked arm, through the
## front plate and the deck. Presentation only.
func _stand_mount_on_deck(model: Node3D, mount_name: String) -> void:
	var mount := model.get_node_or_null("mount") as Node3D
	if mount == null or bot.chassis == null:
		return
	model.remove_child(mount)
	mount.owner = null
	mount.name = mount_name
	mount.transform = Transform3D(Basis.IDENTITY, pivot - Vector3(0.0, PIVOT_LIFT, 0.0))
	bot.chassis.add_child(mount)
	PartVisuals.bind(mount, bot.livery)


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
## The EDGE. An axe held down is still one swing, and holding the button while the
## reset runs must not queue a second one.
func apply_input(_pressed: bool, fired: bool, _dt: float) -> void:
	if fired:
		_fire()


func _fire() -> void:
	if not ready():
		return
	_phase = 1
	_timer = STRIKE_S
	_struck = false
	_reaction = Vector3.ZERO
	_set_motor(-sweep() / STRIKE_S, STRIKE_IMPULSE)
	if windup != null and is_instance_valid(windup):
		windup.trigger()
	bot.emit_weapon_fired()


func physics_tick(dt: float) -> void:
	if _phase == 0:
		return
	if _phase == 1:
		if not _struck:
			_try_strike()
		if _reaction != Vector3.ZERO and bot.chassis != null:
			# Re-applied every tick: forces are cleared every step.
			var chassis: RigidBody3D = bot.chassis
			chassis.apply_central_force(_reaction)
		_timer -= dt
		if _timer <= 0.0:
			_phase = 2
			_reset_left = maxf(float(spec.get("reset_s", 1.4)), 0.05)
			_timer = _reset_left * RESET_LIMP_FRACTION
			_reaction = Vector3.ZERO
			# Dead weight: the motor is off and the arm hangs where it landed.
			if is_instance_valid(joint):
				joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return

	# Phase 2, the reset. The head is STILL DANGEROUS while it is falling: the
	# 0.15 s window is how long the motor drives for, not how long the arm takes
	# to arrive. Measured: a swing onto an opponent's lid reached it AFTER the
	# window closed (the motor cannot take a 9 kg arm to 11.5 rad/s inside one tick
	# and the victim slows it further), so a strike detected only inside the window
	# found nothing at all, three placements out of three. Detection runs through
	# the limp window as well, which is the arm still falling.
	# It cannot be gated on "the arm is still descending" either: an arm that has
	# landed ON somebody stops dead, which is exactly the tick the hit happens.
	if not _struck and _timer > 0.0:
		_try_strike()
	_reset_left -= dt
	_timer -= dt
	if _timer <= 0.0 and is_instance_valid(joint):
		if not joint.get_flag(HingeJoint3D.FLAG_ENABLE_MOTOR):
			joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
		var wind := maxf(_reset_left, 0.05)
		_set_motor(minf(sweep() / wind, _home_velocity()), HOLD_IMPULSE)
	if _reset_left <= 0.0:
		_phase = 0
		_set_motor(0.0, HOLD_IMPULSE)


## THE WIND-BACK SERVOS ONTO THE COCKED POSE (2026-09-27). It used to drive at
## sweep / time-left until the reset ran out, so the arm reached the top early and the
## motor (a velocity constraint Jolt makes as strong as it has to be, see flipper.gd)
## kept pushing it 1 to 3 degrees past the upper limit: two constraints fighting. The
## next swing then sat still for 3 ticks and let go all at once, a 5.4 m/s kick that
## vaulted the hero wedge 1.4 m onto its back on every second swing (weapons_test
## axe/wedge "removed nothing", the attacker never reached the target). Now the wind
## slows as the arm nears the rest angle and never drives past it; every swing starts
## the way the first one does.
func _home_velocity() -> float:
	if arm == null or arm.detached or bot.chassis == null or not arm.is_inside_tree():
		return 0.0
	# The direct state, not the node cache (a replay seek runs 16 steps a frame).
	var arm_state := PhysicsServer3D.body_get_direct_state(arm.get_rid())
	var hull_state := PhysicsServer3D.body_get_direct_state(bot.chassis.get_rid())
	if arm_state == null or hull_state == null:
		return 0.0
	var local := hull_state.transform.basis.inverse() * arm_state.transform.basis.x
	return maxf((rest_angle - atan2(local.y, local.x)) * HOME_GAIN, 0.0)


const HOME_GAIN := 12.0


func _set_motor(velocity: float, impulse: float) -> void:
	if not is_instance_valid(joint):
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, velocity)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, impulse)


# ---------------------------------------------------------------------------
# The blow
# ---------------------------------------------------------------------------
## One hit per swing, on the first tick the head has something in it.
func _try_strike() -> void:
	var part := _head_target()
	if part == null:
		return
	_struck = true
	var victim: Node = part.owner_bot
	var where := head.global_position
	var on_top := _is_top_face(part, victim, where)
	var amount := strike_amount(on_top)
	bot.opponent_damage_tick(part, amount, "impact")
	_last_strike = {"part": part.part_key, "amount": amount, "top": on_top,
		"tick": int(bot.call("sim_ticks")) if bot.has_method("sim_ticks") else Engine.get_physics_frames()}

	# The physical blow: down the way the head is travelling, into the victim's
	# chassis rather than into the plate it landed on (a 2 kg plate takes a 60 N s
	# blow to 30 m/s; the flipper hits the chassis for the same reason).
	var chassis: RigidBody3D = bot.chassis
	var body := part as RigidBody3D
	if victim != null and victim.has_method("flip_resistance"):
		var victim_chassis = victim.get("chassis")
		if victim_chassis != null:
			body = victim_chassis
	var forward := chassis.global_basis.x
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.RIGHT
	var direction := (Vector3.DOWN + forward * 0.35).normalized()
	var resist := 1.0
	if victim != null and victim.has_method("flip_resistance"):
		resist = maxf(float(victim.call("flip_resistance")), 0.1)
	var blow := _impulse * BLOW_SHARE * (1.0 if not on_top else _top_bonus) / resist
	body.apply_impulse(direction * blow, Vector3.ZERO)
	_reaction = -direction * (blow * REACTION_SHARE / STRIKE_S)


## Condition removed by one strike, before the victim's own material factor. The
## AI and the notes both want this number, so it is a function rather than three
## lines inside `_try_strike`.
func strike_amount(on_top: bool) -> float:
	return _impulse * DAMAGE_PER_IMPULSE * (_top_bonus if on_top else 1.0)


## Did the head land on a TOP face? A top plate answers for itself; a bare hull
## asks the victim's own `face_for_contact`, which is the same test the damage
## model uses for a contact, so an axe and a spinner agree about what "top" is.
func _is_top_face(part: BotPart, victim: Node, where: Vector3) -> bool:
	if part.part_key == "armour_top":
		return true
	if part.part_kind == "chassis" and victim != null \
			and victim.has_method("face_for_contact"):
		return str(victim.call("face_for_contact", where)) == "top"
	return false


## The nearest foreign body inside the head, picked by distance so the answer
## never depends on the order Jolt reports overlaps in.
func _head_target() -> BotPart:
	if head == null or arm == null or arm.detached or not head.is_inside_tree():
		return null
	var here := head.global_position
	var best: BotPart = null
	var best_distance := INF
	for body in head.get_overlapping_bodies():
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
## The last blow, or an empty dictionary if this axe has never connected.
func last_strike() -> Dictionary:
	return _last_strike.duplicate()


## The live arm angle from the forward horizontal, positive up. `rest_angle` when
## cocked, `strike_angle` at the end of a swing.
func arm_angle() -> float:
	if arm == null or arm.detached or bot.chassis == null or not arm.is_inside_tree():
		return rest_angle
	var chassis: RigidBody3D = bot.chassis
	var local: Vector3 = chassis.global_basis.inverse() * arm.global_basis.x
	return atan2(local.y, local.x)


## The sweep this hull has room for, in radians. Always positive.
func sweep() -> float:
	return rest_angle - strike_angle


func ready() -> bool:
	return not jammed and _phase == 0 and arm != null and not arm.detached


func readiness() -> float:
	if jammed or arm == null or arm.detached:
		return 0.0
	if _phase == 0:
		return 1.0
	if _phase == 1:
		return 0.0
	var total := maxf(float(spec.get("reset_s", 1.4)), 0.05)
	return clampf(1.0 - _reset_left / total, 0.0, 0.99)


func status_text() -> String:
	if jammed:
		return "JAMMED"
	if _phase == 1:
		return "SWING"
	if _phase == 2:
		return "RESET"
	return "READY"


func tip_height() -> float:
	if arm == null or arm.detached or not arm.is_inside_tree():
		return -1.0
	return maxf((arm.global_transform * Vector3(ARM_LEN * 0.5, 0.0, 0.0)).y, 0.0)


func set_jammed() -> void:
	jammed = true
	_phase = 0
	_reaction = Vector3.ZERO
	if is_instance_valid(joint):
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"reset": maxf(_reset_left, 0.0)}
