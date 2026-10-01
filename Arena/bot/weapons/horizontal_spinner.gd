extends WeaponBase
## Horizontal spinner (docs/stage4-spec.md section 4, agent W1).
##
## A 1.10 m bar (0.55 m each side, which is the catalogue `reach` at the hardened
## tip) on a VERTICAL hinge at the front socket, motorised. Holding the button
## spins it up over `spin_up_s`; the stored energy is the spin fraction, and a
## contact spends most of it in one bite. Above 60 percent spin the bite throws a
## reaction back into the wielder's own chassis (`self_destabilise`), which is the
## whole character of the weapon: it is the biggest hit in the catalogue and it
## wrecks your own driving line every time it lands.
##
## HOW A HIT IS DELIVERED (the same shape for both spinners; the drum differs only
## in its numbers and its launch vector):
##
##   1. the bar is a real RigidBody3D registered as part_kind "weapon", so its own
##      ordinary contacts already go through `BotPart._integrate_forces` ->
##      `Bot.report_contact` in BOTH directions: the victim takes the mechanical
##      impulse on the face it was struck on, and the bar takes its share, which
##      is how a bar bends and eventually jams;
##   2. on top of that mechanical contact the weapon delivers the SPINNER'S OWN
##      energy, which the solver cannot produce because a hinge motor Jolt drives
##      at a fixed velocity has no momentum budget to lose. `_note_contacts` reads
##      the bar's contact list from inside the step (read only), picks the single
##      strongest foreign contact, and `physics_tick` then applies
##        - an impulse `impulse * spin` along the bar's tangential velocity to the
##          struck body (divided by the victim's `flip_resistance`, exactly as the
##          flipper divides its throw),
##        - the damage that impulse is worth, through
##          `bot.opponent_damage_tick(part, severity, "impact")`, with `severity`
##          read off the SAME FightTypes BREAK_MIN / BREAK_MAX curve the contact
##          path uses, including the victim's armour thickness scaling, so a
##          spinner hit and a ram hit of the same N s are worth the same condition;
##        - the reaction: an equal and opposite impulse on our own chassis at the
##          contact offset, scaled by `self_destabilise`.
##   3. the bite costs spin. One good hit at full spin drops the bar to a fifth
##      (`BITE_SPIN_COST` 0.80, was 0.62 until 2026-09-27: at a third the bar was
##      back in the fight too soon and went 8-1 in the gauntlet), so the AI has to
##      disengage and re-spin, which is what spec section 6 asks the spinner AI to do.
##      A catalogue row may override it with `bite_spin_cost` (a tuning aid).
##
## MEASURED, do not "tidy": the tip speed is deliberately modest. 60 Hz discrete
## collision cannot see a 0.06 m thick bar that moves 0.37 m between steps, so the
## bar tunnels straight through an opponent and nothing happens at all. The bar
## runs at 12 rad/s (6.6 m/s at the tip, 0.11 m per step) with `continuous_cd` on,
## and the energy lives in the impulse model above rather than in the tip speed.

## Fitment pass 2, round 3 (coordinator 1 Oct): an UNDERCUTTER. The bar is the catalogue
## reach either side (0.35, a 0.70 m bar, about the box's track width), a thin blade that
## runs low, under or just in front of a weapon block on the nose. It was 1.10 m and
## 0.06 thick at the nose socket's height. `_bar_len` is the catalogue reach, both sides.
var _bar_len := 0.70
const BAR_THICK := 0.030
const BAR_DEPTH := 0.15
const BAR_FRICTION := 0.25
## Full-spin angular velocity, rad/s. See the tunnelling note above.
const MAX_OMEGA := 12.0
## Jolt drives a hinge motor to its target velocity whatever this says (measured in
## Stage 3, see flipper.gd), so it is here for the contract, not for the result.
const MOTOR_IMPULSE := 900.0
## Coast-down when the button is released, and the extra cost of a bite.
const COAST_S := 6.0
const BITE_SPIN_COST := 0.80
const BITE_COOLDOWN_S := 0.30
const MIN_BITE_SPIN := 0.08
## Reaction on the wielder. The flipper's measured trap applies here too: a single
## large impulse dumped into your own chassis reads as damage on your own wheels,
## so the linear share is small and the yaw share carries the lurch.
const REACTION_LINEAR := 0.22
const REACTION_TORQUE := 0.55
const SELF_DESTABILISE_GATE := 0.60
## The bar's ground clearance. An arm that reaches the floor becomes a third
## ground contact and the bot pogos (flipper.gd's measured trap).
const GROUND_CLEAR := 0.012

