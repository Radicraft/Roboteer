extends Node3D
## Material test board (wave A, materials lead). docs/wave-a-materials-notes.md.
##
## Every master on known-good geometry (Arena/qa/material_board.glb, built to the mask
## contract in docs/wave-a-contracts.md by Tools/textures/make_test_board.py), under a
## self-contained showroom rig taken from docs/look/reference-study.md 3.1 (4300 K key,
## 4:1 fill, two cold rims at 1.2x key, a softbox and two strip lights that exist to be
## reflected, a box-projected reflection probe, black flags). It does not use the
## workshop stage on purpose: a material has to be judged under a light that is not
## changing under it.
##
## Materials come through PartVisuals.slot_material, the same path a machine uses, so
## what the board shows is what a part gets.
##
## Run (windowed):
##   Godot --path Arena res://qa/material_board.tscn -- --board-out=DIR [--board-shot=all|close|paint|tiers]
## Without --board-out it stays open and slowly orbits.

const BOARD := "res://qa/material_board.glb"

## Rows of [shape, slot, livery colour, paint id, label].
const ROWS := [
	[
		["board_panel", "livery", Color("#d1662b"), "", "livery, plain"],
		["board_block", "livery", Color("#2f6fd1"), "", "livery, plain"],
		["board_panel", "livery", Color("#e8b400"), "paint_hazard", "hazard"],
		["board_block", "livery", Color("#94291f"), "paint_carbon", "carbon"],
		["board_panel", "livery", Color("#2f6fd1"), "paint_chrome", "chrome"],
		["board_hub", "dark_metal", Color.WHITE, "", "powder coat"],
	],
	[
		["board_panel", "steel", Color.WHITE, "", "brushed steel"],
		["board_hub", "steel", Color.WHITE, "", "steel, turned"],
		["board_panel", "titanium", Color.WHITE, "", "titanium"],
		["board_block", "hdpe", Color("#2f9d5a"), "", "hdpe"],
		["board_hub", "rubber", Color.WHITE, "", "rubber"],
		["board_panel", "polycarbonate", Color.WHITE, "", "polycarbonate"],
	],
	[
		["board_sphere", "grey", Color.WHITE, "", "18 % grey"],
		["board_sphere", "livery", Color("#d1662b"), "", "livery sphere"],
		["board_sphere", "steel", Color.WHITE, "", "steel sphere"],
		["board_sphere", "status_light", Color.WHITE, "", "status light"],
		["board_sphere", "core_glow", Color.WHITE, "", "core glow"],
		["board_sphere", "dark_metal", Color.WHITE, "", "powder sphere"],
	],
]

var _out := ""
var _shot := "all"
var _camera: Camera3D
var _frames := 0
var _orbit := 0.0
var _shots: Array = []
## `--board-hero[=paint_id][@#livery]`: the fixture machine instead of the board.
var _hero := false
var _hero_paint := ""
var _hero_livery := ""
var _hero_centre := Vector3(0, 0.15, 0)
var _hero_radius := 0.5


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--board-out="):
			_out = a.substr(12)
		elif a.begins_with("--board-shot="):
			_shot = a.substr(13)
		elif a.begins_with("--board-hero"):
			_hero = true
			var rest := a.substr(12).trim_prefix("=")
			var at := rest.find("@")
			_hero_paint = rest if at < 0 else rest.substr(0, at)
			_hero_livery = "" if at < 0 else rest.substr(at + 1)
	_build_rig()
	if _hero:
		_build_hero()
	else:
		_build_board()
	_camera = Camera3D.new()
	_camera.fov = 27.0
	_camera.near = 0.05
	add_child(_camera)
	_camera.make_current()
	_plan_shots()
	_apply_shot(0)


func _meshes() -> Dictionary:
	var out := {}
	var packed := load(BOARD) as PackedScene
	if packed == null:
		push_error("material_board: no " + BOARD)
		return out
	var root := packed.instantiate()
	_collect(root, out)
	return out


