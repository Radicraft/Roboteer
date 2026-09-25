extends SceneTree
## Headless feel test for the FX tree (agent B, docs/stage3-spec.md §11).
##   Godot --headless --path Arena --script tests/fx_test.gd
##
## It drives res://fx/fx.tscn with a fixed 1/60 s presentation delta so four seconds
## of bolt shower run in 240 frames, and checks the things the effect is actually
## made of: the scatter pause happens, the stream arrives staggered, the pitch ramp
## climbs and resets, the HUD is bumped by exactly the scrap that was awarded, the
## pool never exceeds its cap, and the haptic bridge messages stay inside the
## 30 per second contract.
##
## Nothing here can assert on particles: --headless has no renderer, so GPUParticles3D
## never simulates. Those checks are guarded and reported as skipped.

const STEP := 1.0 / 60.0
const AWARD := 30
const SPAWN_AT := Vector3(-0.9, 0.34, 0.7)
const TARGET_AT := Vector3(1.1, 0.22, -0.6)   # about 2.4 m away, a realistic push distance


## Stands in for C's HUD. FightFx only ever calls bump(amount).
class FakeHud extends RefCounted:
	var total: int = 0
	var calls: int = 0
	func bump(amount: int) -> void:
		total += amount
		calls += 1


## Stands in for the SwiftGodotKit host node so Bridge.send() has somewhere to go
## and does not warn once per haptic.
class FakeHost extends Node:
	signal message_from_host(message: Dictionary)
	var received: Array = []
	func emit_message_to_host(message: Dictionary) -> void:
		received.append(message)


## --- wave P (agent F): the doubles WeaponFx reads ----------------------------
##
## `WeaponFx` is duck typed all the way down (every reading goes through `_f`, which
## checks `has_method` first), so a test double only has to answer the accessors the
## real part answers. None of these is a `Bot`, a `WeaponBase` or a `DriveBase`, which
## is the point: if the fx layer ever starts needing something a part does not
## publish, these stop compiling and the coupling is caught here rather than on a phone.

class FakePart extends Node3D:
	var detached := false


class FakePatch extends Node3D:
	var is_lit := false
	func lit() -> bool:
		return is_lit


class FakeWeapon extends Node3D:
	var spec := {"id": ""}
	var kind := ""
	var charge := 0.0
	var arc_count := 0
	var shock_count := 0
	var shot_count := 0
	var contact := 0.0
	var spin_v := 0.0
	var bore := 0.0
	var cut := 0.0
	var head: FakePart = null
	var lance: FakePart = null
	var blades: Array = []
	var patch_list: Array = []
	var target: FakePart = null
	func readiness() -> float: return charge
	func arcs() -> int: return arc_count
	func last_target() -> FakePart: return target
	func shocks() -> int: return shock_count
	func contact_seconds() -> float: return contact
	func spin() -> float: return spin_v
	func boring_seconds() -> float: return bore
	func cutting_seconds() -> float: return cut
	func shots_fired() -> int: return shot_count
	func patches() -> Array: return patch_list


## Agent G1's decal projector, as much of it as WeaponFx uses.
class FakeDecals extends Node3D:
	var scorches: Array = []
	func add_scorch(position: Vector3, size: float, _attach_to: Node3D = null) -> Node:
		scorches.append({"at": position, "size": size})
		return null


class FakeWaveDrive extends RefCounted:
	var id := "4wd"
	var power := 1.0
	var hover := 0.20
	func power_scale() -> float: return power
	func hover_height() -> float: return hover
	func top_speed() -> float: return 3.0


class FakeWaveBot extends Node3D:
	var bot_id := "wp-1"
	var chassis: RigidBody3D = null
	var drive_module: FakeWaveDrive = null
	var weapon: FakeWeapon = null
	var _materials: Dictionary = {}
	var _cook_rate := 0.0
	var _last_input: Dictionary = {"heading": Vector2.ZERO, "turn": 0.0}
	var readiness := 0.0
	var stalled := false
	func weapon_readiness() -> float: return readiness
	func weapon_socket_world() -> Vector3:
		return chassis.global_position + chassis.global_basis.x * 0.30
	func is_disrupted(kind: String) -> bool: return stalled and kind == "drive"
	func is_inverted() -> bool: return false
	func ride_height() -> float: return 0.11

var _failures: int = 0
var _checks: int = 0
var _skipped: int = 0

var _fx: FightFx = null
var _hud: FakeHud = null
var _host: FakeHost = null

