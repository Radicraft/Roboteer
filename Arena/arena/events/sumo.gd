extends "res://arena/events/event_arena_base.gd"
## THE RING (side event 1, docs/stage6-spec.md §1, brief §10 "Sumo: push out of a ring").
##
## A 6 m circular platform standing 0.4 m proud of a 14 x 14 m apron, and NO WALLS. It is
## the only arena in the game with nothing to bounce off, which is the whole point: every
## other arena rewards pinning a machine against something, and this one punishes it.
##
##   FLOOR PLAN (14 x 14 m apron, platform r = 3.0, north is -Z)
##
##      -7            -3        0        +3            +7
##   -7 +---------------------------------------------------+
##      |                  . - - - - - .                    |   apron, 0.4 m BELOW
##      |              .                 .                  |   the platform, no walls
##      |            /     ___________     \                |
##    0 |           |  P  |  .  +  .  |  O  |               |   P player mark (-1.8, 0, 0)
##      |           |     |___________|     |               |   O other  mark (+1.8, 0, 0)
##      |            \                     /                |   +  centre cross
##      |              .                 .                  |   |__| start bars
##      |                  . - - - - - .                    |
##   +7 +---------------------------------------------------+
##
## The two marks are on the platform's east-west diameter, 3.6 m apart and 1.2 m in from
## the rim, so the layout is a 180 degree rotation of itself about the centre and neither
## machine starts nearer the edge. A bot is off when any part of it drops to the apron:
## that is the ring sensor below, a flat slab of Area3D lying just above the apron, which
## nothing standing on the platform can reach.
##
## Marking scheme (original, brief §3: no copied floor markings): one emissive AMBER RIM
## LINE just inside the edge, which is the only thing in this arena that can hurt you; a
## plain centre cross; a 1.8 m inner circle; two start bars at the marks; and sixteen
## radial ticks round the rim so a bot being spun on the spot reads as spinning. On the
## apron, a broken outer ring at r = 4.6 that says "this is not the floor you want".

const PLATFORM_R := 3.0
const PLATFORM_RISE := 0.4
const APRON := 14.0
## The sensor slab. Its top is 0.06 m below the apron-to-platform step, so a machine
## standing anywhere on the platform is clear of it and a machine on the apron is in it.
const RING_SENSOR_TOP := -0.06
const RING_SENSOR_DEPTH := 0.40
## A chassis centre this far out is off, whatever the sensor says. Belt and braces: the
## sensor catches a bot that has landed, this catches one still in the air over the apron.
const OFF_RADIUS := PLATFORM_R + 0.35

## Warm concrete and a cold apron, so the platform reads as the lit stage it is.
const TINT_FLOOR := Color(1.02, 1.0, 0.96)
const TINT_APRON := Color(0.62, 0.64, 0.70)
const COL_RIM := Color(0.95, 0.66, 0.12)
const COL_MARK := Color(0.24, 0.25, 0.28)
const COL_APRON_MARK := Color(0.40, 0.41, 0.45)

var _ring_sensor: Area3D = null


func arena_id() -> String:
	return "sumo"


func _configure() -> void:
	_set_rect(Vector2(APRON, APRON))
	_wall_height = 0.0                 # no walls: `_build_walls` below builds none
	_chevron_caps = false
	_grid_enabled = false
	_floor_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_floor_metallic = 0.10
	_floor_friction = 0.78             # grip, so a push is a push and not a skid
	_ambient_tint = Color(1.0, 0.99, 0.97)
	_key_colour = Color(1.0, 0.98, 0.93)
	_key_energy = 0.58
	_bg_tint = Color(0.72, 0.76, 0.86)
	_spawn_marks = [Vector3(-1.8, 0.25, 0.0), Vector3(1.8, 0.25, 0.0)]
	_spawn_dirs = [Vector3.RIGHT, Vector3.LEFT]


# --------------------------------------------------------------------------------------
# Floor: the apron, then the platform on top of it
# --------------------------------------------------------------------------------------
func _build_floor() -> void:
	var apron := _add_floor_slab("Apron", Vector2.ZERO, Vector2(APRON, APRON))
	apron.position.y -= PLATFORM_RISE
	var mesh := apron.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.material_override = _textured(MAT_PLATE, TINT_APRON, FLOOR_TILE, COL_FLOOR)
	_build_platform()


