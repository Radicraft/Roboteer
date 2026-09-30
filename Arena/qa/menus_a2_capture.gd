extends Node3D
## QA only (docs/look/menus-blueprint-A2.html): the menus A2 staging variants. The live
## workshop stage (the machine, the plinth, the director's shots) stays at the origin and
## the scene AROUND it changes per variant, so every screen keeps the camera the shell
## already uses and only the world behind the machine moves.
##
##   Godot --path Arena --audio-driver Dummy --resolution 1912x880 res://qa/menus_a2_capture.tscn -- \
##     --a2-variant=showroom|arena|gate|pit --a2-screen=menu|builder|shop|board|result \
##     --a2-out=/path/frame.png [--a2-at=7.5] [--a2-dump]
##
## After the frame is saved it prints one `a2_anchors {json}` line: the screen position of
## the parts the page's leader lines point at (weapon, each wheel, each armour panel, the
## hull top, the opponent), and the frame's draw calls, so the page can land its leaders
## on the render it is laid over. Not referenced by any shipped scene.

const SLICE := "res://qa/stage_slice_bots.json"
## The projector gobo lives with the page, not in the pack.
const BLUEPRINT_PNG := "res://../docs/look/menus-bp-a2/blueprint-projector.png"

var variant := "showroom"
var screen := "menu"
var out := ""
var at := 7.5
var dump := false
var stage: WorkshopStage = null
var rig: Node3D = null
var venue: Node3D = null
var _t := 0.0
var _saved := false
var _extra: Array = []          # [{node, kind}] animated by this scene
var _pyro_kit: Node = null
var _look := {}                  # --a2-look=key:value,... quick look-dev dials
var _bots := {}
var _cam: Camera3D = null
var _cam_attr: CameraAttributesPractical = null
## Per screen camera, as the stage director frames it (docs/wave-a-stage-notes.md) with
## the menu camera's pose from camera_rig "menu". yaw 0 = camera on +Z, degrees; dist
## metres from the hero centre (or the weapon for the shop); fx = where the target lands
## across the frame; top = how far down; turn = the turntable angle. A variant overrides
## any of these in _shot.
const SHOTS := {
	"menu": {"yaw": 26.0, "pitch": 17.7, "fov": 28.0, "dist": 4.8, "fx": 0.28, "top": 0.5, "turn": 25.0, "dof": 0.0},
	"builder": {"yaw": 38.0, "pitch": 11.0, "fov": 33.4, "dist": 1.75, "fx": 0.31, "top": 0.5, "turn": 22.0, "dof": 0.7},
	"shop": {"yaw": 28.0, "pitch": 20.0, "fov": 19.5, "dist": 2.0, "fx": 0.45, "top": 0.52, "turn": -70.0, "dof": 0.35},
	"board": {"yaw": -18.0, "pitch": 1.0, "fov": 27.0, "dist": 2.3, "fx": 0.3, "top": 0.36, "turn": 0.0, "dof": 1.6},
	"result": {"yaw": 28.0, "pitch": 8.0, "fov": 27.0, "dist": 2.6, "fx": 0.5, "top": 0.44, "turn": 15.0, "dof": 0.7},
}
var _shot := {}
var _td: Camera3D = null
var _marks: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--a2-variant="):
			variant = a.get_slice("=", 1)
		elif a.begins_with("--a2-screen="):
			screen = a.get_slice("=", 1)
		elif a.begins_with("--a2-out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--a2-at="):
			at = float(a.get_slice("=", 1))
		elif a == "--a2-dump":
			dump = true
		elif a.begins_with("--a2-look="):
			for kv in a.get_slice("=", 1).split(",", false):
				var p := kv.split(":")
				if p.size() == 2:
					_look[p[0]] = float(p[1])
	stage = WorkshopStage.new()
	stage.name = "Stage"
	rig = (load("res://ui/camera_rig.tscn") as PackedScene).instantiate()
	rig.name = "CameraRig"
	add_child(rig)
	add_child(stage)
	var bots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLICE))
	_bots = bots
	stage.show_bot(bots.get("hero", {}))
	stage.set_auto_rotate(false)
	rig.call("set_mode", "workshop")
	if screen == "board":
		stage.show_opponent(bots.get("opponent", {}))
	if screen == "shop":
		stage._set_pull_focus("weapon")
	_cam = Camera3D.new()
	_cam.name = "A2Camera"
	_cam.near = 0.05
	_cam.far = 300.0
	add_child(_cam)
	_cam_attr = CameraAttributesPractical.new()
	_cam.attributes = _cam_attr
	process_priority = 100
	match variant:
		"showroom":
			_variant_showroom()
		"arena":
			_variant_arena()
		"gate":
			_variant_gate()
		"pit":
			_variant_pit()
	if dump:
		_dump(stage, 0)
		if venue != null:
			print("--- venue")
			_dump(venue, 0)


