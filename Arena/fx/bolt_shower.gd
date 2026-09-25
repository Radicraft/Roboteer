class_name BoltShower extends MultiMeshInstance3D
## The scrap shower: brief-v3.md §6 "Bolt showers, damage feedback and scrap, in one effect".
##
## Every piece is a pure presentation particle. Nothing here is a physics body, nothing
## here runs in _physics_process, and nothing here can change the fight. Pieces visualise
## scrap that has ALREADY been awarded, so a piece that never lands is a bug (the pool
## force collects anything that outlives MAX_LIFE_S so the scrap is never lost).
##
## Life of one piece:
##   1. launch in an up-biased cone, 2 to 5 m/s (x severity), under gravity
##   2. exactly one analytic floor bounce at y = 0, restitution 0.4
##   3. wait out its scatter delay (250 ms +/- 90 %) -- this pause IS the effect
##   4. magnetise to the live attacker position, acceleration k / max(distance, 0.3)
##   5. arrive within 0.25 m, emit collected(bot_id), free its pool slot
##
## FightFx drives step(); this node keeps its own _process off so the headless test
## can advance it at a fixed delta.
##
## G4 (graphics bar pass, docs/graphics-fx-notes.md) changed only what a piece LOOKS
## like. Every number above, the pool, the scatter, the magnet and the collect are
## untouched, and fx_test.gd still measures the same timings it always did.
##
## --------------------------------------------------------------------------------
## WAVE F (agent F3, docs/wave-f-f3-notes.md). The owner played the wave G build and
## said "the scrap won doesn't look like scrap". He was right: every particle was the
## same gold hex nut, so a saw scrape and a panel being torn off shed identical
## confetti and none of it looked like anything had broken.
##
## What changed, and NOTHING ELSE DID:
##
##   * the uniform gold bolt is now a MIX of torn metal -- bent armour plate, torn
##     shard, bolt with washer, wheel nut, snapped bracket, coil spring, wire tangle,
##     and a wheel silhouette when a wheel is what came off. `ScrapPieces` owns the
##     meshes, the shader and the banks; this file owns every position and every timing.
##   * the mix follows the SEVERITY of the hit and the MATERIAL of the face that was
##     hit: steel plate for steel, milky shards for polycarbonate, black chips for
##     HDPE, and steel fasteners out of all three because a plastic lid is still
##     bolted on with steel bolts.
##   * pieces are dark metal with a WARM HOT EDGE that cools over 0.6 s and then
##     re-lights to a gold ember when the magnet takes them, which is what keeps the
##     brief's readability rule intact: what is warm and moving toward you is yours,
##     what is grey and lying still (`DebrisChips`) is scenery.
##   * bigger hits throw bigger pieces further; a piece that lands kicks a tiny dust
##     ring, stops tumbling while it sits out its scatter delay, and starts turning
##     again when the magnet lifts it.
##   * sparks at the tear, and a short smoke puff on a heavy hit (`ScrapSparks`).
##
## What did NOT change, and is asserted in fx_test.gd: the pool size, the scatter
## delay and its jitter, the magnet constants, the arrival test, the ledger, the
## per piece `collected` signal, the MAX_LIFE_S force collect, the gold streak and the
## gold collect flash.
##
## This node is still a MultiMeshInstance3D because `fx.tscn` says so, but it no
## longer draws anything itself: its own `multimesh` is left null and every piece is
## drawn by a `ScrapPieces` bank. A MultiMeshInstance3D with no multimesh is free.

## One piece reached its target. The scrap it carries is FightFx's ledger, not ours.
signal collected(bot_id: String)

