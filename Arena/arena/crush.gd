class_name CrushArena extends ArenaBase
## The Crush (brief §7 arena 5, docs/stage5-spec.md §3): a hydraulic ram in each of the
## long walls that presses 0.9 m into the arena on a seeded timer, pins whatever is in
## the stroke and flattens it. The ram is a real kinematic body, so it SHOVES as well as
## damages, and the damage goes through the top face: a bot caught in the stroke loses its
## top plate, then its core.
##
##   FLOOR PLAN (10 x 10 m, north is -Z)
##
##     -5                    0                    +5
##   -5 +-------------------------------------------+
##      |####|  P                                   |   #### west ram, 3.2 m long,
##      |####|         >>>>              <<<<       |        stroke 0.9 m east
##      |####|                                      |   >>>> / <<<< floor chevrons,
##    0 |####|                                      |        lit before a press
##      |####|                            |####|    |   P / O the Yard's spawn marks
##      |    |                            |####|    |
##      |    |                        O   |####|    |   east ram, stroke 0.9 m west
##   +5 +-------------------------------------------+
##
## The rams are OFFSET along Z from each other (west ram centred at z = -1.2, east ram at
## z = +1.2), so the safe ground is a diagonal corridor rather than a middle stripe: you
## can always get out, but not by driving straight. Both spawns sit in that corridor and
## outside both strokes, and the layout is a 180 degree rotation of itself, so neither bot
## starts nearer a ram.
##
## Marking scheme (original, brief §3): a bank of chevrons painted in each ram's stroke,
## pointing the way the ram travels, emissive and lit for the two seconds before a press
## and all through it. Plus a hazard-yellow kerb line at the edge of each stroke, which is
## the line you must be the far side of.

const RAM_LENGTH := 3.2           # metres along Z
const RAM_HEIGHT := 0.75
const RAM_DEPTH := 0.55           # metres along X
const RAM_STROKE := 0.9
const PRESS_S := 1.5
const HOLD_S := 0.6
const RETRACT_S := 1.0
const WARN_S := 2.0
const CYCLE_MIN_S := 10.0
const CYCLE_MAX_S := 14.0
## Heavy, as the spec asks: three or four of these through a side plate is the end of it.
const CRUSH_IMPULSE := 58.0
const CRUSH_PERIOD_TICKS := 24
## The top face takes a separate, smaller bite every damage tick: this is the flattening.
const CRUSH_TOP_AMOUNT := 0.05

const WEST_RAM_Z := -1.2
const EAST_RAM_Z := 1.2

const STATE_IDLE := 0
const STATE_PRESS := 1
const STATE_HOLD := 2
const STATE_RETRACT := 3

## Concrete and hazard yellow. Wave A: the floor was 0.88 at metallic 0.08 and read as
## near black on a phone (arenas.md §2.5). The concrete albedo averages 0.17 (sRGB), about
## 0.025 linear, against the Yard plate's 0.21; the tint is an sRGB multiplier, so 2.55
## (x7.8 linear) lands the floor at ~0.19, the Yard's value band. The walls drop from 2.35
## to 1.6 with a warm industrial cast.
const TINT_FLOOR := Color(2.55, 2.53, 2.47)
const TINT_WALL := Color(1.62, 1.55, 1.38)
const COL_CHEVRON := Color(0.93, 0.76, 0.13)
const COL_KERB := Color(0.28, 0.27, 0.24)

var _rams: Array = []


func arena_id() -> String:
	return "crush"


func _configure() -> void:
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT
	_floor_mat = MAT_CONCRETE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.08
	_floor_friction = 0.72                       # bare concrete, more grip than plate
	_ambient_tint = Color(0.98, 0.98, 1.0)
	_key_colour = Color(1.0, 0.99, 0.96)
	_key_energy = 0.52
	_bg_tint = Color(0.85, 0.86, 0.88)
	_grid_enabled = false


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build_hazards() -> void:
	var wall_face := _half - FightTypes.WALL_THICKNESS * 0.5
	_rams.append(_add_ram("RamWest", Vector3(-wall_face, 0.0, WEST_RAM_Z), 1.0))
	_rams.append(_add_ram("RamEast", Vector3(wall_face, 0.0, EAST_RAM_Z), -1.0))