func _collect(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D:
		out[String(node.name)] = (node as MeshInstance3D).mesh
	for c in node.get_children():
		_collect(c, out)


func _build_board() -> void:
	var meshes := _meshes()
	var spacing := 0.48
	for r in range(ROWS.size()):
		var row: Array = ROWS[r]
		for c in range(row.size()):
			var cell: Array = row[c]
			var mesh: Mesh = meshes.get(cell[0])
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "%d_%d_%s" % [r, c, cell[4]]
			var x := (c - (row.size() - 1) * 0.5) * spacing
			var z := (r - 1) * 0.55
			var y := 0.14
			if cell[0] == "board_panel":
				y = 0.16
				mi.rotation_degrees = Vector3(0, 0, 0)
			elif cell[0] == "board_block":
				y = 0.10
				mi.rotation_degrees = Vector3(0, -30, 0)
			elif cell[0] == "board_hub":
				y = 0.09
				mi.rotation_degrees = Vector3(0, 25, 0)
			elif cell[0] == "board_sphere":
				y = 0.10
			mi.position = Vector3(x, y, z)
			var material := _material(str(cell[1]), cell[2], str(cell[3]))
			material = PartVisuals.density_matched(material, PartVisuals.uv_per_metre(mesh))
			mi.material_override = material
			add_child(mi)


## The stage3 fixture's player machine, built exactly the way WorkshopStage.show_bot
## builds it (Livery.begin around setup, then frozen), under the board's showroom rig.
func _build_hero() -> void:
	var cfg: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	var config: Dictionary = ((cfg["bots"] as Array)[0] as Dictionary).duplicate(true)
	if _hero_paint != "":
		config["paint"] = _hero_paint
	if _hero_livery != "":
		config["livery"] = _hero_livery
	var bot := (load("res://bot/bot.tscn") as PackedScene).instantiate() as Node3D
	add_child(bot)
	Livery.begin(config)
	bot.call("setup", config, 0, RandomNumberGenerator.new())
	Livery.clear()
	if bot.has_method("place_at"):
		bot.call("place_at", Vector3(0, 0.0, 0), Vector3.RIGHT)
	if bot.has_method("freeze"):
		bot.call("freeze")
	_freeze(bot)
	BotMarkings.apply(bot, Color(str(config.get("livery", "#2f6fd1"))), self)
	var box := _bounds(bot)
	if box.size != Vector3.ZERO:
		_hero_centre = box.get_center()
		_hero_radius = box.size.length() * 0.5


func _freeze(node: Node) -> void:
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	for c in node.get_children():
		_freeze(c)


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "VisualInstance3D", true, false):
		var v := mi as VisualInstance3D
		if not v.is_visible_in_tree() or v is Decal:
			continue
		var b := v.global_transform * v.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _material(slot: String, colour: Color, paint: String) -> Material:
	if slot == "grey":
		var g := StandardMaterial3D.new()
		g.albedo_color = Color(0.18, 0.18, 0.18).linear_to_srgb()
		g.roughness = 0.5
		return g
	Livery.current = paint
	var m := PartVisuals.slot_material(slot, colour)
	Livery.clear()
	return m


