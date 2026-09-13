class_name Yard extends Node3D
## The Yard (docs/stage3-spec.md §5): a 10 x 10 m floor, four low walls with a
## chevron strip, a central spike patch on a physics-tick timer, an
## out-of-arena sensor and the two spawn markers. Everything is procedural:
## flat materials, chunky readable shapes, tabletop-miniature feel
## (Art/direction/arena-mid-fight.png).
##
## The camera is NOT here (agent C owns the rig).

signal body_out(body: Node)

const HALF := FightTypes.ARENA_SIZE * 0.5
const FLOOR_THICKNESS := 0.4
const GRID_STEP := 1.0
const GRID_WIDTH := 0.015
const SPIKE_PATCH := 1.6
const SPIKE_RISE := 0.25
const SPIKE_CYCLE_S := 6.0
const SPIKE_UP_S := 1.2
const SPIKE_TRAVEL_S := 0.25
## Spikes have no contact impulse of their own (they are an Area3D), so the
## hazard supplies one on a fixed cadence while it is risen.
const HAZARD_IMPULSE := 26.0
const HAZARD_PERIOD_TICKS := 15

const COL_FLOOR := Color(0.55, 0.56, 0.58)
const COL_GRID := Color(0.46, 0.47, 0.50)
const COL_WALL := Color(0.35, 0.36, 0.39)
const COL_SPIKE := Color(0.66, 0.67, 0.70)
const COL_BG := Color(0.21, 0.24, 0.29)      # flat grey-blue, no sky

var spawn_player: Marker3D = null
var spawn_opponent: Marker3D = null

var _spikes: Array[AnimatableBody3D] = []
var _spike_area: Area3D = null
var _ooa: Area3D = null
var _phase_ticks := 0
var _ticks := 0
var _spikes_up := false
var _built := false


func _ready() -> void:
	if not _built:
		build()


## Called by R with the shared RNG so the spike phase is part of the seed.
func setup(rng: RandomNumberGenerator) -> void:
	if not _built:
		build()
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	_phase_ticks = rng.randi_range(0, cycle - 1) if rng != null else 0
	_ticks = 0
	_set_spikes(0.0)


func build() -> void:
	if _built:
		return
	_built = true
	_build_environment()
	_build_floor()
	_build_walls()
	_build_spikes()
	_build_ooa()
	_build_markers()


func spikes_risen() -> bool:
	return _spikes_up


## Seconds until the spikes next start to rise. The AI steers away inside 1 s.
func seconds_to_spike_rise() -> float:
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	var t := (_ticks + _phase_ticks) % cycle
	return float(cycle - t) / float(FightTypes.TICK_HZ)


func spike_patch_centre() -> Vector3:
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.88)
	env.ambient_light_energy = 0.4
	env.ssao_enabled = false
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	# From the top left, matching the render's raking light.
	key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-135.0), 0.0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.98, 0.94)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 24.0
	add_child(key)


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = FightTypes.LAYER_ARENA
	floor_body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.0
	floor_body.physics_material_override = pm
	floor_body.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FightTypes.ARENA_SIZE, FLOOR_THICKNESS, FightTypes.ARENA_SIZE)
	shape.shape = box
	floor_body.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(box.size)
	mi.material_override = _flat(COL_FLOOR)
	floor_body.add_child(mi)
	add_child(floor_body)

	var grid := MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = _grid_mesh()
	grid.material_override = _flat(COL_GRID)
	grid.position = Vector3(0.0, 0.003, 0.0)
	add_child(grid)