var bar: BotPart = null
var joint: HingeJoint3D = null
var pivot := Vector3.ZERO

var _spin := 0.0
var _pressed := false
var _bite_cooldown := 0.0
var _announced := false
## Filled inside the physics step by the bar, drained by `physics_tick`.
var _hit_body: RigidBody3D = null
var _hit_point := Vector3.ZERO


## The bar body. It reads its own contact list so the weapon can add the spinner's
## energy to a blow the solver has already resolved. Nothing is mutated in here.
class SpinBar extends BotPart:
	var weapon: RefCounted = null

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		super(state)
		if weapon != null and not detached:
			weapon.call("_note_contacts", state)


func _build() -> void:
	_bar_len = 2.0 * float(spec.get("reach", 0.35))
	pivot = socket_transform().origin
	# Never let the bar reach the floor.
	var lowest := -float(bot.ride_height()) + GROUND_CLEAR + BAR_THICK * 0.5
	pivot.y = maxf(pivot.y, lowest)
	_socket_y = pivot.y
	# the undercutter's lowest: the drawn blade BLADE_FLOOR off the floor (its 30 mm box is
	# then 9 mm off it: thin enough not to become a third ground contact)
	_low_y = -float(bot.ride_height()) + BLADE_FLOOR + BLADE_HALF
	# `--tune=horizontal_spinner.fit_forward=0` puts the bar back on the nose socket (the
	# before side of a gauntlet). Absent = the forward mount.
	if float(spec.get("fit_forward", 1.0)) > 0.5:
		_mount_ahead_of_the_nose()

	bar = SpinBar.new()
	bar.weapon = self
	bar.name = "SpinnerBar"
	bar.part_key = FightTypes.PART_WEAPON
	bar.part_kind = "weapon"
	bar.material_name = "steel"
	bar.physics_material_override = _material(BAR_FRICTION)
	bar.continuous_cd = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_bar_len, BAR_THICK, BAR_DEPTH)
	shape.shape = box
	bar.add_child(shape)
	_add_visual(Vector3(_bar_len, BAR_THICK, BAR_DEPTH))

	bar.transform = Transform3D(Basis.IDENTITY, pivot)
	bot.register_part(bar, FightTypes.PART_WEAPON, "weapon", mass())

	joint = HingeJoint3D.new()
	joint.name = "JointSpinner"
	# A hinge turns about the JOINT's local Z, so Z has to point up: a -90 degree
	# turn about X sends +Z to +Y.
	joint.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), pivot)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(bar)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true


