class_name VenueCrowd extends Node3D
## The venue crowd (docs/wave-a-kit-notes.md, owner decision 2026-09-24: rendered person
## cards near the walls, silhouettes and small lights further back).
##
## Three MultiMeshes, whatever the size of the crowd:
##   Cards        lit person cards from the Blender atlas (crowd_card.gdshader)
##   Silhouettes  the same cards drawn flat dark, for the back of the house
##   Specks       phone screens and camera flashes (crowd_specks.gdshader), additive
##
## A venue adds rows with add_row() / add_block(), then calls commit(). Everything is
## placed from a private RandomNumberGenerator with a constant seed, so the same venue
## always seats the same people and nothing here can touch the fight's shared RNG.
## Animation is TIME in the shader plus two uniforms the kit drives (excitement, flinch).

## Crowd treatments (owner review 2026-09-24, docs/look/arenas/arenas-yard-proof.html):
##   "stylised"  the first Blender atlas (crowd_atlas.png)
##   "human"     MakeHuman-based atlas (crowd_atlas_human.png), when it has been rendered
##   "lights"    a dark house: every person a rim-lit silhouette, more phones and flashes
##   Wave C crowd options (docs/look/crowd-options.html, owner to pick):
##   "real"       A: every lit person a 3D MakeHuman mesh (vertex animation texture), facing
##                the arena, heads following the fight; silhouettes stay cards at the back
##   "broadcast"  B: cards, but the house is dark: rim-lit shapes, phones, flags, a light
##                sweep, cross-faded poses (no pops)
##   "mixed"      C: 3D people on the first rows by the wall, B's dark house behind
const CROWD_DIR := "res://arena/kit/crowd/"
const STYLES := ["stylised", "human", "lights", "real", "broadcast", "mixed"]
const PEOPLE_JSON := "res://arena/kit/crowd/crowd_people.json"
const PEOPLE_VAT := "res://arena/kit/crowd/crowd_people_vat.png"
const PERSON_SHADER := "res://arena/kit/shaders/crowd_person.gdshader"
const FLAG_SHADER := "res://arena/kit/shaders/crowd_flag.gdshader"
const GLOW_TEX := "res://fx/textures/spark_glow.png"
const CARD_SHADER := "res://arena/kit/shaders/crowd_card.gdshader"
const SPECK_SHADER := "res://arena/kit/shaders/crowd_specks.gdshader"

## Clothing and light variation. Multiplies the atlas, so it stays close to white.
const TINTS := [
	Color(1.0, 1.0, 1.0), Color(0.92, 0.95, 1.0), Color(1.0, 0.95, 0.9), Color(0.88, 0.88, 0.9),
	Color(1.05, 1.0, 0.96), Color(0.95, 1.0, 0.97), Color(0.82, 0.84, 0.88),
]

var density := 1.0
var style := "stylised"
var atlas_name := "crowd_atlas"
var arena_half := 5.1
var silhouettes_enabled := true
var specks_enabled := true
var phone_share := 0.16
var phone_size := 0.05
var phone_colour := Color(0.75, 0.85, 1.0)
var flash_share := 0.08

var _rng := RandomNumberGenerator.new()
var _cards: Array = []        # [origin: Vector3, custom: Color, tint: Color]
var _sil: Array = []
var _specks: Array = []       # [origin, custom, colour]
var _cols := 16
var _last_variant := -1
var _card_size := Vector2(1.05, 2.1)
var _feet_anchor := 0.0
var card_material: ShaderMaterial = null
var silhouette_material: ShaderMaterial = null
var speck_material: ShaderMaterial = null
var render_layers := 1
## 3D people: "" none, "all" every lit person (A), "front" the first rows only (C).
var people_mode := ""
## C: how far past the wall (metres) the 3D rows reach.
var people_front_depth := 2.2
## A: rows closer than this (metres past the wall) get the full mesh, the rest the far LOD.
var people_full_depth := 3.6
## B/C: the dark house (cards drawn as rim-lit shapes, flags, light sweep).
var broadcast := false
var flag_share := 0.025
var _people: Array = []       # [origin, yaw, custom: Color, scale: Vector3]
var _flags: Array = []        # [origin, yaw, custom: Color, colour]
var person_materials: Array = []
var flag_material: ShaderMaterial = null
var _flinch_age := 100.0
var _was_flinch := false