const GRAVITY := 9.8
const RESTITUTION := 0.4            # the single floor bounce
const GROUND_FRICTION := 0.72       # horizontal speed kept through that bounce
const REST_DRAG := 3.0              # per second, once a piece is lying on the floor
const SPEED_CAP := 12.0             # m/s, magnet phase
const ARRIVE_DIST := 0.25           # m
const MAGNET_K := 45.0              # see docs/stage3-fx-notes.md for how this was tuned
const MAGNET_MIN_DIST := 0.3        # the max(distance, 0.3) clamp in the brief
## Per second rate at which the magnet also turns a piece's existing velocity toward
## the target. Pure central attraction is a logarithmic potential: a piece launched
## sideways at 5 m/s goes into a stable ORBIT and never arrives. Measured: at 0 it
## orbits from every distance, at 6 every launch lands in 0.08 to 1.05 s.
const MAGNET_ALIGN := 6.0
const LAUNCH_SPEED_MIN := 2.0
const LAUNCH_SPEED_MAX := 5.0
const LAUNCH_CONE_DEG := 55.0       # half angle around +Y, so the shower is up-biased
const SPIN_RATE_MIN := 9.0          # rad/s
const SPIN_RATE_MAX := 20.0
## Second tumble axis. A single axis spin reads as a coin flipping in place; two
## axes at different rates make the facets catch the key light at irregular
## intervals, which is most of what sells a piece as a real machined object.
const SPIN2_RATE_MIN := 4.0
const SPIN2_RATE_MAX := 11.0
## The PHYSICAL size. It sets the height a piece rests at on the floor and therefore
## feeds the ballistics, so it is frozen at the Stage 3 value: changing it would move
## the timings agent B measured and the test asserts.
const BOLT_SIZE := 0.05             # m across the flats of the hex head
## The DRAWN size of the plain bolt, and nothing else. A real 50 mm nut is three
## pixels at the fight framing on a 6.9 inch phone, which is the whole of why the
## first desktop frames showed gold specks instead of a shower. Every other shape has
## its own drawn size in ScrapPieces.KIND_SIZE_M; this one is kept here because
## fx_test.gd measures it against BOLT_SIZE to hold the two apart.
const BOLT_VISUAL_SIZE := 0.09
const SHORT_POOL_SCALE := 1.6       # fewer, bigger pieces when the pool is short
const MAX_LIFE_S := 8.0             # safety net: force collect, never drop scrap

## --- how a piece looks, and for how long ------------------------------------
## The hot edge falls from 1 to 0 over this long. 0.6 s is the brief's own beat: it
## is still cooling while the piece is in the air and it is out by the time the piece
## has settled, so the cooling is something the eye follows rather than a flicker.
const HOT_COOL_S := 0.6
const HOT_EASE := 1.7               # >1 so the glow dies fast then lingers faintly
## When the magnet takes a piece the rim lifts back to a gold ember. This is the one
## thing standing between "dark torn metal" and brief §6's readability rule: a piece
## streaming toward a bot has to say it is SCRAP, and warm is how the art direction
## says that. Structural debris never lights at all.
const MAGNET_EMBER := 0.30
const EMBER_RISE_S := 0.12

## Severity shapes the throw. A scrape sheds small pieces at the low end of the launch
## band; a panel coming off throws big ones a third further.
const LAUNCH_SEVERITY_MIN := 0.78
const LAUNCH_SEVERITY_SPAN := 0.52
const SIZE_SEVERITY_MIN := 0.80
const SIZE_SEVERITY_SPAN := 0.50
const SIZE_JITTER_MIN := 0.85
const SIZE_JITTER_MAX := 1.20
## The dead part's silhouette, thrown once per detach.
const SILHOUETTE_SCALE := 1.9

## A piece that has landed and is nearly still stops turning: scrap spinning on the
## floor reads as a bug, and the stillness is what makes the magnet lift read.
const SETTLE_SPEED := 0.30          # m/s
const SETTLE_DAMP := 9.0            # per second

## HOW LONG THE MAGNET WILL WAIT FOR A LANDING, and why this constant had to exist.
##
## brief v3 §6 is "scatter, bounce, then magnetise", and Stage 3 built exactly that.
## Measured while adding the landing dust (docs/wave-f-f3-notes.md): at a real hit
## height the bounce had NEVER happened. A piece leaves the tear at 2 to 5 m/s inside
## a 55 degree cone, so its upward speed is 1.4 to 6.1 m/s, and from a hit at 0.34 m
## it needs 0.44 s at the very fastest to come back down. The scatter delay is 25 to
## 475 ms. The magnet therefore took essentially every piece in mid air, the single
## analytic bounce was dead code in practice, and nothing ever landed on the floor of
## the arena at all.
##
## So: when a piece's scatter delay runs out while it is still in the air, the magnet
## waits for it to land, but never longer than this. Nothing else moved -- the delay,
## its jitter, the launch band, the cone, the magnet constants and the arrival test
## are all still agent B's. Set this to 0.0 and the effect is exactly what shipped in
## wave G.
const LAND_GRACE_S := 0.30
## And once it has landed it sits for at least this long, so a landing is never an
## instant snatch. Most pieces have more scatter delay left than this and use that
## instead; this is only the floor.
const SIT_AFTER_LAND_S := 0.12

## The landing dust ring. Only a real landing kicks one, and only some of the small
## pieces do, or a 120 piece shower carpets the floor in dust.
const RING_MIN_SPEED := 1.1         # m/s of downward speed at the bounce
const RING_BIG_PIECE := 0.11        # m: anything this long always kicks dust
const RING_CHANCE := 0.4

