class_name BotMarkings extends RefCounted
## Cosmetic machine markings (wave A, materials lead; docs/wave-a-materials-notes.md 5).
##
## Stencils, a hazard stripe and a model code, projected onto the chassis as Decal nodes.
## Every mark is invented (Tools/textures/make_decals.py); none is a real brand.
##
## Placement is from the chassis model's bounds in bot space (+X forward, +Y up, +Z right,
## docs/graphics-models-notes.md), so it needs no per-chassis authoring: the maker's mark
## high on each flank, the model code on the rear deck, the hazard stripe across the rear
## face. Each box is shallow (6 cm) and sits on the face it marks, so it cannot reach the
## floor or the opponent.
##
## Tiers: decals are a Forward+ and Mobile feature. GraphicsQuality turns `decals` off on
## the low tier (GL, the simulator), and `apply()` then adds nothing.
##
## Integration is OWED: `apply()` is called by the material board's hero mode today. The
## stage (`workshop/stage.gd`) and the fight (`fight/fight.gd`) build machines and are
## other leads' files; each wants one line after `setup()`:
##     BotMarkings.apply(bot, Color(config.get("livery", "#d1662b")))

const DIR := "res://assets/textures/decals/"
## Decals fade out past this distance: at the fight camera a 10 cm stencil is a few pixels.
const FADE_BEGIN := 7.0
const FADE_LENGTH := 2.0
## Depth of every decal box, straddling the face it marks.
## Shallow on purpose: 6 cm went through a flank's armour plate and printed a second,
## offset copy on the chassis wall behind it (measured on the wedge, notes 5).
const DEPTH := 0.035
## The box centre sits this far inside the outer face, so it covers the skin and a
## little proud geometry but not what is behind the skin.
const INSET := 0.008


## Adds a `Markings` node under `bot` and returns it, or null when the tier has no decals
## or the chassis cannot be found. Safe to call twice: the old markings go first.
static func apply(bot: Node3D, livery: Color, context: Node = null) -> Node3D:
	if bot == null:
		return null
	var quality := GraphicsQualityRef.resolve(context if context != null else bot)
	if quality != null and quality.has_method("allows") and not bool(quality.call("allows", "decals")):
		return null
	var old := bot.get_node_or_null("Markings")
	if old != null:
		old.free()
	var chassis := _chassis_model(bot)
	if chassis == null:
		return null
	# The OUTER skin: the chassis plus its armour panels (they sit proud of the hull).
	var skin: Array[Node3D] = [chassis]
	for child in bot.get_children():
		if String(child.name).begins_with("Panel") and child is Node3D:
			skin.append(child as Node3D)
	var box := _local_bounds(skin, bot)
	if box.size.x <= 0.0:
		return null
	var points := _skin_points(skin, bot)
	var root := Node3D.new()
	root.name = "Markings"
	bot.add_child(root)

	# Stencil paint: white on a dark livery, near black on a pale one.
	var ink := Color(0.92, 0.92, 0.9) if livery.get_luminance() < 0.55 else Color(0.06, 0.06, 0.07)
	var c := box.get_center()
	var s := box.size
	var top := box.position.y + s.y
	# Maker's mark, both flanks, centred on the side armour when there is any (the
	# largest flat livery on a machine), else on the chassis flank.
	var flank: Array[Node3D] = []
	for node in skin:
		if String(node.name).begins_with("PanelSides"):
			flank.append(node)
	var fb := _local_bounds(flank, bot) if not flank.is_empty() else box
	if fb.size.x <= 0.0:
		fb = box
	var mark_w := clampf(fb.size.x * 0.55, 0.12, 0.26)
	for side in [1.0, -1.0]:
		var z: float = c.z + side * s.z * 0.5
		_decal(root, "decal_kestrel_works.png",
			Vector3(fb.get_center().x, fb.get_center().y, z),
			Vector3(0, 0, side), Vector3(mark_w, mark_w * 0.5, 0), ink, "Mark",
			Vector3(side, 0, 0), points)  # U toward the viewer's right on each flank
	# Model code on the rear deck, reading from behind.
	var code_w := clampf(s.z * 0.30, 0.10, 0.20)
	_decal(root, "decal_torq9.png", Vector3(box.position.x + s.x * 0.18, top, c.z),
		Vector3.UP, Vector3(code_w, code_w * 0.25, 0), ink, "Code", Vector3(0, 0, 1), points)  # reads from behind
	# Hazard stripe across the rear face.
	var stripe_w := s.z * 0.62
	_decal(root, "decal_hazard_stripe.png", Vector3(box.position.x, box.position.y + s.y * 0.45, c.z),
		Vector3(-1, 0, 0), Vector3(stripe_w, stripe_w * 0.25, 0), Color.WHITE, "Hazard", Vector3.ZERO, points)
	return root


