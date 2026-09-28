class_name MenuVenue extends Node3D
## WAVE C: the menus in the arena (owner decision 2026-09-28, docs/wave-c-menus-notes.md).
##
## The blueprint menus (direction A) stand in front of staging 2 "In the arena": the
## player's machine on its plinth on the Coliseum floor, a full house in the bowl behind,
## the truss ring and its moving heads overhead, the gate lit, pyro on arrival and on a
## win. The WorkshopStage keeps the plinth, the machine and its own key, fill and rims;
## this node builds everything AROUND them and is only ever a child of the stage.
##
## Fixes over the A2 mockup (docs/look/menus-blueprint-A2.html, staging 2):
##   - the machine's livery reads true: the venue's lights never touch the machine (they
##     cull HERO_LAYER), the venue's blue ambient is neutralised, and the stage key stays
##     the brightest light on it. The red and blue grade stays on the bowl behind.
##   - the crowd has depth: staged through the kit's own crowd interface (VenueCrowd.stage)
##     with light falling off row by row, a cold rim from the floods, phone glints and the
##     back of the bowl sinking into the dark. The crowd's meshes and animation are the
##     crowd lead's (branch wave-c-crowd) and are not touched here.
##   - the pyro is a jet from a launcher you can see (MenuPyro), fired on arrival at a
##     screen and on a win, never looping.
##   - the close screens (builder, shop) get moving heads sweeping through haze behind the
##     machine, as cones with soft edges (no box fog volumes).
##   - a blueprint of the machine is projected on the floor round the plinth (BLUEPRINT
##     below: one switch turns it off).
##
## PRESENTATION ONLY. The Coliseum instance is built for its look and nothing else: its
## processing is off and every collision object in it has no layer and no mask, so it can
## never touch a physics space; it reads no fight state and no fight RNG.

const VENUE_SCENE := "res://arena/coliseum.tscn"
## The render layer the machine (and the face-off opponent) is moved to while staged, so
## the venue's own lights can leave it out. Bit 17 is free (kit 10, 13, 14; stage 11, 19).
const HERO_LAYER_BIT := 17
const HERO_LAYER := 1 << HERO_LAYER_BIT
## Where the plinth stands in the Coliseum (venue-local), and the venue's turn about it.
const VENUE_AT := Vector3(1.5, 0.0, 1.5)
const VENUE_YAW_DEG := -15.0
## QA and look-dev only (qa/menus_arena_capture.gd --mc-venue=): overrides for the dials
## above ("x", "z", "yaw") and the jets ("jet0", "jet1" as Vector3). Empty in the game.
static var qa := {}
## The hazards are off between fights: their floor art only clutters the plinth.
const HIDE_IN_VENUE := ["CentreRing", "RadialStar", "HazardRings", "SpikePatch", "TurntableWest",
	"TurntableEast", "GrinderWest", "GrinderEast", "HazardTelegraph", "Markers", "JetNorth", "JetSouth"]
## The projected blueprint on the floor round the plinth. Recommended, owner may veto.
const BLUEPRINT := true
## Screens close enough that the bowl is out of frame: moving heads through haze instead.
const CLOSE_SCREENS := ["builder", "shop"]
## Screens whose lens sees a launcher: they fire the arrival jet.
const PYRO_SCREENS := ["menu", "board", "result"]
## One arrival jet at most every this many seconds (screen hopping must not strobe).
const ARRIVAL_COOLDOWN_S := 8.0

## The crowd staged for the menu lens (VenueCrowd.stage keys, the kit's own interface).
## Depth: the front rows lit warm white by the floods, falling off over SPILL_DEPTH rows,
## a cold rim on heads and shoulders, phones glinting, the back of the bowl gone to dark.
const CROWD_STAGING := {
	"body_light": 0.5, "saturation": 0.95,
	"spill_color": Color(1.0, 0.88, 0.74), "spill_strength": 1.15, "spill_depth": 4.0, "spill_height": 6.5,
	"rim_color": Color(0.72, 0.8, 1.0), "rim_strength": 0.26,
	"haze_color": Color(0.005, 0.007, 0.014), "haze_near": 8.0, "haze_far": 28.0, "haze_max": 0.94,
	"desat_far": 0.8, "phone_glow": 0.7, "phone_color": Color(0.9, 0.95, 1.0),
}

var tier := "high"
var stage: Node3D = null
var arena: Node3D = null
var kit: Node = null
var environment: Environment = null
var world_env: WorldEnvironment = null
var screen := ""

