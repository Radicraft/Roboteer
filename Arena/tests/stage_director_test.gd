extends SceneTree
## Wave A: the stage director's shots, through the real bridge path (docs/wave-a-stage-notes.md).
##   Godot --headless --path Arena --script tests/stage_director_test.gd
##
## `workshop_config` with no `shot` must leave everything as it was (the rig's camera has the
## picture). With a shot the stage's own camera takes it, the turntable follows the shot,
## the face-off stands an opponent in the far slot and retracts the platform, the part
## focus pulls the category's bodies out, `stage_camera` orbits the garage, and a fight
## hands the picture straight back to the rig.

const FIGHT_SCENE := "res://fight/fight.tscn"
const SLICE := "res://qa/stage_slice_bots.json"
const DESIGN_SIZE := Vector2i(1206, 556)

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	# No host is attached in a --script run, so without this the fight autostarts its
	# fixture after 60 frames, builds a new World and takes the stage down mid test.
	fight.set("_autostarted", true)
	var host := SubViewport.new()
	host.size = DESIGN_SIZE
	root.add_child(host)
	host.add_child(fight)
	await process_frame
	await process_frame
	var bots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLICE))
	var hero: Dictionary = bots["hero"]
	var opponent: Dictionary = bots["opponent"]

	# --- legacy: no shot, the rig keeps the picture
	_send({"mode": "menu", "bot": hero})
	await _frames(3)
	var stage: WorkshopStage = fight.get("_workshop_stage") as WorkshopStage
	_check(stage != null, "the fight has a workshop stage")
	if stage == null:
		_finish()
		return
	var director := stage.director()
	_check(director != null, "the stage builds a director")
	var rig: Node = fight.get("_camera_rig")
	var rig_camera: Camera3D = rig.call("camera") as Camera3D
	_check(not director.is_directing(), "no shot: the director is idle")
	var world_vp := director.camera().get_viewport()
	print("world viewport ", world_vp, " ", world_vp.get_visible_rect().size)
	_check(world_vp.get_camera_3d() == rig_camera, "no shot: the rig's camera has the picture")

	# --- M1 showroom
	_send({"mode": "menu", "shot": "showroom", "bot": hero})
	await _frames(3)
	_check(director.shot() == "showroom", "shot showroom is taken")
	_check(world_vp.get_camera_3d() == director.camera(), "the director's camera has the picture")
	_check(is_equal_approx(director.camera().fov, StageDirector.FOV_50MM), "the showroom is a 50 mm lens")
	# Stepped by hand, so the rate is exact whatever the headless frame rate is.
	var a0 := stage.turntable_angle_deg()
	for i in 10:
		stage.call("_process", 0.1)
	var turned := absf(wrapf(stage.turntable_angle_deg() - a0, -180.0, 180.0))
	_check(turned > 3.0 and turned < 7.5, "the showroom turntable turns at about 5 deg/s (%.2f in 1 s)" % turned)
	var width := world_vp.get_visible_rect().size.x
	var hero_px := director.camera().unproject_position(stage.hero_bounds()["centre"])
	_check(absf(hero_px.x / width - 0.5) < 0.06, "the showroom centres the machine (x %.2f)" % (hero_px.x / width))

	# --- face-off with no opponent falls back to the showroom (owner decision)
	_send({"mode": "menu", "shot": "faceoff", "bot": hero})
	await _frames(2)
	_check(director.shot() == "showroom", "a face-off with no opponent is the showroom")
	_check(stage.opponent_bot() == null, "and the opponent's slot is empty")

	# --- M2 face-off
	_send({"mode": "menu", "shot": "faceoff", "bot": hero, "opponent": opponent})
	await _frames(2)
	for i in 12:
		stage.call("_process", 0.1)
		director.call("_process", 0.1)
	_check(director.shot() == "faceoff", "shot faceoff is taken (%s)" % director.shot())
	_check(stage.opponent_bot() != null, "the opponent stands in the far slot")
	_check(stage.platform_share() < 0.01, "the face-off retracts the platform (%.2f)" % stage.platform_share())
	var park := wrapf(stage.turntable_angle_deg() - stage.faceoff_hero_yaw_deg(), -180.0, 180.0)
	_check(absf(park) < 2.0, "the hero is parked facing the opponent (off by %.2f deg)" % park)
	var cam := director.camera()
	var hb: Dictionary = stage.hero_bounds()
	var hx := cam.unproject_position(hb["centre"]).x / width
	var ox := cam.unproject_position(stage.opponent_point()).x / width
	_check(hx > 0.2 and hx < 0.45, "the hero lands on the left (x %.2f)" % hx)
	_check(ox > 0.62 and ox < 0.9, "the opponent lands across the floor on the right (x %.2f)" % ox)
	_check(cam.global_position.y < 0.5, "the face-off lens is low (%.2f m)" % cam.global_position.y)
	var opp_before := stage.opponent_bot()
	_send({"mode": "menu", "shot": "faceoff", "bot": hero, "opponent": opponent})
	await _frames(2)
	_check(stage.opponent_bot() == opp_before, "an unchanged opponent is not rebuilt on every edit")

	# --- G1 garage and stage_camera orbit
	_send({"mode": "workshop", "shot": "garage", "frame": 0.3, "bot": hero})
	await _seconds(1.0)
	_check(director.shot() == "garage", "shot garage is taken (%s, world %s, stage in tree %s)" % [director.shot(), is_instance_valid(world_vp), stage.is_inside_tree()])
	_check(stage.opponent_bot() == null, "leaving the face-off clears the opponent")
	_check(stage.platform_share() > 0.99, "the garage raises the platform again")
	_check(is_equal_approx(director.camera().fov, StageDirector.FOV_40MM), "the garage is a 40 mm lens")
	var pos_before := director.camera().global_position
	_bridge().call("inject_from_host", {"type": "stage_camera", "json": '{"orbit":[80.0,0.0]}'})
	await _frames(3)
	_check(director.camera().global_position.distance_to(pos_before) > 0.05,
		"a forwarded drag orbits the garage camera")
	var held := stage.turntable_angle_deg()
	await _seconds(0.5)
	_check(absf(wrapf(stage.turntable_angle_deg() - held, -180.0, 180.0)) < 0.2,
		"the turntable holds still while a finger was just on it")

	# --- G2 part focus: the weapon comes out of the machine
	var weapon_before := _category_position(stage, "weapon")
	_send({"mode": "workshop", "shot": "part", "focus": "weapon", "frame": 0.3, "bot": hero})
	await _seconds(1.2)
	_check(director.shot() == "part" and director.focus_category() == "weapon", "shot part:weapon is taken")
	_check(is_equal_approx(director.camera().fov, StageDirector.FOV_70MM), "the part focus is a 70 mm lens")
	var weapon_after := _category_position(stage, "weapon")
	_check(weapon_before != Vector3.INF and weapon_after.distance_to(weapon_before) > 0.06,
		"the weapon slides out of the machine (%.3f m)" % weapon_after.distance_to(weapon_before))
	_send({"mode": "workshop", "shot": "garage", "bot": hero})
	await _seconds(0.3)
	_check(stage.pull_share() == 0.0, "leaving the part focus puts the part back")

	# --- attract: the test-fire cue fires once the showroom has been left alone
	_send({"mode": "menu", "shot": "showroom", "bot": hero})
	print("world viewport ", world_vp.get_visible_rect().size)
	var cues := director.attract_count()
	await _seconds(StageDirector.ATTRACT_AFTER_S + StageDirector.ATTRACT_MIN_S + 0.5)
	_check(director.attract_count() > cues, "the showroom plays a test-fire cue when idle")

	# --- a fight takes the picture back
	_send({"mode": "menu", "bot": hero})
	await _frames(2)
	_check(not director.is_directing(), "a workshop_config with no shot releases the director")
	_check(world_vp.get_camera_3d() == rig_camera, "and the rig's camera has the picture again")
	_send({"mode": "menu", "shot": "showroom", "bot": hero})
	await _frames(2)
	stage.set_active(false)
	await _frames(1)
	_check(not director.is_directing(), "the stage going dark releases the director")
	_check(world_vp.get_camera_3d() != director.camera(), "a fight never looks through the stage camera")
	_finish()


func _category_position(stage: WorkshopStage, category: String) -> Vector3:
	var nodes: Array = stage.call("_category_nodes", category)
	if nodes.is_empty():
		return Vector3.INF
	return (nodes[0] as Node3D).global_position


func _send(payload: Dictionary) -> void:
	_bridge().call("inject_from_host", {"type": "workshop_config", "json": JSON.stringify(payload)})


func _bridge() -> Node:
	return root.get_node_or_null("Bridge")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  stage director: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  stage director: %d checks, %d failures" % [_checks, _failures])
		quit(1)
