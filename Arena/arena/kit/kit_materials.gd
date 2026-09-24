class_name KitMaterials extends RefCounted
## The venue kit's material library (docs/wave-a-kit-notes.md). Kit models name their
## glTF materials by SLOT (docs/wave-a-contracts.md section 2 and the Blender scripts in
## Tools/blender/arena_kit/); this binds every slot to one shared material built from G2's
## PBR sets, triplanar in WORLD space so a hundred containers from one mesh do not all
## wear the same rust in the same place.
##
## One instance per VenueKit. Materials are created once and shared by every mesh that
## asks for the slot, which is what keeps the kit to a handful of pipelines.

const TEX := "res://assets/textures/"
const KIT_TEX := "res://arena/kit/textures/"

## Slot -> recipe. `tex` is a G2 set under assets/textures (albedo, normal, roughness),
## `tint` multiplies the albedo, `tile` is metres per texture repeat (triplanar).
const RECIPES := {
	"galv_steel": {"tex": "brushed_steel", "tint": Color(0.62, 0.64, 0.66), "metal": 0.85, "rough": 0.48, "tile": 1.2},
	"aluminium": {"tex": "brushed_steel", "tint": Color(0.8, 0.82, 0.84), "metal": 0.9, "rough": 0.32, "tile": 0.8},
	"dark_metal": {"tex": "brushed_steel", "tint": Color(0.1, 0.105, 0.115), "metal": 0.55, "rough": 0.58, "tile": 1.0},
	"container_paint": {"tex": "concrete_dark", "tint": Color(1.0, 1.0, 1.0), "metal": 0.25, "rough": 0.62, "tile": 1.6,
		"instance_colour": true, "rust": true},
	"rust": {"tex": "concrete_dark", "tint": Color(0.46, 0.25, 0.14), "metal": 0.35, "rough": 0.78, "tile": 1.2, "rust": true},
	"concrete": {"tex": "concrete_dark", "tint": Color(1.25, 1.22, 1.18), "metal": 0.0, "rough": 0.9, "tile": 2.0},
	"rubber": {"tex": "tyre_rubber", "tint": Color(0.5, 0.5, 0.52), "metal": 0.0, "rough": 0.85, "tile": 0.6},
	"cable": {"colour": Color(0.03, 0.03, 0.035), "metal": 0.0, "rough": 0.5},
	"wood": {"tex": "concrete_dark", "tint": Color(0.62, 0.45, 0.28), "metal": 0.0, "rough": 0.82, "tile": 0.9},
	"flight_case": {"tex": "hdpe_moulded", "tint": Color(0.07, 0.07, 0.075), "metal": 0.0, "rough": 0.6, "tile": 1.0},
	"grating": {"alpha_tex": "chainlink.png", "colour": Color(0.7, 0.72, 0.75), "metal": 0.8, "rough": 0.45, "uv_tile": Vector3(8.0, 6.0, 1.0)},
	"hazard_paint": {"chevron": true},
	"lamp_warm": {"emit": Color(1.0, 0.64, 0.3), "energy": 7.0},
	"lamp_white": {"emit": Color(0.92, 0.95, 1.0), "energy": 6.0},
	"lamp_amber": {"emit": Color(1.0, 0.55, 0.08), "energy": 4.0},
	"lamp_red": {"emit": Color(1.0, 0.1, 0.06), "energy": 5.0},
	"lamp_strip": {"emit": Color(1.0, 0.72, 0.25), "energy": 3.0},
	"sign": {"colour": Color(0.6, 0.6, 0.6), "metal": 0.2, "rough": 0.6},
	"screen": {"colour": Color(0.01, 0.01, 0.012), "metal": 0.0, "rough": 0.25},
	"glass": {"colour": Color(0.05, 0.06, 0.07), "metal": 0.0, "rough": 0.1},
}

var _cache := {}
var tier := "high"


func _init(tier_name: String = "high") -> void:
	tier = tier_name