## A hit at or above this severity also gets a smoke puff. Matches FightFx's own
## light/heavy split (FightFx.IMPACT_HEAVY_SEVERITY) so one hit never reads as two
## different sizes of event.
const SMOKE_SEVERITY := 0.3

## --- trail ------------------------------------------------------------------
## HARD CAP. One streak segment per pool slot and no more, so the trail can never
## cost more draw data than the pieces themselves.
const TRAIL_SEGMENTS := 120
## A segment reaches full brightness, or fades to nothing, in this long. Also the
## length of travel the streak represents.
const TRAIL_LIFE_S := 0.12
## How much travel the streak DRAWS, kept separate from the 120 ms fade so the
## streak could be doubled in length without touching the locked fade time.
const TRAIL_LENGTH_S := 0.24
const TRAIL_MIN_SPEED := 2.2        # m/s; below this a piece draws no streak at all
const TRAIL_FULL_SPEED := 8.0       # m/s at which the streak is at full alpha
## Tuned on the second desktop pass: at 1.10 m and 65 mm the streaks read as TRACER
## FIRE rather than as a stream of scrap, which is the wrong genre entirely. Shorter
## and slimmer keeps the stream and gives the piece itself back the eye.
const TRAIL_MAX_LEN := 0.75         # m, so a capped 12 m/s piece does not draw a spear
const TRAIL_WIDTH := 0.050          # m

## --- collect flash ----------------------------------------------------------
const FLASH_POOL := 8
## 0.26, was 0.48 (the white-out pass, 2026-09-25): a dozen 0.48 m gold pops growing to
## 1.15 m sat over the attacker on every award. Never drawn past FLASH_MAX_SIZE.
const FLASH_SIZE := 0.26            # m, before the pop; FxFlashPool grows it
const FLASH_MAX_SIZE := 0.40
const FLASH_LIFE_S := 0.14

## The world the pools are allowed to live in. Shared by every child pool so a parked
## instance can never collapse the AABB and cull the live ones.
const POOL_AABB := AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))

## A parked instance: zero basis, so it has no area and the renderer draws nothing.
var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _rng := RandomNumberGenerator.new()   # presentation RNG, deliberately unseeded (§7)

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _spin_axis := PackedVector3Array()
var _spin_angle := PackedFloat32Array()
var _spin_rate := PackedFloat32Array()
var _spin_axis2 := PackedVector3Array()
var _spin_angle2 := PackedFloat32Array()
var _spin_rate2 := PackedFloat32Array()
## The tumble rates a piece was born with, so a piece that stopped turning while it
## sat on the floor can start again when the magnet lifts it.
var _spin_born := PackedFloat32Array()
var _spin_born2 := PackedFloat32Array()
var _delay := PackedFloat32Array()       # seconds left before the magnet engages
## Seconds of extra wait the magnet will still give a piece that has not landed yet.
var _grace := PackedFloat32Array()
var _magnet_t := PackedFloat32Array()    # seconds the magnet has had this piece
var _life := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _alive := PackedByteArray()
var _bounced := PackedByteArray()
## Mirror of what we last wrote into a bank: 1 = a real transform, 0 = parked.
var _written := PackedByteArray()
## What this piece IS: a ScrapPieces.KIND_*, its drawn long axis in metres, and the
## surface it is drawn with.
var _kind := PackedInt32Array()
var _size := PackedFloat32Array()
var _tint: PackedColorArray = PackedColorArray()
var _metal := PackedFloat32Array()
var _rough := PackedFloat32Array()
var _bot_id: Array[String] = []
var _getter: Array[Callable] = []

var _free: PackedInt32Array = PackedInt32Array()
var _live_count: int = 0
## Per frame cache of target positions so the getter is called once per bot, not once
## per piece, while still being re-read every frame.
var _target_cache: Dictionary = {}
var _rest_y: float = BOLT_SIZE * 0.2

var _pieces: ScrapPieces = null
## True while every bank has already been told it is empty, so the idle frames between
## showers do not keep re-publishing the same nothing.
var _banks_empty: bool = true
var _sparks: ScrapSparks = null

var _trail: MultiMeshInstance3D = null
var _trail_count: int = 0
var _trail_alpha := PackedFloat32Array()
var _trail_live: int = 0

var _flash: FxFlashPool = null


func _ready() -> void:
	_rng.randomize()
	_build()
	set_process(false)   # FightFx steps us


