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

## TEXEL DENSITY (wave V, agent V4, 2026-09-16; docs/wave-v-v4-notes.md).
##
## The owner played on the phone: "not high res enough", "house bots look blurry". Measured
## over every .glb in `assets/parts`, the UV unwraps do not share a texel density: a weapon
## or a wheel carries 1900 to 3400 texels per metre of surface, a house bot hull 810 to
## 2500, and a CHASSIS — the largest surface on the machine, 2.5 to 3.6 m2 of it — only 288
## to 434. At 0.176 UV units per metre a chassis shows less than a THIRD of one tile of
## brushed steel across its whole body: the material is not tiling, it is being blown up,
## and on the workshop stage that is 0.42 texels per screen pixel, magnified two and a half
## times. That is the blur, and it is an unwrap that does not match the rest of the kit
## rather than a texture that is too small.
##
## The fix here is the one that costs nothing in the pack: every surface gets a `uv1_scale`
## chosen from its OWN measured UV density so that it lands on TARGET_TEXELS_PER_M. The
## seamless sets in `assets/textures` are built to tile (docs/graphics-textures-notes.md
## measures their wrap seam at exactly zero), so scaling the UVs is free and is what the
## material was authored for. The proper fix is a re-unwrap in `Tools/blender/**`, which is
## agent G3's file and not this one; when that lands, these numbers converge on 1.0 and
## nothing here has to change.
##
## 1600 is the compromise, and it is a compromise: the close views (the workshop turntable
## at 2.4 m, about 860 screen pixels per metre) want about 900 to be exactly sharp and the
## fight camera at 235 pixels per metre wants about 250, and one number has to serve both.
## 1600 gives the workshop 1.9 texels per pixel, which is sharp with headroom for a pinch
## in, and leaves the fight relying on the mip chain, the normal map and the machine now
## being 19 to 25 % of the frame instead of 10 %. Raising it sharpens the workshop and
## flattens the fight; lowering it does the reverse.
const TARGET_TEXELS_PER_M := 1600.0
## The scale is snapped to one of these, so a fight builds at most this many variants of a
## material instead of one per mesh. They are ratios, not sizes: a step is a factor of
## about 1.4, which is half a mip, so the snap can never cost more than a quarter of a mip.
const UV_SCALE_STEPS: Array[float] = [0.5, 0.7, 1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0]
## At most this many triangles are measured per mesh, strided across the whole index array.
## A chassis is 11 000 triangles and the density is a ratio of two sums, so a strided 256
## is within a fraction of a percent of the exact answer and costs a millisecond instead of
## fifty. Measured ONCE per mesh resource and cached for the life of the process.
const DENSITY_SAMPLE_TRIS := 256

static var _cache: Dictionary = {}          # slot -> Material (colour independent)
static var _tinted: Dictionary = {}         # slot + colour -> Material
## mesh RID id -> UV units per metre of surface, in the mesh's own local units. Pure
## geometry, so it is NOT cleared by reset_cache(): the same .glb always answers the same.
static var _density: Dictionary = {}
## "<material instance id>@<step>" -> the same material with that uv1_scale.
static var _scaled: Dictionary = {}