func _process(delta: float) -> void:
	_t += delta
	_tick_extra(delta)
	_place_camera()
	if _saved or _t < at:
		return
	# A pyro burst needs a few frames to rise: never shoot the frame it was fired on.
	for e in _extra:
		if str(e["kind"]) == "fire" and (not bool(e.get("done", false)) or _t - float(e.get("fired_at", -9.0)) < 0.4):
			return
	_saved = true
	var cam := get_viewport().get_camera_3d()
	var img := get_viewport().get_texture().get_image()
	if out != "":
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		img.save_png(out)
	var info := _anchors(cam, img.get_size())
	var rid := get_viewport().get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	info["draw_calls"] = RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	info["objects"] = RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	info["primitives"] = RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	info["lights"] = _count_lights(self)
	info["particles"] = _count_particles(self)
	info["fog_volumes"] = find_children("*", "FogVolume", true, false).filter(
		func(n: Node) -> bool: return (n as Node3D).is_visible_in_tree()).size()
	info["cam"] = [cam.global_position, cam.fov, cam.h_offset] if cam != null else []
	print("a2_anchors ", JSON.stringify(info))
	get_tree().quit()


# ---------------------------------------------------------------- anchors

func _anchors(cam: Camera3D, size: Vector2i) -> Dictionary:
	var out_d := {"size": [size.x, size.y], "variant": variant, "screen": screen}
	if cam == null:
		return out_d
	var p := func(v: Vector3) -> Array:
		var s := cam.unproject_position(v)
		return [snappedf(s.x, 0.5), snappedf(s.y, 0.5), cam.is_position_behind(v)]
	out_d["weapon"] = p.call(stage.weapon_point())
	out_d["weapon_focus"] = p.call(stage.part_focus("weapon")["centre"])
	var hb := stage.hero_bounds()
	var top: Vector3 = hb["centre"] + Vector3(0, float(hb["height"]) * 0.5, 0)
	out_d["top"] = p.call(top)
	out_d["centre"] = p.call(hb["centre"])
	var bot := stage.bot()
	var wheels := []
	var armour := []
	if bot != null and bot.has_method("attached_parts"):
		for part in bot.call("attached_parts"):
			var box := AABB()
			var first := true
			for m in stage._meshes_under(part):
				var b: AABB = m.global_transform * m.get_aabb()
				box = b if first else box.merge(b)
				first = false
			if first:
				continue
			var entry := {"name": str(part.name), "key": str(part.get("part_key")),
				"at": p.call(box.get_center()), "dist": snappedf(cam.global_position.distance_to(box.get_center()), 0.01)}
			match str(part.get("part_kind")):
				"wheel":
					wheels.append(entry)
				"armour":
					armour.append(entry)
	out_d["wheels"] = wheels
	out_d["armour"] = armour
	var opp := stage.opponent_bot()
	if opp != null:
		out_d["opponent"] = p.call(stage.opponent_point())
	return out_d


func _count_lights(n: Node) -> Dictionary:
	var d := {"visible": 0, "shadowed": 0}
	for c in n.find_children("*", "Light3D", true, false):
		var l := c as Light3D
		if l.is_visible_in_tree() and l.light_energy > 0.0:
			d["visible"] += 1
			if l.shadow_enabled:
				d["shadowed"] += 1
	return d


func _count_particles(n: Node) -> Dictionary:
	var d := {"emitters": 0, "amount": 0}
	for c in n.find_children("*", "GPUParticles3D", true, false):
		var g := c as GPUParticles3D
		if g.is_visible_in_tree() and g.emitting:
			d["emitters"] += 1
			d["amount"] += g.amount
	return d


