extends RefCounted
## THE GRINDER as a venue (docs/look/arenas/arenas-v1.html, the Grinder concept): a working
## machine shop at night. Cold steel-blue light from fluorescent tube banks under the roof,
## metal bleachers behind safety mesh on the far side, a machine line (lathes, presses,
## pipework) down the east side, a yellow gantry crane over the lot as the hero piece, and
## metal dust hanging in the cold light. The only warm colour in the room is the sparks
## off the two discs (the hazards lead's; the kit adds none).
##
## The fight camera looks from (-x, -z) toward (+x, +z): the SOUTH (+z) and EAST (+x) sides
## are the far walls. Only the VenueKit placement API is used here. Nothing collides.

const S := 0
const E := 1
const N := 2
const W := 3
const STEEL_BLUE := Color(0.72, 0.84, 1.0)
const TUBE := Color(0.82, 0.92, 1.0)


static func _facing(side: int) -> Basis:
	match side:
		S:
			return Basis(Vector3.UP, PI)
		E:
			return Basis(Vector3.UP, -PI * 0.5)
		W:
			return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	_grade(kit, low)
	_shell(kit)
	_tubes_and_lights(kit, rng)
	_bleachers(kit, wall)
	_machine_line(kit, wall, rng)
	_gantry(kit)
	_near_sides(kit, wall, rng)
	var d := 7.3
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(-d, -d)), Vector3(d, 0, d)), 1, 0)
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(d, d)), Vector3(-d, 0, -d)), 0, 0)
	# Metal dust hanging in the cold light.
	var motes := VenueFx.motes(kit.tier, Vector3(8.0, 2.6, 8.0))
	if motes != null:
		motes.position = Vector3(0, 2.8, 0)
		kit.add_child(motes)
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		kit.add_pyro(c * (wall + 0.55), "columns", true)
	for pose in [[Vector3(-12, 6.0, -8), Vector3(0, 0.5, 0)], [Vector3(8, 3.0, 11), Vector3(6.0, 2.0, 6.0)],
			[Vector3(-4, 10, -13), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


static func _grade(kit: VenueKit, low: bool) -> void:
	kit.grade({
		"key_colour": Color(0.88, 0.94, 1.0),
		"key_energy_scale": 1.3 if low else 1.25,
		"key_from": Vector3(-2.0, 12.0, -3.0),
		"fill_colour": Color(0.45, 0.6, 1.0),
		"fill_energy": 0.4,
		"fill_from": Vector3(6.0, 5.0, 9.0),
		"ambient_colour": Color(0.5, 0.58, 0.72),
		"ambient_energy_scale": 1.1 if low else 0.95,
		"fog_colour": Color(0.1, 0.16, 0.26),
		"fog_density": 0.012,
		"floor_map": VenueKit.KIT_TEX + "grinder_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "grinder_floor_n.png",
		"floor_params": {
			"steel": Color(0.46, 0.48, 0.5) if low else Color(0.42, 0.44, 0.47),
			"metallic_base": 0.35 if low else 0.6,
			"rough_dry": 0.42, "rough_min": 0.12, "wet_darken": 0.1,
			"scratch_contrast": 0.5, "scratch_normal": 0.35, "normal_depth": 1.0,
			"pool_radius": 4.2, "pool_edge": 0.72,
			"warm_pool": Vector3(0.0, 0.0, 0.01), "cold_pool": Vector3(0.0, 0.0, 6.0),
			"cold_tint": Color(0.82, 0.92, 1.12),
			"oil_color": Color(0.05, 0.055, 0.06),
		},
		"glint": {"from": Vector3(5.0, 7.0, 7.0), "colour": TUBE, "energy": 0.1, "specular": 6.0},
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": Color(0.8, 0.88, 1.0),
			"energy": 0.35, "specular": 0.3},
		"wall_panels": {"style": "xbrace"},
		"probe": {"deck_colour": Color(0.4, 0.55, 0.85), "deck_energy": 0.0, "intensity": 1.0,
			"height": 0.9},
		"volumetric": {"density": 0.16, "albedo": Color(0.8, 0.86, 0.95), "floods": 4.0,
			"key": 0.0, "fill": 0.0, "length": 40.0, "reach": 0.5, "width": 3.0, "edge_fade": 0.7},
	})
	kit.crowd_staging = {
		"body_light": 0.3, "saturation": 1.2, "spill_strength": 0.25,
		"spill_color": Color(0.75, 0.85, 1.0),
		"rim_color": Color(0.6, 0.75, 1.0), "rim_strength": 0.7,
		"phone_glow": 0.25, "phone_color": Color(0.9, 0.95, 1.0),
		"haze_color": Color(0.05, 0.08, 0.13),
	}
	kit.crowd.phone_size = 0.07
	kit.crowd.phone_colour = Color(0.92, 0.96, 1.0)
	kit.speck_staging = {"phone_twinkle": 1.0}
	kit.beam_card = {"high": 0.03, "medium": 0.12}
	kit.board_level = 0.4


## The shed: a dark concrete floor round the arena, ribbed steel walls, a roof of trusses.
static func _shell(kit: VenueKit) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.3, 0.31, 0.33)
	ground.roughness = 0.6
	kit.add_ground(40.0, ground)
	var wall_col := Color(0.16, 0.19, 0.24)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = wall_col
	shell.roughness = 0.7
	shell.metallic = 0.4
	var r := 24.0
	var h := 15.0
	for side in [[Vector3(0, h * 0.5, r), Vector3(r * 2.0, h, 0.3)], [Vector3(0, h * 0.5, -r), Vector3(r * 2.0, h, 0.3)],
			[Vector3(r, h * 0.5, 0), Vector3(0.3, h, r * 2.0)], [Vector3(-r, h * 0.5, 0), Vector3(0.3, h, r * 2.0)]]:
		kit.add_block(Transform3D(Basis.IDENTITY, side[0]), side[1], shell)
	# Wall ribs (columns) every 4 m, and a roof of trusses with dark panels between.
	for k in range(-6, 7):
		var t := float(k) * 4.0
		for p in [Vector3(t, h * 0.5, r - 0.4), Vector3(t, h * 0.5, -r + 0.4), Vector3(r - 0.4, h * 0.5, t), Vector3(-r + 0.4, h * 0.5, t)]:
			kit.add_block(Transform3D(Basis.IDENTITY, p), Vector3(0.45, h, 0.45), "dark_metal")
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(t, h - 0.4, 0)), Vector3(0.35, 0.8, r * 2.0), "dark_metal")
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.05, 0.06, 0.08)
	roof.roughness = 0.9
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, h + 0.2, 0)), Vector3(r * 2.0, 0.3, r * 2.0), roof)


