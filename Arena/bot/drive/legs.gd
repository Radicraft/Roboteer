extends BodilessDrive
## Hydraulic legs (brief v5 section 9.5, Level 30): a four leg walker. Slow,
## immense push, and it steps over a floor hazard instead of driving through it.
##
## WHY IT IS NOT FOUR WHEELS. A leg does not roll, so there is no hinge motor and
## no wheel speed to command: the feet are four collision shapes on the hull (the
## same way the skirts and the rear wedge ride on it, and for the same reason,
## brief section 12's body budget) and the walk is thrust along the nose with the
## catalogue's traction as lateral grip. What a player feels is a machine that is
## slow, turns slowly, cannot be shoved off a line, and pushes harder than
## anything else in the catalogue.
##
## THE LANDING. A machine that meets the floor on four rigid feet bolted to the
## hull would credit the whole landing impulse to an armour face: measured off the
## spawn mark, 51 N s against an armour break threshold of 24, which is a plate
## damaged for nothing every time the machine is set down. Real legs have
## hydraulics, so these do: `support()` opposes downward velocity over the last
## `leg_travel` of the drop and the feet touch down at walking pace. It only ever
## opposes a fall, never lifts, so a walker cannot hop and cannot fly.
##
## MESHES (agent E, wave P). `legs.glb` is ONE hydraulic leg, authored hanging
## from the hull underside at its own origin and reaching the floor at
## LEG_MODEL_HEIGHT below it. Four are fitted, one per `wheel_slots("4wd")`
## point, each scaled in Y to the drop this hull actually has, and each given a
## `PartAnim` in STRIDE with the phase of a trot. The plain struts are kept as
## the fallback for a build with no art, exactly as every other part does it.

## How hard the hydraulics can catch a fall, and how quickly.
const CATCH_S := 0.05
const CATCH_MAX_G := 5.0
## The collision foot, and the strut drawn when E's model is missing.
const FOOT_LENGTH := 0.16
const FOOT_WIDTH := 0.12
const FOOT_MIN_HEIGHT := 0.03
const FOOT_FRICTION := 0.25
## The height `legs.glb` is authored at, hip to sole. The model is scaled in Y
## to the hull's real drop, which is 0.05 to 0.09 m; only the shin and the ram
## stretch enough to see, and the alternative (a leg authored per hull) is six
## models of the same part.
const LEG_MODEL_HEIGHT := 0.090
## A trot: the diagonal pairs move together. `wheel_slots("4wd")` comes back in
## catalogue order, which is front right, front left, rear right, rear left, so
## front right and rear left share a phase and the other two share the opposite.
const STRIDE_PHASE: Array[float] = [0.0, 0.5, 0.5, 0.0]

## A walker turns by stepping: the feet that are swinging are off the floor, so while
## it is asked to yaw the planted feet's scrub is this instead of FOOT_FRICTION. Without
## it the four feet's friction held a commanded 92 deg/s pivot to 15 to 33 deg/s (systems
## gauntlet D3).
const FOOT_TURN_FRICTION := 0.005
## Yaw rates below this are "going straight" and keep the full bite.
const TURNING_RAD_S := 0.2
const LEG_YAW_RESPONSE_S := 0.02
## Stepping up. A foot is a box from the hull to the floor, so a 4 cm lip was a wall
## (systems gauntlet D3: stuck dead, though the blurb says it steps over things). When
## the walker has been asked to walk and has been held back for STEP_BLOCKED_S, not by
## another machine, the hydraulics lift the body until the feet clear STEP_HEIGHT, and
## the thrust carries them over; `support()` sets it down on the far side.
const STEP_BLOCKED_S := 0.15
const STEP_HEIGHT := 0.06
const STEP_LIFT_G := 0.6
const STEP_STALL := 0.3
var _blocked_s := 0.0

var _feet: Array[Vector3] = []
var _foot_material: PhysicsMaterial = null


func setup(owner: Node, chassis_module: ChassisBase, drive_spec: Dictionary,
		drive_id: String) -> void:
	super.setup(owner, chassis_module, drive_spec, drive_id)
	# The stance is the ride height: a walker stands taller than it rolls.
	radius = maxf(float(spec.get("stance_height", 0.14)), hull.wheel_radius_min())


func leg_travel() -> float:
	return maxf(float(spec.get("leg_travel", 0.08)), 0.01)


func build_stance() -> void:
	super.build_stance()
	_feet.clear()
	var top := hull.floor_y()
	var bottom := -radius + 0.004
	var height := maxf(top - bottom, FOOT_MIN_HEIGHT)
	var centre_y := bottom + height * 0.5
	for slot in hull.wheel_slots("4wd"):
		var at := Vector3(slot.x, centre_y, slot.z)
		_feet.append(at)
		var shape := BoxShape3D.new()
		shape.size = Vector3(FOOT_LENGTH, height, FOOT_WIDTH)
		hull.add_shape(shape, Transform3D(Basis.IDENTITY, at))
		_add_leg(Vector3(slot.x, top, slot.z), height, _feet.size() - 1)
	# Friction on the feet, and why it is not the catalogue traction. The lateral
	# grip and the braking are already modelled as forces in `BodilessDrive`, so
	# physical friction here is a second helping of the same thing, and it is
	# subtracted from the thrust rather than added to it: measured 2026-09-21, a
	# coefficient of 1.1 against a thrust of 1.3 g left the walker covering 0.73 m
	# in a second and unable to turn at all. What the feet need is enough bite not
	# to be shoved about when the drive is not answering.
	var material := PhysicsMaterial.new()
	material.friction = FOOT_FRICTION
	material.bounce = 0.0
	bot.chassis.physics_material_override = material
	_foot_material = material


