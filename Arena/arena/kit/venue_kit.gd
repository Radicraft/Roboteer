class_name VenueKit extends Node3D
## THE VENUE KIT (wave A; docs/wave-a-kit-notes.md, docs/wave-a-contracts.md section 2).
##
## One instance of res://arena/kit/venue_kit.tscn sits under each arena scene as the
## child "VenueKit" and builds everything OUTSIDE the fight: the stands and the crowd,
## the flood towers and their light, the big screen, the fighters' gates with their pyro,
## the ground and the night sky, the dust in the air and the grime on the floor. Which
## venue it builds is `venue`; the layout lives in res://arena/kit/venues/<venue>.gd,
## which only calls the placement API below.
##
## THE RULES (the tests assert them):
##   1. Nothing here collides. No bodies, no areas, no shapes: pure VisualInstance3D.
##   2. Nothing here reads or writes the fight's RNG or runs on the physics tick. It runs
##      in _process and on the GPU; its own randomness is a constant-seeded private RNG.
##   3. It only READS the arena (size, escalated(), the hazard_fx signal) and the fight
##      (bots, names, clock). The fight result is bit-identical with or without the kit
##      (Arena/tests/venue_kit_test.gd runs the Yard fixture both ways and compares).
##   4. Every piece scales by GraphicsQuality tier: fewer and thinner cards, fewer real
##      lights, fewer particles, no live feed. Nothing in the kit carries hazard
##      information, so dropping any of it can never hide a warning.

@export var venue := "yard"
## "stylised", "human" or "lights" (VenueCrowd.STYLES). The owner picks on the proof page.
@export var crowd_style := "stylised"

## Kit geometry also renders on this layer, so a camera can leave the venue out.
const RENDER_LAYER_VENUE_BIT := 10
const RENDER_LAYERS := 1 | (1 << RENDER_LAYER_VENUE_BIT)
const MODELS_DIR := "res://arena/kit/models/"
const VENUES_DIR := "res://arena/kit/venues/"
const KIT_TEX := "res://arena/kit/textures/"
const SKY_SHADER := "res://arena/kit/shaders/sky_dome.gdshader"
const QUALITY_SCRIPT := "res://render/graphics_quality.gd"

## Real (unshadowed) lights the kit may add per tier. The arena's own key, fill and any
## hazard lights are the hazards lead's and are not counted here.
const LIGHT_BUDGET := {"high": 4, "medium": 2, "low": 0}
## Share of crowd cards kept per tier ("cards thinner on older phones").
const CROWD_DENSITY := {"high": 1.0, "medium": 0.6, "low": 0.3}

## Rough stand-ins for any model that has not been exported yet, so a venue lays out
## before its Blender pieces land. Size in metres; origin at the base centre.
const PLACEHOLDER := {
	"stand_scaffold_bay": Vector3(2.0, 3.1, 4.5),
	"stand_scaffold_endcap": Vector3(0.1, 3.1, 4.5),
	"container_20ft": Vector3(6.06, 2.59, 2.44),
	"container_20ft_open": Vector3(6.06, 2.59, 2.44),
	"flood_tower": Vector3(1.2, 9.9, 1.2),
	"stair_scaffold": Vector3(4.0, 3.0, 1.0),
	"fence_panel": Vector3(2.4, 2.0, 0.1),
	"crowd_barrier": Vector3(2.0, 1.2, 0.6),
	"entrance_gate": Vector3(5.0, 3.6, 4.0),
	"truss_span_2m": Vector3(2.0, 0.3, 0.3),
	"truss_corner": Vector3(0.3, 0.3, 0.3),
	"truss_tower_leg": Vector3(0.3, 6.0, 0.3),
	"moving_head": Vector3(0.35, 0.6, 0.35),
	"screen_frame": Vector3(5.1, 3.0, 0.3),
	"beacon": Vector3(0.16, 0.3, 0.16),
	"pyro_launcher": Vector3(0.5, 0.62, 0.5),
	"flight_case_stack": Vector3(1.2, 1.3, 0.8),
	"cable_drum": Vector3(0.9, 1.2, 1.2),
	"scrap_pile_a": Vector3(3.0, 1.6, 2.0),
	"scrap_pile_b": Vector3(3.0, 1.8, 2.0),
	"crane_skyline": Vector3(4.0, 18.0, 4.0),
	"camera_crane": Vector3(3.0, 2.2, 1.0),
	# Not a Blender piece: the far-field container, a 12-triangle box for the skyline
	# stacks 24 to 44 m out, where corrugation is below a pixel.
	"container_far": Vector3(6.06, 2.59, 2.44),
}

## Tests and QA only: force a tier regardless of the renderer.
static var force_tier := ""
## Tests only: every VenueKit removes itself before building (the "without the kit" run).
static var disabled := false

var tier := "high"
var arena: Node3D = null
var mats: KitMaterials = null
var crowd: VenueCrowd = null
## How bright painted boards read (albedo and glow), 1.0 = as authored.
var board_level := 1.0
## A venue's staging of the crowd shader (VenueCrowd.stage), applied after commit.
var crowd_staging := {}
## A venue may hand the intro wave some flyover poses.
var intro_marks: Array[Transform3D] = []

var _built := false
var _models := {}
var _batches := {}              # model -> {"xforms": [], "colours": [], "shadow": bool}
var _lights: Array = []         # [{light, base}]
var _flicker: Array = []        # [{light or material, base, phase}]
var _beams: Array = []          # [{mesh, base}]
var _pyro := {}                 # group -> [GPUParticles3D]
var _pyro_lights := {}          # group -> [OmniLight3D]
var _gate_strips: Array = []    # [StandardMaterial3D] by side
var _heads: Array = []          # [{yoke, head, beam, phase, base_yaw}]
var _screens: Array = []
var _grime_items: Array = []
var _excitement := 0.12
var _base_excitement := 0.12
var _flinch_s := 0.0
var _flash := 0.0
var _entrance_t := -1.0
var _entrance_side := 0
var _endgame_seen := false
var _t := 0.0
var _qa := {}