## Fluorescent tube banks hung at 7.5 m on chains, in rows across the shed; two real cold
## downlights over the arena (the tier's budget), one tube that flickers.
static func _tubes_and_lights(kit: VenueKit, rng: RandomNumberGenerator) -> void:
	var y := 7.5
	var flick := 0
	for zi in range(-3, 4):
		for xi in range(-2, 3):
			var c := Vector3(float(xi) * 3.2, y, float(zi) * 2.6)
			# A two-tube fitting with a reflector.
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.06, 0)), Vector3(1.6, 0.05, 0.3), "galv_steel")
			var f := rng.randf() < 0.04 and flick < 1 and absf(c.x) < 4.0
			if f:
				flick += 1
			kit.add_tube(Transform3D(Basis.IDENTITY, c + Vector3(0, 0, -0.07)), 1.5, TUBE, 5.0, f)
			kit.add_tube(Transform3D(Basis.IDENTITY, c + Vector3(0, 0, 0.07)), 1.5, TUBE, 5.0)
			for sx in [-0.7, 0.7]:
				kit.add_beam_block(c + Vector3(sx, 0.08, 0), Vector3(c.x + sx, 12.6, c.z), 0.012, "cable")
	if flick == 0:
		kit.add_tube(Transform3D(Basis.IDENTITY, Vector3(1.6, y - 0.05, 0.2)), 1.5, TUBE, 5.0, true)
	kit.add_downlight(Vector3(-2.0, y + 0.3, 2.0), Vector3(-1.0, 0, 1.0), TUBE, 2.2, 38.0, 0.04)
	kit.add_downlight(Vector3(2.0, y + 0.3, -2.0), Vector3(1.0, 0, -1.0), TUBE, 2.2, 38.0, 0.04)


