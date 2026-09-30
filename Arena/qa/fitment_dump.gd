extends SceneTree
## Wave C fitment harness, half 1 of 2: assemble every chassis with every part it can
## take, in every slot, at every allowed count, and dump where every drawn mesh and
## every collider ended up, in BOT SPACE. Nothing here judges anything: the geometry
## checks run in `Tools/fitment/fitment_check.py`, which reads this dump (numpy is far
## better at a million point-in-mesh tests than GDScript is).
##
##   Godot --headless --path Arena --script res://qa/fitment_dump.gd -- OUT_DIR [sweep]
##
## OUT_DIR gets `configs.jsonl` (one assembled machine per line) and `meshes.json`
## (each distinct mesh's triangles, written once, keyed by resource path or content
## hash). `sweep` limits the run to one of: weapons, drives, utility, armour, owner.
##
## The machine is built exactly as a fight and the garage stage build it
## (`bot.tscn` + `Bot.setup`), placed at the origin with an identity transform and read
## BEFORE the first physics step, so every body is still where the assembler put it.

const BOT_SCENE := "res://bot/bot.tscn"

var _out_dir := ""
var _sweep := ""
var _meshes := {}            # key -> {"v": [...], "i": [...]}
var _mesh_keys := {}         # Mesh instance id -> key (resources are shared, so cache)
var _lines := PackedStringArray()
var _count := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if _out_dir == "":
			_out_dir = a
		else:
			_sweep = a
	if _out_dir == "":
		_out_dir = "user://fitment"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _run() -> void:
	await process_frame
	var host := Node3D.new()
	host.name = "FitHost"
	root.add_child(host)
	var configs := _configs()
	print("fitment_dump: %d configs (sweep %s)" % [configs.size(),
		_sweep if _sweep != "" else "all"])
	var f := FileAccess.open(_out_dir.path_join("configs.jsonl"), FileAccess.WRITE)
	for entry in configs:
		var row := _assemble(host, entry)
		f.store_line(JSON.stringify(row))
		_count += 1
		if _count % 100 == 0:
			print("  %d / %d" % [_count, configs.size()])
			await process_frame
	f.close()
	var m := FileAccess.open(_out_dir.path_join("meshes.json"), FileAccess.WRITE)
	m.store_string(JSON.stringify(_meshes))
	m.close()
	print("fitment_dump: %d machines, %d meshes -> %s" % [_count, _meshes.size(), _out_dir])
	quit(0)


# ---------------------------------------------------------------------------
# The matrix
# ---------------------------------------------------------------------------
func _legal_weapons(chassis_id: String) -> Array:
	var out := []
	var row := PartsCatalogue.chassis(chassis_id)
	var allowed: Array = row.get("weapons_allowed", []) as Array
	for w in PartsCatalogue.ids("weapon"):
		var spec := PartsCatalogue.weapon(str(w))
		if not allowed.is_empty() and not allowed.has(w):
			continue
		var req := str(spec.get("requires_chassis", ""))
		if req != "" and req != chassis_id:
			continue
		out.append(str(w))
	return out


## Every legal utility fit, in both orders (the order is the claim order of the two
## utility sockets, and a player can fit them either way round).
func _utility_sets(chassis_id: String) -> Array:
	var ids := PartsCatalogue.ids("utility")
	var needs_srimech := not bool(PartsCatalogue.chassis(chassis_id).get("invertible", false))
	var out := []
	if needs_srimech:
		out.append(["srimech"])
		for u in ids:
			if u == "srimech":
				continue
			out.append(["srimech", u])
			out.append([u, "srimech"])
	else:
		out.append([])
		for a in ids:
			out.append([a])
			for b in ids:
				if a != b:
					out.append([a, b])
	return out


func _base_utility(chassis_id: String) -> Array:
	return [] if bool(PartsCatalogue.chassis(chassis_id).get("invertible", false)) \
		else ["srimech"]


func _armour(material: String, thickness: int) -> Dictionary:
	var out := {}
	for face in BuildRules.FACES:
		out[face] = {"material": material, "thickness": thickness}
	return out


