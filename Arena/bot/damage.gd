class_name BotDamage extends RefCounted
## The Stage 3 damage model (docs/stage3-spec.md §6, brief §6 "damage is joint
## failure"). One of these per bot. It owns the condition dictionary, which is
## exactly the FightConfig "damage" shape, and turns contact impulses into
## condition loss plus detachment decisions.
##
## Nothing here touches the scene tree: `apply_impulse_damage` is called from
## inside the physics step (from a part's `_integrate_forces`) and only records.
## The Bot flushes the recorded events, detaches parts and emits signals from
## `_physics_process`, which is the only safe place to reparent bodies.

## Part key -> ("wheels", index) | ("weapon", -1) | ("armour", "front") | ("core", -1)
## The default 4WD row. Stage 4 sets `wheel_keys` per build instead: six wheels
## give six keys, and tracks give two ("track_l", "track_r"), one per side.
const WHEEL_KEYS := ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
const ARMOUR_FACES := ["front", "sides", "rear", "top"]

## Drive motors degrade alongside the wheels they turn (brief §6).
const DRIVE_BLEED := 0.25
## Chassis hits only bite the core once the top plate is gone.
const CORE_FACTOR := 1.0

# --- wave P (D1): the damage sources the Level 35 to 95 weapons report -------
## `source` is the word a weapon passes to `apply_direct_damage`, and its only
## mechanical job is to pick a row out of the armour material's `factor` table.
## Stage 4's are "impact", "hazard", "cut" and "burn"; wave P adds three.
##
## A source with no row in that table is taken at 1.0 on every material, which is
## the ruling `flamethrower.gd` made for "burn" and the right one for both of
## these: a shock and an arc are electrical, and what the plate is made of is not
## the answer to either.
const SOURCE_SHOCK := "shock"          # the shock prod's contact current
const SOURCE_ARC := "arc"              # the tesla arc's discharge
## The drill lance. This one DOES read the table, and then ignores half of what
## it says: brief v5 section 9.5, "ignores half the armour's factor".
const SOURCE_PIERCE := "pierce"
## How much of the material's advantage (or disadvantage) the lance ignores.
const PIERCE_IGNORE := 0.5


## The drill lance's armour factor: the material's own `cut` factor moved halfway
## to 1.0. Steel's 0.4 becomes 0.7 and HDPE's 1.6 becomes 1.3, so the lance is the
## weapon that cares least what it is pointed at. `Bot.take_direct_damage` is the
## only caller, because it is the only place that knows the victim's material.
static func pierce_factor(cut_factor: float) -> float:
	return 1.0 + (cut_factor - 1.0) * (1.0 - PIERCE_IGNORE)


var condition: Dictionary = {}
## Queued this physics step, drained by the Bot next `_physics_process`.
var pending: Array[Dictionary] = []
## One key per entry in condition["wheels"], in the same order.
var wheel_keys: Array[String] = []
## Per part multiplier on BREAK_MIN and BREAK_MAX: armour thickness scales both
## (spec section 3, BREAK * (0.7 + 0.3 * thickness)), so a 4 unit plate shrugs off
## what a 1 unit plate loses a corner to.
var threshold_scale: Dictionary = {}


func setup(from_config: Dictionary, wheel_count: int, keys: Array = []) -> void:
	wheel_keys.clear()
	for i in range(wheel_count):
		wheel_keys.append(str(keys[i]) if i < keys.size()
			else (WHEEL_KEYS[i] if i < WHEEL_KEYS.size() else "wheel_x%d" % i))
	var wheels: Array = []
	var cfg_wheels: Array = from_config.get("wheels", []) as Array
	for i in range(wheel_count):
		wheels.append(float(cfg_wheels[i]) if i < cfg_wheels.size() else 1.0)
	var cfg_armour: Dictionary = from_config.get("armour", {}) as Dictionary
	var armour := {}
	for face in ARMOUR_FACES:
		armour[face] = float(cfg_armour.get(face, 1.0))
	condition = {
		"wheels": wheels,
		"weapon": float(from_config.get("weapon", 1.0)),
		"armour": armour,
		"drive": float(from_config.get("drive", 1.0)),
		"core": float(from_config.get("core", 1.0)),
	}


## Deep copy so callers cannot mutate the live state (R serialises this).
func snapshot() -> Dictionary:
	return {
		"wheels": (condition["wheels"] as Array).duplicate(),
		"weapon": condition["weapon"],
		"armour": (condition["armour"] as Dictionary).duplicate(),
		"drive": condition["drive"],
		"core": condition["core"],
	}


func value_for(part_key: String) -> float:
	var idx := wheel_keys.find(part_key)
	if idx >= 0:
		var wheels: Array = condition["wheels"]
		return float(wheels[idx]) if idx < wheels.size() else 0.0
	if part_key == FightTypes.PART_WEAPON:
		return float(condition["weapon"])
	if part_key.begins_with("armour_"):
		return float((condition["armour"] as Dictionary).get(part_key.substr(7), 0.0))
	if part_key == FightTypes.PART_CORE or part_key == "chassis":
		return float(condition["core"])
	return 1.0