func _init(seed_value: int = 7011, style_name: String = "stylised") -> void:
	_rng.seed = seed_value
	name = "Crowd"
	style = style_name if style_name in STYLES else "stylised"
	atlas_name = "crowd_atlas"
	if style in ["human", "real", "broadcast", "mixed"] \
			and ResourceLoader.exists(CROWD_DIR + "crowd_atlas_human.png"):
		atlas_name = "crowd_atlas_human"
	if style == "lights":
		phone_share = 0.3
		flash_share = 0.12
		silhouettes_enabled = true
	if style == "real":
		people_mode = "all"
	elif style == "mixed":
		people_mode = "front"
	if style in ["broadcast", "mixed"]:
		broadcast = true
		phone_share = 0.24
		flash_share = 0.1
	if people_mode != "" and not ResourceLoader.exists(PEOPLE_VAT):
		people_mode = ""
	_read_layout()


## One line of people from a to b on a tread, facing the arena. `spacing` is metres
## between people; `fill` 0..1 leaves gaps (empty seats); `back` > 0 turns the row into
## silhouettes instead of lit cards.
func add_row(a: Vector3, b: Vector3, spacing: float = 0.56, fill: float = 0.92,
		silhouette: bool = false, scale: float = 1.0) -> void:
	var length := a.distance_to(b)
	var eff := spacing / maxf(density, 0.05)
	var count := int(floor(length / eff))
	if count <= 0:
		return
	var dir := (b - a) / length
	for i in range(count):
		if _rng.randf() > fill:
			continue
		var t := (float(i) + 0.5 + _rng.randf_range(-0.28, 0.28)) * eff
		var p := a + dir * t
		# Depth jitter within the tread, never across it.
		p += Vector3(-dir.z, 0.0, dir.x) * _rng.randf_range(-0.13, 0.13)
		_add_person(p, silhouette, scale)


## Several rows on stepped treads: `rows` of {a, b} dictionaries.
func add_rows(rows: Array, spacing: float = 0.56, fill: float = 0.92,
		silhouette: bool = false) -> void:
	for r in rows:
		var d: Dictionary = r
		add_row(d["a"], d["b"], spacing, fill, silhouette)


func _add_person(p: Vector3, silhouette: bool, scale: float) -> void:
	# Never the same person twice in a row: identical neighbours are what give a card
	# crowd away first.
	var v := _rng.randi_range(0, _cols - 2)
	if v >= _last_variant:
		v += 1
	_last_variant = v
	var variant := float(v)
	var phase := _rng.randf()
	var excit := _rng.randf_range(0.2, 1.0)
	var s := scale * _rng.randf_range(0.92, 1.08)
	if style == "lights":
		silhouette = true
	if _rng.randf() < 0.5:
		s = -s
	var custom := Color(variant, phase, excit, s)
	var tint: Color = TINTS[_rng.randi_range(0, TINTS.size() - 1)]
	var beyond := maxf(absf(p.x), absf(p.z)) - arena_half
	var as_3d := people_mode == "all" \
		or people_mode == "front" and not silhouette and beyond < people_front_depth
	if as_3d:
		# A: the back of the house (the card crowd's silhouettes) is 3D too, at the far LOD.
		# Near rows (by the wall) at the full mesh, the rest at the far LOD.
		_add_person_3d(p, scale, 1 if silhouette or beyond >= people_full_depth else 0)
	elif silhouette:
		if silhouettes_enabled:
			_sil.append([p, custom, tint])
	else:
		_cards.append([p, custom, tint])
	if broadcast and not as_3d and _rng.randf() < flag_share:
		_add_flag(p)
	if not specks_enabled:
		return
	var roll := _rng.randf()
	if roll < phone_share:
		var hand := p + Vector3(_rng.randf_range(-0.15, 0.15), _card_size.y * 0.8 * absf(s), 0.0)
		# A phone screen: a small warm-white sparkle point, not a lit rectangle.
		_specks.append([hand, Color(0.0, _rng.randf(), phone_size, 1.0), phone_colour])
	elif roll < phone_share + flash_share:
		var head := p + Vector3(0.0, _card_size.y * 0.75 * absf(s), 0.0)
		_specks.append([head, Color(1.0, _rng.randf(), 0.35, 1.0), Color(1.0, 0.98, 0.94)])


## Free-standing specks (distant lamps, a far crowd that is only lights).
func add_speck(p: Vector3, kind: int, size: float, colour: Color, level: float = 1.0) -> void:
	if not specks_enabled:
		return
	_specks.append([p, Color(float(kind), _rng.randf(), size, level), colour])