func _dump(n: Node, depth: int) -> void:
	for c in n.get_children():
		var extra := ""
		if c is Node3D:
			extra = " pos=%s vis=%s" % [(c as Node3D).position, (c as Node3D).visible]
		if c is GPUParticles3D:
			extra += " amount=%d" % (c as GPUParticles3D).amount
		if c is Light3D:
			extra += " energy=%.2f" % (c as Light3D).light_energy
		print("  ".repeat(depth), c.name, " <", c.get_class(), ">", extra)
		if depth < 1:
			_dump(c, depth + 1)


# ---------------------------------------------------------------- camera

func _s(key: String) -> float:
	# look dials override the variant's shot, which overrides the screen default
	if _look.has(key):
		return float(_look[key])
	if _shot.has(key):
		return float(_shot[key])
	return float((SHOTS[screen] as Dictionary).get(key, 0.0))


func _place_camera() -> void:
	if _cam == null:
		return
	if screen == "board":
		stage.set_turntable_angle(stage.faceoff_hero_yaw_deg() + _s("turn"))
	else:
		stage.set_turntable_angle(_s("turn"))
	var hb := stage.hero_bounds()
	var centre: Vector3 = hb["centre"]
	if screen == "shop":
		centre = stage.part_focus("weapon")["centre"]
	centre += Vector3(_s("tx"), _s("ty"), _s("tz"))
	var fov := _s("fov")
	var dist := _s("dist")
	var yaw := deg_to_rad(_s("yaw"))
	var pitch := deg_to_rad(_s("pitch"))
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := centre + dir * dist
	var frame_h := 2.0 * dist * tan(deg_to_rad(fov) * 0.5)
	var look := centre - Vector3(0.0, (0.5 - _s("top")) * frame_h, 0.0)
	_cam.fov = fov
	_cam.look_at_from_position(pos, look, Vector3.UP)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	_cam.h_offset = (0.5 - _s("fx")) * 2.0 * dist * tan(deg_to_rad(fov) * 0.5) * aspect
	_cam.current = true
	if _l("topdown", 0.0) > 0.5:
		if _td == null:
			_td = Camera3D.new()
			_td.projection = Camera3D.PROJECTION_ORTHOGONAL
			_td.size = _l("tdsize", 34.0)
			_td.far = 200.0
			add_child(_td)
			for k in 2:
				var m := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.35
				sp.height = 0.7
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = Color.RED if k == 0 else Color.GREEN
				sp.material = mat
				m.mesh = sp
				add_child(m)
				_marks.append(m)
		_td.look_at_from_position(Vector3(0, _l("tdy", 4.8), 0.01), Vector3.ZERO, Vector3.FORWARD)
		(_marks[0] as Node3D).position = pos + Vector3(0, 3, 0)
		(_marks[1] as Node3D).position = Vector3(0, 3, 0)
		_td.current = true
		return
	var behind := _s("dof")
	_cam_attr.dof_blur_far_enabled = behind > 0.0
	_cam_attr.dof_blur_far_distance = dist + behind
	_cam_attr.dof_blur_far_transition = behind * 2.5 + 1.0
	_cam_attr.dof_blur_amount = _s("dofamt") if _s("dofamt") > 0.0 else 0.08
	_cam_attr.exposure_multiplier = _s("exposure") if _s("exposure") > 0.0 else 1.0


# ---------------------------------------------------------------- helpers

## A variant's own default for a dial: the command line still wins.
func _def(per_screen: Dictionary) -> void:
	var d: Dictionary = per_screen.get(screen, {})
	var all_d: Dictionary = per_screen.get("all", {})
	for k in all_d.keys():
		if not _look.has(k):
			_look[k] = all_d[k]
	for k in d.keys():
		if not _look.has(k):
			_look[k] = d[k]


func _l(key: String, default: float) -> float:
	return float(_look.get(key, default))


## Hide the stage's own room (floor, black backdrop, flags, hall, probe) so a venue can
## stand round the plinth. The plinth, the machine, its key, fill and rims stay.
func _strip_room(also: Array = []) -> void:
	for n in ["Floor", "Backdrop", "FlagLeft", "FlagRight", "FlagFront", "Room", "RoomProbe",
			"Hall", "FogFloor", "Movers"] + also:
		var node := stage.get_node_or_null(NodePath(n)) as Node3D
		if node != null:
			node.visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED


func _drop_stage_env() -> void:
	var we := stage.get_node_or_null("Environment")
	if we != null:
		stage.remove_child(we)
		we.queue_free()


