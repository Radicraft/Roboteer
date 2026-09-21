class_name FxEmitters extends Node3D
## A pool of aimable particle emitters, taken out by NAME and handed back, for the
## effects that RUN rather than happen (wave P, agent F).
##
## `FightParticles` covers the events: a hit bursts sparks, a detach puffs dust, and
## its emitters are round robin because an event is over by the time the next one
## arrives. Wave P is full of the other kind. A drill grinds for three seconds, a
## fire patch burns for six, a hover's skirt throws dust for the whole fight, and an
## overcharge core smokes until its weapon idles. Those need an emitter that STAYS
## on, follows something, and is given back when the thing it belongs to stops.
##
##     emitters.hold("drill:player-1", FxEmitters.SPARK, tip, along_lance, 1.0)
##     ...
##     emitters.sweep()      # anything not held this frame is released
##
## THE POOL IS THE CAP. `POOL` emitters exist and no more; a hold that cannot get one
## is refused and returns false, which is a quieter fight rather than a slower one.
## A key that was held last frame and is not held this frame is released by `sweep()`,
## so a machine that is eliminated mid grind cannot leak an emitter.
##
## FIVE FLAVOURS, each a different physical thing:
##
##   SPARK   metal being cut: hot, fast, gravity, dead in a quarter second
##   CURL    swarf off a drill flute: slow, heavy, tumbling, cools as it falls
##   SMOKE   what is left after a fire: grey, rising, slow, opaque, never emissive
##   EMBER   what the fire throws up: small, warm, rising, dying
##   DUST    the floor being disturbed: pale, low, spreading, settling
##
## Presentation only, stepped by its owner on `FightFx`'s clock. Headless has no
## renderer and therefore never simulates a particle, so the tests assert on which
## emitters are ON, never on particle output (`FightParticles.gpu_available()`).

enum { SPARK, CURL, SMOKE, EMBER, DUST }
const FLAVOURS := 5

## How many emitters exist. Measured against the worst realistic frame: two machines
## each grinding (2), a twin saw's two blades (2), two hovers throwing skirt dust (2),
## four fire patches burning (4 smoke + 2 ember, capped by WeaponFx), a cooking core
## (1) and a charge in flight (1) is about 12, and the last two are the headroom that
## keeps a Rumble from refusing the player's own weapon a voice.
const POOL := 14

## Per flavour: particle count and life in seconds. Counts are deliberately small.
## Eight of these can be live at once, where `FightParticles` only ever has one or
## two, so a flavour that cost 48 particles the way an impact does would be eight
## times the impact budget standing still.
const AMOUNTS := [20, 8, 14, 10, 16]
const LIVES := [0.28, 0.85, 1.30, 0.70, 0.95]

var _emitters: Array[GPUParticles3D] = []
var _flavour := PackedInt32Array()          ## what each slot is configured as, -1 = none
var _busy := PackedByteArray()
var _shot_left := PackedFloat32Array()      ## > 0 while a one shot is finishing
var _process_materials: Array = []          ## flavour -> ParticleProcessMaterial
var _draw_meshes: Array = []                ## flavour -> Mesh
var _draw_materials: Array = []             ## flavour -> Material
var _slot_of: Dictionary = {}               ## key -> slot index
var _touched: Dictionary = {}               ## key -> true, this frame
var _refused: int = 0


func _ready() -> void:
	_build()
	set_process(false)


## --- public API --------------------------------------------------------------

## Hold `key` on `flavour`, pointed along `aim` from `at`, at `level` (0..1, the
## emitter's `amount_ratio`). Call it every frame the effect is running. Returns
## false when the pool is full, which is the cap doing its job.
func hold(key: String, flavour: int, at: Vector3, aim: Vector3,
		level: float = 1.0) -> bool:
	if flavour < 0 or flavour >= FLAVOURS:
		return false
	_touched[key] = true
	var slot: int = int(_slot_of.get(key, -1))
	if slot < 0:
		slot = _take(flavour, false)
		if slot < 0:
			_refused += 1
			return false
		_slot_of[key] = slot
		_emitters[slot].restart()
	var p := _emitters[slot]
	if _flavour[slot] != flavour:
		_dress(slot, flavour)
	p.global_position = at
	_aim(p, aim)
	p.amount_ratio = clampf(level, 0.05, 1.0)
	p.emitting = true
	return true


