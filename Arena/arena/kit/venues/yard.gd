extends RefCounted
## THE YARD as a venue (docs/look/arenas/arenas-v1.html, the Yard concept; docs/aaa/arenas.md
## section 2.1): a club fight night held in a breaker's yard. Scaffold bleachers on the
## south side under the big screen, shipping containers stacked into stands on the east
## side with the crowd standing on top, sodium flood towers on the other diagonal, the
## fighters' gates in the two spawn corners, scrap, road cases and a camera jib round the
## near sides, and a cold night over the lot with the town's sodium glow on the horizon.
##
## The fight camera looks from the player's corner (-x, -z) toward +x, +z, so the SOUTH
## (+z) and EAST (+x) sides are the ones that enter the top of the fight frame: they get
## the tall stands and the people. The north and west sides are for the entrance, the
## endgame reveal and the orbit, so they get lower dressing.
##
## Only the VenueKit placement API is used here. Nothing collides.

const S := 0      # side ids for `_facing`
const E := 1
const N := 2
const W := 3

const CONTAINER_COLOURS := [
	Color(0.62, 0.17, 0.11), Color(0.14, 0.28, 0.52), Color(0.16, 0.38, 0.24),
	Color(0.78, 0.38, 0.1), Color(0.42, 0.43, 0.45), Color(0.1, 0.36, 0.4),
	Color(0.55, 0.12, 0.1), Color(0.72, 0.62, 0.2),
]


## The kit's +Z front turned to face the arena from `side`.
static func _facing(side: int) -> Basis:
	match side:
		S:
			return Basis(Vector3.UP, PI)
		E:
			return Basis(Vector3.UP, -PI * 0.5)
		W:
			return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY


## A basis whose +Z points from `at` toward `target` on the ground plane.
static func _toward(at: Vector3, target: Vector3) -> Basis:
	var d := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
	return Basis(Vector3.UP, atan2(d.x, d.z))


static func build(kit: VenueKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var half := kit.arena_half()                    # 5.0
	var wall := half + FightTypes.WALL_THICKNESS * 0.5   # outer face, 5.1
	var tier := kit.tier
	# Painted boards catch the floods; they must never outshine the arena.
	kit.board_level = 0.42

	# Night first: the arena's own key, fill, ambient, floor and wall tops, regraded.
	_grade(kit)
	# Floods first: they get the tier's real-light budget before the practicals do.
	_floods(kit)
	_backdrop(kit, rng)
	_south_stand(kit, wall)
	_east_containers(kit, wall, rng)
	_near_sides(kit, wall, rng)
	_gates_and_truss(kit)
	_floor_grime(kit, half, rng)
	# No lit board ring in the Yard (the concept has none, and at night it outshone the
	# arena): the wall tops carry the worn hazard paint instead, see _grade.

	# Dust hanging over the arena, where the floods can catch it.
	var motes := VenueFx.motes(tier, Vector3(8.0, 2.2, 8.0))
	if motes != null:
		motes.position = Vector3(0, 2.3, 0)
		kit.add_child(motes)

	# Grit on the wind, over the arena and the far stands.
	var grit := VenueFx.grit(tier, Vector3(9.0, 2.5, 9.0))
	if grit != null:
		grit.position = Vector3(1.5, 3.2, 1.5)
		kit.add_child(grit)

	# Endgame pyro: a column in each corner outside the wall.
	for c in [Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)]:
		var p: Vector3 = c * (wall + 0.55)
		kit.add_pyro(p, "columns", true)

	# Suggested flyover poses for the intro wave (camera transforms, looking at centre).
	for pose in [[Vector3(-13, 6.5, -9), Vector3(0, 0.5, 0)], [Vector3(9, 3.2, 12), Vector3(7.2, 1.5, 7.2)],
			[Vector3(-5, 11, -14), Vector3(0, 0, 1)]]:
		var from: Vector3 = pose[0]
		kit.intro_marks.append(Transform3D.IDENTITY.looking_at(pose[1] - from, Vector3.UP).translated(from))


