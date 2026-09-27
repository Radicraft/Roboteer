extends RefCounted
## THE WORKSHOP TEST BAY as a venue (wave B; docs/wave-b-test-arena-notes.md): the private
## test pit the builder drives into from the workshop (Arena/arena/test_arena.tscn, the
## Yard's floor and walls with no hazard and a target pad on the north wall). Not a fight
## night: a working garage after hours. Sealed grey concrete painted as a test floor
## (metre crosses, measuring tapes, pivot rings, start boxes, the impact lane in front of
## the pad), LED high-bays on drop rods, two halogen work lights on tripods aimed into the
## pit, a pegboard tool wall and a bench line on the far side, the pit crew bay with a
## machine up on a stand and two mechanics, crates, tyres and gas bottles, a roller door.
##
## The fight camera looks from (-x, -z) toward (+x, +z): the SOUTH (+z) and EAST (+x) sides
## are the ones in the top of the fight frame, so they carry the tool wall, the benches
## and the crew. North and west are for the orbit and the wide shots.
##
## Only the VenueKit placement API is used here. Nothing collides.

const S := 0
const E := 1
const N := 2
const W := 3
## The building: far walls close behind the pit (they are the fight frame's backdrop), the
## near walls well back so every QA camera pose is inside.
const FAR := 10.0
const NEAR := -15.0
const H := 13.5
const HALOGEN := Color(1.0, 0.78, 0.52)
const LED := Color(1.0, 0.96, 0.9)
const WALL_TEX := VenueKit.KIT_TEX + "workshop_wall.png"


static func _facing(side: int) -> Basis:
	match side:
		S:
			return Basis(Vector3.UP, PI)
		E:
			return Basis(Vector3.UP, -PI * 0.5)
		W:
			return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY


