class_name BuildRules extends RefCounted
## The weight budget and the legality rules, docs/stage4-spec.md section 1. This is
## the GDScript half of a rule implemented twice: `BuildRules.swift` is the other,
## and the two must agree to the gram and to the sentence.
##
## Error strings are shown to the player as they are, so they are plain sentences
## with a full stop and no em dashes.
##
## Everything here is static and pure: no scene tree, no rng, no side effects. The
## Bot validates before it assembles and logs anything it finds, but it still
## assembles (a fight must never fail to start because of a bad row in a config).

const FACES := ["front", "sides", "rear", "top"]
const MAX_UTILITY := 2
const MIN_THICKNESS := 1
const MAX_THICKNESS := 4


## Total build weight in catalogue kilograms.
static func total_weight(config: Dictionary) -> float:
	var w := category_weights(config)
	return float(w["chassis"]) + float(w["drive"]) + float(w["weapon"]) \
		+ float(w["utility"]) + float(w["armour"])


## The same total, split the way the workshop bar shows it.
static func category_weights(config: Dictionary) -> Dictionary:
	var chassis_id := str(config.get("chassis", ""))
	var drive_id := str(config.get("drive", ""))
	var weapon_id := str(config.get("weapon", ""))
	var utility_weight := 0.0
	for id in _utility_list(config):
		utility_weight += float(PartsCatalogue.utility(str(id)).get("weight", 0.0))
	var armour_weight := 0.0
	var per_face := {}
	for face in FACES:
		var w := face_weight(config, face)
		per_face[face] = w
		armour_weight += w
	return {
		"chassis": float(PartsCatalogue.chassis(chassis_id).get("weight", 0.0)),
		"drive": float(PartsCatalogue.drive(drive_id).get("weight", 0.0)),
		"weapon": float(PartsCatalogue.weapon(weapon_id).get("weight", 0.0)),
		"utility": utility_weight,
		"armour": armour_weight,
		"armour_faces": per_face,
	}


## thickness * kg_per_unit_area * face area, the catalogue's own formula.
static func face_weight(config: Dictionary, face: String) -> float:
	var entry := face_entry(config, face)
	if entry.is_empty():
		return 0.0
	var material := PartsCatalogue.armour_material(str(entry.get("material", "")))
	if material.is_empty():
		return 0.0
	return thickness_of(entry) * float(material.get("kg_per_unit_area", 0.0)) \
		* PartsCatalogue.face_area(face)


static func face_entry(config: Dictionary, face: String) -> Dictionary:
	var armour: Dictionary = config.get("armour", {}) as Dictionary
	return armour.get(face, {}) as Dictionary


static func thickness_of(entry: Dictionary) -> float:
	return clampf(float(entry.get("thickness", 1)), float(MIN_THICKNESS), float(MAX_THICKNESS))


static func _utility_list(config: Dictionary) -> Array:
	var raw: Variant = config.get("utility", [])
	return raw as Array if raw is Array else []


## Plain sentences, one per problem, in the order the builder screens present them.
## Empty means the build is legal.
static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	var chassis_id := str(config.get("chassis", ""))
	var chassis := PartsCatalogue.chassis(chassis_id)
	if chassis.is_empty():
		errors.append("Pick a chassis." if chassis_id == ""
			else "There is no chassis called \"%s\"." % chassis_id)

	var drive_id := str(config.get("drive", ""))
	var drive := PartsCatalogue.drive(drive_id)
	if drive.is_empty():
		errors.append("Pick a drive." if drive_id == ""
			else "There is no drive called \"%s\"." % drive_id)

	var weapon_id := str(config.get("weapon", ""))
	var weapon := PartsCatalogue.weapon(weapon_id)
	if weapon.is_empty():
		errors.append("Pick a weapon." if weapon_id == ""
			else "There is no weapon called \"%s\"." % weapon_id)

	# Utility slots: at most two, no duplicates, and a srimech unless the chassis
	# drives either way up.
	var utility := _utility_list(config)
	if utility.size() > MAX_UTILITY:
		errors.append("There are only two utility slots.")
	var seen := {}
	for id_variant in utility:
		var id := str(id_variant)
		if PartsCatalogue.utility(id).is_empty():
			errors.append("There is no utility part called \"%s\"." % id)
			continue
		if seen.has(id):
			errors.append("%s is fitted twice." % _name_of("utility", id))
		seen[id] = true
	if not chassis.is_empty() and not bool(chassis.get("invertible", false)) \
			and not seen.has("srimech"):
		errors.append("A %s needs a srimech." % str(chassis.get("name", chassis_id)))

	# Chassis and weapon compatibility.
	if not chassis.is_empty() and not weapon.is_empty():
		var allowed: Array = chassis.get("weapons_allowed", []) as Array
		if not allowed.is_empty() and not allowed.has(weapon_id):
			errors.append("The %s only takes %s." % [
				str(chassis.get("name", chassis_id)), _list_names("weapon", allowed)])
		var requires := str(weapon.get("requires_chassis", ""))
		if requires != "" and requires != chassis_id:
			errors.append("The %s only fits the %s." % [
				str(weapon.get("name", weapon_id)),
				str(PartsCatalogue.chassis(requires).get("name", requires))])

	# Armour: every face, a real material, thickness 1 to 4.
	for face in FACES:
		var entry := face_entry(config, face)
		if entry.is_empty() or str(entry.get("material", "")) == "":
			errors.append("The %s needs an armour material." % _face_name(face))
			continue
		var material_name := str(entry["material"])
		if PartsCatalogue.armour_material(material_name).is_empty():
			errors.append("There is no armour material called \"%s\"." % material_name)
		var raw := float(entry.get("thickness", 0))
		if raw < float(MIN_THICKNESS) or raw > float(MAX_THICKNESS) or raw != floorf(raw):
			errors.append("%s armour thickness must be between 1 and 4."
				% _face_name(face).capitalize())

	# The budget, last: it is the number the player is watching.
	var budget := PartsCatalogue.weight_budget()
	var total := total_weight(config)
	if total > budget + 0.0005:
		errors.append("Over the weight budget by %s kg." % _kg(total - budget))

	return errors


static func _face_name(face: String) -> String:
	match face:
		"front": return "front"
		"sides": return "sides"
		"rear": return "rear"
		"top": return "top"
	return face


static func _name_of(category: String, id: String) -> String:
	var row: Dictionary = PartsCatalogue._row(category, id)
	return str(row.get("name", id))


static func _list_names(category: String, ids: Array) -> String:
	var names := PackedStringArray()
	for id in ids:
		names.append(_name_of(category, str(id)).to_lower())
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	var last := names[names.size() - 1]
	names.remove_at(names.size() - 1)
	return "a " + ", a ".join(names) + " or a " + last


## "6" not "6.0", "6.4" when it matters. The builder shows these in a sentence.
static func _kg(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return "%d" % int(roundf(value))
	return "%.1f" % value


## Convenience for the workshop: is this build legal at all?
static func is_valid(config: Dictionary) -> bool:
	return validate(config).is_empty()
