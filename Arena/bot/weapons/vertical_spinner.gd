extends WeaponBase
## Vertical spinner, the drum (docs/stage4-spec.md section 4, agent W1).
##
## A 0.24 m drum on a hinge whose axis runs along the bot's +Z (its right), at the
## front socket, turning so that its FRONT face climbs. It is the horizontal
## spinner's opposite number and shares its delivery mechanism (read
## `horizontal_spinner.gd` for the full description of how a bite is delivered);
## every number that makes it a different weapon is here:
##
##   - reach 0.25 against the bar's 0.55, so it has to be driven right into the
##     opponent, and `spin_up_s` 1.8 against 2.5, so it gets there sooner;
##   - `launch` 0.7: most of the bite goes UP rather than sideways, which is what
##     puts an opponent on its back instead of across the arena;
##   - the reaction on the wielder is a fraction of the bar's and it points DOWN
##     and back, so a drum plants itself while it works. That is the catalogue's
##     "safer" in one line of code;
##   - a bite costs less spin (0.35 against 0.62) and the cooldown is shorter, so
##     the drum grinds where the bar bites once and has to run away.
##
## THE DRUM'S HEIGHT IS NOT THE SOCKET'S. A 0.12 m radius drum hung on a wedge's
## front socket at y = -0.03 would be 0.14 m underground. The pivot is lifted to
## put the drum's underside `GROUND_CLEAR` above the floor, which is where a real
## drum runs and what makes its front lip get under things.

const DRUM_RADIUS := 0.118
const DRUM_WIDTH := 0.40
const DRUM_FRICTION := 0.4
## Full-spin angular velocity, rad/s. A drum is small, so the same 0.11 m per step
## tunnelling ceiling as the bar allows it more rad/s (see horizontal_spinner.gd).
## MEASURED and lowered from 26: an unstallable motor plus a fast drum held against
## a plate resolves as a huge contact impulse every step and the drum ground its own
## condition to zero in ten seconds. The bite's energy is the impulse model, not the
## surface speed, so this costs the weapon nothing.
const MAX_OMEGA := 16.0
const MOTOR_IMPULSE := 700.0
const COAST_S := 4.0
const BITE_SPIN_COST := 0.35
const BITE_COOLDOWN_S := 0.18
const MIN_BITE_SPIN := 0.08
## The drum's own reaction. `self_destabilise` is not in the catalogue row for this
## weapon on purpose: it is the safe one, so the number lives here.
const SELF_DESTABILISE := 0.12
const REACTION_LINEAR := 0.30
const REACTION_TORQUE := 0.18
const GROUND_CLEAR := 0.010
## How far the drum's leading edge must stand proud of the hull's front armour.
## THE TRAP, measured: a wedge's `socket_weapon_front` is the FLIPPER's pinned
## pivot at x = 0.1115 (docs/stage4-assembly-notes.md section 3), 0.36 m behind the
## nose, because a flipper arm reaches forward from it. Hang a 0.118 m drum there
## and it sits entirely inside the hull: the bot's own front plate touches first
## and the drum never contacts anything at all. A rotating HEAD has to be carried
## out to the nose; only an ARM hinges at the arm socket.
const NOSE_PROUD := 0.030

var drum: BotPart = null
var joint: HingeJoint3D = null
var pivot := Vector3.ZERO

var _spin := 0.0
var _pressed := false
var _bite_cooldown := 0.0
var _announced := false
var _hit_body: RigidBody3D = null
var _hit_point := Vector3.ZERO


## Reads its own contact list inside the step so the weapon can add the drum's
## energy to a blow the solver has already resolved. Read only.
class SpinDrum extends BotPart:
	var weapon: RefCounted = null

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		super(state)
		if weapon != null and not detached:
			weapon.call("_note_contacts", state)


func _build() -> void:
	pivot = socket_transform().origin
	pivot.y = maxf(pivot.y, -float(bot.ride_height()) + GROUND_CLEAR + DRUM_RADIUS)
	pivot.x = maxf(pivot.x, _nose() + NOSE_PROUD - DRUM_RADIUS)

	drum = SpinDrum.new()
	drum.weapon = self
	drum.name = "SpinnerDrum"
	drum.part_key = FightTypes.PART_WEAPON
	drum.part_kind = "weapon"
	drum.material_name = "steel"
	drum.physics_material_override = _material(DRUM_FRICTION)
	drum.continuous_cd = true

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = DRUM_RADIUS
	cylinder.height = DRUM_WIDTH
	shape.shape = cylinder
	# A CylinderShape3D stands on Y; the drum's axis is the bot's Z.
	shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	drum.add_child(shape)
	_add_visual()

	drum.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.register_part(drum, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointDrum"
	# The hinge turns about the JOINT's local Z, which is already the bot's right,
	# so the joint sits at identity.
	joint.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(drum)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


## `socket_pivot` on the model is its own origin, so it parents at identity.
func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "vertical_spinner")))
	if model != null:
		drum.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = DRUM_RADIUS
	mesh.bottom_radius = DRUM_RADIUS
	mesh.height = DRUM_WIDTH
	mesh.radial_segments = 16
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	drum.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.05
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	_bite_cooldown = maxf(_bite_cooldown - dt, 0.0)
	var alive := drum != null and is_instance_valid(drum) and not drum.detached
	var winding := _pressed and not jammed and alive \
		and not bool(bot.is_disrupted("weapon"))
	if winding:
		_spin = minf(_spin + dt / maxf(spin_up_s(), 0.01), 1.0)
	else:
		_spin = maxf(_spin - dt / COAST_S, 0.0)
	_drive_motor()
	_spend_hit()
	if _spin >= 1.0 and not _announced:
		_announced = true
		bot.emit_weapon_fired()
	elif _spin < 0.5:
		_announced = false


