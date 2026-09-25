extends RefCounted
## DROP ZONE as a venue (docs/look/arenas/arenas-v1.html, the Drop Zone concept): an
## underground bunker where the pit is the light source. Steep dark concrete stands on all
## four sides, the crowd mostly silhouettes and small lights, cold downlights from the
## ceiling through haze, a dark rig hanging over the pit, amber beacons turning slowly at
## the arena's corners, and when the cover opens, red haze and embers rising out of the
## shaft. Amber is the only warm colour in the room; the open pit glows red from below.
##
## The pit's own glow, rim strip and warning are the hazards lead's; the kit only reads
## pit_open() to start its embers and haze. Nothing here collides.

const COLD := Color(0.7, 0.82, 1.0)
const AMBER := Color(1.0, 0.55, 0.08)


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3030
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	_grade(kit, low)
	_bunker(kit)
	_stands(kit, wall)
	_rig_and_lights(kit)
	_pit_fx(kit)
	# Amber beacons on short posts at the four outside corners of the arena wall.
	for c in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		kit.add_rotating_beacon(c * (wall + 0.35), AMBER, 1.1, 0.7)
	var d := 7.6
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(-d, -d)), Vector3(d, 0, d)), 1, 0)
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(d, d)), Vector3(-d, 0, -d)), 0, 0)
	var motes := VenueFx.motes(kit.tier, Vector3(9.0, 3.0, 9.0))
	if motes != null:
		motes.position = Vector3(0, 3.2, 0)
		kit.add_child(motes)
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		kit.add_pyro(c * (wall + 0.9), "columns", true)
	for pose in [[Vector3(-12, 7.0, -9), Vector3(0, 0.0, 0)], [Vector3(0, 3.0, -9), Vector3(0, -0.5, 0)],
			[Vector3(-5, 11, -13), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


static func _grade(kit: VenueKit, low: bool) -> void:
	# The crowd is a house of small lights: more phones than anywhere else.
	kit.crowd.phone_share = 0.3
	kit.crowd.phone_size = 0.07
	kit.crowd.phone_colour = Color(0.9, 0.95, 1.0)
	kit.grade({
		"key_colour": Color(0.78, 0.86, 1.0),
		"key_energy_scale": 1.5 if low else 1.3,
		"key_from": Vector3(-3.0, 12.0, -2.0),
		"fill_colour": Color(0.4, 0.55, 1.0),
		"fill_energy": 0.3,
		"fill_from": Vector3(5.0, 4.0, 9.0),
		"ambient_colour": Color(0.3, 0.38, 0.55),
		"ambient_energy_scale": 1.0 if low else 0.75,
		"fog_colour": Color(0.06, 0.1, 0.18),
		"fog_density": 0.02,
		"floor_map": VenueKit.KIT_TEX + "drop_zone_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "drop_zone_floor_n.png",
		"floor_params": {
			"steel": Color(0.46, 0.47, 0.49) if low else Color(0.42, 0.43, 0.45),
			"metallic_base": 0.05, "rough_dry": 0.72, "rough_min": 0.2, "wet_darken": 0.2,
			"scratch_contrast": 0.7, "scratch_normal": 0.5, "normal_depth": 0.8,
			"pool_radius": 4.0, "pool_edge": 0.55,
			"warm_pool": Vector3(0.0, 0.0, 2.2), "warm_tint": Color(1.25, 0.85, 0.7),
			"cold_pool": Vector3(0.0, 0.0, 9.0), "cold_tint": Color(0.82, 0.92, 1.15),
		},
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": COLD, "energy": 0.3, "specular": 0.2},
		"probe": {"deck_colour": Color(0.3, 0.42, 0.7), "deck_energy": 0.0, "intensity": 0.8, "height": 0.8},
		"volumetric": {"density": 0.14, "albedo": Color(0.8, 0.86, 0.95), "floods": 5.0,
			"key": 0.0, "fill": 0.0, "length": 40.0, "reach": 0.6, "width": 3.4, "edge_fade": 0.7},
	})
	kit.crowd_staging = {
		"body_light": 0.24, "saturation": 1.1, "spill_strength": 0.2,
		"spill_color": Color(0.7, 0.8, 1.0),
		"rim_color": Color(0.55, 0.7, 1.0), "rim_strength": 0.45,
		"phone_glow": 0.25, "phone_color": Color(0.9, 0.95, 1.0),
		"haze_color": Color(0.03, 0.05, 0.1), "haze_near": 5.0, "haze_far": 22.0,
	}
	kit.speck_staging = {"phone_twinkle": 1.0}
	kit.beam_card = {"high": 0.03, "medium": 0.14}


## The bunker: a dark concrete box 40 m across, ribbed, with a low ceiling slab.
static func _bunker(kit: VenueKit) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.22, 0.23, 0.25)
	kit.add_ground(40.0, ground)
	var conc := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	conc.albedo_color = Color(0.3, 0.32, 0.36)
	var r := 22.0
	var h := 16.0
	for side in [[Vector3(0, h * 0.5, r), Vector3(r * 2.0, h, 0.5)], [Vector3(0, h * 0.5, -r), Vector3(r * 2.0, h, 0.5)],
			[Vector3(r, h * 0.5, 0), Vector3(0.5, h, r * 2.0)], [Vector3(-r, h * 0.5, 0), Vector3(0.5, h, r * 2.0)]]:
		kit.add_block(Transform3D(Basis.IDENTITY, side[0]), side[1], conc)
	var ceiling := StandardMaterial3D.new()
	ceiling.albedo_color = Color(0.03, 0.035, 0.045)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, h, 0)), Vector3(r * 2.0, 0.4, r * 2.0), ceiling)
	for k in range(-5, 6):
		var t := float(k) * 4.0
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(t, h - 0.6, 0)), Vector3(0.6, 1.0, r * 2.0), conc)


