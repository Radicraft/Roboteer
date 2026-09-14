class_name TestOverlay extends CanvasLayer
## The test arena's physics debug overlay (docs/stage4-spec.md section 5, brief section 10).
##
## Per bot it draws the centre of mass, the front lip clearance in millimetres, the
## weapon reach arc and height band, the speed, the wheel contact count, and the last
## damage event; plus a Reset button and a Hide toggle. Shown only when
## `rules.mode == "test"`, which is R2's call.
##
## Presentation only, and defensive by design: every reading is duck typed off the Bot,
## so an overlay written in wave 1 keeps working while P2 and W1/W2 add methods to it.
## Anything the Bot cannot answer is simply not drawn.

## The Reset button. R2 connects this to its own test_reset.
signal reset_requested

const OVERLAY_LAYER := 3
const MARGIN := 18.0
## The shell's Back / TEST ARENA / Reset row owns the top of the screen in test mode, so
## nothing of ours starts above it. Quoted in design points, like everything in the HUD.
const SHELL_BAND_PT := 60.0
const REF_WIDTH_PT := 1206.0
const REF_HEIGHT_PT := 556.0
const FONT_PT := 15.0
const LINE_H := 19.0

const COL_TEXT := Color(0.95, 0.96, 1.0)
const COL_SHADOW := Color(0.0, 0.0, 0.0, 0.75)
const COL_COM := Color(0.45, 0.92, 1.0)
const COL_REACH := Color(0.55, 0.85, 1.0, 0.85)
const COL_DAMAGE := Color(1.0, 0.55, 0.45)
const COL_PANEL := Color(0.05, 0.06, 0.08, 0.55)

const COM_RADIUS := 9.0
## Half angle of the drawn reach arc, degrees either side of the weapon's forward.
const REACH_HALF_ARC_DEG := 40.0
## Used when the Bot cannot say how far its weapon reaches (Stage 3 flipper length).
const DEFAULT_REACH := 0.45

## The drawing surface. An inner class so the whole overlay stays one file and one
## script; _draw is forwarded straight back to the overlay.
class OverlayCanvas extends Control:
	var overlay: Node = null
	## Counted so the headless test can prove the draw calls really ran.
	var draws: int = 0

	func _draw() -> void:
		draws += 1
		if overlay != null and is_instance_valid(overlay) and overlay.has_method("draw_overlay"):
			overlay.call("draw_overlay", self)


var _bots: Array = []
var _camera: Camera3D = null
var _canvas: OverlayCanvas = null

var _overlay_visible := true
var _last_damage := ""
var _last_damage_age := 0.0
var _built := false


func _ready() -> void:
	_build()
	set_process(true)


# ---------------------------------------------------------------- public API

## `bots` is an Array of Bot nodes (any node that answers the queries below) and
## `camera` is the live Camera3D the readings are projected through.
func bind(bots: Array, camera: Camera3D) -> void:
	_build()
	_bots = bots.duplicate()
	_camera = camera


## Hides the drawing and the readings. The button bar stays up so the overlay can be
## brought back, which is the whole point of a toggle.
func set_visible_overlay(on: bool) -> void:
	_build()
	_overlay_visible = on
	_canvas.visible = on
	pass
	_canvas.queue_redraw()


func is_overlay_visible() -> bool:
	return _overlay_visible


## The last damage_event on either bot, as R2 receives it. Payload shape is spec
## section 6: {bot, part, severity, detached, ...}.
func note_damage_event(info: Dictionary) -> void:
	var bot_name := str(info.get("bot", info.get("bot_id", "")))
	var part := str(info.get("part", "?"))
	var severity := float(info.get("severity", 0.0))
	var detached: bool = bool(info.get("detached", false))
	_last_damage = "%s %s -%.2f%s" % [bot_name, part, severity, "  DETACHED" if detached else ""]
	_last_damage_age = 0.0


func last_damage_line() -> String:
	return _last_damage


func canvas() -> Control:
	_build()
	return _canvas


## How many times the overlay has drawn. The headless test's proof that _draw ran.
func draw_count() -> int:
	_build()
	return _canvas.draws


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_last_damage_age += delta
	if _overlay_visible and _canvas != null:
		_canvas.queue_redraw()


