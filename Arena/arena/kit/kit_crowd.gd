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
const CROWD_DIR := "res://arena/kit/crowd/"
const STYLES := ["stylised", "human", "lights"]
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


func _init(seed_value: int = 7011, style_name: String = "stylised") -> void:
	_rng.seed = seed_value
	name = "Crowd"
	style = style_name if style_name in STYLES else "stylised"
	atlas_name = "crowd_atlas"
	if style == "human" and ResourceLoader.exists(CROWD_DIR + "crowd_atlas_human.png"):
		atlas_name = "crowd_atlas_human"
	if style == "lights":
		phone_share = 0.3
		flash_share = 0.12
		silhouettes_enabled = true
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
	if silhouette:
		if silhouettes_enabled:
			_sil.append([p, custom, tint])
	else:
		_cards.append([p, custom, tint])
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
	if not _specks.is_empty():
		speck_material = ShaderMaterial.new()
		speck_material.shader = load(SPECK_SHADER) as Shader
		speck_material.set_shader_parameter("glow_tex", load(GLOW_TEX))
		add_child(_multimesh("Specks", _speck_mesh(speck_material), _specks))


func set_excitement(value: float, flinch: bool) -> void:
	for m in [card_material, silhouette_material]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("excitement", value)
			(m as ShaderMaterial).set_shader_parameter("flinch", 1.0 if flinch else 0.0)
	if speck_material != null:
		speck_material.set_shader_parameter("excitement", value)


## A reaction that ripples out from `pos` (the machines). `age` is pushed every frame.
func react(pos: Vector3, strength: float) -> void:
	_react_age = 0.0
	for m in [card_material, silhouette_material]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("react_pos", pos)
			(m as ShaderMaterial).set_shader_parameter("react_strength", strength)


var _react_age := 100.0


func tick(delta: float) -> void:
	if _react_age > 30.0:
		return
	_react_age += delta
	for m in [card_material, silhouette_material]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("react_age", _react_age)


## Any staging uniform, on both card layers (the proof page's treatments use this).
func stage(params: Dictionary) -> void:
	for m in [card_material, silhouette_material]:
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
