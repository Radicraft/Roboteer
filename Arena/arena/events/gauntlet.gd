extends "res://arena/events/event_arena_base.gd"
## THE RUN (side event 2, docs/stage6-spec.md §1, brief §10 "Gauntlet: traverse a hazard
## run against the clock").
##
## A 24 x 6 m corridor with one of each of the game's hazards in it, in the order the
## spec sets, and a pad at the far end. There is no opponent: the pressure is the clock in
## front of you and BANDSAW behind you (the rules send it in twenty seconds after the
## bell, from the gate at your back).
##
##   FLOOR PLAN (24 x 6 m, north is -Z, drive +X)
##
##   -12      -9.6    -7.6     -3.6      0.4      4.6     7.2    9.8    +12
##    +----------------------------------------------------------------------+
##  -3|  G  P  |       |       |   (g) |  <<<<< |       |[#####]|   /////////|
##    |        | ##### | ##### |       |        |[#####]|       |   /////////|
##   0|        | ##### | ##### |       |        |[#####]|       |   //PAD///|
##    |        | ##### | ##### |   (g) |  >>>>> |       |[#####]|   /////////|
##   +3|       |       |       |       |        |       |       |   /////////|
##    +----------------------------------------------------------------------+
##      start     spike patch     grinder   flame gate   crush presses   finish
##      G chaser gate (-11.7, 0, 0)         (alternating)  (offset in Z)
##      P player mark (-11.0, 0, 0)
##
## Every section leaves a lane, and no two lanes are the same lane, so the run is a weave
## rather than a sprint:
##   * SPIKES, 4 m across a 6 m corridor: a 1 m ribbon of clear floor on each flank, or
##     drive straight over between rises. The Stage 3 cadence, unchanged.
##   * GRINDERS at z = +/-1.35: the lane is the centre line, or either outside edge.
##   * FLAME GATE: two opposed wall jets that ALTERNATE, so the lane is the far side of
##     the corridor from whichever one is lit, and twice a cycle both are out.
##   * CRUSH PRESSES, offset in Z from each other: the lane crosses from the +Z half to
##     the -Z half between them.
## The finish pad is the full width of the corridor, so the run ends the moment you are on
## it, not when you have parked on a mark.
##
## Marking scheme (original, brief §3): the corridor is painted as a WORKS FLOOR. A
## continuous hazard-yellow kerb line down each flank; a numbered section bar across the
## floor at the mouth of each hazard (one, two, three, four ticks, which is the only place
## in the game that counts anything on the floor); a keep-out ring around each grinder;
## chevrons under each press pointing down; and the finish pad hatched and lit.

const LENGTH := 24.0
const WIDTH := 6.0

const SPIKE_X := -7.6
const SPIKE_EXTENT := 4.0
const GRINDER_X := -3.6
const GRINDER_Z := 1.35
const FLAME_X := 0.4
## Alternating gate: north jet, both out, south jet, both out.
const FLAME_ON_S := 2.2
const FLAME_GAP_S := 1.0
const FLAME_CYCLE_S := (FLAME_ON_S + FLAME_GAP_S) * 2.0

const PRESS_A := Vector3(4.6, 0.0, -1.0)
const PRESS_B := Vector3(7.2, 0.0, 1.0)
const PRESS_SIZE := Vector3(1.6, 0.5, 2.4)
const PRESS_UP_Y := 1.9
const PRESS_DOWN_Y := 0.37
const PRESS_WARN_S := 1.4
const PRESS_DOWN_S := 0.5
const PRESS_HOLD_S := 0.5
const PRESS_UP_S := 1.1
const PRESS_IDLE_S := 2.7
const PRESS_CYCLE_S := PRESS_WARN_S + PRESS_DOWN_S + PRESS_HOLD_S + PRESS_UP_S + PRESS_IDLE_S
## Crush numbers lifted from `crush.gd`, which measured them: heavy impulse on a slow
## cadence, plus a separate small bite through the top face, which is the flattening.
const PRESS_IMPULSE := 58.0
const PRESS_PERIOD_TICKS := 24
const PRESS_TOP_AMOUNT := 0.05

