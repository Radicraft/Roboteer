class_name DropZoneArena extends ArenaBase
## Drop Zone (brief §7 arena 3, docs/stage5-spec.md §3): a 2.4 m square pit in the middle
## of the floor under a two-leaf cover that retracts at a seeded time between 30 and 60
## seconds, stays open for 15, and closes again. Falling in is out of the arena, for
## either bot, with no appeal: the pit volume is part of the OOA sensor.
##
##   FLOOR PLAN (10 x 10 m, north is -Z)
##
##     -5                    0                    +5
##   -5 +-------------------------------------------+
##      |  P     \                         /        |   P  player spawn (-3.2, -3.2)
##      |         \    +===========+      /         |   O  opponent spawn (3.2, 3.2)
##      |          \   | | | | | | |     /          |   +=+ warning strip (amber)
##    0 |              | |  PIT  | |                |   |||  the two cover leaves,
##      |          /   | | | | | | |     \          |        retracting east and west
##      |         /    +===========+      \         |    \ / the four approach lines
##      |        /                         \      O |
##   +5 +-------------------------------------------+
##
## The pit is dead centre: both spawns are 4.5 m from it along the same diagonal, so it is
## symmetric, and the diagonal the bots charge along at the bell runs straight across it.
## That is deliberate. For the first 30 seconds the cover is a floor and the middle is the
## best ground in the arena; once it opens, the habit both drivers have built is a trap.
##
## Marking scheme (original, brief §3): a square amber strip around the rim, hatched
## inside it, and four approach lines running out to the corners. The strip is emissive
## and blinks for 3 seconds before the cover moves.

const PIT := 2.4                       # metres square
const PIT_DEPTH := 2.8
const COVER_THICKNESS := 0.1
const COVER_TRAVEL_S := 1.0
const OPEN_S := 15.0
const WARN_S := 3.0
## The seeded window the brief asks for.
const OPEN_MIN_S := 30.0
const OPEN_MAX_S := 60.0
## If a fight runs long enough to see it close, it comes back. 90 second fights normally
## see the pit once.
const REOPEN_S := 45.0

const STATE_CLOSED := 0
const STATE_OPENING := 1
const STATE_OPEN := 2
const STATE_CLOSING := 3

## Dark, with the amber as the only warm thing in the room. Wave A: the floor was 0.72 at
## metallic 0.12 and swallowed the bots' shadows (arenas.md §2.3); 1.7 keeps it the
## darkest floor in the game by a clear step while a machine separates from it. The
## darkness moves to the walls (1.9 -> 1.25, cold slate) and the pit, which now glows.
const TINT_FLOOR := Color(1.62, 1.64, 1.74)
const TINT_WALL := Color(1.18, 1.22, 1.36)
const COL_AMBER := Color(0.95, 0.62, 0.08)
const COL_HATCH := Color(0.30, 0.24, 0.12)

var _cover_west: AnimatableBody3D = null
var _cover_east: AnimatableBody3D = null
var _warn_mat: StandardMaterial3D = null
var _rim_light: OmniLight3D = null
var _pit_light: OmniLight3D = null

var _open_at := int(round(OPEN_MIN_S * FightTypes.TICK_HZ))
var _state := STATE_CLOSED
var _state_ticks := 0
var _warning := false


func arena_id() -> String:
	return "drop_zone"


func _configure() -> void:
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT
	_floor_mat = MAT_CONCRETE
	_wall_mat = MAT_CONCRETE
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.12
	_ambient_tint = Color(0.78, 0.80, 0.92)
	_ambient_energy_scale = 0.85
	_key_colour = Color(0.94, 0.94, 1.0)
	_key_energy = 0.46
	_bg_tint = Color(0.62, 0.66, 0.78)
	_grid_enabled = false


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
## Four slabs around a square hole, rather than one slab: a hole in a BoxShape3D is not a
## thing, and a ConcavePolygonShape3D floor would cost the fight its cheapest collider.
func _build_floor() -> void:
	var edge := (_arena_size - PIT) * 0.5          # 3.8 m
	var off := (PIT + edge) * 0.5                  # 3.1 m
	_add_floor_slab("FloorNorth", Vector2(0.0, -off), Vector2(_arena_size, edge))
	_add_floor_slab("FloorSouth", Vector2(0.0, off), Vector2(_arena_size, edge))
	_add_floor_slab("FloorWest", Vector2(-off, 0.0), Vector2(edge, PIT))
	_add_floor_slab("FloorEast", Vector2(off, 0.0), Vector2(edge, PIT))
	_build_pit()


