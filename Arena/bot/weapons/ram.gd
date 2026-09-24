extends WeaponBase
## The ram (docs/stage4-spec.md section 4): a spike wedge bolted to the nose. No
## hinge, no motor, no button, nothing to spin up and nothing to jam. What it does
## is multiply the contact impulse it delivers by the catalogue `impulse_bonus`,
## so the same charge from the same drive throws the other bot further.
##
## THE BONUS IS MOMENTUM, NOT DAMAGE, and that is deliberate. The extra goes on the
## victim as an impulse; the victim's damage model still only sees the contact it
## really took. That is what makes a ram bot read as a ram bot: brief section 5.3's
## "everything into speed and armour", and R2's three builds test expects exactly
## this shape from it (the highest push distance and the LOWEST damage removed). A
## ram that also multiplied damage would be a spinner that never needs spinning up.
## Where the hurt comes from is the wall, the spikes and the floor the victim is
## driven into, all of which hit `impulse_bonus` times harder now it arrives faster.
##
## THE BONUS IS ONE KICK PER BLOW, worked out from the closing speed and the two
## bots' masses, and NOT a multiplier on the contact impulses Jolt reports.
## Multiplying the reported impulses is the obvious implementation and it was the
## first one; it is wrong twice over.
##   1. A single body is only told about its own share of a collision. Measured
##      head on, box against box: the ram body saw 6.3 N s of contact while the
##      victim's momentum changed by 32 N s. Multiplying a fifth of the blow by 1.4
##      is not the promise the catalogue makes, and it measured as a 2 percent
##      difference at the victim.
##   2. It fires every tick of a shove, not once per hit, which turns a bulldozing
##      match into free acceleration.
## So: on the first tick of a genuine impact (closing speed above IMPACT_SPEED, and
## not within REARM_TICKS of the last one), apply `(bonus - 1) * reduced_mass *
## closing_speed` along the charge. That is exactly `impulse_bonus` times the blow a
## head on inelastic collision delivers, which is the number in the shop. A shove
## never re-triggers it, because a shove has no closing speed.
##
## THE EXTRA IS FREE MOMENTUM: there is no equal and opposite impulse on the
## wielder. Also measured: a ram stays in contact while it shoves, so a reaction
## lands every tick too and cancels the wielder's own push, and with one the ram bot
## left its victim at 1.60 m/s where the same bot carrying a dead plate left it at
## 2.00 m/s. Conserving momentum here makes the ram a WORSE chassis than no weapon
## at all, which is not a trade the catalogue is offering.
##
const RAM_DEPTH := 0.16
const RAM_HEIGHT := 0.20
const RAM_WIDTH := 0.40
const RAM_FRICTION := 0.3
## WHERE A RAM GOES, and this one is measured. A ram bolted to the front SOCKET is
## useless on a ramped hull: the wedge's front socket is the flipper's pinned hinge
## point at x = 0.11, which is 0.34 m behind the nose, and a 0.2 m spike there sits
## entirely inside its own bodywork. Two wedges nose to nose stop 0.90 m apart on
## their lips and the spike's face never gets within 0.2 m of anything. Measured:
## zero bonus impulses delivered in a full speed head on charge, and the ram bot
## actually pushed its victim LESS far than a bot carrying a dead plate.
## So the ram places itself: at the front lip, RAM_PROUD past the hull, low enough
## that it is the first thing to touch and high enough never to touch the floor
## (the flipper's third-ground-contact trap, docs/stage4-assembly-notes.md).
## HOW FAR PROUD, also measured. At 0.10 m the spike touched first but the armour
## plates behind it were in the collision a millisecond later, and Jolt shared the
## impulse out between them: the ram body saw 0.08 N s of a 20 N s collision and
## the bonus did nothing. The catalogue reach is 0.20 at the point, so the spike
## gets 0.18 m of clear air past the hull and is unambiguously the thing that hits.
const RAM_PROUD := 0.18
const RAM_CLEAR := 0.03                      # air under the spike

## The ram model's point, from Arena/assets/parts/manifest.json.
const MODEL_TIP := Vector3(0.312, 0.03, 0.0)

