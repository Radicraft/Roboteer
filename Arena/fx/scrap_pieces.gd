class_name ScrapPieces extends Node3D
## The things a scrap shower is actually MADE of: torn metal, not gold pips.
##
## Wave F, agent F3. The owner played the wave G build and said "the scrap won
## doesn't look like scrap", which was fair: every particle in a shower was the same
## 19 mm hex nut in the same gold, so a panel being torn off and a saw scrape shed
## visually identical confetti. This class is the fix. It owns
##
##   * eight hand built meshes (bent armour plate, torn shard, bolt with washer,
##     wheel nut, snapped bracket, coil spring, wire tangle, wheel silhouette),
##   * one shader that draws all of them as dark steel / milky polycarbonate /
##     black HDPE with a warm hot edge that cools,
##   * one MultiMesh "bank" per mesh, and the per frame write cursor that keeps the
##     drawn instance count equal to the number of pieces actually in flight.
##
## It draws; it does not simulate. `BoltShower` owns every position, every timing and
## the whole collect contract, and calls `begin_frame()`, `write()` and `end_frame()`
## once per presentation step. Delete this node and the fight is bit for bit the same.
##
## WHY ONE BANK PER SHAPE. A MultiMesh has exactly one mesh, so a MIX of shapes needs
## one MultiMesh per shape. Each bank is allocated at the full pool size but draws
## only what was written this frame (`visible_instance_count`), and a bank with
## nothing in it is `visible = false`, so an idle shower costs no draw call at all and
## a live one costs one call per shape that is actually on screen (typically three or
## four). The TOTAL instance count across every bank can never exceed the pool,
## because the pool is what hands out the slots.
##
## WHY A SHADER AND NOT A StandardMaterial3D. Each piece needs its own albedo (the
## face material it was torn from), its own metallic/roughness (steel and HDPE are not
## the same surface) and above all its own HEAT, falling from 1 to 0 over 0.6 s.
## `vertex_color_use_as_albedo` can carry the first of those and nothing else, and
## `BaseMaterial3D` has no per instance emission at all. MultiMesh custom data is
## exactly one vec4 per instance, which is one more than we need: heat, metallic,
## roughness. The hot edge itself is a view dependent rim rather than an authored edge
## mask, because a rim reads as a glowing torn edge from every angle a tumbling piece
## presents, and costs one dot product.

## Shape banks. The order is the order of every per kind table below.
const KIND_PLATE := 0        # bent armour plate, the big one
const KIND_SHARD := 1        # a torn flat sliver: milky for polycarbonate, black for HDPE
const KIND_BOLT := 2         # a bolt with its washer still on it
const KIND_NUT := 3          # a wheel nut
const KIND_BRACKET := 4      # a snapped L bracket
const KIND_SPRING := 5       # a coil spring
const KIND_WIRE := 6         # a tangle of wire
const KIND_WHEEL := 7        # a wheel silhouette: thrown only when a wheel comes off
const KIND_COUNT := 8

const KIND_NAMES := ["plate", "shard", "bolt", "nut", "bracket", "spring", "wire", "wheel"]

## The DRAWN long axis of each shape, in metres, before severity and jitter.
##
## These are not real part sizes and do not pretend to be, for exactly the reason
## docs/graphics-fx-notes.md §10 records about `BOLT_VISUAL_SIZE`: at the fight camera
## distance on a 6.9 inch phone a real 19 mm nut is three pixels, and three pixels
## cannot read as a shape no matter how bright it is. These are the sizes at which a
## plate reads as a plate and a spring reads as a spring.
const KIND_SIZE_M := [0.165, 0.120, 0.095, 0.072, 0.130, 0.105, 0.115, 0.330]

## Kinds that are FASTENERS: made of steel whatever the panel they came out of was.
## A polycarbonate lid is still bolted on with steel bolts, and keeping the fasteners
## metallic is most of what stops a plastic bot's shower going flat and grey.
const FASTENER_KINDS := [KIND_BOLT, KIND_NUT, KIND_BRACKET, KIND_SPRING, KIND_WIRE]