func drive(heading: Vector2, secondary: bool, dt: float, turn: float = 0.0) -> void:
	_set_foot_friction(FOOT_FRICTION)
	super.drive(heading, secondary, dt, turn)


func set_yaw_rate(chassis: RigidBody3D, want: float, dt: float) -> void:
	if absf(want) > TURNING_RAD_S:
		_set_foot_friction(FOOT_TURN_FRICTION)
	# Stiffer than the hover's: a planted walker holds the rate it steps at, where the
	# shared 0.07 s blend settled 20 % under it against the welded plates' drag.
	var av := chassis.angular_velocity
	var blend := clampf(dt / LEG_YAW_RESPONSE_S, 0.0, 1.0)
	chassis.angular_velocity = Vector3(av.x, lerpf(av.y, want, blend), av.z)


func push_along(chassis: RigidBody3D, fwd: Vector3, target_speed: float) -> void:
	super.push_along(chassis, fwd, target_speed)
	var along := chassis.linear_velocity.dot(fwd) * signf(target_speed)
	var stalled := absf(target_speed) > 0.3 and along < absf(target_speed) * STEP_STALL
	if not stalled or touching_machine(chassis):
		_blocked_s = 0.0
		return
	_blocked_s += _dt
	if _blocked_s < STEP_BLOCKED_S:
		return
	if chassis.global_position.y < radius + STEP_HEIGHT and chassis.linear_velocity.y < 0.4:
		apply_at_com(chassis, Vector3.UP * (1.0 + STEP_LIFT_G) * 9.8 * machine_mass())


func _set_foot_friction(value: float) -> void:
	if _foot_material != null and not is_equal_approx(_foot_material.friction, value):
		_foot_material.friction = value


## One leg. Not a body: a visual on the hull, like the skirts and the rear wedge,
## because the foot's collision is the box added above and this only has to look
## like the thing that box is.
##
## `hip` is the hull underside at this wheel slot, which is where the model's own
## origin belongs; the model then reaches `height` down to the floor.
func _add_leg(hip: Vector3, height: float, index: int) -> void:
	var model := PartVisuals.instantiate("legs")
	if model == null:
		_add_strut(hip - Vector3(0.0, height * 0.5, 0.0), height, index)
		return
	model.name = "Leg%d" % index
	model.position = hip
	model.scale = Vector3(1.0, maxf(height / LEG_MODEL_HEIGHT, 0.3), 1.0)
	bot.chassis.add_child(model)
	PartVisuals.bind(model, bot.livery)
	var anim := PartAnim.new()
	anim.name = "Stride"
	anim.configure(model, PartAnim.Mode.STRIDE,
		STRIDE_PHASE[index % STRIDE_PHASE.size()])
	model.add_child(anim)


## The no-art fallback: a plain strut, which is what this drive wore before the
## model landed.
func _add_strut(at: Vector3, height: float, index: int) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Leg%d" % index
	mesh.mesh = BotMeshes.flat_box_mesh(
		Vector3(FOOT_LENGTH, height, FOOT_WIDTH))
	mesh.position = at
	mesh.material_override = PartVisuals.slot_material("dark_metal", bot.livery)
	bot.chassis.add_child(mesh)


## The hydraulics. Opposes a fall over the last `leg_travel` of it and does
## nothing else, so the machine settles on its feet rather than dropping on them.
func support(chassis: RigidBody3D, dt: float) -> void:
	var up := upright_amount(chassis)
	if up <= UPRIGHT_MIN:
		return
	var falling := -chassis.linear_velocity.y
	if falling <= 0.0:
		return
	var travel := leg_travel()
	var slack := radius + travel - chassis.global_position.y
	if slack <= 0.0:
		return
	# Full authority by half travel: a ramp that only reaches full strength as the
	# feet touch down has already let the machine land on them.
	var into := clampf(slack / travel * 2.0, 0.0, 1.0)
	var accel := clampf(falling / CATCH_S, 0.0, CATCH_MAX_G * 9.8) \
		* into * clampf(up, 0.0, 1.0)
	apply_at_com(chassis, Vector3.UP * accel * machine_mass())
	# The hydraulics level the body as they take the weight, which is also what
	# stops a machine landing tail first and taking its own rear plate off.
	level_body(chassis, dt, into)


## The feet are on the hull, so "wheels down" is the hull at stance height. The
## audio layer and the test overlay read this.
func wheel_contacts() -> Array[bool]:
	var out: Array[bool] = []
	var down: bool = bot.chassis != null \
		and bot.chassis.global_position.y <= radius + 0.04
	for _i in range(maxi(_feet.size(), 1)):
		out.append(down)
	return out