var _collect_times: Array[float] = []
var _collect_amounts: Array[int] = []
var _haptic_times: Array[float] = []
var _haptic_kinds: Array[String] = []
var _max_semitones: int = 0
var _max_visible: int = 0
var _max_trail: int = 0
var _max_flash: int = 0
## Wave F (agent F3): the scrap banks and the pools that go with them.
var _max_pieces: int = 0
var _max_rings: int = 0
var _max_smoke: int = 0
var _max_cpu_sparks: int = 0
## Set if the number of pieces written to the banks in a frame ever disagrees with the
## number the pool says are in flight. One flag rather than a check per frame, so a
## single stray frame out of thousands still fails the run.
var _piece_mismatch: bool = false
## Wave P (agent F): the peaks of the three pools this wave added.
var _wp_max_emitters: int = 0
var _wp_max_glows: int = 0
var _wp_max_arcs: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# --- setup ---------------------------------------------------------------
	_host = FakeHost.new()
	_host.name = "__swiftgodotkit_bridge__"
	root.add_child(_host)

	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null:
		_fail("Bridge autoload is present")
		_finish()
		return
	bridge.message_sent.connect(_on_message_sent)

	_check(_check_audio_imports(), "every placeholder sound imported and loads as AudioStreamWAV")

	var packed: PackedScene = load("res://fx/fx.tscn") as PackedScene
	if packed == null:
		_fail("fx.tscn loads")
		_finish()
		return
	_ok("fx.tscn loads")
	_fx = packed.instantiate() as FightFx
	if _fx == null:
		_fail("fx.tscn root is a FightFx")
		_finish()
		return
	_ok("fx.tscn root is a FightFx")
	root.add_child(_fx)
	await process_frame

	_hud = FakeHud.new()
	_fx.bind(_hud, _bot_position)
	_fx.fixed_delta_override = STEP
	_fx.bolts_landed.connect(_on_bolts_landed)

	if FightParticles.gpu_available():
		_ok("a renderer is present, particles will simulate")
	else:
		_skip("particle emission (headless has no renderer)")

	# --- phase 1: one 30 scrap shower, four simulated seconds ----------------
	_fx.on_scrap_awarded("player-1", AWARD, SPAWN_AT)
	await _run_frames(int(4.0 / STEP))

	_check(_max_visible == AWARD, "all %d bolts became visible (peak %d)" % [AWARD, _max_visible])
	_check(_collect_times.size() == AWARD, "%d bolts were collected (got %d)" % [AWARD, _collect_times.size()])

	var first := _collect_times[0] if not _collect_times.is_empty() else -1.0
	_check(first >= 0.150,
		"no bolt is collected before 150 ms: the scatter pause is real (first at %.3f s)" % first)

	var last := _collect_times[_collect_times.size() - 1] if not _collect_times.is_empty() else 999.0
	_check(last <= 3.0, "every bolt is collected within 3 s (last at %.3f s)" % last)

	_check(_hud.total == AWARD, "hud.bump totals exactly the scrap awarded (%d, got %d)" % [AWARD, _hud.total])
	_check(_hud.calls == AWARD, "hud.bump was called once per bolt (%d, got %d)" % [AWARD, _hud.calls])

	var stagger := _stagger_report()
	_check(stagger["spread"] >= 0.25,
		"the arrivals are a stream, not a burst: %.3f s from first bolt to last" % stagger["spread"])
	_check(stagger["max_per_frame"] <= 6,
		"no frame swallowed a clump of bolts (worst frame %d, mean gap %.1f ms)"
		% [stagger["max_per_frame"], stagger["mean_gap_ms"]])

	_check(_max_semitones >= 5,
		"the collect pitch ramp climbed at least 5 semitones during the stream (reached +%d)" % _max_semitones)
	_check(_max_semitones <= FightTypes.BOLT_MAX_SEMITONES,
		"the ramp never passed the +%d cap" % FightTypes.BOLT_MAX_SEMITONES)
	_check(_fx.collect_audio().semitones == 0,
		"the ramp reset after the stream ended (now +%d)" % _fx.collect_audio().semitones)
	_check(is_equal_approx(_fx.collect_audio().current_pitch(), 1.0), "reset pitch is exactly 1.0")

	_check(_fx.bolt_shower().live_count() == 0, "the pool is fully returned after the shower")
	_check(_fx.bolt_shower().free_slots() == FightTypes.BOLT_POOL, "every pool slot is free again")

	var ticks := _kind_count("tick")
	_check(ticks > 0, "haptic ticks were sent for the collects (%d)" % ticks)

	# --- phase 2: a shower far bigger than the pool --------------------------
	_max_visible = 0
	_collect_times.clear()
	_collect_amounts.clear()
	_hud.total = 0
	_hud.calls = 0
	_fx.on_scrap_awarded("player-1", 500, SPAWN_AT)
	await _run_frames(int(5.0 / STEP))

	_check(_max_visible <= FightTypes.BOLT_POOL,
		"visible bolts never exceeded the pool cap of %d (peak %d)" % [FightTypes.BOLT_POOL, _max_visible])
	_check(_max_visible == FightTypes.BOLT_POOL,
		"the oversized shower filled the pool (peak %d)" % _max_visible)
	_check(_collect_times.size() == FightTypes.BOLT_POOL,
		"a 500 scrap award spawned %d fatter bolts, not 500 (got %d)" % [FightTypes.BOLT_POOL, _collect_times.size()])
	_check(_hud.total == 500,
		"the value is preserved: fewer bolts still bump the HUD by 500 (got %d)" % _hud.total)
	_check(_fx.bolt_shower().free_slots() == FightTypes.BOLT_POOL, "the pool is free again after the big shower")

	# --- phase 3: the rest of the API, and the haptic rate cap ---------------
	_fx.on_damage_event({
		"attacker": "player-1", "victim": "ai-1", "part": "armour_front", "severity": 0.12,
		"position": SPAWN_AT, "impulse": 31.0, "detached": false, "tick": 120,
	})
	_fx.on_damage_event({
		"attacker": "player-1", "victim": "ai-1", "part": "wheel_fl", "severity": 0.81,
		"position": [0.4, 0.2, -0.3], "impulse": 190.0, "detached": true, "tick": 140,
	})
	_fx.on_weapon_fired("player-1")
	_fx.on_countdown(3)
	_fx.on_countdown(0)
	_fx.on_ko_tick(7)
	_fx.on_bell()
	_fx.on_spikes(true, Vector3.ZERO)
	_fx.set_motor_state("player-1", 0.85)
	_fx.set_motor_state("ai-1", 0.2)
	await _run_frames(30)
	_fx.on_spikes(false, Vector3.ZERO)
	_fx.set_haptics_enabled(false)
	var before_off := _haptic_times.size()
	_fx.on_bell()
	await _run_frames(2)
	_check(_haptic_times.size() == before_off, "set_haptics_enabled(false) stops every haptic message")
	_fx.set_haptics_enabled(true)

	_check(_kind_count("impact_light") == 1, "a severity 0.12 hit sent impact_light")
	_check(_kind_count("impact_heavy") == 1, "a severity 0.81 hit sent impact_heavy")
	# B6 (combat feel): a dry fire is a light tap; only a flipper that THREW something is
	# felt, as a heavy tap from _flipper_connect. No fake weapons here, so this is a dry fire.
	_check(_kind_count("flip") == 0, "a dry flipper fire sends no flip haptic, only a light tap")
	_check(_kind_count("ko_tick") == 1, "the knockout count sent ko_tick")
	_check(_kind_count("bell") == 1, "the result bell sent the bell haptic")

	var worst := _max_in_window(_haptic_times, 1.0)
	_check(worst <= FightTypes.HAPTIC_MAX_PER_S,
		"haptic messages never exceeded %d in any one second (worst %d, %d sent, %d dropped)"
		% [FightTypes.HAPTIC_MAX_PER_S, worst, _fx.haptics().sent_count(), _fx.haptics().dropped_count()])
	_check(_fx.haptics().dropped_count() > 0,
		"the 120 bolt stream really did hit the cap and drop ticks (%d dropped)" % _fx.haptics().dropped_count())
	_check(_host.received.size() == _haptic_times.size(),
		"every haptic that passed the cap reached the host (%d)" % _host.received.size())

	# --- phase 4: G4's graphics pass (docs/graphics-fx-notes.md) -------------
	# Everything above is agent B's Stage 3 feel contract and must not move. These
	# checks are about the things the visual upgrade ADDED, and above all about its
	# caps: an effect whose pool can grow is an effect that will eventually cost a
	# frame on a phone.
	var shower := _fx.bolt_shower()

	_check(shower.trail_capacity() <= 120,
		"the bolt trail is capped at 120 segments (%d)" % shower.trail_capacity())
	_check(shower.trail_capacity() == FightTypes.BOLT_POOL,
		"one trail segment per pool slot, so the cap is structural (%d segments, %d bolts)"
		% [shower.trail_capacity(), FightTypes.BOLT_POOL])
	_check(_max_trail <= shower.trail_capacity(),
		"live trail segments never exceeded the cap during two showers (peak %d)" % _max_trail)
	_check(_max_trail > 0, "the bolts actually drew streaks (peak %d live segments)" % _max_trail)
	_check(shower.trail_live_count() == 0,
		"every streak faded out after the showers ended (%d still lit)" % shower.trail_live_count())

	var bolt_flash: FxFlashPool = shower.flash_pool()
	_check(bolt_flash != null and bolt_flash.pool_size() == 8,
		"the collect flash pool is 8 quads (%d)" % (bolt_flash.pool_size() if bolt_flash != null else -1))
	_check(_max_flash > 0 and _max_flash <= 8,
		"collect flashes fired and stayed inside the pool (peak %d)" % _max_flash)
	_check(bolt_flash != null and bolt_flash.live_count() == 0,
		"the flash pool is idle again after the showers")

	# The drawn size was raised for readability at the fight framing; the PHYSICAL
	# size feeds the rest height and therefore the ballistics agent B measured, so it
	# must not move with it.
	_check(is_equal_approx(BoltShower.BOLT_SIZE, 0.05),
		"the physical bolt size is still 0.05 m, so the Stage 3 timings are untouched")
	_check(BoltShower.BOLT_VISUAL_SIZE > BoltShower.BOLT_SIZE,
		"the drawn bolt is larger than the physical one (%.3f m drawn, %.3f m physical)"
		% [BoltShower.BOLT_VISUAL_SIZE, BoltShower.BOLT_SIZE])
	_check(BoltShower.TRAIL_LENGTH_S > 0.0 and is_equal_approx(BoltShower.TRAIL_LIFE_S, 0.12),
		"the streak still fades over 120 ms, with its length on a separate scalar")
	# The readability rule, brief §6: structural debris must never be mistakable for
	# scrap. This is the only place in the codebase that can enforce it mechanically.
	var particles: FightParticles = _fx.particles()
	var chips: DebrisChips = null
	if particles != null:
		chips = particles.chips()
	_check(chips != null and chips.pool_size() == 32,
		"the chip pool is 32 (%d)" % (chips.pool_size() if chips != null else -1))
	var chip_mat: StandardMaterial3D = null
	if chips != null:
		chip_mat = chips.material_override as StandardMaterial3D
	_check(chip_mat != null and not chip_mat.emission_enabled,
		"chips are never emissive: they must not read as collectible gold")
	_check(chip_mat != null and chip_mat.albedo_color.s < 0.25,
		"chips are dull grey, not gold (saturation %.3f vs the bolt's %.3f)"
		% [chip_mat.albedo_color.s if chip_mat != null else -1.0, FightTypes.BOLT_GOLD.s])

	# Twenty detaches back to back: far more chips than the pool holds.
	for i in 20:
		_fx.on_damage_event({
			"attacker": "player-1", "victim": "ai-1", "part": "armour_side", "severity": 0.9,
			"position": Vector3(0.2, 0.25, 0.1), "impulse": 200.0, "detached": true, "tick": 200 + i,
		})
	await _run_frames(6)
	_check(chips != null and chips.live_count() > 0 and chips.live_count() <= 32,
		"a 20 detach pile-up filled the chip pool and never passed it (%d live)"
		% (chips.live_count() if chips != null else -1))
	# Read the shake HERE, six frames after the hits: trauma decays in about 0.4 s
	# and the chip lifetime wait below is three times that.
	var shake: ImpactShake = _fx.impact_shake()
	_check(shake != null and shake.is_in_group(ImpactShake.GROUP),
		"the impact shake is in the group the camera rig looks it up by")
	_check(shake != null and shake.offset() != Vector3.ZERO,
		"the detach pile-up kicked the camera (offset %.4f m)"
		% (shake.offset().length() if shake != null else -1.0))
	# 1.2 s lifetime plus a frame of slack.
	await _run_frames(int(1.35 / STEP))
	_check(chips != null and chips.live_count() == 0,
		"every chip expired after its 1.2 s lifetime (%d still live)"
		% (chips.live_count() if chips != null else -1))

	# Bounded, and back to exactly zero afterwards.
	var peak := 0.0
	shake.reset()
	shake.kick(1.0)
	for i in 40:
		shake.step(STEP)
		peak = maxf(peak, shake.offset().length())
	_check(peak > 0.0 and peak <= ImpactShake.MAX_OFFSET * 1.001,
		"the kick stays inside MAX_OFFSET (peak %.4f m of %.4f)" % [peak, ImpactShake.MAX_OFFSET])
	for i in 10:
		shake.kick(1.0)
	_check(is_equal_approx(shake.trauma, 1.0), "ten kicks at once still clamp to one unit of trauma")
	for i in int(1.0 / STEP):
		shake.step(STEP)
	_check(shake.trauma == 0.0 and shake.offset() == Vector3.ZERO,
		"the shake settles to exactly zero within a second")

	# The flamethrower cone, built for W2. Nothing calls it yet, so the test is the
	# only thing standing between it and rotting before the weapon arrives.
	var flame := FlameCone.new()
	flame.external_clock = true
	root.add_child(flame)
	await process_frame
	_check(flame.particles() != null and flame.light() != null and flame.haze() != null,
		"FlameCone builds its three layers: cone, haze glow, flickering light")
	_check(not flame.is_active() and not flame.particles().emitting,
		"FlameCone starts inactive")
	flame.set_active(true)
	_check(flame.is_active() and flame.particles().emitting and flame.light().visible,
		"set_active(true) lights the cone, the haze and the light")
	flame.set_length(2.4)
	_check(is_equal_approx(flame.length(), 2.4), "set_length(2.4) took (%.2f)" % flame.length())
	_check(flame.light().omni_range > 2.4,
		"the light reaches past the tip of the flame (range %.2f m)" % flame.light().omni_range)
	flame.set_length(99.0)
	_check(is_equal_approx(flame.length(), FlameCone.MAX_LENGTH),
		"set_length clamps a silly reach to MAX_LENGTH (%.1f m)" % flame.length())
	flame.set_length(-3.0)
	_check(is_equal_approx(flame.length(), FlameCone.MIN_LENGTH),
		"set_length clamps a negative reach to MIN_LENGTH (%.1f m)" % flame.length())
	flame.set_length(1.6)
	var e0: float = flame.light().light_energy
	var moved := false
	for i in 30:
		flame.step(STEP)
		if not is_equal_approx(flame.light().light_energy, e0):
			moved = true
	_check(moved, "the flame light flickers when it is stepped")
	flame.set_active(false)
	_check(not flame.particles().emitting and not flame.light().visible,
		"set_active(false) puts the fire out")
	root.remove_child(flame)
	flame.free()

	# G1 owns the environment, this file owns the emissives, and the two only work
	# together if the bolt clears the glow threshold. Neither agent can see the other
	# change, so the contract is asserted here rather than remembered.
	_check(_check_glow_headroom(), "the bolt emission clears G1's glow HDR threshold")

	if particles != null and particles.light_pool() != null:
		var lights: FxLightPool = particles.light_pool()
		_check(lights.pool_size() == 4, "the impact light pool is 4 (%d)" % lights.pool_size())
		_check(lights.live_count() == 0,
			"every impact light expired (%d still on)" % lights.live_count())
	else:
		_fail("FightParticles exposes an impact light pool")

	# The mipmap trap from docs/graphics-textures-notes.md, now for the FX sprites:
	# Godot imports a PNG with mipmaps OFF and only turns them on when the EDITOR
	# notices the texture on a 3D material. This project never opens the editor.
	_check(_check_fx_textures(), "every FX texture is imported with mipmaps on")

	# The compatibility tier contract: emissive values must bloom where there is HDR
	# and must NOT clip to white where there is not. Headless has no RenderingDevice,
	# so this run exercises the tamed path.
	_check(FxMaterials.energy(FxMaterials.SPARK_ENERGY) <= FxMaterials.SPARK_ENERGY,
		"FxMaterials.energy never raises the nominal energy (%.2f of %.2f)"
		% [FxMaterials.energy(FxMaterials.SPARK_ENERGY), FxMaterials.SPARK_ENERGY])
	if FxMaterials.hdr_available():
		_ok("this run has an HDR buffer, emissives use their full energy")
	else:
		_check(is_equal_approx(FxMaterials.energy(FxMaterials.SPARK_ENERGY), FxMaterials.LDR_ENERGY),
			"with no HDR buffer the spark energy is tamed to %.2f, not clipped to white"
			% FxMaterials.LDR_ENERGY)
	if particles != null and particles.trails_enabled():
		_ok("particle trails are available and in use")
	else:
		_skip("particle trails (no RenderingDevice: headless and GL Compatibility use streak quads)")

	# --- phase 5: wave F, the scrap pass (docs/wave-f-f3-notes.md) -----------
	# The owner's note on the wave G build was "the scrap won doesn't look like
	# scrap". Everything below is about the answer to that: a shower is now a MIX of
	# torn metal whose shapes follow the severity of the hit and the material of the
	# face that was hit, and a piece is dark metal with a hot edge that cools rather
	# than a gold pip. None of the feel contract above moved, which is the point of
	# running these checks after it rather than instead of it.
	var pieces: ScrapPieces = shower.pieces()
	_check(pieces != null and pieces.bank_count() == ScrapPieces.KIND_COUNT,
		"the shower draws %d shapes, one MultiMesh bank each (%d)"
		% [ScrapPieces.KIND_COUNT, pieces.bank_count() if pieces != null else -1])
	_check(pieces != null and pieces.capacity() == FightTypes.BOLT_POOL,
		"every bank is allocated at the pool size, so the pool is still the only cap")

	var meshes_ok := true
	var worst_tris := 0
	if pieces != null:
		for kind in ScrapPieces.KIND_COUNT:
			var b: MultiMeshInstance3D = pieces.bank(kind)
			var tris: int = pieces.triangles_of(kind)
			if b == null or b.multimesh == null or b.multimesh.mesh == null or tris <= 0:
				meshes_ok = false
			worst_tris = maxi(worst_tris, tris)
			print("      %-8s %3d tris, %3.0f mm long, extent %.4f m"
				% [str(ScrapPieces.KIND_NAMES[kind]), tris,
					float(ScrapPieces.KIND_SIZE_M[kind]) * 1000.0, pieces.mesh_extent(kind)])
	_check(meshes_ok, "every scrap shape is a real hand built mesh with triangles in it")
	# The budget this agent quoted in docs/wave-f-f3-notes.md. A shape that quietly
	# grows past it is the one way this effect could start costing a frame on a phone.
	_check(worst_tris * FightTypes.BOLT_POOL <= 6000,
		"worst case scrap geometry is inside budget (%d tris if all %d slots were the heaviest shape, budget 6000)"
		% [worst_tris * FightTypes.BOLT_POOL, FightTypes.BOLT_POOL])

	var scrap_mat: ShaderMaterial = pieces.material() if pieces != null else null
	_check(scrap_mat != null and scrap_mat.shader != null,
		"the scrap banks share one shader material")
	_check(scrap_mat != null and is_equal_approx(
			float(scrap_mat.get_shader_parameter("hot_energy")),
			FxMaterials.energy(FxMaterials.BOLT_EMISSION)),
		"the hot edge rides FxMaterials' own bolt energy, so the glow contract still covers it")
	var hot: Color = scrap_mat.get_shader_parameter("hot_colour") if scrap_mat != null else Color.BLACK
	_check(hot.r > hot.b,
		"the hot edge is WARM: brief §6 says what is coming to you is warm and what is dead scenery is grey (%.2f r vs %.2f b)"
		% [hot.r, hot.b])

	# Fasteners are steel whatever they were bolted into: a polycarbonate lid is still
	# held on with steel bolts, and that is most of what stops a plastic bot's shower
	# going flat and grey.
	var poly_shard: Dictionary = ScrapPieces.look_for(ScrapPieces.KIND_SHARD, "polycarbonate")
	var hdpe_shard: Dictionary = ScrapPieces.look_for(ScrapPieces.KIND_SHARD, "hdpe")
	var hdpe_bolt: Dictionary = ScrapPieces.look_for(ScrapPieces.KIND_BOLT, "hdpe")
	_check((poly_shard["tint"] as Color).get_luminance() > 0.5,
		"polycarbonate sheds MILKY shards (luminance %.2f)"
		% (poly_shard["tint"] as Color).get_luminance())
	_check((hdpe_shard["tint"] as Color).get_luminance() < 0.15,
		"HDPE sheds BLACK chips (luminance %.2f)" % (hdpe_shard["tint"] as Color).get_luminance())
	_check(is_equal_approx(float(hdpe_bolt["metal"]), float(ScrapPieces.FASTENER_LOOK["metal"])),
		"a bolt out of an HDPE panel is still steel")
	_check(pieces != null and pieces.resolve_material("nobody-at-all", "armour_front") == "steel",
		"an unknown victim falls back to steel rather than failing")

	# Three identical hits on three different materials. Same severity, same part, same
	# count: everything that differs is the material.
	var steel_hit := await _shower("armour_front", "steel", 0.85, false, 40)
	var poly_hit := await _shower("armour_front", "polycarbonate", 0.85, false, 40)
	var hdpe_hit := await _shower("armour_front", "hdpe", 0.85, false, 40)
	var steel_h: PackedInt32Array = steel_hit["hist"]
	var poly_h: PackedInt32Array = poly_hit["hist"]
	var hdpe_h: PackedInt32Array = hdpe_hit["hist"]
	print("      steel  %s" % str(steel_h))
	print("      poly   %s" % str(poly_h))
	print("      hdpe   %s" % str(hdpe_h))
	_check(steel_h[ScrapPieces.KIND_PLATE] > steel_h[ScrapPieces.KIND_SHARD],
		"a hard hit on STEEL sheds bent plate, not shards (%d plate, %d shard)"
		% [steel_h[ScrapPieces.KIND_PLATE], steel_h[ScrapPieces.KIND_SHARD]])
	_check(poly_h[ScrapPieces.KIND_SHARD] > poly_h[ScrapPieces.KIND_PLATE],
		"a hard hit on POLYCARBONATE shatters into shards (%d shard, %d plate)"
		% [poly_h[ScrapPieces.KIND_SHARD], poly_h[ScrapPieces.KIND_PLATE]])
	_check(poly_h[ScrapPieces.KIND_SHARD] > steel_h[ScrapPieces.KIND_SHARD]
			and hdpe_h[ScrapPieces.KIND_SHARD] > steel_h[ScrapPieces.KIND_SHARD],
		"plastics shed more shards than steel does (%d poly, %d hdpe, %d steel)"
		% [poly_h[ScrapPieces.KIND_SHARD], hdpe_h[ScrapPieces.KIND_SHARD],
			steel_h[ScrapPieces.KIND_SHARD]])

	# Severity. A scrape and a panel coming off must not look like the same event.
	var light_hit := await _shower("armour_front", "steel", 0.08, false, 40)
	var heavy_hit := await _shower("armour_front", "steel", 1.0, false, 40)
	_check(float(heavy_hit["mean_size"]) > float(light_hit["mean_size"]) * 1.15,
		"a heavy hit throws BIGGER pieces (%.1f mm mean vs %.1f mm)"
		% [float(heavy_hit["mean_size"]) * 1000.0, float(light_hit["mean_size"]) * 1000.0])
	_check(float(heavy_hit["mean_dist"]) > float(light_hit["mean_dist"]) * 1.15,
		"a heavy hit throws them FURTHER (%.0f mm out after two frames vs %.0f mm)"
		% [float(heavy_hit["mean_dist"]) * 1000.0, float(light_hit["mean_dist"]) * 1000.0])
	var light_h: PackedInt32Array = light_hit["hist"]
	_check(light_h[ScrapPieces.KIND_BOLT] + light_h[ScrapPieces.KIND_NUT]
			> light_h[ScrapPieces.KIND_PLATE],
		"a scrape sheds shorn fasteners, which is what brief §6 is written about (%d bolts and nuts, %d plate)"
		% [light_h[ScrapPieces.KIND_BOLT] + light_h[ScrapPieces.KIND_NUT],
			light_h[ScrapPieces.KIND_PLATE]])

	# The hot edge. Hot at the tear, cold by 0.6 s, and then re-lit to an ember by the
	# magnet so a piece on its way home still reads as scrap rather than as scenery.
	_check(float(steel_hit["max_heat"]) > 0.9,
		"scrap comes off HOT (%.2f at the tear)" % float(steel_hit["max_heat"]))
	_check(float(steel_hit["cool_heat"]) <= BoltShower.MAGNET_EMBER + 0.02,
		"the hot edge has cooled to the magnet ember by %.2f s (%.2f, ember %.2f)"
		% [BoltShower.HOT_COOL_S, float(steel_hit["cool_heat"]), BoltShower.MAGNET_EMBER])
	_check(BoltShower.MAGNET_EMBER > 0.0,
		"a magnetised piece keeps a warm rim, so it is never confusable with a dead chip")

	# A component kill throws the dead part's silhouette.
	# 40 pieces, not 12: the pick is an unseeded presentation RNG, and at 12 a nut-free
	# shower came up about 1 run in 30 (the suite hit it 2026-09-25). At 40 it is ~1 in 10^5.
	var wheel_hit := await _shower("wheel_fl", "steel", 0.95, true, 40)
	var wheel_h: PackedInt32Array = wheel_hit["hist"]
	_check(wheel_h[ScrapPieces.KIND_WHEEL] >= 1,
		"a wheel coming off throws the wheel's silhouette (%d)" % wheel_h[ScrapPieces.KIND_WHEEL])
	_check(float(wheel_hit["max_size"]) > float(steel_hit["max_size"]),
		"the silhouette is the biggest thing in the shower (%.0f mm vs %.0f mm)"
		% [float(wheel_hit["max_size"]) * 1000.0, float(steel_hit["max_size"]) * 1000.0])
	_check(wheel_h[ScrapPieces.KIND_NUT] > 0,
		"a wheel also sheds its wheel nuts (%d)" % wheel_h[ScrapPieces.KIND_NUT])
	var armour_kill := await _shower("armour_front", "steel", 0.95, true, 12)
	var armour_h: PackedInt32Array = armour_kill["hist"]
	_check(armour_h[ScrapPieces.KIND_WHEEL] == 0,
		"a panel coming off does NOT throw a wheel (%d)" % armour_h[ScrapPieces.KIND_WHEEL])

	# Sparks, smoke and the landing dust, and above all their caps.
	var scrap_sparks: ScrapSparks = shower.sparks()
	_check(scrap_sparks != null, "the shower owns a ScrapSparks")
	_check(int(heavy_hit["smoke"]) > 0,
		"a heavy hit puffs smoke at the tear (%d live)" % int(heavy_hit["smoke"]))
	_check(int(light_hit["smoke"]) == 0,
		"a scrape does NOT: smoke on every scrape would read as a fire (%d live)"
		% int(light_hit["smoke"]))
	_check(_max_rings > 0, "pieces landing kicked dust rings (peak %d)" % _max_rings)
	_check(_max_rings <= ScrapSparks.RING_POOL,
		"the dust ring pool never overflowed (peak %d of %d)" % [_max_rings, ScrapSparks.RING_POOL])
	_check(_max_smoke <= ScrapSparks.SMOKE_POOL,
		"the smoke pool never overflowed (peak %d of %d)" % [_max_smoke, ScrapSparks.SMOKE_POOL])
	if FxMaterials.hdr_available():
		_check(scrap_sparks.gpu_sparks() and scrap_sparks.emitter_count() == ScrapSparks.SPARK_EMITTERS,
			"with a RenderingDevice the tear sparks are GPU particles (%d emitters)"
			% scrap_sparks.emitter_count())
	else:
		_check(not scrap_sparks.gpu_sparks()
				and scrap_sparks.cpu_spark_pool() == ScrapSparks.CPU_SPARKS,
			"with no RenderingDevice the tear sparks fall back to a %d quad CPU pool"
			% ScrapSparks.CPU_SPARKS)
		_check(scrap_sparks.live_sparks() >= 0 and _max_cpu_sparks > 0,
			"the CPU spark fallback actually ran (peak %d live)" % _max_cpu_sparks)

	# The one cap that matters: however the mix comes out, the banks between them can
	# never draw more instances than the pool has slots.
	_check(_max_pieces > 0 and _max_pieces <= FightTypes.BOLT_POOL,
		"drawn scrap instances across every bank stayed inside the pool (peak %d of %d)"
		% [_max_pieces, FightTypes.BOLT_POOL])
	_check(not _piece_mismatch,
		"every piece in flight was written to a bank, and nothing else was")
	_check(pieces != null and pieces.live_instances() == 0
			and pieces.banks_drawing() == 0,
		"with nothing in flight every bank is empty and costs no draw call")
	_check(shower.free_slots() == FightTypes.BOLT_POOL,
		"the pool is fully returned after the whole scrap pass")

	await _test_wave_p()

	# Locals in this function are still on the stack when quit() runs, and a live
	# StandardMaterial3D reference keeps the shader RID that BaseMaterial3D shares
	# across the family alive with it, which the engine reports as a leak at exit.
	chip_mat = null
	bolt_flash = null

	# Let the voices stop and the audio server drop their playbacks, or the engine
	# reports them as leaked instances at exit. This needs WALL clock time, not
	# frames: headless frames take microseconds and the mixer runs on its own thread.
	_fx.stop_all_audio()
	await create_timer(0.25).timeout

	_finish()