func _build() -> void:
	# This node draws nothing of its own any more; ScrapPieces owns the banks. The
	# class still extends MultiMeshInstance3D so fx.tscn does not have to change.
	multimesh = null
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = POOL_AABB

	_pieces = ScrapPieces.new()
	_pieces.name = "ScrapPieces"
	add_child(_pieces)
	_pieces.configure(FightTypes.BOLT_POOL, POOL_AABB)

	_sparks = ScrapSparks.new()
	_sparks.name = "ScrapSparks"
	add_child(_sparks)
	_sparks.configure(POOL_AABB)

	var n := FightTypes.BOLT_POOL
	_pos.resize(n)
	_vel.resize(n)
	_spin_axis.resize(n)
	_spin_angle.resize(n)
	_spin_rate.resize(n)
	_spin_axis2.resize(n)
	_spin_angle2.resize(n)
	_spin_rate2.resize(n)
	_spin_born.resize(n)
	_spin_born2.resize(n)
	_delay.resize(n)
	_grace.resize(n)
	_magnet_t.resize(n)
	_life.resize(n)
	_scale.resize(n)
	_alive.resize(n)
	_bounced.resize(n)
	_written.resize(n)
	_kind.resize(n)
	_size.resize(n)
	_tint.resize(n)
	_metal.resize(n)
	_rough.resize(n)
	_bot_id.resize(n)
	_getter.resize(n)
	_free.resize(n)
	for i in n:
		_alive[i] = 0
		_written[i] = 0
		_free[i] = n - 1 - i          # pop_back hands out 0, 1, 2 ... first

	_build_trail()
	_build_flash()


## The streak. Slot i belongs to piece i, so the cap is structural rather than a
## budget somebody has to remember: there can never be more segments than pieces.
func _build_trail() -> void:
	_trail_count = mini(FightTypes.BOLT_POOL, TRAIL_SEGMENTS)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)     # unit quad; the instance basis stretches it
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _trail_count
	_trail = MultiMeshInstance3D.new()
	_trail.name = "BoltTrail"
	_trail.multimesh = mm
	_trail.material_override = FxMaterials.additive(
		FxMaterials.texture("trail_streak.png"),
		FxMaterials.TRAIL_GOLD, FxMaterials.TRAIL_ENERGY, false)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_trail.custom_aabb = POOL_AABB
	add_child(_trail)
	_trail_alpha.resize(_trail_count)
	for i in _trail_count:
		_trail_alpha[i] = 0.0
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


func _build_flash() -> void:
	_flash = FxFlashPool.new()
	_flash.name = "CollectFlash"
	add_child(_flash)
	_flash.configure(FLASH_POOL, FLASH_SIZE, FightTypes.BOLT_GOLD, FLASH_LIFE_S,
		FxMaterials.FLASH_ENERGY, POOL_AABB, FLASH_MAX_SIZE)


## Spawn up to count pieces at origin that magnetise to bot_id.
## target_getter takes a bot_id String and returns the live chassis Vector3.
## Returns how many were actually spawned: when the pool is short we spawn fewer,
## bigger pieces (brief §6 budget rule) and FightFx gives each one a larger share.
##
## `hit` is the damage event that earned the scrap, and it is what decides what the
## shower is MADE of. Keys, all optional:
##   severity  float 0..1   -- how much is thrown, how far, and how big
##   part      String       -- "armour_front", "wheel_fl", "weapon", "core", "drive"
##   victim    String       -- bot id, used to look the face material up
##   material  String       -- the face material, if the caller already knows it
##   detached  bool         -- a component kill: throw the dead part's silhouette
## With no `hit` at all the severity is recovered from the award (FightTypes.scrap_for
## is round(severity x 40)), so an award that arrives without its event still looks
## like the hit it was.
func spawn(origin: Vector3, count: int, bot_id: String, target_getter: Callable,
		hit: Dictionary = {}) -> int:
	if count <= 0:
		return 0
	var n: int = mini(count, _free.size())
	if n <= 0:
		return 0
	var scale: float = 1.0 if n >= count else SHORT_POOL_SCALE

	var severity := clampf(float(hit.get("severity", severity_from_award(count))), 0.0, 1.0)
	var part := str(hit.get("part", "armour_front"))
	var detached := bool(hit.get("detached", false))
	var material := str(hit.get("material", ""))
	if material == "" and _pieces != null:
		material = _pieces.resolve_material(str(hit.get("victim", "")), part)
	if material == "":
		material = "steel"
	var row: PackedFloat32Array = PackedFloat32Array()
	if _pieces != null:
		row = _pieces.weights(material, part, severity)

	# The tear itself: sparks always, smoke only when it was a real blow.
	if _sparks != null:
		_sparks.burst(origin, severity)
		if detached or severity >= SMOKE_SEVERITY:
			_sparks.smoke(origin, severity)

	for k in n:
		var i: int = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		var kind: int = ScrapPieces.pick(row, _rng)
		var size_mul := 1.0
		# A component kill throws what died: one big silhouette, first out of the tear
		# so it leads the shower rather than trailing it.
		if detached and k == 0:
			kind = ScrapPieces.silhouette_kind(part)
			size_mul = SILHOUETTE_SCALE
		_spawn_one(i, origin, bot_id, target_getter, scale, kind, material, severity, size_mul)
	_live_count += n
	return n