## The platform is its OWN static body standing 0.4 m proud of the apron, which is the
## shape the Stage 5 turntable trap asks for: a surface flush with the slab under it is
## coplanar with it and the solver rests the bot on the slab instead (see
## docs/stage5-arenas-notes.md trap 1). Here the step is the mechanic, so it is 0.4 m.
func _build_platform() -> void:
	var body := StaticBody3D.new()
	body.name = "Platform"
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = _floor_friction
	pm.bounce = 0.0
	body.physics_material_override = pm
	body.position = Vector3(0.0, -PLATFORM_RISE * 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = PLATFORM_R
	cyl.height = PLATFORM_RISE
	shape.shape = cyl
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = PLATFORM_R
	mesh.bottom_radius = PLATFORM_R
	mesh.height = PLATFORM_RISE
	mesh.radial_segments = 40
	mi.mesh = mesh
	mi.material_override = _floor_material()
	body.add_child(mi)
	add_child(body)


## No walls. The whole event is "there is nothing to stop you".
func _build_walls() -> void:
	pass


# --------------------------------------------------------------------------------------
# Markings
# --------------------------------------------------------------------------------------
func _build_markings() -> void:
	# The rim line, emissive, sitting just inside the edge. Lit rather than painted
	# because it is the losing line and has to read at the default camera framing.
	var rim := PackedVector3Array()
	var rim_n := PackedVector3Array()
	_mark_ring(rim, rim_n, Vector2.ZERO, PLATFORM_R - 0.13, 0.16, 56)
	_add_marking("RimLine", _mesh_from(rim, rim_n), COL_RIM, 2.2)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	# Sixteen radial ticks: the read for a machine being spun on the spot.
	for i in range(16):
		var a := TAU * float(i) / 16.0
		_mark_line(verts, norms, Vector2(cos(a), sin(a)) * (PLATFORM_R - 0.45),
			Vector2(cos(a), sin(a)) * (PLATFORM_R - 0.28), 0.055)
	_mark_ring(verts, norms, Vector2.ZERO, 0.9, 0.05, 40)
	_mark_line(verts, norms, Vector2(-0.55, 0.0), Vector2(0.55, 0.0), 0.07)
	_mark_line(verts, norms, Vector2(0.0, -0.55), Vector2(0.0, 0.55), 0.07)
	# Start bars, one across each mark, square to the push.
	for mark in _spawn_marks:
		_mark_line(verts, norms, Vector2(mark.x, mark.z - 0.45),
			Vector2(mark.x, mark.z + 0.45), 0.07)
	_add_marking("RingMarks", _mesh_from(verts, norms), COL_MARK, 0.0)

	# The apron's own warning: a broken ring outside the platform, on the lower level.
	var apron := PackedVector3Array()
	var apron_n := PackedVector3Array()
	for i in range(12):
		var a0 := TAU * float(i) / 12.0 + 0.08
		_mark_ring(apron, apron_n, Vector2.ZERO, 4.6, 0.12, 5, a0, a0 + 0.36)
	var mi := _add_marking("ApronWarning", _mesh_from(apron, apron_n), COL_APRON_MARK, 0.0)
	mi.position.y = -PLATFORM_RISE + MARK_Y


# --------------------------------------------------------------------------------------
# The ring sensor
# --------------------------------------------------------------------------------------
## A flat slab of Area3D lying over the apron. It is not an annulus, because an Area3D is
## made of convex primitives and an annulus is not one: it is the WHOLE apron, at a HEIGHT
## nothing on the platform can reach. A wheel on the platform bottoms out at y = 0; the
## slab's top is at -0.06. The platform body passes through it and is ignored, because the
## mask is bots only.
func _build_hazards() -> void:
	_ring_sensor = Area3D.new()
	_ring_sensor.name = "RingSensor"
	_ring_sensor.collision_layer = FightTypes.LAYER_OOA
	_ring_sensor.collision_mask = FightTypes.LAYER_BOT
	_ring_sensor.monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(APRON, RING_SENSOR_DEPTH, APRON)
	shape.shape = box
	shape.position = Vector3(0.0, RING_SENSOR_TOP - RING_SENSOR_DEPTH * 0.5, 0.0)
	_ring_sensor.add_child(shape)
	_ring_sensor.body_entered.connect(_on_ring_entered)
	add_child(_ring_sensor)


func _on_ring_entered(body: Node3D) -> void:
	# Same signal the base's out-of-arena sensor uses, so anything already listening for a
	# machine leaving hears this one too.
	emit_signal("body_out", body)
	if body is BotPart:
		emit_signal("hazard_fx", "ring_out", true, (body as BotPart).global_position)


# --------------------------------------------------------------------------------------
# The contract the Sumo rules read
# --------------------------------------------------------------------------------------
func platform_radius() -> float:
	return PLATFORM_R


func platform_rise() -> float:
	return PLATFORM_RISE


## True while this world position is over the platform and above the step. Used by the
## rules every tick, so it is pure arithmetic and asks the physics nothing.
func on_platform(position: Vector3) -> bool:
	return Vector2(position.x, position.z).length() <= OFF_RADIUS \
		and position.y > RING_SENSOR_TOP


## The AI's read. There is no hazard with a clock; the danger is the rim, everywhere, and
## the one place that is definitely safe is the middle.
func hazard_helpers() -> Dictionary:
	return {
		"next_danger_in_s": 999.0,
		"danger_positions": [] as Array[Vector3],
		"safe_positions": [Vector3.ZERO] as Array[Vector3],
	}


func _physics_process(_delta: float) -> void:
	_ticks += 1
