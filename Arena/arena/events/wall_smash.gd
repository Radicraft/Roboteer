extends "res://arena/events/event_arena_base.gd"
## THE DEMOLITION RUN (side event 5, docs/stage6-spec.md §1, brief §10 "Wall Smash").
##
## A 20 x 6 m corridor with five breakable walls across it. Nothing else: no hazards, no
## opponent, no chaser. It is the one event that is purely about what the BUILD can do,
## which is why it is the one that most wants a heavy ram and a straight line.
##
##   FLOOR PLAN (20 x 6 m, north is -Z, drive +X)
##
##    -10    -8.6      -5.0    -2.0    +1.0    +4.0    +7.0        +9.2  +10
##     +-----------------------------------------------------------------+
##   -3|  1  |         |###|   |###|   |###|   |###|   |###|      |||||||| 
##     |  P  >         |###|   |###|   |###|   |###|   |###|      ||FIN|||
##    0|  .  >         |###|   |###|   |###|   |###|   |###|      ||||||||
##     |     >         |###|   |###|   |###|   |###|   |###|      ||||||||
##   +3|     |         |###|   |###|   |###|   |###|   |###|      ||||||||
##     +-----------------------------------------------------------------+
##          run-up        1       2       3       4       5        finish bar
##
## Each wall is six bricks: three across the corridor, two courses high, every one a
## `RigidBody3D` welded to the wall's own anchor by a locked `Generic6DOFJoint3D` that
## fails under a hit. That is the armour plate's mechanism (`Bot.weld` plus
## `BotPart._integrate_forces`) with a wall for a chassis, so a brick behaves like a plate:
## it holds rigid, it pops off under a real blow, and it is loose debris afterwards. What
## counts as a blow is `brick.gd`'s business and the measurement behind it is in that file.
##
## A wall COUNTS as broken when one COLUMN is clear, top course and bottom, because that is
## the hole you can actually drive through: the top course stands 0.35 m off the floor and
## a machine is taller than that, so a missing bottom brick on its own is a trip, not a
## door. When a bottom brick goes the brick resting on it is carrying nothing and goes with
## it, which is both what a wall does and what makes one good ram into one clear column.
##
## The RUN-UP matters and is deliberate: 3.6 m from the mark to the first wall is about
## what a 4wd build needs to reach top speed, so the first wall measures your drive and the
## rest measure whether you can line up again after a hit.
##
## Marking scheme (original, brief §3): a works floor again, but counting DOWN. A numbered
## bay bar in front of each wall, one to five; a centre lane line running the whole
## corridor, which is the line a good run never leaves; a kerb each side; and the finish
## bar at the east end lit green. No warning yellow anywhere: nothing in this arena is
## trying to hurt you.

const BrickScript := preload("res://arena/events/brick.gd")

const LENGTH := 20.0
const WIDTH := 6.0

const WALL_X := [-5.0, -2.0, 1.0, 4.0, 7.0]
const BRICK_COLUMNS := 3
const BRICK_ROWS := 2
const BRICK_SIZE := Vector3(0.30, 0.34, 1.94)     # depth x, height y, width z
const BRICK_GAP := 0.03
const BRICK_MASS := 4.0
## Newton seconds of ARRIVING MOMENTUM (see `brick.gd`): the closing speed along the
## contact normal times the mass of the machine behind it. MEASURED with the Stage 3
## fixture wedge (58 kg of physics mass) over the 3.6 m run-up: the ram arrives at between
## 73 and 122 N s depending on how square the nose is when it lands, and the SAME machine
## stalled against the wall at full throttle arrives at nothing at all, because a stalled
## machine has no closing speed. 60 is under the weakest ram measured and nowhere near a
## shove, which is the separation the event needs: bring weight and bring it up to speed,
## but do not lose the run because the nose was two degrees off.
## `tests/events_test.gd` prints the peak it saw, so a retune is one number and one run.
const BRICK_BREAK_IMPULSE := 60.0

const START_MARK := Vector3(-8.6, 0.25, 0.0)
const PEN_MARK := Vector3(9.4, 0.25, 2.2)
const FINISH_X := 9.2

const TINT_FLOOR := Color(0.86, 0.87, 0.90)
const TINT_WALL := Color(2.28, 2.28, 2.32)
const COL_LANE := Color(0.30, 0.31, 0.34)
const COL_BAY := Color(0.62, 0.66, 0.74)
const COL_FINISH := Color(0.30, 0.86, 0.52)
const COL_BRICK := Color(0.52, 0.34, 0.28)

## Emitted the tick a wall reaches BRICKS_TO_BREAK loose bricks.
signal wall_broken(index: int, at: Vector3)
## Emitted the tick one brick comes out, for the FX and the sound.
signal brick_freed(wall_index: int, at: Vector3)

var _walls: Array = []


func arena_id() -> String:
	return "wall_smash"


