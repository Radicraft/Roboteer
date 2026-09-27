extends WeaponBase
## Full body spinner (docs/stage4-spec.md section 4, agent W1).
##
## The Shell's outer ring, taken over as a weapon. `chassis/shell.gd` already does
## its half of the handover (docs/stage4-assembly-notes.md section 8): the moment
## this script exists, `has_own_ring()` goes false, the hull shrinks its collision
## to the hub and hides the `ring` mesh inside `shell.glb`, and the ring becomes
## ONE body of ours on a vertical hinge at `socket_weapon_shell`, wearing
## `full_body_spinner.glb` (the toothed version, teeth at the catalogue reach of
## 0.45 m).
##
## Three things make it a different weapon from the bar, and all three are in the
## catalogue row: `spin_up_s` 3.5 (the slowest in the game), `control_penalty` 0.5,
## and no weak side.
##
## 1. THE BITE is the horizontal spinner's, without the self-destabilise: the ring
##    IS the bot, so there is no arm to throw a reaction through, and what the ring
##    keeps instead is the spin it spends. Read `horizontal_spinner.gd` for the
##    delivery mechanism; the ring records its strongest foreign contact inside the
##    step and spends it outside, as an impulse plus the condition that impulse is
##    worth through `bot.opponent_damage_tick(part, severity, "impact")`.
##
## 2. CONTROL. `Bot.apply_input` drives first and hands the weapon the button
##    second, so by the time `apply_input` runs here the drive module has already
##    written this tick's motor targets into the wheel hinges. We multiply them by
##    `lerp(1, control_penalty, spin)` in place, which scales the forward speed and
##    the turn together, without the weapon having to know anything about arcade
##    steering. At full spin a Shell drives at half pace and turns at half rate:
##    "terrible controllability", from the one number in the catalogue. When the
##    weapon is disrupted or jammed the Bot stops calling `apply_input` at all, so
##    `physics_tick` does the same scaling whenever no input arrived for two ticks,
##    and a coasting ring still costs you control.
##
## 3. NO WEAK SIDE, through the existing damage path and nothing else. Above
##    `SHIELD_SPIN` (30 percent) the armour panel bodies are taken out of the
##    collision world entirely: `collision_layer` AND `collision_mask` go to zero,
##    which is what it takes in Godot, where a pair collides if EITHER side's layer
##    is in the other's mask. A body nothing can touch never reaches
##    `BotPart._integrate_forces`, so it never reaches `Bot.report_contact`, so no
##    damage event can name `armour_front` or `armour_sides` while the ring is up.
##    The panels are welded to the hull with all six degrees of freedom locked, so
##    dropping them out of the world costs nothing else: they do not fall, they do
##    not need the floor, they are along for the ride. The hub is shielded the
##    ordinary way, by geometry: the ring's shape is a 0.45 m disc standing proud
##    of the 0.328 m hub all the way round, so an attacker reaches the ring first
##    and only a blow from directly above gets past it. Hits on the ring land on a
##    body registered as part_kind "weapon" with part_key "weapon", so they spend
##    the WEAPON's condition. That is the spec's "the ring is the armour" exactly:
##    grind the ring down and `Bot._handle_zero` jams the weapon, the ring coasts
##    to a stop, the spin drops under 30 percent, the panels come back into the
##    world and the shell is an ordinary bot with no armour worth speaking of.
##
## KNOWN LIMIT of point 3, and it is deliberate: a hit landing on the TOP of the
## hub still routes through `Bot.face_for_contact` to `armour_top`, which is the
## one face a full body spinner really does leave open. An axe bot is the answer to
## a shell, and that is the rock-paper-scissors the brief asks for.

## The ring's collision is a solid disc rather than a true annulus: the hub, the
## wheels and the panels all live inside it and are collision excluded from it
## anyway, so the twelve extra boxes an annulus would cost buy nothing.
const RING_TOP := 0.10
const RING_FRICTION := 0.30
## Rad/s at full spin. A 0.45 m ring at 6 rad/s is 2.7 m/s at the teeth. Measured
## and lowered from 9 for the same reason the saw and the drum came down: the ring
## is on the "weapon" BREAK row and an unstallable motor grinding it against another
## bot spends its own condition faster than the opponent's.
const MAX_OMEGA := 6.0
const MOTOR_IMPULSE := 1400.0
const COAST_S := 9.0
const BITE_SPIN_COST := 0.5
const BITE_COOLDOWN_S := 0.30
const MIN_BITE_SPIN := 0.08
## The ring does not throw a reaction into its own hull the way a bar does, but a
## bite still shoves the whole bot: it is the same body.
const RECOIL := 0.12
## Above this the faces are out of the world (see point 3 above).
const SHIELD_SPIN := 0.30

var ring: BotPart = null
var joint: HingeJoint3D = null
var pivot := Vector3.ZERO

var _spin := 0.0
var _pressed := false
var _bite_cooldown := 0.0
var _announced := false
var _shielded := false
var _ticks_since_input := 10
var _hit_body: RigidBody3D = null
var _hit_point := Vector3.ZERO


class SpinRing extends BotPart:
	var weapon: RefCounted = null

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		super(state)
		if weapon != null and not detached:
			weapon.call("_note_contacts", state)


