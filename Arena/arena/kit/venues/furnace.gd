extends RefCounted
## FURNACE as a venue (docs/look/arenas/arenas-v1.html, the Furnace concept): a foundry
## with molten metal behind the walls. Catwalk stands high round the far walls, the crowd
## on them lit orange from below; chains and hooks hanging from the dark roof; embers
## everywhere and smoke at venue height; and the hero, a crucible pouring a stream of
## molten metal into a mould in the backdrop, as a slow emissive loop that throws its own
## light. Orange and deep red from below, dark steel above.
##
## The jets, nozzles, burn fans and the belt are the hazards lead's; the kit adds none of
## their light or warning. Nothing here collides.

const EMBER := Color(1.0, 0.45, 0.12)
const GLOW := Color(1.0, 0.42, 0.12)


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7070
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	_grade(kit, low)
	_hall(kit)
	_crucible(kit)
	_catwalks(kit, wall)
	_chains(kit, rng)
	var d := 7.6
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(-d, -d)), Vector3(d, 0, d)), 1, 0)
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(d, d)), Vector3(-d, 0, -d)), 0, 0)
	# Embers everywhere: a wide slow drift through the whole room.
	var embers := VenueFx.embers(kit.tier, Vector3(11.0, 2.5, 11.0), 0.5)
	if embers != null:
		embers.position = Vector3(0, 1.5, 0)
		embers.lifetime = 8.0
		kit.add_child(embers)
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		kit.add_pyro(c * (wall + 0.6), "columns", true)
	for pose in [[Vector3(-11, 6.5, -9), Vector3(0, 0.5, 0)], [Vector3(6, 3.5, 12), Vector3(10.0, 5.0, 14.0)],
			[Vector3(-5, 11, -13), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


static func _grade(kit: VenueKit, low: bool) -> void:
	kit.grade({
		"key_colour": Color(1.0, 0.72, 0.48),
		"key_energy_scale": 1.6 if low else 1.5,
		"key_from": Vector3(6.0, 9.0, 8.0),
		"fill_colour": Color(1.0, 0.35, 0.12),
		"fill_energy": 0.5,
		"fill_from": Vector3(-6.0, 1.5, -4.0),
		"ambient_colour": Color(0.45, 0.28, 0.22),
		"ambient_energy_scale": 1.3 if low else 1.1,
		"fog_colour": Color(0.26, 0.12, 0.06),
		"fog_density": 0.02,
		"floor_map": VenueKit.KIT_TEX + "furnace_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "furnace_floor_n.png",
		"floor_params": {
			"steel": Color(0.5, 0.38, 0.3) if low else Color(0.46, 0.35, 0.27),
			"metallic_base": 0.3 if low else 0.5,
			"rough_dry": 0.55, "rough_min": 0.15, "wet_darken": 0.2,
			"scratch_contrast": 0.55, "scratch_normal": 0.35, "normal_depth": 1.0,
			"pool_radius": 4.4, "pool_edge": 0.7,
			"warm_pool": Vector3(1.0, 0.0, 5.0), "warm_tint": Color(1.2, 0.9, 0.7),
			"cold_pool": Vector3(0.0, 0.0, 0.01),
			"oil_color": Color(0.06, 0.04, 0.03),
		},
		"wall_panels": {"style": "xbrace", "base_color": Color(0.26, 0.16, 0.11),
			"rib_color": Color(0.38, 0.22, 0.13), "bay_m": 1.6, "metallic_v": 0.45, "rough_v": 0.6, "grime": 0.5},
		"wall_wash": {"from": Vector3(-5.0, 2.0, -6.0), "colour": Color(1.0, 0.5, 0.2), "energy": 0.35, "specular": 0.3},
		"glint": {"from": Vector3(6.0, 6.0, 8.0), "colour": GLOW, "energy": 0.08, "specular": 6.0},
		"probe": {"deck_colour": Color(0.5, 0.2, 0.08), "deck_energy": 0.4, "intensity": 0.9, "height": 0.9},
	})
	kit.crowd_staging = {
		"body_light": 0.26, "saturation": 1.15, "spill_strength": 0.7,
		"spill_color": Color(1.0, 0.45, 0.15), "spill_depth": 5.0, "spill_height": 6.0,
		"rim_color": Color(1.0, 0.5, 0.2), "rim_strength": 0.6,
		"phone_glow": 0.25, "phone_color": Color(1.0, 0.85, 0.65),
		"haze_color": Color(0.12, 0.05, 0.02), "haze_near": 6.0, "haze_far": 26.0,
	}
	kit.crowd.phone_size = 0.07
	kit.crowd.phone_colour = Color(1.0, 0.88, 0.7)
	kit.speck_staging = {"phone_twinkle": 1.0}
	# High tier: smoke hanging at venue height (not over the floor).
	if kit.tier == "high":
		var we := kit.arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.volumetric_fog_enabled = true
			we.environment.volumetric_fog_density = 0.0005
			we.environment.volumetric_fog_length = 40.0
		var fv := FogVolume.new()
		fv.name = "Smoke"
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fv.size = Vector3(44.0, 7.0, 44.0)
		fv.position = Vector3(0, 10.5, 0)
		var fm := FogMaterial.new()
		fm.density = 0.05
		fm.albedo = Color(0.5, 0.35, 0.28)
		fm.edge_fade = 0.4
		fv.material = fm
		kit.add_child(fv)


## The foundry hall: dark steel walls with ribs, a roof lost in smoke, a slag-dark floor.
static func _hall(kit: VenueKit) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.22, 0.17, 0.14)
	kit.add_ground(40.0, ground)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.09, 0.08)
	steel.metallic = 0.5
	steel.roughness = 0.7
	var r := 24.0
	var h := 18.0
	for side in [[Vector3(0, h * 0.5, r), Vector3(r * 2.0, h, 0.4)], [Vector3(0, h * 0.5, -r), Vector3(r * 2.0, h, 0.4)],
			[Vector3(r, h * 0.5, 0), Vector3(0.4, h, r * 2.0)], [Vector3(-r, h * 0.5, 0), Vector3(0.4, h, r * 2.0)]]:
		kit.add_block(Transform3D(Basis.IDENTITY, side[0]), side[1], steel)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, h, 0)), Vector3(r * 2.0, 0.4, r * 2.0), steel)
	for k in range(-6, 7):
		var t := float(k) * 4.0
		for p in [Vector3(t, h * 0.5, r - 0.4), Vector3(r - 0.4, h * 0.5, t), Vector3(t, h * 0.5, -r + 0.4), Vector3(-r + 0.4, h * 0.5, t)]:
			kit.add_block(Transform3D(Basis.IDENTITY, p), Vector3(0.5, h, 0.5), "rust")
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(t, h - 1.0, 0)), Vector3(0.4, 1.2, r * 2.0), "dark_metal")


