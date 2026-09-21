extends ChassisBase
## Shell: a low drum with the wheels tucked inside it and a rotating outer ring.
##
## The ring is a separate mesh in `shell.glb`. When the full body spinner is
## fitted, the WEAPON owns the ring (it becomes a body on a vertical hinge), so
## this hull hides its own and shrinks its collision to the hub. With any other
## weapon the ring is a fixed part of the hull, which is what makes the shell's
## sides unreachable.
##
## Inverted, a shell rests on its dome and its wheels no longer reach the floor.
## Rather than giving it absurd wheels, the Bot lets an invertible chassis fire the
## righting impulse with `secondary` even with no srimech fitted: a real shell bot
## rights itself on its own ring, and the catalogue already says this one is
## "immune to flipping".

const HUB_RADIUS_FRACTION := 0.82
const RING_HEIGHT := 0.12
const RING_Y := 0.04


func com_x() -> float:
	return 0.0


## The hull keeps its ring unless a full body spinner is actually going to take it
## over. While the weapon's module does not exist the Bot fits an inert plate
## instead, and a shell with neither ring would have an open flank, so the
## handover is conditional on that module being there.
##
## The test is the catalogue KIND, not the id (wave P, D1): "fbs" is now two
## weapons, `full_body_spinner` and the Level 95 `vortex_spinner`, and a hull that
## only recognised the first would have drawn its own ring inside the second's.
func has_own_ring() -> bool:
	var weapon_id := str(config.get("weapon", ""))
	if str(PartsCatalogue.weapon(weapon_id).get("kind", "")) != "fbs":
		return true
	return not ResourceLoader.exists("res://bot/weapons/%s.gd" % weapon_id)


func hub_radius() -> float:
	return half_wid() * HUB_RADIUS_FRACTION


func ring_radius() -> float:
	return half_wid()


func shapes() -> Array[Dictionary]:
	var hub := CylinderShape3D.new()
	hub.radius = hub_radius()
	hub.height = height()
	var out: Array[Dictionary] = [{"shape": hub, "transform": Transform3D(Basis.IDENTITY,
		Vector3(0.0, floor_y() + height() * 0.5, 0.0))}]
	if has_own_ring():
		var ring := CylinderShape3D.new()
		ring.radius = ring_radius()
		ring.height = RING_HEIGHT
		out.append({"shape": ring, "transform": Transform3D(Basis.IDENTITY,
			Vector3(0.0, RING_Y, 0.0))})
	return out


func hull_points() -> PackedVector3Array:
	var points := BotMeshes.cylinder_points(hub_radius(), floor_y(), top_y(), 12)
	if has_own_ring():
		points.append_array(BotMeshes.cylinder_points(ring_radius(),
			RING_Y - RING_HEIGHT * 0.5, RING_Y + RING_HEIGHT * 0.5, 12))
	return points


func procedural_meshes() -> Array[Dictionary]:
	var drum := CylinderMesh.new()
	drum.top_radius = hub_radius()
	drum.bottom_radius = hub_radius()
	drum.height = height()
	drum.radial_segments = 16
	var out: Array[Dictionary] = [{"mesh": drum, "transform": Transform3D(Basis.IDENTITY,
		Vector3(0.0, floor_y() + height() * 0.5, 0.0)), "slot": "livery"}]
	if has_own_ring():
		var ring := CylinderMesh.new()
		ring.top_radius = ring_radius()
		ring.bottom_radius = ring_radius()
		ring.height = RING_HEIGHT
		ring.radial_segments = 16
		out.append({"mesh": ring, "transform": Transform3D(Basis.IDENTITY,
			Vector3(0.0, RING_Y, 0.0)), "slot": "steel"})
	return out


## The full body spinner takes the ring over, so the hull must not draw it too.
func _on_model_bound() -> void:
	if has_own_ring():
		return
	var ring := ring_mesh()
	if ring != null:
		ring.visible = false


func ring_mesh() -> MeshInstance3D:
	if model == null:
		return null
	return model.find_child("ring", true, false) as MeshInstance3D


func front_lip_point() -> Vector3:
	return Vector3(hub_radius(), floor_y(), 0.0)