func _set_value(part_key: String, v: float) -> void:
	var idx := wheel_keys.find(part_key)
	if idx >= 0:
		var wheels: Array = condition["wheels"]
		if idx < wheels.size():
			wheels[idx] = v
		return
	if part_key == FightTypes.PART_WEAPON:
		condition["weapon"] = v
		return
	if part_key.begins_with("armour_"):
		(condition["armour"] as Dictionary)[part_key.substr(7)] = v
		return
	if part_key == FightTypes.PART_CORE or part_key == "chassis":
		condition["core"] = v


## The one entry point. `kind` picks the BREAK_MIN/BREAK_MAX row
## ("wheel"|"weapon"|"armour"|"chassis"); `source` is "impact" or "hazard".
## Returns the severity applied (0.0 when the impulse was below the threshold).
func apply_impulse_damage(part_key: String, kind: String, material_name: String,
		impulse: float, source: String, position: Vector3, attacker: String,
		core_exposed: bool, extra_factor: float = 1.0) -> float:
	var scale := float(threshold_scale.get(part_key, 1.0))
	var break_min := float(FightTypes.BREAK_MIN.get(kind, 40.0)) * scale
	var break_max := float(FightTypes.BREAK_MAX.get(kind, 200.0)) * scale
	if impulse <= break_min:
		return 0.0

	# The chassis body is only damageable once the armour in front of it is
	# gone; the Bot decides that and passes `core_exposed`.
	var target := part_key
	if kind == "chassis":
		if not core_exposed:
			return 0.0
		target = FightTypes.PART_CORE

	var factor := 1.0
	if kind == "armour":
		# THE CATALOGUE, not FightTypes.MATERIAL_FACTOR. The constant table only
		# carries the four Stage 4 materials, so wave P's reinforced and reactive
		# plates would silently have read a factor of 1.0 against everything and
		# been worse than steel. `PartsCatalogue.material_factor` reads
		# `armour.material.<id>.factor` and falls back to the same constant table,
		# so the four old materials are unchanged to the decimal.
		factor = PartsCatalogue.material_factor(material_name, source)
	elif kind == "chassis":
		factor = CORE_FACTOR
	# wheels and the flipper arm are factor 1.0 by spec.

	var severity := clampf((impulse - break_min) / maxf(break_max - break_min, 0.001),
		0.0, 1.0) * factor * maxf(extra_factor, 0.0)
	if severity <= 0.0:
		return 0.0

	var before := value_for(target)
	if before <= 0.0:
		return 0.0
	var after := maxf(before - severity, 0.0)
	_set_value(target, after)
	var applied := before - after

	if wheel_keys.has(target):
		condition["drive"] = maxf(float(condition["drive"]) - applied * DRIVE_BLEED, 0.0)

	pending.append({
		"attacker": attacker,
		"part": target,
		"severity": applied,
		"position": position,
		"impulse": impulse,
		"zeroed": after <= 0.0,
		"tick": Engine.get_physics_frames(),
	})
	return applied


# ---------------------------------------------------------------------------
# Wave P: reactive armour, and the drive of a machine with no wheels
# ---------------------------------------------------------------------------
## Reactive armour's counterpunch, in newton seconds (brief v5 section 9.5). The
## plate's charge fires outward when a blow lands on it and shoves the attacker
## away; the Bot applies the impulse, because this file never touches the scene
## tree. `severity` is the condition the blow actually took off the plate, so a
## glancing hit is a nudge and a spinner's bite is a throw. Zero for every other
## material: the number is the catalogue's `knockback` and only reactive has one.
static func reactive_knockback(material_name: String, severity: float) -> float:
	if severity <= 0.0:
		return 0.0
	var charge := float(PartsCatalogue.armour_material(material_name).get("knockback", 0.0))
	if charge <= 0.0:
		return 0.0
	return charge * clampf(severity, 0.0, 1.0)


## The drive bleed for a machine with no wheels (the walker, the hover). A wheeled
## machine loses drive with its wheels, `applied * DRIVE_BLEED` at a time; one with
## no wheels has nothing to lose it through, so the Bot sends its hull hits here at
## the drive's catalogue `hull_bleed`. Returns what was taken off.
func bleed_drive(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := float(condition["drive"])
	var after := maxf(before - amount, 0.0)
	condition["drive"] = after
	return before - after


## Continuous damage that is not a blow: the saw's cut, the crusher's chew, the
## flamethrower's burn. It bypasses the impulse thresholds (there is no impulse)
## and applies `amount` scaled by the material's factor for that source, which the
## caller resolves from the catalogue. Same bookkeeping, same events, so R and the
## FX layer cannot tell the difference.
func apply_direct_damage(part_key: String, amount: float, source: String,
		position: Vector3, attacker: String, factor: float) -> float:
	if amount <= 0.0:
		return 0.0
	var target := part_key
	var severity := amount * maxf(factor, 0.0)
	if severity <= 0.0:
		return 0.0
	var before := value_for(target)
	if before <= 0.0:
		return 0.0
	var after := maxf(before - severity, 0.0)
	_set_value(target, after)
	var applied := before - after
	if wheel_keys.has(target):
		condition["drive"] = maxf(float(condition["drive"]) - applied * DRIVE_BLEED, 0.0)
	pending.append({
		"attacker": attacker,
		"part": target,
		"severity": applied,
		"position": position,
		"impulse": 0.0,
		"zeroed": after <= 0.0,
		"tick": Engine.get_physics_frames(),
	})
	return applied
