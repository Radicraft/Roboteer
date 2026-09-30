class_name VenueCrowd extends Node3D
## The venue crowd (docs/wave-a-kit-notes.md; wave C: docs/wave-c-crowd-notes.md).
##
## Owner decision 2026-09-30 (docs/aaa/decisions-2026-09-30.md, item 2): option C "mix".
## Real 3D people on the rows by the rail, a dark broadcast house behind them:
##   People       3D MakeHuman people (CrowdPeopleData + crowd_person.gdshader), one
##                MultiMesh per person and detail level, drawn from one vertex animation
##                texture; stands behind the camera are skipped (see _cull)
##   Cards        picture cards (crowd_card.gdshader) for the rest of the house, darkened
##                progressively away from the 3D rows ("house" ramp, no band)
##   Silhouettes  the same cards drawn flat dark, for the back of the house
##   Flags        a few flags on poles over the dark house (crowd_flag.gdshader)
##   Specks       phone screens and camera flashes (crowd_specks.gdshader), additive
## Tiers (VenueKit sets `tier` from GraphicsQuality): high = 3D rows to ~2 m past the front
## row plus a few scattered further back; medium = the front row only; low = cards only.
##
## A venue adds rows with add_row() / add_rows(), then calls commit(). Everything is
## placed from a private RandomNumberGenerator with a constant seed, so the same venue
## always seats the same people and nothing here can touch the fight's shared RNG.
## Animation is TIME in the shaders plus uniforms the kit drives (excitement, flinch,
## reactions). Presentation only: nothing here feeds back into the fight.
##
## REACTION API (for the kit and anything that stages the show):
##   react(kind, strength = 1.0, origin = null)
##     kind "hit"     a big moment: a ripple spreads from `origin` (the machines); the keen
##                    raise their arms (some film it on a phone), others clap
##     kind "cheer"   a clear judges' decision: the whole house cheers, longer
##     kind "boo"     a close decision: most boo (fists forward and down, heads shaking),
##                    some cover their faces; the cards cover their faces
##     kind "flinch"  the arena biting (same as set_excitement's flinch)
##   `origin` is world space; null = the arena centre. `strength` 0..1.
##   VenueKit.on_crowd_reaction(key) maps its keys (big_hit, flipped, ko, endgame,
##   verdict_clear, verdict_close) onto these.

## Crowd treatments (`--roboteer-venue-crowd=` for QA; the kit's default is "mixed"):
##   "stylised"   the first Blender atlas (crowd_atlas.png, not in the export)
##   "human"      MakeHuman picture cards (crowd A, 2026-09-25)
##   "lights"     a dark house: every person a rim-lit silhouette
##   "real"       every person 3D (option A of docs/look/crowd-options.html)
##   "broadcast"  cards only, dark house, flags, sweeps (option B; the low tier of "mixed")
##   "mixed"      option C, the owner's pick
const CROWD_DIR := "res://arena/kit/crowd/"
const STYLES := ["stylised", "human", "lights", "real", "broadcast", "mixed"]
const PEOPLE_DATA := "res://arena/kit/crowd/crowd_people.res"
const PEOPLE_VAT := "res://arena/kit/crowd/crowd_people_vat.png"
const PERSON_SHADER := "res://arena/kit/shaders/crowd_person.gdshader"
const FLAG_SHADER := "res://arena/kit/shaders/crowd_flag.gdshader"
const GLOW_TEX := "res://fx/textures/spark_glow.png"
const CARD_SHADER := "res://arena/kit/shaders/crowd_card.gdshader"
const SPECK_SHADER := "res://arena/kit/shaders/crowd_specks.gdshader"
const REACT_KINDS := {"hit": 0.0, "cheer": 1.0, "boo": 2.0}

## Clothing and light variation. Multiplies the atlas, so it stays close to white.
const TINTS := [
	Color(1.0, 1.0, 1.0), Color(0.92, 0.95, 1.0), Color(1.0, 0.95, 0.9), Color(0.88, 0.88, 0.9),
	Color(1.05, 1.0, 0.96), Color(0.95, 1.0, 0.97), Color(0.82, 0.84, 0.88),
]

