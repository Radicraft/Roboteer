class_name VenueScreen extends Node3D
## A venue big screen (docs/wave-a-kit-notes.md). The face is an LED shader fed by a
## small 2D SubViewport that draws the broadcast graphics: the venue name, the two
## machines' names, the fight clock, a LIVE tag and a sting on big moments.
##
## High tier: the graphics sit over a LIVE FEED, a second low-resolution camera in the
## fight world that follows the two machines, updated at a third of the frame rate and
## blind to the venue layer (so the screen never films itself, and the second render
## stays cheap). A big hit freezes the feed and slowly pushes in on it with a REPLAY tag:
## the frame the crowd reacted to, held. Medium and low tiers: graphics only.
##
## Everything here READS the fight (names, clock, bot positions); nothing writes it.

## The Blueprint faces (docs/look/fonts-options.html, system 01): the stencil for the LIVE
## tag and the sting, the Saira UI face for the names, and the same face with tabular figures
## for the clock (Broadcast.font_numerals()). The stencil is wider than the Barlow it
## replaced, so its sizes are 0.8 of the old; the clock is 0.87, as tall as the mono it replaced.
const FONT_DISPLAY := "res://assets/fonts/SairaStencilOne-Regular.ttf"
const FONT_LABEL := "res://assets/fonts/SairaSemiCondensed-Bold.ttf"
const SHADER := "res://arena/kit/shaders/led_screen.gdshader"

var venue_title := "THE YARD"
var tier := "high"
var face_size := Vector2(4.8, 2.7)
var exclude_layer_bit := 10

var _vp: SubViewport = null
var _feed_vp: SubViewport = null
var _feed_cam: Camera3D = null
var _feed_rect: TextureRect = null
var _clock: Label = null
var _names: Label = null
var _tag: Label = null
var _sting: Label = null
var _bg: ColorRect = null
var _mat: ShaderMaterial = null
var _fight: Node = null
var _frame := 0
var _freeze_s := 0.0
var _sting_s := 0.0
var _t := 0.0
var face: MeshInstance3D = null


func build(face_mesh: MeshInstance3D = null) -> ShaderMaterial:
	var res := Vector2i(384, 216) if tier == "high" else Vector2i(256, 144)
	_vp = SubViewport.new()
	_vp.name = "ScreenGraphics"
	_vp.size = res
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.06, 0.09)
	_bg.size = Vector2(res)
	_vp.add_child(_bg)

	if tier == "high":
		_feed_vp = SubViewport.new()
		_feed_vp.name = "LiveFeed"
		_feed_vp.size = Vector2i(320, 180)
		_feed_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_feed_vp.msaa_3d = Viewport.MSAA_DISABLED
		_feed_vp.positional_shadow_atlas_size = 0
		_feed_vp.own_world_3d = false
		add_child(_feed_vp)
		_feed_cam = Camera3D.new()
		_feed_cam.fov = 22.0
		_feed_cam.cull_mask = 0xFFFFF & ~(1 << exclude_layer_bit)
		_feed_cam.position = Vector3(6.5, 3.2, 6.5)
		_feed_vp.add_child(_feed_cam)
		_feed_cam.look_at_from_position(_feed_cam.position, Vector3.ZERO, Vector3.UP)
		_feed_rect = TextureRect.new()
		_feed_rect.texture = _feed_vp.get_texture()
		_feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_feed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_feed_rect.size = Vector2(res)
		_feed_rect.pivot_offset = Vector2(res) * 0.5
		_vp.add_child(_feed_rect)

	var bar := ColorRect.new()
	bar.color = Color(0.02, 0.02, 0.03, 0.82)
	bar.position = Vector2(0, res.y * 0.78)
	bar.size = Vector2(res.x, res.y * 0.22)
	_vp.add_child(bar)
	var accent := ColorRect.new()
	accent.color = Color(0.95, 0.72, 0.14)
	accent.position = Vector2(0, res.y * 0.78)
	accent.size = Vector2(res.x, 3)
	_vp.add_child(accent)

	var s := float(res.y) / 216.0
	_names = _label(FONT_LABEL, int(24 * s), Color(0.95, 0.95, 0.92))
	_names.position = Vector2(10 * s, res.y * 0.8)
	_names.size = Vector2(res.x * 0.72, res.y * 0.2)
	_names.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vp.add_child(_names)
	_clock = _label("", int(33 * s), Color(1.0, 0.8, 0.2), Broadcast.font_numerals())
	_clock.position = Vector2(res.x * 0.72, res.y * 0.79)
	_clock.size = Vector2(res.x * 0.27, res.y * 0.21)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vp.add_child(_clock)
	_tag = _label(FONT_DISPLAY, int(16 * s), Color(1, 1, 1))
	_tag.position = Vector2(10 * s, 8 * s)
	_vp.add_child(_tag)
	_sting = _label(FONT_DISPLAY, int(51 * s), Color(1.0, 0.85, 0.25))
	_sting.size = Vector2(res.x, res.y * 0.6)
	_sting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sting.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_sting.add_theme_constant_override("outline_size", int(8 * s))
	_vp.add_child(_sting)

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("feed", _vp.get_texture())
	_mat.set_shader_parameter("pixels", Vector2(res) * 0.5)
	_mat.set_shader_parameter("brightness", 2.4 if tier != "low" else 1.1)
	face = face_mesh
	if face != null:
		face.material_override = _mat
	_names.text = venue_title
	_clock.text = ""
	_tag.text = "LIVE" if tier == "high" else venue_title
	return _mat


