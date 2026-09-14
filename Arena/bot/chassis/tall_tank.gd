extends ChassisBase
## Tall Tank: two stacked boxes with a turret ring on top. Heavy, high mounting for
## an overhead weapon, and a high centre of mass that tips it (catalogue
## `tip_resistance` 0.6).

const SHOULDER_FRACTION := 0.5      # where the lower box ends, as a fraction of height
const UPPER_INSET_X := 0.09
const UPPER_INSET_Z := 0.05


func com_x() -> float:
	return -0.06


func shoulder_y() -> float:
	return floor_y() + height() * SHOULDER_FRACTION


func shapes() -> Array[Dictionary]:
	var lower := BoxShape3D.new()
	lower.size = Vector3(half_len() * 2.0, shoulder_y() - floor_y(), half_wid() * 2.0)
	var upper := BoxShape3D.new()
	upper.size = Vector3((half_len() - UPPER_INSET_X) * 2.0, top_y() - shoulder_y(),
		(half_wid() - UPPER_INSET_Z) * 2.0)
	return [
		{"shape": lower, "transform": Transform3D(Basis.IDENTITY,
			Vector3(0.0, (floor_y() + shoulder_y()) * 0.5, 0.0))},
		{"shape": upper, "transform": Transform3D(Basis.IDENTITY,
			Vector3(0.0, (shoulder_y() + top_y()) * 0.5, 0.0))},
	]


func hull_points() -> PackedVector3Array:
	var points := BotMeshes.box_points(
		Vector3(half_len() * 2.0, shoulder_y() - floor_y(), half_wid() * 2.0),
		Vector3(0.0, (floor_y() + shoulder_y()) * 0.5, 0.0))
	points.append_array(BotMeshes.box_points(
		Vector3((half_len() - UPPER_INSET_X) * 2.0, top_y() - shoulder_y(),
			(half_wid() - UPPER_INSET_Z) * 2.0),
		Vector3(0.0, (shoulder_y() + top_y()) * 0.5, 0.0)))
	return points


func procedural_meshes() -> Array[Dictionary]:
	return [
		{"mesh": BotMeshes.flat_box_mesh(Vector3(half_len() * 2.0,
			shoulder_y() - floor_y(), half_wid() * 2.0)),
			"transform": Transform3D(Basis.IDENTITY,
				Vector3(0.0, (floor_y() + shoulder_y()) * 0.5, 0.0)), "slot": "livery"},
		{"mesh": BotMeshes.flat_box_mesh(Vector3((half_len() - UPPER_INSET_X) * 2.0,
			top_y() - shoulder_y(), (half_wid() - UPPER_INSET_Z) * 2.0)),
			"transform": Transform3D(Basis.IDENTITY,
				Vector3(0.0, (shoulder_y() + top_y()) * 0.5, 0.0)), "slot": "livery"},
	]