# ---------------------------------------------------------------------------------
## The Yard at night (docs/look/arenas/yard-concept.webp): a warm sodium key from the
## east flood tower, a cold blue rim from across the arena, a dark blue ambient, a dark
## oily floor and worn hazard paint on the wall tops. Presentation only (VenueKit.grade).
const SODIUM := Color(1.0, 0.64, 0.33)
const NIGHT_BLUE := Color(0.42, 0.56, 1.0)


static func _grade(kit: VenueKit) -> void:
	var low := kit.tier == "low"
	kit.grade({
		"key_colour": SODIUM,
		"key_energy_scale": 1.3 if low else 0.92,
		"key_from": Vector3(8.8, 9.9, -8.8),
		"fill_colour": NIGHT_BLUE,
		"fill_energy": 0.5,
		"fill_from": Vector3(3.0, 4.0, 10.0),
		"ambient_colour": Color(0.28, 0.36, 0.58),
		"ambient_energy_scale": 0.9 if low else 0.55,
		"fog_colour": Color(0.08, 0.12, 0.22),
		"fog_density": 0.012,
		# Pass 2: the Yard's own plates (no tile grid), dark metallic steel, wet sheen.
		"floor_map": VenueKit.KIT_TEX + "yard_floor.png",
		"floor_normal": VenueKit.KIT_TEX + "yard_floor_n.png",
		"grid_hide": true,
		"floor_params": {
			"steel": Color(0.24, 0.245, 0.255) if low else Color(0.19, 0.195, 0.205),
			"metallic_base": 0.35 if low else 0.62,
			"rough_dry": 0.52, "rough_min": 0.05, "wet_darken": 0.15,
			"scratch_contrast": 0.4, "scratch_normal": 0.3, "normal_depth": 1.0,
			"pool_radius": 3.4, "pool_edge": 0.6,
			"warm_pool": Vector3(2.2, -1.6, 3.6), "cold_pool": Vector3(-2.2, 2.4, 3.8),
			"cold_tint": Color(0.66, 0.84, 1.3),
		},
		# The sheen: a sodium glint from across the arena that only the floor sees, so the
		# wet plates light up toward the fight camera without moving any shadow.
		"glint": {"from": Vector3(6.5, 7.5, 7.5), "colour": Color(1.0, 0.66, 0.36),
			"energy": 0.12, "specular": 9.0},
		# Pale worn concrete walls: a wall-only wash from the camera side lifts the inner
		# faces that the key never reaches.
		"wall_tint": Color(2.75, 2.62, 2.45),
		"wall_wash": {"from": Vector3(-6.0, 7.0, -5.0), "colour": Color(1.0, 0.86, 0.7),
			"energy": 0.55, "specular": 0.2},
		"hazard_trim": {"height": 0.13, "overhang": 0.012},
		# The venue's own reflection probe with a cold sky deck: cool steel, hot highlights.
		"probe": {"deck_colour": Color(0.3, 0.45, 0.8), "deck_energy": 0.7, "intensity": 1.0,
			"height": 0.9},
		# High tier: lit haze in the flood beams.
		"volumetric": {"density": 0.2, "albedo": Color(0.85, 0.87, 0.92), "anisotropy": 0.55,
			"key": 0.0, "fill": 0.0, "floods": 5.0, "length": 40.0, "reach": 0.42,
			"width": 2.4, "edge_fade": 0.7},
	})
	# The crowd reads mostly dark: warm rim from the floods behind them, little spill, but
	# enough clothing colour to tell people apart. Phones are warm-white sparkle points.
	kit.crowd_staging = {
		"body_light": 0.3,
		"saturation": 1.35,
		"spill_strength": 0.34,
		"rim_color": Color(1.0, 0.62, 0.32),
		"rim_strength": 0.75,
		"phone_glow": 0.25,
		"phone_color": Color(1.0, 0.86, 0.66),
	}
	kit.crowd.phone_size = 0.075
	kit.crowd.phone_colour = Color(1.0, 0.9, 0.74)
	kit.speck_staging = {"phone_twinkle": 1.0}
	kit.beam_card = {"high": 0.03, "medium": 0.16}
	kit.shafts = 3
	kit.shaft_strength = 0.07