## The hero: a crucible (ladle) on a gantry hook, tipped, pouring a molten stream into a
## mould on the floor of the backdrop, south-east beyond the far corner. The pour is an
## emissive loop with its own light; embers spit off the mould.
static func _crucible(kit: VenueKit) -> void:
	var at := Vector3(5.0, 0, 16.5)
	var molten := ShaderMaterial.new()
	molten.shader = load("res://arena/kit/shaders/molten.gdshader")
	molten.set_shader_parameter("noise_tex", load(VenueKit.KIT_TEX + "noise.png"))
	molten.set_shader_parameter("energy", 3.2)
	molten.set_shader_parameter("flow", Vector2(0.0, 1.4))
	molten.set_shader_parameter("scale", 0.6)
	var pool := molten.duplicate() as ShaderMaterial
	pool.set_shader_parameter("flow", Vector2(0.05, 0.03))
	pool.set_shader_parameter("energy", 2.4)
	pool.set_shader_parameter("scale", 1.5)
	# The ladle: a thick steel bucket with a lip, tilted toward the mould.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-38.0))
	var ladle := at + Vector3(0, 9.5, -1.6)
	kit.add_cylinder(Transform3D(tilt, ladle), 1.3, 2.2, "dark_metal", 20)
	kit.add_cylinder(Transform3D(tilt, ladle + tilt * Vector3(0, 1.15, 0)), 1.4, 0.18, "rust", 20)
	kit.add_cylinder(Transform3D(tilt, ladle + tilt * Vector3(0, 1.2, 0)), 1.15, 0.05, molten, 20)
	# Trunnions and the hook frame it hangs from.
	for sx in [-1.45, 1.45]:
		kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), ladle + Vector3(sx, 0, 0)), 0.18, 0.4, "dark_metal")
		kit.add_beam_block(ladle + Vector3(sx, 0, 0), at + Vector3(sx * 0.4, 13.5, -1.6), 0.18, "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 13.7, -1.6)), Vector3(1.4, 0.5, 0.6), "hazard_paint")
	kit.add_beam_block(at + Vector3(0, 13.9, -1.6), at + Vector3(0, 17.8, -1.6), 0.08, "dark_metal")
	# The stream and the mould.
	var lip := ladle + tilt * Vector3(0, 1.1, 1.25)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(lip.x, (lip.y + 4.0) * 0.5, lip.z)), 0.14, lip.y - 4.0, molten, 10)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(lip.x, 2.0, lip.z)), Vector3(3.0, 4.0, 2.2), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(lip.x, 4.01, lip.z)), Vector3(2.6, 0.02, 1.8), pool)
	kit.add_practical(Vector3(lip.x, 5.5, lip.z - 1.5), GLOW, 6.0, 16.0)
	var spit := VenueFx.embers(kit.tier, Vector3(1.2, 0.2, 0.9), 2.2, Color(1.0, 0.6, 0.2))
	if spit != null:
		spit.position = Vector3(lip.x, 4.1, lip.z)
		kit.add_child(spit)
	# A second, distant pour on the other side of the hall, for the reveal.
	var far := Vector3(-13.0, 0, 14.0)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, far + Vector3(0, 5.0, 0)), 0.1, 8.0, molten, 8)
	kit.add_block(Transform3D(Basis.IDENTITY, far + Vector3(0, 0.5, 0)), Vector3(2.4, 1.0, 2.0), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, far + Vector3(0, 1.01, 0)), Vector3(2.0, 0.02, 1.6), pool)


