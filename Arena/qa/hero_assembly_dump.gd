extends SceneTree
## Wave A (models): dump where every part model of the hero build sits, in bot space,
## so the Blender review render assembles the machine EXACTLY as the engine does
## (plates on the physics hull's armour anchors, the flipper on the pinned pivot, the
## wheels on the 4wd sockets) rather than on the .glb sockets.
##
## Run: Godot --headless --path Arena --script res://qa/hero_assembly_dump.gd -- OUT.json
## The build is Tinribs, `Arena/fight/fixtures/stage3_config.json` bot 0, which is the
## first build in a new garage (BuildRules.tinribs in the app).

func _initialize() -> void:
	var out_path := "user://hero_assembly.json"
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".json"):
			out_path = a
	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	var bot_cfg: Dictionary = (config["bots"] as Array)[0]
	var host := Node3D.new()
	root.add_child(host)
	var bot: Node3D = (load("res://bot/bot.tscn") as PackedScene).instantiate()
	host.add_child(bot)
	bot.call("setup", bot_cfg, 0, RandomNumberGenerator.new())
	var rows: Array = []
	_collect(bot, bot, rows)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"build": bot_cfg, "parts": rows}, "  "))
	f.close()
	print("hero_assembly_dump: %d models -> %s" % [rows.size(), out_path])
	quit(0)


func _collect(node: Node, bot: Node3D, rows: Array) -> void:
	if node is Node3D and String(node.name) == "FlipperMount":
		var m := _relative(node as Node3D, bot)
		rows.append({"id": "flipper", "only": "mount",
			"origin": [m.origin.x, m.origin.y, m.origin.z],
			"basis_x": [m.basis.x.x, m.basis.x.y, m.basis.x.z],
			"basis_y": [m.basis.y.x, m.basis.y.y, m.basis.y.z],
			"basis_z": [m.basis.z.x, m.basis.z.y, m.basis.z.z],
			"face_material": ""})
		return
	if node is Node3D and String(node.name).begins_with("Model_"):
		var n := node as Node3D
		var t := _relative(n, bot)
		var face_material := ""
		var p := n.get_parent()
		while p != null and p != bot:
			if "material_name" in p and str(p.get("material_name")) != "":
				face_material = str(p.get("material_name"))
				break
			p = p.get_parent()
		var b := t.basis
		rows.append({
			"id": String(n.name).substr(6),
			"origin": [t.origin.x, t.origin.y, t.origin.z],
			"basis_x": [b.x.x, b.x.y, b.x.z],
			"basis_y": [b.y.x, b.y.y, b.y.z],
			"basis_z": [b.z.x, b.z.y, b.z.z],
			"face_material": face_material,
		})
		return
	for c in node.get_children():
		_collect(c, bot, rows)


func _relative(n: Node3D, bot: Node3D) -> Transform3D:
	var t := n.transform
	var walk := n.get_parent() as Node3D
	while walk != null and walk != bot:
		t = walk.transform * t
		walk = walk.get_parent() as Node3D
	return t