## Recover the severity of a hit from the scrap it awarded. FightTypes.scrap_for is
## `round(severity * 40)`, doubled on a detach, so this is that read backwards and
## clamped. Only used when a shower arrives with no damage event attached.
static func severity_from_award(amount: int) -> float:
	return clampf(float(amount) / 40.0, 0.0, 1.0)


func _spawn_one(i: int, origin: Vector3, bot_id: String, target_getter: Callable,
		scale: float, kind: int, material: String, severity: float,
		size_mul: float) -> void:
	_pos[i] = origin + Vector3(
		_rng.randf_range(-0.05, 0.05),
		_rng.randf_range(-0.02, 0.06),
		_rng.randf_range(-0.05, 0.05))
	# Uniform on a spherical cap around +Y: up-biased, never a flat spray.
	var az := _rng.randf_range(0.0, TAU)
	var y := _rng.randf_range(cos(deg_to_rad(LAUNCH_CONE_DEG)), 1.0)
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var dir := Vector3(r * cos(az), y, r * sin(az))
	# Bigger hits throw further. The BAND is agent B's, the multiplier is severity's.
	var throw := LAUNCH_SEVERITY_MIN + LAUNCH_SEVERITY_SPAN * severity
	_vel[i] = dir * _rng.randf_range(LAUNCH_SPEED_MIN, LAUNCH_SPEED_MAX) * throw
	_spin_axis[i] = _random_axis()
	_spin_angle[i] = _rng.randf_range(0.0, TAU)
	_spin_rate[i] = _rng.randf_range(SPIN_RATE_MIN, SPIN_RATE_MAX)
	_spin_axis2[i] = _random_axis()
	_spin_angle2[i] = _rng.randf_range(0.0, TAU)
	_spin_rate2[i] = _rng.randf_range(SPIN2_RATE_MIN, SPIN2_RATE_MAX)
	_spin_born[i] = _spin_rate[i]
	_spin_born2[i] = _spin_rate2[i]
	# The arrival stagger is emergent from this jitter, never scheduled.
	var base := float(FightTypes.BOLT_SCATTER_DELAY_MS) / 1000.0
	_delay[i] = maxf(0.0, base * (1.0 + FightTypes.BOLT_SCATTER_JITTER * _rng.randf_range(-1.0, 1.0)))
	_grace[i] = -1.0        # undecided; see the landing grace in _step_pieces
	_magnet_t[i] = 0.0
	_life[i] = 0.0
	_scale[i] = scale
	_alive[i] = 1
	_bounced[i] = 0

	_kind[i] = kind
	var base_size: float = float(ScrapPieces.KIND_SIZE_M[kind])
	_size[i] = base_size * size_mul * scale \
		* (SIZE_SEVERITY_MIN + SIZE_SEVERITY_SPAN * severity) \
		* _rng.randf_range(SIZE_JITTER_MIN, SIZE_JITTER_MAX)
	var look: Dictionary = ScrapPieces.look_for(kind, material)
	_tint[i] = look["tint"]
	_metal[i] = float(look["metal"])
	_rough[i] = float(look["rough"])

	_bot_id[i] = bot_id
	_getter[i] = target_getter


func _random_axis() -> Vector3:
	var v := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0))
	if v.length_squared() < 0.05:
		return Vector3.UP
	return v.normalized()


## Presentation step. delta is seconds; FightFx passes its own clock delta.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	if _live_count > 0:
		_step_pieces(delta)
	elif _pieces != null and not _banks_empty:
		# The first idle frame after a shower: publish an empty frame so every bank
		# hides itself and the shower costs no draw call at all between hits. Done
		# once rather than every idle frame.
		_pieces.begin_frame()
		_pieces.end_frame()
		_banks_empty = true
	# The streak, the flash, the sparks and the dust outlive the piece that made them,
	# so they are stepped whether or not anything is in flight.
	_decay_trail(delta)
	if _flash != null:
		_flash.step(delta)
	if _sparks != null:
		_sparks.step(delta)


