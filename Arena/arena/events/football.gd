extends "res://arena/events/event_arena_base.gd"
## THE PITCH (side event 4, docs/stage6-spec.md §1, brief §10 "Football").
##
## A 12 x 8 m pitch, a half metre ball at three kilos, a goal cut into each end wall and
## one AI machine that wants the same ball you do. Ninety seconds, most goals wins.
##
##   FLOOR PLAN (12 x 8 m, north is -Z)
##
##      -6    -4.5      -2.6    0    +2.6      +4.5   +6
##   -4 +--------------------------------------------------+
##      |     |                 :                 |        |
##      | =GOAL=          .- - - - -.        =GOAL=        |   the goals are 3.0 m
##   -1.5 ###|      P     |    o    |     O      |###      |   mouths in the end
##      | W |              `- - - - '              | E |    |   walls, with a post
##   +1.5 ###|                 :                 |###      |   at each side
##      |     |                 :                 |        |
##   +4 +--------------------------------------------------+
##        goal box        centre circle        goal box
##      P player mark (-2.6, 0, 0), attacks the EAST goal
##      O other  mark (+2.6, 0, 0), attacks the WEST goal
##      o the ball, on the centre spot
##
## The end walls are CLOSED and the goal is an `Area3D` standing in front of each one, so
## the ball can never leave the pitch: a ball that has gone out of play is a rule nobody
## wants to referee with a robot. A post at each side of the mouth funnels a shot in and
## gives a defender something to sit between.
##
## Marking scheme (original, brief §3): chalk on plate. A halfway line and a centre spot,
## a 2.4 m centre circle, a boxed goal area at each end with a lit mouth, a corner tick in
## each corner, and a bay mark under each machine's start position. The lit goal mouths
## are the only emissive marks, because the goal is the only thing on this floor that
## changes the score.

const LENGTH_X := 12.0
const LENGTH_Z := 8.0

const BALL_R := 0.25
const BALL_MASS := 3.0
const BALL_BOUNCE := 0.55
const BALL_FRICTION := 0.35
const BALL_SPAWN := Vector3(0.0, 0.45, 0.0)

const GOAL_HALF_Z := 1.5
const GOAL_DEPTH := 0.55
const GOAL_HEIGHT := 0.9
const POST_R := 0.10
## A goal cannot be scored again for this long, which is the window the rules use to put
## the ball back on the spot without the sensor counting the same ball twice.
const GOAL_LOCKOUT_TICKS := 30

const PLAYER_MARK := Vector3(-2.6, 0.25, 0.0)
const OTHER_MARK := Vector3(2.6, 0.25, 0.0)

const TINT_FLOOR := Color(0.72, 0.92, 0.76)
const TINT_WALL := Color(2.30, 2.34, 2.36)
const COL_CHALK := Color(0.92, 0.94, 0.92)
const COL_GOAL := Color(0.30, 0.86, 0.98)

## Emitted the tick the ball is wholly over a line. `team` is who scored: 0 is the player,
## whose goal is the EAST one.
signal goal_scored(team: int, at: Vector3)

var _ball: RigidBody3D = null
var _goals: Array = []              # [west sensor, east sensor]; index is the CONCEDING end
var _goal_lock_tick := 0


func arena_id() -> String:
	return "football"


func _configure() -> void:
	_set_rect(Vector2(LENGTH_X, LENGTH_Z))
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = false
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.12
	_floor_friction = 0.68
	_ambient_tint = Color(0.96, 1.02, 0.96)
	_key_colour = Color(1.0, 0.99, 0.95)
	_key_energy = 0.56
	_bg_tint = Color(0.80, 0.88, 0.84)
	_spawn_marks = [PLAYER_MARK, OTHER_MARK]
	_spawn_dirs = [Vector3.RIGHT, Vector3.LEFT]


func _build_hazards() -> void:
	_goals.append(_add_goal(-1, "GoalWest"))
	_goals.append(_add_goal(1, "GoalEast"))
	_build_ball()


## One goal: two posts and the sensor between them. `side` is -1 for the west end.
func _add_goal(side: int, goal_name: String) -> Area3D:
	var x := float(side) * (LENGTH_X * 0.5)
	for z_variant in [-GOAL_HALF_Z - POST_R, GOAL_HALF_Z + POST_R]:
		var z := float(z_variant)
		var post := StaticBody3D.new()
		post.name = "%sPost%s" % [goal_name, "N" if z < 0.0 else "S"]
		post.collision_layer = FightTypes.LAYER_ARENA
		post.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
		post.position = Vector3(x - float(side) * GOAL_DEPTH * 0.5, GOAL_HEIGHT * 0.5, z)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = POST_R
		cyl.height = GOAL_HEIGHT
		shape.shape = cyl
		post.add_child(shape)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var mesh := CylinderMesh.new()
		mesh.top_radius = POST_R
		mesh.bottom_radius = POST_R
		mesh.height = GOAL_HEIGHT
		mesh.radial_segments = 12
		mi.mesh = mesh
		mi.material_override = _lamp(COL_GOAL, 1.1)
		post.add_child(mi)
		add_child(post)

	# The sensor watches the BALL only (layer debris), never a machine: a bot parked in
	# its own mouth is a defender, not a goal.
	var area := Area3D.new()
	area.name = goal_name
	area.collision_layer = FightTypes.LAYER_HAZARD
	area.collision_mask = FightTypes.LAYER_DEBRIS
	area.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GOAL_DEPTH, GOAL_HEIGHT, GOAL_HALF_Z * 2.0)
	shape.shape = box
	shape.position = Vector3(x - float(side) * GOAL_DEPTH * 0.5, GOAL_HEIGHT * 0.5, 0.0)
	area.add_child(shape)
	add_child(area)
	return area


