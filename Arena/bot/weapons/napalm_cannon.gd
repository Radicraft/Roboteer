extends WeaponBase
## Napalm cannon (brief v5 section 9.5, Level 80, wave P agent D1).
##
## A stubby mortar on the nose. Each shot lobs a burning charge `reach` metres
## down the machine's own forward line; where it lands it leaves a patch of fire
## `patch_radius` across that burns for `fuel_s` seconds. Anything foreign that
## drives through the patch takes `dps` a second, and a second of it cuts that
## machine's DRIVE for `disrupt_s`. There are `charges` shells in the rack and no
## way to get more of them except the spare battery utility, exactly like the
## flipper's gas: `bot.gas_charges` is the shared count, so the shop's battery
## means one more shell here as well.
##
## IT IS THE ONLY WEAPON IN THE GAME THAT FIGHTS WHERE YOU ARE NOT. Everything
## else on the ladder needs its wielder to be touching the other machine when the
## damage lands. A napalm bot puts fire between itself and its opponent, across
## the ramp it wants to come down, or on top of a machine that has just been
## flipped, and then drives away from it. That is what 23 kg and Level 80 buy: not
## more damage per second than a twin saw (it is a third of one), but damage that
## keeps working with nobody standing over it.
##
## THE PATCH IS NOT PART OF THE BOT. It is a node in the fight world, so it stays
## where it was thrown when the machine that fired it drives off, and it keeps
## burning after that machine has been flipped. It is not a body, so nothing can
## push it, drive it or take condition off it; it is an Area3D that asks who is
## standing in it, which is the same mechanism the flamethrower's cone uses.
##
## THE FIRE ONLY BURNS THE OTHER MACHINE, and that is a decision rather than a
## simulation: `Bot.opponent_damage_tick` refuses to damage the bot that owns the
## weapon, so a shell dropped short is wasted rather than suicidal. A patch that
## burned its owner would make the weapon unusable in the clinch, which is where
## phone-sized fights actually happen. The dial, if the owner wants the harder
## version, is one line in `FirePatch._burn`.
##
## DETERMINISM. The charge does not fly as a rigid body: it follows a parabola
## worked out from the muzzle and the landing point at the moment it is fired, one
## step per physics tick, with no rng and no wall clock. Two runs of one seed put
## the fire in the same place to the millimetre.

const TUBE_LENGTH := 0.18
const TUBE_HEIGHT := 0.16
const TUBE_WIDTH := 0.18
const TUBE_FRICTION := 0.4
const TUBE_CLEAR := 0.05
const TUBE_PROUD := 0.04
## The arena floor. Bot heights are measured off it everywhere else in this
## folder, so the patch sits on it rather than on whatever the shell passed over.
const FLOOR_Y := 0.0

var tube: BotPart = null

var _pressed := false
var _cooldown := 0.0
var _reset_s := 2.0
## THE RACK RELOADS (weapons pass, 2026-09-25). Five shells and no way to get more
## measured as five shells in the first minute and two unarmed minutes after it
## (0.02 condition in a whole fight against the box ram). The loader now puts one
## shell back every `reload_s` while the rack is below what it started the fight
## with, so the cannon is a weapon for all three minutes and still has to pick its
## moments: a held button empties it in ten seconds and it takes a minute to refill.
## 0 (or no key) is the old fixed rack.
var _reload_s := 0.0
var _reload_left := 0.0
## The rack the fight started with (catalogue charges plus any spare battery), read
## on the first tick because the Bot sets `gas_charges` after the weapon is built.
var _rack := -1
var _shots := 0
## Every patch this cannon has lit that is still burning.
var _patches: Array[Node3D] = []