static func _mat(colour: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	var half := kit.arena_half()
	var wall := half + FightTypes.WALL_THICKNESS * 0.5
	var low := kit.tier == "low"
	# Mechanics, not a crowd: no phones, no flashes.
	kit.crowd.phone_share = 0.0
	kit.crowd.flash_share = 0.0
	var m := {
		"block": _mat(Color(0.5, 0.52, 0.5), 0.85),
		"dado": _mat(Color(0.2, 0.24, 0.24), 0.8),
		"clad": _mat(Color(0.13, 0.14, 0.16), 0.6, 0.45),
		"roof": _mat(Color(0.04, 0.045, 0.05), 0.9),
		"red": _mat(Color(0.62, 0.07, 0.05), 0.35, 0.3),
		"red_dark": _mat(Color(0.28, 0.03, 0.02), 0.5, 0.3),
		"bench": _mat(Color(0.38, 0.27, 0.16), 0.7),
		"blue": _mat(Color(0.08, 0.2, 0.42), 0.5, 0.3),
		"orange": _mat(Color(0.85, 0.36, 0.06), 0.45, 0.2),
		"green": _mat(Color(0.1, 0.3, 0.18), 0.5, 0.3),
		"crate": _mat(Color(0.56, 0.42, 0.25), 0.85),
		"mat": _mat(Color(0.05, 0.05, 0.055), 0.9),
		"curtain": _mat(Color(0.75, 0.25, 0.03), 0.6),
		"window": kit.mats.lamp(Color(1.0, 0.8, 0.55), 1.1),
		"cork": _mat(Color(0.42, 0.3, 0.18), 0.9),
		"paper": _mat(Color(0.85, 0.85, 0.82), 0.8),
		"paper_y": _mat(Color(0.9, 0.78, 0.3), 0.8),
	}
	# The block walls hold a little bounce light (nothing lights them directly).
	(m["block"] as StandardMaterial3D).emission_enabled = true
	(m["block"] as StandardMaterial3D).emission = Color(0.5, 0.48, 0.44)
	(m["block"] as StandardMaterial3D).emission_energy_multiplier = 0.12
	_grade(kit, low)
	# Real lights first (the tier's budget): two high-bays over the pit, then the halogens.
	_lights(kit, m)
	_shell(kit, m)
	_south_tool_wall(kit, wall, m, rng)
	_east_pit_crew(kit, wall, m)
	_north_and_west(kit, wall, m, rng)
	_floor_grime(kit, half, rng)
	var motes := VenueFx.motes(kit.tier, Vector3(8.0, 2.4, 8.0))
	if motes != null:
		motes.position = Vector3(0, 2.6, 0)
		motes.amount = maxi(1, int(motes.amount * 0.5))
		kit.add_child(motes)
	for pose in [[Vector3(-9, 4.5, -7), Vector3(0, 0.5, 0)], [Vector3(6.5, 2.6, 8.5), Vector3(7.2, 1.2, 1.5)],
			[Vector3(-4, 8, -11), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


# ---------------------------------------------------------------------------------
## After hours in a clean garage: neutral LED from overhead, warm halogen fill from the
## work lights, warm grey ambient, a little dust. Presentation only (VenueKit.grade).
static func _grade(kit: VenueKit, low: bool) -> void:
	kit.grade({
		"key_colour": Color(1.0, 0.95, 0.88),
		"key_energy_scale": 1.25 if low else 1.0,
		"key_from": Vector3(-3.0, 11.0, 2.0),
		"fill_colour": HALOGEN,
		"fill_energy": 0.45,
		"fill_from": Vector3(8.0, 3.0, -4.0),
		"ambient_colour": Color(0.6, 0.57, 0.52),
		"ambient_energy_scale": 1.1 if low else 0.95,
		"fog_colour": Color(0.16, 0.15, 0.14),
		"fog_density": 0.01,
		"floor_map": VenueKit.KIT_TEX + "workshop_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "workshop_floor_n.png",
		"grid_hide": true,
		"floor_params": {
			# Sealed concrete: the map carries the tone and the paint, this is its scale.
			"steel": Color(0.62, 0.62, 0.61) if low else Color(0.56, 0.56, 0.555),
			"metallic_base": 0.04,
			"rough_dry": 0.42, "rough_min": 0.18, "wet_darken": 0.1,
			"scratch_contrast": 0.18, "scratch_normal": 0.12, "normal_depth": 0.8,
			"pool_radius": 4.4, "pool_edge": 0.78,
			"warm_pool": Vector3(3.2, -1.2, 3.4), "cold_pool": Vector3(40.0, 40.0, 0.1),
			"warm_tint": Color(1.1, 1.0, 0.88),
			"oil_color": Color(0.06, 0.055, 0.05),
		},
		# The sealed floor's sheen under the high-bays.
		"glint": {"from": Vector3(4.0, 9.0, 6.0), "colour": LED, "energy": 0.08, "specular": 5.0},
		"wall_panels": {"style": "riveted", "base_color": Color(0.36, 0.37, 0.38),
			"rib_color": Color(0.5, 0.5, 0.5), "grime": 0.45},
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": Color(1.0, 0.92, 0.82),
			"energy": 0.4, "specular": 0.3},
		"hazard_trim": {"height": 0.13, "overhang": 0.012},
		"probe": {"deck_colour": Color(0.55, 0.52, 0.48), "deck_energy": 0.35, "intensity": 0.8,
			"height": 0.9},
		"volumetric": {"density": 0.08, "albedo": Color(0.9, 0.88, 0.85), "floods": 3.0,
			"key": 0.0, "fill": 0.0, "length": 30.0, "reach": 0.5, "width": 2.6, "edge_fade": 0.7},
	})
	kit.crowd_staging = {
		"body_light": 0.55, "saturation": 1.1, "spill_strength": 0.3,
		"spill_color": HALOGEN, "rim_color": Color(1.0, 0.85, 0.65), "rim_strength": 0.5,
		"haze_color": Color(0.1, 0.095, 0.09),
	}
	kit.beam_card = {"high": 0.025, "medium": 0.1}
	kit.board_level = 0.5


# ---------------------------------------------------------------------------------
## Two LED high-bays on drop rods over the pit as real downlights, seven more as fixtures
## only; two halogen twin-head work lights on tripods just outside the wall, aimed in.
static func _lights(kit: VenueKit, m: Dictionary) -> void:
	var y := 6.2
	var bays := []
	for x in [-3.2, 0.0, 3.2]:
		for z in [-3.2, 0.0, 3.2]:
			bays.append(Vector3(x, y, z))
	for p in bays:
		var at := p as Vector3
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.14, 0)), 0.3, 0.22, "dark_metal", 16)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3, 0)), 0.1, 0.12, "dark_metal", 10)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at), 0.27, 0.03, "lamp_white", 16)
		kit.add_beam_block(at + Vector3(0, 0.36, 0), Vector3(at.x, H - 0.6, at.z), 0.02, "galv_steel", true)
	# The room round the pit: more high-bays (fixtures only) with painted pools under them.
	for p in [Vector3(-7.5, y, -3.0), Vector3(-7.5, y, 4.0), Vector3(-2.0, y, -8.0), Vector3(4.5, y, -8.0),
			Vector3(7.5, y, -5.0), Vector3(7.5, y, 1.5), Vector3(7.5, y, 7.5), Vector3(1.5, y, 7.8), Vector3(-5.0, y, 7.8)]:
		var at := p as Vector3
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.14, 0)), 0.3, 0.22, "dark_metal", 16)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at), 0.27, 0.03, "lamp_white", 16)
		kit.add_beam_block(at + Vector3(0, 0.25, 0), Vector3(at.x, H - 0.6, at.z), 0.02, "galv_steel", true)
		var pool := VenueFx.floor_glow(3.6, Color(1.0, 0.93, 0.82), 0.3)
		pool.position = Vector3(at.x, 0.02, at.z)
		kit.add_child(pool)
	kit.add_downlight(Vector3(-1.6, y, 1.6), Vector3(-1.2, 0, 1.2), LED, 1.6, 44.0, 0.03)
	kit.add_downlight(Vector3(1.6, y, -1.6), Vector3(1.2, 0, -1.2), LED, 1.6, 44.0, 0.03)
	# Work lights: the east one lights the pit crew side, the south one the bench side.
	for spec in [[Vector3(6.1, 0, -2.4), Vector3(0.5, 0, 0.5)], [Vector3(-2.6, 0, 6.1), Vector3(0.3, 0, 0.5)]]:
		_tripod_light(kit, spec[0], spec[1])