func _ready() -> void:
	add_to_group("venue_kit")
	_read_qa_args()
	if _qa.has("off") or disabled:
		queue_free()
		return
	# The arena builds itself in ITS _ready, which runs after this one: wait for it.
	call_deferred("_build")


# ---------------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------------
func _build() -> void:
	if _built or not is_inside_tree():
		return
	_built = true
	arena = get_parent() as Node3D
	tier = _resolve_tier()
	mats = KitMaterials.new(tier)
	if _qa.has("crowd"):
		crowd_style = str(_qa["crowd"])
	crowd = VenueCrowd.new(hash(venue) & 0x7fffffff, crowd_style)
	crowd.arena_half = arena_half() + FightTypes.WALL_THICKNESS * 0.5
	crowd.density = float(CROWD_DENSITY.get(tier, 0.3))
	crowd.silhouettes_enabled = tier != "low" or crowd_style == "lights"
	crowd.specks_enabled = tier != "low"
	crowd.render_layers = RENDER_LAYERS
	var path := VENUES_DIR + venue + ".gd"
	if ResourceLoader.exists(path):
		var script := load(path) as GDScript
		if script != null:
			script.call("build", self)
	_commit_batches()
	_commit_grime()
	crowd.commit()
	crowd.stage(crowd_staging)
	add_child(crowd)
	_set_layers(self)
	if arena != null and arena.has_signal("hazard_fx"):
		arena.connect("hazard_fx", _on_hazard_fx)
	set_process(true)


func _resolve_tier() -> String:
	if force_tier != "":
		return force_tier
	if _qa.has("tier"):
		return str(_qa["tier"])
	var script := load(QUALITY_SCRIPT) as GDScript
	if script == null:
		return "high"
	var q: Node = script.call("resolve", self)
	if q == null:
		return "high"
	var t := str(q.call("tier"))
	# resolve() hands back a private instance when there is no autoload; free it.
	if not q.is_inside_tree():
		q.free()
	return t


func arena_half() -> float:
	if arena != null and arena.has_method("arena_half_extent"):
		return float(arena.call("arena_half_extent"))
	return FightTypes.ARENA_SIZE * 0.5


## The parts of a kit model: [[mesh (materials bound), local Transform3D, node name]].
func model_parts(model: String) -> Array:
	if _models.has(model):
		return _models[model]
	var parts: Array = []
	var path := MODELS_DIR + model + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var root := scene.instantiate() as Node3D
			_collect_meshes(root, Transform3D.IDENTITY, parts, true)
			root.free()
	if parts.is_empty():
		var size: Vector3 = PLACEHOLDER.get(model, Vector3.ONE)
		var box := BoxMesh.new()
		box.size = size
		box.material = mats.slot("container_paint" if model == "container_far" else "dark_metal")
		parts.append([box, Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), model])
	_models[model] = parts
	return parts


func has_model(model: String) -> bool:
	return ResourceLoader.exists(MODELS_DIR + model + ".glb")


func _collect_meshes(node: Node, parent_xf: Transform3D, out: Array, is_root: bool) -> void:
	var xf := parent_xf
	var n3 := node as Node3D
	if n3 != null and not is_root:
		xf = parent_xf * n3.transform
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append([mats.bind_mesh(mi.mesh), xf, str(mi.name)])
	for c in node.get_children():
		_collect_meshes(c, xf, out, false)


## One model at one place, as its own MeshInstance3D(s). For a handful of pieces.
func place(model: String, xf: Transform3D, overrides: Dictionary = {},
		shadow: bool = false) -> Node3D:
	var holder := Node3D.new()
	holder.name = model.to_pascal_case()
	holder.transform = xf
	for p in model_parts(model):
		var part: Array = p
		var mi := MeshInstance3D.new()
		mi.name = str(part[2])
		var mesh: Mesh = part[0]
		if not overrides.is_empty():
			mesh = _override_mesh(mesh, overrides)
		mi.mesh = mesh
		mi.transform = part[1]
		mi.cast_shadow = _shadow_setting(shadow)
		holder.add_child(mi)
	add_child(holder)
	return holder


func _override_mesh(mesh: Mesh, overrides: Dictionary) -> Mesh:
	var out: Mesh = mesh.duplicate() as Mesh
	for i in range(out.get_surface_count()):
		var s := KitMaterials.surface_slot(mesh, i)
		if overrides.has(s):
			out.surface_set_material(i, overrides[s])
	return out


## Many copies of one model: batched into one MultiMesh per model part at commit, which
## is what keeps a whole stand to a few draw calls. `colour` tints `container_paint`.
func batch(model: String, xf: Transform3D, colour: Color = Color.WHITE, shadow: bool = false) -> void:
	if not _batches.has(model):
		_batches[model] = {"xforms": [], "colours": [], "shadow": shadow}
	var b: Dictionary = _batches[model]
	(b["xforms"] as Array).append(xf)
	(b["colours"] as Array).append(colour)


