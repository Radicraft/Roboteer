extends "res://arena/events/event_arena_base.gd"
## THE TABLE (side event 3, docs/stage6-spec.md §1, brief §10 "Pinball").
##
## A 10 x 14 m table played the long way, with the machine as the ball. Six bumpers that
## KICK, a ramp on the west flank, and two drop targets. No hazards and no opponent: the
## only thing that can go wrong is running out of clock, so this is the event that teaches
## a player their drive rather than their armour.
##
##   FLOOR PLAN (10 x 14 m, north is -Z, play up the table)
##
##      -5      -3.3     0      +3.3    +5
##   -7 +-------------------------------------+
##      |          (B)         (B)            |   (B) bumper, post r = 0.35,
##      |               (B)                   |       kick ring r = 0.60
##   -4 |                                     |
##      |      [T]              [T]           |   [T] drop target, 5 s reset
##   -2 |                                     |
##      | (B)                          (B)    |
##    0 | /|                                  |
##      |/ |          (B)                     |   /  the RAMP, rising 0.5 m
##   +2 |  |                                  |      to a gate at its head
##      |  |                                  |
##   +4 | \|                                  |
##      |                                     |
##   +6 | x           P                       |   P player mark (0, 0, +5.6)
##   +7 +-------------------------------------+   x parking bay for the spare machine
##
## The bumpers are laid out as three ranks, not a pattern: a three bumper bank at the head
## of the table where a fast run ends up, a pair on the flanks at the waist that a bot
## bounces between, and one lone bumper on the centre line that is in the way of every
## straight line anyone will try to drive. No bumper is within 1.4 m of another, so a kick
## always throws you clear rather than wedging you in a nest.
##
## SCORING is the rules' business (`fight/events/pinball.gd`): the table only reports what
## was hit, because a table that also counted would be two places to change a number.
##
## Marking scheme (original, brief §3): the table is painted as a SCOREBOARD. A lit
## scoring ring under each bumper; the ramp lane hatched and arrowed toward its gate; a
## boxed bay under each drop target; and a plunger arrow at the player's mark. Nothing on
## this floor is a warning, which is the point: it is the one arena with no danger in it.

const LENGTH_X := 10.0
const LENGTH_Z := 14.0

const BUMPER_R := 0.35
const BUMPER_H := 0.50
const BUMPER_RING := 0.60
## 180 N s into a 100 kg machine is about 1.8 m/s, which is half the drive's top speed:
## enough that a bumper THROWS you and not so much that the table plays itself.
const BUMPER_KICK := 180.0
const BUMPER_COOLDOWN_TICKS := 18
const BUMPERS := [
	Vector3(-2.2, 0.0, -4.6), Vector3(0.0, 0.0, -5.6), Vector3(2.2, 0.0, -4.6),
	Vector3(-3.3, 0.0, -0.9), Vector3(3.3, 0.0, -0.9),
	Vector3(0.0, 0.0, 1.8),
]

const RAMP_X := -4.0
const RAMP_W := 1.6
const RAMP_RUN := 3.05
const RAMP_RISE := 0.5
const RAMP_MID_Z := 2.7
const RAMP_GATE_Z := 1.25
const RAMP_REARM_TICKS := 72          # 1.2 s, so one pass is one crossing

const TARGETS := [Vector3(-1.5, 0.0, -2.6), Vector3(1.5, 0.0, -2.6)]
const TARGET_SIZE := Vector3(0.70, 0.50, 0.16)
const TARGET_UP_Y := 0.25
const TARGET_DOWN_Y := -0.45
const TARGET_RESET_S := 5.0

const PLAYER_MARK := Vector3(0.0, 0.25, 5.6)
const PEN_MARK := Vector3(-4.2, 0.25, 6.2)

const TINT_FLOOR := Color(0.80, 0.84, 0.98)
const TINT_WALL := Color(2.30, 2.36, 2.70)
const COL_RING := Color(0.26, 0.78, 0.95)
const COL_LANE := Color(0.95, 0.56, 0.14)
const COL_BAY := Color(0.86, 0.32, 0.62)