# ---------------------------------------------------------------------------------
static func _backdrop(kit: VenueKit, rng: RandomNumberGenerator) -> void:
	kit.add_sky({
		"horizon_color": Color(0.3, 0.16, 0.08),
		"mid_color": Color(0.028, 0.05, 0.1),
		"zenith_color": Color(0.008, 0.014, 0.034),
		"glow_dir": Vector3(0.6, 0.0, 1.0),
	})
	var ground := kit.mats.slot("concrete").duplicate() as StandardMaterial3D
	ground.albedo_color = Color(0.2, 0.2, 0.21)
	ground.roughness = 0.42
	ground.uv1_scale = Vector3.ONE / 3.0
	kit.add_ground(90.0, ground)

	# The rest of the breaker's yard: stacks of containers in the dark, well back. Boxes,
	# not the corrugated model: at 24 m and beyond the ribs are under a pixel. Not on the
	# low tier (the simulator), where every draw costs a frame.
	var stacks := 0 if kit.tier == "low" else 34
	for i in range(stacks):
		var ang := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(24.0, 44.0)
		var base := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3) + (PI * 0.5 if rng.randf() < 0.5 else 0.0))
		var levels := rng.randi_range(1, 3)
		for l in range(levels):
			var col: Color = CONTAINER_COLOURS[rng.randi_range(0, CONTAINER_COLOURS.size() - 1)]
			kit.batch("container_far", Transform3D(rot, base + Vector3(0, 2.59 * l, 0)), col * 0.7, false)
		# A sodium lamp on some stacks, a warm speck in the distance.
		if rng.randf() < 0.35:
			kit.crowd.add_speck(base + Vector3(0, 2.59 * levels + 1.2, 0), 2, 1.4, Color(1.0, 0.6, 0.25), 1.6)
	# Two cranes on the skyline, with their red lamps.
	for c in ([] if kit.tier == "low" else [[Vector3(34, 0, 46), 0.4], [Vector3(-48, 0, 26), -1.1], [Vector3(52, 0, -18), 2.2]]):
		var at: Vector3 = c[0]
		kit.place("crane_skyline", Transform3D(Basis(Vector3.UP, float(c[1])), at), {}, false)
		kit.crowd.add_speck(at + Vector3(0, 18.5, 0), 2, 0.9, Color(1.0, 0.12, 0.08), 2.0)


# ---------------------------------------------------------------------------------
## South (+z): six scaffold bays of bleachers facing the arena, the screen above them.
static func _south_stand(kit: VenueKit, wall: float) -> void:
	var z0 := wall + 0.55
	var basis := _facing(S)
	var xs := [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0]
	for x in xs:
		kit.batch("stand_scaffold_bay", Transform3D(basis, Vector3(x, 0, z0)), Color.WHITE, true)
	kit.batch("stand_scaffold_endcap", Transform3D(basis, Vector3(-6.0, 0, z0)))
	# People on the treads: tread i top at 0.55 + 0.5 i, front edge 0.75 i back.
	for i in range(6):
		var y := 0.55 + 0.5 * float(i)
		var z := z0 + 0.75 * float(i) + 0.38
		kit.crowd.add_row(Vector3(-6.9, y, z), Vector3(4.9, y, z), 0.5, 0.9)
	# Standing room behind the top rail, dark.
	kit.crowd.add_row(Vector3(-6.8, 3.05, z0 + 4.25), Vector3(4.8, 3.05, z0 + 4.25), 0.55, 0.8, true)
	# Boards along the front fascia, facing the arena.
	for k in range(xs.size()):
		kit.add_board(Transform3D(basis, Vector3(xs[k], 0.3, z0 + 0.05)), k % 4, Vector2(1.9, 0.475))
	# The big screen on two truss legs behind the top row.
	var sx := -1.0
	var sz := z0 + 5.0
	for lx in [sx - 2.75, sx + 2.75]:
		kit.batch("truss_tower_leg", Transform3D(Basis.IDENTITY, Vector3(lx, 0, sz)))
	for k in range(3):
		kit.batch("truss_span_2m", Transform3D(Basis.IDENTITY, Vector3(sx - 2.0 + 2.0 * k, 6.15, sz)))
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(8.0))
	kit.add_screen(Transform3D(basis * tilt, Vector3(sx, 4.55, sz - 0.2)), "THE YARD")
	kit.add_practical(Vector3(sx, 3.2, sz - 2.0), Color(0.55, 0.65, 1.0), 1.2, 7.0)