## A lit patch of floor. Lives in the fight world, not on the bot, and runs its
## own clock so it keeps burning after the machine that threw it has gone.
class FirePatch extends Node3D:
	## Seconds the charge is in the air. Long enough to read as a lob, short
	## enough that the fire arrives while the opponent is still where it was
	## aimed.
	const FLIGHT_S := 0.45
	## How high above the straight line the charge rises at the top of the arc.
	const ARC_HEIGHT := 0.55
	## Continuous seconds in the fire before the drive goes, and the grace that
	## stops a bot bouncing on its suspension from re-arming the timer (both from
	## `flamethrower.gd`, where they were measured).
	const DISRUPT_AFTER_S := 1.0
	const EXPOSURE_GRACE_S := 0.25
	const FLAME_CONE_SCRIPT := "res://fx/flame_cone.gd"

	var attacker: Node = null
	var dps := 0.04
	var burn_s := 6.0
	var disrupt_s := 1.5
	var radius := 0.45

	var area: Area3D = null
	var flame: Node3D = null
	var disc: MeshInstance3D = null
	var shell: MeshInstance3D = null

	var _from := Vector3.ZERO
	var _to := Vector3.ZERO
	var _flight_left := 0.0
	var _burn_left := 0.0
	var _lit := false
	## victim bot id -> {"time": seconds in the fire, "gap": seconds since seen}
	var _exposure: Dictionary = {}

	func launch(from: Vector3, to: Vector3) -> void:
		_from = from
		_to = to
		_flight_left = FLIGHT_S
		_burn_left = burn_s
		global_position = from

	func lit() -> bool:
		return _lit

	func burn_left() -> float:
		return _burn_left

	func _ready() -> void:
		shell = MeshInstance3D.new()
		shell.name = "Charge"
		var ball := SphereMesh.new()
		ball.radius = 0.055
		ball.height = 0.11
		ball.radial_segments = 10
		ball.rings = 6
		shell.mesh = ball
		shell.material_override = _ember()
		add_child(shell)

		area = Area3D.new()
		area.name = "Fire"
		area.collision_layer = 0
		area.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
		area.monitorable = false
		area.monitoring = false
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = 0.5
		shape.shape = cylinder
		shape.position = Vector3(0.0, 0.25, 0.0)
		area.add_child(shape)
		add_child(area)

	func _physics_process(delta: float) -> void:
		if attacker == null or not is_instance_valid(attacker):
			queue_free()
			return
		if _flight_left > 0.0:
			_fly(delta)
			return
		_burn(delta)

	## One step of the parabola. `t` is how far along the throw we are, and the
	## rise is a sine, so the charge leaves the muzzle and arrives nose down.
	func _fly(delta: float) -> void:
		_flight_left = maxf(_flight_left - delta, 0.0)
		var t := clampf(1.0 - _flight_left / FLIGHT_S, 0.0, 1.0)
		global_position = _from.lerp(_to, t) + Vector3.UP * ARC_HEIGHT * sin(PI * t)
		if _flight_left > 0.0:
			return
		_land()

	func _land() -> void:
		global_position = _to
		_lit = true
		if shell != null:
			shell.queue_free()
			shell = null
		if area != null:
			area.monitoring = true
		_light()

	func _burn(delta: float) -> void:
		_burn_left = maxf(_burn_left - delta, 0.0)
		if _burn_left <= 0.0:
			queue_free()
			return
		if flame != null and flame.has_method("step"):
			flame.call("step", delta)
		var seen: Dictionary = {}
		for part in _parts_in_fire():
			# Only the other machine burns. See the header: a patch that cooked
			# its owner would be unusable in the clinch.
			attacker.call("opponent_damage_tick", part, dps * delta, "burn")
			var victim: Node = part.owner_bot
			if victim == null:
				continue
			var key := str(victim.get("bot_id"))
			if seen.has(key):
				continue
			seen[key] = true
			var row: Dictionary = _exposure.get(key, {"time": 0.0, "gap": 0.0})
			row["time"] = float(row["time"]) + delta
			row["gap"] = 0.0
			_exposure[key] = row
			if float(row["time"]) >= DISRUPT_AFTER_S:
				row["time"] = 0.0
				if victim.has_method("disrupt"):
					victim.call("disrupt", "drive", disrupt_s)
		_age(delta, seen)

	func _age(delta: float, seen: Dictionary) -> void:
		var drop: Array[String] = []
		for key_variant in _exposure.keys():
			var key := str(key_variant)
			if seen.has(key):
				continue
			var row: Dictionary = _exposure[key]
			row["gap"] = float(row["gap"]) + delta
			if float(row["gap"]) > EXPOSURE_GRACE_S:
				drop.append(key)
			else:
				_exposure[key] = row
		for key in drop:
			_exposure.erase(key)

	## Everything foreign standing in the fire, sorted by instance id so the
	## damage lands in the same order in two runs of one seed.
	func _parts_in_fire() -> Array[BotPart]:
		var out: Array[BotPart] = []
		if area == null or not area.is_inside_tree() or not area.monitoring:
			return out
		for body in area.get_overlapping_bodies():
			var part := body as BotPart
			if part == null or part.detached or part.owner_bot == null:
				continue
			if part.owner_bot == attacker:
				continue
			out.append(part)
		out.sort_custom(func(a: BotPart, b: BotPart) -> bool:
			return a.get_instance_id() < b.get_instance_id())
		return out

	## The fire itself is `fx/flame_cone.gd`, the effect the flamethrower already
	## ships, stood on its end: its cone fires along +X, so a quarter turn about Z
	## points it at the ceiling. A missing fx file leaves the glowing disc, which
	## is there either way so the patch is never invisible.
	func _light() -> void:
		disc = MeshInstance3D.new()
		disc.name = "Scorch"
		var plate := CylinderMesh.new()
		plate.top_radius = radius
		plate.bottom_radius = radius
		plate.height = 0.012
		plate.radial_segments = 18
		disc.mesh = plate
		disc.position = Vector3(0.0, 0.006, 0.0)
		disc.material_override = _ember()
		add_child(disc)
		if not ResourceLoader.exists(FLAME_CONE_SCRIPT):
			return
		var script := load(FLAME_CONE_SCRIPT) as Script
		if script == null:
			return
		var node := script.new() as Node3D
		if node == null:
			return
		node.name = "Fire"
		node.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
		node.set("external_clock", true)
		add_child(node)
		flame = node
		if flame.has_method("set_length"):
			flame.call("set_length", maxf(radius * 1.4, 0.2))
		if flame.has_method("set_active"):
			flame.call("set_active", true)

	func extinguish() -> void:
		if flame != null and flame.has_method("set_active"):
			flame.call("set_active", false)
		queue_free()

	static func _ember() -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.92, 0.36, 0.10)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.52, 0.16)
		material.emission_energy_multiplier = 1.8
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return material