## Emitted the tick a bumper is struck, after the kick. `index` is into BUMPERS.
signal bumper_hit(index: int, position: Vector3)
## Emitted the tick the head of the ramp is crossed.
signal ramp_crossed()
## Emitted the tick a target goes down, and again when it comes back up.
signal target_dropped(index: int)
signal target_reset(index: int)

var _bumpers: Array = []
var _targets: Array = []
var _ramp_gate: Area3D = null
var _ramp_ready_tick := 0


func arena_id() -> String:
	return "pinball"


func _configure() -> void:
	_set_rect(Vector2(LENGTH_X, LENGTH_Z))
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = false
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_STEEL
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.48
	_floor_friction = 0.55            # a shade slick: the table wants the machine sliding
	_ambient_tint = Color(0.88, 0.93, 1.12)
	_key_colour = Color(0.94, 0.96, 1.0)
	_key_energy = 0.52
	_fill_colour = Color(0.62, 0.78, 1.0)
	_fill_energy = 0.18
	_bg_tint = Color(0.72, 0.80, 1.05)
	_spawn_marks = [PLAYER_MARK, PEN_MARK]
	_spawn_dirs = [Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0)]


# --------------------------------------------------------------------------------------
# Furniture
# --------------------------------------------------------------------------------------
func _build_hazards() -> void:
	for i in range(BUMPERS.size()):
		_bumpers.append(_add_bumper(BUMPERS[i], i))
	_build_ramp()
	for i in range(TARGETS.size()):
		_targets.append(_add_target(TARGETS[i], i))


## A bumper is a kinematic post with a ring of Area3D round it. Kinematic rather than
## static so it can be animated later without changing what it is, and a post rather than
## a pure sensor so that driving into one STOPS you: the kick has something to kick from.
func _add_bumper(centre: Vector3, index: int) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.name = "Bumper%d" % index
	body.sync_to_physics = false
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.position = Vector3(centre.x, BUMPER_H * 0.5, centre.z)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BUMPER_R
	cyl.height = BUMPER_H
	shape.shape = cyl
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = BUMPER_R * 0.82
	mesh.bottom_radius = BUMPER_R
	mesh.height = BUMPER_H
	mesh.radial_segments = 20
	mi.mesh = mesh
	mi.material_override = _lamp(COL_RING, 0.6)
	body.add_child(mi)
	add_child(body)

	var area := _make_hazard_area("Kick",
		_cylinder_shape(BUMPER_RING, 0.7, Vector3(0.0, 0.35, 0.0)), body)
	area.monitoring = true
	# The kick ring sits ON the post, so the shape offset is relative to the post's own
	# centre height; drop it back to the floor.
	(area.get_child(0) as CollisionShape3D).position.y = 0.35 - BUMPER_H * 0.5
	return {"body": body, "area": area, "mesh": mi, "centre": Vector3(centre.x, 0.0, centre.z),
		"index": index, "ready_tick": 0, "lit": false}


func _build_ramp() -> void:
	var angle := atan(RAMP_RISE / RAMP_RUN)
	var body := StaticBody3D.new()
	body.name = "Ramp"
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85               # grip on the climb, or nothing ever gets up it
	pm.bounce = 0.0
	body.physics_material_override = pm
	# Rotating about +X sends local +Z down, so the ramp rises toward -Z, up the table.
	# The foot is set flush with the floor: 0.12 is the slab's half thickness projected
	# onto the tilted normal, and 0.2506 is half the run's rise.
	body.rotation = Vector3(angle, 0.0, 0.0)
	body.position = Vector3(RAMP_X, 0.132, RAMP_MID_Z)
	var size := Vector3(RAMP_W, 0.24, RAMP_RUN)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(size)
	mi.material_override = _textured(MAT_STEEL, Color(1.7, 1.72, 1.85), 0.5, Color(0.52, 0.53, 0.58))
	body.add_child(mi)
	add_child(body)

	_ramp_gate = Area3D.new()
	_ramp_gate.name = "RampGate"
	_ramp_gate.collision_layer = FightTypes.LAYER_HAZARD
	_ramp_gate.collision_mask = FightTypes.LAYER_BOT
	_ramp_gate.monitoring = true
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(RAMP_W, 1.0, 0.45)
	gate_shape.shape = gate_box
	gate_shape.position = Vector3(RAMP_X, RAMP_RISE + 0.35, RAMP_GATE_Z)
	_ramp_gate.add_child(gate_shape)
	add_child(_ramp_gate)