## A subtle 1 m grid as one flat mesh of thin quads laid just over the floor.
func _grid_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var h := GRID_WIDTH * 0.5
	var n := int(FightTypes.ARENA_SIZE / GRID_STEP)
	for i in range(n + 1):
		var p := -HALF + float(i) * GRID_STEP
		_quad(verts, norms, Vector3(p - h, 0, -HALF), Vector3(p + h, 0, -HALF),
			Vector3(p + h, 0, HALF), Vector3(p - h, 0, HALF))
		_quad(verts, norms, Vector3(-HALF, 0, p - h), Vector3(-HALF, 0, p + h),
			Vector3(HALF, 0, p + h), Vector3(HALF, 0, p - h))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _quad(verts: PackedVector3Array, norms: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		if (p1 - p0).cross(p2 - p0).dot(Vector3.UP) > 0.0:
			var s := p1
			p1 = p2
			p2 = s
		verts.append(p0)
		verts.append(p1)
		verts.append(p2)
		for _i in range(3):
			norms.append(Vector3.UP)


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var t := FightTypes.WALL_THICKNESS
	var h := FightTypes.WALL_HEIGHT
	var span := FightTypes.ARENA_SIZE + t
	var chevron := _chevron_material()
	var layout := [
		{"name": "WallNorth", "pos": Vector3(0, h * 0.5, -HALF), "size": Vector3(span, h, t)},
		{"name": "WallSouth", "pos": Vector3(0, h * 0.5, HALF), "size": Vector3(span, h, t)},
		{"name": "WallWest", "pos": Vector3(-HALF, h * 0.5, 0), "size": Vector3(t, h, span)},
		{"name": "WallEast", "pos": Vector3(HALF, h * 0.5, 0), "size": Vector3(t, h, span)},
	]
	for entry_variant in layout:
		var entry: Dictionary = entry_variant
		var body := StaticBody3D.new()
		body.name = str(entry["name"])
		body.collision_layer = FightTypes.LAYER_ARENA
		body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
		body.position = entry["pos"]
		var size: Vector3 = entry["size"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = BotMeshes.flat_box_mesh(size)
		mi.material_override = _flat(COL_WALL)
		body.add_child(mi)
		# Yellow and black chevron strip capping the wall, as in the render.
		var strip := MeshInstance3D.new()
		strip.name = "Chevron"
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(size.x + 0.01, 0.06, size.z + 0.01)
		strip.mesh = strip_mesh
		strip.material_override = chevron
		strip.position = Vector3(0.0, size.y * 0.5, 0.0)
		body.add_child(strip)
		walls.add_child(body)


func _chevron_material() -> StandardMaterial3D:
	var w := 32
	var img := Image.create(w, 8, false, Image.FORMAT_RGB8)
	var yellow := Color(0.93, 0.76, 0.13)
	var black := Color(0.10, 0.10, 0.11)
	for y in range(8):
		for x in range(w):
			# A diagonal band makes the chevron read from the isometric camera.
			var v := (x + y) % 16
			img.set_pixel(x, y, yellow if v < 8 else black)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(24.0, 1.0, 1.0)
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


func _build_spikes() -> void:
	var patch := Node3D.new()
	patch.name = "SpikePatch"
	add_child(patch)
	var step := SPIKE_PATCH / 3.0
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.005
	spike_mesh.bottom_radius = 0.07
	spike_mesh.height = 0.34
	spike_mesh.radial_segments = 6
	spike_mesh.rings = 1
	var spike_mat := _flat(COL_SPIKE)
	spike_mat.metallic = 0.5
	spike_mat.roughness = 0.45
	for gx in range(3):
		for gz in range(3):
			var body := AnimatableBody3D.new()
			body.name = "Spike%d%d" % [gx, gz]
			body.sync_to_physics = false
			body.collision_layer = FightTypes.LAYER_HAZARD
			body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
			body.add_to_group("arena_hazard")
			body.position = Vector3((float(gx) - 1.0) * step, -0.2, (float(gz) - 1.0) * step)
			var shape := CollisionShape3D.new()
			var cone := CylinderShape3D.new()
			cone.radius = 0.06
			cone.height = 0.34
			shape.shape = cone
			body.add_child(shape)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = spike_mesh
			mi.material_override = spike_mat
			body.add_child(mi)
			patch.add_child(body)
			_spikes.append(body)

	_spike_area = Area3D.new()
	_spike_area.name = "SpikeHazard"
	_spike_area.collision_layer = FightTypes.LAYER_HAZARD
	_spike_area.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	_spike_area.monitoring = false
	_spike_area.add_to_group("arena_hazard")
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(SPIKE_PATCH, 0.34, SPIKE_PATCH)
	area_shape.shape = area_box
	area_shape.position = Vector3(0.0, 0.17, 0.0)
	_spike_area.add_child(area_shape)
	patch.add_child(_spike_area)
	_set_spikes(0.0)


## Out of the arena: below y = -1, or outside the walls at any height.
func _build_ooa() -> void:
	_ooa = Area3D.new()
	_ooa.name = "OutOfArena"
	_ooa.collision_layer = FightTypes.LAYER_OOA
	_ooa.collision_mask = FightTypes.LAYER_BOT
	_ooa.monitoring = true
	var outside := HALF + FightTypes.WALL_THICKNESS
	var far := 40.0
	var boxes := [
		{"size": Vector3(far * 2.0, 2.0, far * 2.0), "pos": Vector3(0, FightTypes.OUT_OF_ARENA_Y - 1.0, 0)},
		{"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(-outside - far * 0.5, 3.0, 0)},
		{"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(outside + far * 0.5, 3.0, 0)},
		{"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0, 3.0, -outside - far * 0.5)},
		{"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0, 3.0, outside + far * 0.5)},
	]
	for entry_variant in boxes:
		var entry: Dictionary = entry_variant
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry["size"]
		shape.shape = box
		shape.position = entry["pos"]
		_ooa.add_child(shape)
	_ooa.body_entered.connect(_on_ooa_body_entered)
	add_child(_ooa)


func _build_markers() -> void:
	var player := Marker3D.new()
	player.name = "SpawnPlayer"
	player.position = FightTypes.SPAWN_PLAYER
	player.look_at_from_position(FightTypes.SPAWN_PLAYER,
		Vector3(FightTypes.SPAWN_OPPONENT.x, FightTypes.SPAWN_PLAYER.y, FightTypes.SPAWN_OPPONENT.z),
		Vector3.UP)
	add_child(player)
	spawn_player = player

	var opponent := Marker3D.new()
	opponent.name = "SpawnOpponent"
	opponent.position = FightTypes.SPAWN_OPPONENT
	opponent.look_at_from_position(FightTypes.SPAWN_OPPONENT,
		Vector3(FightTypes.SPAWN_PLAYER.x, FightTypes.SPAWN_OPPONENT.y, FightTypes.SPAWN_PLAYER.z),
		Vector3.UP)
	add_child(opponent)
	spawn_opponent = opponent


## Spawn facings as world directions, so a Bot can be placed without caring
## which way a Marker3D's -Z points.
func spawn_facing(team_index: int) -> Vector3:
	var from := FightTypes.SPAWN_PLAYER if team_index == 0 else FightTypes.SPAWN_OPPONENT
	var to := FightTypes.SPAWN_OPPONENT if team_index == 0 else FightTypes.SPAWN_PLAYER
	return (Vector3(to.x, 0.0, to.z) - Vector3(from.x, 0.0, from.z)).normalized()


func spawn_position(team_index: int) -> Vector3:
	return FightTypes.SPAWN_PLAYER if team_index == 0 else FightTypes.SPAWN_OPPONENT


# ---------------------------------------------------------------------------
# Hazard tick (physics tick, phase from the seed: deterministic)
# ---------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	var up_ticks := int(round(SPIKE_UP_S * FightTypes.TICK_HZ))
	var travel := int(round(SPIKE_TRAVEL_S * FightTypes.TICK_HZ))
	var t := (_ticks + _phase_ticks) % cycle
	_ticks += 1

	var height := 0.0
	if t < up_ticks:
		if t < travel:
			height = float(t) / float(travel)
		elif t > up_ticks - travel:
			height = float(up_ticks - t) / float(travel)
		else:
			height = 1.0
	_set_spikes(clampf(height, 0.0, 1.0))

	var risen := height > 0.6
	if risen != _spikes_up:
		_spikes_up = risen
		if _spike_area != null:
			_spike_area.monitoring = risen
	if _spikes_up and _ticks % HAZARD_PERIOD_TICKS == 0:
		_damage_overlaps()


func _set_spikes(amount: float) -> void:
	var y := -0.2 + amount * (SPIKE_RISE + 0.2)
	for spike in _spikes:
		if is_instance_valid(spike):
			spike.position.y = y


func _damage_overlaps() -> void:
	if _spike_area == null:
		return
	for body in _spike_area.get_overlapping_bodies():
		if body is BotPart:
			var part: BotPart = body
			if part.detached or part.owner_bot == null:
				continue
			part.owner_bot.hazard_hit(part, HAZARD_IMPULSE, part.global_position)


func _on_ooa_body_entered(body: Node3D) -> void:
	emit_signal("body_out", body)


func _flat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat
