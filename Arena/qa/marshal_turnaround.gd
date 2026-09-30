extends SceneTree
## QA only (wave D): the Marshal on a turntable in a plain studio, for docs/look/marshal.html.
##   Godot --path Arena --audio-driver Dummy --resolution 900x700 \
##     --script qa/marshal_turnaround.gd -- --marshal-shots=DIR
## Eight angles with the bar idle, then the bar's states close up: the countdown's three
## blocks, FIGHT, a knockout count at 7 and at 3, POWER DOWN and the card.

var _dir := ""
var _m: FightMarshal = null
var _cam: Camera3D = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		if str(raw).begins_with("--marshal-shots="):
			_dir = str(raw).get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.58)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	env.environment = e
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(rim)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.16, 0.16, 0.17)
	fm.roughness = 0.9
	floor.material_override = fm
	world.add_child(floor)
	_m = FightMarshal.new()
	world.add_child(_m)
	_m.configure(5.0)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	world.add_child(_cam)
	_cam.current = true
	for i in 8:
		var yaw := deg_to_rad(45.0 * i)
		await _pose({"state": "fighting"}, yaw, 25.0, 2.4)
		await _save("turn_%d" % i)
	await _pose({"state": "countdown", "countdown_left": 2.5}, PI, 30.0, 1.5)
	await _save("bar_countdown_3")
	_m.on_fight_start()
	await _pose({"state": "fighting"}, PI, 30.0, 1.5, 3)
	await _save("bar_fight")
	await _pose({"state": "fighting", "ko": {"index": 0, "show": true, "seconds_left": 7}}, PI, 30.0, 1.5, 30)
	await _save("bar_count_7")
	await _pose({"state": "fighting", "ko": {"index": 0, "show": true, "seconds_left": 3}}, PI, 30.0, 1.5, 30)
	await _save("bar_count_3")
	await _pose({"state": "result"}, PI, 30.0, 1.5, 40)
	await _save("bar_power_down")
	_m.show_card(Vector3(0.0, 1.0, -2.0))
	await _pose({"state": "result"}, PI - deg_to_rad(40.0), 20.0, 1.8, 30)
	await _save("card")
	quit(0)


## Hold the Marshal still at 1 m, facing the camera at `yaw` around it, and let the bar settle.
func _pose(facts: Dictionary, yaw: float, pitch_deg: float, dist: float, frames: int = 12) -> void:
	var at := Vector3(0.0, 1.0, 0.0)
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var cam_pos := at + dir * dist * cos(deg_to_rad(pitch_deg)) + Vector3.UP * dist * sin(deg_to_rad(pitch_deg))
	facts["camera"] = cam_pos
	for i in frames:
		_m.step(1.0 / 60.0, facts)
		_m.set("_pos", at)
		_m.set("_vel", Vector3.ZERO)
		_m.set("_lean", Vector2.ZERO)
		_m.transform = Transform3D(Basis.IDENTITY, at)
		_cam.look_at_from_position(cam_pos, at, Vector3.UP)
		await process_frame
	await process_frame


func _save(file_name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(_dir.path_join(file_name + ".png"))
	print("marshal_turnaround: ", file_name)