func _drop_env_under(n: Node) -> void:
	for we in n.find_children("*", "WorldEnvironment", true, false):
		we.get_parent().remove_child(we)
		we.queue_free()


func _add_venue(path: String, xf: Transform3D) -> Node3D:
	var v := (load(path) as PackedScene).instantiate() as Node3D
	v.transform = xf
	add_child(v)
	return v


func _hide_in_venue(names: Array) -> void:
	for n in names:
		var node := venue.get_node_or_null(NodePath(n)) as Node3D
		if node != null:
			node.visible = false


func _kit() -> Node:
	return venue.get_node_or_null("VenueKit") if venue != null else null


func _fog_box(at_pos: Vector3, size: Vector3, density: float, albedo: Color, emission: Color = Color.BLACK,
		falloff: float = 1.0, shape: int = RenderingServer.FOG_VOLUME_SHAPE_BOX) -> FogVolume:
	var fv := FogVolume.new()
	fv.shape = shape
	fv.size = size
	fv.position = at_pos
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = albedo
	fm.emission = emission
	fm.height_falloff = falloff
	fm.edge_fade = 0.35
	var noise := FastNoiseLite.new()
	noise.frequency = 0.9
	var tex := NoiseTexture3D.new()
	tex.width = 64
	tex.height = 32
	tex.depth = 64
	tex.seamless = true
	tex.noise = noise
	fm.density_texture = tex
	fv.material = fm
	add_child(fv)
	return fv


func _spot(from: Vector3, to: Vector3, colour: Color, energy: float, angle: float, fog: float = 1.0,
		shadow: bool = false) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = colour
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_range = from.distance_to(to) * 1.6
	s.spot_attenuation = 0.5
	s.spot_angle_attenuation = 0.9
	s.light_volumetric_fog_energy = fog
	s.shadow_enabled = shadow
	s.light_specular = _l("spec", 0.25)
	add_child(s)
	s.look_at_from_position(from, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD)
	return s


func _omni(at_pos: Vector3, colour: Color, energy: float, rng: float, fog: float = 0.5) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = colour
	o.light_energy = energy
	o.omni_range = rng
	o.light_volumetric_fog_energy = fog
	o.shadow_enabled = false
	o.position = at_pos
	add_child(o)
	return o


func _beam(from: Vector3, to: Vector3, r0: float, r1: float, colour: Color, strength: float,
		streaks: float = 0.6, motes: float = 0.4) -> MeshInstance3D:
	var b := VenueFx.beam(from, to, r0, r1, colour, strength, streaks, motes)
	add_child(b)
	return b


## A moving head: a real spot plus its beam card, swept on a slow sine by _tick_extra.
func _mover(from: Vector3, aim: Vector3, colour: Color, energy: float, angle: float, card: float,
		sweep: Vector3, period: float, phase: float) -> void:
	var s := _spot(from, aim, colour, energy, angle, 3.0)
	var b := _beam(from, aim.lerp(from, 0.08), 0.05, tan(deg_to_rad(angle)) * from.distance_to(aim) * 0.55,
		colour, card, 0.8, 0.5)
	_extra.append({"kind": "mover", "spot": s, "beam": b, "from": from, "aim": aim, "sweep": sweep,
		"period": period, "phase": phase})


func _stage_dry_ice(gain: float, alpha_gain: float) -> void:
	if screen == "board":
		# The face-off lens is 0.26 m off the floor, inside the bank: keep it thin there.
		alpha_gain = minf(alpha_gain, 1.2)
	for c in stage.get_children():
		if c is GPUParticles3D and (str(c.name).begins_with("DryIce") or str(c.name) == "Dust"):
			var g := c as GPUParticles3D
			g.amount = int(g.amount * gain)
			g.emitting = true
			g.visible = true
			g.preprocess = 6.0
			var mat := g.draw_pass_1.surface_get_material(0) if g.draw_pass_1 != null else null
			if mat == null:
				mat = g.material_override
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				for key in ["alpha_scale", "alpha", "opacity"]:
					var v: Variant = sm.get_shader_parameter(key)
					if v != null:
						sm.set_shader_parameter(key, float(v) * alpha_gain)