## albedo / metallic / roughness per armour material (FightTypes.MATERIAL_FACTOR names).
## Albedo is authored in sRGB the way `albedo_color` is, and converted on the way into
## the instance buffer, so these numbers can be compared with FightTypes.MATERIAL_COLOUR.
const LOOK := {
	"steel": {"tint": Color(0.355, 0.375, 0.415), "metal": 0.88, "rough": 0.42},
	"titanium": {"tint": Color(0.255, 0.275, 0.315), "metal": 0.82, "rough": 0.34},
	"hdpe": {"tint": Color(0.085, 0.085, 0.095), "metal": 0.0, "rough": 0.78},
	"polycarbonate": {"tint": Color(0.805, 0.850, 0.900), "metal": 0.0, "rough": 0.16},
}
const FASTENER_LOOK := {"tint": Color(0.400, 0.415, 0.445), "metal": 0.95, "rough": 0.32}

## The mix, by face material, at a scrape (LIGHT) and at a panel coming off (HEAVY).
## Severity lerps between the two rows, so a saw scrape sheds fasteners and a spinner
## hit that removes a panel sheds plate. Rows do not have to sum to 1: `_pick` normalises.
const MIX_LIGHT := {
	"steel": [0.06, 0.04, 0.30, 0.26, 0.10, 0.12, 0.12, 0.0],
	"titanium": [0.06, 0.04, 0.30, 0.26, 0.10, 0.12, 0.12, 0.0],
	"hdpe": [0.04, 0.30, 0.26, 0.20, 0.08, 0.06, 0.06, 0.0],
	"polycarbonate": [0.02, 0.34, 0.26, 0.20, 0.06, 0.06, 0.06, 0.0],
}
const MIX_HEAVY := {
	"steel": [0.34, 0.10, 0.16, 0.12, 0.14, 0.07, 0.07, 0.0],
	"titanium": [0.34, 0.10, 0.16, 0.12, 0.14, 0.07, 0.07, 0.0],
	"hdpe": [0.10, 0.48, 0.14, 0.10, 0.08, 0.05, 0.05, 0.0],
	"polycarbonate": [0.06, 0.56, 0.12, 0.08, 0.08, 0.05, 0.05, 0.0],
}

## What the part that was hit contributes. Multiplies the material row before the
## pick, so a wheel really does shed wheel nuts and the core sheds wiring.
const PART_BIAS := {
	"wheel": [0.3, 0.6, 1.4, 2.2, 1.0, 1.6, 1.0, 0.0],
	"armour": [1.0, 1.0, 1.0, 1.0, 1.0, 0.7, 0.7, 0.0],
	"weapon": [0.7, 0.8, 1.5, 1.0, 1.8, 1.2, 0.8, 0.0],
	"drive": [0.5, 0.5, 1.2, 1.2, 1.2, 1.6, 1.8, 0.0],
	"core": [0.4, 0.8, 1.0, 0.8, 1.0, 1.0, 2.6, 0.0],
}

## Rim colour of the hot edge. Gold, deliberately: brief v3 §6's readability rule is
## that what is coming to you is warm and what is dead scenery is grey, and the rim is
## how a dark steel plate still says "this is yours" at the fight framing.
const HOT_COLOUR := Color(1.0, 0.72, 0.30)
## How much of the emission follows the rim and how much is flat over the whole piece.
## All rim looks like a decal; no rim looks like a lightbulb.
const RIM_MIX := 0.72
const RIM_POWER := 2.0

## Built in code rather than as a .gdshader file so the whole effect is one owned
## script and there is nothing extra to import. Nothing in here needs a
## RenderingDevice: no derivatives, no screen texture, no depth read, so it compiles
## on gl_compatibility (the Simulator) as well as on Forward+.
const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, shadows_disabled, specular_schlick_ggx;

uniform vec3 hot_colour : source_color = vec3(1.0, 0.72, 0.30);
uniform float hot_energy = 5.0;
uniform float rim_power = 2.0;
uniform float rim_mix = 0.72;

varying vec3 v_albedo;
varying vec3 v_pbr;   // heat, metallic, roughness