## `sign_x` is the direction the ram travels: +1 for the west ram, -1 for the east one.
func _add_ram(ram_name: String, wall_point: Vector3, sign_x: float) -> Dictionary:
	var rest_x := wall_point.x + sign_x * RAM_DEPTH * 0.5

	var body := AnimatableBody3D.new()
	body.name = ram_name
	body.sync_to_physics = false
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.position = Vector3(rest_x, RAM_HEIGHT * 0.5, wall_point.z)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.0
	body.physics_material_override = pm

	var size := Vector3(RAM_DEPTH, RAM_HEIGHT, RAM_LENGTH)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	# Wave A: a cast ram head (bevelled block, ribs, a steel frame and bolt heads round
	# the face) in dark painted steel with two chrome piston rods running back into the
	# wall, which slide into view as it presses. It used to be MAT_STEEL at 1.35x albedo
	# and read as a blank white block. Render only: the BoxShape3D above is unchanged.
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = HM.ram_head(size, sign_x, RAM_STROKE + FightTypes.WALL_THICKNESS + 0.45,
		[_hazard_mat("ram"), _hazard_mat("chrome"), _hazard_mat("steel")])
	body.add_child(mi)

	# A yellow and black face plate, so the business end reads from the camera.
	var face := MeshInstance3D.new()
	face.name = "Face"
	var face_mesh := BoxMesh.new()
	face_mesh.size = Vector3(0.05, RAM_HEIGHT * 0.72, RAM_LENGTH * 0.96)
	face.mesh = face_mesh
	face.material_override = _chevron_strip_material()
	face.position = Vector3(sign_x * (RAM_DEPTH * 0.5 + 0.025), 0.0, 0.0)
	body.add_child(face)
	add_child(body)

	# The crush zone: the volume the ram sweeps. Anything in here while the ram is
	# pressing is between the ram and the wall it came out of, and gets both the heavy
	# impulse and the top-face bite.
	var zone_holder := Node3D.new()
	zone_holder.name = ram_name + "Zone"
	zone_holder.position = Vector3(rest_x + sign_x * (RAM_DEPTH * 0.5 + RAM_STROKE * 0.5),
		0.0, wall_point.z)
	add_child(zone_holder)
	var area := _make_hazard_area("Crush",
		_box_shape(Vector3(RAM_STROKE, RAM_HEIGHT, RAM_LENGTH), Vector3(0.0, RAM_HEIGHT * 0.5, 0.0)),
		zone_holder)

	# The warning lamp on the wall above the ram.
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.08, 0.1, RAM_LENGTH * 0.5)
	lamp.mesh = lamp_mesh
	var lamp_mat := _lamp(COL_CHEVRON, 0.4)
	lamp.material_override = lamp_mat
	lamp.position = Vector3(wall_point.x - sign_x * 0.02, RAM_HEIGHT + 0.14, wall_point.z)
	add_child(lamp)

	# Wave A: the housing the rods retract into, behind the wall (outside the arena, no
	# collision), so the ram comes OUT of something.
	var housing := MeshInstance3D.new()
	housing.name = ram_name + "Housing"
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.9, RAM_HEIGHT + 0.3, RAM_LENGTH + 0.4)
	housing.mesh = housing_mesh
	housing.material_override = _hazard_mat("dark")
	housing.position = Vector3(wall_point.x - sign_x * (FightTypes.WALL_THICKNESS * 0.5 + 0.45 + 0.1),
		(RAM_HEIGHT + 0.3) * 0.5, wall_point.z)
	add_child(housing)

	return {
		"body": body, "area": area, "zone": zone_holder, "lamp_mat": lamp_mat,
		"sign": sign_x, "rest_x": rest_x, "z": wall_point.z,
		"centre": Vector3(rest_x + sign_x * (RAM_DEPTH * 0.5 + RAM_STROKE * 0.5), 0.0, wall_point.z),
		"state": STATE_IDLE, "state_ticks": 0, "cycle": int(round(12.0 * FightTypes.TICK_HZ)),
		"phase": 0, "chevron_mat": null, "extension": 0.0,
	}