## One decal whose projection axis (-Y local) points into the face with normal `n`.
## `size.x` runs along `across` (default: the forward axis, or +Z on a face that faces
## forward or back), `size.y` along the remaining axis.
static func _decal(parent: Node3D, file: String, at: Vector3, n: Vector3, size: Vector3,
		modulate: Color, name: String, across: Vector3 = Vector3.ZERO,
		points: PackedVector3Array = PackedVector3Array()) -> Decal:
	var tex := load(DIR + file) as Texture2D
	if tex == null:
		return null
	var d := Decal.new()
	d.name = name
	d.texture_albedo = tex
	d.modulate = modulate
	d.albedo_mix = 1.0
	d.normal_fade = 0.35
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.distance_fade_enabled = true
	d.distance_fade_begin = FADE_BEGIN
	d.distance_fade_length = FADE_LENGTH
	var y := n.normalized()
	var x := across
	if x == Vector3.ZERO:
		x = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK
	x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y).normalized()
	# The texture's U runs along the decal's +X and V along +Z.
	# Snap onto the skin the eye sees: cast five rays inward along -n (centre and the four
	# half-way points of the footprint) against the skin's triangles and take the median
	# first hit. The bounding box face is often a bolt, a lip or a raised rim well proud
	# of the panel, and a shallow box placed there misses the panel (it did on the wedge).
	if not points.is_empty():
		var hits: Array[float] = []
		var hx := size.x * 0.25
		var hz := size.y * 0.25
		for o in [Vector2.ZERO, Vector2(hx, hz), Vector2(-hx, hz), Vector2(hx, -hz), Vector2(-hx, -hz)]:
			var origin: Vector3 = at + x * o.x + z * o.y + y * 0.5
			var nearest := INF
			var i := 0
			while i + 2 < points.size():
				var hit: Variant = Geometry3D.ray_intersects_triangle(
					origin, -y, points[i], points[i + 1], points[i + 2])
				if hit != null:
					nearest = minf(nearest, origin.distance_to(hit as Vector3))
				i += 3
			if nearest < INF:
				hits.append(0.5 - nearest)
		if not hits.is_empty():
			hits.sort()
			at += y * hits[hits.size() / 2]
	d.transform = Transform3D(Basis(x, y, z), at - y * INSET)
	d.size = Vector3(size.x, DEPTH, size.y)
	parent.add_child(d)
	return d


## The skin as a triangle soup in bot space (three points per triangle), read once when
## the machine is built. A wedge with its plates is about 20 000 triangles; five rays per
## decal and four decals is a few milliseconds, never per frame.
static func _skin_points(models: Array[Node3D], bot: Node3D) -> PackedVector3Array:
	var inv := bot.global_transform.affine_inverse()
	var out := PackedVector3Array()
	for model in models:
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var t := inv * mi.global_transform
			for v in mi.mesh.get_faces():
				out.append(t * v)
	return out


static func _chassis_model(bot: Node) -> Node3D:
	var chassis := bot.get_node_or_null("Chassis")
	if chassis == null:
		return null
	for child in chassis.get_children():
		if String(child.name).begins_with("Model_"):
			return child as Node3D
	return chassis as Node3D


static func _local_bounds(models: Array[Node3D], bot: Node3D) -> AABB:
	var inv := bot.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var meshes: Array[Node] = []
	for model in models:
		if model is MeshInstance3D:
			meshes.append(model)
		meshes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mi := node as MeshInstance3D
		var b := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		return AABB()
	return box


## GraphicsQuality has no class_name (it is an autoload); reach it by script path.
class GraphicsQualityRef:
	static func resolve(context: Node) -> Node:
		var script := load("res://render/graphics_quality.gd") as GDScript
		if script == null:
			return null
		return script.call("resolve", context) as Node