## South: metal bleachers behind safety mesh, the crowd sparse and dark, a screen above.
static func _bleachers(kit: VenueKit, wall: float) -> void:
	var z0 := wall + 1.1
	var basis := _facing(S)
	for x in [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0]:
		kit.batch("stand_scaffold_bay", Transform3D(basis, Vector3(x, 0, z0)), Color.WHITE, true)
	kit.batch("stand_scaffold_endcap", Transform3D(basis, Vector3(-6.0, 0, z0)))
	# Safety mesh: fence panels on a steel frame right behind the wall, 2.4 m tall.
	for k in range(6):
		var x := -6.0 + 2.4 * float(k)
		kit.batch("fence_panel", Transform3D(basis, Vector3(x, 0, wall + 0.45)))
		kit.batch("fence_panel", Transform3D(basis, Vector3(x, 2.0, wall + 0.45)))
	for i in range(6):
		var y := 0.55 + 0.5 * float(i)
		var z := z0 + 0.75 * float(i) + 0.38
		kit.crowd.add_row(Vector3(-6.9, y, z), Vector3(4.9, y, z), 0.55, 0.62 + 0.04 * float(i))
	kit.crowd.add_row(Vector3(-6.8, 3.05, z0 + 4.25), Vector3(4.8, 3.05, z0 + 4.25), 0.6, 0.7, true)
	# Workshop banners with no text, hung from the roof trusses over the stand.
	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color(0.1, 0.2, 0.32)
	banner.roughness = 0.9
	for x in [-5.0, 0.0, 5.0]:
		kit.add_block(Transform3D(basis, Vector3(x, 7.0, z0 + 5.5)), Vector3(2.2, 3.2, 0.03), banner)
	kit.add_screen(Transform3D(basis * Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(-1.0, 5.2, z0 + 5.2)), "THE GRINDER")


## East: the machine line. Lathes, a press, a milling machine and pipe runs, grey-green
## machine paint and galvanised guards, lit cold; a mezzanine with a few spectators.
static func _machine_line(kit: VenueKit, wall: float, rng: RandomNumberGenerator) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.22, 0.3, 0.32)
	paint.roughness = 0.55
	paint.metallic = 0.3
	var x0 := wall + 1.4
	var z := -6.5
	while z < 6.5:
		var kind := rng.randi_range(0, 2)
		var ln := rng.randf_range(1.6, 2.6)
		var c := Vector3(x0 + 1.0, 0, z + ln * 0.5)
		match kind:
			0:
				# A lathe: bed, headstock, tailstock, chuck, chip guard.
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.45, 0)), Vector3(0.9, 0.9, ln), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.15, -ln * 0.35)), Vector3(0.8, 0.6, 0.6), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.05, ln * 0.38)), Vector3(0.5, 0.4, 0.4), paint)
				kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(0, 1.1, -ln * 0.05)), 0.18, 0.2, "galv_steel")
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.3, 1.3, 0)), Vector3(0.04, 0.5, ln * 0.5), "glass")
			1:
				# A pillar press: base, column, head, ram.
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.3, 0)), Vector3(1.1, 0.6, 1.1), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0.35, 1.6, 0)), Vector3(0.35, 2.6, 0.5), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 2.8, 0)), Vector3(1.0, 0.6, 0.7), paint)
				kit.add_cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 2.2, 0)), 0.1, 0.8, "galv_steel")
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.56, 1.0, 0)), Vector3(0.02, 0.8, 1.1), "hazard_paint")
			_:
				# A milling machine with a cabinet and a work lamp.
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.7, 0)), Vector3(1.0, 1.4, 1.2), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0.2, 1.9, 0)), Vector3(0.6, 1.0, 0.6), paint)
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.4, 1.0, 0.4)), Vector3(0.3, 0.5, 0.3), "dark_metal")
				kit.add_tube(Transform3D(Basis(Vector3.UP, PI * 0.5), c + Vector3(-0.2, 2.5, 0)), 0.5, TUBE, 3.0)
		z += ln + rng.randf_range(0.4, 0.9)
	# Pipe runs along the back wall and a cable tray.
	for y in [3.4, 3.7, 4.2]:
		kit.add_beam_block(Vector3(x0 + 2.4, y, -9.0), Vector3(x0 + 2.4, y, 9.0), 0.16, "galv_steel", true)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x0 + 2.2, 4.8, 0)), Vector3(0.5, 0.08, 18.0), "dark_metal")
	# A mezzanine over the machines with a rail and a few people watching.
	var mz := Vector3(x0 + 2.0, 4.0, 0)
	kit.add_block(Transform3D(Basis.IDENTITY, mz), Vector3(2.2, 0.15, 12.0), "grating")
	for k in range(7):
		kit.add_beam_block(Vector3(mz.x - 1.0, 0, -6.0 + 2.0 * float(k)), Vector3(mz.x - 1.0, 4.0, -6.0 + 2.0 * float(k)), 0.15, "dark_metal")
	kit.add_beam_block(Vector3(mz.x - 1.05, 5.05, -6.0), Vector3(mz.x - 1.05, 5.05, 6.0), 0.05, "hazard_paint", true)
	kit.crowd.add_row(Vector3(mz.x - 0.5, 4.08, -5.8), Vector3(mz.x - 0.5, 4.08, 5.8), 0.55, 0.7)
	kit.crowd.add_row(Vector3(mz.x + 0.3, 4.08, -5.8), Vector3(mz.x + 0.3, 4.08, 5.8), 0.6, 0.5, true)