# ---------------------------------------------------------------- drawing

## Called back from OverlayCanvas._draw. Everything is drawn here so there is one
## place that knows the layout.
func draw_overlay(canvas_node: Control) -> void:
	if not _overlay_visible:
		return
	var font := canvas_node.get_theme_default_font()
	if font == null:
		return
	var size := canvas_node.size
	var row := 0
	for bot_variant in _bots:
		var bot := bot_variant as Node
		if bot == null or not is_instance_valid(bot):
			continue
		_draw_bot(canvas_node, font, bot, row, size)
		row += 1
	_draw_damage_line(canvas_node, font, size)


func _draw_bot(canvas_node: Control, font: Font, bot: Node, row: int, size: Vector2) -> void:
	var chassis := _chassis_of(bot)
	var lines: Array[String] = []
	lines.append(_bot_label(bot, row))

	if chassis != null:
		var com := _com_world(chassis)
		_draw_com(canvas_node, font, com)
		lines.append("speed %.2f m/s" % chassis.linear_velocity.length())

	if bot.has_method("front_edge_height"):
		lines.append("front lip %d mm" % int(round(float(bot.call("front_edge_height")) * 1000.0)))
	if bot.has_method("weapon_height_band"):
		lines.append("weapon band %s" % str(bot.call("weapon_height_band")))
	if bot.has_method("wheel_contacts"):
		var contacts: Variant = bot.call("wheel_contacts")
		if contacts is Array:
			var down := 0
			for c in (contacts as Array):
				if bool(c):
					down += 1
			lines.append("wheels down %d of %d" % [down, (contacts as Array).size()])
		elif contacts is int or contacts is float:
			lines.append("wheels down %d" % int(contacts))
	if bot.has_method("weapon_readiness"):
		lines.append("weapon %d%%" % int(round(float(bot.call("weapon_readiness")) * 100.0)))

	_draw_reach(canvas_node, bot, chassis)

	# One column per bot: the first down the left, the second down the right.
	var width := 232.0
	var x: float = MARGIN if row == 0 else maxf(size.x - width - MARGIN, MARGIN)
	var y := _top_band(size) + MARGIN
	var panel := Rect2(Vector2(x - 8.0, y - LINE_H), Vector2(width, LINE_H * lines.size() + 12.0))
	canvas_node.draw_rect(panel, COL_PANEL, true)
	for line in lines:
		_text(canvas_node, font, Vector2(x, y), line, COL_TEXT)
		y += LINE_H


func _draw_com(canvas_node: Control, font: Font, world: Vector3) -> void:
	var at: Variant = _project(world)
	if at == null:
		return
	var p: Vector2 = at
	canvas_node.draw_line(p - Vector2(COM_RADIUS + 5.0, 0.0), p + Vector2(COM_RADIUS + 5.0, 0.0), COL_COM, 1.5)
	canvas_node.draw_line(p - Vector2(0.0, COM_RADIUS + 5.0), p + Vector2(0.0, COM_RADIUS + 5.0), COL_COM, 1.5)
	canvas_node.draw_arc(p, COM_RADIUS, 0.0, TAU, 20, COL_COM, 1.5)
	_text(canvas_node, font, p + Vector2(COM_RADIUS + 8.0, -4.0), "COM", COL_COM)


## The weapon's reach, as an arc on the screen centred on the weapon socket and
## radiused by projecting a point one reach ahead of it.
func _draw_reach(canvas_node: Control, bot: Node, chassis: RigidBody3D) -> void:
	if chassis == null:
		return
	var socket := _weapon_socket_world(bot, chassis)
	var forward := chassis.global_transform.basis.x
	forward = Vector3(forward.x, 0.0, forward.z)
	if forward.length_squared() < 0.000001:
		return
	forward = forward.normalized()
	var reach := _weapon_reach(bot)
	var socket_px: Variant = _project(socket)
	var tip_px: Variant = _project(socket + forward * reach)
	if socket_px == null or tip_px == null:
		return
	var centre: Vector2 = socket_px
	var tip: Vector2 = tip_px
	var radius := centre.distance_to(tip)
	if radius < 2.0:
		return
	var mid := (tip - centre).angle()
	var half := deg_to_rad(REACH_HALF_ARC_DEG)
	canvas_node.draw_arc(centre, radius, mid - half, mid + half, 24, COL_REACH, 2.0)
	canvas_node.draw_line(centre, centre + Vector2(cos(mid - half), sin(mid - half)) * radius, COL_REACH, 1.0)
	canvas_node.draw_line(centre, centre + Vector2(cos(mid + half), sin(mid + half)) * radius, COL_REACH, 1.0)