## Catwalk stands: steel grating decks at 3.3 m round the south and east walls on columns
## and cross-braces, a rail, the crowd two rows deep on them, lit orange from below by
## two uplights (the tier's budget). A stair up at each end.
static func _catwalks(kit: VenueKit, wall: float) -> void:
	var y := 3.3
	var d := wall + 0.4
	var runs := [
		[Vector3(-7.5, y, d), Vector3(7.5, y, d), Vector3(0, 0, 1)],
		[Vector3(d, y, 7.5), Vector3(d, y, -7.5), Vector3(1, 0, 0)],
	]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var out: Vector3 = run[2]
		var dir := (b - a).normalized()
		var ln := a.distance_to(b)
		var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
		for tier_i in range(2):
			var off := out * (0.2 + 2.4 * float(tier_i)) + Vector3(0, 1.2 * float(tier_i), 0)
			var mid := (a + b) * 0.5 + off + out * 1.1
			kit.add_block(Transform3D(basis, mid), Vector3(ln, 0.12, 2.2), "grating")
			kit.add_block(Transform3D(basis, mid - Vector3(0, 0.2, 0)), Vector3(ln, 0.25, 0.2), "rust")
			var n := int(ln / 2.5)
			for k in range(n + 1):
				var p := a + dir * (ln * float(k) / float(n)) + off
				for s in [0.15, 2.05]:
					var foot: Vector3 = p + out * float(s)
					kit.add_beam_block(Vector3(foot.x, 0, foot.z), foot, 0.18, "rust")
				if k < n:
					var q := a + dir * (ln * float(k + 1) / float(n)) + off + out * 0.15
					kit.add_beam_block(Vector3(p.x, 0.2, p.z) + out * 0.15, q - Vector3(0, 0.3, 0), 0.08, "rust")
			# Rail along the front edge.
			kit.add_beam_block(a + off + Vector3(0, 1.05, 0), b + off + Vector3(0, 1.05, 0), 0.05, "dark_metal", true)
			kit.crowd.add_row(a + off + out * 0.6, b + off + out * 0.6, 0.52, 0.88, false)
			kit.crowd.add_row(a + off + out * 1.4, b + off + out * 1.4, 0.56, 0.8, tier_i == 1)
		kit.add_practical((a + b) * 0.5 + out * 1.0 + Vector3(0, -2.2, 0), GLOW, 2.5, 9.0)
	for p in [Vector3(-8.6, 0, wall + 1.5), Vector3(wall + 1.5, 0, -8.6)]:
		kit.batch("stair_scaffold", Transform3D(Basis(Vector3.UP, 0.0 if p.x < 0 else PI * 0.5), p))


## Chains and hooks from the roof: over the stands and one over the arena, high enough
## to stay above every machine and every camera move.
static func _chains(kit: VenueKit, rng: RandomNumberGenerator) -> void:
	for i in range(9):
		var x := rng.randf_range(-9.0, 12.0)
		var z := rng.randf_range(-3.0, 14.0)
		if absf(x) < 6.5 and absf(z) < 6.5:
			x = 2.2
			z = 1.5
		var bottom := rng.randf_range(5.8, 8.5)
		kit.add_beam_block(Vector3(x, 17.8, z), Vector3(x, bottom + 0.35, z), 0.07, "dark_metal")
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x, bottom + 0.2, z)), Vector3(0.22, 0.3, 0.12), "dark_metal")
		kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, bottom - 0.05, z)), 0.16, 0.06, "dark_metal", 10)
