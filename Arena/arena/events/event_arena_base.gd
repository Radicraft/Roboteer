extends ArenaBase
## The rectangular floor kit the five side event arenas are built on (agent E6,
## docs/stage6-spec.md §1, brief §10). `ArenaBase` assumes a SQUARE arena: one slab of
## `_arena_size` on a side, four walls laid out from `_half`, and an out-of-arena sensor
## whose side boxes sit at `_half` on both axes. Four of the five events are corridors or
## tables, so this subclass generalises exactly those three things and nothing else.
##
## Everything else in the kit is used unchanged: the render setup, the materials, the
## markings geometry, the spike patch, the grinder, the flame jet, the hazard plumbing
## (`_make_hazard_area`, `_damage_overlaps`, `_bots_in_area`) and the `hazard_fx` signal.
##
## A subclass sets its footprint in `_configure()` with `_set_rect(Vector2(x_m, z_m))`,
## which also sets `_arena_size` to the LONG side so `ArenaBase.build()` derives a `_half`
## that the base's own out-of-arena boxes are still outside of. `_extra_ooa_volumes()`
## then closes the short axis, which would otherwise be open from the wall out to `_half`:
## in a 24 x 6 corridor that is a nine metre band on each flank where a bot is past the
## wall and not yet out of the arena.
##
## Spawn marks are explicit rather than derived. `ArenaBase.spawn_position` returns The
## Yard's corner marks whenever the arena happens to be 10 m, and derives corners from
## `_spawn_inset` otherwise; a corridor wants its marks on the centre line at one end, and
## a table wants one mark and a parking bay.

## x by z, metres. The long side becomes `_arena_size`.
var _rect := Vector2(FightTypes.ARENA_SIZE, FightTypes.ARENA_SIZE)
## World positions for team 0 and team 1. Always two entries, even in a solo event: the
## fight always builds two machines (`fight.gd._spawn_bots` reads `bots[0]` and `bots[1]`),
## so a solo event still has to say where the second one is put.
var _spawn_marks: Array[Vector3] = [Vector3(-3.2, 0.25, 0.0), Vector3(3.2, 0.25, 0.0)]
## World direction each nose points at spawn. Empty entries fall back to "look at the other".
var _spawn_dirs: Array[Vector3] = []


## Call from `_configure()`. `_arena_size` is the long side so the base's floor probe,
## out-of-arena boxes and camera fit are all at least as big as the arena.
func _set_rect(rect: Vector2) -> void:
	_rect = rect
	_arena_size = maxf(rect.x, rect.y)


func rect_size() -> Vector2:
	return _rect


## The long half extent. `Rules.is_out_of_arena(pos, half)` compares BOTH axes against one
## number, so this has to be the generous one or a corridor declares its own far end out.
## The short axis is policed by `_extra_ooa_volumes()` and by the walls instead.
func arena_half_extent() -> float:
	return maxf(_rect.x, _rect.y) * 0.5


func _build_floor() -> void:
	_add_floor_slab("Floor", Vector2.ZERO, _rect)


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var t := FightTypes.WALL_THICKNESS
	var h := _wall_height
	if h <= 0.0:
		return
	var hx := _rect.x * 0.5
	var hz := _rect.y * 0.5
	for entry_variant in [
		{"name": "WallNorth", "pos": Vector3(0.0, h * 0.5, -hz), "size": Vector3(_rect.x + t, h, t)},
		{"name": "WallSouth", "pos": Vector3(0.0, h * 0.5, hz), "size": Vector3(_rect.x + t, h, t)},
		{"name": "WallWest", "pos": Vector3(-hx, h * 0.5, 0.0), "size": Vector3(t, h, _rect.y + t)},
		{"name": "WallEast", "pos": Vector3(hx, h * 0.5, 0.0), "size": Vector3(t, h, _rect.y + t)},
	]:
		var entry: Dictionary = entry_variant
		walls.add_child(_wall_box(str(entry["name"]), entry["pos"], entry["size"]))


## One wall slab with the chevron cap, built the way `ArenaBase._build_walls` builds one.
## Public to the subclasses so a goal frame or a start gate is the same object as a wall.
func _wall_box(box_name: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(size)
	mi.material_override = _wall_material()
	body.add_child(mi)
	if _chevron_caps:
		var strip := MeshInstance3D.new()
		strip.name = "Chevron"
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(size.x + 0.01, 0.06, size.z + 0.01)
		strip.mesh = strip_mesh
		strip.material_override = _chevron_strip_material()
		strip.position = Vector3(0.0, size.y * 0.5, 0.0)
		body.add_child(strip)
	return body


## Close the short axis. The base already walls off everything past `_half` on both axes;
## this adds the band between the short wall and `_half`.
func _extra_ooa_volumes() -> Array:
	var out: Array = []
	var far := 40.0
	var hx := _rect.x * 0.5 + FightTypes.WALL_THICKNESS
	var hz := _rect.y * 0.5 + FightTypes.WALL_THICKNESS
	if _rect.y < _rect.x:
		out.append({"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0.0, 3.0, -hz - far * 0.5)})
		out.append({"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0.0, 3.0, hz + far * 0.5)})
	elif _rect.x < _rect.y:
		out.append({"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(-hx - far * 0.5, 3.0, 0.0)})
		out.append({"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(hx + far * 0.5, 3.0, 0.0)})
	return out


func spawn_position(team_index: int) -> Vector3:
	var i := clampi(team_index, 0, _spawn_marks.size() - 1)
	return _spawn_marks[i] if _spawn_marks.size() > 0 else Vector3.ZERO


func spawn_facing(team_index: int) -> Vector3:
	var i := clampi(team_index, 0, 1)
	if i < _spawn_dirs.size():
		var d: Vector3 = _spawn_dirs[i]
		if Vector2(d.x, d.z).length() > 0.0001:
			return Vector3(d.x, 0.0, d.z).normalized()
	var from := spawn_position(i)
	var to := spawn_position(1 - i)
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat.normalized() if flat.length() > 0.0001 else Vector3.RIGHT


# --------------------------------------------------------------------------------------
# No event has a spike patch except the Gauntlet, and that one inherits the real clock, so
# the default answer to the Stage 3 spike contract is "never".
# --------------------------------------------------------------------------------------
func spikes_risen() -> bool:
	return not _spikes.is_empty() and _spikes_up


func seconds_to_spike_rise() -> float:
	if _spikes.is_empty():
		return 999.0
	return super()