# --- phase 8 (wave P, agent F): the six weapons, the drives, the core, the plate
#
# Everything wave P added arrived working and INVISIBLE: no bolt on the arc, no spark
# on the prod, no smoke on the fire patch, no dust under the hover, and a core cooking
# itself to death with nothing on screen at all. These checks are that each cue fires
# off the thing that causes it, that every pool is a pool (it caps, and it empties),
# and that none of it can call `randf()` or outrun the frame budget.
#
# Nothing here asserts on particle OUTPUT: headless has no renderer and a GPUParticles3D
# never simulates. What it asserts on is which emitters are on, which is the decision
# this layer makes.

func _test_wave_p() -> void:
	print("")
	print("      --- wave P: weapons, drives, the core and the plate ---")
	await _wp_pools()
	await _wp_machines()


## The three pools, on their own, before any machine exists.
func _wp_pools() -> void:
	# --- the arc bolt ---------------------------------------------------------
	var bolts := ArcBolt.new()
	root.add_child(bolts)
	bolts.configure()
	_check(bolts.pool_size() == ArcBolt.BOLTS
			and bolts.instance_count() == ArcBolt.BOLTS * ArcBolt.SEGMENTS,
		"the arc bolt pool is %d bolts of %d spans (%d instances)"
		% [ArcBolt.BOLTS, ArcBolt.SEGMENTS, bolts.instance_count()])
	_check(bolts.live_count() == 0, "and nothing is drawn until something discharges")

	var from := Vector3(0.0, 0.25, 0.0)
	var to := Vector3(0.9, 0.25, 0.0)
	bolts.strike(from, to, 1.0)
	bolts.step(0.001)
	_check(bolts.live_count() == 1, "one discharge is one bolt (%d)" % bolts.live_count())
	var line := bolts.last_points()
	_check(line.size() == ArcBolt.SEGMENTS + 1,
		"a bolt is %d spans between %d points (%d)"
		% [ArcBolt.SEGMENTS, ArcBolt.SEGMENTS + 1, line.size()])
	_check(line[0].is_equal_approx(from) and line[line.size() - 1].is_equal_approx(to),
		"pinned at the electrode and at the thing it earthed through")
	var off := _wp_max_offset(line, from, to)
	_check(off > 0.01,
		"the bolt is JAGGED, not a straight line (widest kink %.0f mm off the line)"
		% (off * 1000.0))
	# Two perpendicular axes, each up to JAG of the length, so the diagonal is the bound.
	_check(off <= ArcBolt.JAG * from.distance_to(to) * sqrt(2.0) * 1.01,
		"and no kink leaves the line by more than JAG allows (%.0f mm)" % (off * 1000.0))

	# DETERMINISM. The jag is an integer hash of the strike number and the span, never
	# `randf()`: two runs of one seed have to draw the same bolt in the same place, or
	# a replay is not a replay.
	var twin := ArcBolt.new()
	root.add_child(twin)
	twin.configure()
	twin.strike(from, to, 1.0)
	twin.step(0.001)
	var twin_line := twin.last_points()
	var same: bool = twin_line.size() == line.size()
	if same:
		for i in line.size():
			if not line[i].is_equal_approx(twin_line[i]):
				same = false
				break
	_check(same, "two bolts thrown from the same strike number are identical, to the millimetre")

	for i in 12:
		bolts.strike(from, to + Vector3(0.0, 0.0, 0.1 * float(i)), 1.0)
	_check(bolts.live_count() <= ArcBolt.BOLTS,
		"twelve discharges in one frame still fit the pool (%d of %d)"
		% [bolts.live_count(), ArcBolt.BOLTS])
	for i in 30:
		bolts.step(ArcBolt.LIFE_S * 0.2)
	_check(bolts.live_count() == 0,
		"every bolt is gone within its %.2f s life" % ArcBolt.LIFE_S)
	root.remove_child(twin)
	twin.free()
	root.remove_child(bolts)
	bolts.free()

	# --- the glow pool --------------------------------------------------------
	var glow := FxGlowPool.new()
	root.add_child(glow)
	glow.configure(4, Color(1.0, 0.5, 0.2), FxMaterials.FLAME_ENERGY,
		AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8)))
	_check(glow.pool_size() == 4 and glow.live_count() == 0,
		"the glow pool is four slots and starts dark")
	glow.set_glow(0, Vector3.ZERO, 0.2, 0.6)
	_check(glow.live_count() == 1 and absf(glow.level_of(0) - 0.6) < 0.01,
		"a slot holds the level it was given (%.2f)" % glow.level_of(0))
	glow.set_glow(0, Vector3.ZERO, 0.2, 0.0)
	_check(glow.live_count() == 0, "level zero clears the slot rather than drawing black")
	glow.set_glow(99, Vector3.ZERO, 0.2, 1.0)
	_check(glow.live_count() == 0, "a slot outside the pool is ignored and does not crash")
	root.remove_child(glow)
	glow.free()

	# --- the emitter pool -----------------------------------------------------
	var em := FxEmitters.new()
	root.add_child(em)
	await process_frame
	_check(em.pool_size() == FxEmitters.POOL and em.live_count() == 0,
		"the emitter pool is %d and starts idle" % FxEmitters.POOL)
	em.hold("grind", FxEmitters.SPARK, Vector3.ZERO, Vector3.UP, 1.0)
	_check(em.is_held("grind") and em.flavour_of("grind") == FxEmitters.SPARK
			and em.live_count() == 1,
		"a hold takes one emitter out of the pool and dresses it")
	em.hold("grind", FxEmitters.SPARK, Vector3.ONE, Vector3.UP, 0.5)
	_check(em.held_count() == 1, "holding the same key again re-points it, it does not take a second")
	em.sweep()
	_check(em.is_held("grind"), "a key held this frame survives the sweep")
	em.sweep()
	_check(not em.is_held("grind") and em.live_count() == 0,
		"a key that stopped being asked for is released by the next sweep")

	em.burst(FxEmitters.DUST, Vector3.ZERO, Vector3.UP, 1.0)
	_check(em.live_count() == 1, "a burst takes an emitter as a one shot")
	em.step(float(FxEmitters.LIVES[FxEmitters.DUST]) * 1.2)
	em.step(0.05)
	_check(em.live_count() == 0, "and hands it back once its particles have finished")

	var got := 0
	for i in FxEmitters.POOL + 4:
		if em.hold("fill%d" % i, FxEmitters.SMOKE, Vector3.ZERO, Vector3.UP, 1.0):
			got += 1
	_check(got == FxEmitters.POOL and em.refused_count() == 4,
		"the pool is the cap: %d holds granted, %d refused" % [got, em.refused_count()])
	em.stop_all()
	_check(em.live_count() == 0 and em.held_count() == 0, "stop_all empties it")
	root.remove_child(em)
	em.free()