func _build() -> void:
	pivot = socket_transform().origin
	var radius := maxf(float(spec.get("reach", 0.45)), 0.2)
	var bottom := -0.06
	if bot.chassis_module != null:
		bottom = float(bot.chassis_module.floor_y())
	var height := maxf(RING_TOP - bottom, 0.08)
	var centre := bottom + height * 0.5

	ring = SpinRing.new()
	ring.weapon = self
	ring.name = "SpinnerRing"
	ring.part_key = FightTypes.PART_WEAPON
	ring.part_kind = "weapon"
	ring.material_name = "steel"
	ring.physics_material_override = _material(RING_FRICTION)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = Vector3(0.0, centre - pivot.y, 0.0)
	ring.add_child(shape)
	_add_visual(radius, height)

	ring.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.register_part(ring, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointRing"
	# The hinge turns about the JOINT's local Z, so Z has to point up.
	joint.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(ring)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


## `socket_weapon_shell` is the hull origin and the model's `socket_pivot` is its
## own origin, so the toothed ring parents at identity and lands where the hull's
## own ring was.
func _add_visual(radius: float, height: float) -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "full_body_spinner")))
	if model != null:
		model.position = -pivot
		ring.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, -pivot.y + 0.02, 0.0)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	ring.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.1
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed
	_ticks_since_input = 0
	_scale_drive()


func physics_tick(dt: float) -> void:
	_bite_cooldown = maxf(_bite_cooldown - dt, 0.0)
	var alive := ring != null and is_instance_valid(ring) and not ring.detached
	var winding := _pressed and not jammed and alive \
		and not bool(bot.is_disrupted("weapon"))
	if winding:
		_spin = minf(_spin + dt / maxf(spin_up_s(), 0.01), 1.0)
	else:
		_spin = maxf(_spin - dt / COAST_S, 0.0)
	# A jammed or disrupted weapon never sees `apply_input`, and a ring that is
	# still turning still costs control, so catch up here.
	# Counted in this weapon's own ticks, not Engine.get_physics_frames(): a hit-stop hold
	# advances the engine's frame count with nothing simulated (combat feel wave).
	if _ticks_since_input >= 2:
		_scale_drive()
	_ticks_since_input += 1
	_drive_motor()
	_shield(_spin > SHIELD_SPIN)
	_spend_hit()
	if _spin >= 1.0 and not _announced:
		_announced = true
		bot.emit_weapon_fired()
	elif _spin < 0.5:
		_announced = false


func spin_up_s() -> float:
	return float(spec.get("spin_up_s", 3.5)) * float(bot.spin_up_factor())


func _drive_motor() -> void:
	if not is_instance_valid(joint):
		return
	if jammed:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
		return
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, MAX_OMEGA * _spin)


# ---------------------------------------------------------------------------
# Controllability
# ---------------------------------------------------------------------------
## 1.0 with the ring stopped, `control_penalty` with it at full spin.
func drive_scale() -> float:
	var penalty := clampf(float(spec.get("control_penalty", 0.5)), 0.05, 1.0)
	return lerpf(1.0, penalty, clampf(_spin, 0.0, 1.0))


## Scale the wheel motor targets the drive module has just written. Doing it here
## rather than inside the drive keeps the penalty where the weapon that causes it
## lives, and it scales the differential too, so the Shell loses its turn rate at
## the same rate as its speed.
func _scale_drive() -> void:
	var scale := drive_scale()
	if scale >= 0.999:
		return
	var drive: DriveBase = bot.drive_module
	if drive == null:
		return
	for hinge in drive.joints:
		if not is_instance_valid(hinge):
			continue
		var target := float(hinge.get_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY))
		if target != 0.0:
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, target * scale)


# ---------------------------------------------------------------------------
# No weak side
# ---------------------------------------------------------------------------
## Take the armour panels out of the collision world, or put them back. See the
## header: this is the whole of "the faces are unreachable while the ring spins",
## and it works by starving `Bot.report_contact`, not by special casing it.
func _shield(on: bool) -> void:
	if on == _shielded:
		return
	_shielded = on
	for part in bot.attached_parts():
		if part.part_kind != "armour":
			continue
		part.collision_layer = 0 if on else FightTypes.LAYER_BOT
		part.collision_mask = 0 if on else FightTypes.MASK_BOT


## True while the faces cannot be reached. The test and the overlay read it.
func shielded() -> bool:
	return _shielded


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
	if jammed or ring == null or not is_instance_valid(ring) or ring.detached:
		return
	if _spin < MIN_BITE_SPIN or _bite_cooldown > 0.0:
		return
	var dir := _tangential(_hit_point)
	if dir == Vector3.ZERO:
		return

	var spin := _spin
	var newtons := float(spec.get("impulse", 200.0)) * spin
	var resist := 1.0
	var other := victim.owner_bot
	if other != null:
		resist = maxf(float(other.call("flip_resistance")), 0.1)

	victim.apply_impulse(dir * (newtons / resist), _hit_point - victim.global_position)
	bot.opponent_damage_tick(victim, WeaponBase.spinner_bite(_severity_for(victim, newtons)), "impact")
	if bot.chassis != null:
		bot.chassis.apply_central_impulse(-dir * newtons * RECOIL)

	_bite_cooldown = BITE_COOLDOWN_S
	_spin = maxf(_spin - float(spec.get("bite_spin_cost", BITE_SPIN_COST)) * spin, 0.0)


func _tangential(point: Vector3) -> Vector3:
	var v := ring.linear_velocity + ring.angular_velocity.cross(point - ring.global_position)
	v.y = 0.0
	if v.length_squared() < 0.04:
		return Vector3.ZERO
	return v.normalized()


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


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or ring == null or not is_instance_valid(ring) or ring.detached:
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "SPIN %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	if ring == null or not is_instance_valid(ring) or ring.detached:
		return -1.0
	return maxf(ring.global_position.y, 0.0)


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_hit_body = null
	if is_instance_valid(joint):
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


## RESULT state. The ring stops, so the faces come back: nothing may be left in a
## state the next fight would inherit.
func freeze() -> void:
	set_jammed()
	_spin = 0.0
	_shield(false)


func state() -> Dictionary:
	return {"spin": snappedf(_spin, 0.001), "shielded": _shielded}
