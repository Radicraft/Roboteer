extends RefCounted
## THE CRUSH as a venue (docs/look/arenas/arenas-v1.html, the Crush concept): a hydraulic
## press hall with oppressive scale. Concrete stands behind thick safety glass on every
## side, above the press machinery line; big hydraulic cylinders with gauges standing
## behind the two ram walls (the hero set piece); pipe runs under a low concrete ceiling;
## cold white work light pooling on pale cracked concrete; steam venting from the pipes.
## Hazard yellow is the only saturated colour.
##
## The rams, their lamps, chevrons and warning are the hazards lead's. Nothing collides.

const WORK := Color(0.92, 0.96, 1.0)


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	_grade(kit, low)
	_hall(kit)
	_stands(kit, wall)
	_press_line(kit, wall)
	_pipes_and_steam(kit, rng)
	var d := 7.6
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(-d, -d)), Vector3(d, 0, d)), 1, 0)
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(d, d)), Vector3(-d, 0, -d)), 0, 0)
	var motes := VenueFx.motes(kit.tier, Vector3(8.0, 2.5, 8.0))
	if motes != null:
		motes.position = Vector3(0, 2.5, 0)
		kit.add_child(motes)
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		kit.add_pyro(c * (wall + 0.6), "columns", true)
	for pose in [[Vector3(-11, 7.0, -9), Vector3(0, 0.5, 0)], [Vector3(-2, 2.5, 0), Vector3(7.5, 3.0, 1.2)],
			[Vector3(-5, 10, -13), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


static func _grade(kit: VenueKit, low: bool) -> void:
	kit.grade({
		"key_colour": Color(0.95, 0.97, 1.0),
		"key_energy_scale": 1.4 if low else 1.35,
		"key_from": Vector3(-3.0, 12.0, -2.0),
		"fill_colour": Color(0.6, 0.72, 1.0),
		"fill_energy": 0.3,
		"fill_from": Vector3(6.0, 5.0, 9.0),
		"ambient_colour": Color(0.5, 0.55, 0.62),
		"ambient_energy_scale": 1.0 if low else 0.8,
		"fog_colour": Color(0.12, 0.14, 0.18),
		"fog_density": 0.014,
		"floor_map": VenueKit.KIT_TEX + "crush_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "crush_floor_n.png",
		"floor_params": {
			"steel": Color(0.78, 0.78, 0.78) if low else Color(0.74, 0.74, 0.75),
			"metallic_base": 0.0, "rough_dry": 0.78, "rough_min": 0.3, "wet_darken": 0.2,
			"scratch_contrast": 0.5, "scratch_normal": 0.4, "normal_depth": 1.0,
			"pool_radius": 3.8, "pool_edge": 0.6,
			"warm_pool": Vector3(0.0, 0.0, 0.01), "cold_pool": Vector3(0.0, 0.0, 0.01),
		},
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": WORK, "energy": 0.3, "specular": 0.2},
		"probe": {"deck_colour": Color(0.4, 0.45, 0.55), "deck_energy": 0.0, "intensity": 0.7, "height": 0.9},
		"volumetric": {"density": 0.12, "albedo": Color(0.85, 0.88, 0.95), "floods": 3.0,
			"key": 0.0, "fill": 0.0, "length": 40.0, "reach": 0.55, "width": 2.8, "edge_fade": 0.7},
	})
	kit.crowd_staging = {
		"body_light": 0.32, "saturation": 1.1, "spill_strength": 0.2,
		"spill_color": Color(0.85, 0.9, 1.0),
		"rim_color": Color(0.8, 0.88, 1.0), "rim_strength": 0.45,
		"phone_glow": 0.25, "phone_color": Color(0.95, 0.97, 1.0),
		"haze_color": Color(0.08, 0.09, 0.12),
	}
	kit.crowd.phone_size = 0.07
	kit.crowd.phone_colour = Color(0.95, 0.96, 1.0)
	kit.speck_staging = {"phone_twinkle": 1.0}
	kit.beam_card = {"high": 0.03, "medium": 0.12}


## The press hall: a concrete box with columns and a low dark ceiling, work lights in a
## grid under it (two real downlights over the arena, the rest emissive).
static func _hall(kit: VenueKit) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.4, 0.4, 0.42)
	kit.add_ground(40.0, ground)
	var conc := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	conc.albedo_color = Color(0.55, 0.55, 0.57)
	var r := 22.0
	var h := 13.0
	for side in [[Vector3(0, h * 0.5, r), Vector3(r * 2.0, h, 0.5)], [Vector3(0, h * 0.5, -r), Vector3(r * 2.0, h, 0.5)],
			[Vector3(r, h * 0.5, 0), Vector3(0.5, h, r * 2.0)], [Vector3(-r, h * 0.5, 0), Vector3(0.5, h, r * 2.0)]]:
		kit.add_block(Transform3D(Basis.IDENTITY, side[0]), side[1], conc)
	var ceiling := StandardMaterial3D.new()
	ceiling.albedo_color = Color(0.06, 0.065, 0.07)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, h, 0)), Vector3(r * 2.0, 0.4, r * 2.0), ceiling)
	for k in range(-5, 6):
		var t := float(k) * 4.0
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(t, h - 0.5, 0)), Vector3(0.7, 0.8, r * 2.0), conc)
		for p in [Vector3(t, h * 0.5, r - 0.5), Vector3(r - 0.5, h * 0.5, t), Vector3(t, h * 0.5, -r + 0.5), Vector3(-r + 0.5, h * 0.5, t)]:
			kit.add_block(Transform3D(Basis.IDENTITY, p), Vector3(0.8, h, 0.8), conc)
	# Work lights: square fittings under the ceiling beams.
	for xi in range(-3, 4):
		for zi in range(-3, 4):
			var c := Vector3(float(xi) * 4.0, h - 1.0, float(zi) * 4.0)
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.08, 0)), Vector3(0.6, 0.12, 0.6), "dark_metal")
			kit.add_block(Transform3D(Basis.IDENTITY, c), Vector3(0.5, 0.03, 0.5), kit.mats.slot("lamp_white"))
	kit.add_downlight(Vector3(-2.0, h - 1.1, -2.0), Vector3(-1.0, 0, -1.0), WORK, 3.5, 30.0, 0.04)
	kit.add_downlight(Vector3(2.0, h - 1.1, 2.0), Vector3(1.0, 0, 1.0), WORK, 3.5, 30.0, 0.04)