void vertex() {
	v_albedo = COLOR.rgb;
	v_pbr = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = v_albedo;
	METALLIC = clamp(v_pbr.g, 0.0, 1.0);
	ROUGHNESS = clamp(v_pbr.b, 0.04, 1.0);
	SPECULAR = 0.55;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = hot_colour * (hot_energy * clamp(v_pbr.r, 0.0, 1.0) * mix(1.0 - rim_mix, 1.0, rim));
}
"""

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _banks: Array[MultiMeshInstance3D] = []
var _extent := PackedFloat32Array()     # longest mesh axis per kind, for the size scale
var _cursor := PackedInt32Array()       # instances written into each bank this frame
var _capacity: int = 0
var _material: ShaderMaterial = null

## victim bot id + "/" + part -> armour material name. See `resolve_material`.
var _material_cache: Dictionary = {}
var _bot_cache: Dictionary = {}


func _ready() -> void:
	set_process(false)


## Build the banks. `capacity` is the pool size (every bank is allocated at the full
## pool size, because any one shower may legitimately be all of one shape).
func configure(capacity: int, aabb: AABB) -> void:
	_capacity = maxi(1, capacity)
	_material = _build_material()
	_extent.resize(KIND_COUNT)
	_cursor.resize(KIND_COUNT)
	for kind in KIND_COUNT:
		var mesh := _build_mesh(kind)
		var size := mesh.get_aabb().size
		_extent[kind] = maxf(0.0001, maxf(size.x, maxf(size.y, size.z)))
		_cursor[kind] = 0

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = _capacity
		mm.visible_instance_count = 0

		var bank := MultiMeshInstance3D.new()
		bank.name = "Scrap" + str(KIND_NAMES[kind]).capitalize()
		bank.multimesh = mm
		bank.material_override = _material
		bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bank.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		bank.custom_aabb = aabb
		bank.visible = false
		add_child(bank)
		_banks.append(bank)


func _build_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("hot_colour", HOT_COLOUR)
	# The glow contract, docs/graphics-fx-notes.md §6: the hot edge rides the same
	# nominal energy the gold bolts always used, so G1's glow threshold check in
	# fx_test.gd still covers it, and FxMaterials.energy() still tames it on the tier
	# with no HDR buffer instead of letting it clip to a white blob.
	m.set_shader_parameter("hot_energy", FxMaterials.energy(FxMaterials.BOLT_EMISSION))
	m.set_shader_parameter("rim_power", RIM_POWER)
	m.set_shader_parameter("rim_mix", RIM_MIX)
	return m


# --------------------------------------------------------------------- per frame

## Start a frame. Every piece still in flight must be written before `end_frame()`,
## because what is not written is not drawn.
func begin_frame() -> void:
	for kind in KIND_COUNT:
		_cursor[kind] = 0


## Draw one piece. `heat` is 0 to 1 and drives the hot edge.
func write(kind: int, xform: Transform3D, tint: Color, metal: float, rough: float,
		heat: float) -> void:
	if kind < 0 or kind >= _banks.size():
		return
	var at: int = _cursor[kind]
	if at >= _capacity:
		return   # cannot happen while the pool hands out the slots, but never overrun
	var mm: MultiMesh = _banks[kind].multimesh
	mm.set_instance_transform(at, xform)
	mm.set_instance_color(at, tint.srgb_to_linear())
	mm.set_instance_custom_data(at, Color(clampf(heat, 0.0, 1.0), metal, rough, 0.0))
	_cursor[kind] = at + 1


## Publish the frame: each bank draws exactly what was written into it, and a bank
## with nothing in it is hidden so it costs no draw call.
func end_frame() -> void:
	for kind in _banks.size():
		var n: int = _cursor[kind]
		var bank: MultiMeshInstance3D = _banks[kind]
		bank.multimesh.visible_instance_count = n
		bank.visible = n > 0


# --------------------------------------------------------------------- choosing

## The shape mix for one hit. `material` is an armour material name, `part` is the
## damage event's part ("armour_front", "wheel_fl", "weapon", "core", "drive"), and
## `severity` is 0 to 1.
func weights(material: String, part: String, severity: float) -> PackedFloat32Array:
	var light: Array = MIX_LIGHT.get(material, MIX_LIGHT["steel"]) as Array
	var heavy: Array = MIX_HEAVY.get(material, MIX_HEAVY["steel"]) as Array
	var bias: Array = PART_BIAS.get(_part_family(part), PART_BIAS["armour"]) as Array
	var s := clampf(severity, 0.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(KIND_COUNT)
	for k in KIND_COUNT:
		out[k] = lerpf(float(light[k]), float(heavy[k]), s) * float(bias[k])
	return out


## Pick one kind out of a weight row. Presentation RNG only: the caller passes its
## own unseeded generator, never the fight's seeded one.
static func pick(row: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in row:
		total += maxf(0.0, w)
	if total <= 0.0:
		return KIND_BOLT
	var r := rng.randf() * total
	for k in row.size():
		r -= maxf(0.0, row[k])
		if r <= 0.0:
			return k
	return KIND_BOLT


## A component kill throws the dead part's silhouette: a wheel throws a wheel, a
## panel throws a plate, a weapon throws the bracket it was bolted through.
static func silhouette_kind(part: String) -> int:
	match _part_family(part):
		"wheel":
			return KIND_WHEEL
		"weapon":
			return KIND_BRACKET
		"core", "drive":
			return KIND_WIRE
		_:
			return KIND_PLATE


static func _part_family(part: String) -> String:
	if part.begins_with("wheel") or part.begins_with("track"):
		return "wheel"
	if part.begins_with("armour"):
		return "armour"
	if part == "weapon":
		return "weapon"
	if part == "drive":
		return "drive"
	if part == "core" or part == "chassis":
		return "core"
	return "armour"


## The look of one piece: a fastener is always steel, everything else takes the face
## material it was torn out of. Returns {"tint": Color, "metal": float, "rough": float}.
static func look_for(kind: int, material: String) -> Dictionary:
	if kind in FASTENER_KINDS:
		return FASTENER_LOOK
	return LOOK.get(material, LOOK["steel"]) as Dictionary


# --------------------------------------------------------------------- material lookup

## What the face that was hit is made of.
##
## The damage event carries the FACE (`part`) but not the material: `BotDamage` uses the
## material to scale the severity and then drops it, and this agent may not change
## `Arena/bot/**` or `fight.gd` to add it. What the payload does carry is enough to find
## it: the victim's own `BotPart` bodies each hold the `material_name` they were built
## with, so this walks the fight subtree once per (victim, part) pair and remembers the
## answer. Read only, guarded at every step, and "steel" whenever anything is missing,
## so a bot that has already been freed costs a look up and a default, never an error.
func resolve_material(victim_id: String, part: String) -> String:
	if victim_id == "" or part == "":
		return "steel"
	var key := victim_id + "/" + part
	if _material_cache.has(key):
		return str(_material_cache[key])
	var bot := _find_bot(victim_id)
	var out := "steel"
	if bot != null:
		var body := _find_part_body(bot, part)
		if body != null:
			out = str(body.get("material_name"))
			if out == "":
				out = "steel"
	_material_cache[key] = out
	return out


## Everything the lookup remembers dies with the fight it was measured in. `FightFx` is
## rebuilt per fight, so this is belt and braces; it also covers a bot being replaced
## inside one FX tree.
func forget_materials() -> void:
	_material_cache.clear()
	_bot_cache.clear()


func _find_bot(victim_id: String) -> Node:
	if not is_inside_tree():
		return null
	if _bot_cache.has(victim_id):
		var cached: Node = _bot_cache[victim_id]
		if is_instance_valid(cached):
			return cached
		_bot_cache.erase(victim_id)
		_material_cache.clear()
	# Search from the top of the running scene rather than from here: the bots are
	# siblings of the FX tree, not children of it. Climbing to the last node below the
	# tree root finds Fight in the game and the test's own root in a headless run.
	var from: Node = self
	while from.get_parent() != null and from.get_parent() != get_tree().root:
		from = from.get_parent()
	if from == self:
		from = get_tree().root
	var found := _search(from, func(n: Node) -> bool:
		var id: Variant = n.get("bot_id")
		return id is String and str(id) == victim_id)
	if found != null:
		_bot_cache[victim_id] = found
	return found


func _find_part_body(bot: Node, part: String) -> Node:
	var want := part
	if want == "core":
		want = "chassis"   # the core lives in the chassis body, which carries the top material
	return _search(bot, func(n: Node) -> bool:
		var key: Variant = n.get("part_key")
		return key is String and str(key) == want)


## Breadth first, bounded. A fight subtree is a few hundred nodes; the cap is there so
## a presentation lookup can never become a frame spike if somebody parents the world
## somewhere unexpected.
static func _search(from: Node, predicate: Callable, limit: int = 4000) -> Node:
	var queue: Array[Node] = [from]
	var seen := 0
	while not queue.is_empty() and seen < limit:
		var n: Node = queue.pop_front()
		seen += 1
		if predicate.call(n):
			return n
		for c in n.get_children():
			queue.append(c)
	return null


# --------------------------------------------------------------------- introspection

func capacity() -> int:
	return _capacity


func bank_count() -> int:
	return _banks.size()


func bank(kind: int) -> MultiMeshInstance3D:
	if kind < 0 or kind >= _banks.size():
		return null
	return _banks[kind]


## Longest axis of the built mesh for `kind`, so the caller can scale a piece to a
## size in metres without knowing how the mesh was made.
func mesh_extent(kind: int) -> float:
	if kind < 0 or kind >= _extent.size():
		return 1.0
	return _extent[kind]


func material() -> ShaderMaterial:
	return _material


## Instances written this frame, across every bank. Never more than the pool.
func live_instances() -> int:
	var n := 0
	for c in _cursor:
		n += c
	return n


func live_of(kind: int) -> int:
	if kind < 0 or kind >= _cursor.size():
		return 0
	return _cursor[kind]


## Banks that would issue a draw call this frame.
func banks_drawing() -> int:
	var n := 0
	for kind in _banks.size():
		if _cursor[kind] > 0:
			n += 1
	return n


## Triangles if every slot in the pool were this shape. The worst case the budget in
## docs/wave-f-f3-notes.md is quoted against.
func triangles_worst_case() -> int:
	var worst := 0
	for kind in _banks.size():
		worst = maxi(worst, _triangles(kind) * _capacity)
	return worst


func _triangles(kind: int) -> int:
	var b := bank(kind)
	if b == null or b.multimesh == null or b.multimesh.mesh == null:
		return 0
	var mesh: Mesh = b.multimesh.mesh
	var n := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		n += verts.size() / 3
	return n


func triangles_of(kind: int) -> int:
	return _triangles(kind)


# --------------------------------------------------------------------- the meshes
#
# Every mesh is a hand built triangle soup with per face flat normals, exactly like
# the Stage 3 fallback nut this replaces. Flat normals are the point: a machined edge
# catching the key light separately from the face next to it is what reads as metal,
# and an index buffer with smoothed normals would take that away for the sake of a few
# hundred bytes. No glb, nothing to import, nothing to keep in sync with agent G3.
#
# Shapes are built at roughly real part sizes and then scaled to KIND_SIZE_M by the
# caller through `mesh_extent`, so a shape can be re-proportioned here without
# anything else moving.

func _build_mesh(kind: int) -> ArrayMesh:
	match kind:
		KIND_PLATE:
			return _plate_mesh()
		KIND_SHARD:
			return _shard_mesh()
		KIND_BOLT:
			return _bolt_mesh()
		KIND_NUT:
			return _nut_mesh()
		KIND_BRACKET:
			return _bracket_mesh()
		KIND_SPRING:
			return _spring_mesh()
		KIND_WIRE:
			return _wire_mesh()
		_:
			return _wheel_mesh()


## A bent armour plate. A five sided slab (one edge torn rather than cut) folded along
## its long axis, because a plate that has been hit hard enough to come off is never
## flat again, and the fold is what stops it reading as a flying playing card.
static func _plate_mesh() -> ArrayMesh:
	var poly := PackedVector2Array([
		Vector2(-0.050, -0.026),
		Vector2(0.050, -0.030),
		Vector2(0.048, 0.024),
		Vector2(0.004, 0.032),     # torn: the free edge is not straight
		Vector2(-0.046, 0.021),
	])
	var verts := _slab(poly, 0.0055)
	_fold(verts, 0.38)
	return _soup(verts)


## A torn sliver. Flat, jagged, no thickness at all: it is drawn two sided, and at the
## fight framing a 1 mm edge is nothing but aliasing. This is the shape that carries
## polycarbonate (milky) and HDPE (black chips).
static func _shard_mesh() -> ArrayMesh:
	var poly := PackedVector2Array([
		Vector2(-0.055, -0.004),
		Vector2(-0.012, -0.022),
		Vector2(0.030, -0.012),
		Vector2(0.058, 0.008),
		Vector2(0.006, 0.020),
		Vector2(-0.030, 0.014),
	])
	var verts := PackedVector3Array()
	_fan(verts, poly, 0.0, false)
	_fold(verts, 0.22)
	return _soup(verts)


## A bolt that took its washer with it. Hex head, square shank (four sides is enough at
## this size and saves a third of the triangles), and a flat hex washer partway down.
static func _bolt_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	_prism(verts, _ngon(6, 0.0105), -0.010, 0.010, true, false)      # head
	_prism(verts, _ngon(4, 0.0042), -0.030, -0.009, false, false)    # shank
	_fan(verts, _ngon(6, 0.0125), -0.0115, false)                    # washer, flat
	return _soup(verts)


## A wheel nut. A plain hex prism, and the one shape in the set that is still the
## Stage 3 silhouette, kept on purpose: brief v3 §6 is written about shorn fasteners
## and the shower would be wrong without any.
static func _nut_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	_prism(verts, _ngon(6, 0.0095), -0.0065, 0.0065, true, true)
	return _soup(verts)


## A snapped bracket. Two thin slabs at right angles, one arm torn short.
static func _bracket_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var arm := _slab(PackedVector2Array([
		Vector2(-0.030, -0.009), Vector2(0.030, -0.009),
		Vector2(0.030, 0.009), Vector2(-0.030, 0.009),
	]), 0.004)
	verts.append_array(arm)
	# The second arm stands up at the end of the first, and is snapped off short.
	var up := _slab(PackedVector2Array([
		Vector2(-0.018, -0.009), Vector2(0.014, -0.009),
		Vector2(0.008, 0.009), Vector2(-0.018, 0.009),
	]), 0.004)
	var at := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.027, 0.0, 0.018))
	for v in up:
		verts.append(at * v)
	return _soup(verts)


## A coil spring, drawn as a helical ribbon rather than a swept tube: a tube around
## fifteen path points is over a hundred triangles for a 10 cm object, and the ribbon
## is two sided, so as the piece tumbles it flashes exactly like a real coil.
static func _spring_mesh() -> ArrayMesh:
	const TURNS := 2.5
	const PER_TURN := 6
	const R := 0.0105
	const WIDTH := 0.0055
	var steps := int(TURNS * PER_TURN)
	var span := 0.052
	var verts := PackedVector3Array()
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for k in steps + 1:
		var t := float(k) / float(steps)
		var a := t * TURNS * TAU
		var radial := Vector3(cos(a), 0.0, sin(a))
		var centre := radial * R + Vector3(0.0, -span * 0.5 + span * t, 0.0)
		var inner := centre - radial * (WIDTH * 0.5)
		var outer := centre + radial * (WIDTH * 0.5)
		if k > 0:
			_quad(verts, prev_in, prev_out, outer, inner)
		prev_in = inner
		prev_out = outer
	return _soup(verts)


## A tangle of wire: three short ribbons on scribbled paths, so it reads as loom rather
## than as one bent rod. This is what a core or a drive motor sheds.
static func _wire_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	_strand(verts, Vector3(-0.030, -0.004, 0.006), 1.0, 0.0)
	_strand(verts, Vector3(0.004, 0.006, -0.010), -1.0, 1.9)
	_strand(verts, Vector3(0.012, -0.008, 0.012), 0.8, 3.6)
	return _soup(verts)


static func _strand(verts: PackedVector3Array, start: Vector3, curl: float, phase: float) -> void:
	const SEGMENTS := 4
	const WIDTH := 0.0035
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for k in SEGMENTS + 1:
		var t := float(k) / float(SEGMENTS)
		var a := phase + t * 3.4 * curl
		var centre := start + Vector3(
			t * 0.048 + 0.010 * sin(a * 1.7),
			0.011 * sin(a),
			0.013 * cos(a * 1.3))
		var side := Vector3(0.0, WIDTH * 0.5, 0.0).rotated(Vector3.RIGHT, a)
		if k > 0:
			_quad(verts, prev_a, prev_b, centre + side, centre - side)
		prev_a = centre - side
		prev_b = centre + side


## A wheel silhouette, thrown only when a wheel is knocked off. A ten sided disc with a
## rim, sized far larger than anything else in the set, because the whole job of this
## shape is for the player to see WHAT they just took off at a glance.
static func _wheel_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	_prism(verts, _ngon(10, 0.075), -0.016, 0.016, true, true)
	return _soup(verts)


# --------------------------------------------------------------------- mesh helpers

static func _ngon(sides: int, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in sides:
		var a := float(k) / float(sides) * TAU
		out.append(Vector2(cos(a) * radius, sin(a) * radius))
	return out


## A closed prism from a convex-ish outline in the XZ plane, from y = low to y = high.
static func _prism(verts: PackedVector3Array, poly: PackedVector2Array, low: float,
		high: float, cap_top: bool, cap_bottom: bool) -> void:
	var n := poly.size()
	for k in n:
		var j := (k + 1) % n
		var a := Vector3(poly[k].x, low, poly[k].y)
		var b := Vector3(poly[j].x, low, poly[j].y)
		var c := Vector3(poly[j].x, high, poly[j].y)
		var d := Vector3(poly[k].x, high, poly[k].y)
		_quad(verts, a, b, c, d)
	if cap_top:
		_fan(verts, poly, high, false)
	if cap_bottom:
		_fan(verts, poly, low, true)


## A flat polygon at height y, as a triangle fan around its first vertex.
static func _fan(verts: PackedVector3Array, poly: PackedVector2Array, y: float,
		flip: bool) -> void:
	for k in range(1, poly.size() - 1):
		var a := Vector3(poly[0].x, y, poly[0].y)
		var b := Vector3(poly[k].x, y, poly[k].y)
		var c := Vector3(poly[k + 1].x, y, poly[k + 1].y)
		if flip:
			verts.append_array(PackedVector3Array([a, c, b]))
		else:
			verts.append_array(PackedVector3Array([a, b, c]))


## A solid slab: an outline in the XZ plane given half a thickness either side of y = 0.
static func _slab(poly: PackedVector2Array, thickness: float) -> PackedVector3Array:
	var verts := PackedVector3Array()
	_prism(verts, poly, -thickness * 0.5, thickness * 0.5, true, true)
	return verts


static func _quad(verts: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	verts.append_array(PackedVector3Array([a, b, c, a, c, d]))


## Bend a built shape into a V along X. Done to the finished vertices rather than to
## the outline, so any shape can be folded and the flat normals are computed afterwards
## from the folded triangles, which is what makes the two halves catch the light apart.
static func _fold(verts: PackedVector3Array, amount: float) -> void:
	for i in verts.size():
		var v := verts[i]
		v.y += absf(v.x) * amount
		verts[i] = v


## Triangle soup with one flat normal per triangle. A degenerate triangle (which a fold
## or a jagged outline can produce) is dropped rather than given a zero normal, because
## a zero normal is a black facet.
static func _soup(verts: PackedVector3Array) -> ArrayMesh:
	var out := PackedVector3Array()
	var norms := PackedVector3Array()
	var i := 0
	while i + 2 < verts.size():
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() > 1e-12:
			n = n.normalized()
			out.append_array(PackedVector3Array([a, b, c]))
			norms.append_array(PackedVector3Array([n, n, n]))
		i += 3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