## The cues, driven off doubles that answer exactly what the real parts answer.
func _wp_machines() -> void:
	var wfx: WeaponFx = _fx.weapon_fx()
	if wfx == null:
		_fail("FightFx owns a WeaponFx")
		return
	_ok("FightFx owns a WeaponFx and steps it on the presentation clock")
	var mix: AudioMix = _fx.audio_mix()

	# The dispatcher must stand back for all six: three of them share a KIND with an
	# older weapon and would otherwise take its loop (the napalm cannon is kind
	# `flame`, so `on_weapon_state` would start the flamethrower's burner on it).
	var arc_bot := _wp_bot("wp-arc", "tesla_arc", "4wd", Vector3(-2.0, 0.12, 0.0))
	var prod_bot := _wp_bot("wp-prod", "shock_prod", "4wd", Vector3(2.0, 0.12, 0.0))
	var drill_bot := _wp_bot("wp-drill", "drill_lance", "4wd", Vector3(0.0, 0.12, 2.0))
	var saw_bot := _wp_bot("wp-saw", "twin_saw", "4wd", Vector3(0.0, 0.12, -2.0))
	wfx.bind_bots([arc_bot, prod_bot, drill_bot, saw_bot])
	await _wp_frames(4)
	var claimed := 0
	for id in ["wp-arc", "wp-prod", "wp-drill", "wp-saw"]:
		if wfx.claims_loop(id):
			claimed += 1
	_check(claimed == 4,
		"WeaponFx claims the weapon loop for every wave P weapon it is driving (%d of 4)"
		% claimed)
	_check(WeaponFx.CLAIMED.size() == 6,
		"and it claims all six of them (%d)" % WeaponFx.CLAIMED.size())

	# --- the tesla arc --------------------------------------------------------
	arc_bot.weapon.charge = 0.30
	await _wp_frames(3)
	var arc_key := "wp:arc:wp-arc"
	_check(mix.loop_sound(arc_key) == "arc_crackle_loop",
		"a charging coil crackles (%s)" % mix.loop_sound(arc_key))
	var low_pitch := float(mix.loop_player(arc_key).get("pitch_scale"))
	arc_bot.weapon.charge = 1.0
	await _wp_frames(3)
	var high_pitch := float(mix.loop_player(arc_key).get("pitch_scale"))
	_check(high_pitch > low_pitch + 0.1,
		"and the crackle climbs as it charges (%.2f -> %.2f)" % [low_pitch, high_pitch])
	_check(wfx.glows().live_count() > 0, "the electrode glows while the coil is charged")

	var target := FakePart.new()
	target.name = "ArcTarget"
	root.add_child(target)
	target.global_position = Vector3(-1.2, 0.20, 0.0)
	arc_bot.weapon.target = target
	var before_strikes := wfx.arc_bolts().strike_count()
	arc_bot.weapon.arc_count += 1
	await _wp_frames(2)
	_check(wfx.arc_bolts().strike_count() == before_strikes + 1,
		"a discharge throws exactly one bolt (%d)" % (wfx.arc_bolts().strike_count() - before_strikes))
	_check(mix.active_count("arc_discharge") > 0, "and it cracks")
	# The bolt really reaches the thing it hit, rather than being a stub on the coil.
	var thrown := wfx.arc_bolts().last_points()
	var reach := 0.0 if thrown.is_empty() else thrown[0].distance_to(thrown[thrown.size() - 1])
	_check(thrown.size() > 1 and thrown[thrown.size() - 1].is_equal_approx(
			target.global_position),
		"the bolt ends ON the part it earthed through, not on the coil")
	_check(reach > 0.25,
		"so it really spans the gap (%.2f m)" % reach)
	arc_bot.weapon.charge = 0.0
	await _wp_frames(3)
	_check(not mix.has_loop(arc_key),
		"a discharged coil stops crackling: the sweep hands the voice back")

	# --- the shock prod -------------------------------------------------------
	prod_bot.weapon.contact = 0.20
	await _wp_frames(3)
	var spark_key := "%d:prod:wp-prod" % FxEmitters.SPARK
	_check(wfx.emitters().is_held(spark_key),
		"a prod held against a machine throws contact sparks")
	var zaps := wfx.arc_bolts().strike_count()
	prod_bot.weapon.shock_count += 1
	await _wp_frames(2)
	_check(wfx.arc_bolts().strike_count() == zaps + 1,
		"a bite arcs across the prongs")
	_check(mix.active_count("prod_zap") > 0, "and zaps")
	prod_bot.weapon.contact = 0.0
	await _wp_frames(3)
	_check(not wfx.emitters().is_held(spark_key),
		"the sparks stop the frame the prod comes away")

	# --- the drill ------------------------------------------------------------
	drill_bot.weapon.spin_v = 0.85
	await _wp_frames(3)
	_check(mix.loop_sound("wp:drill:wp-drill") == "drill_grind_loop",
		"a spinning lance grinds (%s)" % mix.loop_sound("wp:drill:wp-drill"))
	var curls := 0
	for i in 40:
		drill_bot.weapon.bore += STEP
		await _wp_frames(1)
		if wfx.emitters().flavour_of("%d:drill:wp-drill" % FxEmitters.SPARK) == FxEmitters.SPARK:
			curls += 1
	_check(curls > 20,
		"a lance in the work throws a spark stream for as long as it is boring (%d frames of %d)"
		% [curls, 40])
	_check(_wp_max_emitters >= 2,
		"and swarf curls come off it as well as sparks (peak %d emitters live)" % _wp_max_emitters)
	drill_bot.weapon.spin_v = 0.0
	await _wp_frames(3)
	_check(not mix.has_loop("wp:drill:wp-drill"), "a stopped lance is silent")

	# --- the twin saw ---------------------------------------------------------
	var blade_a := FakePart.new()
	var blade_b := FakePart.new()
	saw_bot.add_child(blade_a)
	saw_bot.add_child(blade_b)
	blade_a.position = Vector3(0.3, 0.0, 0.115)
	blade_b.position = Vector3(0.3, 0.0, -0.115)
	saw_bot.weapon.blades = [blade_a, blade_b]
	saw_bot.weapon.spin_v = 0.90
	saw_bot.weapon.cut = 0.1
	await _wp_frames(3)
	var lo: Node = mix.loop_player("wp:saw:wp-saw:lo")
	var hi: Node = mix.loop_player("wp:saw:wp-saw:hi")
	_check(lo != null and hi != null, "the twin saw runs two voices, one per disc")
	if lo != null and hi != null:
		var ratio := float(hi.get("pitch_scale")) / maxf(float(lo.get("pitch_scale")), 0.001)
		_check(absf(ratio - WeaponFx.SAW_OCTAVE) < 0.001,
			"and they are exactly an octave apart (%.3f)" % ratio)
		_check(float(hi.get("volume_db")) < float(lo.get("volume_db")),
			"with the upper disc under the lower, so the pair is not one loud blade")
	for i in 4:
		saw_bot.weapon.cut += STEP
		await _wp_frames(1)
	var lines := 0
	for i in 2:
		if wfx.emitters().is_held("%d:saw:wp-saw:%d" % [FxEmitters.SPARK, i]):
			lines += 1
	_check(lines == 2, "a cut throws a spark line off BOTH discs (%d)" % lines)
	blade_b.detached = true
	for i in 4:
		saw_bot.weapon.cut += STEP
		await _wp_frames(1)
	_check(not wfx.emitters().is_held("%d:saw:wp-saw:1" % FxEmitters.SPARK),
		"a disc that has come off stops cutting")

	for bot in [arc_bot, prod_bot, drill_bot, saw_bot]:
		bot.queue_free()
	target.queue_free()
	wfx.stop_all()
	await process_frame

	# --- the napalm cannon ----------------------------------------------------
	var fire_bot := _wp_bot("wp-fire", "napalm_cannon", "4wd", Vector3(0.0, 0.12, 0.0))
	wfx.bind_bots([fire_bot])
	await _wp_frames(2)
	fire_bot.weapon.shot_count += 1
	await _wp_frames(2)
	_check(mix.active_count("napalm_launch") > 0, "the mortar thumps when it throws a charge")

	var patch := FakePatch.new()
	patch.name = "Patch"
	root.add_child(patch)
	patch.global_position = Vector3(1.4, 0.0, 0.4)
	fire_bot.weapon.patch_list = [patch]
	await _wp_frames(3)
	var patch_key := "%d:charge:wp-fire:%d" % [FxEmitters.SMOKE, patch.get_instance_id()]
	_check(wfx.emitters().is_held(patch_key),
		"a charge in flight trails smoke")
	_check(wfx.glows().live_count() > 0, "and glows")
	var decals := FakeDecals.new()
	decals.name = "FakeDecals"
	root.add_child(decals)
	wfx.set("_decals", decals)
	patch.is_lit = true
	await _wp_frames(3)
	_check(decals.scorches.size() == 1,
		"a patch landing scorches the floor ONCE, not once a frame (%d)"
		% decals.scorches.size())
	if decals.scorches.size() == 1:
		var mark: Dictionary = decals.scorches[0]
		_check(absf((mark["at"] as Vector3).y) < 0.001,
			"and the mark is on the floor, not in the air (%.3f m)" % (mark["at"] as Vector3).y)
	var fire_key := "wp:patch:wp-fire:%d" % patch.get_instance_id()
	_check(mix.loop_sound(fire_key) == "fire_patch_loop",
		"a lit patch burns out loud (%s)" % mix.loop_sound(fire_key))
	_check(wfx.emitters().is_held("%d:patch:wp-fire:%d" % [FxEmitters.SMOKE, patch.get_instance_id()]),
		"with smoke standing off it")
	_check(wfx.emitters().is_held("%d:ember:wp-fire:%d" % [FxEmitters.EMBER, patch.get_instance_id()]),
		"and embers coming off the top")
	await _wp_frames(20)
	_check(decals.scorches.size() == 1,
		"twenty frames later it is still one mark (%d)" % decals.scorches.size())
	fire_bot.weapon.patch_list = []
	await _wp_frames(3)
	_check(not mix.has_loop(fire_key) and not wfx.emitters().is_held(patch_key),
		"the fire, the smoke and the embers all die WITH the patch")
	patch.queue_free()
	decals.queue_free()

	# --- the vortex, and its throw --------------------------------------------
	fire_bot.queue_free()
	wfx.stop_all()
	await process_frame
	var ring_bot := _wp_bot("wp-ring", "vortex_spinner", "4wd", Vector3(0.0, 0.12, 0.0))
	var hit_bot := _wp_bot("wp-hit", "ram", "4wd", Vector3(0.6, 0.12, 0.0))
	hit_bot._materials = {"front": "reactive", "rear": "steel"}
	wfx.bind_bots([ring_bot, hit_bot])
	ring_bot.weapon.charge = 0.7
	await _wp_frames(3)
	_check(mix.loop_sound("wp:vortex:wp-ring") == "vortex_spin_loop",
		"the vortex ring winds up (%s)" % mix.loop_sound("wp:vortex:wp-ring"))

	var hit := {"attacker": "wp-ring", "victim": "wp-hit", "part": "armour_front",
		"severity": 0.22, "position": Vector3(0.45, 0.16, 0.0), "impulse": 90.0,
		"detached": false, "tick": 1}
	wfx.on_damage_event(hit)
	_check(int(wfx.state_of("wp-ring").get("throws", 0)) == 1,
		"a bite from the ring is a lift throw")
	_check(mix.active_count("vortex_throw") > 0, "which is heard")
	wfx.on_damage_event(hit)
	_check(int(wfx.state_of("wp-ring").get("throws", 0)) == 1,
		"and two bites in one frame are still one throw, not a rumble")

	# --- the reactive plate ---------------------------------------------------
	_check(mix.active_count("reactive_clang") > 0,
		"a blow on a reactive plate fires its charge back at the attacker")
	var quiet := {"attacker": "wp-ring", "victim": "wp-hit", "part": "armour_rear",
		"severity": 0.22, "position": Vector3(-0.45, 0.16, 0.0), "impulse": 90.0,
		"detached": false, "tick": 2}
	var before_clangs := mix.active_count("reactive_clang")
	wfx.on_damage_event(quiet)
	_check(mix.active_count("reactive_clang") <= before_clangs,
		"and a blow on the STEEL face of the same machine does not")
	var cut_event := {"attacker": "wp-ring", "victim": "wp-hit", "part": "armour_front",
		"severity": 0.22, "position": Vector3(0.45, 0.16, 0.0), "impulse": 0.0,
		"detached": false, "tick": 3}
	var before_cut := mix.active_count("reactive_clang")
	wfx.on_damage_event(cut_event)
	_check(mix.active_count("reactive_clang") <= before_cut,
		"a SAW on a reactive plate does not fire it either: only a blow does (impulse 0)")

	ring_bot.queue_free()
	hit_bot.queue_free()
	wfx.stop_all()
	await process_frame

	# --- the hover ------------------------------------------------------------
	var hover_bot := _wp_bot("wp-hover", "", "hover", Vector3(0.0, 0.20, 0.0))
	wfx.bind_bots([hover_bot])
	hover_bot.chassis.linear_velocity = Vector3(2.4, 0.0, 0.0)
	await _wp_frames(4)
	_check(wfx.emitters().is_held("%d:skirt:wp-hover" % FxEmitters.DUST),
		"a hover's skirt throws dust off the boards")
	# The thruster pods are agent E's: their model carries a `glow` mesh in each fan
	# throat and `PartAnim` in HOVER mode brightens it with the work. A second glow
	# here would be two pulses at two rates on one machine, so there is not one.
	_check(wfx.glows().live_count() == 0,
		"and the pods are left to E's model, not glowed twice (%d slots lit)"
		% wfx.glows().live_count())
	hover_bot.drive_module.power = 0.0
	await _wp_frames(3)
	_check(not wfx.emitters().is_held("%d:skirt:wp-hover" % FxEmitters.DUST),
		"a dead drive stops blowing, and the dust goes with it")
	hover_bot.queue_free()
	wfx.stop_all()
	await process_frame

	# --- the walker -----------------------------------------------------------
	var walk_bot := _wp_bot("wp-legs", "", "legs", Vector3(0.0, 0.14, 0.0))
	wfx.bind_bots([walk_bot])
	walk_bot.chassis.linear_velocity = Vector3(2.0, 0.0, 0.0)
	await _wp_frames(int(1.0 / STEP))
	var steps := int(wfx.state_of("wp-legs").get("steps", 0))
	var want := int(round(2.0 / WeaponFx.STRIDE_M))
	_check(absi(steps - want) <= 1,
		"a walker at 2 m/s lands a pair of feet %d times a second (%d, %.2f m apart)"
		% [want, steps, WeaponFx.STRIDE_M])
	# THE SOUND HAS TO LAND WITH THE LEG. `PartAnim` swings each leg through one cycle
	# per `STRIDE_LENGTH` of travel and `legs.gd` trots them in diagonal pairs, so a
	# pair plants twice a cycle. A footfall spacing that was this node's own number
	# would walk out of step with the legs on screen inside a second.
	_check(is_equal_approx(WeaponFx.STRIDE_M, PartAnim.STRIDE_LENGTH * 0.5),
		"and it is agent E's stride, halved for the trot (%.2f m of E's %.2f)"
		% [WeaponFx.STRIDE_M, PartAnim.STRIDE_LENGTH])
	_check(mix.active_count("footfall") > 0, "and every one of them is heard")
	walk_bot.chassis.linear_velocity = Vector3.ZERO
	var still := int(wfx.state_of("wp-legs").get("steps", 0))
	await _wp_frames(int(0.5 / STEP))
	_check(int(wfx.state_of("wp-legs").get("steps", 0)) == still,
		"a walker standing still does not walk")
	walk_bot.queue_free()
	wfx.stop_all()
	await process_frame

	# --- the overcharge core --------------------------------------------------
	var core_bot := _wp_bot("wp-core", "horizontal_spinner", "4wd", Vector3(0.0, 0.12, 0.0))
	core_bot._cook_rate = 0.05
	core_bot.readiness = 1.0
	wfx.bind_bots([core_bot])
	await _wp_frames(int(3.0 / STEP))
	var hot := float(wfx.state_of("wp-core").get("heat", 0.0))
	var cooked := float(wfx.state_of("wp-core").get("cooked", 0.0))
	_check(hot > 0.15,
		"a weapon held at full heats the core (%.2f of the glow's range in 3 s)" % hot)
	_check(absf(cooked - 0.15) < 0.01,
		"by exactly the condition the simulation took off it (%.3f, cook_rate 0.05 x 3 s)"
		% cooked)
	_check(int(wfx.state_of("wp-core").get("ticks", 0)) > 0,
		"and it is ticking a warning (%d)" % int(wfx.state_of("wp-core").get("ticks", 0)))
	_check(wfx.glows().live_count() > 0, "the core glows with the heat")
	var ticked := int(wfx.state_of("wp-core").get("ticks", 0))
	core_bot.readiness = 0.0
	await _wp_frames(int(2.0 / STEP))
	_check(float(wfx.state_of("wp-core").get("heat", 0.0)) < hot,
		"letting the weapon idle cools it again, which is the dial the player has")
	_check(int(wfx.state_of("wp-core").get("ticks", 0)) == ticked,
		"and the warning stops the moment it stops cooking")

	# --- the stall ------------------------------------------------------------
	core_bot.stalled = true
	var stalls := int(wfx.state_of("wp-core").get("stalls", 0))
	await _wp_frames(int(1.0 / STEP))
	var stutters := int(wfx.state_of("wp-core").get("stalls", 0)) - stalls
	var want_stutters := int(1.0 / WeaponFx.STALL_EVERY_S)
	_check(absi(stutters - want_stutters) <= 1,
		"a machine whose drive has been cut stutters %d times a second (%d)"
		% [want_stutters, stutters])
	core_bot.stalled = false
	var settled := int(wfx.state_of("wp-core").get("stalls", 0))
	await _wp_frames(int(0.5 / STEP))
	_check(int(wfx.state_of("wp-core").get("stalls", 0)) == settled,
		"and it stops the moment the drive comes back")
	core_bot.queue_free()
	await process_frame

	# --- the budget, and the teardown ----------------------------------------
	print("      wave P peaks: %d emitters of %d, %d glows of %d, %d bolts of %d"
		% [_wp_max_emitters, FxEmitters.POOL, _wp_max_glows, WeaponFx.GLOW_SLOTS,
			_wp_max_arcs, ArcBolt.BOLTS])
	_check(_wp_max_emitters > 0 and _wp_max_emitters <= FxEmitters.POOL,
		"the emitter pool was used and never overflowed (peak %d of %d)"
		% [_wp_max_emitters, FxEmitters.POOL])
	_check(_wp_max_glows > 0 and _wp_max_glows <= WeaponFx.GLOW_SLOTS,
		"the glow pool was used and never overflowed (peak %d of %d)"
		% [_wp_max_glows, WeaponFx.GLOW_SLOTS])
	_check(_wp_max_arcs > 0 and _wp_max_arcs <= ArcBolt.BOLTS,
		"the bolt pool was used and never overflowed (peak %d of %d)"
		% [_wp_max_arcs, ArcBolt.BOLTS])
	_check(wfx.emitters().refused_count() == 0,
		"and nothing was ever refused an emitter in a real fight's worth of cues (%d)"
		% wfx.emitters().refused_count())
	# The whole point of the sweeps: a machine that goes takes its voices with it.
	wfx.stop_all()
	await process_frame
	_check(wfx.loop_keys().is_empty() and wfx.glows().live_count() == 0
			and wfx.emitters().live_count() == 0,
		"stop_all leaves no loop, no glow and no emitter behind")

	# The haptic contract is the one thing wave P could have broken from outside: it
	# adds five new senders, and the bridge caps at 30 a second however many there are.
	var worst := _wp_worst_haptic_second()
	_check(worst <= FightTypes.HAPTIC_MAX_PER_S,
		"wave P's cues never pushed the haptic rate past %d in any one second (worst %d)"
		% [FightTypes.HAPTIC_MAX_PER_S, worst])


