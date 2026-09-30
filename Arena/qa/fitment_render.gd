extends Node3D
## Wave C fitment contact sheet: real Godot renders of assembled machines, a 3/4 view and
## a side view each (plus a front view and a "weapon turned" view on request), on a plain
## grey floor under neutral light so a part's fit is all there is to look at.
##
##   Godot --audio-driver Dummy --path Arena res://qa/fitment_render.tscn -- \
##       --fit-list=LIST.json --fit-out=DIR [--fit-size=560x400]
##
## LIST.json is an array of {"name": "...", "config": {bot config}, "views": ["q", "s",
## "f", "t", "spin"]}. "q" = 3/4 front right, "s" = right side, "f" = nose on, "t" = top,
## "spin" = 3/4 with every hinged weapon body turned 90 degrees about its hinge (a saw's
## drawn arm goes round with its blade: this is how that shows).
## Files: DIR/<name>_<view>.png. Physics is switched off, so every body stays exactly
## where `Bot.setup` put it; the machine sits with its wheels on the floor.

const BOT_SCENE := "res://bot/bot.tscn"
const VIEWS := {
	# name: [yaw_deg from the nose toward the right side, pitch_deg down, distance, fov]
	"q": [40.0, 24.0, 1.75, 30.0],
	"s": [90.0, 4.0, 1.8, 30.0],
	"f": [0.0, 8.0, 1.8, 30.0],
	"t": [90.0, 89.0, 1.9, 30.0],
	"r": [150.0, 22.0, 1.8, 30.0],
	"dq": [35.0, 30.0, 1.0, 30.0],
	"dr": [160.0, 30.0, 1.0, 30.0],
	"ns": [90.0, 3.0, 0.9, 30.0],
	"nq": [25.0, 16.0, 1.0, 30.0],
	"spin": [40.0, 24.0, 1.75, 30.0],
}

var _list: Array = []
var _out := ""
var _size := Vector2i(560, 400)
var _vp: SubViewport = null
var _cam: Camera3D = null
var _host: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fit-list="):
			_list = JSON.parse_string(FileAccess.get_file_as_string(a.substr(11)))
		elif a.begins_with("--fit-out="):
			_out = a.substr(10)
		elif a.begins_with("--fit-size="):
			var p := a.substr(11).split("x")
			_size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	PhysicsServer3D.set_active(false)
	_build_set()
	_run()


func _build_set() -> void:
	_vp = SubViewport.new()
	_vp.size = _size
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.83, 0.84, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, -140.0, 0.0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.62, 0.63, 0.65)
	fm.roughness = 0.9
	floor_mesh.material_override = fm
	_vp.add_child(floor_mesh)
	# a 10 cm grid on the floor, so a gap or an overhang has a scale next to it
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-20, 21):
		var v := float(i) * 0.1
		im.surface_add_vertex(Vector3(v, 0.001, -2.0))
		im.surface_add_vertex(Vector3(v, 0.001, 2.0))
		im.surface_add_vertex(Vector3(-2.0, 0.001, v))
		im.surface_add_vertex(Vector3(2.0, 0.001, v))
	im.surface_end()
	grid.mesh = im
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.5, 0.51, 0.53)
	grid.material_override = gm
	_vp.add_child(grid)
	_host = Node3D.new()
	_vp.add_child(_host)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true


func _run() -> void:
	for i in range(8):
		await RenderingServer.frame_post_draw
	var n := 0
	for entry_variant in _list:
		var entry: Dictionary = entry_variant
		var bot: Node3D = (load(BOT_SCENE) as PackedScene).instantiate()
		_host.add_child(bot)
		bot.call("setup", entry["config"], 0, RandomNumberGenerator.new())
		bot.call("place_on", Vector3.ZERO, Vector3.RIGHT)
		for hide_name in entry.get("hide", []):
			var hidden := bot.find_child(str(hide_name), true, false) as Node3D
			if hidden != null:
				hidden.visible = false
		var centre := _centre(bot)
		var views: Array = entry.get("views", ["q", "s"])
		for view in views:
			if view == "spin":
				_turn_hinged(bot, -deg_to_rad(float(entry.get("spin_deg", 90.0))))
			var c2 := centre
			if str(view).begins_with("d"):
				c2 = centre + Vector3(-0.22, 0.12, 0.0)
			elif str(view).begins_with("n"):
				c2 = centre + Vector3(0.33, -0.06, 0.0)
			_aim(str(view), c2)
			for i in range(3):
				await RenderingServer.frame_post_draw
			var img := _vp.get_texture().get_image()
			img.save_png(_out.path_join("%s_%s.png" % [entry["name"], view]))
			if view == "spin":
				_turn_hinged(bot, deg_to_rad(float(entry.get("spin_deg", 90.0))))
		_host.remove_child(bot)
		bot.free()
		n += 1
	print("fitment_render: %d machines -> %s" % [n, _out])
	get_tree().quit(0)


func _centre(bot: Node3D) -> Vector3:
	var chassis := bot.get("chassis") as Node3D
	var c := chassis.global_position if chassis != null else Vector3.ZERO
	return Vector3(c.x + 0.05, 0.12, c.z)


func _aim(view: String, centre: Vector3) -> void:
	var v: Array = VIEWS.get(view, VIEWS["q"])
	var yaw := deg_to_rad(float(v[0]))
	var pitch := deg_to_rad(float(v[1]))
	var dist := float(v[2])
	var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
	_cam.fov = float(v[3])
	var up := Vector3.UP if absf(float(v[1])) < 85.0 else Vector3.RIGHT
	_cam.look_at_from_position(centre + dir * dist, centre, up)


## Turn every hinged weapon body about its own hinge (presentation only: physics is off).
func _turn_hinged(bot: Node3D, angle: float) -> void:
	var joints := bot.find_child("Joints", true, false)
	if joints == null:
		return
	for j in joints.get_children():
		var hinge := j as HingeJoint3D
		if hinge == null or String(hinge.name).begins_with("JointWheel"):
			continue
		var body := hinge.get_node_or_null(hinge.node_b) as Node3D
		if body == null:
			continue
		var axis := hinge.global_transform.basis.z.normalized()
		var pivot := hinge.global_transform.origin
		var rot := Basis(axis, angle)
		var t := body.global_transform
		body.global_transform = Transform3D(rot * t.basis, rot * (t.origin - pivot) + pivot)