var spike: BotPart = null


## The ram body reads its own contacts. Extending BotPart rather than copying it
## keeps the damage path (and its per-collider summing) in one place.
class RamBody extends BotPart:
	## The catalogue `impulse_bonus`. 1.0 means bent: no bonus, just a shape.
	var bonus := 1.0
	## Every kick this ram has handed out, in N s. For the test and for tuning,
	## never for gameplay.
	var extra_delivered := Vector3.ZERO
	var hits := 0

	## Below this closing speed it is a shove, not a blow.
	const IMPACT_SPEED := 0.35
	## How far back to look for the speed of the charge. By the tick the ram's own
	## body first reports a foreign contact the collision has already been running
	## for a few steps and the closing speed has collapsed: measured, 0.73 m/s off a
	## charge that was doing 2.03 m/s a fifth of a second earlier, which priced the
	## blow at a third of what the catalogue promises. The charge is what the bonus
	## is a bonus ON, so the charge is what is measured.
	const CHARGE_WINDOW := 12
	## A blow cannot repeat inside this many ticks, so one collision is one kick.
	const REARM_TICKS := 18
	## Nothing the catalogue prices should be able to throw a bot out of the arena.
	const MAX_EXTRA := 60.0

	var _last_hit := -1000
	var _charge := PackedFloat32Array()
	var _charge_head := 0
	## The blow found this step, handed to the weapon to apply on the NEXT one.
	var pending := Vector3.ZERO
	var pending_victim: RigidBody3D = null
	var pending_offset := Vector3.ZERO

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		super._integrate_forces(state)
		if detached or owner_bot == null or bonus <= 1.0:
			return
		# The charge direction. The ram is welded to the hull, so its +X is the
		# bot's forward (docs/stage3-physics-notes.md section 1).
		var forward := global_basis.x
		forward.y = 0.0
		if forward.length_squared() < 1e-6:
			return
		forward = forward.normalized()
		if _charge.is_empty():
			_charge.resize(CHARGE_WINDOW)
		_charge[_charge_head] = state.linear_velocity.dot(forward)
		_charge_head = (_charge_head + 1) % CHARGE_WINDOW
		# The machine's own tick, not the engine's frame count: a hit-stop hold must not
		# count toward the rearm (see Bot.sim_ticks).
		var frame: int = int(owner_bot.call("sim_ticks")) if owner_bot.has_method("sim_ticks") \
			else Engine.get_physics_frames()
		if frame - _last_hit < REARM_TICKS:
			return

		# The body to kick: the victim's CHASSIS, not the plate the spike happened
		# to land on. A 2 kg plate takes the whole blow to 30 m/s and the bot it is
		# bolted to barely moves; the flipper's throw hits the chassis for the same
		# reason. Picked by instance id so two runs of one seed agree.
		var victim: RigidBody3D = null
		var victim_bot: Node = null
		var spot := Vector3.ZERO
		for i in range(state.get_contact_count()):
			var other := state.get_contact_collider_object(i) as BotPart
			if other == null or other.detached or other.owner_bot == null:
				continue
			if other.owner_bot == owner_bot:
				continue
			var body: RigidBody3D = other
			var hull := (other.owner_bot as Node).get("chassis") as RigidBody3D
			if hull != null:
				body = hull
			if victim == null or body.get_instance_id() < victim.get_instance_id():
				victim = body
				victim_bot = other.owner_bot
				spot = state.get_contact_local_position(i)
		if victim == null:
			return

		var charge := 0.0
		for v in _charge:
			charge = maxf(charge, v)
		var closing := maxf(charge, state.linear_velocity.dot(forward)) \
			- victim.linear_velocity.dot(forward)
		if closing < IMPACT_SPEED:
			return
		# The blow a head on inelastic collision delivers is the reduced mass times
		# the closing speed. Whole bots, not bodies: the spike is bolted to one and
		# the plate it hit is bolted to the other.
		var mine := _bot_mass(owner_bot, mass)
		var theirs := _bot_mass(victim_bot, victim.mass)
		var reduced := mine * theirs / maxf(mine + theirs, 0.001)
		var extra := forward * minf((bonus - 1.0) * reduced * closing, MAX_EXTRA)
		# Handed to the weapon and applied from its physics_tick, not here. It
		# measured identically either way (Jolt queues an impulse raised inside
		# `_integrate_forces` to the next step regardless), and outside the step is
		# where the rest of this game applies impulses: the flipper's throw, the
		# srimech, the axe's blow. One habit, not two.
		pending = extra
		pending_victim = victim
		pending_offset = spot - victim.global_position
		hits += 1
		_last_hit = frame

	func _bot_mass(node: Node, fallback: float) -> float:
		if node != null and node.has_method("total_mass"):
			return maxf(float(node.call("total_mass")), 0.1)
		return maxf(fallback, 0.1)