func _draw_damage_line(canvas_node: Control, font: Font, size: Vector2) -> void:
	if _last_damage == "":
		return
	var colour := COL_DAMAGE
	colour.a = clampf(1.2 - _last_damage_age * 0.15, 0.35, 1.0)
	_text(canvas_node, font, Vector2(MARGIN, size.y - MARGIN), "last damage: " + _last_damage, colour)


## The band across the top of the screen the shell's own test arena chrome occupies, in
## viewport pixels for this viewport.
func _top_band(size: Vector2) -> float:
	var pt := 1.0
	if size.x > 1.0 and size.y > 1.0:
		pt = minf(size.x / REF_WIDTH_PT, size.y / REF_HEIGHT_PT)
	return SHELL_BAND_PT * maxf(pt, 0.1)


func _text(canvas_node: Control, font: Font, at: Vector2, text: String, colour: Color) -> void:
	canvas_node.draw_string(font, at + Vector2(1.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(FONT_PT), COL_SHADOW)
	canvas_node.draw_string(font, at, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(FONT_PT), colour)


# ---------------------------------------------------------------- readings

## null when there is no camera or the point is behind it, so every caller has to
## decide what to do rather than drawing at a wrapped screen position.
func _project(world: Vector3) -> Variant:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return null
	if _camera.is_position_behind(world):
		return null
	return _camera.unproject_position(world)


func _chassis_of(bot: Node) -> RigidBody3D:
	var direct: Variant = bot.get("chassis")
	if direct is RigidBody3D and is_instance_valid(direct):
		return direct as RigidBody3D
	var node := bot.get_node_or_null("Chassis")
	return node as RigidBody3D


func _com_world(chassis: RigidBody3D) -> Vector3:
	return chassis.global_transform * chassis.center_of_mass


func _bot_label(bot: Node, row: int) -> String:
	var id: Variant = bot.get("bot_id")
	if id is String and str(id) != "":
		return str(id).to_upper()
	return "BOT %d" % (row + 1)


## The Stage 3 Bot has no socket accessor, so this walks the ladder: an explicit
## method first, then the weapon body by name, then the chassis nose.
func _weapon_socket_world(bot: Node, chassis: RigidBody3D) -> Vector3:
	if bot.has_method("weapon_socket_world"):
		var out: Variant = bot.call("weapon_socket_world")
		if out is Vector3:
			return out as Vector3
	for child in bot.get_children():
		var node3d := child as Node3D
		if node3d == null:
			continue
		var lower := String(node3d.name).to_lower()
		if lower.begins_with("flipper") or lower.begins_with("weapon"):
			return node3d.global_position
	return chassis.global_transform * Vector3(0.3, 0.06, 0.0)


func _weapon_reach(bot: Node) -> float:
	for method in ["weapon_reach", "reach"]:
		if bot.has_method(method):
			var value: Variant = bot.call(method)
			if value is float or value is int:
				var reach := float(value)
				if reach > 0.0:
					return reach
	return DEFAULT_REACH


# ---------------------------------------------------------------- construction

func _build() -> void:
	if _built:
		return
	_built = true
	layer = OVERLAY_LAYER

	_canvas = get_node_or_null("Canvas") as OverlayCanvas
	if _canvas == null:
		_canvas = OverlayCanvas.new()
		_canvas.name = "Canvas"
		add_child(_canvas)
	_canvas.overlay = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# NO buttons of our own (changed 2026-09-14). The shell draws the test arena's
	# chrome itself, a Back / TEST ARENA / Reset row across the top, and a second RESET
	# next to its own read as a bug. `reset_requested` is still the signal the rules
	# layer listens on; the shell's button is what emits it now. The readout below is
	# all this overlay draws.


## Kept for the rules layer and the headless test: there is no button behind it any
## more, the shell's own Reset is.
func request_reset() -> void:
	emit_signal("reset_requested")