## Hand `key` back. Safe to call for a key that is not held.
func release(key: String) -> void:
	var slot: int = int(_slot_of.get(key, -1))
	_slot_of.erase(key)
	_touched.erase(key)
	if slot < 0:
		return
	_free_slot(slot)


## Release every key that was not held this frame. The owner calls it once, at the
## end of its own step, so an effect stops by simply not being asked for again and a
## machine that vanishes cannot leave an emitter running.
func sweep() -> void:
	if not _slot_of.is_empty():
		var drop: Array[String] = []
		for key_variant in _slot_of.keys():
			var key := str(key_variant)
			if not _touched.has(key):
				drop.append(key)
		for key in drop:
			release(key)
	_touched.clear()


## One puff: an emitter taken out as a ONE SHOT and handed back when its particles
## have finished. Used for the moments (a footfall, a muzzle, a machine thrown up by
## the vortex) rather than the processes.
func burst(flavour: int, at: Vector3, aim: Vector3, level: float = 1.0) -> bool:
	if flavour < 0 or flavour >= FLAVOURS:
		return false
	var slot := _take(flavour, true)
	if slot < 0:
		_refused += 1
		return false
	if _flavour[slot] != flavour:
		_dress(slot, flavour)
	var p := _emitters[slot]
	p.one_shot = true
	p.global_position = at
	_aim(p, aim)
	p.amount_ratio = clampf(level, 0.05, 1.0)
	p.restart()
	p.emitting = true
	_shot_left[slot] = float(LIVES[flavour]) * 1.15
	return true


## Age the one shots. Held emitters need no stepping: the caller re-points them.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	for i in POOL:
		if _shot_left[i] <= 0.0:
			continue
		_shot_left[i] -= delta
		if _shot_left[i] <= 0.0:
			_free_slot(i)


func stop_all() -> void:
	_slot_of.clear()
	_touched.clear()
	for i in POOL:
		_free_slot(i)


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func pool_size() -> int:
	return POOL


## Emitters currently emitting, held and one shot together.
func live_count() -> int:
	var n := 0
	for i in POOL:
		if _busy[i] == 1:
			n += 1
	return n


func held_count() -> int:
	return _slot_of.size()


func is_held(key: String) -> bool:
	return _slot_of.has(key)


func flavour_of(key: String) -> int:
	var slot: int = int(_slot_of.get(key, -1))
	return _flavour[slot] if slot >= 0 else -1


## How many holds and bursts the pool has refused. Non zero means the fight asked for
## more simultaneous effects than the cap allows, which is a number worth printing
## rather than a failure.
func refused_count() -> int:
	return _refused


func emitter_for(key: String) -> GPUParticles3D:
	var slot: int = int(_slot_of.get(key, -1))
	return _emitters[slot] if slot >= 0 else null


## --- internals --------------------------------------------------------------

func _build() -> void:
	_flavour.resize(POOL)
	_busy.resize(POOL)
	_shot_left.resize(POOL)
	for f in FLAVOURS:
		_process_materials.append(_process_for(f))
		_draw_meshes.append(_mesh_for(f))
		_draw_materials.append(_material_for(f))
	for i in POOL:
		var p := GPUParticles3D.new()
		p.name = "Emitter%d" % i
		p.emitting = false
		p.one_shot = false
		p.explosiveness = 0.0
		p.local_coords = false          # the fire stays where it was thrown
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		add_child(p)
		_emitters.append(p)
		_flavour[i] = -1
		_busy[i] = 0
		_shot_left[i] = 0.0
		_dress(i, SPARK)


## Point an emitter's local +Y along `aim`, which is the direction every one of the
## process materials emits in. A zero aim falls back to straight up.
static func _aim(p: GPUParticles3D, aim: Vector3) -> void:
	var dir := aim
	if dir.length_squared() < 1e-8:
		dir = Vector3.UP
	dir = dir.normalized()
	if absf(dir.dot(Vector3.UP)) > 0.999:
		p.global_basis = Basis.IDENTITY if dir.y > 0.0 \
			else Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK)
		return
	var side := dir.cross(Vector3.UP).normalized()
	var back := side.cross(dir).normalized()
	p.global_basis = Basis(side, dir, back)