func _cfg(sweep: String, chassis_id: String, drive_id: String, weapon_id: String,
		utility: Array, material: String, thickness: int) -> Dictionary:
	return {"sweep": sweep, "config": {
		"id": "fit", "name": "Fit", "controller": "player",
		"chassis": chassis_id, "drive": drive_id, "weapon": weapon_id,
		"utility": utility, "armour": _armour(material, thickness),
		"livery": "#C8C8C8"}}


func _configs() -> Array:
	var out := []
	var chassis_ids := PartsCatalogue.ids("chassis")
	var drives := PartsCatalogue.ids("drive")
	for c in chassis_ids:
		var weapons := _legal_weapons(c)
		var base_u := _base_utility(c)
		# 1. Every weapon on every drive (weapon vs wheels, tracks, legs, fans).
		if _sweep in ["", "drives"]:
			for d in drives:
				for w in weapons:
					out.append(_cfg("drives", c, d, w, base_u, "steel", 2))
		# 2. Every weapon at both armour extremes (a ramped nose lifts the front
		#    weapon by the plate stack) and with the scoop on the nose.
		if _sweep in ["", "weapons"]:
			for w in weapons:
				for t in [1, 4]:
					out.append(_cfg("weapons", c, "4wd", w, base_u, "steel", t))
				var scooped := base_u.duplicate()
				scooped.append("scoop")
				out.append(_cfg("weapons", c, "4wd", w, scooped, "steel", 4))
		# 3. Every legal utility fit, both orders, against every weapon.
		if _sweep in ["", "utility"]:
			for u in _utility_sets(c):
				for w in weapons:
					out.append(_cfg("utility", c, "4wd", w, u, "steel", 2))
			# and against every drive (skirts and magnets live down by the wheels)
			for u in _utility_sets(c):
				for d in drives:
					if d == "4wd":
						continue
					out.append(_cfg("utility", c, d, weapons[0], u, "steel", 2))
		# 4. Every armour material at every thickness.
		if _sweep in ["", "armour"]:
			for mat in PartsCatalogue.armour_materials():
				for t in [1, 2, 3, 4]:
					var u2 := base_u.duplicate()
					if not u2.has("spare_battery"):
						u2.append("spare_battery")
					out.append(_cfg("armour", c, "4wd", weapons[0], u2, str(mat), t))
	# 0. The machines the owner actually looks at: the menu stage's hero and its
	#    opponents (qa/stage_slice_bots.json), the stage 3 fixture pair.
	if _sweep in ["", "owner", "hero"]:
		var slice: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://qa/stage_slice_bots.json"))
		for key in slice.keys():
			if slice[key] is Dictionary and (slice[key] as Dictionary).has("chassis"):
				out.append({"sweep": "hero", "config": slice[key]})
	# 5. The owner's two reports, first: a spare battery on a box, a saw on the nose.
	if _sweep in ["", "owner"]:
		for d in drives:
			out.append(_cfg("owner", "box", d, "saw", ["srimech", "spare_battery"], "steel", 1))
			out.append(_cfg("owner", "box", d, "saw", ["spare_battery", "srimech"], "steel", 4))
	return out


# ---------------------------------------------------------------------------
# One machine
# ---------------------------------------------------------------------------
func _assemble(host: Node3D, entry: Dictionary) -> Dictionary:
	var cfg: Dictionary = entry["config"]
	var bot: Node3D = (load(BOT_SCENE) as PackedScene).instantiate()
	host.add_child(bot)
	bot.call("setup", cfg, 0, RandomNumberGenerator.new())
	var inv := bot.global_transform.affine_inverse()
	var meshes := []
	var shapes := []
	var joints := []
	_walk(bot, bot, inv, meshes, shapes, joints)
	var cm: Object = bot.get("chassis_module")
	var info := {
		"floor_y": cm.call("floor_y"), "top_y": cm.call("top_y"),
		"half_len": cm.call("half_len"), "half_wid": cm.call("half_wid"),
		"ride_height": bot.call("ride_height"),
		"weapon_mount": str((bot.get("weapon") as Object).get("spec").get("mount", ""))
			if bot.get("weapon") != null else "",
	}
	var row := {"sweep": entry["sweep"], "config": cfg, "info": info,
		"errors": bot.get("build_errors"), "meshes": meshes, "shapes": shapes,
		"joints": joints}
	host.remove_child(bot)
	bot.free()
	return row