var _built := false
var _ready_fired := false
var _active := true
var _level := 1.0
var _lights: Array = []           # [{light, base}] every venue light, for the build dimmer
var _close_rig: Node3D = null
var _heads: Array = []            # [{spot, beam, from, aim, sweep, period, phase}]
var _jets: Array[MenuPyro] = []
var _blueprint: MeshInstance3D = null
var _blueprint_mat: StandardMaterial3D = null
var _t := 0.0
var _last_arrival := -99.0
var _pending_arrival := false


## Build the venue round `stage_node`. `tier_name` is the stage's GraphicsQuality tier.
func build(stage_node: Node3D, tier_name: String) -> bool:
	if _built:
		return arena != null
	_built = true
	stage = stage_node
	tier = tier_name
	name = "MenuVenue"
	if not ResourceLoader.exists(VENUE_SCENE):
		return false
	var packed := load(VENUE_SCENE) as PackedScene
	if packed == null:
		return false
	arena = packed.instantiate() as Node3D
	if arena == null:
		return false
	var at := Vector3(float(qa.get("x", VENUE_AT.x)), 0.0, float(qa.get("z", VENUE_AT.z)))
	var r := Basis(Vector3.UP, deg_to_rad(float(qa.get("yaw", VENUE_YAW_DEG))))
	arena.transform = Transform3D(r, -(r * at))
	# Never processed (no hazards turning, no light shift) and never in a physics space.
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(arena)
	_strip_physics(arena)
	for n in HIDE_IN_VENUE:
		var node := arena.get_node_or_null(NodePath(n)) as Node3D
		if node != null:
			node.visible = false
	kit = arena.get_node_or_null("VenueKit")
	if kit != null:
		# The kit is the only thing in the venue that moves (heads, crowd, pyro lights).
		kit.process_mode = Node.PROCESS_MODE_ALWAYS
	world_env = arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		environment = world_env.environment
	_build_close_rig()
	_build_ring_rig()
	_build_pyro()
	if BLUEPRINT:
		_build_blueprint()
	set_process(true)
	return true


func is_built() -> bool:
	return _built and arena != null


## The kit and the arena grade themselves a frame or two after they enter the tree; this
## runs once after that to take the machine out of the venue's light and stage the crowd.
func _after_build() -> void:
	_ready_fired = true
	_lights.clear()
	for c in arena.find_children("*", "Light3D", true, false):
		var l := c as Light3D
		l.light_cull_mask = l.light_cull_mask & ~HERO_LAYER
		_lights.append({"light": l, "base": l.light_energy})
	if environment != null:
		# The grade stays on the bowl: the ambient goes neutral and low, so the machine's
		# shadow side is its own livery darkened, never the venue's purple.
		environment.ambient_light_color = Color(0.5, 0.52, 0.56)
		environment.ambient_light_energy = 0.12
		environment.ambient_light_sky_contribution = 0.0
		environment.volumetric_fog_ambient_inject = 0.0
		environment.fog_enabled = false
		if environment.volumetric_fog_enabled:
			environment.volumetric_fog_density = minf(environment.volumetric_fog_density, 0.02)
	if kit != null:
		var crowd: Variant = kit.get("crowd")
		if crowd != null and (crowd as Object).has_method("stage"):
			(crowd as Object).call("stage", CROWD_STAGING)
			if tier == "low":
				(crowd as Node3D).visible = false
	_place_jets()
	_calm_grade()
	_raise_head_beams()
	_apply_level()
	_apply_screen()


## The Coliseum's blue and red floods stay on the bowl but at a level that leaves the people
## in the near stands their own colours: the A2 mockup's crowd read as flat blue cut outs
## because the blue flood swamped them. Any strongly saturated venue light is turned down.
const SATURATED_LIGHT_GAIN := 0.45


## The truss ring's moving heads hang 10 m up, above every menu lens: what reads of them
## in the frame is their shafts coming down through the haze over the gate. The kit draws
## those shafts faint for the fight camera; the menu lens is lower and wants them seen.
const HEAD_BEAM_STRENGTH := {"high": 0.1, "medium": 0.14, "low": 0.0}


func _raise_head_beams() -> void:
	if kit == null:
		return
	var heads: Variant = kit.get("_heads")
	if not (heads is Array):
		return
	for h in heads:
		var mat := _beam_mat((h as Dictionary).get("beam") as MeshInstance3D)
		if mat != null:
			_kit_beams.append({"mat": mat, "base": float(HEAD_BEAM_STRENGTH.get(tier, 0.0))})


