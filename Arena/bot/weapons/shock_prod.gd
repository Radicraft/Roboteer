extends WeaponBase
## Shock prod (brief v5 section 9.5, Level 35, wave P agent D1).
##
## A live spike bolted to the nose. It is the cheapest and lightest thing on the
## ladder above the lifter, and it is not bought for its damage: `dps` 0.035 is
## half the saw's, and the reason to fit one is that every touch cuts the other
## machine's DRIVE for `disrupt_s` seconds. A prod bot wins by leaving its
## opponent stranded in front of the spikes, not by taking it apart.
##
## HOW IT IS BUILT. A welded body, like the ram's spike and for the same reason:
## there is no mechanism, so there is nothing to spin up, nothing to reset and
## nothing to tear off (a welded weapon body cannot be detached, it can only be
## bent, which is `set_jammed`). It stands `PROD_PROUD` past the nose so it is
## unambiguously the first thing to touch, which is the measured lesson in
## `ram.gd`: a weapon mounted at the front SOCKET on a ramped hull sits 0.34 m
## behind the lip and never reaches anything.
##
## HOW THE SHOCK IS DELIVERED. A small Area3D rides on the head. Every tick the
## button is held, everything foreign inside it takes `dps * dt` with source
## "shock", and a contact that has been unbroken for `arm_s` seconds fires the
## disruption: `victim.disrupt("drive", disrupt_s)`, then `reset_s` seconds before
## the prod can do it again. The damage keeps flowing during the reset; it is the
## DISRUPTION that has a cooldown, because a prod that stalled a drive every tick
## would simply delete the other machine's mobility for the whole fight.
##
## WHY "shock" AND NOT "cut". No armour material has a `shock` row, so every
## material takes it at 1.0 (the same ruling `flamethrower.gd` made for "burn").
## A prod that read the "cut" row would have been a second saw, best against the
## same plate and worst against the same plate; this way the answer to a prod is
## to stay off its nose, which is a driving problem rather than a shopping one.

const HEAD_DEPTH := 0.10
const HEAD_HEIGHT := 0.14
const HEAD_WIDTH := 0.26
const PROD_FRICTION := 0.35
## Air under the head, so the prod never becomes a third ground contact (the pogo
## trap, docs/stage3-physics-notes.md section 5).
const PROD_CLEAR := 0.03
## How far past the hull's own nose the head stands. The ram measured 0.18 m as
## the distance at which the spike, and not the armour behind it, takes the
## collision; the prod is a contact weapon and wants the same.
const PROD_PROUD := 0.18
## The sensor is the head plus a couple of millimetres, so a plate resting against
## it is inside it.
const AREA_MARGIN := 0.015

var head: BotPart = null
var sensor: Area3D = null

var _pressed := false
var _cooldown := 0.0
var _contact_s := 0.0
var _shocks := 0
var _reset_s := 2.5
var _arm_s := 0.12


func _build() -> void:
	_reset_s = maxf(float(spec.get("reset_s", 2.5)), 0.05)
	_arm_s = maxf(float(spec.get("arm_s", 0.12)), 0.0)

	head = BotPart.new()
	head.name = "ProdHead"
	head.part_key = FightTypes.PART_WEAPON
	head.part_kind = "weapon"
	head.material_name = "steel"
	head.physics_material_override = _material()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HEAD_DEPTH, HEAD_HEIGHT, HEAD_WIDTH)
	shape.shape = box
	head.add_child(shape)

	sensor = Area3D.new()
	sensor.name = "ProdContact"
	sensor.collision_layer = 0
	sensor.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	sensor.monitorable = false
	var sensor_shape := CollisionShape3D.new()
	var sensor_box := BoxShape3D.new()
	sensor_box.size = Vector3(HEAD_DEPTH, HEAD_HEIGHT, HEAD_WIDTH) \
		+ Vector3.ONE * AREA_MARGIN * 2.0
	sensor_shape.shape = sensor_box
	sensor.add_child(sensor_shape)
	head.add_child(sensor)

	_add_visual()

	var nose := _nose() + PROD_PROUD - HEAD_DEPTH * 0.5
	var low := float(bot.chassis_module.floor_y()) + PROD_CLEAR + HEAD_HEIGHT * 0.5
	head.transform = Transform3D(Basis.IDENTITY, Vector3(nose, low, 0.0))
	bot.register_part(head, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(head)


func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "shock_prod")))
	if model != null:
		model.transform = Transform3D(Basis.IDENTITY,
			Vector3(-HEAD_DEPTH * 0.5, 0.0, 0.0))
		head.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(HEAD_DEPTH, HEAD_HEIGHT, HEAD_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	head.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = PROD_FRICTION
	material.bounce = 0.05
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL: a prod is live for as long as the thumb is down.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	var alive := head != null and is_instance_valid(head) and not head.detached
	if not _pressed or jammed or not alive:
		_contact_s = 0.0
		return
	var victims := _touching()
	if victims.is_empty():
		_contact_s = 0.0
		return

	var amount := float(spec.get("dps", 0.035)) * dt
	for victim in victims:
		bot.opponent_damage_tick(victim, amount, BotDamage.SOURCE_SHOCK)

	_contact_s += dt
	if _contact_s < _arm_s or _cooldown > 0.0:
		return
	# The machine that owns the first victim in instance id order: the order is
	# fixed, so two runs of one seed stall the same drive.
	var owner_bot: Node = victims[0].owner_bot
	if owner_bot != null and owner_bot.has_method("disrupt"):
		owner_bot.call("disrupt", "drive", float(spec.get("disrupt_s", 1.2)))
		_shocks += 1
		_cooldown = _reset_s
		_contact_s = 0.0
		bot.emit_weapon_fired()


## Everything foreign in the head's sensor, sorted by instance id, because the
## order an Area reports overlaps in is not part of the contract.
func _touching() -> Array[BotPart]:
	var out: Array[BotPart] = []
	if sensor == null or not sensor.is_inside_tree():
		return out
	for body in sensor.get_overlapping_bodies():
		var part := body as BotPart
		if part == null or part.detached or part.owner_bot == null \
				or part.owner_bot == bot:
			continue
		out.append(part)
	out.sort_custom(func(a: BotPart, b: BotPart) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	return out


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## Ready means "the next touch will stall them". The damage never stops, but the
## readout and the AI both care about the stall, which is what the part is for.
func readiness() -> float:
	if jammed or head == null or not is_instance_valid(head) or head.detached:
		return 0.0
	return clampf(1.0 - _cooldown / _reset_s, 0.0, 1.0)


## How many drives this prod has stalled. The test and the notes read it.
func shocks() -> int:
	return _shocks


## Seconds of unbroken contact so far, for the test.
func contact_seconds() -> float:
	return _contact_s


func status_text() -> String:
	if jammed:
		return "BENT"
	if _cooldown > 0.0:
		return "PROD %d%%" % int(round(readiness() * 100.0))
	return "PROD"


func tip_height() -> float:
	if head == null or not is_instance_valid(head) or head.detached:
		return -1.0
	return maxf(head.global_position.y, 0.0)


## A bent prod is a dead plate. It cannot fall off (it is welded on like an armour
## panel), which is the point of spending nothing on a mechanism.
func set_jammed() -> void:
	jammed = true
	_pressed = false
	_contact_s = 0.0


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"shocks": _shocks, "reset": snappedf(_cooldown, 0.001)}