var density := 1.0
var style := "stylised"
## GraphicsQuality tier ("high", "medium", "low"): how much of the house is 3D.
var tier := "high"
var atlas_name := "crowd_atlas"
var arena_half := 5.1
var silhouettes_enabled := true
var specks_enabled := true
var phone_share := 0.16
var phone_size := 0.05
var phone_colour := Color(0.75, 0.85, 1.0)
var flash_share := 0.08
var render_layers := 1
## 3D rows: how far behind each stand's front row (metres) the 3D people reach (high tier),
## and the width of the zone where 3D people thin out into cards.
var people_depth := 1.9
var people_blend := 1.4
## Share of 3D people scattered into the dark house on the high tier.
var scatter_share := 0.05
## Share of the 3D people scattered into the dark house who sit on the step edge (never in
## the standing rows by the rail: a sitter's legs push through the people in front).
var seated_share := 0.35
## B/C: the dark house (cards drawn as rim-lit shapes, flags, light sweep).
var broadcast := false
var flag_share := 0.02
## "all" (A), "front" (C) or "" (cards only).
var people_mode := ""

var card_material: ShaderMaterial = null
var silhouette_material: ShaderMaterial = null
var speck_material: ShaderMaterial = null
var person_material: ShaderMaterial = null
var flag_material: ShaderMaterial = null

var _rng := RandomNumberGenerator.new()
var _cands: Array = []        # every person added: see _add_person
var _cards: Array = []        # [origin: Vector3, custom: Color, tint: Color]
var _sil: Array = []
var _specks: Array = []       # [origin, custom, colour]
var _people: Array = []       # [origin, yaw, custom: Color, scale: Vector3, lod, side]
var _flags: Array = []        # [origin, yaw, custom: Color, colour]
var _cols := 16
var _last_variant := -1
var _card_size := Vector2(1.05, 2.1)
var _feet_anchor := 0.0
var _flinch_age := 100.0
var _was_flinch := false
var _react_age := 100.0
## Culling: per person MultiMesh, the instance buffer per stand side.
var _cull: Array = []         # [{mm, mmi, stride, slices: [PackedFloat32Array x 4]}]
var _side_boxes: Array = []   # AABB per side in crowd space (empty AABB = no people)
var _vis_mask := -1
var _last_xform := Transform3D()


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
	if style == "real":
		people_mode = "all"
	elif style == "mixed":
		people_mode = "front"
	if style in ["broadcast", "mixed"]:
		broadcast = true
		phone_share = 0.22
		flash_share = 0.1
	_read_layout()


## One line of people from a to b on a tread, facing the arena. `spacing` is metres
## between people; `fill` 0..1 leaves gaps (empty seats); `silhouette` makes the row the
## dark back of the house.
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


## A person is only a candidate until commit(): whether they are 3D, a lit card or a dark
## card depends on where the stand's front row is, which is known once every row is in.
func _add_person(p: Vector3, silhouette: bool, scale: float) -> void:
	# Never the same card twice in a row: identical neighbours give a card crowd away first.
	var v := _rng.randi_range(0, _cols - 2)
	if v >= _last_variant:
		v += 1
	_last_variant = v
	var s := scale * _rng.randf_range(0.92, 1.08)
	if _rng.randf() < 0.5:
		s = -s
	_cands.append({
		"p": p, "sil": silhouette or style == "lights", "scale": scale,
		"custom": Color(float(v), _rng.randf(), _rng.randf_range(0.2, 1.0), s),
		"tint": TINTS[_rng.randi_range(0, TINTS.size() - 1)],
		"side": _side_of(p), "beyond": maxf(absf(p.x), absf(p.z)) - arena_half,
		"r": [_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()],
	})


static func _side_of(p: Vector3) -> int:
	if absf(p.x) >= absf(p.z):
		return 0 if p.x >= 0.0 else 1
	return 2 if p.z >= 0.0 else 3


## Free-standing specks (distant lamps, a far crowd that is only lights).
func add_speck(p: Vector3, kind: int, size: float, colour: Color, level: float = 1.0) -> void:
	if not specks_enabled:
		return
	_specks.append([p, Color(float(kind), _rng.randf(), size, level), colour])


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