## --- wave P helpers ---------------------------------------------------------

func _wp_bot(id: String, weapon_id: String, drive_id: String,
		at: Vector3) -> FakeWaveBot:
	var bot := FakeWaveBot.new()
	bot.bot_id = id
	bot.name = "Fake_" + id
	var drive := FakeWaveDrive.new()
	drive.id = drive_id
	bot.drive_module = drive
	var body := RigidBody3D.new()
	body.name = "Chassis"
	body.freeze = true
	body.contact_monitor = false
	bot.add_child(body)
	bot.chassis = body
	if weapon_id != "":
		var weapon := FakeWeapon.new()
		weapon.name = "Weapon"
		weapon.spec = {"id": weapon_id}
		weapon.head = FakePart.new()
		weapon.lance = FakePart.new()
		bot.add_child(weapon)
		weapon.add_child(weapon.head)
		weapon.add_child(weapon.lance)
		bot.weapon = weapon
	root.add_child(bot)
	bot.global_position = at
	return bot


## Step the FX tree `count` frames, recording the wave P pool peaks as it goes.
func _wp_frames(count: int) -> void:
	var wfx: WeaponFx = _fx.weapon_fx()
	for i in count:
		await process_frame
		if wfx == null:
			continue
		_wp_max_emitters = maxi(_wp_max_emitters, wfx.emitters().live_count())
		_wp_max_glows = maxi(_wp_max_glows, wfx.glows().live_count())
		_wp_max_arcs = maxi(_wp_max_arcs, wfx.arc_bolts().live_count())