## Configure slot `i` as `flavour`. The process material, the mesh and the material
## are SHARED per flavour: two live emitters of one flavour differ in where they are,
## where they point and their `amount_ratio`, which is everything this node needs and
## costs no extra resources.
func _dress(i: int, flavour: int) -> void:
	var p := _emitters[i]
	p.amount = int(AMOUNTS[flavour])
	p.lifetime = float(LIVES[flavour])
	p.process_material = _process_materials[flavour]
	p.draw_pass_1 = _draw_meshes[flavour]
	p.material_override = _draw_materials[flavour]
	p.explosiveness = 0.55 if flavour == DUST else 0.0
	_flavour[i] = flavour


func _take(flavour: int, one_shot: bool) -> int:
	# Prefer a free slot that is already dressed as this flavour: no resource churn.
	for i in POOL:
		if _busy[i] == 0 and _shot_left[i] <= 0.0 and _flavour[i] == flavour:
			_busy[i] = 1
			_emitters[i].one_shot = one_shot
			return i
	for i in POOL:
		if _busy[i] == 0 and _shot_left[i] <= 0.0:
			_busy[i] = 1
			_emitters[i].one_shot = one_shot
			return i
	return -1


func _free_slot(i: int) -> void:
	if i < 0 or i >= POOL:
		return
	_busy[i] = 0
	_shot_left[i] = 0.0
	var p := _emitters[i]
	p.emitting = false
	p.one_shot = false


## --- the five flavours -------------------------------------------------------