static func _tripod_light(kit: VenueKit, base: Vector3, target: Vector3) -> void:
	var top := base + Vector3(0, 2.1, 0)
	for k in range(3):
		var a := TAU * float(k) / 3.0 + 0.4
		kit.add_beam_block(base + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), top - Vector3(0, 0.6, 0), 0.03, "hazard_paint")
	kit.add_beam_block(top - Vector3(0, 0.7, 0), top + Vector3(0, 0.1, 0), 0.035, "dark_metal", true)
	# The T-bar and two lamp heads, their glass faces toward the target.
	var d := (target - top)
	var fwd := Vector3(d.x, 0, d.z).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	kit.add_beam_block(top - side * 0.42, top + side * 0.42, 0.04, "dark_metal")
	var look := Basis.looking_at(-(target - top).normalized(), Vector3.UP)
	for s: float in [-0.3, 0.3]:
		var c := top + side * s + Vector3(0, 0.08, 0)
		kit.add_block(Transform3D(look, c), Vector3(0.36, 0.28, 0.16), "hazard_paint")
		kit.add_block(Transform3D(look, c + look * Vector3(0, 0, 0.085)), Vector3(0.3, 0.22, 0.01), "lamp_warm")
		kit.crowd.add_speck(c + look * Vector3(0, 0, 0.12), 2, 0.9, Color(1.0, 0.85, 0.6), 1.6)
	kit.add_beam_block(top, top + Vector3(0, -2.0, 0) + fwd * 0.4, 0.012, "cable")
	kit.add_downlight(top + fwd * 0.15, target, HALOGEN, 2.2, 38.0, 0.04)