func _tick_extra(delta: float) -> void:
	for e in _extra:
		match str(e["kind"]):
			"mover":
				var sw: Vector3 = e["sweep"]
				var ph := _t * TAU / float(e["period"]) + float(e["phase"])
				var aim: Vector3 = e["aim"] + Vector3(sin(ph) * sw.x, 0.0, cos(ph * 0.7) * sw.z)
				var from: Vector3 = e["from"]
				(e["spot"] as SpotLight3D).look_at_from_position(from, aim, Vector3.UP)
				VenueFx.aim_beam(e["beam"] as MeshInstance3D, from, aim.lerp(from, 0.08))
			"flicker":
				var n := sin(_t * 41.0) * sin(_t * 13.7) * sin(_t * 3.1)
				(e["light"] as Light3D).light_energy = float(e["base"]) * (0.4 + 1.2 * absf(n))
			"fire":
				if _t >= float(e["at"]) and not bool(e.get("done", false)):
					e["done"] = true
					e["fired_at"] = _t
					var kit := _pyro_kit if _pyro_kit != null else _kit()
					if kit != null:
						kit.call("fire_pyro", str(e["group"]))


# ---------------------------------------------------------------- variants

## Put venue-local point `p` at the stage origin, turned so venue-local direction `back`
## (on the ground) points away from the camera (world -Z): what lies that way in the
## venue is what the menu cameras see behind the machine.
func _venue_xf(p: Vector3, back_yaw_deg: float) -> Transform3D:
	var r := Basis(Vector3.UP, deg_to_rad(back_yaw_deg))
	return Transform3D(r, -(r * p))


## The environment the frame is graded with. Called a moment after the venue has built
## (the kit grades its arena's environment deferred).
func _env() -> Environment:
	for n in find_children("*", "WorldEnvironment", true, false):
		if n.is_inside_tree() and (n as WorldEnvironment).environment != null:
			return (n as WorldEnvironment).environment
	return null