func _build_rig() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.009, 0.011)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.ambient_light_energy = 0.05
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.1
	env.glow_intensity = 0.45
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 1.8
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Glossy near-black floor (reference-study 3.1 item 8, black flags).
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.025, 0.026, 0.03)
	fm.roughness = 0.32
	floor_mi.material_override = fm
	add_child(floor_mi)

	_spot("Key", Vector3(-1.6, 1.7, 1.6), Color(1.0, 0.84, 0.70), 7.0, 28.0, true)
	_spot("Fill", Vector3(2.2, 0.7, 1.9), Color(1.0, 0.98, 0.98), 1.75, 40.0, false)
	# Rims grazing from behind and above, narrow, so they catch top and side edges
	# and do not pool on the glossy floor in front of the camera.
	_spot("RimL", Vector3(-1.5, 1.9, -2.2), Color(0.86, 0.90, 1.0), 8.5, 14.0, false)
	_spot("RimR", Vector3(1.5, 1.9, -2.2), Color(0.86, 0.90, 1.0), 8.5, 14.0, false)

	# Softbox above frame and two strips behind: exist to be reflected.
	_emitter("Softbox", Vector3(1.6, 0.02, 0.6), Vector3(0, 2.2, 0.2), Vector3.ZERO, 3.0)
	_emitter("StripL", Vector3(2.4, 0.08, 0.08), Vector3(-1.8, 1.2, -1.6), Vector3(0, 45, 0), 4.0)
	_emitter("StripR", Vector3(2.4, 0.08, 0.08), Vector3(1.8, 1.2, -1.6), Vector3(0, -45, 0), 4.0)
	var under := OmniLight3D.new()
	under.position = Vector3(0, 2.0, 0.2)
	under.light_energy = 1.2
	under.omni_range = 3.0
	under.light_color = Color(1.0, 0.95, 0.9)
	add_child(under)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(8, 4, 8)
	probe.position = Vector3(0, 1.0, 0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


func _spot(n: String, pos: Vector3, colour: Color, energy: float, angle: float, shadow: bool) -> void:
	var s := SpotLight3D.new()
	s.name = n
	s.light_color = colour
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_range = 8.0
	s.shadow_enabled = shadow
	s.light_size = 0.15 if shadow else 0.0
	add_child(s)
	s.look_at_from_position(pos, Vector3(0, 0.12, 0))


func _emitter(n: String, size: Vector3, pos: Vector3, rot: Vector3, energy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var m := StandardMaterial3D.new()
	# Emission only: an unshaded white albedo adds 1.0 on top of the emission, which put
	# the softbox at about 4x instead of 3x and bloomed every steel plate that saw it.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.98, 0.96)
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation_degrees = rot
	add_child(mi)


## [name, eye, target]
func _plan_shots() -> void:
	var all := ["board_all", Vector3(0.0, 1.35, 3.6), Vector3(0, 0.05, 0.05)]
	var close_paint := ["close_paint", Vector3(-0.55, 0.42, 0.55), Vector3(-0.72, 0.12, -0.55)]
	var close_metal := ["close_metal", Vector3(-0.35, 0.40, 1.0), Vector3(-0.6, 0.13, 0.0)]
	var close_block := ["close_block", Vector3(-0.05, 0.40, 0.25), Vector3(-0.24, 0.10, -0.55)]
	var close_spheres := ["close_spheres", Vector3(0.0, 0.55, 2.0), Vector3(0.0, 0.1, 0.55)]
	if _hero:
		# 50 mm (27 deg vertical) at the distance that makes the machine fill ~40 % of
		# the frame height (reference-study 3.2 item 1), then two closer looks.
		var c := _hero_centre
		var d := _hero_radius / tan(deg_to_rad(13.5)) * 1.15
		_shots = [
			["hero_three_quarter", c + Vector3(d * 0.62, d * 0.30, d * 0.72), c],
			["hero_side", c + Vector3(0.1, d * 0.16, d * 0.98), c],
			# Key side. From the fill side the front plate's lobe is the fill light itself
			# and the whole wedge reads as one white highlight (measured, notes 4.2).
			["hero_close", c + Vector3(d * 0.34, d * 0.22, -d * 0.34), c + Vector3(0.1, 0.02, -0.05)],
			["hero_rear", c + Vector3(-d * 0.55, d * 0.26, d * 0.40), c],
		]
		return
	match _shot:
		"close":
			_shots = [close_paint, close_block, close_metal]
		_:
			_shots = [all, close_paint, close_block, close_metal, close_spheres]


func _apply_shot(i: int) -> void:
	var s: Array = _shots[i]
	_camera.look_at_from_position(s[1], s[2])


func _process(delta: float) -> void:
	_frames += 1
	if _out == "":
		_orbit += delta * 0.08
		var r := 3.6
		_camera.look_at_from_position(Vector3(sin(_orbit) * r, 1.3, cos(_orbit) * r), Vector3(0, 0.1, 0))
		return
	# 40 frames per shot: the probe, SSR and shadows settle; then save and move on.
	var idx := _frames / 40
	if _frames % 40 == 39:
		DirAccess.make_dir_recursive_absolute(_out)
		var img := get_viewport().get_texture().get_image()
		var path := _out.path_join("%s.png" % _shots[idx][0])
		img.save_png(path)
		print("material_board saved ", path)
		if idx + 1 >= _shots.size():
			get_tree().quit()
			return
		_apply_shot(idx + 1)