# ---------------------------------------------------------------------------------
## The building: painted block walls to 3.2 m with a dark dado, dark cladding above,
## columns, roof trusses, a closed roller door in the east wall.
static func _shell(kit: VenueKit, m: Dictionary) -> void:
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.46, 0.46, 0.46)
	ground.roughness = 0.55
	kit.add_ground(60.0, ground)
	var mid := (FAR + NEAR) * 0.5
	var span := FAR - NEAR
	var walls := [
		[Vector3(mid, 0, FAR), Vector3(span, 0, 0.3)], [Vector3(mid, 0, NEAR), Vector3(span, 0, 0.3)],
		[Vector3(FAR, 0, mid), Vector3(0.3, 0, span)], [Vector3(NEAR, 0, mid), Vector3(0.3, 0, span)],
	]
	for w in walls:
		var at: Vector3 = w[0]
		var sz: Vector3 = w[1]
		kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 1.75, 0)), sz + Vector3(0, 2.3, 0), m["block"])
		kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3, 0)), sz + Vector3(0.02, 0.6, 0.02), m["dado"])
		kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 2.9 + (H - 2.9) * 0.5, 0)), sz + Vector3(0, H - 2.9, 0), m["clad"])
	# Columns every 5 m along the walls; roof trusses across.
	var t := NEAR
	while t <= FAR + 0.01:
		for p in [Vector3(t, H * 0.5, FAR - 0.3), Vector3(FAR - 0.3, H * 0.5, t), Vector3(t, H * 0.5, NEAR + 0.3), Vector3(NEAR + 0.3, H * 0.5, t)]:
			kit.add_block(Transform3D(Basis.IDENTITY, p), Vector3(0.35, H, 0.35), "dark_metal")
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(t, H - 0.5, mid)), Vector3(0.25, 0.7, span), "dark_metal")
		t += 5.0
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(mid, H + 0.15, mid)), Vector3(span, 0.3, span), m["roof"])
	# Roller door in the east wall (closed): galvanised slats, hazard-painted jambs.
	var dz0 := -4.6
	var dz1 := 0.4
	var dh := 4.6
	var dc := (dz0 + dz1) * 0.5
	var slat := 0.0
	while slat < dh:
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.18, slat + 0.09, dc)), Vector3(0.05, 0.16, dz1 - dz0), "galv_steel")
		slat += 0.18
	for z in [dz0 - 0.15, dz1 + 0.15]:
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.2, dh * 0.5, z)), Vector3(0.12, dh, 0.25), "hazard_paint")
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.35, dh + 0.3, dc)), Vector3(0.5, 0.55, dz1 - dz0 + 0.6), "dark_metal")