func _calm_grade() -> void:
	for e in _lights:
		var l := e["light"] as Light3D
		var c := l.light_color
		if c.s > 0.45 and not (l is DirectionalLight3D):
			e["base"] = float(e["base"]) * SATURATED_LIGHT_GAIN


## Take every collision object out of the instance: its visual children are lifted onto
## its parent (keeping their world placement) and the body, its shapes and any area are
## freed. What is left is pure VisualInstance3D, so the stage can be carried into a fight's
## World (fight.gd moves it into every new World) without one body entering that physics
## space. Zeroing the layers was not enough: a fight run after the menus then diverged
## from a plain one (tests/stage_menus_test.gd), the bodies still being in the space.
func _strip_physics(root_node: Node) -> void:
	var bodies: Array[Node] = []
	for c in root_node.find_children("*", "CollisionObject3D", true, false):
		bodies.append(c)
	# Deepest first, so a body inside a body is lifted out before its parent goes.
	bodies.reverse()
	for b in bodies:
		var body := b as Node3D
		var parent := body.get_parent()
		if parent == null:
			continue
		for child in body.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D or child is CollisionObject3D:
				continue
			var keep := child is Node3D
			var xf: Transform3D = (child as Node3D).global_transform if keep else Transform3D()
			body.remove_child(child)
			parent.add_child(child)
			if keep:
				(child as Node3D).global_transform = xf
		parent.remove_child(body)
		body.free()


## On for the menus, off for a fight: the venue's environment must never be the fight's.
func set_active(on: bool) -> void:
	_active = on
	visible = on
	if world_env != null:
		world_env.environment = environment if on else null
	if kit != null:
		kit.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_DISABLED
	set_process(on)
	for j in _jets:
		j.stop()


## How lit the venue is, 0 to 1: the loading screen's build keeps it down with the rig.
func set_level(k: float) -> void:
	if absf(k - _level) < 0.002:
		return
	_level = k
	_apply_level()


func _apply_level() -> void:
	for e in _lights:
		var l := e["light"] as Light3D
		if is_instance_valid(l):
			l.light_energy = float(e["base"]) * _level
	if environment != null:
		environment.background_energy_multiplier = _level
	# The shafts are cards, not lights: they come up with the rig too.
	for e in _heads:
		if e["spot"] != null:
			(e["spot"] as SpotLight3D).light_energy = float(e.get("spot_base", 0.0)) * _level
		var mat := _beam_mat(e["beam"] as MeshInstance3D)
		if mat != null:
			mat.set_shader_parameter("strength", float(e["beam_base"]) * _level)
	for e in _kit_beams:
		(e["mat"] as ShaderMaterial).set_shader_parameter("strength", float(e["base"]) * _level)
	# The crowd's own glow (the floods' spill, the rim, the phones) with it.
	if kit != null and _ready_fired:
		var crowd: Variant = kit.get("crowd")
		if crowd != null and (crowd as Object).has_method("stage"):
			(crowd as Object).call("stage", {
				"spill_strength": float(CROWD_STAGING["spill_strength"]) * _level,
				"rim_strength": float(CROWD_STAGING["rim_strength"]) * _level,
				"phone_glow": float(CROWD_STAGING["phone_glow"]) * maxf(_level, 0.35),
			})


static func _beam_mat(beam: MeshInstance3D) -> ShaderMaterial:
	if beam == null:
		return null
	var mat := beam.material_override as ShaderMaterial
	if mat == null and beam.mesh != null:
		mat = beam.mesh.surface_get_material(0) as ShaderMaterial
	return mat


func set_screen(value: String) -> void:
	var prev := screen
	screen = value
	_apply_screen()
	if value != prev and value in PYRO_SCREENS:
		_pending_arrival = true


## `cue` from the shell: "win" fires the win pyro (both jets, twice, with the gerbs).
func cue(kind: String) -> void:
	if kind == "win":
		for j in _jets:
			j.fire(true)
		_last_arrival = _t
		_pending_arrival = false