const PAD_X0 := 9.8
const PAD_CENTRE := Vector3(10.9, 0.0, 0.0)
const GATE := Vector3(-11.7, 0.25, 0.0)
const START_MARK := Vector3(-11.0, 0.25, 0.0)
## Where the second machine is parked. A Gauntlet has no opponent, but the fight always
## builds two, so the run gives the spare one a bay behind the finish pad and the rules
## freeze it there. Documented in docs/stage6-events-notes.md.
const PEN_MARK := Vector3(11.5, 0.25, 2.3)

const TINT_FLOOR := Color(0.90, 0.90, 0.92)
const TINT_WALL := Color(2.30, 2.28, 2.30)
const COL_KERB := Color(0.93, 0.76, 0.13)
const COL_SECTION := Color(0.26, 0.27, 0.30)
const COL_PAD := Color(0.30, 0.86, 0.52)

var _grinders: Array = []
var _jets: Array = []
var _presses: Array = []
var _pad: Area3D = null
var _flame_phase_ticks := 0
var _press_phase_ticks := 0


func arena_id() -> String:
	return "gauntlet"


func _configure() -> void:
	_set_rect(Vector2(LENGTH, WIDTH))
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = false
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.30
	_ambient_tint = Color(0.98, 0.96, 0.94)
	_key_colour = Color(1.0, 0.97, 0.92)
	_key_energy = 0.54
	_bg_tint = Color(0.86, 0.87, 0.92)
	_spawn_marks = [START_MARK, PEN_MARK]
	_spawn_dirs = [Vector3.RIGHT, Vector3.LEFT]


# --------------------------------------------------------------------------------------
# Hazards, west to east
# --------------------------------------------------------------------------------------
func _build_hazards() -> void:
	_add_spike_patch(Vector3(SPIKE_X, 0.0, 0.0), SPIKE_EXTENT)
	_grinders.append(_add_grinder(Vector3(GRINDER_X, 0.0, -GRINDER_Z), "GrinderNorth"))
	_grinders.append(_add_grinder(Vector3(GRINDER_X, 0.0, GRINDER_Z), "GrinderSouth"))
	_jets.append(_add_flame_jet(Vector3(FLAME_X, 0.35, -WIDTH * 0.5), Vector3(0.0, 0.0, 1.0),
		"FlameNorth"))
	_jets.append(_add_flame_jet(Vector3(FLAME_X, 0.35, WIDTH * 0.5), Vector3(0.0, 0.0, -1.0),
		"FlameSouth"))
	_presses.append(_add_press(PRESS_A, "PressWest", 0.0))
	_presses.append(_add_press(PRESS_B, "PressEast", PRESS_CYCLE_S * 0.5))
	_build_finish_pad()


## One overhead press. `ArenaBase` ships spikes, a grinder, a flame jet and a turntable;
## the ram lives in `crush.gd`, which is not mine to reach into, so this is the same idea
## built from the base's own plumbing (`_make_hazard_area`, `_box_shape`,
## `_damage_overlaps`, `_crush_bots_in_area`) and the same measured numbers. It comes DOWN
## rather than in from a wall, because a 6 m corridor has no room for a 0.9 m side stroke.
func _add_press(centre: Vector3, press_name: String, phase_s: float) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.name = press_name
	body.sync_to_physics = false
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.add_to_group("arena_hazard")
	body.position = Vector3(centre.x, PRESS_UP_Y, centre.z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PRESS_SIZE
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(PRESS_SIZE)
	mi.material_override = _textured(MAT_STEEL, Color(1.4, 1.35, 1.3), 0.5, Color(0.46, 0.45, 0.47))
	body.add_child(mi)
	add_child(body)

	# The stroke volume, at floor level. Live only while the press is down.
	var holder := Node3D.new()
	holder.name = press_name + "Zone"
	holder.position = Vector3(centre.x, 0.0, centre.z)
	add_child(holder)
	var area := _make_hazard_area("Crush",
		_box_shape(Vector3(PRESS_SIZE.x, 0.7, PRESS_SIZE.z), Vector3(0.0, 0.3, 0.0)), holder)

	return {"body": body, "area": area, "centre": Vector3(centre.x, 0.0, centre.z),
		"phase": int(round(phase_s * FightTypes.TICK_HZ)), "down": false}


func _build_finish_pad() -> void:
	_pad = Area3D.new()
	_pad.name = "FinishPad"
	_pad.collision_layer = FightTypes.LAYER_HAZARD
	_pad.collision_mask = FightTypes.LAYER_BOT
	_pad.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH * 0.5 - PAD_X0 + 0.2, 1.2, WIDTH)
	shape.shape = box
	shape.position = Vector3((PAD_X0 + LENGTH * 0.5) * 0.5, 0.5, 0.0)
	_pad.add_child(shape)
	add_child(_pad)


