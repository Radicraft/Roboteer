class_name FurnaceArena extends ArenaBase
## Furnace (brief §7 arena 4, docs/stage5-spec.md §3): wall flame jets on two walls on a
## seeded timer, and a 2 m conveyor strip along the third wall that carries anything
## standing on it at 1.2 m/s. The jets burn and cut the drive; the belt decides where you
## are when they fire. Neither knows whose bot it has.
##
##   FLOOR PLAN (10 x 10 m, north is -Z)
##
##     -5      -3                  0                +5
##   -5 +======+------------------------------------+
##      | belt |    ^      ^          ^             |   ^  north jets, firing +Z
##      |  ||  |    |      |          |             |      (x = -1.0, 1.2, 3.4)
##      |  ||  |                                    |   P  player spawn (-2.5, -1.6)
##    0 |  ||  |  P                     O           |   O  opponent spawn (2.5, 1.6)
##      |  ||  |                                    |   || conveyor, running SOUTH
##      |  vv  |             |      |        |      |      at 1.2 m/s
##      |      |             v      v        v      |   v  south jets, firing -Z
##   +5 +======+------------------------------------+      (x = -3.4, -1.2, 1.0)
##
## The belt runs south along the west wall and discharges straight into the south jet at
## x = -3.4: ride it and the arena hands you to the flame. That is the arena's one idea,
## and it works on both bots because the belt is a surface velocity, not a trigger.
##
## Both spawns sit in the jet-free middle band (|z| < 2.4, since a jet reaches 2.5 m) and
## clear of the belt (|x| < 3.0), which is why they are NOT the Yard's corner marks: the
## Furnace's corners are all hazard.
##
## Marking scheme (original, brief §3): belt edge lines with direction arrows, a burn
## fan painted in front of every nozzle, and a plain safe-band line across the middle.

const BELT_WIDTH := 2.0
const BELT_SPEED := 1.2
## Seeded firing pattern: each bank gets its own period in this window and its own phase.
const JET_PERIOD_MIN_S := 8.0
const JET_PERIOD_MAX_S := 12.0
const JET_BURN_S := ArenaBase.FLAME_BURN_S

const NORTH_JET_X := [-1.0, 1.2, 3.4]
const SOUTH_JET_X := [-3.4, -1.2, 1.0]
const SPAWN_A := Vector3(-2.5, 0.25, -1.6)
const SPAWN_B := Vector3(2.5, 0.25, 1.6)

## Warm rust and orange light.
const TINT_FLOOR := Color(1.22, 1.00, 0.86)
const TINT_WALL := Color(2.70, 2.26, 1.90)
const COL_BELT_EDGE := Color(0.88, 0.58, 0.10)
const COL_BURN_FAN := Color(0.42, 0.22, 0.12)

var _belt: StaticBody3D = null
var _jets_north: Array = []
var _jets_south: Array = []
var _period_north := int(round(10.0 * FightTypes.TICK_HZ))
var _period_south := int(round(10.0 * FightTypes.TICK_HZ))
var _phase_north := 0
var _phase_south := 0


func arena_id() -> String:
	return "furnace"


func _configure() -> void:
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.30
	_ambient_tint = Color(1.28, 0.98, 0.76)      # the room is lit by what is burning in it
	_ambient_energy_scale = 1.1
	_key_colour = Color(1.0, 0.90, 0.76)
	_key_energy = 0.48
	_fill_colour = Color(1.0, 0.62, 0.30)
	_fill_energy = 0.16
	_bg_tint = Color(1.25, 0.92, 0.72)
	_grid_enabled = false


func spawn_position(team_index: int) -> Vector3:
	return SPAWN_A if team_index == 0 else SPAWN_B


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build_floor() -> void:
	var main := _arena_size - BELT_WIDTH
	_add_floor_slab("Floor", Vector2(BELT_WIDTH * 0.5, 0.0), Vector2(main, _arena_size))
	_build_belt()


