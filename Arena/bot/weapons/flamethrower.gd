extends WeaponBase
## The flamethrower (docs/stage4-spec.md section 4): a nozzle on the nose, a cone
## of fire `reach` long, `fuel_s` seconds of gas in the bottle and no way to get
## any more of it. Everything in the cone takes `dps` a second, and a victim held
## in it for a full second has its electronics cut for `disrupt_s` (weapon or
## drive, alternating, first one chosen off the shared rng).
##
## It is the only weapon in the game that is not about impulse, so nothing about
## it is: there is no knockback, no launch, no contact. The cone is an Area3D and
## the damage goes through `bot.opponent_damage_tick`, the continuous path P2
## built for the saw and the crusher.
##
## THE FUEL IS THE WHOLE DESIGN. 20 seconds in a 90 second fight means a
## flamethrower bot has to pick its moments, and `readiness()` is the gas gauge,
## so R2's AI ("flame keeps `reach` distance and sweeps") can see it running out.
##
## FIRE DOES NOT CARE WHAT THE PLATE IS MADE OF, deliberately. The damage is
## reported with source "burn", which no armour material has a factor for, so
## every material takes it at 1.0. The catalogue's factor table is about cutting
## and impact (a spinner bounces off HDPE, a saw eats it); a burn that read the
## "cut" row would have made the flamethrower a second saw, quietly best against
## the same material and worst against the same one. This way it is the answer to
## the armour everything else is wrong about.

const NOZZLE_LEN := 0.16
const NOZZLE_HEIGHT := 0.09
const NOZZLE_WIDTH := 0.14

## The cone: a convex hull from an apex at the nozzle to a ring at `reach`.
const CONE_HALF_ANGLE := deg_to_rad(16.0)
const CONE_RING := 10

## Continuous exposure needed before the electronics go (spec section 4). Reset
## after each disruption, so a held burn disrupts once a second.
const DISRUPT_AFTER_S := 1.0
## A tick where the sensor reports nothing does not end the exposure; a real
## break does. Without this a victim bouncing on its suspension re-arms the timer.
const EXPOSURE_GRACE_S := 0.25

const FLAME_CONE_SCRIPT := "res://fx/flame_cone.gd"
## How much longer and fatter the visible fire is than the damage cone. See _add_flame.
const FLAME_VISUAL_THROW := 1.45
const FLAME_VISUAL_GIRTH := 1.5

var nozzle: BotPart = null
var cone: Area3D = null
var flame: Node3D = null

var _burning := false
var _pressed := false
var _fuel := 20.0
var _fuel_total := 20.0
## THE BOTTLE REFILLS (weapons pass, 2026-09-25). A fixed 20 s bottle in a 3 minute
## fight measured as a burner that ran 14.7 s and then never again: 2 wins in 9, never
## a stoppage. A pressure regulator now bleeds `fuel_regen` seconds of gas back into
## the bottle for every second the burner is OFF, after `REGEN_DELAY_S` of it being off,
## so the fuel is still the whole design (a held button still empties it in 20 s) but
## it is a fuel you manage, not one you spend once. 0 (or no key) is the old bottle.
const REGEN_DELAY_S := 1.0
var _fuel_regen := 0.0
var _off_s := 0.0
var _dps := 0.03
var _disrupt_s := 1.5
var _reach := 0.7
## victim bot id -> {"time": seconds in the fire, "gap": seconds since last seen}
var _exposure: Dictionary = {}
## Alternates. The FIRST one is drawn from the shared rng, which is the spec's
## "decided by the shared rng", and alternating after that means a long burn
## always takes both systems rather than rolling weapon four times.
var _next_kind := "weapon"