func _build_ball() -> void:
	var ball := RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = BALL_MASS
	# The ball is DEBRIS, not a bot and not arena furniture: `FightTypes.MASK_BOT` already
	# includes the debris layer, so every part of both machines collides with it for free,
	# and the out-of-arena sensor (bots only) ignores it.
	ball.collision_layer = FightTypes.LAYER_DEBRIS
	ball.collision_mask = FightTypes.MASK_DEBRIS
	ball.can_sleep = false
	# A 0.5 m ball kicked by a flipper crosses a 0.2 m wall in one tick without this.
	ball.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = BALL_BOUNCE
	pm.friction = BALL_FRICTION
	ball.physics_material_override = pm
	ball.position = BALL_SPAWN
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_R
	shape.shape = sphere
	ball.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := SphereMesh.new()
	mesh.radius = BALL_R
	mesh.height = BALL_R * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mi.mesh = mesh
	var mat := _flat(Color(0.95, 0.95, 0.96))
	mat.roughness = 0.55
	mi.material_override = mat
	ball.add_child(mi)
	add_child(ball)
	_ball = ball


# --------------------------------------------------------------------------------------
# Markings
# --------------------------------------------------------------------------------------
func _build_markings() -> void:
	var chalk := PackedVector3Array()
	var chalk_n := PackedVector3Array()
	var hx := LENGTH_X * 0.5
	var hz := LENGTH_Z * 0.5
	_mark_line(chalk, chalk_n, Vector2(0.0, -hz + 0.25), Vector2(0.0, hz - 0.25), 0.07)
	_mark_ring(chalk, chalk_n, Vector2.ZERO, 1.2, 0.07, 44)
	_mark_ring(chalk, chalk_n, Vector2.ZERO, 0.11, 0.22, 10)
	for side_variant in [-1.0, 1.0]:
		var side := float(side_variant)
		var box_x := side * (hx - 1.6)
		_mark_line(chalk, chalk_n, Vector2(box_x, -2.2), Vector2(box_x, 2.2), 0.07)
		_mark_line(chalk, chalk_n, Vector2(box_x, -2.2), Vector2(side * hx, -2.2), 0.07)
		_mark_line(chalk, chalk_n, Vector2(box_x, 2.2), Vector2(side * hx, 2.2), 0.07)
		# Corner ticks.
		for z_variant in [-hz + 0.3, hz - 0.3]:
			var z := float(z_variant)
			_mark_line(chalk, chalk_n, Vector2(side * (hx - 0.55), z), Vector2(side * (hx - 0.15), z), 0.07)
	for mark in [PLAYER_MARK, OTHER_MARK]:
		_mark_ring(chalk, chalk_n, Vector2(mark.x, mark.z), 0.55, 0.05, 24)
	_add_marking("Chalk", _mesh_from(chalk, chalk_n), COL_CHALK, 0.0)

	var mouths := PackedVector3Array()
	var mouths_n := PackedVector3Array()
	for side_variant in [-1.0, 1.0]:
		var side := float(side_variant)
		_mark_rect(mouths, mouths_n,
			Vector2(side * (LENGTH_X * 0.5 - GOAL_DEPTH * 0.5), 0.0),
			Vector2(GOAL_DEPTH, GOAL_HALF_Z * 2.0))
	_add_marking("GoalMouths", _mesh_from(mouths, mouths_n), COL_GOAL, 2.0)


# --------------------------------------------------------------------------------------
# The tick
# --------------------------------------------------------------------------------------
## Polled rather than signalled. `body_entered` fires whenever the engine gets round to it
## and a replay has to agree with its fight tick for tick, so the sensor is READ on the
## tick instead (docs/stage3-rules-notes.md: everything that can change the outcome
## happens inside the fixed step).
func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ball == null or not is_instance_valid(_ball) or _ticks < _goal_lock_tick:
		return
	for conceding in range(_goals.size()):
		var area := _goals[conceding] as Area3D
		if area == null or not area.monitoring:
			continue
		if not area.get_overlapping_bodies().has(_ball):
			continue
		# West goal conceded means the player (east-attacking, team 0) did NOT score.
		var scorer := 1 if conceding == 0 else 0
		_goal_lock_tick = _ticks + GOAL_LOCKOUT_TICKS
		emit_signal("hazard_fx", "goal", true, _ball.global_position)
		emit_signal("goal_scored", scorer, _ball.global_position)
		return


# --------------------------------------------------------------------------------------
# The contract the Football rules read
# --------------------------------------------------------------------------------------
func ball() -> RigidBody3D:
	return _ball


func ball_position() -> Vector3:
	return _ball.global_position if _ball != null and is_instance_valid(_ball) else BALL_SPAWN


## Put the ball back on the spot, dead. Called by the rules after a goal, and at kickoff.
func reset_ball() -> void:
	if _ball == null or not is_instance_valid(_ball):
		return
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = BALL_SPAWN
	_ball.force_update_transform()


## The goal this team is shooting AT. Team 0 attacks east.
func attack_goal(team_index: int) -> Vector3:
	var side := 1.0 if team_index == 0 else -1.0
	return Vector3(side * (LENGTH_X * 0.5 - GOAL_DEPTH * 0.5), 0.0, 0.0)


## The goal this team is defending.
func own_goal(team_index: int) -> Vector3:
	return attack_goal(1 - team_index)


func hazard_helpers() -> Dictionary:
	return {
		"next_danger_in_s": 999.0,
		"danger_positions": [] as Array[Vector3],
		"safe_positions": [Vector3.ZERO] as Array[Vector3],
	}