func _build_pit() -> void:
	var pit := StaticBody3D.new()
	pit.name = "Pit"
	pit.collision_layer = FightTypes.LAYER_ARENA
	pit.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	add_child(pit)

	var wall_mat := _textured(MAT_CONCRETE, Color(0.9, 0.88, 0.92), 0.6, Color(0.18, 0.18, 0.2))
	var t := 0.2
	var sides := [
		{"pos": Vector3(0.0, -PIT_DEPTH * 0.5, -(PIT + t) * 0.5), "size": Vector3(PIT + t * 2.0, PIT_DEPTH, t)},
		{"pos": Vector3(0.0, -PIT_DEPTH * 0.5, (PIT + t) * 0.5), "size": Vector3(PIT + t * 2.0, PIT_DEPTH, t)},
		{"pos": Vector3(-(PIT + t) * 0.5, -PIT_DEPTH * 0.5, 0.0), "size": Vector3(t, PIT_DEPTH, PIT)},
		{"pos": Vector3((PIT + t) * 0.5, -PIT_DEPTH * 0.5, 0.0), "size": Vector3(t, PIT_DEPTH, PIT)},
		# The bottom, so a bot that falls in stops somewhere instead of falling forever.
		{"pos": Vector3(0.0, -PIT_DEPTH - 0.1, 0.0), "size": Vector3(PIT + t * 2.0, 0.2, PIT + t * 2.0)},
	]
	for entry_variant in sides:
		var entry: Dictionary = entry_variant
		var size: Vector3 = entry["size"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = entry["pos"]
		pit.add_child(shape)
		var mi := MeshInstance3D.new()
		mi.mesh = BotMeshes.flat_box_mesh(size)
		mi.material_override = wall_mat
		mi.position = entry["pos"]
		pit.add_child(mi)

	# Wave A: the abyss glows (arenas.md §2.3 gap 1). An emissive floor far down and a red
	# light in the shaft, lit only while the cover is off, so an open pit is the brightest
	# thing on screen rather than the darkest. No collision: meshes and a light.
	var glow := MeshInstance3D.new()
	glow.name = "PitGlow"
	var glow_mesh := PlaneMesh.new()
	glow_mesh.size = Vector2(PIT, PIT)
	glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.2, 0.03, 0.01)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.22, 0.06)
	glow_mat.emission_energy_multiplier = 3.0
	glow.material_override = glow_mat
	glow.position = Vector3(0.0, -PIT_DEPTH + 0.01, 0.0)
	pit.add_child(glow)
	_pit_light = OmniLight3D.new()
	_pit_light.name = "PitShaftLight"
	_pit_light.light_color = Color(1.0, 0.28, 0.08)
	_pit_light.light_energy = 3.5
	_pit_light.omni_range = 3.6
	_pit_light.shadow_enabled = false
	_pit_light.position = Vector3(0.0, -1.6, 0.0)
	_pit_light.visible = false
	pit.add_child(_pit_light)


