extends SceneTree
## Timing probe (not a test): how long it takes to load every part model and every
## material the catalogue can ask for, cold, on one thread.
##   Godot --headless --path Arena --script tests/_preload_timing_probe.gd

func _initialize() -> void:
	var manifest: Dictionary = PartsCatalogue.manifest()
	var parts: Dictionary = manifest.get("parts", {}) as Dictionary
	var t0 := Time.get_ticks_usec()
	var loaded := 0
	var worst := 0.0
	var worst_id := ""
	for id in parts.keys():
		var entry: Dictionary = parts[id] as Dictionary
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var a := Time.get_ticks_usec()
		var res := load(path)
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		if res != null:
			loaded += 1
		if ms > worst:
			worst = ms
			worst_id = str(id)
	var t1 := Time.get_ticks_usec()
	print("TIMING %d part models loaded cold: %.1f ms (worst %s at %.1f ms)"
		% [loaded, (t1 - t0) / 1000.0, worst_id, worst])

	var mats := 0
	for slot in PartVisuals.MATERIAL_FILES.keys():
		var path := str(PartVisuals.MATERIAL_FILES[slot])
		if ResourceLoader.exists(path):
			var res := load(path)
			if res != null:
				mats += 1
	var t2 := Time.get_ticks_usec()
	print("TIMING %d materials loaded cold: %.1f ms" % [mats, (t2 - t1) / 1000.0])
	print("TIMING everything: %.1f ms" % ((t2 - t0) / 1000.0))
	quit(0)