func _step_pieces(delta: float) -> void:
	_target_cache.clear()
	var cam := _camera_position()
	var arrived: Array[String] = []
	if _pieces != null:
		_pieces.begin_frame()
		_banks_empty = false
	for i in FightTypes.BOLT_POOL:
		if _alive[i] == 0:
			continue
		_life[i] += delta
		var done := false
		# Wait while the scatter delay is still running, and then a little longer if
		# the piece is still in the air, so the bounce in brief §6 actually happens.
		var waiting: bool = _delay[i] > 0.0
		if not waiting and _bounced[i] == 0:
			# Decided once, the frame the delay runs out: is this piece nearly down?
			# If it is, the magnet waits for the landing. If it is still high in the
			# air the magnet takes it exactly when it always did, so the front of the
			# stream keeps agent B's timing and only the low, slow pieces land.
			if _grace[i] < 0.0:
				var fall := _time_to_floor(i)
				_grace[i] = fall if fall > 0.0 and fall <= LAND_GRACE_S else 0.0
			if _grace[i] > 0.0:
				_grace[i] -= delta
				waiting = true
		if waiting:
			if _delay[i] > 0.0:
				_delay[i] -= delta
			var landed := _ballistic(i, delta)
			if landed > 0.0:
				_kick_dust(i, landed)
				# It is down: sit for the rest of the scatter delay, or for the floor,
				# whichever is longer.
				_delay[i] = maxf(_delay[i], SIT_AFTER_LAND_S)
				_grace[i] = 0.0
			_settle(i, delta)
		else:
			if _magnet_t[i] <= 0.0:
				# The magnet lifts it: whatever it stopped doing on the floor, it does
				# again in the air.
				_spin_rate[i] = _spin_born[i]
				_spin_rate2[i] = _spin_born2[i]
			_magnet_t[i] += delta
			done = _magnet(i, delta)
		if not done and _life[i] >= MAX_LIFE_S:
			done = true   # never lose scrap to a lost piece
		if done:
			arrived.append(_bot_id[i])
			if _flash != null:
				_flash.flash(_pos[i], _scale[i])
			_retire(i)
			continue
		_spin_angle[i] += _spin_rate[i] * delta
		_spin_angle2[i] += _spin_rate2[i] * delta
		_write_piece(i)
		_write_trail(i, delta, cam)
	if _pieces != null:
		_pieces.end_frame()
	for id in arrived:
		collected.emit(id)


func _write_piece(i: int) -> void:
	if _pieces == null:
		return
	var kind: int = _kind[i]
	var s: float = _size[i] / _pieces.mesh_extent(kind)
	var basis := (Basis(_spin_axis[i], _spin_angle[i])
		* Basis(_spin_axis2[i], _spin_angle2[i])).scaled(Vector3.ONE * s)
	_pieces.write(kind, Transform3D(basis, _pos[i]), _tint[i], _metal[i], _rough[i], _heat(i))
	_written[i] = 1


## The hot edge. It cools from 1 to 0 over HOT_COOL_S, and then the magnet re-lights
## it to a gold ember so the piece still reads as scrap on its way home.
func _heat(i: int) -> float:
	var cool: float = pow(clampf(1.0 - _life[i] / HOT_COOL_S, 0.0, 1.0), HOT_EASE)
	if _magnet_t[i] <= 0.0:
		return cool
	var ember: float = MAGNET_EMBER * clampf(_magnet_t[i] / EMBER_RISE_S, 0.0, 1.0)
	return maxf(cool, ember)


## How long this piece still needs to reach the floor, from where it is and how fast
## it is going. The same closed form as the bounce. Negative means it is not coming
## down inside any sensible time (it is already at rest height, or rising hard).
func _time_to_floor(i: int) -> float:
	var p := _pos[i]
	var v := _vel[i]
	if p.y <= _rest_y:
		return 0.0
	var disc := v.y * v.y + 2.0 * GRAVITY * (p.y - _rest_y)
	if disc < 0.0:
		return -1.0
	return (v.y + sqrt(disc)) / GRAVITY


## A piece lying nearly still stops turning. Scrap spinning on the floor reads as a
## bug, and the stillness is what makes the magnet lifting it read as a lift.
func _settle(i: int, delta: float) -> void:
	if _bounced[i] == 0:
		return
	if _vel[i].length_squared() > SETTLE_SPEED * SETTLE_SPEED:
		return
	var k := minf(1.0, delta * SETTLE_DAMP)
	_spin_rate[i] = lerpf(_spin_rate[i], 0.0, k)
	_spin_rate2[i] = lerpf(_spin_rate2[i], 0.0, k)


