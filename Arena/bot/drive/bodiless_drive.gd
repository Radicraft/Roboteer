class_name BodilessDrive extends DriveBase
## The half of a drive that has no wheels: the hydraulic legs and the hover
## thrusters (brief v5 section 9.5, docs/wave-p-d2-notes.md).
##
## Every Stage 4 drive is wheel bodies on hinge motors, and the arcade steering in
## `drive_base.gd` turns a heading into per side wheel speeds. Neither of these two
## has a wheel to turn, so the motion is worked out here instead and applied to the
## hull as forces: a yaw rate the machine holds, a thrust along its nose, a lateral
## grip term and whatever holds it up (legs catch the fall on their hydraulics, the
## hover rides its cushion). Nothing here uses the rng or the clock, and every
## number comes from the drive's catalogue row.
##
## Damage. A wheeled drive loses condition through its wheels and bleeds the drive
## motors with them (`BotDamage.DRIVE_BLEED`). These two have no wheel to lose, so
## the whole of their mobility is `condition["drive"]` and the Bot bleeds it on
## every hull hit at the catalogue's `hull_bleed`. That is why the machine reports
## no wheel rows at all and why the match report prints one line for the drive:
## there is nothing else on it to lose.
##
## Weight. A drive with no bodies would weigh nothing in the simulation and the
## assembly test's mass check would catch it, so the catalogue weight goes on the
## hull (`Bot.add_hull_mass`), exactly as a utility part's does.

## How fast the machine settles onto a commanded yaw rate. Low enough that a blow
## still spins it, high enough that it answers the stick.
const YAW_RESPONSE_S := 0.07
## How fast thrust closes on the commanded road speed. Stiff on purpose: this is a
## velocity controller, and a soft one settles wherever the machine's own friction
## balances it rather than at the catalogue top speed (measured 2026-09-21: a
## walker rated at 2.0 m/s holding 1.12).
const THRUST_REACH_S := 0.06
## How fast the lateral grip term kills a sideways slide. Its authority is the
## catalogue `traction`, so a walker plants and a hover drifts.
const SIDE_REACH_S := 0.25
## Braking with the stick at rest.
const BRAKE_REACH_S := 0.35
## Below this much "up" the machine is on its side or its back and the drive stops
## answering: a walker cannot step and a hover cannot blow downward.
const UPRIGHT_MIN := 0.15


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func wheel_count() -> int:
	return 0


func bodiless() -> bool:
	return true


func build() -> void:
	condition_keys.clear()
	bot.add_hull_mass(float(spec.get("weight", 20.0)))
	build_stance()


## The feet, the skirt: collision and visuals that ride on the hull rather than
## being bodies of their own (the brief's body budget, section 12).
func build_stance() -> void:
	pass


# ---------------------------------------------------------------------------
# Catalogue readings
# ---------------------------------------------------------------------------
## Metres per second squared the drive can put into the hull.
func thrust_accel() -> float:
	return float(spec.get("thrust_g", 1.0)) * 9.8


## What is left of the thrust while the machine is leaning on another machine.
## This is the whole of "no pushing power": a hover's fans blow past an opponent
## instead of driving through it, a walker's feet are planted and push in full.
func contact_grip() -> float:
	return float(spec.get("contact_grip", 1.0))


## Sideways grip in g. The catalogue `traction`, used the way a tyre uses it.
func side_grip() -> float:
	return traction()


## Mobility is the drive condition and nothing else: there are no wheels to count.
func power_scale() -> float:
	if bot == null or bot.damage == null:
		return 1.0
	return clampf(float(bot.damage.condition["drive"]), 0.0, 1.0)


func alive_count() -> int:
	return 1


func alive_fraction() -> float:
	return 1.0