func _commit_batches() -> void:
	for model in _batches.keys():
		var b: Dictionary = _batches[model]
		var xforms: Array = b["xforms"]
		var colours: Array = b["colours"]
		for p in model_parts(str(model)):
			var part: Array = p
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = part[0]
			mm.instance_count = xforms.size()
			var local: Transform3D = part[1]
			for i in range(xforms.size()):
				mm.set_instance_transform(i, (xforms[i] as Transform3D) * local)
				mm.set_instance_color(i, colours[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [str(model).to_pascal_case(), str(part[2])]
			mmi.multimesh = mm
			mmi.cast_shadow = _shadow_setting(bool(b["shadow"]))
			add_child(mmi)
	_batches.clear()


func _shadow_setting(want: bool) -> GeometryInstance3D.ShadowCastingSetting:
	if want and tier == "high":
		return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _set_layers(node: Node) -> void:
	var vi := node as VisualInstance3D
	if vi != null and not (vi is Light3D) and not (vi is ReflectionProbe):
		vi.layers = RENDER_LAYERS
	for c in node.get_children():
		# The screen's own SubViewports are separate worlds of UI; leave them be.
		if c is SubViewport:
			continue
		_set_layers(c)


# ---------------------------------------------------------------------------------
# Pieces with behaviour
# ---------------------------------------------------------------------------------
## A flood tower at `xf` whose lamp head aims at `target`. `real_light` asks for a
## SpotLight3D (granted while the tier's budget lasts); the lens glare and the beam card
## are there on every tier but low.
func add_flood(xf: Transform3D, target: Vector3, real_light: bool, colour: Color = Color(1.0, 0.62, 0.3),
		energy: float = 5.0, flicker: bool = false) -> void:
	place("flood_tower", xf, {}, false)
	var head := xf * Vector3(0.0, 9.25, 0.45)   # lamp_array_centre in flood_tower.glb
	var lamp_glare := colour.lerp(Color.WHITE, 0.35)
	for i in range(6):
		var off := xf.basis * Vector3((float(i % 3) - 1.0) * 0.42, (0.5 - float(i / 3)) * 0.42 + 0.0, 0.25)
		crowd.add_speck(head + off, 2, 0.9, lamp_glare, 2.2)
	if tier != "low":
		# The beam dies out in the air above the floor: a cone that reached the floor drew
		# a grey disc on it. The floor pool is the light's job, not the card's.
		_add_beam(head, target.lerp(head, 0.4), 0.5, 2.0, colour, 0.05)
	if real_light and _lights.size() < int(LIGHT_BUDGET.get(tier, 0)):
		var spot := SpotLight3D.new()
		spot.name = "FloodLight"
		spot.light_color = colour
		spot.light_energy = energy
		spot.spot_range = head.distance_to(target) * 1.8
		spot.spot_angle = 34.0
		spot.spot_attenuation = 0.6
		spot.spot_angle_attenuation = 0.8
		spot.shadow_enabled = false
		spot.light_specular = 0.6
		add_child(spot)
		spot.look_at_from_position(head, target, Vector3.UP)
		_lights.append({"light": spot, "base": energy})
		if flicker:
			_flicker.append({"light": spot, "base": energy, "phase": 0.37})


## A real omni light, within the tier's light budget (practicals under screens, gates).
func add_practical(pos: Vector3, colour: Color, energy: float, light_range: float) -> OmniLight3D:
	if _lights.size() >= int(LIGHT_BUDGET.get(tier, 0)):
		return null
	var o := OmniLight3D.new()
	o.name = "Practical"
	o.light_color = colour
	o.light_energy = energy
	o.omni_range = light_range
	o.omni_attenuation = 1.2
	o.shadow_enabled = false
	o.position = pos
	add_child(o)
	_lights.append({"light": o, "base": energy})
	return o


func _add_beam(from: Vector3, to: Vector3, r0: float, r1: float, colour: Color, strength: float) -> MeshInstance3D:
	var b := VenueFx.beam(from, to, r0, r1, colour, strength)
	add_child(b)
	_beams.append({"mesh": b, "base": strength})
	return b


## The big screen. `xf` puts the centre of the display face; it faces +Z of `xf`.
func add_screen(xf: Transform3D, title: String) -> VenueScreen:
	var scr := VenueScreen.new()
	scr.name = "Screen"
	scr.tier = tier
	scr.venue_title = title
	scr.exclude_layer_bit = RENDER_LAYER_VENUE_BIT
	add_child(scr)
	scr.transform = xf
	var mat := scr.build()
	if has_model("screen_frame"):
		# The frame's `screen` slot is the display face (x +-2.4, y +-1.35, z 0).
		place("screen_frame", xf, {"screen": mat}, false)
	else:
		var face := MeshInstance3D.new()
		face.name = "Face"
		var q := QuadMesh.new()
		q.size = Vector2(4.8, 2.7)
		face.mesh = q
		face.material_override = mat
		scr.add_child(face)
	_screens.append(scr)
	if tier != "low":
		crowd.add_speck(xf * Vector3(0, 0, 1.2), 2, 5.5, Color(0.25, 0.35, 0.55), 0.35)
	return scr


## A fighters' entrance: the gate model, its lamp strip (animated by the entrance), its
## sign, and a pyro launcher on each pedestal. `side` 0 is the player's, 1 the opponent's.
func add_gate(xf: Transform3D, side: int, sign_row: int = 0) -> Node3D:
	var strip := mats.lamp(Color(1.0, 0.7, 0.22), 2.5)
	while _gate_strips.size() <= side:
		_gate_strips.append(null)
	_gate_strips[side] = strip
	var sign_mat := mats.plate(KIT_TEX + "gate_signs.png", Rect2(0.0, 0.5 * float(sign_row), 1.0, 0.5), 0.25)
	var gate := place("entrance_gate", xf, {"lamp_strip": strip, "sign": sign_mat}, true)
	# pyro_pedestal_l / _r in entrance_gate.glb: tops at (+-2.0, 0.9, 0.55).
	for x in [-2.0, 2.0]:
		add_pyro(xf * Vector3(x, 0.0, 0.55), "gate%d" % side, true)
	set_gate_mark(side, xf * Vector3(0, 0, 1.5))
	return gate


## A pyro point: a launcher model (optional), a flame column and a spark fountain, plus a
## flash light on the high tier. Fired by group name.
func add_pyro(pos: Vector3, group: String, with_launcher: bool = true) -> void:
	var base := pos
	if with_launcher:
		place("pyro_launcher", Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.9 if group.begins_with("gate") else 0.0, 0)))
		base = pos + Vector3(0, (0.9 if group.begins_with("gate") else 0.0) + 0.62, 0)
	var flame := VenueFx.flame_column(tier)
	flame.position = base
	add_child(flame)
	var sparks := VenueFx.spark_fountain(tier, 4.5)
	sparks.position = base
	add_child(sparks)
	if not _pyro.has(group):
		_pyro[group] = []
	(_pyro[group] as Array).append_array([flame, sparks])
	# One flash light per GROUP, not per launcher: a burst is one event of light, and the
	# group's first launcher stands in for all of them.
	if tier == "high" and not _pyro_lights.has(group):
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.6, 0.25)
		o.light_energy = 0.0
		o.omni_range = 9.0
		o.shadow_enabled = false
		o.position = base + Vector3(0, 1.5, 0)
		o.visible = false
		add_child(o)
		_pyro_lights[group] = [o]


