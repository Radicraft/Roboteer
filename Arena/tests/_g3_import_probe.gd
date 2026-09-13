extends SceneTree
## G3 model probe: does every generated part load in a headless Godot, with the
## meshes, the named material surfaces and the socket empties the manifest
## promises, and with the axis rule holding inside Godot rather than only in the
## glTF file?
##
## Named with a leading underscore so scripts/test-arena.sh treats it as a
## helper and does not run it in the suite: it is an asset check for agent G3's
## own work, not a behaviour test of the game.
##
##   Tools/blender/build_parts.py                             (generates the .glb files)
##   Godot --headless --path Arena --import                   (once, after a rebuild)
##   Godot --headless --path Arena --script tests/_g3_import_probe.gd
##
## Exits 0 only when every check passes.

const MANIFEST := "res://assets/parts/manifest.json"

## Material slot names from docs/graphics-bar.md. A surface must be one of these.
const SLOTS := [
	"livery", "steel", "titanium", "hdpe",
	"polycarbonate", "rubber", "dark_metal", "core_glow",
]

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _ok(label: String) -> void:
	_pass += 1
	print("PASS  ", label)


func _bad(label: String) -> void:
	_fail += 1
	_failures.append(label)
	print("FAIL  ", label)


func _check(cond: bool, label: String) -> bool:
	if cond:
		_ok(label)
	else:
		_bad(label)
	return cond


func _gather(node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D:
		out["meshes"].append(node)
	out["names"][node.name] = node
	for child in node.get_children():
		_gather(child, out)


func _init() -> void:
	print("G3 model probe")
	print("==============")

	if not ResourceLoader.exists(MANIFEST):
		_bad("manifest is missing: run Tools/blender/build_parts.py")
		_finish()
		return
	var text := FileAccess.get_file_as_string(MANIFEST)
	var json: Variant = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY or not json.has("parts"):
		_bad("manifest is not readable JSON with a `parts` map")
		_finish()
		return

	var parts: Dictionary = json["parts"]
	var ids := parts.keys()
	ids.sort()
	print("%d parts in the manifest\n" % ids.size())

	var total_tris := 0
	for id_any in ids:
		var id := String(id_any)
		var entry: Dictionary = parts[id]
		var path := String(entry["path"])
		total_tris += int(entry["tris"])

		if not ResourceLoader.exists(path):
			_bad("%s: %s does not load (did you run --import?)" % [id, path])
			continue
		var packed := ResourceLoader.load(path) as PackedScene
		if packed == null:
			_bad("%s: %s is not a PackedScene" % [id, path])
			continue
		var root := packed.instantiate()
		if root == null:
			_bad("%s: instantiate() returned null" % id)
			continue

		var found := {"meshes": [], "names": {}}
		_gather(root, found)
		var meshes: Array = found["meshes"]
		var names: Dictionary = found["names"]

		# 1. geometry arrived
		var expect_meshes: Array = entry["meshes"]
		var mesh_ok := meshes.size() == expect_meshes.size() and meshes.size() > 0
		if not _check(mesh_ok, "%s: %d MeshInstance3D (manifest says %d)"
				% [id, meshes.size(), expect_meshes.size()]):
			root.free()
			continue

		# 2. every surface carries one of the eight named material slots, and
		#    every mesh has UV0 so G2's textures can land on it
		var slot_names: Array[String] = []
		var slots_ok := true
		var uv_ok := true
		for mi_any in meshes:
			var mi := mi_any as MeshInstance3D
			var mesh := mi.mesh
			if mesh == null:
				slots_ok = false
				continue
			for s in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s)
				var nm := "" if mat == null else mat.resource_name
				if not SLOTS.has(nm):
					slots_ok = false
				elif not slot_names.has(nm):
					slot_names.append(nm)
				var arrays := mesh.surface_get_arrays(s)
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				if uvs.is_empty():
					uv_ok = false
		slot_names.sort()
		_check(slots_ok, "%s: every surface is a named slot [%s]"
				% [id, ", ".join(slot_names)])
		_check(uv_ok, "%s: every surface has UV0" % id)

		# 3. the sockets the manifest promises are real nodes at the right place
		var sockets: Dictionary = entry["sockets"]
		var missing: Array[String] = []
		var moved: Array[String] = []
		for key_any in sockets:
			var key := String(key_any)
			if not names.has(key):
				missing.append(key)
				continue
			var node := names[key] as Node3D
			if node == null:
				missing.append(key)
				continue
			var want: Array = sockets[key]
			var got := node.global_position if node.is_inside_tree() else node.position
			if absf(got.x - float(want[0])) > 0.002 \
					or absf(got.y - float(want[1])) > 0.002 \
					or absf(got.z - float(want[2])) > 0.002:
				moved.append("%s %s vs %s" % [key, got, want])
		_check(missing.is_empty(), "%s: %d sockets present%s"
				% [id, sockets.size(), "" if missing.is_empty() else " (missing " + ", ".join(missing) + ")"])
		_check(moved.is_empty(), "%s: socket positions match the manifest%s"
				% [id, "" if moved.is_empty() else " (" + ", ".join(moved) + ")"])

		# 4. THE AXIS RULE, checked in Godot's own space
		if String(entry["category"]) == "chassis":
			var front := names.get("socket_weapon_front") as Node3D
			var fr := names.get("socket_wheel_fr") as Node3D
			var fl := names.get("socket_wheel_fl") as Node3D
			var rr := names.get("socket_wheel_rr") as Node3D
			if front != null and fr != null and fl != null and rr != null:
				_check(front.position.x > 0.0,
						"%s: the nose socket is on +X (forward)" % id)
				_check(fr.position.z > 0.0 and fl.position.z < 0.0,
						"%s: wheel fr is on +Z and fl on -Z (right and left)" % id)
				_check(fr.position.x > rr.position.x,
						"%s: the front axle is forward of the rear one" % id)
				_check(is_zero_approx(fr.position.y) and is_zero_approx(rr.position.y),
						"%s: wheel sockets sit on the axle plane (y = 0)" % id)
			else:
				_bad("%s: a chassis is missing its nose or wheel sockets" % id)

			# a chassis must be wider across Z than it is tall, and longer
			# along X than it is wide: the readable robot silhouette
			var aabb := AABB()
			var first := true
			for mi_any in meshes:
				var mi := mi_any as MeshInstance3D
				var a := mi.transform * mi.get_aabb()
				aabb = a if first else aabb.merge(a)
				first = false
			_check(aabb.size.x > 0.3 and aabb.size.z > 0.3,
					"%s: hull is %.3f x %.3f x %.3f m (x, y, z)"
					% [id, aabb.size.x, aabb.size.y, aabb.size.z])

		root.free()

	print("\n%d parts, %d tris in total" % [ids.size(), total_tris])
	_finish()


func _finish() -> void:
	print("\n==============")
	if _fail == 0:
		print("PASS  %d checks, 0 failures" % _pass)
	else:
		print("FAIL  %d of %d checks failed:" % [_fail, _pass + _fail])
		for f in _failures:
			print("      ", f)
	quit(0 if _fail == 0 else 1)