# ---------------------------------------------------------------------------------
## South (+z), the far side of the fight frame: the pegboard tool wall, the TEST BAY sign,
## a bench line with vices, parts and red roll cabinets, a battens row over it.
static func _south_tool_wall(kit: VenueKit, wall: float, m: Dictionary, rng: RandomNumberGenerator) -> void:
	var zw := FAR - 0.17
	var basis := _facing(S)
	# Pegboard: 2 sections either side of the sign column, 1.9 m tall, from 1.0 m.
	for sec in [[-7.5, -1.0], [1.0, 7.5]]:
		var x0: float = sec[0]
		var x1: float = sec[1]
		var w := x1 - x0
		_plate(kit, Transform3D(basis, Vector3((x0 + x1) * 0.5, 2.0, zw)), Vector2(w, 1.9),
			Rect2(0.0, 0.0, w / 3.8, 0.5))
	# The sign, a painted band high on the wall between two columns (they stand every 5 m).
	_plate(kit, Transform3D(basis, Vector3(-2.5, 4.6, zw)), Vector2(4.2, 1.05), Rect2(0.0, 0.5, 1.0, 0.5), 0.15)
	# Benches: 2.4 m tops at 0.92 m, legs, a vice each, parts on top.
	var bz := zw - 0.5
	for bx in [-6.2, -3.4, 2.4, 5.2]:
		var c := Vector3(bx, 0, bz)
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.9, 0)), Vector3(2.4, 0.06, 0.8), m["bench"])
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.84, 0)), Vector3(2.36, 0.08, 0.76), "dark_metal")
		for lx in [-1.1, 1.1]:
			for lz in [-0.33, 0.33]:
				kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(lx, 0.42, lz)), Vector3(0.06, 0.84, 0.06), "dark_metal")
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.18, 0)), Vector3(2.3, 0.04, 0.7), "dark_metal")
		# Drawer unit under one end.
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0.7, 0.45, 0.02)), Vector3(0.7, 0.7, 0.66), m["blue"])
		for k in range(4):
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0.7, 0.2 + 0.17 * float(k), -0.32)), Vector3(0.5, 0.02, 0.02), "galv_steel")
		# Vice at the front edge.
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.8, 1.02, -0.3)), Vector3(0.22, 0.18, 0.28), m["blue"])
		kit.add_beam_block(c + Vector3(-0.8, 1.0, -0.46), c + Vector3(-0.8, 1.0, -0.6), 0.03, "galv_steel", true)
		# Parts: a wheel, a battery pack, a motor, a small box.
		kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), c + Vector3(-0.1, 1.07, 0.05)), 0.14, 0.08, "rubber", 14)
		kit.add_block(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), c + Vector3(0.35, 0.99, 0.12)), Vector3(0.26, 0.12, 0.16), m["orange"])
		kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c + Vector3(0.75, 1.0, -0.05)), 0.07, 0.2, "galv_steel", 12)
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.5, 1.03, 0.2)), Vector3(0.3, 0.2, 0.22), m["red"])
		# A batten over each bench.
		kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 3.08, 0.1)), Vector3(1.6, 0.05, 0.14), "galv_steel")
		kit.add_tube(Transform3D(Basis.IDENTITY, c + Vector3(0, 3.03, 0.1)), 1.5, LED, 3.0)
		var pool := VenueFx.floor_glow(1.6, Color(1.0, 0.9, 0.75), 0.18)
		pool.position = c + Vector3(0, 0.013, -0.7)
		kit.add_child(pool)
	# Red roll cabinets in the gap under the sign.
	for rx in [-0.45, 0.45]:
		_roll_cab(kit, Vector3(rx, 0, zw - 0.4), m)
	# Crates and a pallet on the pit side of the benches, in the corners of the frame.
	_crates(kit, Vector3(-4.8, 0, wall + 1.2), rng, m, 3)
	_crates(kit, Vector3(3.6, 0, wall + 1.0), rng, m, 2)
	# Tyre stack and gas bottles by the south-east corner.
	for k in range(4):
		kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(7.4, 0.1 + 0.2 * float(k), wall + 1.6)), 0.33, 0.19, "rubber", 16)
	for k in range(3):
		var p := Vector3(8.4 + 0.3 * float(k), 0, wall + 2.6)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.7, 0)), 0.12, 1.4, m["green"] if k != 1 else m["blue"], 12)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, 1.47, 0)), 0.05, 0.14, "galv_steel", 8)


static func _roll_cab(kit: VenueKit, at: Vector3, m: Dictionary) -> void:
	kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.58, 0)), Vector3(0.8, 0.95, 0.5), m["red"])
	kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 1.28, 0.02)), Vector3(0.78, 0.4, 0.44), m["red"])
	for k in range(6):
		kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.22 + 0.15 * float(k), -0.255)), Vector3(0.7, 0.025, 0.02), "galv_steel")
	kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.08, 0)), Vector3(0.82, 0.06, 0.52), m["red_dark"])
	for cx in [-0.32, 0.32]:
		for cz in [-0.18, 0.18]:
			kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(cx, 0.05, cz)), 0.05, 0.04, "rubber", 8)