## Steep concrete stands on all four sides, starting 1.3 m behind the wall above a 1.4 m
## concrete front wall; the front rows are people, the rest silhouettes and lights, with a
## row of small lamps along each landing.
static func _stands(kit: VenueKit, wall: float) -> void:
	var conc := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	conc.albedo_color = Color(0.26, 0.28, 0.31)
	var d := wall + 1.4
	var e := 7.4
	var sides := [
		[Vector3(-e, 0, d), Vector3(e, 0, d), Vector3(0, 0, 1)],
		[Vector3(d, 0, e), Vector3(d, 0, -e), Vector3(1, 0, 0)],
		[Vector3(e, 0, -d), Vector3(-e, 0, -d), Vector3(0, 0, -1)],
		[Vector3(-d, 0, -e), Vector3(-d, 0, e), Vector3(-1, 0, 0)],
	]
	for i in range(sides.size()):
		var sd: Array = sides[i]
		var far := i < 2
		kit.add_stepped_stand(sd[0], sd[1], sd[2], 11 if far else 8, conc, 0.5, 0.8, 1.0,
			3 if far else 2, 0.9 if far else 0.7, 1.4)
		# Small lamps along the front wall and every third landing.
		var a: Vector3 = sd[0]
		var b: Vector3 = sd[1]
		var out: Vector3 = sd[2]
		for row in [0, 4, 8]:
			var y := 1.0 + 0.5 * float(row) + 0.1
			for k in range(9):
				var p := a.lerp(b, (float(k) + 0.5) / 9.0) + out * (0.8 * float(row) - 0.15) + Vector3(0, y, 0)
				kit.crowd.add_speck(p, 2, 0.35, Color(1.0, 0.78, 0.5), 1.2)


## A dark rig hanging over the pit with a ring of cold tubes underneath, and cold
## downlights from the ceiling corners (the tier's light budget) through haze.
static func _rig_and_lights(kit: VenueKit) -> void:
	var y := 9.0
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, y + 0.8, 0)), Vector3(4.2, 1.6, 4.2), "dark_metal")
	for s in [-1.0, 1.0]:
		kit.add_tube(Transform3D(Basis.IDENTITY, Vector3(0, y - 0.05, s * 1.9)), 3.6, COLD, 4.0)
		kit.add_tube(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s * 1.9, y - 0.05, 0)), 3.6, COLD, 4.0)
	for dx in [-1.8, 1.8]:
		for dz in [-1.8, 1.8]:
			kit.add_beam_block(Vector3(dx, y + 1.6, dz), Vector3(dx, 15.8, dz), 0.03, "cable")
	for c in [Vector3(-6.0, 13.5, -6.0), Vector3(6.0, 13.5, 6.0), Vector3(6.0, 13.5, -6.0), Vector3(-6.0, 13.5, 6.0)]:
		kit.add_downlight(c, Vector3(c.x * 0.15, 0, c.z * 0.15), COLD, 7.0, 24.0, 0.05)


## The shaft: embers rising and a red haze out of the open pit, only while it is open.
static func _pit_fx(kit: VenueKit) -> void:
	var embers := VenueFx.embers(kit.tier, Vector3(1.0, 0.3, 1.0), 1.1)
	if embers != null:
		embers.position = Vector3(0, -0.6, 0)
		kit.add_child(embers)
		kit.add_state_fx(embers, "pit_open")
	if kit.tier == "high":
		var fv := FogVolume.new()
		fv.name = "PitHaze"
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fv.size = Vector3(2.3, 2.8, 2.3)
		fv.position = Vector3(0, -1.0, 0)
		var fm := FogMaterial.new()
		fm.density = 0.14
		fm.albedo = Color(1.0, 0.35, 0.2)
		fm.emission = Color(0.25, 0.03, 0.01)
		fm.edge_fade = 0.5
		fm.height_falloff = 1.6
		fv.material = fm
		kit.add_child(fv)
		kit.add_state_fx(fv, "pit_open")