## The conveyor. Jolt honours `constant_linear_velocity` on a StaticBody3D: the surface
## moves without the body moving, which is exactly a belt and costs nothing per tick
## (measured headless, see docs/stage5-arenas-notes.md).
func _build_belt() -> void:
	var x := -_half + BELT_WIDTH * 0.5
	_belt = _add_floor_slab("Conveyor", Vector2(x, 0.0), Vector2(BELT_WIDTH, _arena_size))
	var pm := PhysicsMaterial.new()
	# A belt with the floor's 0.6 friction slips: a 60 kg bot never reaches belt speed.
	pm.friction = 1.0
	pm.bounce = 0.0
	_belt.physics_material_override = pm
	_belt.constant_linear_velocity = Vector3(0.0, 0.0, BELT_SPEED)

	# Slats across the belt so the motion is readable even in a still frame.
	var slats := MeshInstance3D.new()
	slats.name = "Slats"
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var n := int(_arena_size / 0.5)
	for i in range(n):
		var z := -_half + 0.25 + float(i) * 0.5
		_mark_line(verts, norms, Vector2(x - BELT_WIDTH * 0.45, z),
			Vector2(x + BELT_WIDTH * 0.45, z), 0.06)
	slats.mesh = _mesh_from(verts, norms)
	slats.material_override = _flat(Color(0.20, 0.17, 0.15))
	slats.position = Vector3(0.0, MARK_Y, 0.0)
	add_child(slats)


func _build_hazards() -> void:
	var inset := _half - FightTypes.WALL_THICKNESS * 0.5
	for x_variant in NORTH_JET_X:
		var x := float(x_variant)
		_jets_north.append(_add_flame_jet(Vector3(x, 0.28, -inset), Vector3(0, 0, 1),
			"JetNorth%d" % _jets_north.size()))
	for x_variant in SOUTH_JET_X:
		var x := float(x_variant)
		_jets_south.append(_add_flame_jet(Vector3(x, 0.28, inset), Vector3(0, 0, -1),
			"JetSouth%d" % _jets_south.size()))


func _build_markings() -> void:
	var belt_x := -_half + BELT_WIDTH * 0.5
	var edges := PackedVector3Array()
	var edges_n := PackedVector3Array()
	var e := belt_x + BELT_WIDTH * 0.5
	_mark_line(edges, edges_n, Vector2(e, -_half), Vector2(e, _half), 0.10)
	# Direction arrows down the belt: three chevrons pointing south.
	for i in range(5):
		var z := -_half + 1.2 + float(i) * 2.0
		_mark_triangle(edges, edges_n, Vector2(belt_x - 0.45, z - 0.4),
			Vector2(belt_x + 0.45, z - 0.4), Vector2(belt_x, z + 0.45))
	_add_marking("BeltEdge", _mesh_from(edges, edges_n), COL_BELT_EDGE, 0.6)

	# A burn fan in front of every nozzle: scorched floor, so the reach is obvious before
	# the first jet ever fires.
	var fans := PackedVector3Array()
	var fans_n := PackedVector3Array()
	var inset := _half - FightTypes.WALL_THICKNESS * 0.5
	for x_variant in NORTH_JET_X:
		var x := float(x_variant)
		_mark_rect(fans, fans_n, Vector2(x, -inset + FLAME_REACH * 0.5 + 0.2),
			Vector2(FLAME_RADIUS * 2.0, FLAME_REACH))
	for x_variant in SOUTH_JET_X:
		var x := float(x_variant)
		_mark_rect(fans, fans_n, Vector2(x, inset - FLAME_REACH * 0.5 - 0.2),
			Vector2(FLAME_RADIUS * 2.0, FLAME_REACH))
	_add_marking("BurnFans", _mesh_from(fans, fans_n), COL_BURN_FAN, 0.0)

	# The safe band: the only two lines in the middle of the floor, marking the ground no
	# jet reaches. Reading them is the whole skill of this arena.
	var band := PackedVector3Array()
	var band_n := PackedVector3Array()
	var safe := _half - FLAME_REACH - 0.2
	for z in [-safe, safe]:
		for i in range(9):
			var x0 := -_half + BELT_WIDTH + 0.2 + float(i) * 0.9
			_mark_line(band, band_n, Vector2(x0, z), Vector2(x0 + 0.5, z), 0.055)
	_add_marking("SafeBand", _mesh_from(band, band_n), Color(0.55, 0.52, 0.46), 0.0)