# ---------------------------------------------------------------------------
# Driving
# ---------------------------------------------------------------------------
func drive(heading: Vector2, _secondary: bool, dt: float, turn: float = 0.0) -> void:
	_dt = dt
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	support(chassis, dt)
	var scale := power_scale()
	if scale <= 0.0 or upright_amount(chassis) <= UPRIGHT_MIN:
		return

	var throttle := clampf(heading.length(), 0.0, 1.0)
	if absf(turn) > PIVOT_DEAD_ZONE and throttle <= PIVOT_HEADING_MAX:
		pivot(turn, scale)
		return
	if throttle < 0.05:
		coast(chassis)
		return

	var fwd := flat_forward(chassis)
	var want := Vector3(heading.x, 0.0, heading.y).normalized()
	var err := wrapf(atan2(-want.z, want.x) - atan2(-fwd.z, fwd.x), -PI, PI)
	var reverse := absf(err) > REVERSE_ANGLE
	if reverse:
		err = wrapf(err - PI, -PI, PI)

	var rate := turn_rate() * scale
	set_yaw_rate(chassis, clampf(err / maxf(dt * 4.0, 0.001), -rate, rate), dt)

	# Forward effort fades as the yaw error grows, the same rule the wheeled drives
	# use, so a bodiless machine still turns first and drives second.
	var align := clampf(1.0 - absf(err) / (PI * 0.5), 0.0, 1.0)
	var target: float = throttle * top_speed() * float(bot.speed_factor()) * scale * align
	if reverse:
		target = -target
	push_along(chassis, fwd, target)


## Spin on the spot: the commanded yaw rate and no road speed.
func pivot(turn: float, scale: float) -> void:
	var chassis: RigidBody3D = bot.chassis
	if chassis == null or scale <= 0.0:
		return
	set_yaw_rate(chassis, clampf(turn, -1.0, 1.0) * turn_rate() * scale, _dt)
	coast(chassis)


## Whatever holds the machine up. Called every tick the drive is answering, and
## NOT from `stop()`: a drive that has been cut stops holding the machine up,
## which is what makes a disrupted hover drop out of the air.
func support(_chassis: RigidBody3D, _dt: float) -> void:
	pass


## Hold the machine level. The walker does it on its hydraulics while its feet are
## within reach of the floor, the hover does it on its cushion while it is airborne
## and upright: both are self levelling in the way the real machine would be, and
## neither has any authority once it is past about sixty degrees, which is what
## keeps a hover's "flips easily" honest.
##
## It is a tidy up, not the fix for a bias: a constant tilt means a force is being
## applied somewhere other than the machine's centre of mass, and `apply_at_com`
## is what stops that happening. What this catches is the wobble left by a
## landing, a shove or a blow.
const LEVEL_RESPONSE_S := 0.25
const LEVEL_RATE := 4.0
const LEVEL_GATE := 0.5


func level_body(chassis: RigidBody3D, dt: float, authority: float) -> void:
	if authority <= 0.0:
		return
	var up := clampf(upright_amount(chassis), 0.0, 1.0)
	var gate := clampf((up - LEVEL_GATE) / maxf(1.0 - LEVEL_GATE, 0.001), 0.0, 1.0)
	if gate <= 0.0:
		return
	# The axis that turns the hull's own up onto the world's, with a length of
	# sin(tilt), so a level machine asks for nothing.
	var axis := chassis.global_basis.y.cross(Vector3.UP)
	var want := axis * LEVEL_RATE
	var blend := clampf(dt / LEVEL_RESPONSE_S, 0.0, 1.0) * gate * clampf(authority, 0.0, 1.0)
	var av := chassis.angular_velocity
	chassis.angular_velocity = Vector3(
		lerpf(av.x, want.x, blend), av.y, lerpf(av.z, want.z, blend))


func set_yaw_rate(chassis: RigidBody3D, want: float, dt: float) -> void:
	var av := chassis.angular_velocity
	var blend := clampf(dt / YAW_RESPONSE_S, 0.0, 1.0)
	chassis.angular_velocity = Vector3(av.x, lerpf(av.y, want, blend), av.z)