func _label(font_path: String, size: int, colour: Color, face: Font = null) -> Label:
	var l := Label.new()
	var f := face if face != null else load(font_path) as Font
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


## A big moment: freeze the feed on it and push in, with a word over it.
func sting(word: String, hold_s: float = 1.8) -> void:
	_sting_s = hold_s
	if _sting != null:
		_sting.text = word
	if _feed_rect != null:
		_freeze_s = hold_s


func _process(delta: float) -> void:
	if _vp == null:
		return
	_t += delta
	_frame += 1
	if _fight == null or not is_instance_valid(_fight):
		_fight = _find_fight()
	_update_text()
	# Sting and replay freeze.
	if _sting_s > 0.0:
		_sting_s -= delta
		_sting.modulate.a = clampf(_sting_s * 3.0, 0.0, 1.0)
	elif _sting != null:
		_sting.modulate.a = 0.0
	if _feed_rect != null:
		if _freeze_s > 0.0:
			_freeze_s -= delta
			var k := 1.0 + (1.8 - maxf(_freeze_s, 0.0)) * 0.12
			_feed_rect.scale = Vector2(k, k)
			_tag.text = "REPLAY"
		else:
			_feed_rect.scale = Vector2.ONE
			_tag.text = "LIVE"
			if _frame % 3 == 0:
				_aim_feed()
				_feed_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		# Graphics only: a slow colour drift behind the names so the wall is never dead.
		_bg.color = Color.from_hsv(0.58 + 0.05 * sin(_t * 0.4), 0.55, 0.16 + 0.04 * sin(_t * 1.3))


func _update_text() -> void:
	if _fight == null:
		return
	var names: Variant = _fight.get("_bot_names")
	if names is Array and (names as Array).size() >= 2:
		var a := str(names[0]).to_upper()
		var b := str(names[1]).to_upper()
		if a != "" and b != "":
			_names.text = "%s  VS  %s" % [a, b]
	var left: Variant = _fight.get("_time_left")
	if left != null:
		var secs := maxi(0, int(ceil(float(left))))
		_clock.text = "%d:%02d" % [secs / 60, secs % 60]


func _aim_feed() -> void:
	if _feed_cam == null or _fight == null or not _fight.has_method("bots"):
		return
	var bots: Array = _fight.call("bots")
	var mid := Vector3.ZERO
	var n := 0
	for b in bots:
		var node := b as Node3D
		if node != null and is_instance_valid(node) and node.is_inside_tree():
			mid += node.global_position
			n += 1
	if n == 0:
		return
	mid /= float(n)
	var look := _feed_cam.get_meta("look", mid) as Vector3
	look = look.lerp(mid, 0.25)
	_feed_cam.set_meta("look", look)
	_feed_cam.look_at(look + Vector3(0, 0.15, 0), Vector3.UP)


func _find_fight() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("fight_time") and n.has_method("bots"):
			return n
		n = n.get_parent()
	return null