func _build() -> void:
	var at := socket_transform().origin
	_reach = maxf(float(spec.get("reach", 0.7)), 0.1)
	_dps = maxf(float(spec.get("dps", 0.03)), 0.0)
	_disrupt_s = maxf(float(spec.get("disrupt_s", 1.5)), 0.0)
	_fuel_total = maxf(float(spec.get("fuel_s", 20.0)), 0.1)
	_fuel = _fuel_total
	_fuel_regen = maxf(float(spec.get("fuel_regen", 0.0)), 0.0)
	if rng != null:
		_next_kind = "weapon" if rng.randf() < 0.5 else "drive"

	nozzle = BotPart.new()
	nozzle.name = "FlameNozzle"
	nozzle.part_key = FightTypes.PART_WEAPON
	nozzle.part_kind = "weapon"
	nozzle.material_name = "steel"
	nozzle.physics_material_override = _material()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(NOZZLE_LEN, NOZZLE_HEIGHT, NOZZLE_WIDTH)
	shape.shape = box
	nozzle.add_child(shape)
	_add_visual()

	# The fire itself: a cone along +X, which is the bot's forward
	# (docs/stage3-physics-notes.md section 1) and the axis FlameCone fires on.
	cone = Area3D.new()
	cone.name = "FlameCone"
	cone.collision_layer = 0
	cone.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	cone.monitorable = false
	var cone_shape := CollisionShape3D.new()
	cone_shape.shape = _cone_shape()
	cone_shape.position = Vector3(NOZZLE_LEN * 0.5, 0.0, 0.0)
	cone.add_child(cone_shape)
	nozzle.add_child(cone)
	_add_flame()

	nozzle.transform = Transform3D(Basis.IDENTITY,
		at + Vector3(NOZZLE_LEN * 0.5, 0.0, 0.0))
	bot.register_part(nozzle, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(nozzle)


func _cone_shape() -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	points.append(Vector3.ZERO)
	var radius := _reach * tan(CONE_HALF_ANGLE)
	for i in range(CONE_RING):
		var a := TAU * float(i) / float(CONE_RING)
		points.append(Vector3(_reach, sin(a) * radius, cos(a) * radius))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _add_visual() -> void:
	var model := PartVisuals.instantiate("flamethrower")
	if model != null:
		model.transform = Transform3D(Basis.IDENTITY,
			Vector3(-NOZZLE_LEN * 0.5, 0.0, 0.0))
		nozzle.add_child(model)
		PartVisuals.bind(model, bot.livery)
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(
		Vector3(NOZZLE_LEN, NOZZLE_HEIGHT, NOZZLE_WIDTH))
	mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
	nozzle.add_child(mesh_instance)


## G4's FlameCone (docs/graphics-fx-notes.md) if it is there, nothing if it is
## not: the weapon is gameplay and the fire is presentation, and a missing FX file
## must never stop a bot assembling.
func _add_flame() -> void:
	if not ResourceLoader.exists(FLAME_CONE_SCRIPT):
		return
	var script := load(FLAME_CONE_SCRIPT) as Script
	if script == null:
		return
	var node := script.new() as Node3D
	if node == null:
		return
	node.name = "Flame"
	node.position = Vector3(NOZZLE_LEN * 0.5, 0.0, 0.0)
	# Driven from the physics tick, not the frame clock, so a headless run and a
	# 120 Hz phone see the same flicker for the same fight.
	node.set("external_clock", true)
	nozzle.add_child(node)
	flame = node
	# READABILITY (weapons pass, 2026-09-25): drawn at the damage cone's reach the fire
	# was a small orange puff from the fight camera. The visible jet now runs a little
	# past the cone (the burning tail, which does no damage) and is fatter, so a burn
	# reads at phone size. The damage volume is unchanged.
	if flame.has_method("set_length"):
		flame.call("set_length", _reach * FLAME_VISUAL_THROW)
	if flame.has_method("set_girth"):
		flame.call("set_girth", FLAME_VISUAL_GIRTH)
	if flame.has_method("set_active"):
		flame.call("set_active", false)


func _material() -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = 0.35
	material.bounce = 0.05
	return material


# ---------------------------------------------------------------------------
# Input and tick
# ---------------------------------------------------------------------------
## The LEVEL: gas burns while the button is down.
func apply_input(pressed: bool, _fired: bool, _dt: float) -> void:
	_pressed = pressed


func physics_tick(dt: float) -> void:
	var want := _pressed and not jammed and _fuel > 0.0 \
		and nozzle != null and not nozzle.detached
	if want:
		_fuel = maxf(_fuel - dt, 0.0)
		_off_s = 0.0
		_burn(dt)
	else:
		_off_s += dt
		if _fuel_regen > 0.0 and _off_s >= REGEN_DELAY_S and not jammed \
				and nozzle != null and not nozzle.detached:
			_fuel = minf(_fuel + _fuel_regen * dt, _fuel_total)
		_cool(dt)
	if want != _burning:
		_burning = want
		if flame != null and flame.has_method("set_active"):
			flame.call("set_active", want)
	if flame != null and flame.has_method("step"):
		flame.call("step", dt)


func _burn(dt: float) -> void:
	var seen: Dictionary = {}
	for part in _parts_in_cone():
		bot.opponent_damage_tick(part, _dps * dt, "burn")
		var victim: Node = part.owner_bot
		if victim == null:
			continue
		var key := str(victim.get("bot_id"))
		if seen.has(key):
			continue
		seen[key] = true
		var row: Dictionary = _exposure.get(key, {"time": 0.0, "gap": 0.0, "bot": victim})
		row["time"] = float(row["time"]) + dt
		row["gap"] = 0.0
		row["bot"] = victim
		_exposure[key] = row
		if float(row["time"]) >= DISRUPT_AFTER_S:
			row["time"] = 0.0
			_disrupt(victim)
	_age(dt, seen)


## Nobody is being burned: exposure decays rather than snapping to zero, so one
## tick of the sensor blinking does not hand the victim a fresh second.
func _cool(dt: float) -> void:
	_age(dt, {})


func _age(dt: float, seen: Dictionary) -> void:
	var drop: Array[String] = []
	for key_variant in _exposure.keys():
		var key := str(key_variant)
		if seen.has(key):
			continue
		var row: Dictionary = _exposure[key]
		row["gap"] = float(row["gap"]) + dt
		if float(row["gap"]) > EXPOSURE_GRACE_S:
			drop.append(key)
		else:
			_exposure[key] = row
	for key in drop:
		_exposure.erase(key)


func _disrupt(victim: Node) -> void:
	if victim == null or not victim.has_method("disrupt"):
		return
	victim.call("disrupt", _next_kind, _disrupt_s)
	_next_kind = "drive" if _next_kind == "weapon" else "weapon"


## Every foreign body in the fire. Sorted by instance id so the order the damage
## lands in is the same in two runs of the same seed, whatever order Jolt happens
## to report the overlaps in.
func _parts_in_cone() -> Array[BotPart]:
	var out: Array[BotPart] = []
	if cone == null or nozzle == null or nozzle.detached or not cone.is_inside_tree():
		return out
	for body in cone.get_overlapping_bodies():
		var other := body as BotPart
		if other == null or other.detached or other.owner_bot == null:
			continue
		if other.owner_bot == bot:
			continue
		out.append(other)
	out.sort_custom(func(a: BotPart, b: BotPart) -> bool:
		return a.get_instance_id() < b.get_instance_id())
	return out


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func burning() -> bool:
	return _burning


func fuel_left() -> float:
	return _fuel


## True when a burst right now would burn something: a foreign machine is inside the
## cone. The AI's `sensed` profile reads it through `Bot.opponent_on_wedge`, so the
## gas goes on the other machine rather than into the air in front of it.
func opponent_on_wedge() -> bool:
	return not _parts_in_cone().is_empty()


## Seconds this victim has been in the fire without a break. The AI's "sweep"
## behaviour and the test both read it.
func exposure_of(bot_id: String) -> float:
	if not _exposure.has(bot_id):
		return 0.0
	return float((_exposure[bot_id] as Dictionary)["time"])


## The gas gauge, which is the only thing that runs out.
func readiness() -> float:
	if jammed or nozzle == null or nozzle.detached:
		return 0.0
	return clampf(_fuel / _fuel_total, 0.0, 1.0)


func status_text() -> String:
	if jammed:
		return "JAMMED"
	if _fuel <= 0.0:
		return "DRY"
	# The epsilon is load bearing: at exactly 17.000000001 s left, which is what
	# 180 ticks off a 20 s bottle actually leaves, a bare ceil() reads "FUEL 18s".
	return "FUEL %ds" % maxi(int(ceil(_fuel - 0.001)), 1)


func set_jammed() -> void:
	jammed = true
	_pressed = false
	_burning = false
	_exposure.clear()
	if flame != null and flame.has_method("set_active"):
		flame.call("set_active", false)


func freeze() -> void:
	set_jammed()


func state() -> Dictionary:
	return {"fuel": _fuel}