## The landing kicks dust. Every big piece does; small ones only sometimes, or a
## 120 piece shower lays a carpet of it.
func _kick_dust(i: int, impact_speed: float) -> void:
	if _sparks == null or impact_speed < RING_MIN_SPEED:
		return
	if _size[i] < RING_BIG_PIECE and _rng.randf() > RING_CHANCE:
		return
	_sparks.ring(_pos[i], _size[i] / RING_BIG_PIECE)


func _retire(i: int) -> void:
	_alive[i] = 0
	_getter[i] = Callable()
	_bot_id[i] = ""
	_free.append(i)
	_live_count -= 1
	_written[i] = 0
	# Nothing to park: a retired piece is simply not written this frame, and
	# ScrapPieces only draws what was written.
	#
	# The streak is deliberately NOT parked either: it keeps its last transform and
	# fades out over TRAIL_LIFE_S, which is what leaves a 120 ms wake behind an
	# arriving piece instead of a hole where it used to be.


## Gravity plus exactly one analytic floor bounce. The bounce is solved for the
## real crossing time inside the frame, so it lands in the same place at 30 fps
## as at 120 fps.
##
## Returns the downward speed the piece hit the floor with, or 0.0 if it did not
## land this frame: the caller turns that into a dust ring.
func _ballistic(i: int, dt: float) -> float:
	var p := _pos[i]
	var v := _vel[i]
	var landed := 0.0
	if _bounced[i] == 0 and v.y < 0.0 and p.y > _rest_y:
		# Solve p.y + v.y t - 0.5 g t^2 = rest_y for the first positive root.
		var disc := v.y * v.y + 2.0 * GRAVITY * (p.y - _rest_y)
		if disc >= 0.0:
			var t_hit := (v.y + sqrt(disc)) / GRAVITY
			if t_hit >= 0.0 and t_hit <= dt:
				p = p + v * t_hit + Vector3(0.0, -0.5 * GRAVITY * t_hit * t_hit, 0.0)
				p.y = _rest_y
				landed = absf(v.y - GRAVITY * t_hit)
				v.y = -(v.y - GRAVITY * t_hit) * RESTITUTION
				v.x *= GROUND_FRICTION
				v.z *= GROUND_FRICTION
				_bounced[i] = 1
				dt -= t_hit
	v.y -= GRAVITY * dt
	p += v * dt
	if p.y < _rest_y:
		p.y = _rest_y
		if _bounced[i] == 0:
			landed = maxf(landed, absf(v.y))
		v.y = 0.0
		var drag := exp(-REST_DRAG * dt)
		v.x *= drag
		v.z *= drag
		_bounced[i] = 1
	_pos[i] = p
	_vel[i] = v
	return landed


## Magnet phase. Acceleration scales inversely with distance so pieces speed up as
## they close (brief §6: constant velocity travel looks lifeless at any speed).
## Returns true when the piece has arrived.
func _magnet(i: int, dt: float) -> bool:
	var target := _target_of(i)
	var p := _pos[i]
	var to := target - p
	var d := to.length()
	if d <= ARRIVE_DIST:
		return true
	var dir := to / d
	var v := _vel[i]
	# Steer the speed the piece already has toward the target before adding the pull,
	# or a sideways launch orbits forever instead of streaming home.
	v = v.lerp(dir * v.length(), clampf(MAGNET_ALIGN * dt, 0.0, 1.0))
	v += dir * (MAGNET_K / maxf(d, MAGNET_MIN_DIST)) * dt
	var speed := v.length()
	if speed > SPEED_CAP:
		v = v * (SPEED_CAP / speed)
	var next := p + v * dt
	_pos[i] = next
	_vel[i] = v
	# A capped piece covers 0.2 m per frame at 60 fps and can step straight over the
	# 0.25 m arrival ball on a slow frame, so test the whole segment, not the endpoint.
	return _segment_distance(p, next, target) <= ARRIVE_DIST


func _target_of(i: int) -> Vector3:
	var id := _bot_id[i]
	if _target_cache.has(id):
		return _target_cache[id]
	var pos := _pos[i]
	var cb := _getter[i]
	if cb.is_valid():
		var got: Variant = cb.call(id)
		if got is Vector3:
			pos = got
	_target_cache[id] = pos
	return pos


static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## --- the streak -------------------------------------------------------------

## Where the fight camera is, so a streak can be turned to face it. A velocity
## aligned quad cannot use BILLBOARD_FIXED_Y: Godot pins that to WORLD +Y, not to
## the instance's own Y, so a horizontal streak would be edge on. One camera lookup
## per frame and a cross product per piece is cheaper than a custom shader and exact.
func _camera_position() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position