func push_along(chassis: RigidBody3D, fwd: Vector3, target_speed: float) -> void:
	var grip := contact_grip() if touching_machine(chassis) else 1.0
	var along := chassis.linear_velocity.dot(fwd)
	var accel := clampf((target_speed - along) / THRUST_REACH_S,
		-thrust_accel(), thrust_accel()) * grip
	apply_at_com(chassis, fwd * accel * machine_mass())
	hold_line(chassis, fwd)


## The lateral grip term: what a tyre does and a fan does not.
func hold_line(chassis: RigidBody3D, fwd: Vector3) -> void:
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var slip := chassis.linear_velocity.dot(side)
	if absf(slip) < 0.001:
		return
	var accel := clampf(-slip / SIDE_REACH_S, -side_grip() * 9.8, side_grip() * 9.8)
	apply_at_com(chassis, side * accel * machine_mass())


## Stick at rest. A walker plants itself, a hover keeps sliding.
func coast(chassis: RigidBody3D) -> void:
	var flat := Vector3(chassis.linear_velocity.x, 0.0, chassis.linear_velocity.z)
	var speed := flat.length()
	if speed < 0.01:
		return
	var accel := minf(speed / BRAKE_REACH_S, side_grip() * 9.8)
	apply_at_com(chassis, -flat / speed * accel * machine_mass())


# ---------------------------------------------------------------------------
# Readings
# ---------------------------------------------------------------------------
## THE MASS THAT HAS TO BE MOVED, and why it is not `chassis.mass`. The hull is one
## body of several: the plates and the weapon are their own bodies, jointed to it,
## and together they are about as heavy again. A force worked out against the hull's
## own kilograms moves half a machine. Measured 2026-09-21: a hover lifting
## `chassis.mass` sagged to 0.139 m under a cushion asked to hold 0.20.
func machine_mass() -> float:
	return maxf(float(bot.total_mass()), 0.1)


## WHERE THE FORCE GOES, and why it is not the hull's own centre of mass. The
## plates and the weapon are welded bodies, so hull plus plates behaves as one
## rigid assembly whose centre of mass sits forward of the hull's: gravity pulls
## at the assembly's centre and a force applied at the hull's makes a couple.
## Measured 2026-09-21: a hover holding a steady 18 degrees nose down, for ever,
## with no wheels to stand on. Lift and thrust are applied here instead.
func machine_com() -> Vector3:
	var total := 0.0
	var sum := Vector3.ZERO
	for part in bot.attached_parts():
		var at: Vector3 = part.global_position
		if part == bot.chassis:
			at = part.global_transform * part.center_of_mass
		sum += at * part.mass
		total += part.mass
	if total <= 0.0:
		return bot.chassis.global_position
	return sum / total


## Apply a force to the machine as a whole: at the assembly's centre of mass, so
## it moves the machine without turning it.
func apply_at_com(chassis: RigidBody3D, force: Vector3) -> void:
	chassis.apply_force(force, machine_com() - chassis.global_position)


func flat_forward(chassis: RigidBody3D) -> Vector3:
	var fwd := chassis.global_basis.x
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT


func upright_amount(chassis: RigidBody3D) -> float:
	return chassis.global_basis.y.dot(Vector3.UP)


## Is this machine leaning on another one? Read off EVERY body it still has, not
## just the hull: a machine drives into an opponent nose first and the nose is the
## weapon, so watching the hull alone would report no contact at all and a hover
## would push like anything else (measured 2026-09-21: it shifted a parked machine
## 3.16 m, further than a 6 wheel). `Bot.register_part` turns contact monitoring on
## for every body, so this costs a list walk and nothing else.
func touching_machine(_chassis: RigidBody3D) -> bool:
	for own in bot.attached_parts():
		for body in own.get_colliding_bodies():
			var part := body as BotPart
			if part == null or part.detached:
				continue
			if part.owner_bot != null and part.owner_bot != bot:
				return true
	return false
