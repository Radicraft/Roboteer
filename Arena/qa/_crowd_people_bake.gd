extends SceneTree
## Tool, not shipped (qa/_* is excluded from the export). Turns the Blender exporter's JSON
## into the binary resource the game loads:
##   Godot --headless --path Arena --script qa/_crowd_people_bake.gd -- \
##     ../Tools/blender/arena_kit/crowd_out/crowd_people.json
## Output: res://arena/kit/crowd/crowd_people.res (CrowdPeopleData).

const OUT := "res://arena/kit/crowd/crowd_people.res"


func _init() -> void:
	var src := "../Tools/blender/arena_kit/crowd_out/crowd_people.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		src = args[0]
	var path := ProjectSettings.globalize_path("res://").path_join(src) if src.begins_with("..") else src
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("crowd bake: cannot read " + path)
		quit(1)
		return
	var d: Dictionary = parsed
	var data := CrowdPeopleData.new()
	data.frames = int(d["frames"])
	var lo: Array = d["pos_min"]
	var hi: Array = d["pos_max"]
	data.pos_min = Vector3(lo[0], lo[1], lo[2])
	data.pos_max = Vector3(hi[0], hi[1], hi[2])
	var clips: Dictionary = d["clips"]
	for k in clips.keys():
		var c: Dictionary = clips[k]
		data.clips[k] = Vector3(float(c["start"]), float(c["count"]), float(c.get("step_s", 1.0 / 12.0)))
	var aabb := AABB(data.pos_min, data.pos_max - data.pos_min)
	for pv in d["people"]:
		var p: Dictionary = pv
		data.names.append(str(p["name"]))
		data.heights.append(float(p["height_m"]))
		data.meshes.append(_mesh(p, p["indices"], aabb))
		data.far_meshes.append(_mesh(p, p["lod1"], aabb))
	var err := ResourceSaver.save(data, OUT, ResourceSaver.FLAG_COMPRESS)
	print("crowd bake: ", data.names.size(), " people, ", data.frames, " frames -> ", OUT, " (", err, ")")
	quit(0 if err == OK else 1)


func _mesh(p: Dictionary, src: Array, aabb: AABB) -> ArrayMesh:
	var nv := int(p["verts"])
	var colour: Array = p["colour"]
	var zone: Array = p["zone"]
	var col0 := int(p["col"])
	var row0 := int(p["row"])
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	verts.resize(nv)
	cols.resize(nv)
	uv.resize(nv)
	uv2.resize(nv)
	for i in range(nv):
		verts[i] = Vector3(0.0, 1.0, 0.0)
		cols[i] = Color8(int(colour[i * 3]), int(colour[i * 3 + 1]), int(colour[i * 3 + 2]))
		uv[i] = Vector2(float(col0 + i) + 0.5, float(row0) + 0.5)
		uv2[i] = Vector2(float(zone[i]), 0.0)
	# Blender winds front faces counter-clockwise, Godot clockwise: swap two corners.
	var idx := PackedInt32Array()
	idx.resize(src.size())
	for t in range(0, src.size(), 3):
		idx[t] = int(src[t])
		idx[t + 1] = int(src[t + 2])
		idx[t + 2] = int(src[t + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(aabb.position * 1.2, aabb.size * 1.2)
	return mesh