func _build() -> void:
	_reset_s = maxf(float(spec.get("reset_s", 2.0)), 0.05)
	_reload_s = maxf(float(spec.get("reload_s", 0.0)), 0.0)
	_reload_left = _reload_s

	tube = BotPart.new()
	tube.name = "NapalmTube"
	tube.part_key = FightTypes.PART_WEAPON
	tube.part_kind = "weapon"
	tube.material_name = "steel"
	tube.physics_material_override = _material()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TUBE_LENGTH, TUBE_HEIGHT, TUBE_WIDTH)
	shape.shape = box
	tube.add_child(shape)
	_add_visual()

	var nose := _nose() + TUBE_PROUD - TUBE_LENGTH * 0.5
	var low := float(bot.chassis_module.floor_y()) + TUBE_CLEAR + TUBE_HEIGHT * 0.5
	tube.transform = Transform3D(Basis.IDENTITY, Vector3(nose, low, 0.0))
	bot.register_part(tube, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(tube)


func _add_visual() -> void:
	var model := PartVisuals.instantiate(str(spec.get("id", "napalm_cannon")))
	if model != null:
		model.transform = Transform3D(Basis.IDENTITY,
			Vector3(-TUBE_LENGTH * 0.5, 0.0, 0.0))
		tube.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(TUBE_LENGTH, TUBE_HEIGHT, TUBE_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	tube.add_child(mesh_instance)


## The outermost point of the hull's front armour, in bot space.
func _nose() -> float:
	if bot.chassis_module == null:
		return 0.4
	return float(bot.chassis_module.half_len()) + ChassisBase.PLATE_PROUD


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = TUBE_FRICTION
	material.bounce = 0.05
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL: holding the button walks shells out at one every `reset_s` until the
## rack is empty. A mortar worked by a tap would be a timing test on a touchscreen
## and the player cannot see the muzzle.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	_forget_dead_patches()
	_reload(dt)
	if not _pressed or jammed or _cooldown > 0.0:
		return
	if tube == null or not is_instance_valid(tube) or tube.detached:
		return
	if bot.gas_charges <= 0:
		return
	_fire()


func _fire() -> void:
	var world := _world()
	if world == null:
		return
	var muzzle := tube.global_position
	var forward := tube.global_basis.x
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		return
	forward = forward.normalized()
	var landing := muzzle + forward * float(spec.get("reach", 1.35))
	landing.y = FLOOR_Y

	var patch := FirePatch.new()
	patch.name = "Napalm%d" % _shots
	patch.attacker = bot
	patch.dps = maxf(float(spec.get("dps", 0.04)), 0.0)
	patch.burn_s = maxf(float(spec.get("fuel_s", 6.0)), 0.1)
	patch.disrupt_s = maxf(float(spec.get("disrupt_s", 1.5)), 0.0)
	patch.radius = maxf(float(spec.get("patch_radius", 0.45)), 0.05)
	world.add_child(patch)
	patch.launch(muzzle, landing)

	_patches.append(patch)
	_shots += 1
	bot.gas_charges -= 1
	_cooldown = _reset_s
	bot.emit_weapon_fired()


## One shell back into the rack every `reload_s` while it is short. A jammed or
## detached cannon loads nothing.
func _reload(dt: float) -> void:
	if _rack < 0:
		_rack = bot.gas_charges
	if _reload_s <= 0.0 or jammed or bot.gas_charges >= _rack:
		_reload_left = _reload_s
		return
	if tube == null or not is_instance_valid(tube) or tube.detached:
		return
	_reload_left -= dt
	if _reload_left <= 0.0:
		bot.gas_charges += 1
		_reload_left = _reload_s


## Where a patch lives: the node the bots are parented to, which is the fight
## world. The patch has to outlive the machine's position, not its own maker, so
## it must never be a child of the bot.
func _world() -> Node:
	var parent := bot.get_parent()
	return parent if parent != null else bot


func _forget_dead_patches() -> void:
	var live: Array[Node3D] = []
	for patch in _patches:
		if is_instance_valid(patch):
			live.append(patch)
	_patches = live


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
## The rack, which is the only thing that runs out. The AI's profile does not spin
## up, so this is read for "is there another shell" rather than for a wind-up.
func readiness() -> float:
	if jammed or tube == null or not is_instance_valid(tube) or tube.detached:
		return 0.0
	if bot.gas_charges <= 0:
		return 0.0
	return 1.0 if _cooldown <= 0.0 else clampf(1.0 - _cooldown / _reset_s, 0.0, 1.0)


func shots_fired() -> int:
	return _shots


## The patches still alight. The test reads it, and so does anything that wants
## to know whether the floor is on fire.
func patches() -> Array[Node3D]:
	_forget_dead_patches()
	return _patches.duplicate()


func burning_patches() -> int:
	var count := 0
	for patch in patches():
		if patch.call("lit"):
			count += 1
	return count


func status_text() -> String:
	if jammed:
		return "JAMMED"
	if bot.gas_charges <= 0:
		return "DRY"
	return "SHELLS %d" % maxi(bot.gas_charges, 0)


func tip_height() -> float:
	if tube == null or not is_instance_valid(tube) or tube.detached:
		return -1.0
	return maxf(tube.global_position.y, 0.0)


func set_jammed() -> void:
	jammed = true
	_pressed = false


## RESULT state. The bell puts the fires out: nothing may be left burning into
## the next fight, and a patch left alight would keep asking a frozen bot for
## damage it will not take anyway.
func freeze() -> void:
	set_jammed()
	for patch in patches():
		patch.call("extinguish")
	_patches.clear()


func state() -> Dictionary:
	return {"shells": maxi(bot.gas_charges, 0), "shots": _shots,
		"burning": burning_patches()}