## Drawn from _build_decor(), not from ArenaBase's _build_markings() slot, because the
## chevron material is handed to the rams and those do not exist until _build_hazards()
## has run.
func _build_decor() -> void:
	var wall_face := _half - FightTypes.WALL_THICKNESS * 0.5
	var chevrons := PackedVector3Array()
	var chev_n := PackedVector3Array()
	var kerbs := PackedVector3Array()
	var kerb_n := PackedVector3Array()
	for entry_variant in [[-wall_face, WEST_RAM_Z, 1.0], [wall_face, EAST_RAM_Z, -1.0]]:
		var entry: Array = entry_variant
		var wx := float(entry[0])
		var wz := float(entry[1])
		var s := float(entry[2])
		var near := wx + s * RAM_DEPTH
		# Four chevrons across the stroke, pointing the way the ram travels.
		for i in range(4):
			var z := wz - RAM_LENGTH * 0.5 + RAM_LENGTH * (float(i) + 0.5) / 4.0
			var tip := near + s * (RAM_STROKE - 0.06)
			var back := near + s * 0.12
			_mark_triangle(chevrons, chev_n, Vector2(back, z - 0.30),
				Vector2(back, z + 0.30), Vector2(tip, z))
		# The kerb: the line to be the far side of.
		var kx := near + s * (RAM_STROKE + 0.12)
		_mark_line(kerbs, kerb_n, Vector2(kx, wz - RAM_LENGTH * 0.5 - 0.4),
			Vector2(kx, wz + RAM_LENGTH * 0.5 + 0.4), 0.1)
	var mark := _add_marking("RamChevrons", _mesh_from(chevrons, chev_n), COL_CHEVRON, 0.25)
	var chevron_mat := mark.material_override as StandardMaterial3D
	for ram_variant in _rams:
		var ram: Dictionary = ram_variant
		ram["chevron_mat"] = chevron_mat
	_add_marking("Kerbs", _mesh_from(kerbs, kerb_n), COL_KERB, 0.0)


# ---------------------------------------------------------------------------
# Seeded timeline
# ---------------------------------------------------------------------------
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	# TWO draws per ram, west then east: cycle length, then phase.
	var lo := int(round(CYCLE_MIN_S * FightTypes.TICK_HZ))
	var hi := int(round(CYCLE_MAX_S * FightTypes.TICK_HZ))
	for i in range(_rams.size()):
		var ram: Dictionary = _rams[i]
		if rng == null:
			ram["cycle"] = lo + i * 60
			ram["phase"] = 0
		else:
			ram["cycle"] = rng.randi_range(lo, hi)
			ram["phase"] = rng.randi_range(0, int(ram["cycle"]) - 1)
		ram["state"] = STATE_IDLE
		ram["state_ticks"] = 0
		ram["extension"] = 0.0
		_set_ram(ram, 0.0)
	_set_lamps(false)


# ---------------------------------------------------------------------------
# Hazard tick
# ---------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	var press := int(round(PRESS_S * FightTypes.TICK_HZ))
	var hold := int(round(HOLD_S * FightTypes.TICK_HZ))
	var retract := int(round(RETRACT_S * FightTypes.TICK_HZ))
	var warn := int(round(WARN_S * FightTypes.TICK_HZ))
	var any_warning := false
	for ram_variant in _rams:
		var ram: Dictionary = ram_variant
		var cycle: int = ram["cycle"]
		var t := (_ticks + int(ram["phase"])) % cycle
		match int(ram["state"]):
			STATE_IDLE:
				any_warning = any_warning or (cycle - t) <= warn
				if t == 0:
					ram["state"] = STATE_PRESS
					ram["state_ticks"] = 0
					emit_signal("hazard_fx", "ram", true, ram["centre"])
			STATE_PRESS:
				any_warning = true
				ram["state_ticks"] = int(ram["state_ticks"]) + 1
				_set_ram(ram, clampf(float(ram["state_ticks"]) / float(press), 0.0, 1.0))
				if int(ram["state_ticks"]) >= press:
					ram["state"] = STATE_HOLD
					ram["state_ticks"] = 0
			STATE_HOLD:
				any_warning = true
				ram["state_ticks"] = int(ram["state_ticks"]) + 1
				if int(ram["state_ticks"]) >= hold:
					ram["state"] = STATE_RETRACT
					ram["state_ticks"] = 0
			STATE_RETRACT:
				ram["state_ticks"] = int(ram["state_ticks"]) + 1
				_set_ram(ram, clampf(1.0 - float(ram["state_ticks"]) / float(retract), 0.0, 1.0))
				if int(ram["state_ticks"]) >= retract:
					ram["state"] = STATE_IDLE
					ram["state_ticks"] = 0
					_set_ram(ram, 0.0)
					emit_signal("hazard_fx", "ram", false, ram["centre"])
		# Pinned and flattened: the impulse through whichever part is in the stroke, and
		# the top-face bite on the chassis, which is what "flattened" means to the damage
		# model (bot.gd take_direct_damage maps a chassis hit to armour_top).
		var area := ram["area"] as Area3D
		var pressing := float(ram["extension"]) > 0.4
		if area.monitoring != pressing:
			area.monitoring = pressing
		if pressing and _ticks % CRUSH_PERIOD_TICKS == 0:
			_damage_overlaps(area, CRUSH_IMPULSE)
			_crush_bots_in_area(area, CRUSH_TOP_AMOUNT)
	_set_lamps(any_warning)
	_ticks += 1