## A 3D person facing the arena (most of them), some turned to a neighbour.
func _add_person_3d(p: Vector3, scale: float, lod: int = 0) -> void:
	var yaw := atan2(-p.x, -p.z) + _rng.randf_range(-0.28, 0.28)
	if _rng.randf() < 0.1:
		yaw += (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.8, 1.3)
	var h := scale * _rng.randf_range(0.95, 1.05)
	var w := h * _rng.randf_range(0.92, 1.1)
	var custom := Color(_rng.randf(), _rng.randf_range(0.15, 1.0), _rng.randf_range(0.85, 1.15), _rng.randf())
	_people.append([p, yaw, custom, Vector3(w, h, w), lod])


## A flag or scarf held up over a card person (B/C).
func _add_flag(p: Vector3) -> void:
	var cols := [Color(0.75, 0.08, 0.05), Color(0.95, 0.75, 0.1), Color(0.1, 0.25, 0.8),
		Color(0.9, 0.9, 0.88), Color(0.05, 0.5, 0.25)]
	var yaw := atan2(-p.x, -p.z) + _rng.randf_range(-0.4, 0.4)
	var big := _rng.randf() < 0.35
	var size := Color(_rng.randf(), 1.0 if big else 0.0, _rng.randf_range(0.85, 1.2), _rng.randf())
	_flags.append([p + Vector3(0.0, 0.0, 0.0), yaw, size, cols[_rng.randi_range(0, cols.size() - 1)]])


func people_count() -> int:
	return _people.size()


func flag_count() -> int:
	return _flags.size()


func card_count() -> int:
	return _cards.size()


func silhouette_count() -> int:
	return _sil.size()


func speck_count() -> int:
	return _specks.size()


## Build the MultiMeshes. Call once, after every row is in.
func commit() -> void:
	var atlas := _atlas_texture()
	var emit: Texture2D = null
	if ResourceLoader.exists(CROWD_DIR + atlas_name + "_emit.png"):
		emit = load(CROWD_DIR + atlas_name + "_emit.png") as Texture2D
	var shader := load(CARD_SHADER) as Shader
	card_material = ShaderMaterial.new()
	card_material.shader = shader
	card_material.set_shader_parameter("atlas", atlas)
	if emit != null:
		card_material.set_shader_parameter("emit_atlas", emit)
	card_material.set_shader_parameter("grid", Vector2(float(_cols), 4.0))
	card_material.set_shader_parameter("card_size", _card_size)
	card_material.set_shader_parameter("feet_anchor", _feet_anchor)
	card_material.set_shader_parameter("arena_half", arena_half)
	if not _cards.is_empty():
		add_child(_multimesh("Cards", _card_mesh(card_material), _cards))
	if not _sil.is_empty():
		silhouette_material = card_material.duplicate() as ShaderMaterial
		silhouette_material.set_shader_parameter("silhouette", 1.0)
		add_child(_multimesh("Silhouettes", _card_mesh(silhouette_material), _sil))
	if broadcast:
		for m in [card_material, silhouette_material]:
			if m != null:
				(m as ShaderMaterial).set_shader_parameter("broadcast", 1.0)
	if not _people.is_empty():
		_commit_people()
	if not _flags.is_empty():
		flag_material = ShaderMaterial.new()
		flag_material.shader = load(FLAG_SHADER) as Shader
		flag_material.set_shader_parameter("arena_half", arena_half)
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.use_colors = true
		fm.use_custom_data = true
		fm.mesh = _flag_mesh(flag_material)
		fm.instance_count = _flags.size()
		for i in range(_flags.size()):
			var f: Array = _flags[i]
			fm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(f[1])), f[0]))
			fm.set_instance_custom_data(i, f[2])
			fm.set_instance_color(i, f[3])
		var fmi := MultiMeshInstance3D.new()
		fmi.name = "Flags"
		fmi.multimesh = fm
		fmi.layers = render_layers
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fmi)
	if not _specks.is_empty():
		speck_material = ShaderMaterial.new()
		speck_material.shader = load(SPECK_SHADER) as Shader
		speck_material.set_shader_parameter("glow_tex", load(GLOW_TEX))
		add_child(_multimesh("Specks", _speck_mesh(speck_material), _specks))