# --------------------------------------------------------------------------------------
# Markings
# --------------------------------------------------------------------------------------
func _build_markings() -> void:
	var kerb := PackedVector3Array()
	var kerb_n := PackedVector3Array()
	for z in [-WIDTH * 0.5 + 0.22, WIDTH * 0.5 - 0.22]:
		_mark_line(kerb, kerb_n, Vector2(-LENGTH * 0.5 + 0.2, z), Vector2(PAD_X0, z), 0.10)
	for centre in [Vector3(GRINDER_X, 0.0, -GRINDER_Z), Vector3(GRINDER_X, 0.0, GRINDER_Z)]:
		_mark_ring(kerb, kerb_n, Vector2(centre.x, centre.z), GRINDER_RADIUS + 0.30, 0.08, 32)
	_add_marking("Kerb", _mesh_from(kerb, kerb_n), COL_KERB, 0.0)

	var marks := PackedVector3Array()
	var marks_n := PackedVector3Array()
	# Section bars at the mouth of each hazard, ticked one to four. The only counting mark
	# on any floor in the game, and it is here because the run has an order to read.
	var mouths := [SPIKE_X - SPIKE_EXTENT * 0.5 - 0.5, GRINDER_X - 1.3, FLAME_X - 1.3,
		PRESS_A.x - 1.5]
	for i in range(mouths.size()):
		var x: float = mouths[i]
		_mark_line(marks, marks_n, Vector2(x, -WIDTH * 0.5 + 0.3), Vector2(x, WIDTH * 0.5 - 0.3), 0.09)
		for t in range(i + 1):
			var z := -0.9 + float(t) * 0.6
			_mark_line(marks, marks_n, Vector2(x - 0.34, z), Vector2(x - 0.34, z + 0.34), 0.12)
	# Down-chevrons under each press.
	for press_centre in [PRESS_A, PRESS_B]:
		for row in range(3):
			var x0: float = press_centre.x - 0.5 + float(row) * 0.5
			_mark_triangle(marks, marks_n,
				Vector2(x0, press_centre.z - 0.9), Vector2(x0, press_centre.z + 0.9),
				Vector2(x0 + 0.34, press_centre.z))
	_add_marking("SectionMarks", _mesh_from(marks, marks_n), COL_SECTION, 0.0)

	var pad := PackedVector3Array()
	var pad_n := PackedVector3Array()
	for i in range(9):
		var x := PAD_X0 + 0.15 + float(i) * 0.24
		_mark_line(pad, pad_n, Vector2(x, -WIDTH * 0.5 + 0.25), Vector2(x - 0.7, WIDTH * 0.5 - 0.25), 0.10)
	_mark_line(pad, pad_n, Vector2(PAD_X0, -WIDTH * 0.5), Vector2(PAD_X0, WIDTH * 0.5), 0.12)
	_add_marking("FinishPad", _mesh_from(pad, pad_n), COL_PAD, 1.8)


# --------------------------------------------------------------------------------------
# Seeding and the tick
# --------------------------------------------------------------------------------------
## Fixed order and a fixed COUNT of draws, whatever is built: the base takes the spike
## phase, then the flame gate, then the presses. Three draws, always.
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	super(rng)
	var flame_cycle := int(round(FLAME_CYCLE_S * FightTypes.TICK_HZ))
	var press_cycle := int(round(PRESS_CYCLE_S * FightTypes.TICK_HZ))
	_flame_phase_ticks = rng.randi_range(0, flame_cycle - 1) if rng != null else 0
	_press_phase_ticks = rng.randi_range(0, press_cycle - 1) if rng != null else 0


func _physics_process(delta: float) -> void:
	_tick_spikes()
	for g in _grinders:
		_tick_grinder(g, delta)
	_tick_flame_gate()
	for p in _presses:
		_tick_press(p)
	_ticks += 1