func _build() -> void:
	var body := RamBody.new()
	body.name = "Ram"
	body.part_key = FightTypes.PART_WEAPON
	body.part_kind = "weapon"
	body.material_name = "steel"
	body.bonus = maxf(float(spec.get("impulse_bonus", 1.4)), 1.0)
	body.physics_material_override = _material(RAM_FRICTION)
	spike = body

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RAM_DEPTH, RAM_HEIGHT, RAM_WIDTH)
	shape.shape = box
	spike.add_child(shape)
	_add_visual()

	var nose: float = float(bot.chassis_module.half_len()) + RAM_PROUD - RAM_DEPTH * 0.5
	var low: float = float(bot.chassis_module.floor_y()) + RAM_CLEAR + RAM_HEIGHT * 0.5
	spike.transform = Transform3D(Basis.IDENTITY, Vector3(nose, low, 0.0))
	bot.register_part(spike, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(spike)


## The model's own point (socket_tip, 0.312 forward of its mount) is lined up with
## the collision box's front face, so what the player sees hitting is what hits.
func _add_visual() -> void:
	var model := PartVisuals.instantiate("ram")
	if model != null:
		model.transform = Transform3D(Basis.IDENTITY,
			Vector3(RAM_DEPTH * 0.5 - MODEL_TIP.x, -MODEL_TIP.y, 0.0))
		spike.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(RAM_DEPTH, RAM_HEIGHT, RAM_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	spike.add_child(mesh_instance)


func _material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.05
	return material


## The ram has no input, but it does have one thing to do per tick: hand out the
## blow its body found last step (see RamBody for why it is not applied in place).
func physics_tick(_dt: float) -> void:
	if spike == null or not (spike is RamBody):
		return
	var body := spike as RamBody
	if body.pending == Vector3.ZERO or body.pending_victim == null:
		return
	if is_instance_valid(body.pending_victim):
		body.pending_victim.apply_impulse(body.pending, body.pending_offset)
		body.extra_delivered += body.pending
	body.pending = Vector3.ZERO
	body.pending_victim = null


# ---------------------------------------------------------------------------
# Queries. There is no button and no state, so these are as short as they look.
# ---------------------------------------------------------------------------
func impulse_bonus() -> float:
	if spike == null or spike.detached or jammed:
		return 1.0
	return maxf(float(spec.get("impulse_bonus", 1.4)), 1.0)


## The total bonus momentum this ram has handed out, in N s, and how many blows
## it took to hand it out. Diagnostic only.
func bonus_delivered() -> Vector3:
	if spike == null or not (spike is RamBody):
		return Vector3.ZERO
	return (spike as RamBody).extra_delivered


func bonus_hits() -> int:
	if spike == null or not (spike is RamBody):
		return 0
	return (spike as RamBody).hits


## Always ready. A ram is a shape, and a shape does not need charging: the AI's
## "ram charges" behaviour reads this and never waits.
func readiness() -> float:
	if jammed or spike == null or spike.detached:
		return 0.0
	return 1.0


func status_text() -> String:
	if jammed:
		return "BENT"
	return "RAM"


## A bent ram stops paying its bonus. It cannot fall off (it is welded on like an
## armour plate), which is the point of spending nothing on a mechanism.
func set_jammed() -> void:
	jammed = true
	if spike != null and spike is RamBody:
		(spike as RamBody).bonus = 1.0


func freeze() -> void:
	set_jammed()