func _add_target(centre: Vector3, index: int) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.name = "Target%d" % index
	body.sync_to_physics = false
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.position = Vector3(centre.x, TARGET_UP_Y, centre.z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = TARGET_SIZE
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(TARGET_SIZE)
	mi.material_override = _lamp(COL_BAY, 1.4)
	body.add_child(mi)
	add_child(body)

	var holder := Node3D.new()
	holder.name = "Target%dZone" % index
	holder.position = Vector3(centre.x, 0.0, centre.z)
	add_child(holder)
	var area := _make_hazard_area("Hit",
		_box_shape(Vector3(TARGET_SIZE.x + 0.28, 0.6, TARGET_SIZE.z + 0.34),
			Vector3(0.0, 0.3, 0.0)), holder)
	area.monitoring = true
	return {"body": body, "area": area, "mesh": mi, "index": index, "down": false,
		"reset_tick": 0, "centre": Vector3(centre.x, 0.0, centre.z)}


# --------------------------------------------------------------------------------------
# Markings
# --------------------------------------------------------------------------------------
func _build_markings() -> void:
	var rings := PackedVector3Array()
	var rings_n := PackedVector3Array()
	for centre in BUMPERS:
		_mark_ring(rings, rings_n, Vector2(centre.x, centre.z), BUMPER_RING, 0.09, 32)
		_mark_ring(rings, rings_n, Vector2(centre.x, centre.z), BUMPER_RING + 0.22, 0.04, 32)
	_add_marking("ScoreRings", _mesh_from(rings, rings_n), COL_RING, 1.6)

	var lane := PackedVector3Array()
	var lane_n := PackedVector3Array()
	for i in range(7):
		var z := RAMP_MID_Z + 1.5 - float(i) * 0.5
		_mark_line(lane, lane_n, Vector2(RAMP_X - RAMP_W * 0.5, z),
			Vector2(RAMP_X + RAMP_W * 0.5, z - 0.32), 0.08)
	# The head of the ramp, and the plunger arrow at the player's mark.
	_mark_triangle(lane, lane_n, Vector2(RAMP_X - 0.45, RAMP_GATE_Z + 0.5),
		Vector2(RAMP_X + 0.45, RAMP_GATE_Z + 0.5), Vector2(RAMP_X, RAMP_GATE_Z - 0.2))
	_mark_triangle(lane, lane_n, Vector2(PLAYER_MARK.x - 0.5, PLAYER_MARK.z + 0.45),
		Vector2(PLAYER_MARK.x + 0.5, PLAYER_MARK.z + 0.45), Vector2(PLAYER_MARK.x, PLAYER_MARK.z - 0.5))
	_add_marking("Lanes", _mesh_from(lane, lane_n), COL_LANE, 1.2)

	var bays := PackedVector3Array()
	var bays_n := PackedVector3Array()
	for centre in TARGETS:
		var c := Vector2(centre.x, centre.z)
		_mark_line(bays, bays_n, c + Vector2(-0.6, -0.4), c + Vector2(0.6, -0.4), 0.07)
		_mark_line(bays, bays_n, c + Vector2(-0.6, 0.4), c + Vector2(0.6, 0.4), 0.07)
		_mark_line(bays, bays_n, c + Vector2(-0.6, -0.4), c + Vector2(-0.6, 0.4), 0.07)
		_mark_line(bays, bays_n, c + Vector2(0.6, -0.4), c + Vector2(0.6, 0.4), 0.07)
	_add_marking("TargetBays", _mesh_from(bays, bays_n), COL_BAY, 1.0)


# --------------------------------------------------------------------------------------
# The tick. Nothing here is seeded: a table with a random element is a table you cannot
# learn, and the event is a skill run. `_seed_hazards` still draws nothing, which is a
# fixed count of draws and therefore still deterministic.
# --------------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	for b in _bumpers:
		_tick_bumper(b)
	_tick_ramp()
	for t in _targets:
		_tick_target(t)
	_ticks += 1


func _tick_bumper(bumper: Dictionary) -> void:
	var area := bumper["area"] as Area3D
	var lit := false
	if _ticks >= int(bumper["ready_tick"]):
		var centre: Vector3 = bumper["centre"]
		var struck := false
		for bot in _bots_in_area(area):
			struck = true
			var chassis: Variant = bot.get("chassis")
			if chassis is RigidBody3D:
				var at: Vector3 = (chassis as RigidBody3D).global_position
				var away := Vector3(at.x - centre.x, 0.0, at.z - centre.z)
				if away.length() < 0.0001:
					away = Vector3.FORWARD
				(chassis as RigidBody3D).apply_central_impulse(away.normalized() * BUMPER_KICK)
		if struck:
			bumper["ready_tick"] = _ticks + BUMPER_COOLDOWN_TICKS
			lit = true
			emit_signal("hazard_fx", "bumper", true, centre)
			emit_signal("bumper_hit", int(bumper["index"]), centre)
	if bool(bumper["lit"]) and not lit and _ticks >= int(bumper["ready_tick"]):
		bumper["lit"] = false
		emit_signal("hazard_fx", "bumper", false, bumper["centre"])
	elif lit:
		bumper["lit"] = true
	var mesh := bumper["mesh"] as MeshInstance3D
	if is_instance_valid(mesh):
		var mat := mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 3.4 if bool(bumper["lit"]) else 0.6


func _tick_ramp() -> void:
	if _ramp_gate == null or _ticks < _ramp_ready_tick:
		return
	if _area_has_part(_ramp_gate):
		_ramp_ready_tick = _ticks + RAMP_REARM_TICKS
		emit_signal("hazard_fx", "ramp", true, Vector3(RAMP_X, RAMP_RISE, RAMP_GATE_Z))
		emit_signal("ramp_crossed")


func _tick_target(target: Dictionary) -> void:
	var body := target["body"] as AnimatableBody3D
	var area := target["area"] as Area3D
	if bool(target["down"]):
		if _ticks >= int(target["reset_tick"]):
			target["down"] = false
			body.position.y = TARGET_UP_Y
			area.monitoring = true
			emit_signal("target_reset", int(target["index"]))
		return
	if _area_has_part(area):
		target["down"] = true
		target["reset_tick"] = _ticks + int(round(TARGET_RESET_S * FightTypes.TICK_HZ))
		body.position.y = TARGET_DOWN_Y
		area.monitoring = false
		emit_signal("hazard_fx", "target", true, target["centre"])
		emit_signal("target_dropped", int(target["index"]))


# --------------------------------------------------------------------------------------
# The contract the Pinball rules read
# --------------------------------------------------------------------------------------
func bumper_count() -> int:
	return _bumpers.size()


func target_count() -> int:
	return _targets.size()


func targets_down() -> int:
	var n := 0
	for t in _targets:
		if bool(t["down"]):
			n += 1
	return n


func hazard_helpers() -> Dictionary:
	var safe: Array[Vector3] = [Vector3(0.0, 0.0, 4.0), Vector3(-2.0, 0.0, -2.4),
		Vector3(2.0, 0.0, -2.4)]
	return {
		"next_danger_in_s": 999.0,
		"danger_positions": [] as Array[Vector3],
		"safe_positions": safe,
	}