static func _crates(kit: VenueKit, at: Vector3, rng: RandomNumberGenerator, m: Dictionary, n: int) -> void:
	# A pallet, then crates stacked on it and beside it.
	kit.add_block(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.07, 0)), Vector3(1.2, 0.14, 1.0), m["crate"])
	var y := 0.14
	for k in range(n):
		var sz := Vector3(rng.randf_range(0.6, 0.95), rng.randf_range(0.45, 0.7), rng.randf_range(0.55, 0.85))
		var off := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.1, 0.1))
		var b := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
		kit.add_block(Transform3D(b, at + off + Vector3(0, y + sz.y * 0.5, 0)), sz, m["crate"])
		# Battens round the crate's middle and edges.
		kit.add_block(Transform3D(b, at + off + Vector3(0, y + sz.y * 0.5, 0)), sz + Vector3(0.02, -sz.y + 0.07, 0.02), "dark_metal")
		y += sz.y
		if y > 1.5:
			break
	kit.add_block(Transform3D(Basis(Vector3.UP, 0.3), at + Vector3(1.1, 0.3, 0.2)), Vector3(0.7, 0.6, 0.6), m["crate"])


# ---------------------------------------------------------------------------------
## East (+x): the pit crew bay. A rubber mat, a machine up on a stand under a lamp, a
## charging cart, the telemetry screen on the wall, two mechanics at the stand.
static func _east_pit_crew(kit: VenueKit, wall: float, m: Dictionary) -> void:
	var cx := wall + 2.6
	var cz := 2.8
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(cx + 0.4, 0.012, cz)), Vector3(3.4, 0.024, 3.6), m["mat"])
	# The stand and the machine on it (a wedge with a spinner, wheels off the ground).
	var s := Vector3(cx + 0.6, 0, cz)
	kit.add_block(Transform3D(Basis.IDENTITY, s + Vector3(0, 0.3, 0)), Vector3(0.5, 0.6, 0.5), "galv_steel")
	kit.add_block(Transform3D(Basis.IDENTITY, s + Vector3(0, 0.62, 0)), Vector3(0.8, 0.04, 0.8), "dark_metal")
	var body := Transform3D(Basis(Vector3.UP, 0.5), s + Vector3(0, 0.8, 0))
	kit.add_block(body, Vector3(0.95, 0.24, 0.75), m["orange"])
	kit.add_block(body * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, -0.02, -0.46)), Vector3(0.95, 0.04, 0.3), "galv_steel")
	for wx in [-0.52, 0.52]:
		for wz in [-0.22, 0.22]:
			kit.add_cylinder(body * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx, -0.04, wz)), 0.13, 0.08, "rubber", 14)
	kit.add_cylinder(body * Transform3D(Basis.IDENTITY, Vector3(0, 0.16, 0.12)), 0.3, 0.05, "galv_steel", 18)
	# Charging cart with its lead to the machine.
	var cart := Vector3(cx + 1.5, 0, cz + 1.4)
	kit.add_block(Transform3D(Basis.IDENTITY, cart + Vector3(0, 0.55, 0)), Vector3(0.6, 0.9, 0.45), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, cart + Vector3(-0.23, 0.8, 0)), Vector3(0.02, 0.2, 0.3), m["window"])
	kit.add_beam_block(cart + Vector3(-0.3, 0.6, -0.1), s + Vector3(0.2, 0.8, 0.1), 0.015, "cable")
	# A lamp on a boom over the stand.
	kit.add_beam_block(s + Vector3(0.8, 0, 0.6), s + Vector3(0.8, 2.4, 0.6), 0.04, "dark_metal", true)
	kit.add_beam_block(s + Vector3(0.8, 2.4, 0.6), s + Vector3(0.1, 2.1, 0.1), 0.03, "dark_metal", true)
	kit.add_block(Transform3D(Basis.IDENTITY, s + Vector3(0.1, 2.06, 0.1)), Vector3(0.3, 0.05, 0.3), "lamp_warm")
	var pool := VenueFx.floor_glow(1.3, Color(1.0, 0.78, 0.5), 0.28)
	pool.position = s + Vector3(0, 0.03, 0)
	kit.add_child(pool)
	# Two mechanics at the stand (cards; none on the low tier's thinned density).
	kit.crowd.add_row(Vector3(cx - 0.35, 0, cz - 0.6), Vector3(cx - 0.35, 0, cz + 0.9), 0.72, 1.0)
	# Telemetry screen on the wall north of the stand and a parts rack south of it.
	# A noticeboard where a fight venue would hang its screen: test sheets pinned up.
	var nb := Vector3(FAR - 0.22, 1.9, 5.4)
	kit.add_block(Transform3D(Basis.IDENTITY, nb), Vector3(0.05, 1.3, 2.4), "dark_metal")
	kit.add_block(Transform3D(Basis.IDENTITY, nb + Vector3(-0.03, 0, 0)), Vector3(0.02, 1.18, 2.28), m["cork"])
	var sheet_rng := RandomNumberGenerator.new()
	sheet_rng.seed = 99
	for k in range(9):
		var p := nb + Vector3(-0.05, sheet_rng.randf_range(-0.4, 0.4), -0.95 + 0.24 * float(k))
		kit.add_block(Transform3D(Basis(Vector3.RIGHT, sheet_rng.randf_range(-0.08, 0.08)), p), Vector3(0.006, 0.3, 0.21),
			m["paper"] if k % 3 else m["paper_y"])
	kit.add_tube(Transform3D(Basis(Vector3.UP, PI * 0.5), nb + Vector3(-0.25, 0.85, 0)), 2.0, LED, 2.5)
	for k in range(4):
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.7, 0.35 + 0.55 * float(k), 8.4)), Vector3(0.6, 0.03, 1.8), "galv_steel")
		for b in range(3):
			kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.72, 0.47 + 0.55 * float(k), 7.8 + 0.6 * float(b))), Vector3(0.45, 0.2, 0.4),
				[m["blue"], m["red"], m["orange"], m["green"]][(k + b) % 4])
	for rz in [7.45, 9.35]:
		kit.add_block(Transform3D(Basis.IDENTITY, Vector3(FAR - 0.7, 1.1, rz)), Vector3(0.05, 2.2, 0.05), "dark_metal")
	# Crates and a cable drum at the east wall's north end, in the frame's right edge.
	_crates(kit, Vector3(wall + 1.3, 0, -3.4), RandomNumberGenerator.new(), m, 2)
	kit.place("cable_drum", Transform3D(Basis(Vector3.UP, 0.4), Vector3(wall + 1.6, 0, -1.2)), {}, false)