## Concrete stands behind thick safety glass on all four sides: a 1.6 m concrete front
## wall, panes on steel posts above it, the crowd stepping up behind.
static func _stands(kit: VenueKit, wall: float) -> void:
	var conc := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	conc.albedo_color = Color(0.46, 0.46, 0.48)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.9, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var d := wall + 2.4
	var e := 7.6
	var sides := [
		[Vector3(-e, 0, d), Vector3(e, 0, d), Vector3(0, 0, 1)],
		[Vector3(d, 0, e), Vector3(d, 0, -e), Vector3(1, 0, 0)],
		[Vector3(e, 0, -d), Vector3(-e, 0, -d), Vector3(0, 0, -1)],
		[Vector3(-d, 0, -e), Vector3(-d, 0, e), Vector3(-1, 0, 0)],
	]
	for i in range(sides.size()):
		var sd: Array = sides[i]
		var a: Vector3 = sd[0]
		var b: Vector3 = sd[1]
		var out: Vector3 = sd[2]
		var far := i < 2
		kit.add_stepped_stand(a, b, out, 9 if far else 6, conc, 0.45, 0.8, 1.6, 3 if far else 2,
			0.88 if far else 0.7, 1.9)
		var dir := (b - a).normalized()
		var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
		var mid := (a + b) * 0.5 - out * 0.05
		var ln := a.distance_to(b)
		kit.add_block(Transform3D(basis, mid + Vector3(0, 3.0, 0)), Vector3(ln, 2.2, 0.04), glass)
		var posts := int(ln / 2.0)
		for k in range(posts + 1):
			var p := a + dir * (ln * float(k) / float(posts)) - out * 0.05
			kit.add_block(Transform3D(basis, p + Vector3(0, 3.0, 0)), Vector3(0.08, 2.2, 0.12), "galv_steel")
		kit.add_beam_block(a - out * 0.05 + Vector3(0, 4.1, 0), b - out * 0.05 + Vector3(0, 4.1, 0), 0.1, "galv_steel")


