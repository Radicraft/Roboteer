extends WeaponBase
## The fallback when a weapon id has no script yet: a plate on the front socket
## that does nothing but exist, so a bot with an unimplemented weapon still fights
## with the right weight in the right place instead of failing to assemble.
##
## The Bot logs an arena warning when it fits one. Delete nothing here when W1 and
## W2 land: a config can always name a weapon a build of the game does not have.

const PLATE_THICK := 0.05

var plate: BotPart = null


func _build() -> void:
	var reach := maxf(float(spec.get("reach", 0.2)), 0.08)
	var size := Vector3(reach, 0.10, 0.34)
	plate = BotPart.new()
	plate.name = "WeaponPlate"
	plate.part_key = FightTypes.PART_WEAPON
	plate.part_kind = "weapon"
	plate.material_name = "steel"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	plate.add_child(shape)

	var model := PartVisuals.instantiate(str(spec.get("id", "")))
	if model != null:
		plate.add_child(model)
		PartVisuals.bind(model, bot.livery)
	else:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = BotMeshes.flat_box_mesh(size)
		mesh_instance.material_override = PartVisuals.slot_material("steel", bot.livery)
		plate.add_child(mesh_instance)

	plate.transform = Transform3D(Basis.IDENTITY,
		socket_transform().origin + Vector3(size.x * 0.5, 0.0, 0.0))
	bot.register_part(plate, FightTypes.PART_WEAPON, "weapon", mass())
	bot.weld(plate)


func readiness() -> float:
	return 0.0


func status_text() -> String:
	return ""
