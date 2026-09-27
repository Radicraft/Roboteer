class_name ColiseumArena extends ArenaBase
## Coliseum (brief §7 arena 6, docs/stage5-spec.md §3): the championship arena. A 12 x 12 m
## polished plate floor, taller walls with banners, and every hazard in the game at once,
## plus two spinning floor discs that carry a bot round whether it wants to go or not.
##
##   FLOOR PLAN (12 x 12 m, north is -Z)
##
##     -6                      0                      +6
##   -6 +--------------------------------------------------+
##      |   P              ^ jet                  .-.       |  P player spawn (-4.2,-4.2)
##      |                                        ( T )      |  O opponent  (4.2, 4.2)
##      |  .-.                                    `-'       |  T turntable, r = 2.0,
##    0 | ( G )              [spikes]                       |    0.6 rad/s, opposed spin
##      |  `-'                                        .-.   |  G grinder, r = 0.55
##      |       .-.                                  ( G )  |  jet: one per long wall,
##      |      ( T )                       jet v      `-'   |       2.5 m reach
##   +6 +--------------------------------------------------+
##
## Everything is placed on the SAME 180 degree rotation about the centre, so the arena is
## identical from either spawn: two grinders opposed, two turntables opposed and spinning
## in opposite directions, one jet per long wall opposed, and the spike patch dead centre
## where both bots have to cross it. The turntables are the championship's own idea: they
## do no damage at all, they just take away the one thing a driver relies on, which is
## that the floor stays where they left it.
##
## Marking scheme (original, brief §3): a broad centre ring around the spike patch, a
## twelve-point radial star out from it, plain keep-out rings on the grinders and painted
## spokes on the turntables. Grander than the Yard's seam grid, and nothing borrowed.

const SIZE := 12.0
const WALL_H := 0.95

const SPIKE_EXTENT := 2.0                 # a bigger patch than the Yard's, to match the floor
const TURNTABLE_RADIUS := 2.0
const TURNTABLE_RATE := 0.6               # rad/s, as the spec asks
const TURNTABLE_A := Vector3(-2.9, 0.0, 2.9)
const TURNTABLE_B := Vector3(2.9, 0.0, -2.9)
const GRINDER_A := Vector3(-4.6, 0.0, -1.5)
const GRINDER_B := Vector3(4.6, 0.0, 1.5)
const JET_NORTH_X := -1.2
const JET_SOUTH_X := 1.2
const JET_PERIOD_MIN_S := 8.0
const JET_PERIOD_MAX_S := 12.0
## brief v4 §2: the same 4 s endgame period the Furnace's jets take. Spelled out rather
## than borrowed from FurnaceArena: a const that reaches across a class_name is resolved
## at parse time, and a headless `--script` run parses this file before that cache exists.
const ENDGAME_JET_PERIOD_S := 4.0
const ENDGAME_JET_PERIOD_TICKS := int(ENDGAME_JET_PERIOD_S * FightTypes.TICK_HZ)

## Polished plate, cool and bright, with the banners as the only saturated colour.
const TINT_FLOOR := Color(1.12, 1.14, 1.20)
## Wave A: 2.45 blew the titanium out to noisy white (arenas.md §2.6 gap 3); a deep
## championship blue cast at a sane level instead.
const TINT_WALL := Color(1.2, 1.3, 1.62)
const COL_RING := Color(0.80, 0.74, 0.52)
const COL_STAR := Color(0.34, 0.35, 0.39)
const BANNER_A := Color(0.20, 0.36, 0.62)   # the player livery blue
const BANNER_B := Color(0.58, 0.16, 0.14)   # the opponent livery red

var _grinders: Array = []
var _jets: Array = []
var _turntables: Array = []
var _jet_period := int(round(10.0 * FightTypes.TICK_HZ))
var _jet_phase := 0
var _spin_phase := 0.0


func arena_id() -> String:
	return "coliseum"