## How far the widest kink of a bolt's polyline leaves the straight line from a to b.
static func _wp_max_offset(line: PackedVector3Array, a: Vector3, b: Vector3) -> float:
	var worst := 0.0
	var dir := (b - a).normalized()
	for point in line:
		var v: Vector3 = point - a
		worst = maxf(worst, (v - dir * v.dot(dir)).length())
	return worst


## The busiest one second window of haptic traffic across the whole run.
func _wp_worst_haptic_second() -> int:
	var worst := 0
	for i in _haptic_times.size():
		var n := 0
		for j in range(i, _haptic_times.size()):
			if _haptic_times[j] - _haptic_times[i] > 1.0:
				break
			n += 1
		worst = maxi(worst, n)
	return worst

## --- helpers ----------------------------------------------------------------

func _bot_position(bot_id: String) -> Vector3:
	var _unused := bot_id
	return TARGET_AT


func _run_frames(count: int) -> void:
	for i in count:
		await process_frame
		var v: int = _fx.bolt_shower().visible_instance_count()
		if v > _max_visible:
			_max_visible = v
		var s: int = _fx.collect_audio().semitones
		if s > _max_semitones:
			_max_semitones = s
		var t: int = _fx.bolt_shower().trail_live_count()
		if t > _max_trail:
			_max_trail = t
		var pool: FxFlashPool = _fx.bolt_shower().flash_pool()
		if pool != null and pool.live_count() > _max_flash:
			_max_flash = pool.live_count()
		var pieces: ScrapPieces = _fx.bolt_shower().pieces()
		if pieces != null:
			var drawn: int = pieces.live_instances()
			_max_pieces = maxi(_max_pieces, drawn)
			if drawn != v:
				_piece_mismatch = true
		var sparks: ScrapSparks = _fx.bolt_shower().sparks()
		if sparks != null:
			_max_rings = maxi(_max_rings, sparks.live_rings())
			_max_smoke = maxi(_max_smoke, sparks.live_smoke())
			_max_cpu_sparks = maxi(_max_cpu_sparks, sparks.live_sparks())


