extends WeaponBase
## Tesla arc (brief v5 section 9.5, Level 60, wave P agent D1).
##
## A coil on the nose that charges over `spin_up_s` and then throws a short arc at
## the nearest opponent part inside `reach`. The arc takes a burst of condition
## off that part and stalls BOTH the victim's weapon and its drive for
## `disrupt_s`, then the coil is empty for `reset_s` before it can charge again.
##
## IT IS NOT A RANGED WEAPON and the 0.75 m reach is not a gun's. Two machines are
## 0.9 m long, so a coil on the nose has to be within about a chassis length of
## the other bot for the arc to find anything: it is a clinch weapon that does not
## need to be ON them, which is the difference from the crusher one Level below.
## What it buys for 17 kg is time: a machine with no weapon and no drive for a
## second and a half can be lined up, pushed onto the spikes, or left alone while
## you go and collect the arc's next charge.
##
## WHERE IT JUMPS. The nearest foreign body inside the coil's sphere, by distance
## from the coil, ties broken on instance id, so two runs of one seed arc at the
## same part. It is deliberately NOT the weakest part or the chassis: an arc looks
## for the shortest path, and the shortest path from a coil on your nose is
## whatever of theirs is closest, which is usually the plate between you.
##
## WHY "arc" AND NOT "impact". No armour material has an `arc` row, so every
## material takes it at 1.0, the same ruling `flamethrower.gd` made for "burn".
## The plate you fit is the answer to spinners and saws; it is not the answer to
## electricity, and it should not be.
##
## THE DAMAGE IS A BURST, NOT A RATE, despite living in the catalogue's `dps`
## column: the column is "how hard does it hit" for the shop's pips and there is
## nowhere else to put it. One discharge removes `dps` condition from one part.

const COIL_LENGTH := 0.14
const COIL_HEIGHT := 0.18
const COIL_WIDTH := 0.22
const COIL_FRICTION := 0.35
## Air under the coil, so it never becomes a third ground contact.
const COIL_CLEAR := 0.03
## The coil sits at the front lip rather than inside the bodywork, for the reason
## measured in `ram.gd`: a weapon at the front SOCKET of a ramped hull is 0.34 m
## behind the nose, and the arc would be reaching out of the middle of the wedge.
const COIL_PROUD := 0.06

var coil: BotPart = null
var field: Area3D = null

var _pressed := false
var _charge := 0.0
var _cooldown := 0.0
var _arcs := 0
var _reset_s := 2.2
## The part the last discharge jumped to, for the test and for F's fx.
var _last_target: BotPart = null


func _build() -> void:
	_reset_s = maxf(float(spec.get("reset_s", 2.2)), 0.05)

	coil = BotPart.new()
	coil.name = "TeslaCoil"
	coil.part_key = FightTypes.PART_WEAPON
	coil.part_kind = "weapon"
	coil.material_name = "steel"
	coil.physics_material_override = _material()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COIL_LENGTH, COIL_HEIGHT, COIL_WIDTH)
	shape.shape = box
	coil.add_child(shape)

	# Everything the arc can reach: a sphere of the catalogue reach around the
	# coil. Monitorable off, nothing needs to find it, it only asks.
	field = Area3D.new()
	field.name = "ArcField"
	field.collision_layer = 0
	field.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	field.monitorable = false
	var field_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(float(spec.get("reach", 0.75)), 0.1)
	field_shape.shape = sphere
	field.add_child(field_shape)
	coil.add_child(field)

	_add_visual()

	var nose := _nose() + COIL_PROUD - COIL_LENGTH * 0.5
	var low := float(bot.chassis_module.floor_y()) + COIL_CLEAR + COIL_HEIGHT * 0.5
	coil.transform = Transform3D(Basis.IDENTITY, Vector3(nose, low, 0.0))
	bot.register_part(coil, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(coil)


func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "tesla_arc")))
	if model != null:
		model.transform = Transform3D(Basis.IDENTITY,
			Vector3(-COIL_LENGTH * 0.5, 0.0, 0.0))
		coil.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(COIL_LENGTH, COIL_HEIGHT, COIL_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	coil.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = COIL_FRICTION
	material.bounce = 0.05
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL: the coil charges while the thumb is down and discharges by itself
## the moment it is full and something is in range. A player never has to time
## the tap, which would be unreadable at arm's length.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	var alive := coil != null and is_instance_valid(coil) and not coil.detached
	if jammed or not alive:
		_charge = 0.0
		return
	if _pressed and _cooldown <= 0.0 and not bool(bot.is_disrupted("weapon")):
		_charge = minf(_charge + dt / maxf(charge_s(), 0.01), 1.0)
	elif not _pressed:
		# Letting go bleeds the coil rather than banking it, so an arc cannot be
		# carried around all fight and spent the instant the bell goes.
		_charge = maxf(_charge - dt / maxf(charge_s(), 0.01), 0.0)
	if _charge >= 1.0:
		_discharge()


func charge_s() -> float:
	return float(spec.get("spin_up_s", 1.6)) * float(bot.spin_up_factor())


func _discharge() -> void:
	var target := _nearest()
	if target == null:
		return
	bot.opponent_damage_tick(target, float(spec.get("dps", 0.09)),
		BotDamage.SOURCE_ARC)
	var victim: Node = target.owner_bot
	if victim != null and victim.has_method("disrupt"):
		var seconds := float(spec.get("disrupt_s", 1.6))
		victim.call("disrupt", "weapon", seconds)
		victim.call("disrupt", "drive", seconds)
	_last_target = target
	_arcs += 1
	_charge = 0.0
	_cooldown = _reset_s
	bot.emit_weapon_fired()


## The nearest foreign body inside the field. Distance first, instance id to break
## a tie, so the arc is the same in two runs of one seed.
func _nearest() -> BotPart:
	if field == null or not field.is_inside_tree() or coil == null:
		return null
	var from := coil.global_position
	var best: BotPart = null
	var best_d := INF
	for body in field.get_overlapping_bodies():
		var part := body as BotPart
		if part == null or part.detached or part.owner_bot == null \
				or part.owner_bot == bot:
			continue
		var d := from.distance_squared_to(part.global_position)
		if best == null or d < best_d - 0.000001 \
				or (absf(d - best_d) <= 0.000001
					and part.get_instance_id() < best.get_instance_id()):
			best = part
			best_d = d
	return best


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## The charge in the coil. The AI's spin_up profile reads it and will not commit
## on an empty one.
func readiness() -> float:
	if jammed or coil == null or not is_instance_valid(coil) or coil.detached:
		return 0.0
	return clampf(_charge, 0.0, 1.0)


func arcs() -> int:
	return _arcs


func last_target() -> BotPart:
	return _last_target


func status_text() -> String:
	if jammed:
		return "DEAD"
	if _cooldown > 0.0:
		return "ARC RESET"
	return "ARC %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	if coil == null or not is_instance_valid(coil) or coil.detached:
		return -1.0
	return maxf(coil.global_position.y, 0.0)


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_charge = 0.0


func freeze() -> void:
	set_jammed()
	_last_target = null


func state() -> Dictionary:
	return {"charge": snappedf(_charge, 0.001), "arcs": _arcs}