func _configure() -> void:
	_arena_size = SIZE
	_wall_height = WALL_H
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_TITANIUM
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.52                   # polished: the probe earns its keep here
	_ambient_tint = Color(1.02, 1.02, 1.06)
	_ambient_energy_scale = 1.15
	_key_colour = Color(1.0, 0.99, 0.96)
	_key_energy = 0.58
	_fill_colour = Color(0.76, 0.84, 1.0)
	_fill_energy = 0.15
	_bg_tint = Color(0.86, 0.90, 1.0)
	_grid_enabled = false
	_spawn_inset = 1.8                       # spawns land on (-4.2, -4.2) and (4.2, 4.2)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build_hazards() -> void:
	_add_spike_patch(Vector3.ZERO, SPIKE_EXTENT)
	_grinders.append(_add_grinder(GRINDER_A, "GrinderWest"))
	_grinders.append(_add_grinder(GRINDER_B, "GrinderEast"))
	var inset := _half - FightTypes.WALL_THICKNESS * 0.5
	_jets.append(_add_flame_jet(Vector3(JET_NORTH_X, 0.28, -inset), Vector3(0, 0, 1), "JetNorth"))
	_jets.append(_add_flame_jet(Vector3(JET_SOUTH_X, 0.28, inset), Vector3(0, 0, -1), "JetSouth"))
	# Both jets run on one clock, so they are one warning (one wind-up, one strike).
	for jet in _jets:
		jet["bank"] = "jets"
	# Opposed spin: the two discs turn against each other, so crossing from one to the
	# other reverses which way the floor is taking you.
	_turntables.append(_add_turntable(TURNTABLE_A, TURNTABLE_RADIUS, TURNTABLE_RATE, "TurntableWest"))
	_turntables.append(_add_turntable(TURNTABLE_B, TURNTABLE_RADIUS, -TURNTABLE_RATE, "TurntableEast"))


func _build_markings() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	# The centre ring: a broad band around the spike patch, the arena's stage.
	_mark_ring(verts, norms, Vector2.ZERO, SPIKE_EXTENT * 0.5 + 0.45, 0.16, 48)
	_mark_ring(verts, norms, Vector2.ZERO, SPIKE_EXTENT * 0.5 + 0.75, 0.06, 48)
	_add_marking("CentreRing", _mesh_from(verts, norms), COL_RING, 0.0)

	var star := PackedVector3Array()
	var star_n := PackedVector3Array()
	# Twelve radial spokes out of the centre, stopping short of the walls.
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var dir := Vector2(cos(a), sin(a))
		_mark_line(star, star_n, dir * (SPIKE_EXTENT * 0.5 + 0.95), dir * (_half - 0.5), 0.07)
	_add_marking("RadialStar", _mesh_from(star, star_n), COL_STAR, 0.0)

	var rings := PackedVector3Array()
	var rings_n := PackedVector3Array()
	for centre in [GRINDER_A, GRINDER_B]:
		_mark_ring(rings, rings_n, Vector2(centre.x, centre.z), GRINDER_RADIUS + 0.30, 0.08, 36)
	for centre in [TURNTABLE_A, TURNTABLE_B]:
		_mark_ring(rings, rings_n, Vector2(centre.x, centre.z), TURNTABLE_RADIUS + 0.18, 0.10, 48)
	_add_marking("HazardRings", _mesh_from(rings, rings_n), Color(0.86, 0.71, 0.14), 0.0)