## The hero: a yellow overhead gantry crane. Two runway girders on columns down the east
## and west of the shed, a bridge girder across the arena, the trolley and a hook block
## hanging on its chains over the south half.
static func _gantry(kit: VenueKit) -> void:
	var rail_y := 10.4
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.78, 0.6, 0.08)
	yellow.roughness = 0.55
	yellow.metallic = 0.25
	# Runways along the shed's side walls (x = +-21), well behind every camera.
	for x in [-21.0, 21.0]:
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x, rail_y, 0)), Vector3(0.35, 0.6, 40.0), "dark_metal")
		for z in [-16.0, -8.0, 0.0, 8.0, 16.0]:
			kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x, rail_y * 0.5, z)), Vector3(0.45, rail_y, 0.45), "dark_metal")
	var bz := 2.6
	# Box girder with a lighter top flange and a hazard stripe on its face.
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, rail_y + 0.55, bz)), Vector3(42.0, 0.9, 0.7), yellow)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, rail_y + 1.05, bz)), Vector3(42.0, 0.1, 0.9), yellow)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, rail_y + 0.2, bz - 0.36)), Vector3(41.0, 0.18, 0.02), "hazard_paint")
	for x in [-21.0, 21.0]:
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(x, rail_y + 0.55, bz)), Vector3(0.9, 1.1, 2.2), yellow)
	# Trolley and hoist, hook block on four falls of chain.
	var tx := 1.4
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(tx, rail_y + 0.25, bz)), Vector3(1.4, 0.7, 1.3), "dark_metal")
	kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx, rail_y - 0.2, bz)), 0.28, 1.0, "dark_metal")
	var hook_y := 6.0
	for dx in [-0.12, 0.12]:
		for dz in [-0.1, 0.1]:
			kit.add_beam_block(Vector3(tx + dx, rail_y - 0.4, bz + dz), Vector3(tx + dx, hook_y + 0.3, bz + dz), 0.03, "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(tx, hook_y, bz)), Vector3(0.45, 0.6, 0.35), yellow)
	kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(tx, hook_y - 0.5, bz)), 0.16, 0.08, "dark_metal", 10)
	# A warning beacon on the trolley.
	kit.batch("beacon", Transform3D(Basis.IDENTITY, Vector3(tx + 0.5, rail_y + 0.6, bz)))


## North and west, behind the camera: tool racks, road cases, a cable drum, fencing.
static func _near_sides(kit: VenueKit, wall: float, rng: RandomNumberGenerator) -> void:
	for side in [N, W]:
		var f := _facing(side)
		for k in range(5):
			var t := -4.8 + 2.4 * float(k)
			var pos := Vector3(t, 0, -(wall + 0.9)) if side == N else Vector3(-(wall + 0.9), 0, t)
			kit.batch("fence_panel", Transform3D(f, pos))
		var a := Vector3(-5.8, 0, -(wall + 1.5)) if side == N else Vector3(-(wall + 1.5), 0, -5.2)
		var b := Vector3(5.4, 0, -(wall + 1.5)) if side == N else Vector3(-(wall + 1.5), 0, 5.8)
		kit.crowd.add_row(a, b, 0.6, 0.6)
	# Tool racks along the north wall.
	for k in range(4):
		var c := Vector3(-6.0 + 3.5 * float(k), 0, -(wall + 4.0))
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.0, 0)), Vector3(2.6, 2.0, 0.5), "dark_metal")
		for s in range(3):
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.5 + 0.6 * float(s), 0.2)), Vector3(2.4, 0.04, 0.4), "galv_steel")
	kit.place("flight_case_stack", Transform3D(_facing(W), Vector3(-(wall + 2.8), 0, -3.4)), {}, false)
	kit.place("cable_drum", Transform3D(Basis(Vector3.UP, 0.7), Vector3(-(wall + 2.6), 0, -1.0)), {}, false)
	kit.place("scrap_pile_a", Transform3D(_facing(W), Vector3(-(wall + 4.5), 0, 3.0)), {}, false)