func _configure() -> void:
	_set_rect(Vector2(LENGTH, WIDTH))
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = false
	_floor_mat = MAT_CONCRETE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.10
	_floor_friction = 0.74               # grip: the run-up is the event
	_ambient_tint = Color(0.99, 0.98, 0.97)
	_key_colour = Color(1.0, 0.98, 0.94)
	_key_energy = 0.55
	_bg_tint = Color(0.84, 0.85, 0.90)
	_spawn_marks = [START_MARK, PEN_MARK]
	_spawn_dirs = [Vector3.RIGHT, Vector3.LEFT]


# --------------------------------------------------------------------------------------
# The walls
# --------------------------------------------------------------------------------------
func _build_hazards() -> void:
	for i in range(WALL_X.size()):
		_walls.append(_add_brick_wall(float(WALL_X[i]), i))


func _add_brick_wall(x: float, index: int) -> Dictionary:
	# One anchor per wall, with no collision shape of its own: it is a fixing point, not an
	# obstacle. A shapeless StaticBody3D is a legal `node_a` for a joint and costs nothing.
	var anchor := StaticBody3D.new()
	anchor.name = "Wall%dAnchor" % (index + 1)
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	anchor.position = Vector3(x, 0.0, 0.0)
	add_child(anchor)

	var span := BRICK_SIZE.z + BRICK_GAP
	var z0 := -span * float(BRICK_COLUMNS - 1) * 0.5
	var bricks: Array = []
	var joints: Array = []
	var brick_mat := _textured(MAT_CONCRETE, Color(1.0, 0.86, 0.80), 0.7, COL_BRICK)
	brick_mat.metallic = 0.0
	for row in range(BRICK_ROWS):
		for col in range(BRICK_COLUMNS):
			var at := Vector3(x, BRICK_SIZE.y * (0.5 + float(row)) + 0.005,
				z0 + span * float(col))
			var brick := RigidBody3D.new()
			brick.set_script(BrickScript)
			brick.name = "Wall%dBrick%d%d" % [index + 1, row, col]
			brick.mass = BRICK_MASS
			# Debris, so both machines collide with it through `FightTypes.MASK_BOT` and the
			# out-of-arena sensor (bots only) never sees it. The layer does not change when
			# the brick comes loose: it was always debris, it was only held still.
			brick.collision_layer = FightTypes.LAYER_DEBRIS
			brick.collision_mask = FightTypes.MASK_DEBRIS
			brick.contact_monitor = true
			brick.max_contacts_reported = 12
			# Awake, always. A sleeping body runs no `_integrate_forces`, and the first hit
			# on a wall is the one that has to be measured, not the second.
			brick.can_sleep = false
			brick.position = at
			brick.set("break_impulse", BRICK_BREAK_IMPULSE)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = BRICK_SIZE
			shape.shape = box
			brick.add_child(shape)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = BotMeshes.flat_box_mesh(BRICK_SIZE)
			mi.material_override = brick_mat
			brick.add_child(mi)
			add_child(brick)
			bricks.append(brick)

			var joint := Generic6DOFJoint3D.new()
			joint.name = "Joint" + brick.name
			joint.position = at
			add_child(joint)
			joint.node_a = joint.get_path_to(anchor)
			joint.node_b = joint.get_path_to(brick)
			for axis in ["x", "y", "z"]:
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
				for p in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
						Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
						Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
						Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
					joint.call("set_param_" + axis, p, 0.0)
			joint.exclude_nodes_from_collision = true
			joints.append(joint)

	return {"index": index, "x": x, "anchor": anchor, "bricks": bricks, "joints": joints,
		"columns": PackedInt32Array([0, 0, 0]), "loose": 0, "broken": false}


# --------------------------------------------------------------------------------------
# Markings
# --------------------------------------------------------------------------------------
func _build_markings() -> void:
	var lane := PackedVector3Array()
	var lane_n := PackedVector3Array()
	_mark_line(lane, lane_n, Vector2(-LENGTH * 0.5 + 0.3, 0.0), Vector2(FINISH_X, 0.0), 0.05)
	for z in [-WIDTH * 0.5 + 0.22, WIDTH * 0.5 - 0.22]:
		_mark_line(lane, lane_n, Vector2(-LENGTH * 0.5 + 0.2, z), Vector2(FINISH_X, z), 0.09)
	_add_marking("Lane", _mesh_from(lane, lane_n), COL_LANE, 0.0)

	var bays := PackedVector3Array()
	var bays_n := PackedVector3Array()
	for i in range(WALL_X.size()):
		var x := float(WALL_X[i]) - 1.1
		_mark_line(bays, bays_n, Vector2(x, -WIDTH * 0.5 + 0.35), Vector2(x, WIDTH * 0.5 - 0.35), 0.08)
		for t in range(i + 1):
			var z := -1.2 + float(t) * 0.6
			_mark_line(bays, bays_n, Vector2(x - 0.36, z), Vector2(x - 0.36, z + 0.34), 0.12)
	_add_marking("BayBars", _mesh_from(bays, bays_n), COL_BAY, 0.0)

	var finish := PackedVector3Array()
	var finish_n := PackedVector3Array()
	_mark_line(finish, finish_n, Vector2(FINISH_X, -WIDTH * 0.5), Vector2(FINISH_X, WIDTH * 0.5), 0.14)
	for i in range(6):
		var x := FINISH_X + 0.2 + float(i) * 0.22
		_mark_line(finish, finish_n, Vector2(x, -WIDTH * 0.5 + 0.2), Vector2(x - 0.6, WIDTH * 0.5 - 0.2), 0.08)
	_add_marking("FinishBar", _mesh_from(finish, finish_n), COL_FINISH, 1.8)