static func reset_cache() -> void:
	_cache = {}
	_tinted = {}
	# The scaled variants are keyed by the instance id of a material that has just been
	# dropped, so they have to go with it. `_density` does not: it is geometry.
	_scaled = {}


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
		# One measurement per mesh, divided by this instance's own scale so a part that is
		# instanced at anything other than 1:1 still lands on the same texel density. The
		# .glb kit exports at identity today; this costs one basis read per part.
		var uv_per_m := uv_per_metre(mesh) / maxf(_node_scale(mesh_instance, node), 0.0001)
		for i in range(mesh.get_surface_count()):
			var existing := mesh.surface_get_material(i)
			var slot := "" if existing == null else str(existing.resource_name)
			var material: Material = null
			if overrides.has(slot):
				material = overrides[slot]
			else:
				material = slot_material(slot, livery)
			material = density_matched(material, uv_per_m)
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
##
## CHANGED 2026-09-16 (wave V, agent V4). This used to be `_flat(colour, 0.42, 0.25)` — a
## bare `StandardMaterial3D` with no maps at all. `livery` is 12.0 m2 of the 52 m2 of
## surface in the whole parts kit, the single largest slot there is, so the biggest area of
## every machine in the game was untextured paint: no grain, no normal, no roughness
## variation, no AO. That is most of "not high res enough" on its own, and it was already
## against the contract written down in docs/graphics-textures-notes.md ("load
## hdpe_moulded.tres, duplicate it per bot, set albedo_color = livery, and change nothing
## else"), which the `hdpe` slot three lines up has been honouring all along.
##
## `hdpe_moulded_albedo.png` is deliberately desaturated to a mean of 0.72 for exactly
## this: a StandardMaterial3D multiplies `albedo_color` by `albedo_texture`, so the moulded
## pebble grain survives as shading on top of the player's colour and a pale livery still
## has headroom. The clear coat stays on top, which is what makes it read as paint over a
## panel rather than as the raw plastic the `hdpe` slot is. Roughness is pulled to 0.62 of
## the texture (mean 0.65, so about 0.40 in the end), which is where the old flat material
## sat; the old 0.25 metallic is gone, because the clear coat is what paint's specular
## actually is and hdpe_moulded ships a constant-zero metallic map that would have
## multiplied it to nothing anyway.
static func _livery_material(colour: Color) -> Material:
	var key := "livery#" + colour.to_html(false)
	if _tinted.has(key):
		return _tinted[key]
	var material: StandardMaterial3D = null
	var base := _base_material("hdpe")
	if base is StandardMaterial3D and (base as StandardMaterial3D).albedo_texture != null:
		material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.albedo_color = colour
		material.roughness = 0.62
	else:
		# No G2 texture set on disk: the Stage 3 flat paint, exactly as it was.
		material = _flat(colour, 0.42, 0.25)
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


# ---------------------------------------------------------------- texel density

## UV units per metre of surface for one mesh, in the mesh's own local units.
##
## sqrt(total UV area / total 3D area) over a strided sample of the mesh's LARGEST surface.
## The largest surface is used rather than all of them because a part's slots share one
## unwrap: measured over the whole kit, the spread between the slots of a single .glb is
## under 2 % (`box.glb` is 0.167 to 0.176, `anvil.glb` 0.453 to 0.476), while the spread
## BETWEEN parts is eightfold. One number per mesh, cached for the life of the process.
##
## Returns 0.0 for anything with no UVs, no indices or no area, which `density_matched()`
## reads as "leave the material exactly as it was authored".
static func uv_per_metre(mesh: Mesh) -> float:
	if mesh == null:
		return 0.0
	var key := int(mesh.get_rid().get_id())
	if _density.has(key):
		return float(_density[key])
	var value := _measure_uv_per_metre(mesh)
	_density[key] = value
	return value