## Sort every candidate into 3D people, lit cards and the dark house.
func _classify() -> void:
	var front := [INF, INF, INF, INF]
	for c in _cands:
		if not bool(c["sil"]):
			front[int(c["side"])] = minf(front[int(c["side"])], float(c["beyond"]))
	for i in range(4):
		if front[i] == INF:
			for c in _cands:
				if int(c["side"]) == i:
					front[i] = minf(front[i], float(c["beyond"]))
	var have_people := people_mode != "" and ResourceLoader.exists(PEOPLE_DATA) \
		and ResourceLoader.exists(PEOPLE_VAT)
	# 3D depth by tier: high = the rows by the rail with a thinning zone behind; medium =
	# the front row only; low = none.
	var depth := people_depth
	var blend := people_blend
	var scatter := scatter_share
	if tier == "medium":
		depth = 0.35
		blend = 0.0
		scatter = 0.0
	elif tier == "low":
		have_people = false
	for c in _cands:
		var rel := float(c["beyond"]) - float(front[int(c["side"])])
		var r: Array = c["r"]
		var sil := bool(c["sil"])
		var as_3d := false
		var lod := 0
		if have_people and people_mode == "all":
			as_3d = true
			lod = 0 if rel < 3.0 else 1
		elif have_people and not sil:
			var keep := 1.0 - smoothstep(depth, depth + maxf(blend, 0.001), rel)
			if rel < depth:
				keep = 1.0
			as_3d = float(r[0]) < keep or float(r[0]) < scatter
			lod = 0 if rel < depth + blend * 0.5 else 1
		elif have_people and sil and tier == "high":
			as_3d = float(r[0]) < scatter * 0.5
			lod = 1
		# How far into the dark house (drives the cards' darkness and the 3D people's dim).
		var house := 0.0
		if broadcast:
			var start := depth if tier != "low" else -0.3
			house = smoothstep(start - 0.4, start + blend + 1.8, rel)
			if sil:
				house = 1.0
		if as_3d:
			_add_person_3d(c, rel, lod, house)
		else:
			var tint: Color = c["tint"]
			tint.a = house
			if sil:
				if silhouettes_enabled:
					_sil.append([c["p"], c["custom"], tint])
			else:
				_cards.append([c["p"], c["custom"], tint])
			if broadcast and float(r[1]) < flag_share * smoothstep(0.2, 0.8, house):
				_add_flag(c["p"])
		_add_specks(c, as_3d)


func _add_specks(c: Dictionary, as_3d: bool) -> void:
	if not specks_enabled:
		return
	var p: Vector3 = c["p"]
	var s := absf(float((c["custom"] as Color).a))
	var roll := float((c["r"] as Array)[2])
	# The 3D people hold real phones (shown while they film); only the cards need specks.
	if roll < phone_share and not as_3d:
		var hand := p + Vector3(_rng.randf_range(-0.15, 0.15), _card_size.y * 0.8 * s, 0.0)
		_specks.append([hand, Color(0.0, _rng.randf(), phone_size, 1.0), phone_colour])
	elif roll >= phone_share and roll < phone_share + flash_share:
		var head := p + Vector3(0.0, _card_size.y * 0.75 * s, 0.0)
		_specks.append([head, Color(1.0, _rng.randf(), 0.35, 1.0), Color(1.0, 0.98, 0.94)])


## A 3D person facing the arena (most of them), some turned to a neighbour; some of the
## few scattered into the dark house sit on the step's edge.
func _add_person_3d(c: Dictionary, rel: float, lod: int, house: float) -> void:
	var p: Vector3 = c["p"]
	var r: Array = c["r"]
	var yaw := atan2(-p.x, -p.z) + (float(r[3]) - 0.5) * 0.56
	if float(r[4]) < 0.1:
		yaw += (1.0 if float(r[4]) < 0.05 else -1.0) * (0.8 + float(r[3]) * 0.5)
	var scale := float(c["scale"])
	var h := scale * (0.95 + 0.1 * _rng.randf())
	var w := h * (0.92 + 0.18 * _rng.randf())
	var seated := house > 0.45 and _rng.randf() < seated_share
	var phase := _rng.randf()
	if seated:
		# Sit on the step's front edge, facing the arena: forward (toward the arena) a little.
		var toward := Vector3(-p.x, 0.0, -p.z).normalized()
		p += toward * 0.22
		phase += 2.0
		yaw = atan2(-p.x, -p.z) + (float(r[3]) - 0.5) * 0.3
	var custom := Color(phase, _rng.randf_range(0.15, 1.0), house, _rng.randf())
	_people.append([p, yaw, custom, Vector3(w, h, w), lod, int(c["side"])])