## A moving-head fixture hanging at `xf` (its base on the truss above). The head sweeps
## on its own and turns toward the gates during the entrance.
func add_moving_head(xf: Transform3D, colour: Color = Color(0.85, 0.9, 1.0)) -> void:
	var holder := place("moving_head", xf, {}, false)
	var yoke: Node3D = null
	var head: Node3D = null
	for c in holder.get_children():
		if str(c.name).begins_with("mh_head"):
			head = c
		elif str(c.name).begins_with("mh_yoke"):
			yoke = c
	var from := xf * Vector3(0, -0.45, 0)
	var beam: MeshInstance3D = null
	if tier != "low":
		beam = _add_beam(from, from + Vector3(0, -5, 0), 0.08, 1.0, colour, 0.07)
	_heads.append({"holder": holder, "yoke": yoke, "head": head, "beam": beam, "from": from,
		"phase": float(_heads.size()) * 1.7, "aim": Vector3.ZERO})


## A board (advertising plate) at `xf` facing +Z, `index` 0..3 in boards.png.
func add_board(xf: Transform3D, index: int, size: Vector2 = Vector2(4.0, 1.0)) -> void:
	var q := QuadMesh.new()
	q.size = size
	var plate := mats.plate(KIT_TEX + "boards.png", Rect2(0.0, 0.25 * float(index), 1.0, 0.25), 0.25 * board_level)
	plate.albedo_color = Color(board_level, board_level, board_level)
	q.material = plate
	var mi := MeshInstance3D.new()
	mi.name = "Board"
	mi.mesh = q
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The perimeter LED boards: a ring of lit advertising boards just behind the wall, tilted
## back toward the camera. This is the one piece of the venue that is in the fight frame
## whenever play is near a wall, so it carries the venue's broadcast identity at the
## fight camera's distance. One mesh, two surfaces (the lit face, the dark back).
var _ring_mat: ShaderMaterial = null


func add_led_ring(offset: float, y0: float, height: float, tilt_deg: float, extent: float) -> void:
	var wall := arena_half() + FightTypes.WALL_THICKNESS * 0.5
	var d := wall + offset
	var tilt := deg_to_rad(tilt_deg)
	var back := height * sin(tilt)
	var rise := height * cos(tilt)
	var fv := PackedVector3Array()
	var fuv := PackedVector2Array()
	var fn := PackedVector3Array()
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var run := 0.0
	# Each side as seen from inside the arena, left to right: (along, outward normal).
	# (Checked in the near-wall capture: reading left to right from inside the arena.)
	var sides := [[Vector3(-1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, 0, -1), Vector3(-1, 0, 0)]]
	for sd in sides:
		var along: Vector3 = sd[0]
		var out: Vector3 = sd[1]
		var a0 := out * d - along * extent + Vector3(0, y0, 0)
		var a1 := out * d + along * extent + Vector3(0, y0, 0)
		var b0 := a0 + out * back + Vector3(0, rise, 0)
		var b1 := a1 + out * back + Vector3(0, rise, 0)
		var n := (-out * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
		var u0 := run
		var u1 := run + extent * 2.0
		run = u1 + 1.0
		# Front: faces the arena (winding checked in the wide capture: the lit side faces in).
		for tri in [[a0, b1, a1, Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)],
				[a0, b0, b1, Vector2(u0, 1), Vector2(u0, 0), Vector2(u1, 0)]]:
			for k in range(3):
				fv.append(tri[k])
				fuv.append(tri[k + 3])
				fn.append(n)
		for tri in [[a0, a1, b1], [a0, b1, b0]]:
			for k in range(3):
				bv.append(tri[k])
				bn.append(-n)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = fv
	arrays[Mesh.ARRAY_TEX_UV] = fuv
	arrays[Mesh.ARRAY_NORMAL] = fn
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var back_arrays := []
	back_arrays.resize(Mesh.ARRAY_MAX)
	back_arrays[Mesh.ARRAY_VERTEX] = bv
	back_arrays[Mesh.ARRAY_NORMAL] = bn
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, back_arrays)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://arena/kit/shaders/led_board.gdshader")
	_ring_mat.set_shader_parameter("boards", load(KIT_TEX + "boards.png"))
	_ring_mat.set_shader_parameter("board_len", height * 4.0)
	_ring_mat.set_shader_parameter("brightness", 1.5 if tier != "low" else 0.9)
	mesh.surface_set_material(0, _ring_mat)
	mesh.surface_set_material(1, mats.slot("dark_metal"))
	var mi := MeshInstance3D.new()
	mi.name = "LedRing"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Floor grime: `cell` 0 oil, 1 tyre marks, 2 dust, 3 weld seam (floor_grime.png).
