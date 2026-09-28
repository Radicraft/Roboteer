extends Node3D
## QA only (docs/wave-c-menus-notes.md): the REAL menu stage in the arena staging, posed
## for one screen exactly as the shell poses it (a `workshop_config` with `screen`), saved
## as a frame plus the `stage_anchors` the shell would receive for it.
##
##   Godot --path Arena --audio-driver Dummy --resolution 1912x880 res://qa/menus_arena_capture.tscn -- \
##     --mc-screen=menu|builder|shop|board|result|career|... --mc-out=/path/frame.png \
##     [--mc-at=6.0] [--mc-tier=high|medium|low] [--mc-focus=weapon] [--mc-cue=win]
##     [--mc-fire=T]   fire the arrival jets T seconds in (a capture of the jet mid burn)
##     [--mc-build=STEP[:F]]   hold the loading screen's build at a row (the handover)
##     [--mc-from=screen:T]    start on another screen and switch at T (a move in progress)
##     [--mc-noblueprint] [--mc-measure]
##
## Writes <out>.json next to the frame: the anchors (normalised, as sent to the shell) and
## the frame's costs (draw calls, objects, lights, particles, venue build ms).

const SLICE := "res://qa/stage_slice_bots.json"

var screen := "menu"
var out := ""
var at := 6.0
var focus := ""
var cue := ""
var fire_at := -1.0
var from_screen := ""
var switch_at := -1.0
var measure := false
## --mc-look=key:value,... overrides the screen profile (StageDirector.SCREEN_PROFILES).
var look := {}
var stage: WorkshopStage = null
var _t := 0.0
var _saved := false
var _fired := false
var _switched := false
var _bots := {}
var _build_ms := 0.0
var _cpu := 0.0
var _frames := 0


func _ready() -> void:
	var tier := ""
	var build_pose := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mc-screen="):
			screen = a.get_slice("=", 1)
		elif a.begins_with("--mc-out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--mc-at="):
			at = float(a.get_slice("=", 1))
		elif a.begins_with("--mc-tier="):
			tier = a.get_slice("=", 1)
		elif a.begins_with("--mc-focus="):
			focus = a.get_slice("=", 1)
		elif a.begins_with("--mc-cue="):
			cue = a.get_slice("=", 1)
		elif a.begins_with("--mc-fire="):
			fire_at = float(a.get_slice("=", 1))
		elif a.begins_with("--mc-build="):
			build_pose = a.get_slice("=", 1)
		elif a.begins_with("--mc-from="):
			var spec := a.get_slice("=", 1).split(":")
			from_screen = spec[0]
			switch_at = float(spec[1]) if spec.size() > 1 else 1.0
		elif a == "--mc-measure":
			measure = true
		elif a.begins_with("--mc-look="):
			for kv in a.get_slice("=", 1).split(",", false):
				var p := kv.split(":")
				if p.size() == 2:
					look[p[0]] = float(p[1])
		elif a.begins_with("--mc-venue="):
			for kv in a.get_slice("=", 1).split(",", false):
				var p := kv.split(":")
				if p.size() == 2:
					MenuVenue.qa[p[0]] = float(p[1])
				elif p.size() == 4:
					MenuVenue.qa[p[0]] = Vector3(float(p[1]), float(p[2]), float(p[3]))
	if tier != "":
		VenueKit.force_tier = tier
	stage = WorkshopStage.new()
	stage.name = "Stage"
	if tier != "":
		stage.force_quality_tier(tier)
	var rig: Node3D = (load("res://ui/camera_rig.tscn") as PackedScene).instantiate()
	rig.name = "CameraRig"
	add_child(rig)
	add_child(stage)
	rig.call("set_mode", "workshop")
	rig.call("set_frame_bias", 0.28)
	_bots = JSON.parse_string(FileAccess.get_file_as_string(SLICE))
	stage.show_bot(_bots.get("hero", {}))
	if build_pose != "":
		var pose := build_pose.split(":")
		stage.set_build_step(int(pose[0]), float(pose[1]) if pose.size() > 1 else 0.0)
	var t0 := Time.get_ticks_usec()
	_present(from_screen if from_screen != "" else screen)
	_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	process_priority = 100


func _present(name_: String) -> void:
	var payload := {"bot": _bots.get("hero", {}), "screen": name_}
	if name_ == "board":
		payload["opponent"] = _bots.get("opponent", {})
	if name_ in ["shop", "builder"]:
		payload["focus"] = focus if focus != "" else "weapon"
	if cue != "" and name_ == screen:
		payload["cue"] = cue
	stage.apply_presentation(payload)
	if not look.is_empty() and stage.director() != null:
		var prof: Dictionary = StageDirector.profile_for(name_).duplicate()
		for k in look.keys():
			prof[k] = look[k]
		var opts := {"profile": prof, "screen": name_}
		if payload.has("focus"):
			opts["focus"] = payload["focus"]
		stage.director().set_shot(str(prof.get("shot", "showroom")), opts)


func _process(delta: float) -> void:
	_t += delta
	if measure and _t > 3.0 and _t < at:
		_cpu += delta
		_frames += 1
	if not _switched and switch_at > 0.0 and _t >= switch_at:
		_switched = true
		_present(screen)
	if not _fired and fire_at >= 0.0 and _t >= fire_at:
		_fired = true
		var v := stage.menu_venue()
		if v != null:
			for j in v.call("jets"):
				(j as MenuPyro).fire(cue == "win")
	if _saved or _t < at:
		return
	_saved = true
	var img := get_viewport().get_texture().get_image()
	if out != "":
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		img.save_png(out)
	var info := stage.stage_anchors()
	var rid := get_viewport().get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var cost := {
		"draw_calls": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"lights": _count_lights(), "particles": _count_particles(), "venue_build_ms": snappedf(_build_ms, 0.1),
		"tier": stage.quality_tier(), "staged": stage.staged(),
		"video_mem_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.1),
	}
	if measure and _frames > 0:
		cost["mean_frame_ms"] = snappedf(_cpu / float(_frames) * 1000.0, 0.01)
	var v := stage.menu_venue()
	if v != null and v.get("kit") != null and (v.get("kit") as Node).has_method("stats"):
		cost["kit"] = (v.get("kit") as Node).call("stats")
	info["cost"] = cost
	if out != "":
		var f := FileAccess.open(out.get_basename() + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(info, "  "))
	print("mc_anchors ", JSON.stringify(info))
	get_tree().quit()


func _count_lights() -> Dictionary:
	var d := {"visible": 0, "shadowed": 0}
	for c in find_children("*", "Light3D", true, false):
		var l := c as Light3D
		if l.is_visible_in_tree() and l.light_energy > 0.0:
			d["visible"] += 1
			if l.shadow_enabled:
				d["shadowed"] += 1
	return d


func _count_particles() -> Dictionary:
	var d := {"emitters": 0, "amount": 0}
	for c in find_children("*", "GPUParticles3D", true, false):
		var g := c as GPUParticles3D
		if g.is_visible_in_tree() and g.emitting:
			d["emitters"] += 1
			d["amount"] += g.amount
	return d
