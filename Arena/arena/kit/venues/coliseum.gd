extends RefCounted
## THE COLISEUM as a venue (docs/look/arenas/arenas-v1.html, the Coliseum concept): the
## stadium final. A full house on all four sides, near rows as people and the upper bowl
## as silhouettes and thousands of phone lights and flashes; red and blue banners hanging
## on the wall below the front rows; a truss ring over the arena full of moving heads
## (the hero set piece, with a four-faced jumbotron hanging in it showing the live fight);
## a polished dark floor that mirrors the show; blue and red light with gold.
##
## The turntables, grinders, spikes and jets are the hazards lead's; the endgame pyro in
## the four corners is the kit's "columns" group. Nothing here collides.

const BLUE := Color(0.35, 0.55, 1.0)
const RED := Color(1.0, 0.25, 0.2)
const GOLD := Color(1.0, 0.78, 0.4)


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1212
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	_grade(kit, low)
	_bowl(kit, wall)
	_truss_ring(kit)
	_jumbotron(kit)
	var d := wall + 2.2
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(-d, -d)), Vector3(d, 0, d)), 1, 0)
	kit.add_gate(Transform3D(Basis(Vector3.UP, atan2(d, d)), Vector3(-d, 0, -d)), 0, 0)
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		kit.add_pyro(c * (wall + 0.7), "columns", true)
	var motes := VenueFx.motes(kit.tier, Vector3(10.0, 3.0, 10.0))
	if motes != null:
		motes.position = Vector3(0, 3.5, 0)
		kit.add_child(motes)
	for pose in [[Vector3(-14, 8.0, -11), Vector3(0, 0.5, 0)], [Vector3(-3, 1.5, -3), Vector3(0, 11.0, 0)],
			[Vector3(-6, 13, -16), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


static func _grade(kit: VenueKit, low: bool) -> void:
	kit.crowd.phone_share = 0.3
	kit.crowd.flash_share = 0.14
	kit.crowd.phone_size = 0.07
	kit.crowd.phone_colour = Color(0.95, 0.97, 1.0)
	kit.grade({
		"key_colour": Color(0.8, 0.88, 1.0),
		"key_energy_scale": 1.3 if low else 1.1,
		"key_from": Vector3(-4.0, 12.0, -3.0),
		"fill_colour": RED,
		"fill_energy": 0.4,
		"fill_from": Vector3(6.0, 4.0, 9.0),
		"ambient_colour": Color(0.3, 0.33, 0.5),
		"ambient_energy_scale": 0.9 if low else 0.7,
		"fog_colour": Color(0.08, 0.1, 0.2),
		"fog_density": 0.012,
		"floor_map": VenueKit.KIT_TEX + "coliseum_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "coliseum_floor_n.png",
		"floor_params": {
			"steel": Color(0.14, 0.15, 0.19) if low else Color(0.09, 0.1, 0.13),
			"metallic_base": 0.5 if low else 0.8,
			"rough_dry": 0.16, "rough_min": 0.08, "wet_darken": 0.0,
			"scratch_contrast": 0.3, "scratch_normal": 0.15, "normal_depth": 0.6,
			"pool_radius": 5.0, "pool_edge": 0.7,
			"warm_pool": Vector3(3.5, 3.5, 4.0), "warm_tint": Color(1.2, 0.8, 0.75),
			"cold_pool": Vector3(-3.5, -3.5, 4.5), "cold_tint": Color(0.75, 0.88, 1.25),
		},
		"wall_panels": {"style": "padded", "base_color": Color(0.08, 0.1, 0.2), "rib_color": Color(0.1, 0.12, 0.25),
			"bay_m": 1.5, "metallic_v": 0.1, "rough_v": 0.5, "grime": 0.1},
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": Color(0.7, 0.8, 1.0), "energy": 0.3, "specular": 0.3},
		"glint": {"from": Vector3(5.0, 6.0, 7.0), "colour": GOLD, "energy": 0.06, "specular": 8.0},
		"probe": {"deck_colour": Color(0.3, 0.4, 0.8), "deck_energy": 0.5, "intensity": 1.0, "height": 0.8},
		"volumetric": {"density": 0.14, "albedo": Color(0.85, 0.88, 0.95), "floods": 5.0,
			"key": 0.0, "fill": 0.0, "length": 44.0, "reach": 0.55, "width": 2.8, "edge_fade": 0.7},
	})
	kit.crowd_staging = {
		"body_light": 0.3, "saturation": 1.3, "spill_strength": 0.3,
		"spill_color": Color(0.8, 0.85, 1.0),
		"rim_color": Color(0.6, 0.72, 1.0), "rim_strength": 0.5,
		"phone_glow": 0.25, "phone_color": Color(0.95, 0.97, 1.0),
		"haze_color": Color(0.04, 0.05, 0.12), "haze_near": 7.0, "haze_far": 30.0,
	}
	kit.speck_staging = {"phone_twinkle": 1.0}
	kit.beam_card = {"high": 0.03, "medium": 0.14}


## The bowl: a 2.6 m banner wall round the arena, then steep stands on all four sides,
## near rows people, the upper bowl silhouettes and lights, and a ring of lamps on each
## landing. Red and blue banners hang on the banner wall, gold trim along its top.
static func _bowl(kit: VenueKit, wall: float) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.1, 0.1, 0.12)
	kit.add_ground(60.0, ground)
	var seat := StandardMaterial3D.new()
	seat.albedo_color = Color(0.1, 0.11, 0.16)
	seat.roughness = 0.7
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.6, 0.06, 0.05)
	red.roughness = 0.8
	red.emission_enabled = true
	red.emission = Color(0.5, 0.05, 0.04)
	red.emission_energy_multiplier = 0.9
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.06, 0.1, 0.45)
	blue.roughness = 0.8
	blue.emission_enabled = true
	blue.emission = Color(0.05, 0.08, 0.4)
	blue.emission_energy_multiplier = 0.9
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.8, 0.6, 0.25)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var d := wall + 0.9
	var e := 6.8
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
		kit.add_stepped_stand(a, b, out, 16 if far else 12, seat, 0.55, 0.85, 2.6, 4 if far else 3,
			0.92 if far else 0.8, 2.6)
		var dir := (b - a).normalized()
		var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
		var ln := a.distance_to(b)
		# Banners on the banner wall: alternating red and blue drops with a pointed foot.
		var n := int(ln / 0.8)
		for k in range(n):
			var p := a + dir * (ln * (float(k) + 0.5) / float(n)) - out * 0.14
			var mat := red if k % 2 == 0 else blue
			kit.add_block(Transform3D(basis, p + Vector3(0, 1.75, 0)), Vector3(0.7, 1.6, 0.03), mat)
			kit.add_block(Transform3D(basis * Basis(Vector3.BACK, PI * 0.25), p + Vector3(0, 0.95, 0)),
				Vector3(0.5, 0.5, 0.03), mat)
		kit.add_block(Transform3D(basis, (a + b) * 0.5 - out * 0.12 + Vector3(0, 2.6, 0)), Vector3(ln, 0.08, 0.12), gold)
		for row in [0, 5, 10]:
			var y := 2.6 + 0.55 * float(row + 1) + 0.05
			for k in range(12):
				var p := a.lerp(b, (float(k) + 0.5) / 12.0) + out * (0.85 * float(row) + 0.05) + Vector3(0, y, 0)
				kit.crowd.add_speck(p, 2, 0.3, GOLD, 1.0)