## Fitment pass 2, the coordinator's call (30 Sept): a FORWARD MOUNT. The bar turned about
## the nose socket, so its 1.1 m sweep covered the whole front half of the machine; raising
## it clear was measured and puts it over every low machine's deck. So, as the drum does,
## the bar stays at its height and its hub is carried forward on a boom until the drawn bar
## (radius BAR_DRAWN_RADIUS) clears everything the machine draws in the bar's height band
## (the hull, the armour boxes, the wheels and tracks) by BAR_CLEAR at every angle. The
## boom itself is drawn by Bot._support_hinged, over the bar.
## PHYSICS: the bar body, its box and its hinge move forward and (round 3) down, and the
## bar is the 0.70 m blade above.
const BAR_CLEAR := 0.010
## horizontal_spinner.glb (round 3): the blade is drawn BLADE_HALF above and below the hinge
## and reaches the catalogue reach plus its corner; the hub boss (the motor's output) stands
## HUB_HEIGHT above the blade, HUB_RADIUS round, under the weapon block.
const BLADE_HALF := 0.018
## Drawn blade's underside above the floor at its lowest, and the air the blade keeps from a
## hull it runs under (a box's belly is 50 mm up).
const BLADE_FLOOR := 0.006
const BLADE_UNDER_CLEAR := 0.006
const BLADE_CORNER := 0.009
const HUB_RADIUS := 0.080
const HUB_HEIGHT := 0.046
var _socket_y := 0.0
var _low_y := 0.0


## Heights from the floor up to the nose socket (never above it: a bar over the deck sweeps
## over a low machine) are tried in 10 mm steps, and the one that needs the shortest mount
## wins (the lowest on a tie): on a box that is right at the floor, under its belly. At each
## the hub goes forward until the blade clears everything drawn in its band and the hub
## boss everything in its band.
func _mount_ahead_of_the_nose() -> void:
	if bot == null or bot.chassis_module == null:
		return
	var best_x := INF
	var best_y := _low_y
	var y := _low_y
	while y <= maxf(_socket_y, _low_y) + 0.0001:
		var x := _mount_x(y)
		if x < best_x - 0.004:
			best_x = x
			best_y = y
		y += 0.01
	pivot = Vector3(best_x, best_y, pivot.z)


func _mount_x(y: float) -> float:
	var reach := float(spec.get("reach", 0.35)) + BLADE_CORNER
	var x := _clear_x(y - BLADE_HALF - BLADE_UNDER_CLEAR, y + BLADE_HALF + BLADE_UNDER_CLEAR,
		reach + BAR_CLEAR, pivot.x)
	x = maxf(x, _clear_x(y + BLADE_HALF, y + BLADE_HALF + HUB_HEIGHT, HUB_RADIUS + BAR_CLEAR,
		pivot.x))
	return ceilf(x / 0.002) * 0.002


## The smallest hub x at or past `x0` that keeps every drawn point of the machine (hull,
## the front and side armour boxes, the drive) in [y0, y1] at least `need` from the axis.
func _clear_x(y0: float, y1: float, need: float, x0: float) -> float:
	var pts := PackedVector2Array()
	var hull: Node3D = bot.chassis_module.model
	if hull != null:
		for mi in Bot._mesh_instances_under(hull):
			if mi.mesh == null or not mi.visible:
				continue
			var t: Transform3D = bot.call("_relative_to_bot", mi)
			for v in Bot._mesh_points(mi.mesh):
				var p := t * v
				if p.y >= y0 and p.y <= y1:
					pts.append(Vector2(p.x, p.z))
	for face in ["front", "sides"]:
		var socket: Dictionary = bot.chassis_module.armour_socket(face)
		var size: Vector3 = socket["size"]
		for at_variant in socket["transforms"]:
			var at: Transform3D = at_variant
			for i in range(3):
				for j in range(9):
					for k in range(5):
						var p := at * Vector3((float(i) / 2.0 - 0.5) * size.x + 0.004,
							(float(j) / 8.0 - 0.5) * size.y, (float(k) / 4.0 - 0.5) * size.z)
						if p.y >= y0 and p.y <= y1:
							pts.append(Vector2(p.x, p.z))
	for box_variant in bot.get("_drive_boxes"):
		var box: AABB = box_variant
		if box.end.y < y0 or box.position.y > y1:
			continue
		for i in range(8):
			var c := box.get_endpoint(i)
			pts.append(Vector2(c.x, c.z))
	var x := x0
	for p in pts:
		var dz := absf(p.y - pivot.z)
		if dz < need:
			x = maxf(x, p.x + sqrt(need * need - dz * dz))
	return x


