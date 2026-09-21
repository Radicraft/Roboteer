extends DriveBase
## Tracks: three road wheels a side under a belt skin, one condition per side.
##
## Three a side rather than four keeps the whole bot inside brief section 12's
## body budget (chassis, six wheels, weapon, panels) with tracks counting as
## wheels, which is what the spec's own body count test asks for. The belt is a
## visual on the chassis, not a body: when a side's condition reaches zero the
## belt comes off, that side's motors stop and the bot circles.

const SKIN_MODEL := "track_unit"
const SKIN_LENGTH := 0.70          # the authored length of track_unit.glb


## Tracks use the six wheel slot row, three a side.
func slot_drive_id() -> String:
	return "6wd"


func wheel_count() -> int:
	return 6


func _key_for(pos: Vector3, _rows: Dictionary) -> String:
	return "track_l" if pos.z < 0.0 else "track_r"


func side_alive(key: String) -> bool:
	var damage: BotDamage = bot.damage
	return damage != null and damage.value_for(key) > 0.0


func _build_skins() -> void:
	for side in [-1.0, 1.0]:
		var xs: Array[float] = []
		var z := 0.0
		for i in range(wheel_local.size()):
			if signf(wheel_local[i].z) != side:
				continue
			xs.append(wheel_local[i].x)
			z = wheel_local[i].z
		if xs.is_empty():
			continue
		xs.sort()
		var span := xs[xs.size() - 1] - xs[0] + radius * 2.0
		var centre := (xs[0] + xs[xs.size() - 1]) * 0.5
		var key := "track_l" if side < 0.0 else "track_r"
		var skin := _skin_node(span)
		if skin == null:
			continue
		skin.name = "TrackSkin" + ("L" if side < 0.0 else "R")
		# track_unit.glb is authored with its frame plate on the inboard (-Z) face,
		# which is the right hand side. The left side is the same unit turned
		# around, never a mirrored scale (that would invert the normals).
		var basis := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
		skin.transform = Transform3D(basis.scaled(Vector3(span / SKIN_LENGTH, 1.0, 1.0)),
			Vector3(centre, 0.0, z))
		bot.chassis.add_child(skin)
		bot.register_visual(key, skin)


## Which .glb the belt skin is. Overridable so `adaptive_tracks.gd` can wear its
## own segmented belt (wave P, agent E); both are authored to SKIN_LENGTH with
## the frame plate on -Z, so everything below is unchanged.
func skin_model() -> String:
	return SKIN_MODEL


func _skin_node(span: float) -> Node3D:
	var model := PartVisuals.instantiate(skin_model())
	if model != null:
		PartVisuals.bind(model, bot.livery)
		return model
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(span, radius * 2.0, FightTypes.WHEEL_WIDTH * 1.4)
	mesh.mesh = box
	mesh.material_override = PartVisuals.slot_material("rubber", bot.livery)
	return mesh