## Banners: simple coloured meshes hung above the wall cap, alternating the two liveries,
## four to a wall. No text, no crest, nothing that could be read as anyone's mark
## (brief §3).
func _build_decor() -> void:
	var banners := Node3D.new()
	banners.name = "Banners"
	add_child(banners)
	var t := FightTypes.WALL_THICKNESS
	var span := _arena_size
	var mats := [_flat(BANNER_A), _flat(BANNER_B)]
	var pole_mat := _flat(Color(0.24, 0.25, 0.27))
	pole_mat.metallic = 0.5
	var index := 0
	for wall in range(4):
		for i in range(4):
			var along := -span * 0.5 + span * (float(i) + 0.5) / 4.0
			var pos := Vector3.ZERO
			var rot := 0.0
			match wall:
				0:
					pos = Vector3(along, 0.0, -_half - t * 0.4)
				1:
					pos = Vector3(along, 0.0, _half + t * 0.4)
					rot = PI
				2:
					pos = Vector3(-_half - t * 0.4, 0.0, along)
					rot = -PI * 0.5
				_:
					pos = Vector3(_half + t * 0.4, 0.0, along)
					rot = PI * 0.5
			var banner := MeshInstance3D.new()
			banner.name = "Banner%d_%d" % [wall, i]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.1, 1.5, 0.03)
			banner.mesh = mesh
			banner.material_override = mats[index % 2]
			banner.position = pos + Vector3(0.0, WALL_H + 0.85, 0.0)
			banner.rotation = Vector3(0.0, rot, 0.0)
			banners.add_child(banner)

			var pole := MeshInstance3D.new()
			var pole_mesh := BoxMesh.new()
			pole_mesh.size = Vector3(1.3, 0.07, 0.07)
			pole.mesh = pole_mesh
			pole.material_override = pole_mat
			pole.position = pos + Vector3(0.0, WALL_H + 1.62, 0.0)
			pole.rotation = Vector3(0.0, rot, 0.0)
			banners.add_child(pole)
			index += 1


# ---------------------------------------------------------------------------
# Seeded timeline
# ---------------------------------------------------------------------------
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	# FOUR draws, in this order: spike phase, jet period, jet phase, disc spin phase.
	super(rng)                                     # the spike phase, one draw
	_next_jet_period = 0
	var lo := int(round(JET_PERIOD_MIN_S * FightTypes.TICK_HZ))
	var hi := int(round(JET_PERIOD_MAX_S * FightTypes.TICK_HZ))
	if rng == null:
		_jet_period = lo
		_jet_phase = 0
		_spin_phase = 0.0
	else:
		_jet_period = rng.randi_range(lo, hi)
		_jet_phase = rng.randi_range(0, _jet_period - 1)
		# A3: never alight on the first tick, never inside the shared warning.
		_jet_phase = ArenaBase.warned_phase(_jet_phase,
			_jet_period, int(round(FLAME_BURN_S * FightTypes.TICK_HZ)))
		_spin_phase = rng.randf() * TAU
	for g in _grinders:
		var disc := g["disc"] as MeshInstance3D
		if is_instance_valid(disc):
			disc.rotation.y = _spin_phase


# ---------------------------------------------------------------------------
# Hazard tick
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	_tick_spikes()
	for g in _grinders:
		_tick_grinder(g, delta)
	var burn := int(round(FLAME_BURN_S * FightTypes.TICK_HZ))
	# Wave B: the jets take their hazards-up period on the tick a burn STARTS.
	if _next_jet_period > 0 and (_ticks + _jet_phase) % _jet_period == 0:
		_jet_period = _next_jet_period
		_next_jet_period = 0
		_jet_phase = posmod(-_ticks, _jet_period)
	var firing := ((_ticks + _jet_phase) % _jet_period) < burn
	for jet in _jets:
		_tick_flame_jet(jet, firing)
	_ticks += 1


## brief v4 §2: the Coliseum gets everything the other five have. The spike patch stays
## risen and the grinders spin up (both in ArenaBase); here the jets drop to the Furnace's
## 4 s endgame period and the floor discs spin at double speed.
func _on_phase(_phase_name: String) -> void:
	# A4: a burn under way carries on; otherwise the first endgame burn waits out the
	# shared warning (the jets lit 0.55 s after the endgame).
	var burn := int(round(FLAME_BURN_S * FightTypes.TICK_HZ))
	var t := (_ticks + _jet_phase) % _jet_period
	_next_jet_period = 0          # wave B: a waiting hazards-up period is dropped
	_jet_period = ENDGAME_JET_PERIOD_TICKS
	_jet_phase = ArenaBase.endgame_phase(_ticks, _jet_phase % _jet_period, _jet_period,
		burn, t < burn, t)
	for table_variant in _turntables:
		var table := table_variant as StaticBody3D
		if is_instance_valid(table):
			table.constant_angular_velocity *= ArenaBase.ENDGAME_RATE