## A flag on a pole over a card person (B/C).
func _add_flag(p: Vector3) -> void:
	var cols := [Color(0.75, 0.08, 0.05), Color(0.95, 0.75, 0.1), Color(0.1, 0.25, 0.8),
		Color(0.9, 0.9, 0.88), Color(0.05, 0.5, 0.25)]
	var yaw := atan2(-p.x, -p.z) + _rng.randf_range(-0.4, 0.4)
	var big := _rng.randf() < 0.35
	var size := Color(_rng.randf(), 1.0 if big else 0.0, _rng.randf_range(0.85, 1.2), _rng.randf())
	_flags.append([p, yaw, size, cols[_rng.randi_range(0, cols.size() - 1)]])


## Build the MultiMeshes. Call once, after every row is in.
func commit() -> void:
	_classify()
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
	if broadcast:
		card_material.set_shader_parameter("broadcast", 1.0)
	if not _cards.is_empty():
		add_child(_multimesh("Cards", _card_mesh(card_material), _cards))
	if not _sil.is_empty():
		silhouette_material = card_material.duplicate() as ShaderMaterial
		silhouette_material.set_shader_parameter("silhouette", 1.0)
		add_child(_multimesh("Silhouettes", _card_mesh(silhouette_material), _sil))
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


## The 3D people: one MultiMesh per MakeHuman person and detail level, one material.
## Instances are stored side by side (the four stand sides) so _cull can draw only the
## sides in front of the camera.
func _commit_people() -> void:
	var data := load(PEOPLE_DATA) as CrowdPeopleData
	var vat := load(PEOPLE_VAT) as Texture2D
	if data == null or vat == null or data.meshes.is_empty():
		return
	person_material = ShaderMaterial.new()
	person_material.shader = load(PERSON_SHADER) as Shader
	person_material.set_shader_parameter("vat", vat)
	person_material.set_shader_parameter("frames", float(data.frames))
	person_material.set_shader_parameter("pos_min", data.pos_min)
	person_material.set_shader_parameter("pos_max", data.pos_max)
	person_material.set_shader_parameter("arena_half", arena_half)
	for k in data.clips.keys():
		var key := "clip_flinch" if str(k) == "flinch_in" else "clip_" + str(k)
		person_material.set_shader_parameter(key, data.clips[k])
	var n := data.meshes.size()
	var buckets: Array = []
	for i in range(n * 2):
		buckets.append([])
	var last := -1
	for it in _people:
		var v := _rng.randi_range(0, n - 2)
		if v >= last:
			v += 1
		last = v
		(buckets[v + n * int(it[4])] as Array).append(it)
	var boxes: Array = [AABB(), AABB(), AABB(), AABB()]
	var have: Array = [false, false, false, false]
	for bi in range(buckets.size()):
		var items: Array = buckets[bi]
		if items.is_empty():
			continue
		var i := bi % n
		var lod := bi / n
		items.sort_custom(func(x: Array, y: Array) -> bool: return int(x[5]) < int(y[5]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = data.far_meshes[i] if lod == 1 else data.meshes[i]
		mm.instance_count = items.size()
		var counts := [0, 0, 0, 0]
		for j in range(items.size()):
			var it: Array = items[j]
			var b := Basis(Vector3.UP, float(it[1])).scaled(it[3])
			mm.set_instance_transform(j, Transform3D(b, it[0]))
			mm.set_instance_custom_data(j, it[2])
			var side := int(it[5])
			counts[side] += 1
			var box := AABB(it[0] + Vector3(-0.8, -0.6, -0.8), Vector3(1.6, 3.1, 1.6))
			boxes[side] = box if not have[side] else (boxes[side] as AABB).merge(box)
			have[side] = true
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "People_" + data.names[i] + ("_far" if lod == 1 else "")
		mmi.multimesh = mm
		mmi.material_override = person_material
		mmi.layers = render_layers
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		# The buffer split by side, for _cull.
		var buf := mm.buffer
		var stride := 16
		var slices: Array = []
		var at := 0
		for sd in range(4):
			slices.append(buf.slice(at * stride, (at + int(counts[sd])) * stride))
			at += int(counts[sd])
		_cull.append({"mm": mm, "mmi": mmi, "slices": slices, "counts": counts})
	_side_boxes = []
	for sd in range(4):
		_side_boxes.append(boxes[sd] if have[sd] else AABB())


## Draw only the stand sides the camera can see: each person MultiMesh's buffer is
## re-ordered visible sides first and `visible_instance_count` cuts the rest. Runs only
## when the set of visible sides changes (a camera cut or a sweep past a corner).
func _cull_sides() -> void:
	if _cull.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var mask := 15
	if cam != null:
		mask = 0
		var planes := cam.get_frustum()
		var inside := cam.global_position - cam.global_transform.basis.z * 1.0
		var xf := global_transform
		for sd in range(4):
			var box: AABB = _side_boxes[sd]
			if box.size == Vector3.ZERO:
				continue
			if _box_in_frustum(xf * box, planes, inside):
				mask |= 1 << sd
	if mask == _vis_mask:
		return
	_vis_mask = mask
	for e in _cull:
		var mm: MultiMesh = e["mm"]
		var counts: Array = e["counts"]
		var slices: Array = e["slices"]
		var buf := PackedFloat32Array()
		var shown := 0
		for sd in range(4):
			if mask & (1 << sd):
				buf.append_array(slices[sd])
				shown += int(counts[sd])
		for sd in range(4):
			if not (mask & (1 << sd)):
				buf.append_array(slices[sd])
		mm.buffer = buf
		mm.visible_instance_count = shown
		(e["mmi"] as MultiMeshInstance3D).visible = shown > 0


static func _box_in_frustum(box: AABB, planes: Array, inside: Vector3) -> bool:
	for pl in planes:
		var plane: Plane = pl
		# Which side of the plane is "in" is taken from a point just ahead of the lens.
		var sign := 1.0 if plane.distance_to(inside) >= 0.0 else -1.0
		# The box is out if every corner is on the far side of any one plane.
		var any_in := false
		for k in range(8):
			if plane.distance_to(box.get_endpoint(k)) * sign >= 0.0:
				any_in = true
				break
		if not any_in:
			return false
	return true


func people_drawn() -> int:
	var n := 0
	for e in _cull:
		var mm: MultiMesh = e["mm"]
		n += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	return n


func _all_materials() -> Array:
	var out: Array = []
	for m in [card_material, silhouette_material, person_material]:
		if m != null:
			out.append(m)
	return out


func set_excitement(value: float, flinch: bool) -> void:
	if flinch and not _was_flinch:
		_flinch_age = 0.0
	_was_flinch = flinch
	for m in _all_materials():
		(m as ShaderMaterial).set_shader_parameter("excitement", value)
	for m in [card_material, silhouette_material]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("flinch", 1.0 if flinch else 0.0)
	if flag_material != null:
		flag_material.set_shader_parameter("excitement", value)
	if speck_material != null:
		speck_material.set_shader_parameter("excitement", value)


## The crowd reacts (see REACTION API at the top). `origin`: world position, null = the
## arena centre.
func react(kind: String, strength: float = 1.0, origin: Variant = null) -> void:
	if kind == "flinch":
		_flinch_age = 0.0
		return
	var pos: Vector3 = to_global(Vector3.ZERO) if is_inside_tree() else Vector3.ZERO
	if origin is Vector3:
		pos = origin
	_react_age = 0.0
	for m in _all_materials():
		(m as ShaderMaterial).set_shader_parameter("react_pos", pos)
		(m as ShaderMaterial).set_shader_parameter("react_strength", clampf(strength, 0.0, 1.0))
		(m as ShaderMaterial).set_shader_parameter("react_kind", float(REACT_KINDS.get(kind, 0.0)))
		(m as ShaderMaterial).set_shader_parameter("react_age", 0.0)


func tick(delta: float) -> void:
	_flinch_age += delta
	if is_inside_tree():
		var xf := global_transform
		if xf != _last_xform:
			_last_xform = xf
			var to_arena := Projection(xf.affine_inverse())
			for m in _all_materials():
				(m as ShaderMaterial).set_shader_parameter("world_to_arena", to_arena)
			if flag_material != null:
				flag_material.set_shader_parameter("world_to_arena", to_arena)
	if person_material != null:
		var kit := get_parent()
		var focus := to_global(Vector3.ZERO) if is_inside_tree() else Vector3.ZERO
		if kit != null and kit.has_method("_action_point"):
			var ap: Variant = kit.call("_action_point")
			if ap is Vector3 and ap != Vector3.ZERO:
				focus = ap
		person_material.set_shader_parameter("focus_pos", focus)
		person_material.set_shader_parameter("flinch_age", _flinch_age)
		_cull_sides()
	if _react_age > 30.0:
		return
	_react_age += delta
	for m in _all_materials():
		(m as ShaderMaterial).set_shader_parameter("react_age", _react_age)


## Any staging uniform, on every crowd layer (venues and the menu stage use this).
func stage(params: Dictionary) -> void:
	for m in _all_materials():
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


## The Blender atlas, or a flat placeholder when it has not been rendered (or exported).
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