# ---------------------------------------------------------------------------------
## North (-z) behind the target pad, and west (-x): the pit office with lit windows, a
## welding bay with its orange curtain, shelving, road cases, the entrance fence.
static func _north_and_west(kit: VenueKit, wall: float, m: Dictionary, rng: RandomNumberGenerator) -> void:
	# Behind the target pad: a low steel backstop (low, it sits in front of the wide camera).
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(0, 0.4, -(wall + 0.3))), Vector3(2.8, 0.8, 0.1), "dark_metal")
	for x in [-1.3, 0.0, 1.3]:
		kit.add_beam_block(Vector3(x, 0, -(wall + 0.8)), Vector3(x, 0.8, -(wall + 0.36)), 0.08, "dark_metal")
	# Pit office in the north-west corner: a cabin with warm lit windows and a stair.
	var o := Vector3(-8.5, 0, -9.0)
	kit.add_block(Transform3D(Basis.IDENTITY, o + Vector3(0, 1.5, 0)), Vector3(5.0, 3.0, 3.4), m["block"])
	kit.add_block(Transform3D(Basis.IDENTITY, o + Vector3(0, 3.05, 0)), Vector3(5.2, 0.1, 3.6), "dark_metal")
	for wx in [-1.5, 0.0, 1.5]:
		kit.add_block(Transform3D(Basis.IDENTITY, o + Vector3(wx, 1.7, 1.71)), Vector3(1.1, 0.9, 0.02), m["window"])
	kit.add_block(Transform3D(Basis.IDENTITY, o + Vector3(2.51, 1.1, 0.6)), Vector3(0.02, 2.1, 0.9), m["blue"])
	# Welding bay on the west wall: frame and curtain.
	var wz := 3.0
	var wxp := NEAR + 3.5
	for p in [Vector3(wxp, 0, wz - 1.5), Vector3(wxp, 0, wz + 1.5), Vector3(wxp - 2.6, 0, wz - 1.5), Vector3(wxp - 2.6, 0, wz + 1.5)]:
		kit.add_beam_block(p, p + Vector3(0, 2.1, 0), 0.05, "dark_metal", true)
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(wxp, 1.15, wz)), Vector3(0.02, 1.9, 3.0), m["curtain"])
	kit.add_block(Transform3D(Basis.IDENTITY, Vector3(wxp - 1.3, 0.45, wz)), Vector3(1.2, 0.9, 0.8), "dark_metal")
	# Shelving along the north wall.
	for k in range(3):
		var c := Vector3(-1.0 + 3.2 * float(k), 0, NEAR + 0.8)
		for sh in range(4):
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.3 + 0.6 * float(sh), 0)), Vector3(2.6, 0.04, 0.7), "galv_steel")
			for b in range(4):
				if rng.randf() < 0.75:
					kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(-0.95 + 0.63 * float(b), 0.45 + 0.6 * float(sh), 0)),
						Vector3(0.5, 0.26, 0.5), [m["blue"], m["crate"], m["red"], m["orange"]][(k + sh + b) % 4])
		for px in [-1.3, 1.3]:
			kit.add_block(Transform3D(Basis.IDENTITY, c + Vector3(px, 1.2, 0)), Vector3(0.05, 2.4, 0.7), "dark_metal")
	# Road cases, a second cable drum, crates on the west side, close to the wall.
	kit.place("flight_case_stack", Transform3D(_facing(W), Vector3(-(wall + 1.6), 0, -3.4)), {}, false)
	kit.place("flight_case_stack", Transform3D(_facing(W) * Basis(Vector3.UP, 0.4), Vector3(-(wall + 1.8), 0, 2.6)), {}, false)
	_crates(kit, Vector3(-(wall + 1.5), 0, 0.0), rng, m, 3)
	_roll_cab(kit, Vector3(-(wall + 1.2), 0, 4.4), m)