# ---------------------------------------------------------------------------
# Wave B pacing: the Coliseum's stages (ArenaBase "the round in stages")
#   0:45 spikes every 4.5 s (base), jets x0.75 from their next burn, grinders every 20
#   1:30 the floor discs spin up x1.5
#   2:00 everything the endgame always did (patch up, jets 4 s, discs x2, grinders 15)
# ---------------------------------------------------------------------------
const STAGE_DISC_RATE := 1.5
var _next_jet_period := 0


func _on_stage(stage_index: int) -> void:
	super(stage_index)
	match stage_index:
		STAGE_HAZARDS_UP:
			if not _escalated:
				var burn := int(round(FLAME_BURN_S * FightTypes.TICK_HZ))
				_next_jet_period = _stage_period(_jet_period,
					burn + ArenaBase.WARN_LEAD_TICKS + 2 * ArenaBase.PHASE_SLACK_TICKS)
		STAGE_WAKE:
			if not _escalated:
				for table_variant in _turntables:
					var table := table_variant as StaticBody3D
					if is_instance_valid(table):
						table.constant_angular_velocity *= STAGE_DISC_RATE


func _wake_word() -> String:
	return "DISCS SPIN UP"


## The two discs' turn rates, rad/s, west then east. arenas_test reads them.
func turntable_rates() -> Array[float]:
	var out: Array[float] = []
	for table_variant in _turntables:
		var table := table_variant as StaticBody3D
		out.append(table.constant_angular_velocity.y if is_instance_valid(table) else 0.0)
	return out


func turntable_positions() -> Array[Vector3]:
	return [TURNTABLE_A, TURNTABLE_B]


func grinder_positions() -> Array[Vector3]:
	return [GRINDER_A, GRINDER_B]


func jets_firing() -> bool:
	for jet in _jets:
		if bool(jet["firing"]):
			return true
	return false


# ---------------------------------------------------------------------------
# The AI's read
# ---------------------------------------------------------------------------
func hazard_helpers() -> Dictionary:
	var burn := int(round(FLAME_BURN_S * FightTypes.TICK_HZ))
	var t := (_ticks + _jet_phase) % _jet_period
	var jet_in := 0.0 if t < burn else float(_jet_period - t) / float(FightTypes.TICK_HZ)
	return {
		# The grinders never stop, so on this floor the answer is always zero. The list of
		# positions is what an AI here has to work with, not the clock.
		"next_danger_in_s": 0.0,
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
		# Kept separately so a smarter driver can still time the two hazards that DO have
		# a clock.
		"spike_rise_in_s": seconds_to_spike_rise(),
		"flame_in_s": jet_in,
	}


## Wave A: the warning layer's clock for the jets (both share one). Read-only.
func _jet_seconds_to_fire(_jet: Dictionary) -> float:
	var burn := int(round(FLAME_BURN_S * FightTypes.TICK_HZ))
	var t := (_ticks + _jet_phase) % _jet_period
	return 0.0 if t < burn else float(_jet_period - t) / float(FightTypes.TICK_HZ)


func _danger_positions() -> Array[Vector3]:
	var out: Array[Vector3] = [GRINDER_A, GRINDER_B]
	if _spikes_up or seconds_to_spike_rise() < 1.5:
		out.append(_spike_centre)
	var inset := _half - FightTypes.WALL_THICKNESS * 0.5
	out.append(Vector3(JET_NORTH_X, 0.0, -inset + FLAME_REACH * 0.5))
	out.append(Vector3(JET_SOUTH_X, 0.0, inset - FLAME_REACH * 0.5))
	return out


## The four pockets between the turntables, the grinders and the jets.
func _safe_positions() -> Array[Vector3]:
	return [
		Vector3(-4.2, 0.0, 3.4),
		Vector3(4.2, 0.0, -3.4),
		Vector3(-1.6, 0.0, -3.6),
		Vector3(1.6, 0.0, 3.6),
	]