func _set_ram(ram: Dictionary, amount: float) -> void:
	ram["extension"] = amount
	var body := ram["body"] as AnimatableBody3D
	if is_instance_valid(body):
		body.position.x = float(ram["rest_x"]) + float(ram["sign"]) * RAM_STROKE * amount


func _set_lamps(lit: bool) -> void:
	for ram_variant in _rams:
		var ram: Dictionary = ram_variant
		var mat := ram["lamp_mat"] as StandardMaterial3D
		if mat != null:
			# 5 Hz flash while a press is coming or running.
			var on := lit and (_ticks / 6) % 2 == 0
			mat.emission_energy_multiplier = 5.0 if on else 0.35
		var chevron := ram["chevron_mat"] as StandardMaterial3D
		if chevron != null:
			chevron.emission_energy_multiplier = 2.6 if lit else 0.25


## brief v4 §2: at the endgame the rams cycle at half the period. The stroke itself
## (press, hold, retract) is unchanged, so what shortens is the idle between presses: a
## 12 s ram becomes a 6 s one and the floor is never still for long.
func _on_phase(_phase_name: String) -> void:
	# The shortest a cycle may be: the whole stroke plus a second of idle to read it.
	var floor_ticks := int(round((PRESS_S + HOLD_S + RETRACT_S + 1.0) * FightTypes.TICK_HZ))
	for ram_variant in _rams:
		var ram: Dictionary = ram_variant
		var cycle := maxi(floor_ticks, int(round(float(ram["cycle"]) / ArenaBase.ENDGAME_RATE)))
		ram["cycle"] = cycle
		ram["phase"] = int(ram["phase"]) % cycle


## The two rams' cycle lengths in ticks, west then east. arenas_test reads them.
func ram_cycles() -> Array[int]:
	var out: Array[int] = []
	for ram_variant in _rams:
		out.append(int((ram_variant as Dictionary)["cycle"]))
	return out


func rams_extended() -> float:
	var most := 0.0
	for ram_variant in _rams:
		most = maxf(most, float((ram_variant as Dictionary)["extension"]))
	return most


func ram_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for ram_variant in _rams:
		out.append((ram_variant as Dictionary)["centre"])
	return out


# ---------------------------------------------------------------------------
# Wave A: the warning layer's read. READ-ONLY, from the same clock the rams run on.
# ---------------------------------------------------------------------------
func _schedule_extra(out: Array) -> void:
	for i in range(_rams.size()):
		var ram: Dictionary = _rams[i]
		var state := int(ram["state"])
		var active := state == STATE_PRESS or state == STATE_HOLD
		var in_s := 0.0
		if state == STATE_IDLE:
			var cycle: int = ram["cycle"]
			var t := (_ticks + int(ram["phase"])) % cycle
			in_s = float((cycle - t) % cycle) / float(FightTypes.TICK_HZ)
		elif state == STATE_RETRACT:
			in_s = ArenaBase.NEVER_S
		var id := "ram_west" if float(ram["sign"]) > 0.0 else "ram_east"
		var body := ram["body"] as Node3D
		var e := _schedule_entry(id, "ram", id, ram["centre"],
			Vector2(RAM_STROKE + 0.1, RAM_LENGTH), "rect", in_s, active,
			[ram["lamp_mat"]], WARN_S)
		e["sound_at"] = body.position if is_instance_valid(body) else ram["centre"]
		out.append(e)


# ---------------------------------------------------------------------------
# The AI's read
# ---------------------------------------------------------------------------
func hazard_helpers() -> Dictionary:
	var soonest := 999.0
	for ram_variant in _rams:
		var ram: Dictionary = ram_variant
		if int(ram["state"]) != STATE_IDLE:
			soonest = 0.0
			continue
		var cycle: int = ram["cycle"]
		var t := (_ticks + int(ram["phase"])) % cycle
		soonest = minf(soonest, float(cycle - t) / float(FightTypes.TICK_HZ))
	return {
		"next_danger_in_s": soonest,
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
	}


## The stroke centres are ALWAYS dangerous ground here: a ram that is not moving now will
## be in at most 14 seconds, and there is nowhere useful to stand inside one.
func _danger_positions() -> Array[Vector3]:
	return ram_centres()


## The diagonal corridor the rams leave: clear of both strokes at every phase.
func _safe_positions() -> Array[Vector3]:
	return [
		Vector3(-1.4, 0.0, 3.0),
		Vector3(1.4, 0.0, -3.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(-3.0, 0.0, 3.2),
		Vector3(3.0, 0.0, -3.2),
	]


func spikes_risen() -> bool:
	return false


func seconds_to_spike_rise() -> float:
	return 999.0