# ---------------------------------------------------------------------------------
static func _floor_grime(kit: VenueKit, half: float, rng: RandomNumberGenerator) -> void:
	# A clean floor: a few scuffs and skid marks, dust at the wall feet.
	for k in range(8):
		var p := Vector2(rng.randf_range(-half + 0.8, half - 0.8), rng.randf_range(-half + 0.8, half - 0.8))
		kit.add_grime(p, rng.randf_range(1.2, 2.0), rng.randf_range(0.0, TAU), 1 if k % 2 == 0 else 2)
	for k in range(8):
		var t := rng.randf_range(-half, half)
		var side := rng.randi_range(0, 3)
		var p := Vector2(t, half - 0.3) if side == 0 else (Vector2(half - 0.3, t) if side == 1 else (
			Vector2(t, -half + 0.3) if side == 2 else Vector2(-half + 0.3, t)))
		kit.add_grime(p, rng.randf_range(0.7, 1.2), rng.randf_range(0.0, TAU), 2)


## A textured plate (workshop_wall.png) facing +Z of `xf`, off the wall by a centimetre.
static func _plate(kit: VenueKit, xf: Transform3D, size: Vector2, region: Rect2, emissive: float = 0.0) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mat := kit.mats.plate(WALL_TEX, region, emissive)
	mat.albedo_color = Color(0.9, 0.9, 0.9)
	mat.roughness = 0.75
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "WallPlate"
	mi.mesh = q
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.add_child(mi)