func _write_trail(i: int, delta: float, cam: Vector3) -> void:
	if _trail == null or i >= _trail_count:
		return
	var v := _vel[i]
	var speed := v.length()
	var target := clampf((speed - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
	var was: float = _trail_alpha[i]
	# Both directions take at most TRAIL_LIFE_S, so a streak fades in and out over
	# 120 ms and never pops.
	var a := move_toward(was, target, delta / TRAIL_LIFE_S)
	_trail_alpha[i] = a
	if was <= 0.0 and a > 0.0:
		_trail_live += 1
	if a <= 0.0:
		if was > 0.0:
			_trail_live -= 1
			_park_trail(i)
		return
	var dir := v / maxf(speed, 0.0001)
	var length := minf(speed * TRAIL_LENGTH_S, TRAIL_MAX_LEN)
	var head := _pos[i]
	var to_cam := (cam - head)
	var side := dir.cross(to_cam)
	if side.length_squared() < 0.000001:
		side = dir.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
	side = side.normalized()
	var face := side.cross(dir).normalized()
	var width: float = TRAIL_WIDTH * _scale[i]
	# QuadMesh spans -0.5..0.5 with v = 0 at +Y, and trail_streak.png is brightest at
	# v = 0, so +Y must be the HEAD. Origin therefore sits half a length behind it.
	var basis := Basis(side * width, dir * length, face)
	_trail.multimesh.set_instance_transform(i, Transform3D(basis, head - dir * (length * 0.5)))
	_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, a))


## Fade out every streak whose piece is gone. Only runs while something is fading.
func _decay_trail(delta: float) -> void:
	if _trail == null or _trail_live <= 0:
		return
	var drop := delta / TRAIL_LIFE_S
	for i in _trail_count:
		if _trail_alpha[i] <= 0.0 or _alive[i] == 1:
			continue
		var a: float = _trail_alpha[i] - drop
		if a <= 0.0:
			_trail_alpha[i] = 0.0
			_trail_live -= 1
			_park_trail(i)
			continue
		_trail_alpha[i] = a
		_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, a))


func _park_trail(i: int) -> void:
	_trail.multimesh.set_instance_transform(i, _hidden)
	_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func live_count() -> int:
	return _live_count


func free_slots() -> int:
	return _free.size()


## Instances the renderer will actually draw.
##
## This counts the transforms we WROTE rather than reading a MultiMesh back, because
## the headless dummy renderer does not keep the instance buffer and
## multimesh.get_instance_transform() returns identity for every slot there. It still
## catches the bug that matters: a retired slot that was never dropped, or a live
## piece whose transform was never written.
func visible_instance_count() -> int:
	var n := 0
	for i in FightTypes.BOLT_POOL:
		if _written[i] == 1:
			n += 1
	return n


## The shape banks. fx_test.gd asserts the drawn instances across all of them never
## exceed the pool.
func pieces() -> ScrapPieces:
	return _pieces


func sparks() -> ScrapSparks:
	return _sparks


## What one live piece is made of, for the test: {"kind", "size", "heat", "tint"}.
## Returns an empty dictionary for a slot that is not in flight.
func piece_state(i: int) -> Dictionary:
	if i < 0 or i >= FightTypes.BOLT_POOL or _alive[i] == 0:
		return {}
	return {
		"kind": _kind[i],
		"pos": _pos[i],
		"size": _size[i],
		"heat": _heat(i),
		"tint": _tint[i],
		"metal": _metal[i],
		"rough": _rough[i],
		"age": _life[i],
	}


## How many pieces of each ScrapPieces kind are in flight. The test uses it to show
## that a steel hit and a polycarbonate hit really do shed different things.
func kind_histogram() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(ScrapPieces.KIND_COUNT)
	for i in FightTypes.BOLT_POOL:
		if _alive[i] == 1:
			out[_kind[i]] += 1
	return out


## The hard cap on streak segments. fx_test.gd asserts this never grows past 120.
func trail_capacity() -> int:
	return _trail_count


func trail_live_count() -> int:
	return _trail_live


func flash_pool() -> FxFlashPool:
	return _flash


## --- mesh ------------------------------------------------------------------

## First mesh in a glTF scene. The part glbs are a single `body` MeshInstance3D
## under a Node3D root, so this is the whole of the contract.
##
## The scrap pieces are hand built (ScrapPieces) and no longer load a glb, but
## `DebrisChips` still uses this to load G3's spark_chip, so it stays here.
static func _mesh_from_glb(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var found: Mesh = null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = (n as MeshInstance3D).mesh
			break
		for c in n.get_children():
			queue.append(c)
	root.free()
	return found