func spin_up_s() -> float:
	return float(spec.get("spin_up_s", 1.8)) * float(bot.spin_up_factor())


## THE SIGN. A point at +X from the axis has velocity omega_z * (Z cross X) =
## omega_z * Y, so a POSITIVE target about the joint's +Z lifts the front face,
## which is the direction that throws an opponent up rather than swallowing it.
func _drive_motor() -> void:
	if not is_instance_valid(joint):
		return
	if jammed:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, MAX_OMEGA * _spin)


# ---------------------------------------------------------------------------
# The bite
# ---------------------------------------------------------------------------
func _note_contacts(state: PhysicsDirectBodyState3D) -> void:
	if jammed or _spin < MIN_BITE_SPIN or _bite_cooldown > 0.0 or _hit_body != null:
		return
	var count := state.get_contact_count()
	if count == 0:
		return
	var ids: Array[int] = []
	var objects: Array = []
	var sums: Array[float] = []
	var spots: Array[Vector3] = []
	for i in range(count):
		var part := state.get_contact_collider_object(i) as BotPart
		if part == null or part.detached or part.owner_bot == null \
				or part.owner_bot == bot:
			continue
		var id := part.get_instance_id()
		var slot := ids.find(id)
		if slot < 0:
			ids.append(id)
			objects.append(part)
			sums.append(0.0)
			spots.append(Vector3.ZERO)
			slot = ids.size() - 1
		sums[slot] += state.get_contact_impulse(i).length()
		spots[slot] = state.get_contact_local_position(i)
	var best := -1
	for slot in range(ids.size()):
		if best < 0 or sums[slot] > sums[best] + 0.0001 \
				or (absf(sums[slot] - sums[best]) <= 0.0001 and ids[slot] < ids[best]):
			best = slot
	if best < 0:
		return
	_hit_body = objects[best]
	_hit_point = spots[best]


func _spend_hit() -> void:
	var victim := _hit_body as BotPart
	_hit_body = null
	if victim == null or not is_instance_valid(victim) or victim.detached:
		return
	if jammed or drum == null or not is_instance_valid(drum) or drum.detached:
		return
	if _spin < MIN_BITE_SPIN or _bite_cooldown > 0.0:
		return
	var dir := _bite_direction(_hit_point)
	if dir == Vector3.ZERO:
		return

	var spin := _spin
	var newtons := float(spec.get("impulse", 150.0)) * spin
	var resist := 1.0
	var tip := 1.0
	var other := victim.owner_bot
	if other != null:
		resist = maxf(float(other.call("flip_resistance")), 0.1)
		tip = maxf(float(other.call("tip_resistance")), 0.1)

	victim.apply_impulse(dir * (newtons / resist), _hit_point - victim.global_position)
	# The drum tumbles what it throws, about the axis it spins on, which is why a
	# drum lands opponents on their backs.
	var axis := drum.global_basis.z
	victim.apply_torque_impulse(axis * (newtons * 0.06 / tip))
	bot.opponent_damage_tick(victim, _severity_for(victim, newtons), "impact")
	_react(dir, newtons)

	_bite_cooldown = BITE_COOLDOWN_S
	_spin = maxf(_spin - BITE_SPIN_COST * spin, 0.0)


## `launch` of the bite goes straight up and the rest follows the drum surface.
func _bite_direction(point: Vector3) -> Vector3:
	var v := drum.linear_velocity + drum.angular_velocity.cross(point - drum.global_position)
	if v.length_squared() < 0.04:
		return Vector3.ZERO
	var launch := clampf(float(spec.get("launch", 0.7)), 0.0, 1.0)
	var dir := v.normalized() * (1.0 - launch) + Vector3.UP * launch
	if dir.length_squared() < 1e-6:
		return Vector3.UP
	return dir.normalized()


func _severity_for(victim: BotPart, newtons: float) -> float:
	var kind := victim.part_kind
	var key := victim.part_key
	if kind == "chassis":
		kind = "armour"
		key = "armour_top"
	var scale := 1.0
	var other := victim.owner_bot
	if other != null and other.get("damage") != null:
		var damage: BotDamage = other.get("damage")
		scale = float(damage.threshold_scale.get(key, 1.0))
	var break_min := float(FightTypes.BREAK_MIN.get(kind, 40.0)) * scale
	var break_max := float(FightTypes.BREAK_MAX.get(kind, 200.0)) * scale
	if newtons <= break_min:
		return 0.0
	return clampf((newtons - break_min) / maxf(break_max - break_min, 0.001), 0.0, 1.0)


## Down and back, and small. A drum pushes itself into the floor when it bites,
## which is the opposite of what the bar does to its wielder.
func _react(dir: Vector3, newtons: float) -> void:
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	var back := -dir * newtons * SELF_DESTABILISE
	back.y = -absf(back.y)
	var arm := _hit_point - chassis.global_position
	chassis.apply_central_impulse(back * REACTION_LINEAR)
	chassis.apply_torque_impulse(arm.cross(back) * REACTION_TORQUE
		/ maxf(float(bot.tip_resistance()), 0.1))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or drum == null or not is_instance_valid(drum) or drum.detached:
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "SPIN %d%%" % int(round(readiness() * 100.0))


## The drum works at its lowest point, which is the number the HUD wants.
func tip_height() -> float:
	if drum == null or not is_instance_valid(drum) or drum.detached:
		return -1.0
	return maxf(drum.global_position.y - DRUM_RADIUS, 0.0)


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_hit_body = null
	if is_instance_valid(joint):
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()
	_spin = 0.0


func state() -> Dictionary:
	return {"spin": snappedf(_spin, 0.001)}