func _build_hazards() -> void:
	var leaf := Vector3(PIT * 0.5, COVER_THICKNESS, PIT)
	_cover_west = _make_cover("CoverWest", Vector3(-PIT * 0.25, -COVER_THICKNESS * 0.5, 0.0), leaf)
	_cover_east = _make_cover("CoverEast", Vector3(PIT * 0.25, -COVER_THICKNESS * 0.5, 0.0), leaf)

	# The rim lamp: off while the cover is shut, blinking in the warning, on while open.
	_rim_light = OmniLight3D.new()
	_rim_light.name = "PitLight"
	_rim_light.light_color = COL_AMBER
	_rim_light.light_energy = 2.2
	_rim_light.omni_range = 5.0
	_rim_light.shadow_enabled = false
	_rim_light.position = Vector3(0.0, 0.6, 0.0)
	_rim_light.visible = false
	add_child(_rim_light)


func _make_cover(cover_name: String, at: Vector3, size: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = cover_name
	body.sync_to_physics = false
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.position = at
	var pm := PhysicsMaterial.new()
	pm.friction = _floor_friction
	pm.bounce = 0.0
	body.physics_material_override = pm

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(size)
	# Wave A: was MAT_STEEL at 1.2x and read as a pale blue square. Tread plate steel
	# a step darker than the floor, so the seam stripe and the warning read on it.
	var mat := _textured(MAT_STEEL, Color(0.78, 0.78, 0.8), 0.7, Color(0.4, 0.4, 0.43))
	mat.metallic = 0.5
	mi.material_override = mat
	body.add_child(mi)

	# A leaf-edge stripe so the seam down the middle of the cover is obvious from the
	# camera: the player should be able to see what is under their wheels.
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.08, 0.012, size.z * 0.96)
	stripe.mesh = stripe_mesh
	stripe.material_override = _lamp(COL_AMBER, 0.8)
	stripe.position = Vector3(size.x * 0.5 - 0.06, COVER_THICKNESS * 0.5, 0.0)
	body.add_child(stripe)

	add_child(body)
	return body


func _build_markings() -> void:
	# The amber rim: four bars round the pit, and a hatch inside them.
	var rim := PackedVector3Array()
	var rim_n := PackedVector3Array()
	var outer := PIT * 0.5 + 0.34
	var bar := 0.22
	_mark_rect(rim, rim_n, Vector2(0.0, -outer + bar * 0.5), Vector2(outer * 2.0, bar))
	_mark_rect(rim, rim_n, Vector2(0.0, outer - bar * 0.5), Vector2(outer * 2.0, bar))
	_mark_rect(rim, rim_n, Vector2(-outer + bar * 0.5, 0.0), Vector2(bar, outer * 2.0 - bar * 2.0))
	_mark_rect(rim, rim_n, Vector2(outer - bar * 0.5, 0.0), Vector2(bar, outer * 2.0 - bar * 2.0))
	var strip := _add_marking("WarningStrip", _mesh_from(rim, rim_n), COL_AMBER, 1.4)
	_warn_mat = strip.material_override as StandardMaterial3D

	var hatch := PackedVector3Array()
	var hatch_n := PackedVector3Array()
	# Hatching between the rim bars and the pit edge, on all four sides.
	var inner := PIT * 0.5
	var band := outer - bar - inner
	if band > 0.02:
		var mid := inner + band * 0.5
		for i in range(11):
			var p := -inner + (2.0 * inner) * float(i) / 10.0
			_mark_line(hatch, hatch_n, Vector2(p - 0.10, -mid - band * 0.4),
				Vector2(p + 0.10, -mid + band * 0.4), 0.06)
			_mark_line(hatch, hatch_n, Vector2(p - 0.10, mid - band * 0.4),
				Vector2(p + 0.10, mid + band * 0.4), 0.06)
			_mark_line(hatch, hatch_n, Vector2(-mid - band * 0.4, p - 0.10),
				Vector2(-mid + band * 0.4, p + 0.10), 0.06)
			_mark_line(hatch, hatch_n, Vector2(mid - band * 0.4, p - 0.10),
				Vector2(mid + band * 0.4, p + 0.10), 0.06)
	_add_marking("Hatching", _mesh_from(hatch, hatch_n), COL_HATCH, 0.0)

	# Four approach lines to the corners: the arena telling you which way you are being
	# driven, which is the only warning the loser usually gets.
	var lines := PackedVector3Array()
	var lines_n := PackedVector3Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var dir: Vector2 = s.normalized()
		_mark_line(lines, lines_n, dir * (outer + 0.25), dir * (_half - 0.35), 0.09)
	_add_marking("ApproachLines", _mesh_from(lines, lines_n), Color(0.42, 0.36, 0.26), 0.0)


