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
const WHEEL_KEYS := ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
const ARMOUR_FACES := ["front", "sides", "rear", "top"]

## Drive motors degrade alongside the wheels they turn (brief §6).
const DRIVE_BLEED := 0.25
## Chassis hits only bite the core once the top plate is gone.
const CORE_FACTOR := 1.0

var condition: Dictionary = {}
## Queued this physics step, drained by the Bot next `_physics_process`.
var pending: Array[Dictionary] = []


func setup(from_config: Dictionary, wheel_count: int) -> void:
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
	var idx := WHEEL_KEYS.find(part_key)
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
	var idx := WHEEL_KEYS.find(part_key)
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
		core_exposed: bool) -> float:
	var break_min := float(FightTypes.BREAK_MIN.get(kind, 40.0))
	var break_max := float(FightTypes.BREAK_MAX.get(kind, 200.0))
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
		var row: Dictionary = FightTypes.MATERIAL_FACTOR.get(material_name, {}) as Dictionary
		factor = float(row.get(source, 1.0))
	elif kind == "chassis":
		factor = CORE_FACTOR
	# wheels and the flipper arm are factor 1.0 by spec.

	var severity := clampf((impulse - break_min) / maxf(break_max - break_min, 0.001), 0.0, 1.0) * factor
	if severity <= 0.0:
		return 0.0

	var before := value_for(target)
	if before <= 0.0:
		return 0.0
	var after := maxf(before - severity, 0.0)
	_set_value(target, after)
	var applied := before - after

	if WHEEL_KEYS.has(target):
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