static func _measure_uv_per_metre(mesh: Mesh) -> float:
	# The surface is picked with surface_get_array_index_len(), which is a stored integer,
	# NOT with surface_get_arrays(), which copies every vertex of every surface out of the
	# resource. Measured on `box.glb`: five surface_get_arrays() calls to pick the biggest
	# and one to read it cost 20.6 ms; one index length per surface and one read costs
	# under 5. That difference lands at the first fight, so it is worth the two lines.
	var surface := -1
	var most := 0
	var array_mesh := mesh as ArrayMesh
	for i in range(mesh.get_surface_count()):
		var count := 0
		if array_mesh != null:
			count = array_mesh.surface_get_array_index_len(i)
		else:
			var probe: Array = mesh.surface_get_arrays(i)
			if not probe.is_empty() and probe[Mesh.ARRAY_INDEX] != null:
				count = (probe[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		if count > most:
			most = count
			surface = i
	if surface < 0 or most < 3:
		return 0.0
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_TEX_UV] == null \
			or arrays[Mesh.ARRAY_INDEX] == null:
		return 0.0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uvs.size() < verts.size():
		return 0.0
	var triangles: int = index.size() / 3
	# Stride rather than take the first N: a mesh's triangles are laid out by island, so
	# the first 256 of a chassis would all come from one panel.
	var stride := maxi(1, int(ceil(float(triangles) / float(DENSITY_SAMPLE_TRIS))))
	var area_3d := 0.0
	var area_uv := 0.0
	var t := 0
	while t < triangles:
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		area_3d += (verts[b] - verts[a]).cross(verts[c] - verts[a]).length() * 0.5
		var d1 := uvs[b] - uvs[a]
		var d2 := uvs[c] - uvs[a]
		area_uv += absf(d1.x * d2.y - d1.y * d2.x) * 0.5
		t += stride
	if area_3d <= 0.000001 or area_uv <= 0.0:
		return 0.0
	return sqrt(area_uv / area_3d)


## The uniform scale between `node` and `root`, so a mesh instanced at anything other than
## 1:1 is measured in the metres it actually occupies. The .glb kit exports every node at
## identity (checked: zero scaled nodes across all 41 parts), so this is a guard rather
## than a correction, and it costs one basis read per mesh.
static func _node_scale(node: Node3D, root: Node) -> float:
	var scale := 1.0
	var walk := node
	while walk != null and walk != root:
		var s := walk.transform.basis.get_scale()
		scale *= maxf((absf(s.x) + absf(s.y) + absf(s.z)) / 3.0, 0.0001)
		walk = walk.get_parent() as Node3D
	return scale


## The same material with `uv1_scale` chosen so this surface lands on
## TARGET_TEXELS_PER_M. Returns the material untouched when there is nothing to work
## from: no measurement, no albedo texture (the flat `core_glow` and the procedural
## fallbacks), or a scale that is already right.
##
## Public because `texel_density_test.gd` asserts against it and because bot.gd's
## `material_override` paths may want it later; it never mutates the material it is
## given, it duplicates.
static func density_matched(material: Material, uv_per_m: float) -> Material:
	if material == null or uv_per_m <= 0.0:
		return material
	var standard := material as StandardMaterial3D
	if standard == null:
		return material
	var texture := standard.albedo_texture
	if texture == null:
		return material
	var size := float(maxi(texture.get_width(), texture.get_height()))
	if size <= 1.0:
		return material
	var step := uv_scale_for(uv_per_m, size)
	if is_equal_approx(step, standard.uv1_scale.x) and is_equal_approx(step, standard.uv1_scale.y):
		return material
	var key := str(material.get_instance_id()) + "@%.2f" % step
	if _scaled.has(key):
		return _scaled[key]
	var copy := standard.duplicate() as StandardMaterial3D
	copy.uv1_scale = Vector3(step, step, standard.uv1_scale.z)
	_scaled[key] = copy
	return copy


## The snapped `uv1_scale` a surface of this UV density wants for a texture of this size.
## Split out so the test can assert the arithmetic without building materials.
static func uv_scale_for(uv_per_m: float, texture_size: float) -> float:
	if uv_per_m <= 0.0 or texture_size <= 1.0:
		return 1.0
	var want := TARGET_TEXELS_PER_M / (uv_per_m * texture_size)
	var best: float = UV_SCALE_STEPS[0]
	var best_error := INF
	for candidate in UV_SCALE_STEPS:
		# Snapped in log space: a step is a ratio, so being 1.4x too coarse and 1.4x too
		# fine have to cost the same.
		var error: float = absf(log(candidate / want))
		if error < best_error:
			best_error = error
			best = candidate
	return best