## The model hinges at its own origin (`socket_pivot` is [0, 0, 0]), so it parents
## to the bar body at identity.
func _add_visual(size: Vector3) -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "horizontal_spinner")))
	if model != null:
		bar.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(size)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	bar.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.1
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL holds the spin. There is no edge behaviour: a spinner is either
## winding up or coasting down.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	_bite_cooldown = maxf(_bite_cooldown - dt, 0.0)
	var alive := bar != null and is_instance_valid(bar) and not bar.detached
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


## `spin_up_s` from the catalogue, already scaled by the spare battery.
func spin_up_s() -> float:
	return float(spec.get("spin_up_s", 2.5)) * float(bot.spin_up_factor())


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
## Called from inside the physics step by the bar. Read only: it records the
## strongest foreign contact and nothing else. Contacts are summed per collider
## (Jolt reports one per contact POINT) and the winner is picked by summed impulse
## with the instance id as the tie break, so the choice never depends on the order
## the engine happens to report them in.
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
		var obj := state.get_contact_collider_object(i)
		var part := obj as BotPart
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


## Spend the recorded contact, outside the step, where applying impulses and
## touching the damage model is safe.
func _spend_hit() -> void:
	var victim := _hit_body as BotPart
	_hit_body = null
	if victim == null or not is_instance_valid(victim) or victim.detached:
		return
	if jammed or bar == null or not is_instance_valid(bar) or bar.detached:
		return
	if _spin < MIN_BITE_SPIN or _bite_cooldown > 0.0:
		return
	var dir := _tangential(_hit_point)
	if dir == Vector3.ZERO:
		return

	var spin := _spin
	var newtons := float(spec.get("impulse", 180.0)) * spin
	var resist := 1.0
	var other := victim.owner_bot
	if other != null:
		resist = maxf(float(other.call("flip_resistance")), 0.1)

	victim.apply_impulse(dir * (newtons / resist), _hit_point - victim.global_position)
	bot.opponent_damage_tick(victim, WeaponBase.spinner_bite(_severity_for(victim, newtons)), "impact")
	_react(dir, newtons, spin)

	_bite_cooldown = BITE_COOLDOWN_S
	_spin = maxf(_spin - float(spec.get("bite_spin_cost", BITE_SPIN_COST)) * spin, 0.0)


## The bar's velocity at a world point, flattened: a horizontal bar hits sideways.
func _tangential(point: Vector3) -> Vector3:
	var v := bar.linear_velocity + bar.angular_velocity.cross(point - bar.global_position)
	v.y = 0.0
	if v.length_squared() < 0.04:
		return Vector3.ZERO
	return v.normalized()


## Newton seconds -> condition, on the same curve `BotDamage.apply_impulse_damage`
## uses, thickness scaling included. `opponent_damage_tick` then applies the
## victim's material factor for "impact", so the two paths agree.
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


## The wielder's half of the bite. Above `SELF_DESTABILISE_GATE` the full
## `self_destabilise` factor applies; below it the bar is not carrying enough to
## upset anything, so only the recoil is felt.
func _react(dir: Vector3, newtons: float, spin: float) -> void:
	var chassis: RigidBody3D = bot.chassis
	if chassis == null:
		return
	var factor := float(spec.get("self_destabilise", 0.6))
	if spin < SELF_DESTABILISE_GATE:
		factor *= 0.35
	var back := -dir * newtons * factor
	var arm := _hit_point - chassis.global_position
	chassis.apply_central_impulse(back * REACTION_LINEAR)
	chassis.apply_torque_impulse(arm.cross(back) * REACTION_TORQUE
		/ maxf(float(bot.tip_resistance()), 0.1))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or bar == null or not is_instance_valid(bar) or bar.detached:
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "SPIN %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	if bar == null or not is_instance_valid(bar) or bar.detached:
		return -1.0
	return maxf(bar.global_position.y, 0.0)


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