# ---------------------------------------------------------------------------
# Seeded timeline
# ---------------------------------------------------------------------------
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	# FOUR draws, always, in this order: north period, north phase, south period, south
	# phase. The order IS the seed.
	var lo := int(round(JET_PERIOD_MIN_S * FightTypes.TICK_HZ))
	var hi := int(round(JET_PERIOD_MAX_S * FightTypes.TICK_HZ))
	if rng == null:
		_period_north = lo
		_period_south = hi
		_phase_north = 0
		_phase_south = lo / 2
		return
	_period_north = rng.randi_range(lo, hi)
	_phase_north = rng.randi_range(0, _period_north - 1)
	_period_south = rng.randi_range(lo, hi)
	_phase_south = rng.randi_range(0, _period_south - 1)


# ---------------------------------------------------------------------------
# Hazard tick
# ---------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	var burn := int(round(JET_BURN_S * FightTypes.TICK_HZ))
	var north := ((_ticks + _phase_north) % _period_north) < burn
	var south := ((_ticks + _phase_south) % _period_south) < burn
	for jet in _jets_north:
		_tick_flame_jet(jet, north)
	for jet in _jets_south:
		_tick_flame_jet(jet, south)
	_ticks += 1


func jets_firing() -> bool:
	for jet in _jets_north + _jets_south:
		if bool(jet["firing"]):
			return true
	return false


func belt_velocity() -> Vector3:
	return _belt.constant_linear_velocity if is_instance_valid(_belt) else Vector3.ZERO


func belt_centre_x() -> float:
	return -_half + BELT_WIDTH * 0.5


# ---------------------------------------------------------------------------
# The AI's read
# ---------------------------------------------------------------------------
func hazard_helpers() -> Dictionary:
	var burn := int(round(JET_BURN_S * FightTypes.TICK_HZ))
	var soonest := minf(_ticks_to_fire(_period_north, _phase_north, burn),
		_ticks_to_fire(_period_south, _phase_south, burn))
	return {
		"next_danger_in_s": soonest / float(FightTypes.TICK_HZ),
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
	}


func _ticks_to_fire(period: int, phase: int, burn: int) -> float:
	var t := (_ticks + phase) % period
	if t < burn:
		return 0.0
	return float(period - t)


## Every nozzle's lane centre, plus the belt, which is not damage but is still somewhere
## an AI should not park.
func _danger_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var inset := _half - FightTypes.WALL_THICKNESS * 0.5
	for x_variant in NORTH_JET_X:
		out.append(Vector3(float(x_variant), 0.0, -inset + FLAME_REACH * 0.5))
	for x_variant in SOUTH_JET_X:
		out.append(Vector3(float(x_variant), 0.0, inset - FLAME_REACH * 0.5))
	out.append(Vector3(belt_centre_x(), 0.0, 0.0))
	return out


## The jet-free middle band, off the belt.
func _safe_positions() -> Array[Vector3]:
	var safe_z := _half - FLAME_REACH - 0.6
	var x0 := -_half + BELT_WIDTH + 0.8
	return [
		Vector3(x0, 0.0, 0.0),
		Vector3(_half - 0.9, 0.0, 0.0),
		Vector3(0.0, 0.0, -safe_z * 0.5),
		Vector3(0.0, 0.0, safe_z * 0.5),
	]


func spikes_risen() -> bool:
	return false


func seconds_to_spike_rise() -> float:
	return 999.0