## The pit is part of the out-of-arena sensor: the box sits BELOW the closed cover, so
## standing on the cover is safe and dropping through it is not.
func _extra_ooa_volumes() -> Array:
	var top := -0.25
	var bottom := -PIT_DEPTH
	return [{
		"size": Vector3(PIT - 0.05, top - bottom, PIT - 0.05),
		"pos": Vector3(0.0, (top + bottom) * 0.5, 0.0),
	}]


# ---------------------------------------------------------------------------
# Seeded timeline
# ---------------------------------------------------------------------------
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	var lo := int(round(OPEN_MIN_S * FightTypes.TICK_HZ))
	var hi := int(round(OPEN_MAX_S * FightTypes.TICK_HZ))
	_open_at = rng.randi_range(lo, hi) if rng != null else lo
	_state = STATE_CLOSED
	_state_ticks = 0
	_warning = false
	_set_cover(0.0)
	_set_warning_light(false, false)


## brief v4 §2: at the endgame the pit opens and never closes again. If the cover is shut
## it starts retracting on this tick; if it is already open REOPEN_S and the fifteen
## second window are both ignored for the rest of the fight. The base class has already
## latched `_escalated`, so nothing here can be undone.
func _on_phase(_phase_name: String) -> void:
	_warning = false
	match _state:
		STATE_CLOSED:
			_open_at = _ticks
		STATE_CLOSING:
			# Mid-close: turn it round rather than let it finish shutting.
			_state = STATE_OPENING
			_state_ticks = int(round((1.0 - float(_cover_amount())) * COVER_TRAVEL_S
				* FightTypes.TICK_HZ))
	_set_warning_light(true, true)


## How far the cover has retracted, 0 shut to 1 open. Read back off the leaf so it is the
## same number the physics has, whatever state the machine is in.
func _cover_amount() -> float:
	if not is_instance_valid(_cover_west):
		return 0.0
	return clampf((-_cover_west.position.x - PIT * 0.25) / (PIT * 0.5 + 0.05), 0.0, 1.0)


## The tick the cover starts to retract, in seconds from the bell. The scouting screen and
## the tests both read it.
func opens_at_s() -> float:
	return float(_open_at) / float(FightTypes.TICK_HZ)


func pit_open() -> bool:
	return _state == STATE_OPEN or _state == STATE_OPENING


func pit_centre() -> Vector3:
	return Vector3.ZERO


func warning_lit() -> bool:
	return _warning


# ---------------------------------------------------------------------------
# Hazard tick
# ---------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	var travel := int(round(COVER_TRAVEL_S * FightTypes.TICK_HZ))
	var open_ticks := int(round(OPEN_S * FightTypes.TICK_HZ))
	var warn_ticks := int(round(WARN_S * FightTypes.TICK_HZ))

	match _state:
		STATE_CLOSED:
			var left := _open_at - _ticks
			var warn := left <= warn_ticks and left > 0
			if warn != _warning:
				_warning = warn
				# Wave A: its own kind. It used to be ("pit", true), the same as the open,
				# so pit_open (the leaves sliding) played three seconds early. The shared
				# warning layer now owns the warning; this stays for anything listening.
				emit_signal("hazard_fx", "pit_warning", warn, Vector3.ZERO)
			# 4 Hz blink while the warning runs.
			_set_warning_light(warn, warn and (_ticks / 8) % 2 == 0)
			if left <= 0:
				_state = STATE_OPENING
				_state_ticks = 0
				_warning = false
				# Wave A: announced as the leaves START to slide, so pit_open (hydraulics,
				# leaves sliding, the stop) plays over the slide it describes.
				emit_signal("hazard_fx", "pit", true, Vector3.ZERO)
		STATE_OPENING:
			_state_ticks += 1
			_set_cover(clampf(float(_state_ticks) / float(travel), 0.0, 1.0))
			_set_warning_light(true, true)
			if _state_ticks >= travel:
				_state = STATE_OPEN
				_state_ticks = 0
		STATE_OPEN:
			_state_ticks += 1
			# The endgame pit never closes (brief v4 §2): the fifteen second window and
			# REOPEN_S are both off for the rest of the fight.
			if _state_ticks >= open_ticks and not _escalated:
				_state = STATE_CLOSING
				_state_ticks = 0
		STATE_CLOSING:
			_state_ticks += 1
			_set_cover(clampf(1.0 - float(_state_ticks) / float(travel), 0.0, 1.0))
			if _state_ticks >= travel:
				_state = STATE_CLOSED
				_state_ticks = 0
				_set_cover(0.0)
				_set_warning_light(false, false)
				_open_at = _ticks + int(round(REOPEN_S * FightTypes.TICK_HZ))
				emit_signal("hazard_fx", "pit", false, Vector3.ZERO)
	_ticks += 1