## The 3D people: one MultiMesh per MakeHuman person, all drawn from one VAT.
func _commit_people() -> void:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE_JSON))
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var d: Dictionary = meta
	var vat := load(PEOPLE_VAT) as Texture2D
	var shader := load(PERSON_SHADER) as Shader
	var people: Array = d["people"]
	var clips: Dictionary = d["clips"]
	var lo: Array = d["pos_min"]
	var hi: Array = d["pos_max"]
	var buckets: Array = []
	for i in range(people.size() * 2):
		buckets.append([])
	var last := -1
	for it in _people:
		var v := _rng.randi_range(0, people.size() - 2)
		if v >= last:
			v += 1
		last = v
		(buckets[v + people.size() * int(it[4])] as Array).append(it)
	for bi in range(buckets.size()):
		var items: Array = buckets[bi]
		if items.is_empty():
			continue
		var i := bi % people.size()
		var lod := bi / people.size()
		var pd: Dictionary = people[i]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("vat", vat)
		mat.set_shader_parameter("vat_size", Vector2(vat.get_width(), vat.get_height()))
		mat.set_shader_parameter("person_row", float(pd["row"]))
		mat.set_shader_parameter("pos_min", Vector3(lo[0], lo[1], lo[2]))
		mat.set_shader_parameter("pos_max", Vector3(hi[0], hi[1], hi[2]))
		mat.set_shader_parameter("fps", float(d["fps"]))
		mat.set_shader_parameter("arena_half", arena_half)
		for k in ["idle", "clap_in", "clap", "raise", "cheer"]:
			var c: Dictionary = clips[k]
			mat.set_shader_parameter("clip_" + k, Vector2(float(c["start"]), float(c["count"])))
		var fc: Dictionary = clips["flinch_in"]
		mat.set_shader_parameter("clip_flinch", Vector2(float(fc["start"]), float(fc["count"])))
		person_materials.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _person_mesh(pd, vat, lo, hi, mat, lod)
		mm.instance_count = items.size()
		for j in range(items.size()):
			var it: Array = items[j]
			var b := Basis(Vector3.UP, float(it[1])).scaled(it[3])
			mm.set_instance_transform(j, Transform3D(b, it[0]))
			mm.set_instance_custom_data(j, it[2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "People_" + str(pd["name"]) + ("_far" if lod == 1 else "")
		mmi.multimesh = mm
		mmi.layers = render_layers
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _person_mesh(pd: Dictionary, vat: Texture2D, lo: Array, hi: Array, mat: Material,
		lod: int = 0) -> ArrayMesh:
	var nv := int(pd["verts"])
	var colour: Array = pd["colour"]
	var zone: Array = pd["zone"]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(nv)
	cols.resize(nv)
	uvs.resize(nv)
	for i in range(nv):
		# Rest positions only give the mesh a sensible AABB; the shader reads the VAT.
		verts[i] = Vector3(0.0, 1.0, 0.0)
		cols[i] = Color8(int(colour[i * 3]), int(colour[i * 3 + 1]), int(colour[i * 3 + 2]))
		uvs[i] = Vector2(float(i) + 0.5, float(zone[i]) / 8.0)
	# Blender winds front faces counter-clockwise, Godot clockwise: swap two corners.
	var src: Array = pd["lod1"] if lod == 1 and pd.has("lod1") else pd["indices"]
	var idx := PackedInt32Array()
	idx.resize(src.size())
	for t in range(0, src.size(), 3):
		idx[t] = int(src[t])
		idx[t + 1] = int(src[t + 2])
		idx[t + 2] = int(src[t + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	mesh.custom_aabb = AABB(Vector3(lo[0], lo[1], lo[2]) * 1.2, (Vector3(hi[0], hi[1], hi[2]) - Vector3(lo[0], lo[1], lo[2])) * 1.2)
	return mesh


func _flag_mesh(mat: Material) -> ArrayMesh:
	# A strip 8 segments long on a pole: x 0..1 along the cloth, y 0..1 up it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	for i in range(n):
		var x0 := float(i) / n
		var x1 := float(i + 1) / n
		for q in [[x0, 0.0], [x1, 0.0], [x1, 1.0], [x0, 0.0], [x1, 1.0], [x0, 1.0]]:
			st.set_uv(Vector2(q[0], q[1]))
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(q[0], q[1], 0.0))
	# The pole: a thin strip flagged by UV.x < 0 (the shader places it at the hand).
	for q in [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0], [1.0, 1.0], [0.0, 1.0]]:
		st.set_uv(Vector2(-1.0 - q[0], q[1]))
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3(q[0], q[1], 0.0))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	mesh.custom_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
	return mesh


func _all_person_materials() -> Array:
	var out: Array = [card_material, silhouette_material]
	out.append_array(person_materials)
	return out


func set_excitement(value: float, flinch: bool) -> void:
	if flinch and not _was_flinch:
		_flinch_age = 0.0
	_was_flinch = flinch
	for m in person_materials:
		(m as ShaderMaterial).set_shader_parameter("excitement", value)
	if flag_material != null:
		flag_material.set_shader_parameter("excitement", value)
	for m in [card_material, silhouette_material]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("excitement", value)
			(m as ShaderMaterial).set_shader_parameter("flinch", 1.0 if flinch else 0.0)
	if speck_material != null:
		speck_material.set_shader_parameter("excitement", value)


## A reaction that ripples out from `pos` (the machines). `age` is pushed every frame.
func react(pos: Vector3, strength: float) -> void:
	_react_age = 0.0
	for m in _all_person_materials():
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("react_pos", pos)
			(m as ShaderMaterial).set_shader_parameter("react_strength", strength)


var _react_age := 100.0


func tick(delta: float) -> void:
	_flinch_age += delta
	if not person_materials.is_empty():
		var kit := get_parent()
		var focus := Vector3.ZERO
		if kit != null and kit.has_method("_action_point"):
			focus = kit.call("_action_point")
		for m in person_materials:
			(m as ShaderMaterial).set_shader_parameter("focus_pos", focus)
			(m as ShaderMaterial).set_shader_parameter("flinch_age", _flinch_age)
	if _react_age > 30.0:
		return
	_react_age += delta
	for m in _all_person_materials():
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("react_age", _react_age)


## Any staging uniform, on both card layers (the proof page's treatments use this).
func stage(params: Dictionary) -> void:
	for m in _all_person_materials():
		if m != null:
			for k in params.keys():
				(m as ShaderMaterial).set_shader_parameter(str(k), params[k])


func set_flash_burst(value: float) -> void:
	if speck_material != null:
		speck_material.set_shader_parameter("flash_burst", value)


func _multimesh(node_name: String, mesh: Mesh, items: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		var it: Array = items[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, it[0]))
		mm.set_instance_custom_data(i, it[1])
		mm.set_instance_color(i, it[2])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.layers = render_layers
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _card_mesh(mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var norms := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var idx := PackedInt32Array([0, 2, 1, 0, 3, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	# The shader moves every vertex; the bounds must cover the stretched, turned card.
	mesh.custom_aabb = AABB(Vector3(-2.0, -0.5, -2.0), Vector3(4.0, 5.0, 4.0))
	return mesh


func _speck_mesh(mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	var idx := PackedInt32Array([0, 2, 1, 0, 3, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	mesh.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	return mesh


func _read_layout() -> void:
	var json_path := CROWD_DIR + atlas_name + ".json"
	if not FileAccess.file_exists(json_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	_cols = int(d.get("cols", 16))
	var cell: Array = d.get("cell", [128, 256])
	var h := float(d.get("world_height_m", 2.1))
	_card_size = Vector2(h * float(cell[0]) / float(cell[1]), h)
	var anchor: Array = d.get("anchor_px", [cell[0] / 2, cell[1]])
	_feet_anchor = 1.0 - float(anchor[1]) / float(cell[1])


## The Blender atlas, or a flat placeholder when it has not been rendered yet.
func _atlas_texture() -> Texture2D:
	if ResourceLoader.exists(CROWD_DIR + atlas_name + ".png"):
		var t := load(CROWD_DIR + atlas_name + ".png") as Texture2D
		if t != null:
			return t
	var w := 32
	var h := 64
	var img := Image.create(w * _cols, h * 4, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for c in range(_cols):
		var shade := Color.from_hsv(float(c) / float(_cols), 0.35, 0.55)
		for r in range(4):
			for y in range(h):
				for x in range(w):
					var fx := float(x) / float(w) - 0.5
					var fy := 1.0 - float(y) / float(h)
					var body := absf(fx) < 0.22 and fy > 0.05 and fy < 0.72
					var head := Vector2(fx, (fy - 0.82) * 2.0).length() < 0.13
					var arms := (r == 2) and absf(absf(fx) - 0.3) < 0.06 and fy > 0.6 and fy < 0.98
					if body or head or arms:
						img.set_pixel(c * w + x, r * h + y, Color(0.75, 0.62, 0.5) if head else shade)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
