class_name HazardMeshes extends RefCounted
## Wave A: render meshes for the arena hazards (docs/wave-a-hazards-notes.md), replacing
## the engine primitives arenas.md §1 called out (grinder discs rendering as black holes,
## rams and turntables as blank white blocks, tiny grey spike cones).
##
## RENDER ONLY. Nothing here is a collision shape; every hazard's CollisionShape3D and
## Area3D is built exactly as before in arena_base.gd / crush.gd, so the physics and the
## timing are byte-identical (hazard_determinism_test.gd).
##
## Every mesh is one ArrayMesh with one surface per MATERIAL SLOT, in a fixed order the
## caller documents, so the materials lead's masters drop onto `surface_override_material`
## by index. Meshes carry normals and UVs (metres, so a tiling master maps at a known
## scale), and are wound clockwise-front as Godot expects.
##
## Built in code rather than in Blender because they are small, parametric (the spike
## patch and the grinder are sized per arena) and must stay cheap to regenerate while the
## kit in Tools/blender/ settles. Each is a handful of hundred triangles.


## A mesh under construction: one PackedArray set per surface.
class Builder:
	var surfaces: Array = []

	func surface(index: int) -> Dictionary:
		while surfaces.size() <= index:
			surfaces.append({"v": PackedVector3Array(), "n": PackedVector3Array(),
				"uv": PackedVector2Array()})
		return surfaces[index]

	## One triangle, flat normal `n`, wound so it faces `n`.
	func tri(s: int, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
			ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		var d := surface(s)
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		(d["v"] as PackedVector3Array).append_array([a, b, c])
		(d["n"] as PackedVector3Array).append_array([n, n, n])
		(d["uv"] as PackedVector2Array).append_array([ua, ub, uc])

	## A quad a-b-c-d (in order round its edge) with smooth per-corner normals.
	func quad_smooth(s: int, a: Vector3, b: Vector3, c: Vector3, e: Vector3,
			na: Vector3, nb: Vector3, nc: Vector3, ne: Vector3,
			ua: Vector2, ub: Vector2, uc: Vector2, ue: Vector2) -> void:
		var d := surface(s)
		var face := (na + nb + nc + ne).normalized()
		for tri_v in [[a, b, c, na, nb, nc, ua, ub, uc], [a, c, e, na, nc, ne, ua, uc, ue]]:
			var p0: Vector3 = tri_v[0]
			var p1: Vector3 = tri_v[1]
			var p2: Vector3 = tri_v[2]
			var n0: Vector3 = tri_v[3]
			var n1: Vector3 = tri_v[4]
			var n2: Vector3 = tri_v[5]
			var u0: Vector2 = tri_v[6]
			var u1: Vector2 = tri_v[7]
			var u2: Vector2 = tri_v[8]
			if (p1 - p0).cross(p2 - p0).dot(face) > 0.0:
				var t := p1
				p1 = p2
				p2 = t
				var tn := n1
				n1 = n2
				n2 = tn
				var tu := u1
				u1 = u2
				u2 = tu
			(d["v"] as PackedVector3Array).append_array([p0, p1, p2])
			(d["n"] as PackedVector3Array).append_array([n0, n1, n2])
			(d["uv"] as PackedVector2Array).append_array([u0, u1, u2])

	func quad(s: int, a: Vector3, b: Vector3, c: Vector3, e: Vector3, n: Vector3) -> void:
		var u := Vector2(0, 0)
		tri(s, a, b, c, n, _uv(a, n), _uv(b, n), _uv(c, n))
		tri(s, a, c, e, n, _uv(a, n), _uv(c, n), _uv(e, n))

	## Planar UVs in metres off the dominant axis, so a tiling master maps at scale.
	func _uv(p: Vector3, n: Vector3) -> Vector2:
		var an := n.abs()
		if an.y >= an.x and an.y >= an.z:
			return Vector2(p.x, p.z)
		if an.x >= an.z:
			return Vector2(p.z, p.y)
		return Vector2(p.x, p.y)

	## An axis-aligned box, optionally without its bottom face.
	func box(s: int, centre: Vector3, size: Vector3, bottom := false) -> void:
		var h := size * 0.5
		var c := centre
		var p := [
			c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
			c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
			c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z),
			c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
		]
		quad(s, p[4], p[5], p[6], p[7], Vector3.UP)
		if bottom:
			quad(s, p[0], p[1], p[2], p[3], Vector3.DOWN)
		quad(s, p[0], p[1], p[5], p[4], Vector3.FORWARD)
		quad(s, p[3], p[2], p[6], p[7], Vector3.BACK)
		quad(s, p[0], p[3], p[7], p[4], Vector3.LEFT)
		quad(s, p[1], p[2], p[6], p[5], Vector3.RIGHT)

	## A surface of revolution about +Y through `centre`. `profile` is [radius, y] pairs
	## from the bottom up; `sides` facets; smooth round the axis, creased at each ring.
	func lathe(s: int, centre: Vector3, profile: Array, sides: int, smooth := true) -> void:
		for i in range(profile.size() - 1):
			var r0 := float((profile[i] as Array)[0])
			var y0 := float((profile[i] as Array)[1])
			var r1 := float((profile[i + 1] as Array)[0])
			var y1 := float((profile[i + 1] as Array)[1])
			var slope := Vector2(y1 - y0, -(r1 - r0)).normalized()   # outward normal in (r, y)
			for k in range(sides):
				var a0 := TAU * float(k) / float(sides)
				var a1 := TAU * float(k + 1) / float(sides)
				var d0 := Vector3(cos(a0), 0.0, sin(a0))
				var d1 := Vector3(cos(a1), 0.0, sin(a1))
				var p00 := centre + d0 * r0 + Vector3(0, y0, 0)
				var p01 := centre + d1 * r0 + Vector3(0, y0, 0)
				var p11 := centre + d1 * r1 + Vector3(0, y1, 0)
				var p10 := centre + d0 * r1 + Vector3(0, y1, 0)
				var n0 := (d0 * slope.x + Vector3(0, slope.y, 0)).normalized()
				var n1 := (d1 * slope.x + Vector3(0, slope.y, 0)).normalized()
				if not smooth:
					var dm := ((d0 + d1) * 0.5).normalized()
					n0 = (dm * slope.x + Vector3(0, slope.y, 0)).normalized()
					n1 = n0
				var u0 := float(k) / float(sides)
				var u1 := float(k + 1) / float(sides)
				if r0 < 0.0001 and r1 < 0.0001:
					continue
				quad_smooth(s, p00, p01, p11, p10, n0, n1, n1, n0,
					Vector2(u0 * TAU * maxf(r0, r1), y0), Vector2(u1 * TAU * maxf(r0, r1), y0),
					Vector2(u1 * TAU * maxf(r0, r1), y1), Vector2(u0 * TAU * maxf(r0, r1), y1))

	## A flat annulus (or disc when inner = 0) facing +Y at height y.
	func ring(s: int, centre: Vector3, inner: float, outer: float, y: float, sides: int,
			from_a := 0.0, to_a := TAU) -> void:
		for k in range(sides):
			var a0 := from_a + (to_a - from_a) * float(k) / float(sides)
			var a1 := from_a + (to_a - from_a) * float(k + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var o := centre + Vector3(0, y, 0)
			var a := o + d0 * inner
			var b := o + d0 * outer
			var c := o + d1 * outer
			var e := o + d1 * inner
			if inner < 0.0001:
				tri(s, o, b, c, Vector3.UP, Vector2(o.x, o.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
			else:
				quad(s, a, b, c, e, Vector3.UP)

	func commit(materials: Array) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for i in range(surfaces.size()):
			var d: Dictionary = surfaces[i]
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var v: PackedVector3Array = d["v"]
			if v.is_empty():
				# Keep the surface index stable for the material slots.
				v = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
				d["n"] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
				d["uv"] = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = d["n"]
			arrays[Mesh.ARRAY_TEX_UV] = d["uv"]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if i < materials.size() and materials[i] != null:
				mesh.surface_set_material(i, materials[i])
		return mesh


# ---------------------------------------------------------------------------
# Spike. Local to the spike body: the old CylinderMesh spanned y -0.17..0.17, and so does
# this. Surfaces: 0 collar (dark), 1 shaft and point (steel).
# ---------------------------------------------------------------------------
static func spike(materials: Array) -> ArrayMesh:
	var b := Builder.new()
	b.lathe(0, Vector3.ZERO, [[0.088, -0.17], [0.088, -0.10], [0.070, -0.085], [0.058, -0.085]], 8, false)
	b.lathe(1, Vector3.ZERO, [[0.058, -0.085], [0.052, 0.05], [0.046, 0.07], [0.0, 0.17]], 8, false)
	return b.commit(materials)


## The spike patch's bezel and recess, flat on the floor. `extent` is the patch side.
## Surfaces: 0 recess plate (dark), 1 bore holes (near black), 2 frame (safety paint),
## 3 lamp dashes (emissive, driven by the telegraph).
static func spike_bezel(extent: float, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	var h := extent * 0.5 + 0.02
	b.box(0, Vector3(0, 0.003, 0), Vector3(extent + 0.04, 0.006, extent + 0.04))
	var step := extent / 3.0
	for gx in range(3):
		for gz in range(3):
			var c := Vector3((float(gx) - 1.0) * step, 0.0, (float(gz) - 1.0) * step)
			b.ring(1, c, 0.0, 0.1, 0.0065, 10)
			b.ring(2, c, 0.1, 0.125, 0.0068, 10)
	var w := 0.11
	var o := h + w
	for side in [[Vector3(0, 0, -h - w * 0.5), Vector3(o * 2.0, 0.018, w)],
			[Vector3(0, 0, h + w * 0.5), Vector3(o * 2.0, 0.018, w)],
			[Vector3(-h - w * 0.5, 0, 0), Vector3(w, 0.018, h * 2.0)],
			[Vector3(h + w * 0.5, 0, 0), Vector3(w, 0.018, h * 2.0)]]:
		var c: Vector3 = side[0]
		var sz: Vector3 = side[1]
		b.box(2, c + Vector3(0, 0.009, 0), sz)
	# Lamp dashes set into the frame, four per side.
	for i in range(4):
		var t := -h + (float(i) + 0.5) * (h * 2.0) / 4.0
		for c in [Vector3(t, 0, -h - w * 0.5), Vector3(t, 0, h + w * 0.5)]:
			b.box(3, c + Vector3(0, 0.0185, 0), Vector3(h * 2.0 / 4.0 * 0.6, 0.004, w * 0.4))
		for c in [Vector3(-h - w * 0.5, 0, t), Vector3(h + w * 0.5, 0, t)]:
			b.box(3, c + Vector3(0, 0.0185, 0), Vector3(w * 0.4, 0.004, h * 2.0 / 4.0 * 0.6))
	return b.commit(materials)


# ---------------------------------------------------------------------------
# Grinder disc, local to the disc node (which spins). Face top at y 0.025.
# Surfaces: 0 machined face (steel), 1 teeth (dark steel), 2 hub and bolts (dark).
# ---------------------------------------------------------------------------
static func grinder_disc(radius: float, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	# The face: a shallow dish with a chamfered rim, bright where the light rakes it.
	b.lathe(0, Vector3.ZERO, [[radius - 0.02, -0.025], [radius, -0.005], [radius - 0.015, 0.02],
		[radius - 0.05, 0.025]], 40)
	b.ring(0, Vector3.ZERO, 0.15, radius - 0.05, 0.025, 40)
	# Radial relief slots, darker (tooth surface), so the spin reads even under blur.
	for i in range(6):
		var a := TAU * float(i) / 6.0 + 0.2
		b.ring(1, Vector3.ZERO, 0.2, radius - 0.1, 0.0255, 2, a, a + 0.09)
	# Teeth: 24 hooked wedges standing just proud of the rim.
	var teeth := 24
	for i in range(teeth):
		var a0 := TAU * float(i) / float(teeth)
		var a1 := a0 + TAU / float(teeth) * 0.55
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var inner := radius - 0.03
		var outer := radius + 0.035
		var top := 0.02
		var bot := -0.01
		var a := p0 * inner + Vector3(0, top, 0)
		var bb := p0 * outer + Vector3(0, top, 0)
		var c := p1 * inner + Vector3(0, top, 0)
		b.tri(1, a, bb, c, Vector3.UP)
		var a2 := p0 * inner + Vector3(0, bot, 0)
		var b2 := p0 * outer + Vector3(0, bot, 0)
		var c2 := p1 * inner + Vector3(0, bot, 0)
		# The cutting face and the back slope.
		b.quad(1, a2, b2, bb, a, (p0.cross(Vector3.UP)).normalized() * -1.0)
		var back_n := ((bb - c).cross(Vector3.UP)).normalized()
		if back_n.dot(p0 + p1) < 0.0:
			back_n = -back_n
		b.quad(1, b2, c2, c, bb, back_n)
	# Hub boss and six bolt heads.
	b.lathe(2, Vector3.ZERO, [[0.15, 0.025], [0.14, 0.045], [0.12, 0.05], [0.0, 0.05]], 20)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var c := Vector3(cos(a), 0, sin(a)) * 0.09
		b.lathe(2, c, [[0.018, 0.05], [0.018, 0.062], [0.0, 0.062]], 6, false)
	return b.commit(materials)


## The grinder's well, collar and lamp ring, flat on the floor round the disc.
## Surfaces: 0 well (dark), 1 collar (safety paint), 2 lamp dashes (emissive).
static func grinder_well(radius: float, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	b.ring(0, Vector3.ZERO, 0.0, radius + 0.12, 0.004, 32)
	b.lathe(1, Vector3.ZERO, [[radius + 0.22, 0.0], [radius + 0.2, 0.016], [radius + 0.12, 0.016],
		[radius + 0.11, 0.004]], 36)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		b.ring(2, Vector3.ZERO, radius + 0.235, radius + 0.285, 0.0065, 2, a, a + TAU / 24.0)
	return b.commit(materials)


# ---------------------------------------------------------------------------
# Flame nozzle, local to the jet holder: origin on the wall face, -Z into the arena.
# Surfaces: 0 housing (dark), 1 barrel (steel), 2 bezel (emissive heat ring), 3 fuel line.
# ---------------------------------------------------------------------------
static func flame_nozzle(wall_top_local: float, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	b.box(0, Vector3(0, -0.01, -0.05), Vector3(0.36, 0.30, 0.10), true)
	# The barrel, lathed about +Y then laid along -Z.
	var barrel := Builder.new()
	barrel.lathe(0, Vector3.ZERO, [[0.10, 0.0], [0.10, 0.04], [0.082, 0.05], [0.075, 0.20],
		[0.088, 0.21], [0.088, 0.25]], 12)
	barrel.lathe(1, Vector3.ZERO, [[0.088, 0.25], [0.06, 0.255], [0.05, 0.24]], 12)
	var rot := Basis(Vector3.RIGHT, -PI * 0.5)       # +Y -> -Z
	for pair in [[0, 1], [1, 2]]:
		var src: Dictionary = barrel.surface(pair[0])
		var dst: Dictionary = b.surface(pair[1])
		var off := Vector3(0, 0, -0.09)
		for i in range((src["v"] as PackedVector3Array).size()):
			(dst["v"] as PackedVector3Array).append(rot * (src["v"] as PackedVector3Array)[i] + off)
			(dst["n"] as PackedVector3Array).append(rot * (src["n"] as PackedVector3Array)[i])
			(dst["uv"] as PackedVector2Array).append((src["uv"] as PackedVector2Array)[i])
	# Fuel line up the wall to the cap.
	var line_top := maxf(wall_top_local, 0.2)
	b.lathe(3, Vector3(0.12, 0.14, -0.03), [[0.022, 0.0], [0.022, line_top - 0.14]], 8)
	b.box(3, Vector3(0.12, 0.13, -0.03), Vector3(0.07, 0.05, 0.07))
	return b.commit(materials)


# ---------------------------------------------------------------------------
# Turntable top, local to the turntable body (its top face is at y 0.05). Spins as
# presentation. Surfaces: 0 plate (steel), 1 edge band and arrows (paint), 2 rim lamps.
# ---------------------------------------------------------------------------
static func turntable_top(radius: float, clockwise: bool, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	b.ring(0, Vector3.ZERO, 0.0, radius - 0.14, 0.051, 48)
	b.lathe(1, Vector3.ZERO, [[radius, -0.05], [radius, 0.04], [radius - 0.02, 0.052],
		[radius - 0.14, 0.052]], 48)
	# Four curved arrows pointing the way it turns.
	var dir := -1.0 if clockwise else 1.0
	for i in range(4):
		var a0 := TAU * float(i) / 4.0
		var span := 0.75
		b.ring(1, Vector3.ZERO, radius * 0.62, radius * 0.72, 0.0535, 8, a0, a0 + span * dir)
		var tip_a := a0 + (span + 0.22) * dir
		var base_a := a0 + span * dir
		var tip := Vector3(cos(tip_a), 0, sin(tip_a)) * radius * 0.67 + Vector3(0, 0.0535, 0)
		var in_p := Vector3(cos(base_a), 0, sin(base_a)) * radius * 0.54 + Vector3(0, 0.0535, 0)
		var out_p := Vector3(cos(base_a), 0, sin(base_a)) * radius * 0.80 + Vector3(0, 0.0535, 0)
		b.tri(1, in_p, out_p, tip, Vector3.UP)
	# Hub.
	b.lathe(1, Vector3.ZERO, [[0.26, 0.051], [0.24, 0.07], [0.0, 0.07]], 20)
	for i in range(24):
		var a := TAU * float(i) / 24.0
		b.ring(2, Vector3.ZERO, radius - 0.12, radius - 0.06, 0.0535, 2, a, a + TAU / 48.0)
	return b.commit(materials)


# ---------------------------------------------------------------------------
# Crush ram head, local to the ram body (a RAM_DEPTH x RAM_HEIGHT x RAM_LENGTH box
# centred on it; `sign_x` is the way it travels). Surfaces: 0 body (dark painted steel),
# 1 piston rods (chrome), 2 bolt heads and face frame (steel).
# ---------------------------------------------------------------------------
static func ram_head(size: Vector3, sign_x: float, rod_length: float, materials: Array) -> ArrayMesh:
	var b := Builder.new()
	var h := size * 0.5
	var bev := 0.035
	# Main block, then bevel strips on the four long edges facing the arena and the top.
	b.box(0, Vector3(-sign_x * bev * 0.5, 0, 0), Vector3(size.x - bev, size.y - bev * 2.0, size.z))
	b.box(0, Vector3(0, 0, 0), Vector3(size.x - bev * 2.0, size.y, size.z - bev * 2.0))
	b.box(0, Vector3(0, 0, 0), Vector3(size.x, size.y - bev * 2.0, size.z - bev * 2.0))
	# Ribs across the top, so it reads as a cast head and not a box.
	for i in range(5):
		var z := -h.z + (float(i) + 0.5) * size.z / 5.0
		b.box(0, Vector3(0, h.y + 0.012, z), Vector3(size.x * 0.8, 0.024, 0.06))
	# Two chrome rods out of the back, into the wall.
	for z in [-h.z * 0.55, h.z * 0.55]:
		var rod := Builder.new()
		rod.lathe(0, Vector3.ZERO, [[0.055, 0.0], [0.055, rod_length]], 12)
		var src: Dictionary = rod.surface(0)
		var dst: Dictionary = b.surface(1)
		# +Y -> -sign_x (back into the wall), starting at the back face.
		var basis := Basis(Vector3.BACK, PI * 0.5 * sign_x)
		var off := Vector3(-sign_x * h.x, 0.0, z)
		for i in range((src["v"] as PackedVector3Array).size()):
			(dst["v"] as PackedVector3Array).append(basis * (src["v"] as PackedVector3Array)[i] + off)
			(dst["n"] as PackedVector3Array).append(basis * (src["n"] as PackedVector3Array)[i])
			(dst["uv"] as PackedVector2Array).append((src["uv"] as PackedVector2Array)[i])
	# A steel frame round the business face, and bolt heads at its corners.
	var fx := sign_x * (h.x + 0.002)
	for c in [Vector3(fx, h.y - 0.05, 0), Vector3(fx, -h.y + 0.05, 0)]:
		b.box(2, c, Vector3(0.03, 0.06, size.z - 0.02))
	for z in [-h.z + 0.08, -h.z * 0.33, h.z * 0.33, h.z - 0.08]:
		for y in [h.y - 0.05, -h.y + 0.05]:
			b.box(2, Vector3(fx + sign_x * 0.02, y, z), Vector3(0.025, 0.045, 0.045))
	return b.commit(materials)