# ---------------------------------------------------------------------------------
## East (+x): containers stacked into terraces. Standing crowd behind barriers at the wall,
## a row of containers with people on the roof, and a two-high row behind that.
static func _east_containers(kit: VenueKit, wall: float, rng: RandomNumberGenerator) -> void:
	# The concept's far wall: a container terrace starting right behind the wall, the crowd
	# on the roofs, two tiers, the top row as silhouettes against the sky.
	var x0 := wall + 0.12
	kit.add_container_terrace(Vector3(x0, 0, -6.1), Vector3(x0, 0, 6.1), Vector3(1, 0, 0), 2,
		CONTAINER_COLOURS, rng)
	# A stair up to the first roof at the north end. No boards on the container faces: right
	# behind the wall they sat in the top of the fight frame and outshone the arena.
	kit.batch("stair_scaffold", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x0 + 1.2, 0, -8.2)))


# ---------------------------------------------------------------------------------
## North (-z) and west (-x): behind the camera at the start, seen on the entrance, the
## reveal and the orbit. Fences with a standing crowd, scrap, road cases, a camera jib.
static func _near_sides(kit: VenueKit, wall: float, rng: RandomNumberGenerator) -> void:
	for side in [N, W]:
		var f := _facing(side)
		for k in range(5):
			var t := -4.8 + 2.4 * float(k)
			var pos := Vector3(t, 0, -(wall + 0.9)) if side == N else Vector3(-(wall + 0.9), 0, t)
			kit.batch("fence_panel", Transform3D(f, pos))
		for d in [1.35, 1.85]:
			var a := Vector3(-5.8, 0, -(wall + d)) if side == N else Vector3(-(wall + d), 0, -5.2)
			var b := Vector3(5.4, 0, -(wall + d)) if side == N else Vector3(-(wall + d), 0, 5.8)
			kit.crowd.add_row(a, b, 0.55, 0.8)
	# Scrap heaps behind the north crowd, a container stack in the north-west.
	kit.place("scrap_pile_a", Transform3D(_facing(N), Vector3(-2.5, 0, -(wall + 4.2))), {}, false)
	kit.place("scrap_pile_b", Transform3D(_facing(N) * Basis(Vector3.UP, 0.3), Vector3(2.8, 0, -(wall + 4.6))), {}, false)
	kit.place("scrap_pile_b", Transform3D(_facing(W) * Basis(Vector3.UP, -0.2), Vector3(-(wall + 4.4), 0, 2.2)), {}, false)
	kit.batch("container_20ft_open", Transform3D(Basis(Vector3.UP, 0.08), Vector3(-2.0, 0, -(wall + 8.0))),
		CONTAINER_COLOURS[0])
	kit.batch("container_20ft", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-(wall + 7.5), 0, -1.5)),
		CONTAINER_COLOURS[1])
	kit.batch("container_20ft", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-(wall + 7.5), 2.59, -1.5)),
		CONTAINER_COLOURS[4])
	# Production kit on the west side: road cases, a cable drum, the camera jib.
	kit.place("flight_case_stack", Transform3D(_facing(W), Vector3(-(wall + 2.8), 0, -3.4)), {}, false)
	kit.place("flight_case_stack", Transform3D(_facing(W) * Basis(Vector3.UP, 0.5), Vector3(-(wall + 3.2), 0, 5.6)), {}, false)
	kit.place("cable_drum", Transform3D(Basis(Vector3.UP, 0.7), Vector3(-(wall + 2.6), 0, -1.0)), {}, false)
	# The jib's arm is its local +X: turn it a quarter so the arm reaches toward the arena.
	var jib := Basis(Vector3.UP, -PI * 0.5)
	for at in [Vector3(-(wall + 1.7), 0, 4.2), Vector3(5.6, 0, -(wall + 1.8))]:
		kit.place("camera_crane", Transform3D(_toward(at, Vector3.ZERO) * jib, at), {}, false)