func _apply_screen() -> void:
	var close := screen in CLOSE_SCREENS
	if _close_rig != null:
		_close_rig.visible = close
	if _ring_rig != null:
		_ring_rig.visible = not close
	if _blueprint != null:
		_blueprint.visible = not close or screen == "builder"


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if not _ready_fired and _t > 0.15 and (kit == null or bool(kit.get("_built"))):
		_after_build()
	_tick_heads()
	if _blueprint != null and stage != null and stage.has_method("turntable"):
		var tt := stage.call("turntable") as Node3D
		if tt != null:
			_blueprint.rotation.y = tt.rotation.y
	# The arrival jet waits for the lights: never into the dark of the loading screen.
	if _pending_arrival and _ready_fired and _level > 0.95 and _t - _last_arrival > ARRIVAL_COOLDOWN_S:
		_pending_arrival = false
		_last_arrival = _t
		for j in _jets:
			j.fire(false)
	elif _pending_arrival and _ready_fired and _t - _last_arrival <= ARRIVAL_COOLDOWN_S:
		_pending_arrival = false


# ---------------------------------------------------------------- close screens

## Four moving heads on a span behind the machine (as seen from the builder and shop
## lenses), each a real spot plus a soft cone, swept on slow sines. The cones are the kit's
## beam cards (radial falloff, no hard edge); there is no box of fog behind them.
func _build_close_rig() -> void:
	_close_rig = Node3D.new()
	_close_rig.name = "CloseRig"
	add_child(_close_rig)
	if tier == "low":
		return
	var cold := Color(0.66, 0.8, 1.0)
	var white := Color(0.86, 0.9, 1.0)
	var amber := Color(1.0, 0.64, 0.3)
	var heads := [
		[Vector3(-3.6, 4.6, -4.8), Vector3(-1.2, 0.0, -1.6), cold, 0.0],
		[Vector3(-1.2, 4.8, -5.2), Vector3(0.4, 0.0, -1.2), white, 1.7],
		[Vector3(1.4, 4.8, -5.2), Vector3(-0.2, 0.0, -1.1), amber, 3.1],
		[Vector3(3.8, 4.6, -4.8), Vector3(1.4, 0.0, -1.5), cold, 4.4],
	]
	var count := heads.size() if tier == "high" else 2
	for i in count:
		var h: Array = heads[i if tier == "high" else i * 2 + 1]
		var from: Vector3 = h[0]
		var aim: Vector3 = h[1]
		var s := SpotLight3D.new()
		s.light_color = h[2]
		s.light_energy = 7.0
		s.spot_angle = 7.0
		s.spot_range = from.distance_to(aim) * 1.6
		s.spot_attenuation = 0.5
		s.spot_angle_attenuation = 0.9
		s.light_volumetric_fog_energy = 2.5
		s.light_specular = 0.2
		s.shadow_enabled = false
		s.light_cull_mask = s.light_cull_mask & ~HERO_LAYER
		_close_rig.add_child(s)
		s.look_at_from_position(from, aim, Vector3.UP)
		var beam := VenueFx.beam(from, aim.lerp(from, 0.06), 0.05,
			tan(deg_to_rad(7.0)) * from.distance_to(aim) * 0.6, h[2], 0.2, 0.7, 0.4)
		_close_rig.add_child(beam)
		_heads.append({"spot": s, "beam": beam, "from": from, "aim": aim, "spot_base": s.light_energy,
			"beam_base": 0.2, "sweep": Vector3(1.5, 0.0, 0.7), "period": 9.0 + float(h[3]), "phase": float(h[3])})


## The wide screens (menu, board, result) look across the floor at the gate: the truss
## ring's own heads hang above those lenses, so four shafts are thrown from the ring's two
## far sides down to the floor in front of the gate, sweeping slowly. Cards only (no
## light) except two real spots on the high tier for the pools they make on the floor.
const RING_HEADS := [Vector3(-5.0, 9.8, -9.0), Vector3(0.0, 9.8, -9.0), Vector3(-9.0, 9.8, -5.0),
	Vector3(-9.0, 9.8, 0.0)]
const RING_AIM := Vector3(-4.0, 0.0, -4.0)
var _ring_rig: Node3D = null
var _kit_beams: Array = []       # [{mat, base}] the truss ring's own shafts