func _xf(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z]


## The nearest ancestors that name what this node belongs to: the physics body
## (BotPart or any RigidBody3D) and the part model (`Model_<id>`).
func _owners(node: Node, bot: Node) -> Dictionary:
	var body := ""
	var model := ""
	var walk := node
	while walk != null and walk != bot:
		var n := String(walk.name)
		if model == "" and n.begins_with("Model_"):
			model = n.substr(6)
		if body == "" and walk is RigidBody3D:
			body = n
		walk = walk.get_parent()
	return {"body": body, "model": model}


func _walk(node: Node, bot: Node3D, inv: Transform3D, meshes: Array, shapes: Array,
		joints: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			var own := _owners(mi, bot)
			meshes.append({"key": _mesh_key(mi.mesh), "node": String(mi.name),
				"body": own["body"], "model": own["model"],
				"xf": _xf(inv * mi.global_transform)})
	elif node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape != null and not cs.disabled:
			var parent := cs.get_parent()
			if parent is CollisionObject3D and not (parent is Area3D):
				shapes.append(_shape_row(cs, inv, _owners(cs, bot)))
	elif node is HingeJoint3D:
		var j := node as HingeJoint3D
		var b := j.get_node_or_null(j.node_b)
		joints.append({"name": String(j.name), "xf": _xf(inv * j.global_transform),
			"body": String(b.name) if b != null else "",
			"limit": j.get_flag(HingeJoint3D.FLAG_USE_LIMIT),
			"lower": j.get_param(HingeJoint3D.PARAM_LIMIT_LOWER),
			"upper": j.get_param(HingeJoint3D.PARAM_LIMIT_UPPER)})
	for c in node.get_children():
		_walk(c, bot, inv, meshes, shapes, joints)


func _shape_row(cs: CollisionShape3D, inv: Transform3D, own: Dictionary) -> Dictionary:
	var s := cs.shape
	var row := {"body": own["body"], "xf": _xf(inv * cs.global_transform)}
	if s is BoxShape3D:
		row["type"] = "box"
		var e := (s as BoxShape3D).size
		row["size"] = [e.x, e.y, e.z]
	elif s is CylinderShape3D:
		row["type"] = "cylinder"
		row["radius"] = (s as CylinderShape3D).radius
		row["height"] = (s as CylinderShape3D).height
	elif s is SphereShape3D:
		row["type"] = "sphere"
		row["radius"] = (s as SphereShape3D).radius
	elif s is CapsuleShape3D:
		row["type"] = "capsule"
		row["radius"] = (s as CapsuleShape3D).radius
		row["height"] = (s as CapsuleShape3D).height
	elif s is ConvexPolygonShape3D:
		row["type"] = "convex"
		var pts := []
		for p in (s as ConvexPolygonShape3D).points:
			pts.append_array([p.x, p.y, p.z])
		row["points"] = pts
	else:
		row["type"] = s.get_class()
	return row


func _mesh_key(mesh: Mesh) -> String:
	var iid := mesh.get_instance_id()
	if _mesh_keys.has(iid):
		return _mesh_keys[iid]
	var verts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var base := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ind: Variant = arrays[Mesh.ARRAY_INDEX]
		for p in v:
			verts.append(p.x)
			verts.append(p.y)
			verts.append(p.z)
		if ind is PackedInt32Array and (ind as PackedInt32Array).size() > 0:
			for i in (ind as PackedInt32Array):
				idx.append(base + i)
		else:
			for i in range(v.size()):
				idx.append(base + i)
		base += v.size()
	var key := mesh.resource_path
	if key == "" or key.contains("::"):
		# Imported sub-resources and procedural meshes: key on the content, so the
		# same procedural wheel built for 900 machines is written once.
		key = "%s#%d" % [key, hash(var_to_bytes(verts))]
	_mesh_keys[iid] = key
	if not _meshes.has(key):
		_meshes[key] = {"v": Array(verts), "i": Array(idx)}
	return key
