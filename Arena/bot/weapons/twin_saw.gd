extends WeaponBase
## Twin saw (brief v5 section 9.5, Level 75, wave P agent D1).
##
## Two discs side by side on one arbor: the Level 5 saw grown up. It is the same
## weapon mechanically, and every line of `saw.gd`'s reasoning still holds (read
## it first), with three differences that are all in the catalogue row:
##
##   1. `blades` 2. Two bodies, two hinges, one motor target. They sit either side
##      of the centreline `BLADE_GAP` apart, so the pair covers 0.42 m of the
##      other machine's flank rather than the single saw's 0.022 m of it, and a
##      plate that slips off one disc lands on the other.
##   2. `reach` 0.38 against 0.30, which is a bigger disc as well as a wider one.
##   3. `dps` against the saw's 0.06, shared between the discs that are in the
##      work: one disc biting cuts at the whole rate, two split it (see `_cut`,
##      changed in the weapons pass), so the number in the shop is what the weapon
##      does however many discs are on the plate. Fitting it costs 21 kg against the saw's 12, which is
##      most of a Wedge's spare budget, so it is a machine built around the saws
##      rather than a machine carrying one.
##
## The damage is "cut", like the saw's, so the material table applies in full:
## twin saws eat HDPE and struggle against steel exactly as one saw does. The
## weapon that does NOT care what the plate is made of is the drill lance, one
## Level below, and that is the choice the ladder is offering at 65 and 75.
##
## Both discs are registered as `part_kind` "weapon" on the one `weapon` condition
## row, and each carries half the catalogue weight so the build's simulated mass
## still matches the shop (assembly_test checks it to 10 percent).

const BLADE_THICK := 0.020
const BLADE_FRICTION := 0.15
## Centre to centre across the machine. Wide enough to straddle a wheel, narrow
## enough to stay inside the narrowest hull in the game (the Long/Low, 0.5 m).
const BLADE_GAP := 0.23
## See `saw.gd`: a motor driven hinge cannot be stalled, so a fast blade held
## against a plate spends its own condition. 14 rad/s survives a long grind, and
## the damage is `dps`, not tip speed.
const MAX_OMEGA := 14.0
const MOTOR_IMPULSE := 400.0
const COAST_S := 1.2
const AREA_MARGIN := 0.018
const GROUND_CLEAR := 0.010
## Wave C fitment (PHYSICS, flagged): the discs stand proud of the front armour, their
## back SLOT_BITE in slots cut in the front plate, on the same rule as the saw. With the
## old rule (teeth 0.03 m past the nose) a 0.19 m disc's centre sat 0.16 m inside the
## hull and the discs came up through the deck.
const SLOT_BITE := 0.020
const MIN_CUT_SPIN := 0.05
## What the disc radius is, as a fraction of the catalogue reach. The saw's own
## 0.155 m disc on a 0.30 m reach is this number.
const RADIUS_PER_REACH := 0.5

var blades: Array[BotPart] = []
var joints: Array[HingeJoint3D] = []
var cutters: Array[Area3D] = []
var radius := 0.19

var _spin := 0.0
var _pressed := false
var _announced := false
var _cutting_s := 0.0


func blade_count() -> int:
	return maxi(int(spec.get("blades", 2)), 1)


func _build() -> void:
	radius = maxf(float(spec.get("reach", 0.38)) * RADIUS_PER_REACH, 0.05)
	var count := blade_count()
	var pivot := socket_transform().origin
	pivot.y = maxf(pivot.y, -float(bot.ride_height()) + GROUND_CLEAR + radius)
	pivot.x = maxf(pivot.x, _nose() + radius - SLOT_BITE)
	# Evenly spaced about the centreline: two discs sit at plus and minus half the
	# gap, three would sit at minus, nought and plus, and so on.
	var span := BLADE_GAP * float(count - 1)
	for i in range(count):
		var at := pivot
		at.z = -span * 0.5 + BLADE_GAP * float(i)
		_build_blade(i, at)
	_add_mount(pivot, span)