func _build_ring_rig() -> void:
	_ring_rig = Node3D.new()
	_ring_rig.name = "RingRig"
	add_child(_ring_rig)
	if tier == "low":
		return
	var cols := [Color(0.62, 0.74, 1.0), Color(1.0, 0.5, 0.4), Color(0.85, 0.9, 1.0), Color(0.62, 0.74, 1.0)]
	for i in RING_HEADS.size():
		var from := to_local(arena.global_transform * (RING_HEADS[i] as Vector3))
		var aim := to_local(arena.global_transform * (RING_AIM + Vector3(float(i % 2) * 2.0 - 1.0, 0.0, float(i / 2) * 2.0 - 1.0) * 1.5))
		var spot: SpotLight3D = null
		if tier == "high" and i % 2 == 1:
			spot = SpotLight3D.new()
			spot.light_color = cols[i]
			spot.light_energy = 14.0
			spot.spot_angle = 5.0
			spot.spot_range = from.distance_to(aim) * 1.3
			spot.spot_attenuation = 0.4
			spot.light_volumetric_fog_energy = 1.5
			spot.light_specular = 0.2
			spot.shadow_enabled = false
			spot.light_cull_mask = spot.light_cull_mask & ~HERO_LAYER
			_ring_rig.add_child(spot)
			spot.look_at_from_position(from, aim, Vector3.UP)
		var beam := VenueFx.beam(from, aim, 0.06, tan(deg_to_rad(5.0)) * from.distance_to(aim), cols[i],
			0.16, 0.6, 0.35)
		_ring_rig.add_child(beam)
		_heads.append({"spot": spot, "beam": beam, "from": from, "aim": aim, "rig": _ring_rig,
			"spot_base": spot.light_energy if spot != null else 0.0, "beam_base": 0.16,
			"sweep": Vector3(2.2, 0.0, 1.6), "period": 13.0 + float(i) * 2.3, "phase": float(i) * 1.9})


func _tick_heads() -> void:
	for e in _heads:
		var rig := e.get("rig", _close_rig) as Node3D
		if rig == null or not rig.visible:
			continue
		var sw: Vector3 = e["sweep"]
		var ph := _t * TAU / float(e["period"]) + float(e["phase"])
		var aim: Vector3 = e["aim"] + Vector3(sin(ph) * sw.x, 0.0, cos(ph * 0.7) * sw.z)
		var from: Vector3 = e["from"]
		if e["spot"] != null:
			(e["spot"] as SpotLight3D).look_at_from_position(from, aim, Vector3.UP)
		VenueFx.aim_beam(e["beam"] as MeshInstance3D, from, aim.lerp(from, 0.06))


# ---------------------------------------------------------------- pyro

## The jets stand on the gate's own pyro pedestals (entrance_gate.glb carries a launcher on
## each side, placed by the kit), so the lens sees each launcher standing on its plinth
## beside the gate the machine is framed under. The kit's own flame columns there are never
## fired in the menus (they read as a glowing figure in the gate mouth); these jets replace
## them. Built once the kit has placed the gate.
const JET_GROUP := "gate0"


func _build_pyro() -> void:
	pass


func _place_jets() -> void:
	if tier == "low" or kit == null or not _jets.is_empty():
		return
	var groups: Variant = kit.get("_pyro")
	if not (groups is Dictionary):
		return
	var at: Array[Vector3] = []
	# VenueKit.add_pyro appends [flame, sparks] per launcher: the flames are the evens.
	var group: Array = (groups as Dictionary).get(JET_GROUP, [])
	for i in range(0, group.size(), 2):
		var n := group[i] as Node3D
		if n != null:
			at.append(to_local(n.global_position))
	for i in at.size():
		var p: Vector3 = qa.get("jet%d" % i, at[i])
		var j := MenuPyro.new()
		j.tier = tier
		j.with_launcher = false
		j.position = p - Vector3(0.0, MenuPyro.NOZZLE_Y, 0.0)
		add_child(j)
		j.build()
		_jets.append(j)


func jets() -> Array[MenuPyro]:
	return _jets


# ---------------------------------------------------------------- the projected blueprint

## A plan of the machine thrown on the floor from overhead, as in staging 4: every part's
## outline from above (the convex hull of its meshes), centre lines through the machine and
## across the floor, a dimension line with ticks, a ring at the plinth. Drawn as flat
## emissive ribbons a few millimetres wide, 1.9x the machine, so the outer parts and the
## lines reach out past the plinth. Rebuilt whenever the machine is.
const BLUEPRINT_SCALE := 1.9
const BLUEPRINT_LINE := 0.012
const BLUEPRINT_COLOUR := Color(0.55, 0.75, 1.0)