## The hero: the press machinery line behind the two ram walls. Each ram gets a press:
## two big horizontal hydraulic cylinders with chrome rods into the wall, a thrust block,
## a manifold, pressure gauges, hydraulic hoses, hazard stripes and a work lamp.
static func _press_line(kit: VenueKit, wall: float) -> void:
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.87, 0.9)
	chrome.metallic = 1.0
	chrome.roughness = 0.12
	# Pass 4: the frames read as black lumps (dark, very metallic, nothing to reflect).
	# Light machine grey that takes the work light, chrome kept for the rods, a striped
	# collar on every cylinder and a work lamp in front of each press.
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.55, 0.58, 0.62)
	body.metallic = 0.35
	body.roughness = 0.38
	var dial := StandardMaterial3D.new()
	dial.albedo_color = Color(0.9, 0.9, 0.85)
	dial.emission_enabled = true
	dial.emission = Color(0.9, 0.92, 0.85)
	dial.emission_energy_multiplier = 0.6
	# Pass 4: the concept's presses push the rams horizontally, a fat cylinder and a chrome
	# rod going out through the wall behind each ram block. The old vertical frames (two
	# columns and a crosshead 6 m up) stood between the concept camera and the arena as a
	# dark lump; these stay low (under 1.9 m), so they read as machinery and hide nothing.
	for ram in [[-1.0, -1.2], [1.0, 1.2]]:
		var sx: float = ram[0]
		var rz: float = ram[1]
		var x0 := sx * (wall + 0.35)
		var ax := Basis(Vector3.FORWARD, PI * 0.5)
		for dz in [-0.9, 0.9]:
			var z: float = rz + float(dz)
			# Barrel, end caps, a striped collar, the chrome rod into the wall.
			var barrel := Vector3(x0 + sx * 1.9, 0.75, z)
			kit.add_cylinder(Transform3D(ax, barrel), 0.42, 2.6, body, 20)
			kit.add_cylinder(Transform3D(ax, barrel + Vector3(sx * 1.35, 0, 0)), 0.5, 0.18, body, 20)
			kit.add_cylinder(Transform3D(ax, barrel - Vector3(sx * 1.35, 0, 0)), 0.5, 0.18, body, 20)
			kit.add_cylinder(Transform3D(ax, barrel - Vector3(sx * 0.9, 0, 0)), 0.44, 0.36, "hazard_paint", 20)
			kit.add_cylinder(Transform3D(ax, Vector3(x0 + sx * 0.3, 0.75, z)), 0.16, 0.8, chrome, 16)
			# Cradle feet and the rear mount.
			for fx: float in [0.9, 2.9]:
				kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x0 + sx * fx, 0.2, z)), Vector3(0.3, 0.4, 0.9), "dark_metal")
			# Gauge on top, facing up and in.
			var g := barrel + Vector3(sx * 0.4, 0.46, 0)
			kit.add_cylinder(Transform3D(Basis.IDENTITY, g), 0.16, 0.08, "dark_metal", 16)
			kit.add_cylinder(Transform3D(Basis.IDENTITY, g + Vector3(0, 0.045, 0)), 0.13, 0.01, dial, 16)
		# Rear yoke tying both cylinders to a thrust block, manifold and hoses on top.
		var rear := Vector3(x0 + sx * 3.5, 0.9, rz)
		kit.add_block(Transform3D(Basis.IDENTITY, rear), Vector3(0.6, 1.8, 3.0), body)
		kit.add_block(Transform3D(Basis.IDENTITY, rear + Vector3(-sx * 0.31, 0.3, 0)), Vector3(0.02, 0.5, 2.9), "hazard_paint")
		kit.add_block(Transform3D(Basis.IDENTITY, rear + Vector3(0, 1.15, 0)), Vector3(0.8, 0.5, 1.0), "dark_metal")
		for k in range(4):
			var hz := rz - 0.45 + 0.3 * float(k)
			kit.add_beam_block(rear + Vector3(0, 1.3, hz - rz), Vector3(x0 + sx * (1.4 + 0.3 * float(k)), 1.2, rz + (0.9 if k % 2 == 0 else -0.9)), 0.06, "rubber", true)
		kit.add_tube(Transform3D(Basis(Vector3.UP, PI * 0.5), rear + Vector3(-sx * 0.35, 1.9, 0)), 2.6, WORK, 3.0)
		kit.batch("beacon", Transform3D(Basis.IDENTITY, rear + Vector3(0, 1.45, 1.2)))
		kit.add_practical(Vector3(x0 + sx * 1.8, 2.8, rz), Color(1.0, 0.94, 0.85), 1.6, 5.0)


## Pipe runs under the ceiling and down the columns, and steam venting from a few joints.
static func _pipes_and_steam(kit: VenueKit, rng: RandomNumberGenerator) -> void:
	for i in range(5):
		var y := 11.2 - 0.35 * float(i)
		var off := -1.6 + 0.8 * float(i)
		kit.add_beam_block(Vector3(-20.0, y, 8.5 + off), Vector3(20.0, y, 8.5 + off), 0.22, "galv_steel", true)
		kit.add_beam_block(Vector3(8.5 + off, y - 0.2, -20.0), Vector3(8.5 + off, y - 0.2, 20.0), 0.18, "dark_metal", true)
	for p in [Vector3(-8.5, 0, 9.0), Vector3(9.5, 0, -8.0), Vector3(9.0, 0, 9.5), Vector3(-9.5, 0, -8.5)]:
		kit.add_beam_block(p, p + Vector3(0, 11.0, 0), 0.26, "galv_steel", true)
	for p in [Vector3(9.0, 3.6, 9.5), Vector3(-8.5, 2.2, 9.0), Vector3(9.5, 4.8, -8.0), Vector3(8.4, 7.0, 3.0)]:
		var st := VenueFx.steam(kit.tier, rng.randf_range(0.8, 1.3))
		if st != null:
			st.position = p
			kit.add_child(st)