func _grade_env() -> void:
	var env := _env()
	if env == null:
		return
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = _l("vfog", env.volumetric_fog_density)
	env.volumetric_fog_albedo = Color(0.82, 0.88, 1.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 40.0
	env.volumetric_fog_detail_spread = 1.5
	if _look.has("dfog"):
		env.fog_density = _l("dfog", 0.0)
		env.fog_enabled = _l("dfog", 0.0) > 0.0
	if _look.has("amb"):
		env.ambient_light_energy = _l("amb", 0.1)
	if _look.has("glow"):
		env.glow_intensity = _l("glow", 0.5)
	if _look.has("expo"):
		env.tonemap_exposure = _l("expo", 1.0)


## 1. SHOWROOM, TURNED UP: the live stage with the room it already has, pushed hard.
## A dry ice bank that pours off the plinth, moving heads sweeping through real haze
## behind the machine, a hard cold rim, embers drifting up past it.
func _variant_showroom() -> void:
	_def({"all": {"vfog": 0.05}})
	_stage_dry_ice(1.6, 3.0)
	# The bank itself: low, dense, lit by the key and the movers, never at lens height.
	var bank_h := 0.22 if screen != "board" else 0.16
	_fog_box(Vector3(0, bank_h * 0.5, -0.4), Vector3(9.0, bank_h, 7.0), _l("ice", 2.2),
		Color(0.85, 0.9, 1.0), Color(0.05, 0.07, 0.1), 2.0)
	_fog_box(Vector3(0, 0.1, 0), Vector3(2.6, 0.2, 2.6), _l("ice", 2.2) * 1.2,
		Color(0.9, 0.93, 1.0), Color(0.06, 0.08, 0.12), 3.0, RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID)
	# Four moving heads on the far truss, sweeping through the haze behind the machine.
	var cold := Color(0.62, 0.78, 1.0)
	var amber := Color(1.0, 0.6, 0.25)
	var heads := [
		[Vector3(-4.2, 4.6, -5.6), Vector3(-1.4, 0, -1.8), cold, 0.0],
		[Vector3(-1.4, 4.8, -6.0), Vector3(0.6, 0, -1.2), Color(0.8, 0.88, 1.0), 1.7],
		[Vector3(1.6, 4.8, -6.0), Vector3(-0.4, 0, -1.0), amber, 3.1],
		[Vector3(4.4, 4.6, -5.6), Vector3(1.6, 0, -1.6), cold, 4.4],
	]
	for h in heads:
		_mover(h[0], h[1], h[2], _l("mover", 9.0), 7.0, _l("card", 0.22), Vector3(1.6, 0, 0.8),
			9.0 + float(h[3]), float(h[3]))
	# The hard cold rim, high behind: the edge of the machine against the haze.
	_spot(Vector3(0.4, 2.6, -2.4), Vector3(0, 0.25, 0), Color(0.7, 0.82, 1.0), _l("rim", 14.0), 22.0, 0.4)
	# Embers and motes drifting up through the key.
	var em := VenueFx.embers("high", Vector3(1.6, 0.2, 1.2), 0.45)
	em.position = Vector3(0, 0.2, -1.2)
	em.amount = int(_l("embers", 36))
	add_child(em)
	var mo := VenueFx.motes("high", Vector3(4.0, 1.6, 3.0))
	mo.position = Vector3(0, 1.8, -1.5)
	mo.amount = 160
	add_child(mo)
	get_tree().create_timer(0.3).timeout.connect(_grade_env)


## 2. IN THE ARENA: the plinth on the Coliseum floor in front of the north stand, full
## house behind, the truss ring's moving heads, the jumbotron, pyro in the corners.
func _variant_arena() -> void:
	_def({"all": {"dfog": 0.0, "vfog": 0.02, "ice": 1.4, "vx": 1.5, "vz": 1.5}, "menu": {"pitch": 0.0, "dist": 4.2, "top": 0.7, "fov": 38.0},
		"builder": {"pitch": 1.0, "top": 0.62, "dofamt": 0.14}, "result": {"pitch": 0.0, "top": 0.6, "fov": 32.0, "dofamt": 0.14},
		"shop": {"pitch": 12.0, "dofamt": 0.16}, "board": {"dofamt": 0.12}})
	_strip_room()
	# Plinth 2.6 m in front of the north wall, looking across the arena at the stand.
	venue = _add_venue("res://arena/coliseum.tscn",
		_venue_xf(Vector3(_l("vx", -1.0), 0, _l("vz", -1.0)), _l("vyaw", -19.0)))
	# The hazards are off between fights: their floor art would only clutter the plinth.
	_hide_in_venue(["CentreRing", "RadialStar", "HazardRings", "SpikePatch", "TurntableWest",
			"TurntableEast", "GrinderWest", "GrinderEast"])
	_drop_stage_env()
	get_tree().create_timer(0.6).timeout.connect(_soften_venue_key)
	_stage_dry_ice(1.6, 3.0)
	_fog_box(Vector3(0, 0.1, 0), Vector3(3.2, 0.2, 3.2), _l("ice", 2.4), Color(0.9, 0.93, 1.0),
		Color(0.06, 0.07, 0.12), 3.0, RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID)
	_fog_box(Vector3(0, 0.08, -1.0), Vector3(12.0, 0.16, 8.0), _l("ice", 2.4) * 0.6,
		Color(0.85, 0.9, 1.0), Color(0.04, 0.05, 0.1), 2.0)
	_spot(Vector3(0.4, 2.8, -2.4), Vector3(0, 0.25, 0), Color(0.7, 0.82, 1.0), _l("rim", 12.0), 22.0, 0.4)
	if _l("pyro", 1.0) > 0.5 and screen in ["menu", "result", "board"]:
		_extra.append({"kind": "fire", "at": at - _l("pyro_lead", 0.5), "group": "columns"})
	get_tree().create_timer(0.5).timeout.connect(_grade_env)


## 3. THE GATE: the machine on its mark in the mouth of the kit's entrance gate before
## the walk-out, lit from inside the tunnel so it stands against a wall of lit smoke,
## dry ice pouring out over the steel floor, the gate's pyro going up either side and
## moving heads on the gate truss. Built alone from the kit (entrance_gate.glb, pyro,
## moving heads) on the stage's own plate floor, so no arena wall stands in the shot.
func _variant_gate() -> void:
	_def({"all": {"vfog": 0.012, "tunnel": 0.02, "ice": 0.12, "back": 10.0, "dofamt": 0.12},
		"menu": {"pitch": 10.0, "top": 0.62, "fov": 34.0, "dist": 5.2}})
	_strip_room(["Stage/Disc", "Stage/Ring", "Stage/EdgeLight"])
	var fl := stage.get_node_or_null("Floor") as Node3D
	if fl != null:
		fl.visible = true
		fl.process_mode = Node.PROCESS_MODE_INHERIT
		fl.scale = Vector3(2.0, 1.0, 2.0)
	(stage.get_node("Stage/Turntable") as Node3D).position.y = 0.0
	stage.set("_hero_bounds", {})
	venue = Node3D.new()
	venue.name = "GateSet"
	add_child(venue)
	var kit := (load("res://arena/kit/venue_kit.tscn") as PackedScene).instantiate()
	kit.set("venue", "none")
	venue.add_child(kit)
	_gate_kit = kit
	call_deferred("_build_gate_set")
	_stage_dry_ice(1.0, _l("icek", 1.5))
	var gz := _l("gd", 0.5)
	# The tunnel full of lit smoke, and the bank rolling out of it along the floor.
	_fog_box(Vector3(_l("gx", 1.2), 1.6, -gz - 2.2), Vector3(4.6, 3.4, 4.0), _l("tunnel", 0.05), Color(0.9, 0.93, 1.0),
		Color(0.02, 0.025, 0.04), 0.0)
	_fog_box(Vector3(0, 0.07, -gz), Vector3(6.0, 0.14, 5.0), _l("ice", 0.6), Color(0.88, 0.92, 1.0),
		Color(0.05, 0.06, 0.1), 2.0)
	_fog_box(Vector3(0, 0.05, 2.5), Vector3(9.0, 0.1, 5.0), _l("ice", 0.6) * 0.5, Color(0.88, 0.92, 1.0),
		Color(0.03, 0.04, 0.07), 3.0)
	# Backlight: from deep in the tunnel, through the smoke, out past the machine.
	_spot(Vector3(_l("gx", 1.2) - 0.6, 2.6, -gz - 3.6), Vector3(0, 0.2, 0.6), Color(0.72, 0.84, 1.0), _l("back", 7.0), 30.0, _l("backfog", 1.0))
	# The tunnel lit from inside: the roller door and the side walls read, cold.
	_omni(Vector3(_l("gx", 1.2), 1.6, -gz - 3.0), Color(0.6, 0.75, 1.0), _l("tunlamp", 2.5), 5.0, 0.3)
	# The arena's light spilling in from behind the camera: warm, low, across the floor.
	_spot(Vector3(-3.0, 3.2, 6.0), Vector3(0.2, 0.1, -0.4), Color(1.0, 0.72, 0.42), _l("spill", 6.0), 22.0, 0.15)
	_spot(Vector3(0.4, 2.6, -2.2), Vector3(0, 0.25, 0), Color(0.7, 0.82, 1.0), _l("rim", 12.0), 22.0, 0.4)
	var mo := VenueFx.motes("high", Vector3(3.0, 2.0, 3.0))
	mo.position = Vector3(0, 2.0, -gz - 1.0)
	mo.amount = 180
	add_child(mo)
	# Not on the main menu: the left launcher stands right behind the wordmark.
	if screen in ["result", "board"] and _l("pyro", 1.0) > 0.5:
		_extra.append({"kind": "fire", "at": at - _l("pyro_lead", 0.4), "group": "gate0"})
		_extra.append({"kind": "fire", "at": at - 1.2, "group": "gate0"})
	get_tree().create_timer(0.4).timeout.connect(_grade_env)


var _gate_kit: Node = null


func _build_gate_set() -> void:
	await get_tree().process_frame
	var kit := _gate_kit
	var gz := _l("gd", 0.5)
	var g := Transform3D(Basis.IDENTITY, Vector3(_l("gx", 1.2), 0, -gz))
	kit.call("add_gate", g, 0, int(_l("sign", 0.0)))
	# A truss portal over the gate with three moving heads, as the Yard hangs it.
	# Three moving heads on a span flown over the gate (out of the menu frames' way).
	for k in range(3):
		kit.call("place", "truss_span_2m", Transform3D(Basis.IDENTITY, g * Vector3(-2.0 + 2.0 * float(k), 5.2, 0.4)))
	for x in [-2.0, 0.0, 2.0]:
		kit.call("add_moving_head", Transform3D(Basis.IDENTITY, g * Vector3(x, 5.03, 0.4)))
	for x in [-2.6, 2.6]:
		kit.call("add_rotating_beacon", g * Vector3(x, 3.75, 0.2))
	_pyro_kit = kit


func _variant_pit() -> void:
	_def({"all": {"amb": 0.3, "wash": 3.0, "dofamt": 0.12}, "menu": {"pitch": 11.0, "top": 0.6, "wx": -2.9},
		"builder": {"projx": 0.7, "projz": 1.0, "wash": 1.5, "proj": 60.0},
		"shop": {"projx": 0.2, "projz": 0.7, "wash": 1.5, "proj": 60.0},
		"board": {"ice": 0.3, "projx": 1.2, "projz": 0.6},
		"result": {"wx": 0.35, "wy": 1.0, "wz": -3.2, "projx": 0.5, "projz": 0.9, "wash": 1.5, "proj": 60.0}})
	_strip_room(["Stage/Disc", "Stage/Ring", "Stage/EdgeLight"])
	(stage.get_node("Stage/Turntable") as Node3D).position.y = 0.0
	stage.set("_hero_bounds", {})
	venue = _add_venue("res://arena/test_arena.tscn",
		_venue_xf(Vector3(_l("vx", 0.0), 0, _l("vz", 1.4)), _l("vyaw", 180.0)))
	_hide_in_venue(["SpikePatch", "WakeGrinder0", "WakeGrinder1", "Grid"])
	_drop_stage_env()
	_stage_dry_ice(0.6, 1.0)
	_fog_box(Vector3(0, 0.08, 0), Vector3(8.0, 0.16, 6.0), _l("ice", 0.9), Color(0.85, 0.9, 1.0),
		Color(0.02, 0.03, 0.05), 2.0)
	# The projector: a cold spot overhead throwing the blueprint over the stand.
	var tex := _blueprint_texture()
	var pc := Vector3(_l("projx", 0.4), 0, _l("projz", 1.3))
	var proj := _spot(pc + Vector3(0, 4.2, 0.1), pc, Color(0.35, 0.6, 1.0), _l("proj", 40.0),
		_l("projang", 19.0), 1.0)
	proj.spot_angle_attenuation = 0.2
	# A soft cold wash on the machine itself, the projector's spill.
	_spot(Vector3(0.2, 3.4, 1.0), Vector3(0, 0.2, 0), Color(0.45, 0.65, 1.0), _l("wash", 3.0), 20.0, 0.8)
	if tex != null:
		proj.light_projector = tex
	# Welder at the bench: sparks and a flickering arc light.
	# (Not in the close shots, where it would sit on top of the machine.)
	if not screen in ["builder", "shop", "board"]:
		var sp := VenueFx.grinder_plume("high", _l("plume", 0.55))
		sp.amount = int(_l("sparks", 150))
		sp.position = Vector3(_l("wx", -2.3), _l("wy", 0.6), _l("wz", -2.6))
		sp.emitting = true
		add_child(sp)
		var arc := _omni(sp.position + Vector3(0, 0.15, 0.2), Color(0.7, 0.8, 1.0), 3.0, 4.0, 1.0)
		_extra.append({"kind": "flicker", "light": arc, "base": 3.0})
	_spot(Vector3(0.4, 2.6, -2.4), Vector3(0, 0.25, 0), Color(0.7, 0.82, 1.0), _l("rim", 10.0), 22.0, 0.4)
	get_tree().create_timer(0.5).timeout.connect(_grade_env)
	get_tree().create_timer(0.6).timeout.connect(_night)


## The venue's directional key and fill are graded for the fight camera 7 m up; on a
## lens a metre off a steel wedge their specular blows the plate out. Keep their light,
## drop their glint.
func _soften_venue_key() -> void:
	for n in ["KeyLight", "FillLight"]:
		var l := venue.get_node_or_null(n) as Light3D
		if l != null:
			l.light_specular = 0.1
			l.light_energy *= _l("keyk", 0.7)


## After hours: the venue's even directional light down, so the halogens, the projector
## and the arc carry the frame.
func _night() -> void:
	for n in ["KeyLight", "FillLight"]:
		var l := venue.get_node_or_null(n) as Light3D
		if l != null:
			l.light_energy *= _l("night", 0.25)


func _blueprint_texture() -> Texture2D:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/look/menus-bp-a2/blueprint-projector.png").simplify_path()
	if not FileAccess.file_exists(path):
		return null
	print("a2 blueprint ", path, " ", FileAccess.file_exists(path))
	var img := Image.load_from_file(path)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