## One controlled shower, driven straight at `BoltShower.spawn` rather than through
## `on_scrap_awarded`.
##
## That is deliberate: phase 5 is about what a shower is MADE of, and the award path
## would also fire the impact audio, the haptics and the camera kick for a hit that is
## not happening, which would poison the rate cap numbers phase 3 measured. Everything
## the spawn contract itself does (the pool, the delay, the magnet, the collect) is
## already covered above.
##
## Returns what the shower looked like: the shape histogram and the piece sizes two
## frames in (before anything has magnetised), the heat then and again after the
## cooling time, and how far the pieces had been thrown.
func _shower(part: String, material: String, severity: float, detached: bool,
		count: int) -> Dictionary:
	var shower := _fx.bolt_shower()
	var sparks: ScrapSparks = shower.sparks()
	var smoke_before: int = sparks.live_smoke() if sparks != null else 0
	shower.spawn(SPAWN_AT, count, "player-1", _bot_position, {
		"severity": severity, "part": part, "material": material,
		"detached": detached, "victim": "ai-1",
	})
	var smoke_fired: int = (sparks.live_smoke() if sparks != null else 0) - smoke_before
	await _run_frames(2)
	var hist := shower.kind_histogram()
	var born := _piece_stats(shower)
	# Long enough for the hot edge to have cooled and the magnet to have taken over.
	await _run_frames(int(BoltShower.HOT_COOL_S / STEP) + 2)
	var cooled := _piece_stats(shower)
	await _drain()
	return {
		"hist": hist,
		"count": born["count"],
		"mean_size": born["mean_size"],
		"max_size": born["max_size"],
		"mean_dist": born["mean_dist"],
		"max_heat": born["max_heat"],
		"cool_heat": cooled["max_heat"],
		"smoke": smoke_fired,
	}