## Wave C fitment: now the discs stand out in front of the nose, something has to be
## seen holding them. A cross axle through both hubs and a boom back into the slot in
## the front plate, on the hull. Presentation only: no body, no shape, no mass.
func _add_mount(pivot: Vector3, span: float) -> void:
	if bot.chassis == null:
		return
	var mount := Node3D.new()
	mount.name = "TwinSawMount"
	var dark := PartVisuals.slot_material("dark_metal", bot.livery)
	var steel := PartVisuals.slot_material("steel", bot.livery)
	var axle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	cyl.height = span + BLADE_THICK * 2.0 + 0.03
	cyl.radial_segments = 14
	axle.mesh = cyl
	axle.material_override = steel
	axle.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), pivot)
	mount.add_child(axle)
	var back := _nose() - 0.06
	var boom := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(pivot.x - back, 0.05), 0.05, 0.05)
	boom.mesh = box
	boom.material_override = dark
	boom.position = Vector3((pivot.x + back) * 0.5, pivot.y, 0.0)
	mount.add_child(boom)
	bot.chassis.add_child(mount)


func _build_blade(index: int, at: Vector3) -> void:
	var blade := BotPart.new()
	blade.name = "SawBlade%d" % index
	blade.part_key = FightTypes.PART_WEAPON
	blade.part_kind = "weapon"
	blade.material_name = "steel"
	blade.physics_material_override = _material()
	blade.continuous_cd = true

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = BLADE_THICK
	shape.shape = cylinder
	shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # cylinder axis Y to Z
	blade.add_child(shape)

	var cutter := Area3D.new()
	cutter.name = "Cutter%d" % index
	cutter.collision_layer = 0
	cutter.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	cutter.monitorable = false
	var cut_shape := CollisionShape3D.new()
	var cut_cylinder := CylinderShape3D.new()
	cut_cylinder.radius = radius + AREA_MARGIN
	cut_cylinder.height = BLADE_THICK + AREA_MARGIN * 2.0
	cut_shape.shape = cut_cylinder
	cut_shape.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	cutter.add_child(cut_shape)
	blade.add_child(cutter)

	_add_visual(blade)

	blade.transform = Transform3D(Basis.IDENTITY, at)
	# Half the catalogue weight each, so the pair weighs what the shop charges for.
	bot.register_part(blade, FightTypes.PART_WEAPON, "weapon",
		mass() / float(blade_count()))

	var joint := HingeJoint3D.new()
	joint.name = "JointTwinSaw%d" % index
	joint.transform = Transform3D(Basis.IDENTITY, at)
	bot.add_joint(joint)
	joint.node_a = joint.get_path_to(bot.chassis)
	joint.node_b = joint.get_path_to(blade)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, MOTOR_IMPULSE)
	joint.exclude_nodes_from_collision = true

	blades.append(blade)
	joints.append(joint)
	cutters.append(cutter)


func _add_visual(blade: BotPart) -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "twin_saw")))
	if model != null:
		var offset := Vector3.ZERO
		var sockets := PartVisuals.read_sockets(model)
		if sockets.has("socket_pivot"):
			offset = sockets["socket_pivot"]
		model.position = -offset
		blade.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = BLADE_THICK
	mesh.radial_segments = 20
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	blade.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = BLADE_FRICTION
	material.bounce = 0.0
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	var winding := _pressed and not jammed and _any_blade_alive() \
		and not bool(bot.is_disrupted("weapon"))
	if winding:
		_spin = minf(_spin + dt / maxf(spin_up_s(), 0.01), 1.0)
	else:
		_spin = maxf(_spin - dt / COAST_S, 0.0)
	_drive_motors()
	_cut(dt)
	if _spin >= 1.0 and not _announced:
		_announced = true
		bot.emit_weapon_fired()
	elif _spin < 0.5:
		_announced = false


func spin_up_s() -> float:
	return float(spec.get("spin_up_s", 0.6)) * float(bot.spin_up_factor())