## 0 = shut, 1 = fully retracted under the floor slabs either side.
func _set_cover(amount: float) -> void:
	if is_instance_valid(_pit_light):
		_pit_light.visible = amount > 0.02
	var slide := (PIT * 0.5 + 0.05) * amount
	if is_instance_valid(_cover_west):
		_cover_west.position.x = -PIT * 0.25 - slide
		# Drop it 0.12 m as it goes, so the leaf slides UNDER the floor rather than
		# through it, and a bot standing on the edge is dropped rather than shoved.
		_cover_west.position.y = -COVER_THICKNESS * 0.5 - 0.12 * amount
	if is_instance_valid(_cover_east):
		_cover_east.position.x = PIT * 0.25 + slide
		_cover_east.position.y = -COVER_THICKNESS * 0.5 - 0.12 * amount


func _set_warning_light(active: bool, lit: bool) -> void:
	if _warn_mat != null:
		_warn_mat.emission_energy_multiplier = 4.5 if lit else 1.0
		_warn_mat.albedo_color = COL_AMBER if active else COL_AMBER.darkened(0.35)
	if is_instance_valid(_rim_light):
		# Wave A: the shared warning layer owns the warning's light (in the shared
		# rhythm); this amber rim lamp now only burns once the cover is moving.
		_rim_light.visible = lit and _state != STATE_CLOSED


# ---------------------------------------------------------------------------
# Wave A: the warning layer's read. READ-ONLY, from the same clock the cover runs on.
# ---------------------------------------------------------------------------
func _schedule_extra(out: Array) -> void:
	var active := _state != STATE_CLOSED
	var in_s := 0.0
	if _state == STATE_CLOSED:
		in_s = maxf(float(_open_at - _ticks), 0.0) / float(FightTypes.TICK_HZ)
	var rim := (PIT * 0.5 + 0.34) * 2.0
	out.append(_schedule_entry("pit", "pit", "pit", Vector3.ZERO, Vector2(rim, rim), "rect",
		in_s, active, [_warn_mat] if _warn_mat != null else [], WARN_S))


# ---------------------------------------------------------------------------
# The AI's read
# ---------------------------------------------------------------------------
func hazard_helpers() -> Dictionary:
	var left := 0.0
	if _state == STATE_CLOSED:
		left = maxf(float(_open_at - _ticks) / float(FightTypes.TICK_HZ), 0.0)
	return {
		"next_danger_in_s": left,
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
	}


func _danger_positions() -> Array[Vector3]:
	if _state == STATE_CLOSED and not _warning:
		return []
	return [Vector3.ZERO]


## No spike patch here. fight.gd's spike clock must read "never" so the judges never score
## seconds on a patch that does not exist.
func spikes_risen() -> bool:
	return false


func seconds_to_spike_rise() -> float:
	return 999.0
