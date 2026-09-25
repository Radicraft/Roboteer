extends DriveBase
## Omni: four wheels with lateral rollers. It STRAFES, which is the only drive
## whose motion is not "point the nose and go": the heading magnitude drives the
## bot in the heading direction without turning at all, and `secondary` pivots it
## on the spot. Weak (push_force 0.8) and slippery (traction 0.7) in exchange.
##
## The sideways motion is a force on the chassis rather than a fifth wheel: Jolt
## hinges have no anisotropic friction, so the lateral roll is modelled instead of
## simulated. Aimed at 0.25 s to reach the commanded sideways speed, capped so it
## can never out accelerate its own catalogue push force.

const STRAFE_REACH_S := 0.25
const STRAFE_MAX_G := 0.8
## The rollers: sliding a wheel along its own axle is what an omni wheel is FOR, but a
## Jolt cylinder has one isotropic friction, so a stopped omni wheel held the machine
## against its own strafe force (systems gauntlet D2: 0.00 m with the stick square to the
## nose). While a sideways component is commanded the wheels' friction drops toward this
## fraction of the catalogue grip, in proportion to how sideways the stick is, so a pure
## strafe slides on the rollers and a pure drive keeps full grip. Stepped so the material
## is only touched when the value really changes.
const ROLLER_FRICTION := 0.15
const ROLLER_STEP := 0.05

var _roller_level := 1.0


func slot_drive_id() -> String:
	return "4wd"


func model_id() -> String:
	return "wheel_omni"


func drive(heading: Vector2, secondary: bool, dt: float, turn: float = 0.0) -> void:
	_dt = dt
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	var scale := power_scale()
	var throttle := clampf(heading.length(), 0.0, 1.0)
	if absf(turn) > PIVOT_DEAD_ZONE and throttle <= PIVOT_HEADING_MAX:
		_set_rollers(1.0)
		pivot(turn, scale)
		return
	if scale <= 0.0 or throttle < 0.05:
		_set_rollers(1.0)
		set_targets(0.0, 0.0)
		return

	var want := Vector3(heading.x, 0.0, heading.y).normalized()
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT
	var side := chassis.global_basis.z
	side.y = 0.0
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.BACK

	var speed: float = throttle * top_speed() * float(bot.speed_factor()) * scale
	var v_fwd: float = want.dot(fwd) * speed
	var v_side: float = want.dot(side) * speed
	set_targets(v_fwd, v_fwd)
	_set_rollers(lerpf(1.0, ROLLER_FRICTION, absf(want.dot(side))))

	var here := chassis.linear_velocity
	# The whole machine is what has to move sideways, wheels included.
	var mass := chassis.mass
	for wheel in wheels:
		if not wheel.detached:
			mass += wheel.mass
	var force := clampf((v_side - here.dot(side)) / STRAFE_REACH_S,
		-STRAFE_MAX_G * 9.8, STRAFE_MAX_G * 9.8) * mass
	chassis.apply_central_force(side * force)
	# Heading hold while strafing: the side force acts at the centre of mass and the
	# rollers' drag below it, front and rear unequally on a wedge, which yawed the machine
	# 85 degrees in a 1.5 s strafe. A strafe keeps its nose (fully from 30 degrees sideways;
	# 22 degrees of drift left in 1.5 s). The stick pivot below still overrides it.
	var sideways := absf(want.dot(side))
	if sideways > 0.05 and not bot.is_inverted():
		chassis.angular_velocity = Vector3(chassis.angular_velocity.x,
			chassis.angular_velocity.y * clampf(1.0 - 2.0 * sideways, 0.0, 1.0), chassis.angular_velocity.z)

	# The stick pivot: hold secondary and the nose snaps to the stick at the catalogue
	# turn rate. Upright only, like every other handbrake in the game.
	if secondary and not bot.is_inverted():
		var yaw_now := atan2(-fwd.z, fwd.x)
		var yaw_want := atan2(-want.z, want.x)
		var err := wrapf(yaw_want - yaw_now, -PI, PI)
		var rate := clampf(err / maxf(_dt, 0.001), -turn_rate(), turn_rate())
		chassis.angular_velocity = Vector3(chassis.angular_velocity.x, rate,
			chassis.angular_velocity.z)


## Scales every wheel's friction to `level` of the catalogue grip (see ROLLER_FRICTION).
func _set_rollers(level: float) -> void:
	var stepped := clampf(snappedf(level, ROLLER_STEP), ROLLER_FRICTION, 1.0)
	if is_equal_approx(stepped, _roller_level):
		return
	_roller_level = stepped
	var friction := WHEEL_FRICTION * traction() * stepped
	for wheel in wheels:
		var material := wheel.physics_material_override
		if material != null:
			material.friction = friction


## Omni pivots instantly, on its rollers, rather than scrubbing four wheels round:
## the yaw rate is commanded directly and the wheels are left stopped.
func pivot(turn: float, scale: float) -> void:
	set_targets(0.0, 0.0)
	var chassis: RigidBody3D = bot.chassis
	if chassis == null or scale <= 0.0:
		return
	chassis.angular_velocity = Vector3(chassis.angular_velocity.x,
		clampf(turn, -1.0, 1.0) * turn_rate() * scale, chassis.angular_velocity.z)