static func _process_for(flavour: int) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.direction = Vector3(0.0, 1.0, 0.0)       # the node is aimed, not the material
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	match flavour:
		SPARK:
			# Metal being cut. A tight fan, fast, heavy gravity, and dead before it
			# reaches the floor: the art direction's rule is that the only persistent
			# saturated warm in the frame is the gold of the bolts.
			m.emission_sphere_radius = 0.02
			m.spread = 26.0
			m.initial_velocity_min = 2.6
			m.initial_velocity_max = 6.2
			m.gravity = Vector3(0.0, -11.0, 0.0)
			m.damping_min = 1.5
			m.damping_max = 4.0
			m.scale_min = 0.8
			m.scale_max = 1.7
			m.color_ramp = _ramp([
				[0.0, Color(1.0, 0.98, 0.90, 1.0)],
				[0.3, Color(1.0, 0.72, 0.30, 1.0)],
				[1.0, Color(0.82, 0.30, 0.08, 0.0)]])
		CURL:
			# Swarf: a drill flute lifts a curl of metal out of the hole and throws it
			# clear. Heavy, slow, tumbling, and it cools from orange to grey on the
			# way down, which is the whole reason it is not a spark.
			m.emission_sphere_radius = 0.025
			m.spread = 40.0
			m.initial_velocity_min = 0.8
			m.initial_velocity_max = 2.2
			m.gravity = Vector3(0.0, -9.0, 0.0)
			m.damping_min = 0.2
			m.damping_max = 0.8
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -420.0
			m.angular_velocity_max = 420.0
			m.scale_min = 0.9
			m.scale_max = 1.6
			m.color_ramp = _ramp([
				[0.0, Color(1.0, 0.66, 0.24, 1.0)],
				[0.35, Color(0.78, 0.46, 0.22, 1.0)],
				[1.0, Color(0.42, 0.44, 0.47, 0.0)]])
		SMOKE:
			# What is left after a fire. Grey, rising, slowing, and ALPHA BLENDED, not
			# additive: smoke has to occlude what is behind it or it reads as more
			# flame. It is also the thing that says a fire is still burning when the
			# fire itself is behind a machine.
			m.emission_sphere_radius = 0.10
			m.spread = 18.0
			m.initial_velocity_min = 0.5
			m.initial_velocity_max = 1.3
			m.gravity = Vector3(0.0, 0.55, 0.0)
			m.damping_min = 0.6
			m.damping_max = 1.4
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -30.0
			m.angular_velocity_max = 30.0
			m.scale_min = 1.1
			m.scale_max = 2.4
			m.scale_curve = _curve([[0.0, 0.45], [0.5, 1.0], [1.0, 1.5]])
			m.color_ramp = _ramp([
				[0.0, Color(0.30, 0.29, 0.28, 0.0)],
				[0.15, Color(0.36, 0.35, 0.34, 0.62)],
				[1.0, Color(0.52, 0.52, 0.53, 0.0)]])
		EMBER:
			# What the fire throws up. Small, warm, and it DIES: an ember that reaches
			# the top of the frame is a firework.
			m.emission_sphere_radius = 0.18
			m.spread = 34.0
			m.initial_velocity_min = 0.9
			m.initial_velocity_max = 2.4
			m.gravity = Vector3(0.0, 1.4, 0.0)
			m.damping_min = 1.2
			m.damping_max = 2.6
			m.scale_min = 0.4
			m.scale_max = 1.0
			m.color_ramp = _ramp([
				[0.0, Color(1.0, 0.86, 0.52, 1.0)],
				[0.45, Color(1.0, 0.48, 0.14, 0.85)],
				[1.0, Color(0.55, 0.12, 0.02, 0.0)]])
		_:
			# DUST. The floor being disturbed: a hover's skirt, a foot landing, a
			# machine thrown up off the boards. Pale, wide, low and it settles.
			m.emission_sphere_radius = 0.12
			m.spread = 62.0
			m.initial_velocity_min = 0.4
			m.initial_velocity_max = 1.6
			m.gravity = Vector3(0.0, -0.9, 0.0)
			m.damping_min = 1.0
			m.damping_max = 2.4
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.angular_velocity_min = -45.0
			m.angular_velocity_max = 45.0
			m.scale_min = 0.9
			m.scale_max = 2.0
			m.scale_curve = _curve([[0.0, 0.5], [0.6, 1.0], [1.0, 1.25]])
			m.color_ramp = _ramp([
				[0.0, Color(0.62, 0.63, 0.65, 0.0)],
				[0.18, Color(0.68, 0.69, 0.71, 0.55)],
				[1.0, Color(0.55, 0.56, 0.58, 0.0)]])
	return m


static func _mesh_for(flavour: int) -> Mesh:
	var quad := QuadMesh.new()
	match flavour:
		SPARK:
			quad.size = Vector2(0.022, 0.10)      # a streak, not a dot
		CURL:
			quad.size = Vector2(0.030, 0.030)
		SMOKE:
			quad.size = Vector2(0.34, 0.34)
		EMBER:
			quad.size = Vector2(0.045, 0.045)
		_:
			quad.size = Vector2(0.30, 0.30)
	return quad


static func _material_for(flavour: int) -> Material:
	if flavour == SMOKE or flavour == DUST:
		# Alpha blended on a soft authored billboard: it must occlude, not glow.
		return FxMaterials.soft_smoke(FxMaterials.texture("dust_soft.png"))
	if flavour == CURL:
		# Swarf is METAL that happens to be hot, so it is not additive: it cools to
		# grey, and an additive grey is invisible.
		return FxMaterials.soft_smoke(FxMaterials.texture("spark_glow.png"))
	var energy := FxMaterials.SPARK_ENERGY
	var tex: Texture2D = null
	if flavour == EMBER:
		energy = FxMaterials.FLAME_ENERGY
		tex = FxMaterials.texture("spark_glow.png")
	var m := FxMaterials.additive(tex, Color.WHITE, energy, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	return m


static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var last: int = points.size() - 1
	g.set_offset(0, float(points[0][0]))
	g.set_color(0, points[0][1] as Color)
	g.set_offset(1, float(points[last][0]))
	g.set_color(1, points[last][1] as Color)
	for i in range(1, last):
		g.add_point(float(points[i][0]), points[i][1] as Color)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(Vector2(float(pt[0]), float(pt[1])))
	var t := CurveTexture.new()
	t.curve = c
	return t
