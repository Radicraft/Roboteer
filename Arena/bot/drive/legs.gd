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

var _feet: Array[Vector3] = []


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