## All grime becomes ONE mesh at commit.
func add_grime(centre: Vector2, size: float, angle: float, cell: int, y: float = 0.006) -> void:
	_grime_items.append([centre, size, angle, cell, y])


func _commit_grime() -> void:
	if _grime_items.is_empty():
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	for g in _grime_items:
		var c: Vector2 = g[0]
		var s: float = g[1] * 0.5
		var a: float = g[2]
		var cell: int = g[3]
		var y: float = g[4]
		var u0 := float(cell % 2) * 0.5
		var v0 := float(cell / 2) * 0.5
		var corners := [Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]
		var cuv := [Vector2(u0, v0), Vector2(u0 + 0.5, v0), Vector2(u0 + 0.5, v0 + 0.5), Vector2(u0, v0 + 0.5)]
		var p := []
		for k in range(4):
			var r := (corners[k] as Vector2).rotated(a) + c
			p.append(Vector3(r.x, y, r.y))
		for tri in [[0, 2, 1], [0, 3, 2]]:
			for k in tri:
				verts.append(p[k])
				uvs.append(cuv[k])
				norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(KIT_TEX + "floor_grime.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(1, 1, 1, 0.6)
	mat.roughness = 0.35
	mat.metallic = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Grime"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_grime_items.clear()


## The ground round the arena: one big plane just under the floor top.
func add_ground(extent: float, material: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2.0, extent * 2.0)
	plane.material = material
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.position = Vector3(0, -0.02, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The night: a dome behind everything.
func add_sky(params: Dictionary = {}) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 90.0
	sphere.height = 180.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var mat := ShaderMaterial.new()
	mat.shader = load(SKY_SHADER)
	mat.set_shader_parameter("noise_tex", load(KIT_TEX + "noise.png"))
	for k in params.keys():
		mat.set_shader_parameter(str(k), params[k])
	mat.render_priority = -100
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Sky"
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)


# ---------------------------------------------------------------------------------
# The venue's grade of the arena itself (presentation only)
# ---------------------------------------------------------------------------------
const FLOOR_SHADER := "res://arena/kit/shaders/venue_floor.gdshader"
const TRIM_SHADER := "res://arena/kit/shaders/hazard_trim.gdshader"

## What the grade did, for the notes and the tests.
var graded := {}


## Regrade the ARENA's own light rig and surfaces for this venue (the Yard at night: a
## sodium key, a cold rim, a dark oily floor). Everything here is a render property of a
## node the arena built: light colours, energies and directions, the environment's
## ambient and fog, and the material_override of the floor and wall meshes. No body,
## shape, physics material or hazard node is touched, and it runs once, after the arena's
## build and after GraphicsQuality has applied the tier, so it scales what the tier set.
## Keys (all optional):
##   key_colour, key_energy_scale, key_from (a point the key shines FROM, toward the
##   centre); fill_colour, fill_energy, fill_from; ambient_colour, ambient_energy_scale;
##   fog_colour, fog_density, exposure_scale, glow_intensity; floor_map (texture path),
##   floor_tint, floor_params {uniform: value}; wall_tint_scale (Color multiply);
##   hazard_trim {height, overhang}.
func grade(g: Dictionary) -> void:
	if arena == null:
		return
	var key := arena.get_node_or_null("KeyLight") as DirectionalLight3D
	if key != null:
		if g.has("key_colour"):
			key.light_color = g["key_colour"]
		if g.has("key_energy_scale"):
			key.light_energy *= float(g["key_energy_scale"])
		if g.has("key_from"):
			key.global_basis = Basis.looking_at(-(g["key_from"] as Vector3).normalized(), Vector3.UP)
		graded["key"] = [key.light_color, key.light_energy]
	var fill := arena.get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		if g.has("fill_colour"):
			fill.light_color = g["fill_colour"]
		if g.has("fill_energy"):
			fill.light_energy = float(g["fill_energy"])
		if g.has("fill_from"):
			fill.global_basis = Basis.looking_at(-(g["fill_from"] as Vector3).normalized(), Vector3.UP)
		graded["fill"] = [fill.light_color, fill.light_energy]
	var we := arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		if g.has("ambient_colour"):
			env.ambient_light_color = g["ambient_colour"]
		if g.has("ambient_energy_scale"):
			env.ambient_light_energy *= float(g["ambient_energy_scale"])
		if g.has("fog_colour"):
			env.fog_light_color = g["fog_colour"]
		if g.has("fog_density"):
			env.fog_density = float(g["fog_density"])
		if g.has("exposure_scale"):
			env.tonemap_exposure *= float(g["exposure_scale"])
		if g.has("glow_intensity"):
			env.glow_intensity = float(g["glow_intensity"])
		if g.has("background"):
			env.background_color = g["background"]
		graded["env"] = true
	if g.has("floor_map"):
		_grade_floor(g)
	if g.has("wall_tint_scale"):
		for w in _arena_walls():
			var mi := w.get_node_or_null("Mesh") as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D if mi != null else null
			if m != null:
				var t: Color = g["wall_tint_scale"]
				m.albedo_color = Color(m.albedo_color.r * t.r, m.albedo_color.g * t.g, m.albedo_color.b * t.b)
		graded["walls"] = true
	if g.has("hazard_trim"):
		_add_hazard_trim(g["hazard_trim"])
	if g.has("grid_colour"):
		var grid := arena.get_node_or_null("Grid") as MeshInstance3D
		var gm := grid.material_override as StandardMaterial3D if grid != null else null
		if gm != null:
			gm.albedo_color = g["grid_colour"]
			gm.roughness = 0.9
			graded["grid"] = true


func _arena_walls() -> Array:
	var out := []
	var walls := arena.get_node_or_null("Walls")
	if walls != null:
		for c in walls.get_children():
			if c is Node3D:
				out.append(c)
	return out


## Every floor slab's visible mesh gets the venue floor shader, fed the arena's own plate
## textures so the scratches and seams stay the ones the owner signed off.
func _grade_floor(g: Dictionary) -> void:
	var shader := load(FLOOR_SHADER) as Shader
	var map := load(str(g["floor_map"])) as Texture2D
	if shader == null or map == null:
		return
	var count := 0
	for c in arena.get_children():
		var body := c as StaticBody3D
		if body == null or not str(body.name).begins_with("Floor"):
			continue
		var mi := body.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null:
			continue
		var old := mi.material_override as StandardMaterial3D
		var mat := ShaderMaterial.new()
		mat.shader = shader
		if old != null:
			mat.set_shader_parameter("plate_albedo", old.albedo_texture)
			mat.set_shader_parameter("plate_normal", old.normal_texture)
			mat.set_shader_parameter("plate_rough", old.roughness_texture)
			mat.set_shader_parameter("plate_ao", old.ao_texture)
			# The arena's triplanar scale is repeats per metre.
			if old.uv1_scale.x > 0.0:
				mat.set_shader_parameter("plate_tile_m", 1.0 / old.uv1_scale.x)
		mat.set_shader_parameter("floor_map", map)
		mat.set_shader_parameter("map_extent", arena_half() * 2.0 + 0.4)
		if g.has("floor_tint"):
			mat.set_shader_parameter("tint", g["floor_tint"])
		for k in (g.get("floor_params", {}) as Dictionary).keys():
			mat.set_shader_parameter(str(k), g["floor_params"][k])
		mi.material_override = mat
		count += 1
	graded["floor_slabs"] = count


## A painted sleeve over the top of every wall: worn hazard stripes on the top and down
## the first few centimetres of both faces (the concept's wall tops). Visual only.
func _add_hazard_trim(p: Dictionary) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(TRIM_SHADER)
	mat.set_shader_parameter("noise_tex", load(KIT_TEX + "noise.png"))
	var h := float(p.get("height", 0.12))
	var over := float(p.get("overhang", 0.012))
	var top := 0.0
	for w in _arena_walls():
		var body := w as Node3D
		var mi := body.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null:
			continue
		var aabb := mi.get_aabb()
		top = body.position.y + aabb.end.y
		# The arena's thin chevron cap stands 3 cm proud of the wall top and would poke
		# through the sleeve: the sleeve replaces it, so hide it (visual only).
		var cap := body.get_node_or_null("Chevron") as MeshInstance3D
		if cap != null:
			cap.visible = false
		var box := BoxMesh.new()
		box.size = Vector3(aabb.size.x + over * 2.0, h + over, aabb.size.z + over * 2.0)
		var sleeve := MeshInstance3D.new()
		sleeve.name = "HazardTrim" + str(body.name).trim_prefix("Wall")
		sleeve.mesh = box
		sleeve.material_override = mat
		sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# In the kit's own tree (never under the wall's body), at the wall's top.
		sleeve.position = body.position + Vector3(0, aabb.end.y - (h - over) * 0.5, 0)
		add_child(sleeve)
	mat.set_shader_parameter("top_y", top + over)
	graded["trim"] = true


# ---------------------------------------------------------------------------------
# Presentation events and hooks (docs/wave-a-contracts.md section 2.3, 2.4)
# ---------------------------------------------------------------------------------
## The crowd's picture follows the crowd's sound: `_poll_crowd_audio` sees AudioMix play a
## swell (after the mixer's own gap check) and calls this on the same frame. Anything else
## may call it too (the group "venue_kit" is there for that).
func on_crowd_reaction(key: String, intensity: float = 1.0) -> void:
	if crowd != null:
		crowd.react(_action_point(), clampf(intensity, 0.0, 1.0))
	# The ripple carries the reaction; the house-wide level only lifts a little, so the
	# nearest section is up first and the far side follows.
	match key:
		"big_hit":
			excite(0.3 * intensity)
			_flash = 1.0
			_sting("BIG HIT")
		"flipped":
			excite(0.4 * intensity)
			_flash = 1.0
			_sting("FLIPPED!")
		"ko":
			excite(0.5)
			_sting("DOWN!")
		"endgame":
			excite(1.0)
			_flash = 1.0


var _mix: Node = null
var _mix_seen := {}
var _mix_search_at := 0.0


## READ-ONLY hook into the audio director (Arena/fx/audio_mix.gd, owned by the audio lead):
## AudioMix stamps `_swell_at[key]` each time a crowd swell actually plays. Watching that
## dictionary means the kit needs no edit to the audio code; a signal on AudioMix would be
## cleaner and is noted as owed in docs/wave-a-contracts.md section 2.3.
func _poll_crowd_audio() -> void:
	if _mix == null or not is_instance_valid(_mix):
		_mix = null
		if _t < _mix_search_at:
			return
		_mix_search_at = _t + 1.0
		var root: Node = get_parent()
		while root != null and not root.has_method("fight_time"):
			root = root.get_parent()
		if root == null:
			return
		_mix = _find_mix(root)
		if _mix == null:
			return
		var seen: Variant = _mix.get("_swell_at")
		_mix_seen = (seen as Dictionary).duplicate() if seen is Dictionary else {}
		return
	var now: Variant = _mix.get("_swell_at")
	if not (now is Dictionary):
		return
	for k in (now as Dictionary).keys():
		if not _mix_seen.has(k) or float(_mix_seen[k]) != float(now[k]):
			_mix_seen[k] = now[k]
			on_crowd_reaction(str(k))


func _find_mix(node: Node) -> Node:
	if node.has_method("crowd_reaction") and node.has_method("play_endgame_horn"):
		return node
	for c in node.get_children():
		if c == self:
			continue
		var found := _find_mix(c)
		if found != null:
			return found
	return null


func _on_hazard_fx(kind: String, active: bool, _position: Vector3) -> void:
	if not active:
		return
	# The crowd winces at the arena biting; a bite with a machine in it is a big hit and
	# comes through on_crowd_reaction as well.
	if kind in ["spikes", "flame", "ram", "pit"]:
		_flinch_s = 0.9
		_excitement = maxf(_excitement, 0.45)


## Where the fight is: the middle of the machines, or the centre of the arena.
func _action_point() -> Vector3:
	var n: Node = get_parent()
	while n != null and not n.has_method("bots"):
		n = n.get_parent()
	if n == null:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var count := 0
	for b in n.call("bots"):
		var node := b as Node3D
		if node != null and is_instance_valid(node) and node.is_inside_tree():
			sum += node.global_position
			count += 1
	return sum / float(count) if count > 0 else Vector3.ZERO


func set_excitement(v: float) -> void:
	_excitement = clampf(v, 0.0, 1.0)


func excite(v: float) -> void:
	_excitement = maxf(_excitement, clampf(v, 0.0, 1.0))


func _sting(word: String) -> void:
	for s in _screens:
		(s as VenueScreen).sting(word)


## Fire a pyro group: "gate0", "gate1", "columns", or "all".
func fire_pyro(group: String) -> void:
	for g in _pyro.keys():
		if group == "all" or str(g) == group:
			for p in _pyro[g]:
				var e := p as GPUParticles3D
				e.restart()
				e.emitting = true
			for o in _pyro_lights.get(g, []):
				(o as OmniLight3D).visible = true
				(o as OmniLight3D).set_meta("t", 0.0)


const ENTRANCE_S := 3.5


## The venue side of the pre-fight entrance (the camera sequence is a later wave).
func play_entrance(side: int = 0) -> void:
	_entrance_t = 0.0
	_entrance_side = clampi(side, 0, 1)


func skip_entrance() -> void:
	_entrance_t = -1.0
	for l in _lights:
		(l["light"] as Light3D).light_energy = float(l["base"])
	for s in _gate_strips:
		if s != null:
			(s as StandardMaterial3D).emission_energy_multiplier = 2.5


func entrance_playing() -> bool:
	return _entrance_t >= 0.0


func intro_camera_marks() -> Array[Transform3D]:
	return intro_marks


## Counts for the notes and the perf test.
func stats() -> Dictionary:
	var out := {"tier": tier, "cards": 0, "silhouettes": 0, "specks": 0, "lights": _lights.size(),
		"mesh_instances": 0, "multimeshes": 0, "draw_surfaces": 0, "tris": 0, "particles": 0,
		"particle_emitters": 0}
	if crowd != null:
		out["cards"] = crowd.card_count()
		out["silhouettes"] = crowd.silhouette_count()
		out["specks"] = crowd.speck_count()
	_stat_walk(self, out)
	return out


func _stat_walk(node: Node, out: Dictionary) -> void:
	if node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null and mm.instance_count > 0:
			out["multimeshes"] = int(out["multimeshes"]) + 1
			out["draw_surfaces"] = int(out["draw_surfaces"]) + mm.mesh.get_surface_count()
			out["tris"] = int(out["tris"]) + _mesh_tris(mm.mesh) * mm.instance_count
	elif node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			out["mesh_instances"] = int(out["mesh_instances"]) + 1
			out["draw_surfaces"] = int(out["draw_surfaces"]) + mesh.get_surface_count()
			out["tris"] = int(out["tris"]) + _mesh_tris(mesh)
	elif node is GPUParticles3D:
		out["particle_emitters"] = int(out["particle_emitters"]) + 1
		out["particles"] = int(out["particles"]) + (node as GPUParticles3D).amount
	for c in node.get_children():
		if c is SubViewport:
			continue
		_stat_walk(c, out)


static func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ---------------------------------------------------------------------------------
# Frame clock (presentation only)
# ---------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	_qa_tick()
	_poll_crowd_audio()
	# Endgame: read, never written.
	if not _endgame_seen and arena != null and arena.has_method("escalated") and bool(arena.call("escalated")):
		_endgame_seen = true
		fire_pyro("columns")
		excite(1.0)
		_base_excitement = 0.3
	# The crowd settles back to a murmur over about two seconds.
	_excitement = lerpf(_excitement, _base_excitement, 1.0 - exp(-delta / 1.6))
	_flash = maxf(0.0, _flash - delta * 0.8)
	_flinch_s = maxf(0.0, _flinch_s - delta)
	if crowd != null:
		crowd.tick(delta)
		crowd.set_excitement(_excitement, _flinch_s > 0.0)
		crowd.set_flash_burst(_flash)
	if _ring_mat != null:
		_ring_mat.set_shader_parameter("excitement", clampf((_excitement - 0.5) * 2.0, 0.0, 1.0))
	_tick_entrance(delta)
	_tick_heads()
	_tick_pyro_lights(delta)
	for f in _flicker:
		var l := f["light"] as Light3D
		var ph: float = f["phase"]
		var n := sin(_t * 23.0 + ph * 10.0) * sin(_t * 7.3 + ph) * sin(_t * 1.1)
		var dip := 1.0 if n > -0.55 else 0.35
		if _entrance_t < 0.0:
			l.light_energy = float(f["base"]) * dip


func _tick_entrance(delta: float) -> void:
	if _entrance_t < 0.0:
		return
	var t0 := _entrance_t
	_entrance_t += delta
	var t := _entrance_t
	# Floods: down for the walk-out, back up with the pyro.
	var level := 1.0
	if t < 0.3:
		level = lerpf(1.0, 0.25, t / 0.3)
	elif t < 2.5:
		level = 0.25
	elif t < 2.9:
		level = lerpf(0.25, 1.15, (t - 2.5) / 0.4)
	else:
		level = lerpf(1.15, 1.0, clampf((t - 2.9) / 0.6, 0.0, 1.0))
	for l in _lights:
		(l["light"] as Light3D).light_energy = float(l["base"]) * level
	for b in _beams:
		((b["mesh"] as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter(
			"strength", float(b["base"]) * (1.0 + (1.0 - level) * 1.5))
	# The gate strip chases while the machine walks out.
	if _entrance_side < _gate_strips.size() and _gate_strips[_entrance_side] != null:
		var strip := _gate_strips[_entrance_side] as StandardMaterial3D
		strip.emission_energy_multiplier = 2.5 + 6.0 * (0.5 + 0.5 * sin(t * 18.0)) * (1.0 if t < 3.0 else 0.0)
	if t0 < 1.0 and t >= 1.0:
		fire_pyro("gate%d" % _entrance_side)
		excite(1.0)
		_flash = 1.0
	if t0 < 2.5 and t >= 2.5:
		fire_pyro("gate%d" % _entrance_side)
		excite(1.0)
	if t >= ENTRANCE_S:
		skip_entrance()


func _tick_heads() -> void:
	for h in _heads:
		var holder := h["holder"] as Node3D
		var yoke := h["yoke"] as Node3D
		var head := h["head"] as Node3D
		var ph: float = h["phase"]
		var aim: Vector3
		if _entrance_t >= 0.0 and _entrance_t < 3.0 and _gate_marks.size() > _entrance_side:
			aim = _gate_marks[_entrance_side]
		else:
			var r := arena_half() * 0.6
			aim = Vector3(sin(_t * 0.31 + ph) * r, 0.0, cos(_t * 0.23 + ph * 1.3) * r)
		var cur: Vector3 = h["aim"]
		cur = cur.lerp(aim, 0.06)
		h["aim"] = cur
		var from: Vector3 = h["from"]
		var dir := (cur - from).normalized()
		# Pan the yoke about the fixture's vertical, tilt the head about its own X.
		var local := holder.global_transform.basis.inverse() * dir
		var pan := atan2(local.x, local.z)
		var tilt := acos(clampf(-local.y, -1.0, 1.0))
		if yoke != null:
			yoke.rotation.y = pan
		if head != null:
			head.rotation = Vector3(0, pan, 0)
			head.rotate_object_local(Vector3.RIGHT, -tilt)
		var beam := h["beam"] as MeshInstance3D
		if beam != null:
			VenueFx.aim_beam(beam, from, from + dir * 5.5)


func _tick_pyro_lights(delta: float) -> void:
	for g in _pyro_lights.keys():
		for o in _pyro_lights[g]:
			var light := o as OmniLight3D
			if not light.visible:
				continue
			var t := float(light.get_meta("t", 0.0)) + delta
			light.set_meta("t", t)
			light.light_energy = 4.0 * exp(-t * 2.2) * (0.8 + 0.2 * sin(t * 40.0))
			if t > 1.6:
				light.visible = false


## Where each gate's mouth is, for the moving heads to find during the entrance.
var _gate_marks: Array[Vector3] = []


func set_gate_mark(side: int, pos: Vector3) -> void:
	while _gate_marks.size() <= side:
		_gate_marks.append(Vector3.ZERO)
	_gate_marks[side] = pos


# ---------------------------------------------------------------------------------
# QA (desktop only): --roboteer-no-venue, --roboteer-venue-tier=, --roboteer-venue-entrance=S,
# --roboteer-venue-react=S, --roboteer-venue-endgame=S, --roboteer-venue-perf
# ---------------------------------------------------------------------------------
func _read_qa_args() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a == "--roboteer-no-venue":
			_qa["off"] = true
		elif a.begins_with("--roboteer-venue-tier="):
			_qa["tier"] = a.get_slice("=", 1)
		elif a.begins_with("--roboteer-venue-entrance="):
			_qa["entrance"] = float(a.get_slice("=", 1))
		elif a.begins_with("--roboteer-venue-react="):
			_qa["react"] = float(a.get_slice("=", 1))
		elif a.begins_with("--roboteer-venue-endgame="):
			_qa["endgame"] = float(a.get_slice("=", 1))
		elif a.begins_with("--roboteer-venue-crowd="):
			_qa["crowd"] = a.get_slice("=", 1)
		elif a == "--roboteer-venue-perf":
			_qa["perf"] = 0.0


func _qa_tick() -> void:
	if _qa.is_empty():
		return
	if _qa.has("entrance") and _t >= float(_qa["entrance"]):
		_qa.erase("entrance")
		play_entrance(1)
	if _qa.has("react") and _t >= float(_qa["react"]):
		_qa.erase("react")
		on_crowd_reaction("big_hit")
	if _qa.has("endgame") and _t >= float(_qa["endgame"]):
		_qa.erase("endgame")
		fire_pyro("columns")
		excite(1.0)
	if _qa.has("perf") and _t >= float(_qa["perf"]):
		_qa["perf"] = _t + 2.0
		var vp := get_viewport()
		var rid := vp.get_viewport_rid()
		print("venue_perf ", JSON.stringify({
			"t": snappedf(_t, 0.1),
			"draw_calls": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"objects": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			"primitives": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			"shadow_draw_calls": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"fps": Engine.get_frames_per_second(),
			"kit": stats(),
		}))