## The hero: a square truss ring 18 m across at 10 m, corner towers down to the floor,
## twelve moving heads sweeping the arena, and four real spots (blue from one side, red
## from the other) inside the tier's budget.
static func _truss_ring(kit: VenueKit) -> void:
	var y := 10.0
	var h := 9.0
	for side in range(4):
		var basis := Basis(Vector3.UP, PI * 0.5 * float(side))
		for k in range(9):
			var x := -8.0 + 2.0 * float(k)
			kit.batch("truss_span_2m", Transform3D(basis, basis * Vector3(x, y, -h)))
		kit.batch("truss_corner", Transform3D(basis, basis * Vector3(-h, y, -h)))
		for k in range(3):
			var x := -5.0 + 5.0 * float(k)
			kit.add_moving_head(Transform3D(basis, basis * Vector3(x, y - 0.17, -h + 0.05)),
				BLUE.lerp(Color.WHITE, 0.4) if (side + k) % 2 == 0 else RED.lerp(Color.WHITE, 0.3))
	# Flown from the roof (no floor towers: the corners are where the cameras stand).
	for c in [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]:
		kit.add_beam_block(c + Vector3(0, y + 0.2, 0), c + Vector3(0, 24.0, 0), 0.04, "cable")
	kit.add_downlight(Vector3(-6.0, y - 0.3, -6.0), Vector3(-1.0, 0, -1.0), BLUE, 6.0, 26.0, 0.04)
	kit.add_downlight(Vector3(6.0, y - 0.3, 6.0), Vector3(1.0, 0, 1.0), RED, 5.0, 26.0, 0.04)
	kit.add_downlight(Vector3(6.0, y - 0.3, -6.0), Vector3(1.5, 0, -1.5), Color(0.9, 0.93, 1.0), 4.0, 22.0, 0.03)
	kit.add_downlight(Vector3(-6.0, y - 0.3, 6.0), Vector3(-1.5, 0, 1.5), GOLD, 4.0, 22.0, 0.03)


## A four-faced jumbotron hanging over the centre of the ring: one face shows the live
## fight (the one facing the camera's side), the others loop the venue's stings.
static func _jumbotron(kit: VenueKit) -> void:
	var c := Vector3(0, 13.0, 0)
	kit.add_block(Transform3D(Basis.IDENTITY, c), Vector3(5.4, 3.2, 5.4), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.75, 0)), Vector3(5.8, 0.3, 5.8), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, c - Vector3(0, 1.75, 0)), Vector3(5.8, 0.3, 5.8), "dark_metal")
	var faces := [[Vector3(0, 0, -2.72), Basis(Vector3.UP, PI), true], [Vector3(-2.72, 0, 0), Basis(Vector3.UP, -PI * 0.5), false],
		[Vector3(0, 0, 2.72), Basis.IDENTITY, false], [Vector3(2.72, 0, 0), Basis(Vector3.UP, PI * 0.5), false]]
	for f in faces:
		kit.add_screen(Transform3D((f[1] as Basis) * Basis(Vector3.RIGHT, deg_to_rad(10.0)), c + (f[0] as Vector3)),
			"COLISEUM", bool(f[2]))
	for dx in [-2.4, 2.4]:
		for dz in [-2.4, 2.4]:
			kit.add_beam_block(c + Vector3(dx, 1.9, dz), Vector3(dx, 22.0, dz), 0.04, "cable")
