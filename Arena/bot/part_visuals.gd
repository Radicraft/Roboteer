class_name PartVisuals extends RefCounted
## Binds agent G3's .glb parts and agent G2's PBR materials to a bot.
##
## Two rules, both from docs/graphics-models-notes.md:
##
## 1. **Parent at identity.** Bot space and glTF space are numerically identical
##    (+X forward, +Y up, +Z right, origin on the axle plane), so a part is added
##    to its body with no rotation, no scale and no axis flip.
## 2. **Match materials by `resource_name`, never by surface index.** The exporter
##    drops slots a part does not use, so index 0 is `steel` on one part and
##    `livery` on the next.
##
## Everything here is presentation. If a .glb is missing the assembler falls back
## to the Stage 3 procedural meshes and the fight is unchanged.

const MODEL_ROOT := "res://assets/parts/"

## G2's materials, by slot name. `dark_metal`, `livery` and `core_glow` have no
## texture set and are built here.
const MATERIAL_FILES := {
	"steel": "res://assets/materials/brushed_steel.tres",
	"titanium": "res://assets/materials/scratched_titanium.tres",
	"hdpe": "res://assets/materials/hdpe_moulded.tres",
	"polycarbonate": "res://assets/materials/polycarbonate.tres",
	"rubber": "res://assets/materials/tyre_rubber.tres",
}

const CORE_GLOW := Color(0.10, 0.45, 0.30)
const CORE_GLOW_ENERGY := 1.6

static var _cache: Dictionary = {}          # slot -> Material (colour independent)
static var _tinted: Dictionary = {}         # slot + colour -> Material


static func reset_cache() -> void:
	_cache = {}
	_tinted = {}


static func has_model(id: String) -> bool:
	var path := PartsCatalogue.model_path(id)
	return path != "" and ResourceLoader.exists(path)


## The part's scene, or null when the model is missing. Callers must handle null:
## every part has a procedural fallback.
static func instantiate(id: String) -> Node3D:
	if not has_model(id):
		return null
	var packed := load(PartsCatalogue.model_path(id)) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node != null:
		node.name = "Model_" + id
	return node


## Socket empties, as a name -> local position dictionary. Positions are relative
## to the model root, which is the part's own origin.
static func read_sockets(node: Node) -> Dictionary:
	var out := {}
	_collect_sockets(node, node as Node3D, out)
	return out


static func _collect_sockets(node: Node, root: Node3D, out: Dictionary) -> void:
	var as_3d := node as Node3D
	if as_3d != null and as_3d != root and String(node.name).begins_with("socket_"):
		out[String(node.name)] = _local_of(as_3d, root)
	for child in node.get_children():
		_collect_sockets(child, root, out)


## Position of `node` in `root`'s frame without needing either to be in the tree.
static func _local_of(node: Node3D, root: Node3D) -> Vector3:
	var t := node.transform
	var walk := node.get_parent() as Node3D
	while walk != null and walk != root:
		t = walk.transform * t
		walk = walk.get_parent() as Node3D
	return t.origin


## Swap every surface of every mesh under `node` for the material its slot names.
## `livery` is the bot's colour; `overrides` can replace any slot (the armour
## plates bind their face material to the plate's `steel` slot this way).
static func bind(node: Node, livery: Color, overrides: Dictionary = {}) -> void:
	for mesh_instance in _mesh_instances(node):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var existing := mesh.surface_get_material(i)
			var slot := "" if existing == null else str(existing.resource_name)
			var material: Material = null
			if overrides.has(slot):
				material = overrides[slot]
			else:
				material = slot_material(slot, livery)
			if material != null:
				mesh_instance.set_surface_override_material(i, material)


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_mesh_instances(child))
	return out


## One material per slot name. `livery` and `hdpe` carry the bot's colour, so they
## are cached per colour; everything else is shared across every bot in the fight.
static func slot_material(slot: String, livery: Color) -> Material:
	match slot:
		"livery":
			return _livery_material(livery)
		"hdpe":
			# Stage 3's rule, kept: HDPE is the colourable plastic, so it takes the
			# livery. The G2 texture is deliberately neutral grey for this.
			return _tint(slot, livery, 0.85)
		"core_glow":
			return _core_material()
		"dark_metal":
			return _dark_metal_material()
		"":
			return null
		_:
			return _base_material(slot)


static func _base_material(slot: String) -> Material:
	if _cache.has(slot):
		return _cache[slot]
	var material: Material = null
	if MATERIAL_FILES.has(slot):
		var path: String = MATERIAL_FILES[slot]
		if ResourceLoader.exists(path):
			material = load(path) as Material
	if material == null:
		material = _flat(FightTypes.MATERIAL_COLOUR.get(slot, Color(0.6, 0.62, 0.66)), 0.5, 0.6)
	_cache[slot] = material
	return material


static func _tint(slot: String, colour: Color, strength: float) -> Material:
	var key := slot + "#" + colour.to_html(false) + "@%.2f" % strength
	if _tinted.has(key):
		return _tinted[key]
	var base := _base_material(slot)
	var material: StandardMaterial3D = null
	if base is StandardMaterial3D:
		material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		var was := material.albedo_color
		material.albedo_color = Color(
			lerpf(was.r, colour.r, strength), lerpf(was.g, colour.g, strength),
			lerpf(was.b, colour.b, strength), was.a)
	else:
		material = _flat(colour, 0.6, 0.0)
	_tinted[key] = material
	return material


## The livery is painted metal: a clear coat over colour, not bare steel.
static func _livery_material(colour: Color) -> Material:
	var key := "livery#" + colour.to_html(false)
	if _tinted.has(key):
		return _tinted[key]
	var material := _flat(colour, 0.42, 0.25)
	material.clearcoat_enabled = true
	material.clearcoat = 0.35
	material.clearcoat_roughness = 0.25
	_tinted[key] = material
	return material


static func _core_material() -> Material:
	if _cache.has("core_glow"):
		return _cache["core_glow"]
	var material := _flat(Color(0.12, 0.13, 0.15), 0.5, 0.0)
	material.emission_enabled = true
	material.emission = CORE_GLOW
	material.emission_energy_multiplier = CORE_GLOW_ENERGY
	_cache["core_glow"] = material
	return material


static func _dark_metal_material() -> Material:
	if _cache.has("dark_metal"):
		return _cache["dark_metal"]
	var base := _base_material("steel")
	var material: StandardMaterial3D = null
	if base is StandardMaterial3D:
		material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.albedo_color = Color(0.10, 0.105, 0.12)
		material.metallic = 0.85
		material.roughness = 0.52
	else:
		material = _flat(Color(0.10, 0.105, 0.12), 0.52, 0.85)
	_cache["dark_metal"] = material
	return material


static func _flat(colour: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## The armour material for a face, which is a G2 PBR set plus the Stage 3 reading
## rules (HDPE wears the livery, polycarbonate is translucent).
static func armour_material(material_name: String, livery: Color) -> Material:
	if material_name == "hdpe":
		return _tint("hdpe", livery, 0.85)
	return _base_material(material_name)


## Tint every mesh under a detached part, so debris reads as scrap (Stage 3).
static func tint_debris(node: Node) -> void:
	var material := _flat(FightTypes.DEBRIS_TINT, 0.8, 0.1)
	for mesh_instance in _mesh_instances(node):
		mesh_instance.material_override = material