## The shared material for a slot. Unknown slots get a neutral grey so a typo shows.
func slot(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var mat: Material = _build(name)
	_cache[name] = mat
	return mat


## A copy of `mesh` with every surface bound to its slot material. Surfaces are matched by
## the imported material's resource_name, then by the surface name.
func bind_mesh(mesh: Mesh, overrides: Dictionary = {}) -> Mesh:
	if mesh == null:
		return null
	var out: Mesh = mesh.duplicate() as Mesh
	for i in range(out.get_surface_count()):
		var slot_name := surface_slot(out, i)
		if overrides.has(slot_name):
			out.surface_set_material(i, overrides[slot_name])
		elif slot_name != "":
			out.surface_set_material(i, slot(slot_name))
	return out


static func surface_slot(mesh: Mesh, i: int) -> String:
	var name := ""
	var m := mesh.surface_get_material(i)
	if m != null:
		name = m.resource_name
	if name == "" and mesh is ArrayMesh:
		name = (mesh as ArrayMesh).surface_get_name(i)
	# Blender appends ".001" when a slot name is reused across files; a surface that is
	# already bound carries the kit's own name ("kit_<slot>").
	var dot := name.find(".")
	if dot > 0:
		name = name.substr(0, dot)
	return name.trim_prefix("kit_")


func _build(name: String) -> Material:
	var r: Dictionary = RECIPES.get(name, {"colour": Color(0.5, 0.5, 0.5)})
	if r.has("chevron"):
		return _chevron()
	var mat := StandardMaterial3D.new()
	mat.resource_name = "kit_" + name
	if r.has("emit"):
		var c: Color = r["emit"]
		mat.albedo_color = c * 0.4
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = float(r["energy"]) if tier != "low" else 1.4
		mat.roughness = 0.3
		return mat
	mat.metallic = float(r.get("metal", 0.0))
	mat.roughness = float(r.get("rough", 0.8))
	if r.has("tex"):
		var base := TEX + str(r["tex"]) + "/" + str(r["tex"])
		mat.albedo_texture = _load(base + "_albedo.png")
		mat.albedo_color = r.get("tint", Color.WHITE)
		if tier != "low":
			var n := _load(base + "_normal.png")
			if n != null:
				mat.normal_enabled = true
				mat.normal_texture = n
				mat.normal_scale = 0.8
			var ro := _load(base + "_roughness.png")
			if ro != null:
				mat.roughness_texture = ro
				mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		var tile := float(r.get("tile", 1.0))
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / tile
		mat.uv1_triplanar_sharpness = 6.0
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		mat.albedo_color = r.get("colour", Color(0.5, 0.5, 0.5))
	if r.has("alpha_tex"):
		mat.albedo_texture = _load(KIT_TEX + str(r["alpha_tex"]))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.4
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.uv1_scale = r.get("uv_tile", Vector3.ONE)
	if bool(r.get("instance_colour", false)):
		mat.vertex_color_use_as_albedo = true
	if bool(r.get("rust", false)) and tier != "low":
		# Rust bloom through the paint: G2's rust overlay as a detail layer, in world space.
		var rust := _load(TEX + "rust_spots/rust_spots_albedo.png")
		if rust != null:
			mat.detail_enabled = true
			mat.detail_albedo = rust
			mat.detail_mask = rust
			mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	return mat


func _chevron() -> Material:
	var path := "res://assets/materials/chevron.tres"
	if ResourceLoader.exists(path):
		var loaded := load(path) as StandardMaterial3D
		if loaded != null:
			var mat := loaded.duplicate() as StandardMaterial3D
			mat.resource_name = "kit_hazard_paint"
			return mat
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color(0.9, 0.72, 0.12)
	return flat


## An emissive material the caller owns and animates (gate strips, beacons).
func lamp(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour * 0.35
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy if tier != "low" else minf(energy, 1.4)
	mat.roughness = 0.3
	return mat


## A texture-mapped plate (boards, gate signs). `region` is the UV rect inside the atlas.
func plate(texture_path: String, region: Rect2, emissive: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _load(texture_path)
	mat.uv1_scale = Vector3(region.size.x, region.size.y, 1.0)
	mat.uv1_offset = Vector3(region.position.x, region.position.y, 0.0)
	mat.roughness = 0.55
	mat.metallic = 0.1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission = Color.WHITE
		mat.emission_energy_multiplier = emissive
	return mat


static func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
