class_name PartsCatalogue extends RefCounted
## The catalogue is the contract (docs/stage4-spec.md section 1). Every part id,
## weight, stat and blurb lives in `Shared/parts.json`, which `scripts/export-pck.sh`
## copies to `Arena/data/parts.json`. Nothing in the assembler may invent a number
## that belongs here.
##
## Both files are read once per process and cached in statics: a Bot is rebuilt on
## every workshop edit, and re-parsing 25 kB of JSON per keystroke is a waste.
##
## The model manifest (`Arena/assets/parts/manifest.json`, agent G3) is cached the
## same way. It is optional: everything still assembles when the .glb files are
## absent, the bot just wears its procedural meshes.

const PARTS_PATH := "res://data/parts.json"
const MANIFEST_PATH := "res://assets/parts/manifest.json"
## Wave C fitment: where the utility parts sit on each hull (presentation only).
const FITMENT_PATH := "res://data/fitment.json"

static var _parts: Dictionary = {}
static var _manifest: Dictionary = {}
static var _loaded := false
static var _manifest_loaded := false
static var _fitment: Dictionary = {}
static var _fitment_loaded := false


static func parts() -> Dictionary:
	if not _loaded:
		_loaded = true
		_parts = _read_json(PARTS_PATH)
	return _parts


## Drop the cache. Only tests need this (they edit nothing, but a stale cache
## across two different projects in one process would be a trap worth avoiding).
static func reset_cache() -> void:
	_loaded = false
	_manifest_loaded = false
	_fitment_loaded = false
	_parts = {}
	_manifest = {}
	_fitment = {}


static func manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		_manifest = _read_json(MANIFEST_PATH)
	return _manifest


## The chassis row of Arena/data/fitment.json ({"deck": [...], "belly": {...}}), or {}.
static func fitment(chassis_id: String) -> Dictionary:
	if not _fitment_loaded:
		_fitment_loaded = true
		_fitment = _read_json(FITMENT_PATH)
	var table: Dictionary = _fitment.get("chassis", {}) as Dictionary
	return table.get(chassis_id, {}) as Dictionary


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


static func _row(category: String, id: String) -> Dictionary:
	var table: Dictionary = parts().get(category, {}) as Dictionary
	return table.get(id, {}) as Dictionary


static func chassis(id: String) -> Dictionary:
	return _row("chassis", id)


static func drive(id: String) -> Dictionary:
	return _row("drive", id)


static func weapon(id: String) -> Dictionary:
	return _row("weapon", id)


static func utility(id: String) -> Dictionary:
	return _row("utility", id)


static func ids(category: String) -> Array:
	var table: Dictionary = parts().get(category, {}) as Dictionary
	var out := table.keys()
	out.sort()
	return out


static func armour_material(name: String) -> Dictionary:
	var armour: Dictionary = parts().get("armour", {}) as Dictionary
	var table: Dictionary = armour.get("material", {}) as Dictionary
	return table.get(name, {}) as Dictionary


static func armour_materials() -> Array:
	var armour: Dictionary = parts().get("armour", {}) as Dictionary
	var out := (armour.get("material", {}) as Dictionary).keys()
	out.sort()
	return out


## Face areas are catalogue constants, not geometry: the weight formula uses them
## so that the Swift builder and the arena agree to the gram.
static func face_area(face: String) -> float:
	var armour: Dictionary = parts().get("armour", {}) as Dictionary
	var faces: Dictionary = armour.get("faces", {}) as Dictionary
	var row: Dictionary = faces.get(face, {}) as Dictionary
	return float(row.get("area", 1.0))


static func weight_budget() -> float:
	return float(parts().get("weight_budget_kg", 100.0))


## Damage factor for a material against a damage source ("impact", "hazard", "cut").
## The catalogue carries all three; FightTypes only carries the first two, which is
## why the saw reads its factor from here.
static func material_factor(name: String, source: String) -> float:
	var row: Dictionary = armour_material(name).get("factor", {}) as Dictionary
	if row.has(source):
		return float(row[source])
	var fallback: Dictionary = FightTypes.MATERIAL_FACTOR.get(name, {}) as Dictionary
	return float(fallback.get(source, 1.0))


# ---------------------------------------------------------------------------
# The model manifest (agent G3)
# ---------------------------------------------------------------------------
static func model(id: String) -> Dictionary:
	var all: Dictionary = manifest().get("parts", {}) as Dictionary
	return all.get(id, {}) as Dictionary


static func model_path(id: String) -> String:
	var row := model(id)
	if row.is_empty():
		return ""
	return str(row.get("path", ""))


## The socket positions the manifest promises, as a name -> Vector3 dictionary.
## `PartVisuals.read_sockets()` reads the same names off the instantiated scene;
## the assembly test compares the two.
static func model_sockets(id: String) -> Dictionary:
	var row := model(id)
	var raw: Dictionary = row.get("sockets", {}) as Dictionary
	var out := {}
	for key in raw.keys():
		var v: Array = raw[key]
		if v.size() >= 3:
			out[str(key)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	return out