# ---------------------------------------------------------------------------------
## The two fighters' gates in the spawn corners, the opponent's under a truss with
## moving heads and beacons (it is the one the fight camera faces).
static func _gates_and_truss(kit: VenueKit) -> void:
	var d := 7.3
	var g1 := Vector3(d, 0, d)
	var b1 := _toward(g1, Vector3.ZERO)
	kit.add_gate(Transform3D(b1, g1), 1, 1)
	var g0 := Vector3(-d, 0, -d)
	kit.add_gate(Transform3D(_toward(g0, Vector3.ZERO), g0), 0, 0)
	# Truss portal over the opponent's gate.
	var legs := [Transform3D(b1, g1) * Vector3(-3.3, 0, 1.2), Transform3D(b1, g1) * Vector3(3.3, 0, 1.2)]
	for p in legs:
		kit.batch("truss_tower_leg", Transform3D(b1, p))
	for k in range(3):
		kit.batch("truss_span_2m", Transform3D(b1, Transform3D(b1, g1) * Vector3(-2.0 + 2.0 * float(k), 6.15, 1.2)))
	for x in [-3.15, 3.15]:
		kit.batch("truss_corner", Transform3D(b1, Transform3D(b1, g1) * Vector3(x, 6.15, 1.2)))
	for x in [-2.0, 0.0, 2.0]:
		kit.add_moving_head(Transform3D(b1, Transform3D(b1, g1) * Vector3(x, 5.98, 1.2)))
	for p in legs:
		kit.batch("beacon", Transform3D(b1, (p as Vector3) + Vector3(0, 6.3, 0)), Color.WHITE, false)
	kit.add_practical(Transform3D(b1, g1) * Vector3(0, 3.4, 1.5), Color(1.0, 0.62, 0.28), 1.8, 8.0)


# ---------------------------------------------------------------------------------
## Sodium flood towers on the other diagonal, lighting the arena warm. Two more behind the
## stands for the skyline.
static func _floods(kit: VenueKit) -> void:
	var sodium := Color(1.0, 0.7, 0.38)
	for p in [Vector3(8.8, 0, -8.8), Vector3(-8.8, 0, 8.8)]:
		kit.add_flood(Transform3D(_toward(p, Vector3.ZERO), p), Vector3(0, 0, 0), true, sodium, 3.2,
			p.x < 0.0)
	for p in [Vector3(14.5, 0, 5.0), Vector3(-5.5, 0, 14.5)]:
		kit.add_flood(Transform3D(_toward(p, Vector3.ZERO), p), Vector3(0, 0, 0), false, sodium, 0.0)


# ---------------------------------------------------------------------------------
## Oil, tyre marks, dust and weld seams on the plate, kept off the spike patch.
static func _floor_grime(kit: VenueKit, half: float, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < 22 and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(-half + 0.5, half - 0.5), rng.randf_range(-half + 0.5, half - 0.5))
		if absf(p.x) < 1.4 and absf(p.y) < 1.4:
			continue
		var cell: int = [0, 1, 1, 1, 2, 2, 2, 3][rng.randi_range(0, 7)]
		var size := rng.randf_range(0.4, 0.9) if cell == 0 else (rng.randf_range(1.4, 2.4) if cell == 1 else rng.randf_range(0.8, 1.5))
		kit.add_grime(p, size, rng.randf_range(0.0, TAU), cell)
		placed += 1
	# Dust drifts along the wall feet.
	for k in range(12):
		var t := rng.randf_range(-half, half)
		var side := rng.randi_range(0, 3)
		var p := Vector2(t, half - 0.35) if side == 0 else (Vector2(half - 0.35, t) if side == 1 else (
			Vector2(t, -half + 0.35) if side == 2 else Vector2(-half + 0.35, t)))
		kit.add_grime(p, rng.randf_range(0.8, 1.5), rng.randf_range(0.0, TAU), 2)