func _any_blade_alive() -> bool:
	for blade in blades:
		if is_instance_valid(blade) and not blade.detached:
			return true
	return false


func _drive_motors() -> void:
	for joint in joints:
		if not is_instance_valid(joint):
			continue
		if jammed:
			joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)
			continue
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, MAX_OMEGA * _spin)


## THE MOTOR'S CUT IS SHARED BETWEEN THE DISCS THAT ARE IN THE WORK (weapons pass,
## 2026-09-25). It used to be `dps / blades` per disc whatever the other disc was
## doing, and the gauntlet measured the cost: on a real machine one disc is in the cut
## far more often than two (the pair straddles a wheel or rides a corner), so the
## Level 75 twin saw removed 1.56 condition a fight to the Level 5 saw's 2.42 and went
## 4-5 to its 6-3. Now the arbor's whole `dps` goes into whichever discs are biting:
## one disc in the work cuts at the full rate, two split it. The width is what the
## second disc buys (it is in the work more often), and the number in the shop is what
## the weapon does.
##
## The blades are walked in build order and each blade's overlaps are sorted by
## instance id, so the damage events land in the same order in two runs of one seed.
func _cut(dt: float) -> void:
	if jammed or _spin < MIN_CUT_SPIN:
		_cutting_s = 0.0
		return
	var knock := float(spec.get("knockback", 0.05)) * _spin
	var biting: Array = []
	for i in range(blades.size()):
		var blade := blades[i]
		var cutter := cutters[i]
		if not is_instance_valid(blade) or blade.detached or cutter == null \
				or not cutter.is_inside_tree():
			continue
		var victims: Array[BotPart] = []
		for body in cutter.get_overlapping_bodies():
			var part := body as BotPart
			if part == null or part.detached or part.owner_bot == null \
					or part.owner_bot == bot:
				continue
			victims.append(part)
		if victims.is_empty():
			continue
		victims.sort_custom(func(a: BotPart, b: BotPart) -> bool:
			return a.get_instance_id() < b.get_instance_id())
		biting.append([blade, victims])
	if biting.is_empty():
		_cutting_s = 0.0
		return
	var share := float(spec.get("dps", 0.13)) * dt * _spin / float(biting.size())
	for entry in biting:
		var blade: BotPart = entry[0]
		for victim in entry[1]:
			bot.opponent_damage_tick(victim, share, "cut")
			if knock > 0.0:
				victim.apply_central_impulse(
					_tangential(blade, victim.global_position) * knock)
	_cutting_s += dt


func _tangential(blade: BotPart, point: Vector3) -> Vector3:
	var v := blade.linear_velocity + blade.angular_velocity.cross(
		point - blade.global_position)
	if v.length_squared() < 0.01:
		return Vector3.ZERO
	return v.normalized()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func readiness() -> float:
	if jammed or not _any_blade_alive():
		return 0.0
	return clampf(_spin, 0.0, 1.0)


func spin() -> float:
	return _spin


func cutting_seconds() -> float:
	return _cutting_s


## How many discs are still on. A twin saw that has lost one is half a weapon,
## not a dead one, which is most of the reason to carry two.
func blades_left() -> int:
	var left := 0
	for blade in blades:
		if is_instance_valid(blade) and not blade.detached:
			left += 1
	return left


func status_text() -> String:
	if jammed:
		return "JAMMED"
	return "SAWS %d%%" % int(round(readiness() * 100.0))


func tip_height() -> float:
	var high := -1.0
	for blade in blades:
		if is_instance_valid(blade) and not blade.detached:
			high = maxf(high, maxf(blade.global_position.y, 0.0))
	return high


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_cutting_s = 0.0
	for joint in joints:
		if is_instance_valid(joint):
			joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, false)


func freeze() -> void:
	set_jammed()
	_spin = 0.0


func state() -> Dictionary:
	return {"spin": snappedf(_spin, 0.001), "blades": blades_left()}