func _piece_stats(shower: BoltShower) -> Dictionary:
	var n := 0
	var size_total := 0.0
	var dist_total := 0.0
	var max_size := 0.0
	var max_heat := 0.0
	for i in FightTypes.BOLT_POOL:
		var st: Dictionary = shower.piece_state(i)
		if st.is_empty():
			continue
		n += 1
		var size := float(st["size"])
		size_total += size
		max_size = maxf(max_size, size)
		max_heat = maxf(max_heat, float(st["heat"]))
		dist_total += (st["pos"] as Vector3).distance_to(SPAWN_AT)
	var denom := maxf(1.0, float(n))
	return {
		"count": n,
		"mean_size": size_total / denom,
		"max_size": max_size,
		"mean_dist": dist_total / denom,
		"max_heat": max_heat,
	}


## Run until the pool is empty again, so one mini shower cannot leak slots into the
## next. Bounded well inside BoltShower.MAX_LIFE_S, which would sweep them up anyway.
func _drain() -> void:
	for i in 600:
		if _fx.bolt_shower().live_count() == 0:
			return
		await _run_frames(1)


func _on_bolts_landed(bot_id: String, amount: int) -> void:
	var _unused := bot_id
	_collect_times.append(_fx.now())
	_collect_amounts.append(amount)


func _on_message_sent(type: String, payload: Dictionary) -> void:
	if type != FightTypes.MSG_HAPTIC:
		return
	_haptic_times.append(_fx.now() if _fx != null else 0.0)
	_haptic_kinds.append(str(payload.get("kind", "")))


func _kind_count(kind: String) -> int:
	var n := 0
	for k in _haptic_kinds:
		if k == kind:
			n += 1
	return n


## Bolts must arrive as a stream, never all at once: the stagger is what makes the
## pitch ramp audible at all (brief §6). Arrival times are frame quantised, so a few
## bolts sharing a frame is just the 60 Hz grid, not a clump; what matters is that
## the arrivals spread over real time and no single frame swallows a handful.
func _stagger_report() -> Dictionary:
	var n := _collect_times.size()
	if n < 2:
		return {"spread": 0.0, "max_per_frame": n, "mean_gap_ms": 0.0}
	var spread: float = _collect_times[n - 1] - _collect_times[0]
	var worst := 1
	var run := 1
	for i in range(1, n):
		if is_equal_approx(_collect_times[i], _collect_times[i - 1]):
			run += 1
			worst = maxi(worst, run)
		else:
			run = 1
	return {"spread": spread, "max_per_frame": worst, "mean_gap_ms": spread / float(n - 1) * 1000.0}


## The most haptics inside any one second window.
##
## The comparison is written the way `FightHaptics._prune` writes it -- looking BACK
## from each send at `t > now - window` -- and not the algebraically equal
## `t_later - t_earlier < window`. The two disagree by one float ulp on a timestamp
## that has been accumulated 1/60 at a time for a couple of seconds, and that
## disagreement is enough to read 31 out of a limiter that let exactly 30 through.
## Agent F3 hit it when the scrap pass lengthened the stream past a second; it was
## always there, it was just never reachable before. The contract being tested is the
## limiter's, so the test now asks the limiter's own question.
func _max_in_window(times: Array[float], window: float) -> int:
	var best := 0
	for j in times.size():
		var cutoff: float = times[j] - window
		var n := 0
		for i in range(j, -1, -1):
			if times[i] > cutoff:
				n += 1
			else:
				break
		best = maxi(best, n)
	return best


## Glow only has something to work with above `glow_hdr_threshold`, and
## `tonemap_exposure` is applied first. Godot's default threshold is 1.0 and
## `Arena/render/arena_env.tres` does not override it, so the sum is
## `luminance x energy x exposure > threshold`. If G1 raises the threshold or drops
## the exposure, this is what says so, instead of the bolts quietly going matte.
func _check_glow_headroom() -> bool:
	const ENV_PATH := "res://render/arena_env.tres"
	if not ResourceLoader.exists(ENV_PATH):
		printerr("      note: ", ENV_PATH, " is missing, so nothing to check against")
		return true
	var env: Environment = load(ENV_PATH) as Environment
	if env == null:
		printerr("      ", ENV_PATH, " did not load as an Environment")
		return false
	if not env.glow_enabled:
		printerr("      note: glow is off in ", ENV_PATH, ", nothing will bloom")
		return true
	var exposure: float = env.tonemap_exposure
	var hdr: float = FightTypes.BOLT_GOLD.get_luminance() * FxMaterials.BOLT_EMISSION * exposure
	var ok: bool = hdr > env.glow_hdr_threshold
	print("      bolt HDR luminance %.2f vs glow threshold %.2f (exposure %.2f)"
		% [hdr, env.glow_hdr_threshold, exposure])
	if not ok:
		printerr("      the bolts will NOT bloom: raise FxMaterials.BOLT_EMISSION",
			" or ask G1 to lower glow_hdr_threshold")
	return ok


## The four FX billboards, and the one import setting that has to be forced on them.
func _check_fx_textures() -> bool:
	var ok := true
	for name in ["flame_soft.png", "spark_glow.png", "dust_soft.png", "trail_streak.png"]:
		var path: String = FxMaterials.TEX_DIR + str(name)
		if not ResourceLoader.exists(path):
			printerr("      missing FX texture import: ", path)
			ok = false
			continue
		if load(path) as Texture2D == null:
			printerr("      not a Texture2D: ", path)
			ok = false
		# Read the .import rather than the texture: a CompressedTexture2D does not
		# report its mipmap count under the dummy renderer, but the setting that
		# produced it is right there on disk.
		var text := FileAccess.get_file_as_string(path + ".import")
		if not text.contains("mipmaps/generate=true"):
			printerr("      mipmaps are OFF for ", path,
				" -- run python3 Arena/fx/textures/make_fx_textures.py")
			ok = false
	return ok


func _check_audio_imports() -> bool:
	var ok := true
	for key in FightFx.SOUNDS:
		var path: String = FightFx.SOUNDS[key]
		if not ResourceLoader.exists(path):
			printerr("      missing import: ", path)
			ok = false
			continue
		var stream: Resource = load(path)
		if not (stream is AudioStreamWAV):
			printerr("      not an AudioStreamWAV: ", path)
			ok = false
	var motor: AudioStreamWAV = load("res://audio/motor_loop.wav") as AudioStreamWAV
	if motor == null or motor.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		printerr("      motor_loop.wav is not set to loop forward")
		ok = false
	return ok


## --- reporting ---------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_ok(label)
	else:
		_fail(label)


func _ok(label: String) -> void:
	_checks += 1
	print("PASS  ", label)


func _skip(label: String) -> void:
	_skipped += 1
	print("SKIP  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	printerr("FAIL  ", label)
	print("FAIL  ", label)


func _finish() -> void:
	# Tear down before quit(), or the engine reports leaked objects and the audio
	# streams as still in use at exit.
	if _fx != null and is_instance_valid(_fx):
		root.remove_child(_fx)
		_fx.free()
	_fx = null
	_hud = null
	if _host != null and is_instance_valid(_host):
		root.remove_child(_host)
		_host.free()
	_host = null
	print("")
	if _failures == 0:
		print("PASS  fx: %d checks, 0 failures, %d skipped" % [_checks, _skipped])
		quit(0)
	else:
		print("FAIL  fx: %d checks, %d failures, %d skipped" % [_checks, _failures, _skipped])
		quit(1)