func _build_blueprint() -> void:
	_blueprint = MeshInstance3D.new()
	_blueprint.name = "Blueprint"
	_blueprint.position = Vector3(0.0, 0.004, 0.0)
	_blueprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blueprint_mat = StandardMaterial3D.new()
	_blueprint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blueprint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blueprint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blueprint_mat.albedo_color = Color(BLUEPRINT_COLOUR.r * 0.5, BLUEPRINT_COLOUR.g * 0.5, BLUEPRINT_COLOUR.b * 0.5, 1.0)
	_blueprint_mat.vertex_color_use_as_albedo = true
	_blueprint_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_blueprint_mat.disable_receive_shadows = true
	_blueprint.material_override = _blueprint_mat
	add_child(_blueprint)


## Redraw the plan from `machine` (the bot on the turntable). Called by the stage after
## every show_bot. The plan is drawn in the TURNTABLE's frame and turned with it.
func draw_blueprint(machine: Node3D, table: Node3D) -> void:
	if _blueprint == null or machine == null or table == null:
		return
	var inv := table.global_transform.affine_inverse()
	var outlines: Array = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi in machine.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := inv * m.global_transform
		var pts := PackedVector2Array()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 300)
			for i in range(0, verts.size(), step):
				var v := xf * verts[i]
				pts.append(Vector2(v.x, v.z))
		if pts.size() < 3:
			continue
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() < 3:
			continue
		var area := 0.0
		for i in hull.size() - 1:
			area += hull[i].x * hull[i + 1].y - hull[i + 1].x * hull[i].y
		if absf(area) * 0.5 < 0.0004:
			continue
		outlines.append(hull)
		for p in hull:
			lo = lo.min(p)
			hi = hi.max(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := BLUEPRINT_SCALE
	var bright := Color(1.0, 1.0, 1.0, 1.0)
	var dim := Color(0.55, 0.55, 0.55, 1.0)
	for hull in outlines:
		for i in (hull as PackedVector2Array).size() - 1:
			_ribbon(st, hull[i] * k, hull[i + 1] * k, BLUEPRINT_LINE, bright)
	if lo.x < INF:
		var c := (lo + hi) * 0.5 * k
		var ext := (hi - lo) * 0.5 * k
		# Centre lines: through the machine and well out across the floor, dashed.
		_dashed(st, Vector2(c.x - ext.x - 1.6, c.y), Vector2(c.x + ext.x + 1.6, c.y), dim)
		_dashed(st, Vector2(c.x, c.y - ext.y - 1.2), Vector2(c.x, c.y + ext.y + 1.2), dim)
		# A dimension line along the length, off to one side, with end ticks.
		var yd := c.y + ext.y + 0.35
		_ribbon(st, Vector2(c.x - ext.x, yd), Vector2(c.x + ext.x, yd), BLUEPRINT_LINE * 0.7, dim)
		for x in [c.x - ext.x, c.x + ext.x]:
			_ribbon(st, Vector2(x, yd - 0.12), Vector2(x, yd + 0.12), BLUEPRINT_LINE * 0.7, dim)
			_ribbon(st, Vector2(x, c.y + ext.y), Vector2(x, yd + 0.05), BLUEPRINT_LINE * 0.5, dim)
		# A ring and a target round the whole plan.
		var rr := maxf(ext.length(), 1.2) + 0.25
		_ring(st, c, rr, BLUEPRINT_LINE * 0.8, dim)
		_ring(st, c, rr + 0.18, BLUEPRINT_LINE * 0.5, dim)
	_blueprint.mesh = st.commit()


func _ribbon(st: SurfaceTool, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.0005:
		return
	var n := Vector2(-d.y, d.x).normalized() * w * 0.5
	var p0 := Vector3(a.x + n.x, 0.0, a.y + n.y)
	var p1 := Vector3(a.x - n.x, 0.0, a.y - n.y)
	var p2 := Vector3(b.x - n.x, 0.0, b.y - n.y)
	var p3 := Vector3(b.x + n.x, 0.0, b.y + n.y)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(p)


func _dashed(st: SurfaceTool, a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	var dir := (b - a) / maxf(len, 0.001)
	var t := 0.0
	var pattern := [0.24, 0.06, 0.04, 0.06]
	var i := 0
	while t < len:
		var seg := minf(float(pattern[i % 4]), len - t)
		if i % 2 == 0:
			_ribbon(st, a + dir * t, a + dir * (t + seg), BLUEPRINT_LINE * 0.6, col)
		t += seg
		i += 1


func _ring(st: SurfaceTool, c: Vector2, r: float, w: float, col: Color) -> void:
	var n := 72
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		_ribbon(st, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, w, col)