# --------------------------------------------------------------------------------------
# The tick: pop the joints the bricks flagged inside the step
# --------------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	for wall_variant in _walls:
		var wall: Dictionary = wall_variant
		var bricks: Array = wall["bricks"]
		for i in range(bricks.size()):
			var brick: RigidBody3D = bricks[i]
			if not is_instance_valid(brick) or bool(brick.get("broken")):
				continue
			if bool(brick.get("pending_break")):
				_free_brick(wall, i)
		if not bool(wall["broken"]) and _column_clear(wall):
			wall["broken"] = true
			emit_signal("wall_broken", int(wall["index"]), Vector3(float(wall["x"]), 0.35, 0.0))
			emit_signal("hazard_fx", "wall_down", true, Vector3(float(wall["x"]), 0.35, 0.0))
	_ticks += 1


## Pop one brick's joint and let it go. A brick in the BOTTOM course takes the one resting
## on it with it: that course was only ever held up by the joint and by the brick below,
## and a wall that leaves a single slab hovering at chest height after the bottom is gone
## looks like a bug even though it is what a locked joint does.
func _free_brick(wall: Dictionary, slot: int) -> void:
	var bricks: Array = wall["bricks"]
	var joints: Array = wall["joints"]
	if slot < 0 or slot >= bricks.size():
		return
	var brick: RigidBody3D = bricks[slot]
	if not is_instance_valid(brick) or bool(brick.get("broken")):
		return
	brick.set("broken", true)
	brick.set("pending_break", false)
	var joint: Node = joints[slot]
	if joint != null and is_instance_valid(joint):
		joint.queue_free()
	var columns: PackedInt32Array = wall["columns"]
	var col := slot % BRICK_COLUMNS
	columns[col] = columns[col] + 1
	wall["columns"] = columns
	wall["loose"] = int(wall["loose"]) + 1
	PartVisuals.tint_debris(brick)
	emit_signal("brick_freed", int(wall["index"]), brick.global_position)
	emit_signal("hazard_fx", "brick", true, brick.global_position)
	if slot < BRICK_COLUMNS:
		_free_brick(wall, slot + BRICK_COLUMNS)


func _column_clear(wall: Dictionary) -> bool:
	for n in (wall["columns"] as PackedInt32Array):
		if n >= BRICK_ROWS:
			return true
	return false


# --------------------------------------------------------------------------------------
# The contract the Wall Smash rules read
# --------------------------------------------------------------------------------------
func wall_count() -> int:
	return _walls.size()


func walls_broken() -> int:
	var n := 0
	for wall_variant in _walls:
		if bool((wall_variant as Dictionary)["broken"]):
			n += 1
	return n


func loose_bricks(index: int) -> int:
	if index < 0 or index >= _walls.size():
		return 0
	return int((_walls[index] as Dictionary)["loose"])


## The largest arriving momentum any brick of this wall has been hit with. The test prints
## it so "the wall did not break" can be told apart from "the wall was not hit".
func peak_impulse(index: int) -> float:
	if index < 0 or index >= _walls.size():
		return 0.0
	var best := 0.0
	for brick_variant in ((_walls[index] as Dictionary)["bricks"] as Array):
		var brick: RigidBody3D = brick_variant
		if is_instance_valid(brick):
			best = maxf(best, float(brick.get("peak_impulse")))
	return best


func wall_position(index: int) -> Vector3:
	if index < 0 or index >= _walls.size():
		return Vector3.ZERO
	return Vector3(float((_walls[index] as Dictionary)["x"]), 0.0, 0.0)


func next_wall_position() -> Vector3:
	for i in range(_walls.size()):
		if not bool((_walls[i] as Dictionary)["broken"]):
			return wall_position(i)
	return Vector3(FINISH_X, 0.0, 0.0)


func hazard_helpers() -> Dictionary:
	return {
		"next_danger_in_s": 999.0,
		"danger_positions": [] as Array[Vector3],
		"safe_positions": [next_wall_position()] as Array[Vector3],
	}