func _tick_flame_gate() -> void:
	var cycle := int(round(FLAME_CYCLE_S * FightTypes.TICK_HZ))
	var on := int(round(FLAME_ON_S * FightTypes.TICK_HZ))
	var half := int(round((FLAME_ON_S + FLAME_GAP_S) * FightTypes.TICK_HZ))
	var t := (_ticks + _flame_phase_ticks) % cycle
	_tick_flame_jet(_jets[0], t < on)
	_tick_flame_jet(_jets[1], t >= half and t < half + on)


func _tick_press(press: Dictionary) -> void:
	var cycle := int(round(PRESS_CYCLE_S * FightTypes.TICK_HZ))
	var t := (_ticks + int(press["phase"])) % cycle
	var warn := int(round(PRESS_WARN_S * FightTypes.TICK_HZ))
	var down := warn + int(round(PRESS_DOWN_S * FightTypes.TICK_HZ))
	var hold := down + int(round(PRESS_HOLD_S * FightTypes.TICK_HZ))
	var up := hold + int(round(PRESS_UP_S * FightTypes.TICK_HZ))

	var amount := 0.0                         # 0 = raised, 1 = pressed home
	if t >= warn and t < down:
		amount = float(t - warn) / float(maxi(down - warn, 1))
	elif t >= down and t < hold:
		amount = 1.0
	elif t >= hold and t < up:
		amount = 1.0 - float(t - hold) / float(maxi(up - hold, 1))
	var body := press["body"] as AnimatableBody3D
	if is_instance_valid(body):
		body.position.y = lerpf(PRESS_UP_Y, PRESS_DOWN_Y, amount)

	var pressing := amount > 0.8
	if pressing != bool(press["down"]):
		press["down"] = pressing
		(press["area"] as Area3D).monitoring = pressing
		emit_signal("hazard_fx", "ram", pressing, press["centre"])
	if pressing and _ticks % PRESS_PERIOD_TICKS == 0:
		_damage_overlaps(press["area"] as Area3D, PRESS_IMPULSE)
		_crush_bots_in_area(press["area"] as Area3D, PRESS_TOP_AMOUNT)


# --------------------------------------------------------------------------------------
# The contract the Gauntlet rules read
# --------------------------------------------------------------------------------------
func finish_pad_centre() -> Vector3:
	return PAD_CENTRE


## The run is over the instant any part is on the pad, so this asks the sensor, not the
## chassis: a machine that arrives on its nose with the chassis still short of the line
## has still finished.
func pad_has_bot() -> bool:
	return _area_has_part(_pad)


func bot_on_pad(bot: Node) -> bool:
	if bot == null or _pad == null or not _pad.monitoring:
		return false
	for body in _pad.get_overlapping_bodies():
		if body is BotPart and (body as BotPart).owner_bot == bot \
				and not (body as BotPart).detached:
			return true
	return false


func on_finish_pad(position: Vector3) -> bool:
	return position.x >= PAD_X0


## Where the chaser comes in. Behind the start mark, on the centre line, facing the run.
func chaser_gate() -> Vector3:
	return GATE


func chaser_facing() -> Vector3:
	return Vector3.RIGHT


func hazard_helpers() -> Dictionary:
	var danger: Array[Vector3] = [Vector3(SPIKE_X, 0.0, 0.0)]
	for g in _grinders:
		danger.append(g["centre"])
	for j in _jets:
		if bool(j["firing"]):
			danger.append(j["centre"])
	for p in _presses:
		danger.append(p["centre"])
	# Somewhere to stand in each section, in order, so a driver that only knows how to run
	# to a safe point still threads the run rather than parking in the spikes.
	var safe: Array[Vector3] = [
		Vector3(SPIKE_X, 0.0, WIDTH * 0.5 - 0.7),
		Vector3(GRINDER_X, 0.0, 0.0),
		Vector3(FLAME_X - 1.8, 0.0, 0.0),
		Vector3((PRESS_A.x + PRESS_B.x) * 0.5, 0.0, 2.0),
		PAD_CENTRE,
	]
	return {
		"next_danger_in_s": seconds_to_spike_rise(),
		"danger_positions": danger,
		"safe_positions": safe,
	}
