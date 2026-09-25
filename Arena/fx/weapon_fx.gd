class_name WeaponFx extends Node3D
## What wave P's parts LOOK and SOUND like (wave P, agent F).
##
## The six weapons, the three drives, the overcharge core and the reactive plate all
## landed working and silent: the arc had no bolt, the fire patch had no smoke, the
## prod had no spark, the walker and the hover fell back to a 4WD's tyre roll, and a
## core cooking itself to death gave the player nothing at all until the machine
## died of it. This node is the feedback for all of them.
##
## IT FINDS THE MACHINES ITSELF, for the reason `MachineAudio` does: `set_motor_state`
## sat unwired for six stages because it was a call somebody had to remember to make.
## Nothing in `fight.gd` calls this node; it walks the fight world every `RESCAN_S`,
## reads each machine's weapon, drive and core through their own public accessors, and
## drives the pools from what it reads. The only things pushed to it are the two cues
## that are damage EVENTS rather than states, and `FightFx.on_damage_event` forwards
## those in its wave P section.
##
## HARD RULE (spec section 7): presentation. It only ever READS the bots, it runs in
## `_process` (through `FightFx`'s clock, so the headless test can step it at a fixed
## delta), it never draws from the fight's rng and it never touches physics state.
## Delete the FX subtree and the result JSON is identical.
##
## WHAT IT OWNS, and what it borrows. It owns an `ArcBolt` pool, an `FxGlowPool` and
## an `FxEmitters`. It borrows `FightParticles` for the flash quads, the impact lights
## and the spark bursts, because a discharge landing on a plate is the same event as a
## hit landing on a plate and the budget for it is already paid.
##
##     var wfx := WeaponFx.new()
##     add_child(wfx)
##     wfx.bind(audio_mix, haptics, particles)     # then nothing: it finds the bots
##     wfx.step(delta)

## Where the bots live in the fight world, exactly as `MachineAudio` looks them up.
const BOTS_HOLDER := "Bots"
const RESCAN_S := 0.5
## How many machines get wave P feedback. The same four as the movement layer: past
## it, the machines already running keep theirs.
const MAX_MACHINES := 4

## The wave P weapon ids, and the fact that this node owns their weapon LOOP. The
## Stage 3 dispatcher in `FightFx.on_weapon_state` maps a weapon's KIND to one of
## five loops, and three of the six wave P weapons would take the wrong one: the
## napalm cannon is kind `flame`, so holding the button would start the flamethrower's
## burner on a machine that is lobbing mortar shells, and the twin saw and the vortex
## would take the single saw's cut and the plain spinner's rev. `claims_loop()` is how
## the dispatcher knows to stand back.
const CLAIMED := {
	"shock_prod": true, "tesla_arc": true, "drill_lance": true,
	"twin_saw": true, "napalm_cannon": true, "vortex_spinner": true,
}

# --- the tesla arc ------------------------------------------------------------
## The crackle while the coil charges: quiet and low at the start of the wind-up,
## at its written level and half an octave up by the time it will fire.
const ARC_CRACKLE_PITCH := [0.80, 1.55]
const ARC_CRACKLE_DB := [-16.0, 0.0]
const ARC_CHARGE_MIN := 0.02
## The electrode's own glow, in metres, and the tint of everything electric here.
const ARC_GLOW_M := 0.17
const ARC_TINT := Color(0.72, 0.86, 1.0)
## How far a bolt reaches when the target has gone (detached, or the machine is out)
## between the discharge and the presentation frame that draws it. It still fires:
## the arc happened, and a discharge with nothing on the end of it is a coil earthing
## itself, which is what this is.
const ARC_STRAY_M := 0.55

# --- the shock prod -----------------------------------------------------------
## The little bolt between the prongs when the prod bites, in metres.
const PROD_ARC_M := 0.16
const PROD_GLOW_M := 0.10
## Contact sparks: level climbs over the arming time, so a touch fizzes and a held
## prod throws a stream.
const PROD_ARM_S := 0.12

# --- the drill ----------------------------------------------------------------
const DRILL_PITCH := [0.70, 1.35]
const DRILL_DB := [-15.0, 0.0]
const DRILL_SPIN_MIN := 0.04
## One curl of swarf per this many seconds of boring. A flute lifts a curl out of the
## hole a few times a second; more than this and the tip is a fountain of metal.
const CURL_EVERY_S := 0.18
## HOW LONG THE WORK SPARKS SURVIVE A GAP. `boring_seconds` and `cutting_seconds` are
## counted in the PHYSICS tick and read in the PRESENTATION frame, and the two are not
## locked together: a presentation frame that lands between two physics ticks sees no
## progress at all and would strobe the spark stream off and on. The sparks therefore
## hold for a moment after the last tick of work, which is also what a real shower of
## sparks does when the blade skips.
const WORK_HOLD_S := 0.15

# --- the twin saw -------------------------------------------------------------
## The two voices. `SAW_OCTAVE` is exactly 2, because the point is that they are one
## octave apart and not that they are detuned: two blades on one arbor under two
## different loads is the same drive heard twice.
const SAW_PITCH := [0.62, 1.22]
const SAW_DB := [-14.0, 0.0]
const SAW_OCTAVE := 2.0
const SAW_SPIN_MIN := 0.04

# --- the napalm cannon --------------------------------------------------------
## Fire patches that get a voice. Four can burn at once; four fire loops is a wash,
## and the two nearest the middle of the fight carry it.
const MAX_PATCH_VOICES := 2
## Patches that get smoke and embers. More than this and the arena is weather.
const MAX_PATCH_FX := 4
## The charge in flight: how hot its tail glows and how big the lump reads.
const CHARGE_GLOW_M := 0.22
const PATCH_GLOW_M := 0.62
const FIRE_TINT := Color(1.0, 0.56, 0.18)

# --- the vortex ---------------------------------------------------------------
const VORTEX_PITCH := [0.55, 2.10]
const VORTEX_DB := [-16.0, 0.0]
## The shortest gap between two lift throws from one machine. A ring in the work
## lands a bite every few physics ticks and the throw is the moment, not the contact.
const THROW_GAP_S := 0.75
## How hard a bite has to be to read as a throw rather than as a scuff.
const THROW_MIN_SEVERITY := 0.05

# --- the hover ----------------------------------------------------------------
## Skirt dust: always a little (the cushion is always blowing), more with speed.
const SKIRT_IDLE := 0.25
const SKIRT_SPEED_MS := 3.2
## THE THRUSTER PODS ARE AGENT E'S, not this node's. Their model carries a `glow` mesh
## in each of the four fan throats and `PartAnim` in HOVER mode brightens it with the
## work the fans are doing (docs/wave-p-e-notes.md, `HOVER_GLOW_MIN/MAX`). A second
## glow here would be two pulses at two rates on one machine, so the pods are left to
## the model and this node draws only what the model cannot: the dust.

# --- the walker ---------------------------------------------------------------
## METRES OF TRAVEL PER FOOTFALL, and it is agent E's number, not a number of this
## node's own. `PartAnim` in STRIDE mode swings each leg through one cycle every
## `STRIDE_LENGTH` of travel, and `legs.gd` hands the four legs the phases of a TROT:
## two diagonal pairs, half a cycle apart. So a pair of feet lands twice per cycle,
## which is once every half of E's stride length, and a footfall sound that used its
## own number would walk out of step with the legs on screen within a second.
const STRIDE_M := PartAnim.STRIDE_LENGTH * 0.5
## A walker that is turning on the spot is still stepping, so the phase also advances
## with yaw: this is metres of stride per radian of turn.
const STRIDE_PER_RAD := 0.10
## Below this the machine is standing still and a footfall would be a bug.
const STRIDE_MIN_MS := 0.15

# --- the overcharge core ------------------------------------------------------
## The cook this node calls "hot". `_cook_rate` is 0.004 a second by default, so full
## heat is about 75 seconds of the weapon held at full, which is roughly the point
## D2's note calls expensive (0.72 of the core over a whole fight).
const COOK_FULL := 0.30
## How long the core takes to give the heat back once the weapon idles. It is a
## picture of temperature, not of damage: the damage never comes back.
const COOL_S := 6.0
## Where the warning starts, and the tick interval at that point and at full heat.
const COOK_WARN_AT := 0.22
const COOK_TICK_SLOW := 1.30
const COOK_TICK_FAST := 0.34
## Smoke once the core is genuinely in trouble.
const COOK_SMOKE_AT := 0.62
const CORE_GLOW_M := 0.26
const CORE_TINT := Color(1.0, 0.42, 0.12)

# --- readability from the fight camera (weapons pass, 2026-09-25) -------------
## The weapons gauntlet looked at every weapon from the fight camera and found that
## the arc and the prod read as the same white flash as any hit, the ram and the lifter
## had no effect of their own, the bar spinner read as a thin stick and the flame as a
## small orange puff. Each weapon now has its own colour and shape, and none of it
## touches the shared contact flash (`FightParticles`' white-out is the combat
## engineer's): these are this node's own glows, bolts, bursts and blur meshes.
##
## ELECTRIC BLUE is the tesla arc's and nobody else's: a saturated blue flash at the
## target, a fat bolt, and a blue burn that stays on the struck part for ARC_BURN_S.
const ARC_HIT_TINT := Color(0.28, 0.52, 1.0)
const ARC_BOLT_SCALE := 1.8
const ARC_BURN_S := 0.35
const ARC_BURN_M := 0.42
## VIOLET is the prod's: a short, hot, purple crackle at the prongs, so a prod and an
## arc never look alike even though both are electric.
const PROD_TINT := Color(0.80, 0.36, 1.0)
const PROD_BURN_S := 0.25
const PROD_BURN_M := 0.30
## THE RAM'S BLOW: a warm flash, a ring of floor dust thrown out from the contact and
## a fan of orange sparks along the charge, all scaled by how hard it landed. The
## hardest blows add the crunch layer.
const RAM_TINT := Color(1.0, 0.66, 0.30)
const RAM_CRUNCH_SEVERITY := 0.10
## THE LIFTER'S LIFT: a hydraulic clunk and a dust puff off the floor the moment the
## forks start carrying something, and an amber work light on the forks while they do.
const LIFT_TINT := Color(1.0, 0.78, 0.22)
const LIFT_GLOW_M := 0.34
const LIFT_START := 0.06
## THE SPINNER'S BLUR: a spinning bar or ring is invisible at speed on a phone, so it
## gets what a camera sees of one: a faint disc where the bar sweeps and a bright rim
## at the tip circle, both fading in with the spin. Bar radius is the catalogue reach.
const BLUR_DISC_ALPHA := 0.16
const BLUR_RIM_ALPHA := 0.55
const BLUR_RIM_WIDTH := 0.045
const BLUR_MIN_SPIN := 0.12
const BLUR_TINT := Color(0.86, 0.90, 0.96)
const BLUR_POOL := 4

# --- the stall ----------------------------------------------------------------
## A machine whose drive has been cut stutters: a small arc walks across the hull
## every STALL_EVERY_S until it comes back. It is the only thing on screen that says
## the prod, the arc or the fire did anything, because the effect itself is the other
## machine simply stopping.
const STALL_EVERY_S := 0.16
const STALL_ARC_M := 0.22

## Pools.
const GLOW_SLOTS := 16
const ARC_POOL := 4

var _mix: AudioMix = null
var _haptics: FightHaptics = null
var _particles: FightParticles = null
var _arcs: ArcBolt = null
var _glow: FxGlowPool = null
var _emitters: FxEmitters = null

var _machines: Array = []
## Agent G1's pooled decal projector, if this world has one. `fight.gd` builds it as
## "DamageDecals" beside the FX tree and feeds it from the damage drain; the only thing
## wave P adds to it is the scorch a fire patch leaves on the floor, which no damage
## event can describe because the fire is not a hit and it is not where the hit was.
var _decals: Node = null
var _scorched: Dictionary = {}
var _bound := false
var _state: Dictionary = {}                 ## bot_id -> bookkeeping
var _now: float = 0.0
var _next_scan: float = -1.0
var _enabled := true

## Loop key -> the SOUNDS name it is playing, and which keys were asked for this
## frame. A loop nobody asked for is stopped in `_sweep`, so an eliminated machine
## cannot leave a saw running.
var _loops: Dictionary = {}
var _loops_touched: Dictionary = {}
## Glow slot allocation by key, same discipline.
var _glow_of: Dictionary = {}
var _glow_touched: Dictionary = {}
var _glow_free: Array[int] = []
## The spinner blur meshes: bot_id -> {"disc": MeshInstance3D, "rim": MeshInstance3D},
## and which of them were asked for this frame (the rest are hidden by `_sweep`).
var _blurs: Dictionary = {}
var _blur_touched: Dictionary = {}


func _ready() -> void:
	_arcs = ArcBolt.new()
	_arcs.name = "ArcBolts"
	add_child(_arcs)
	_arcs.configure(ARC_POOL)

	_glow = FxGlowPool.new()
	_glow.name = "Glows"
	add_child(_glow)
	_glow.configure(GLOW_SLOTS, Color(1.0, 1.0, 1.0), FxMaterials.FLAME_ENERGY,
		AABB(Vector3(-14.0, -3.0, -14.0), Vector3(28.0, 12.0, 28.0)))
	for i in GLOW_SLOTS:
		_glow_free.append(GLOW_SLOTS - 1 - i)

	_emitters = FxEmitters.new()
	_emitters.name = "Emitters"
	add_child(_emitters)
	set_process(false)


## `mix` is the audio director, `haptics` the rate limited sender and `particles` the
## existing flash, light and spark pools. Without a mix this node still draws; without
## particles it still sounds. Nothing here is required for the rest to work.
func bind(mix: AudioMix, haptics: FightHaptics, particles: FightParticles) -> void:
	_mix = mix
	_haptics = haptics
	_particles = particles


## Hand the machines over instead of letting this node find them. The test uses it.
func bind_bots(bots: Array) -> void:
	_machines = bots.duplicate()
	_bound = true


func set_enabled(on: bool) -> void:
	if _enabled == on:
		return
	_enabled = on
	if not on:
		stop_all()


## True when this node is driving the weapon loop for `bot_id`, in which case the
## Stage 3 kind-to-loop dispatcher must not also start one. See CLAIMED.
##
## It answers from the MACHINE when this node has not stepped yet, which is the first
## frame of every fight: `fight.gd` runs its `_process` before the FX tree's (parent
## before child), so an answer that waited for the first step would let a napalm
## cannon start the flamethrower's burner for one frame.
func claims_loop(bot_id: String) -> bool:
	var st: Dictionary = _state.get(bot_id, {})
	if not st.is_empty():
		return bool(st.get("claimed", false))
	if _machines.is_empty() and not _bound:
		_scan()
	for machine in _machines:
		if machine == null or not is_instance_valid(machine):
			continue
		if str(machine.get("bot_id")) == bot_id:
			return CLAIMED.has(_weapon_id(machine))
	return false


## One presentation frame.
func step(delta: float) -> void:
	if not _enabled or delta <= 0.0:
		return
	_now += delta
	if not _bound and _now >= _next_scan:
		_next_scan = _now + RESCAN_S
		_scan()
	_drop_dead()
	var live := 0
	for machine in _machines:
		if live >= MAX_MACHINES:
			break
		# A machine can be FREED between two scans and a freed object cannot even be
		# passed to a typed parameter, so the check belongs here, at the call site.
		if machine == null or not is_instance_valid(machine):
			continue
		if _step_machine(machine, delta):
			live += 1
	_sweep()
	if _emitters != null:
		_emitters.sweep()
		_emitters.step(delta)
	if _arcs != null:
		_arcs.step(delta)


## Silence and clear everything this node owns.
func stop_all() -> void:
	if _mix != null:
		for key in _loops.keys():
			_mix.stop_loop(str(key))
	_loops.clear()
	_loops_touched.clear()
	for pair in _blurs.values():
		((pair as Dictionary)["disc"] as MeshInstance3D).visible = false
		((pair as Dictionary)["rim"] as MeshInstance3D).visible = false
	_blur_touched.clear()
	if _glow != null:
		_glow.clear_all()
	_glow_of.clear()
	_glow_touched.clear()
	_glow_free.clear()
	for i in GLOW_SLOTS:
		_glow_free.append(GLOW_SLOTS - 1 - i)
	if _emitters != null:
		_emitters.stop_all()
	_state.clear()
	_scorched.clear()
	if not _bound:
		_machines.clear()
	_next_scan = -1.0


# ---------------------------------------------------------------- the flipper (combat feel B6)

## bot_id -> the flipper's `throws()` last seen here.
var _flipper_throws: Dictionary = {}


## Called by FightFx when a flipper fires. True when this fire THREW something (the
## flipper's own throw counter moved), false for a dry fire. A throw also gets its dust ring
## off the floor in front of the machine. Read only, like everything in this node.
func flipper_threw(bot_id: String) -> bool:
	var bot: Variant = _bot_by_id(bot_id)
	if bot == null:
		return false
	var weapon: Variant = bot.get("weapon")
	if not (weapon is Object) or not (weapon as Object).has_method("throws"):
		return false
	var now_count := int((weapon as Object).call("throws"))
	var was := int(_flipper_throws.get(bot_id, 0))
	_flipper_throws[bot_id] = now_count
	if now_count <= was:
		return false
	var chassis: Variant = bot.get("chassis")
	if _emitters != null and chassis is RigidBody3D:
		var body := chassis as RigidBody3D
		var fwd := body.global_basis.x
		fwd.y = 0.0
		var front := body.global_position + (fwd.normalized() * 0.45 if fwd.length() > 0.01 else Vector3.ZERO)
		_emitters.burst(FxEmitters.DUST, Vector3(front.x, 0.02, front.z), Vector3.UP, 0.8)
	return true


# ---------------------------------------------------------------- the two events

## The cues that are events rather than states. `FightFx.on_damage_event` forwards
## every damage event here from its wave P section; both of the things below are
## decided from the payload and from what the two machines are made of, never from
## anything the simulation had to be asked for.
func on_damage_event(info: Dictionary) -> void:
	if not _enabled:
		return
	var at := _as_vector3(info.get("position", Vector3.ZERO))
	var attacker := str(info.get("attacker", ""))
	var victim := str(info.get("victim", ""))
	var severity := float(info.get("severity", 0.0))
	# `impulse` is 0.0 for every DIRECT damage event (a cut, a burn, the core cooking
	# itself) and the blow's newton seconds for every impact. It is therefore the one
	# field that tells a shove apart from a saw, which matters because reactive armour
	# only answers a blow.
	var impulse := float(info.get("impulse", 0.0))
	var part := str(info.get("part", ""))

	if impulse > 0.0 and attacker != "" and attacker != "arena" and attacker != victim:
		_lift_throw(attacker, at, severity)
		_reactive_shove(victim, part, at, severity)
	# The ram's blow is a DIRECT impact (impulse 0.0, source "impact"): see ram.gd.
	if impulse == 0.0 and str(info.get("source", "")) == "impact" and attacker != "" \
			and attacker != "arena" and attacker != victim:
		_ram_blow(attacker, at, severity)


## The vortex's bite goes up, not sideways: the machine it hits leaves the floor, and
## what the player sees of that is the dust it takes with it.
func _lift_throw(attacker: String, at: Vector3, severity: float) -> void:
	if severity < THROW_MIN_SEVERITY:
		return
	var bot: Variant = _bot_by_id(attacker)
	if bot == null or _weapon_id(bot) != "vortex_spinner":
		return
	var st: Dictionary = _state.get(attacker, {})
	if st.is_empty() or _now - float(st.get("throw_at", -100.0)) < THROW_GAP_S:
		return
	st["throw_at"] = _now
	st["throws"] = int(st["throws"]) + 1
	var floor_at := Vector3(at.x, 0.02, at.z)
	if _emitters != null:
		_emitters.burst(FxEmitters.DUST, floor_at, Vector3.UP, 0.6 + 0.4 * severity)
	if _particles != null:
		_particles.burst_sparks(at, clampf(severity * 1.4, 0.2, 1.0))
	_play("vortex_throw", at, 0.0, 0.94 + 0.12 * clampf(severity, 0.0, 1.0))
	_haptic("impact_heavy")


## The ram landing a blow: a warm flash, floor dust thrown out from the contact and a
## fan of sparks along the charge, sized by the blow. `ram_hit` itself is the damage
## event's weapon layer (FeelTiers.WEAPON_LAYER), so it is not played twice here; the
## crunch is added on top only for the hardest blows.
func _ram_blow(attacker: String, at: Vector3, severity: float) -> void:
	var bot: Variant = _bot_by_id(attacker)
	if bot == null or _weapon_id(bot) != "ram":
		return
	var big := clampf(severity / 0.15, 0.35, 1.0)
	var st: Dictionary = _state.get(attacker, {})
	if not st.is_empty():
		st["rams"] = int(st["rams"]) + 1
	var along := Vector3.RIGHT
	var chassis: Variant = bot.get("chassis")
	if chassis is RigidBody3D:
		along = (chassis as RigidBody3D).global_basis.x
		along.y = 0.0
		along = along.normalized() if along.length_squared() > 1e-6 else Vector3.RIGHT
	if _particles != null:
		var flash := _particles.flash_pool()
		if flash != null:
			flash.flash(at, 0.9 + 0.8 * big, RAM_TINT)
		_particles.burst_sparks(at, big)
	if _emitters != null:
		_emitters.burst(FxEmitters.DUST, Vector3(at.x, 0.02, at.z), Vector3.UP, 0.6 + 0.4 * big)
		_emitters.burst(FxEmitters.SPARK, at, (along + Vector3.UP * 0.35).normalized(), big)
	if severity >= RAM_CRUNCH_SEVERITY:
		_play("ram_crush", at, -3.0, 0.95 + 0.1 * _fract(at))
	_haptic("impact_heavy")


## The lifter: a clunk and a dust puff when the forks start carrying something, and
## an amber work light on them while they do.
func _lifter_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3, forward: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var lift := _f(weapon, "lift_fraction", 0.0)
	var loaded: bool = weapon.has_method("opponent_on_wedge") \
		and bool(weapon.call("opponent_on_wedge"))
	var tip := socket + forward * 0.3
	var arm: Variant = weapon.get("arm")
	if arm != null and is_instance_valid(arm) and arm is Node3D:
		tip = (arm as Node3D).global_position + forward * 0.12
	var carrying := loaded and lift > LIFT_START
	if carrying and not bool(st["lifting"]):
		st["lifts"] = int(st["lifts"]) + 1
		if _emitters != null:
			_emitters.burst(FxEmitters.DUST, Vector3(tip.x, 0.02, tip.z), Vector3.UP, 0.9)
		_play("crusher_clamp", tip, -2.0, 0.72)
		_haptic("impact_heavy")
	st["lifting"] = carrying
	if carrying:
		_hold_glow("lift:" + bot_id, tip + Vector3.UP * 0.08, LIFT_GLOW_M,
			clampf(0.45 + lift, 0.45, 1.0), LIFT_TINT)


## The arc's blue burn and the prod's violet one, held a beat after the bite.
func _electric_burns(bot_id: String, st: Dictionary) -> void:
	if _now < float(st.get("arc_until", -100.0)):
		var k := (float(st["arc_until"]) - _now) / ARC_BURN_S
		_hold_glow("arcburn:" + bot_id, st["arc_to"] as Vector3, ARC_BURN_M,
			clampf(k, 0.2, 1.0), ARC_HIT_TINT)
	if _now < float(st.get("prod_until", -100.0)):
		var k := (float(st["prod_until"]) - _now) / PROD_BURN_S
		_hold_glow("prodburn:" + bot_id, st["prod_at"] as Vector3, PROD_BURN_M,
			clampf(k, 0.2, 1.0), PROD_TINT)


## A spinning bar or ring as a camera sees one: a faint swept disc and a bright tip
## circle, both following the weapon body and fading with the spin.
func _blur(bot_id: String, weapon: Variant, body_name: String, radius: float,
		chassis: RigidBody3D) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var spin := _f(weapon, "readiness", 0.0)
	if spin < BLUR_MIN_SPIN:
		return
	var body: Variant = weapon.get(body_name)
	if body == null or not is_instance_valid(body) or not (body is Node3D) \
			or bool(body.get("detached")):
		return
	var pair: Dictionary = _blurs.get(bot_id, {})
	if pair.is_empty():
		if _blurs.size() >= BLUR_POOL:
			return
		pair = _make_blur()
		_blurs[bot_id] = pair
	_blur_touched[bot_id] = true
	var at := (body as Node3D).global_position
	var up := chassis.global_basis.y.normalized()
	var basis := Basis(Quaternion(Vector3.UP, up))
	for key in ["disc", "rim"]:
		var mesh := pair[key] as MeshInstance3D
		mesh.visible = true
		mesh.global_transform = Transform3D(basis.scaled(Vector3(radius, 1.0, radius)), at)
	var k := clampf((spin - BLUR_MIN_SPIN) / (1.0 - BLUR_MIN_SPIN), 0.0, 1.0)
	((pair["disc"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a \
		= BLUR_DISC_ALPHA * k
	((pair["rim"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a \
		= BLUR_RIM_ALPHA * k


## One disc and one rim, unit radius (scaled to the weapon), additive, no shadows.
func _make_blur() -> Dictionary:
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.004
	cyl.radial_segments = 32
	cyl.rings = 1
	disc.mesh = cyl
	disc.material_override = _blur_material(BLUR_DISC_ALPHA)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - BLUR_RIM_WIDTH
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = _blur_material(BLUR_RIM_ALPHA)
	for m in [disc, rim]:
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(m as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		(m as MeshInstance3D).visible = false
		add_child(m)
	return {"disc": disc, "rim": rim}


static func _blur_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(BLUR_TINT.r, BLUR_TINT.g, BLUR_TINT.b, alpha)
	return m


static func _spec_of(weapon: Variant) -> Dictionary:
	if weapon == null or not is_instance_valid(weapon):
		return {}
	var spec: Variant = weapon.get("spec")
	return spec as Dictionary if spec is Dictionary else {}


## How many spinner blurs are showing. Introspection for the tests.
func blur_count() -> int:
	var n := 0
	for pair in _blurs.values():
		if ((pair as Dictionary)["disc"] as MeshInstance3D).visible:
			n += 1
	return n


## A reactive plate firing its charge into whoever landed the blow. The plate is the
## VICTIM's, and the damage event carries no material, so it is read off the victim
## itself: the face the part key names, and what that face is made of.
func _reactive_shove(victim: String, part: String, at: Vector3, severity: float) -> void:
	if not part.begins_with("armour_"):
		return
	var bot: Variant = _bot_by_id(victim)
	if bot == null:
		return
	var materials: Variant = bot.get("_materials")
	if not (materials is Dictionary):
		return
	if str((materials as Dictionary).get(part.substr(7), "")) != "reactive":
		return
	var big := clampf(severity * 2.0, 0.25, 1.0)
	if _particles != null:
		var flash := _particles.flash_pool()
		if flash != null:
			flash.flash(at, 1.1 + 0.9 * big, Color(1.0, 0.86, 0.66))
		_particles.burst_sparks(at, big)
	if _emitters != null and bot.get("chassis") is RigidBody3D:
		# Outward: away from the machine that carries the plate, which is the way the
		# charge fires and the way the attacker goes.
		var out := at - (bot.get("chassis") as RigidBody3D).global_position
		out.y = 0.0
		_emitters.burst(FxEmitters.SMOKE, at, out.normalized() if out.length() > 0.01
			else Vector3.UP, 0.5)
	_play("reactive_clang", at, 0.0, 0.96 + 0.08 * big)
	_haptic("impact_heavy")


# ---------------------------------------------------------------- one machine

## Returns true when this machine got wave P feedback this frame.
func _step_machine(machine: Variant, delta: float) -> bool:
	var chassis: RigidBody3D = machine.get("chassis") as RigidBody3D
	if chassis == null or not chassis.is_inside_tree():
		return false
	var bot_id := str(machine.get("bot_id"))
	if bot_id.is_empty():
		bot_id = (machine as Node).name
	var st: Dictionary = _state.get(bot_id, {})
	if st.is_empty():
		st = _new_state(machine)
		_state[bot_id] = st
	st["bot"] = machine

	var weapon: Variant = machine.get("weapon")
	var wid := _weapon_id(machine)
	st["claimed"] = CLAIMED.has(wid)
	var at := chassis.global_position
	var forward := chassis.global_basis.x
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.RIGHT
	var socket := at
	if machine.has_method("weapon_socket_world"):
		socket = machine.call("weapon_socket_world")

	match wid:
		"tesla_arc":
			_arc_weapon(bot_id, st, weapon, socket, forward)
		"shock_prod":
			_prod_weapon(bot_id, st, weapon, socket, forward)
		"drill_lance":
			_drill_weapon(bot_id, st, weapon, socket, forward)
		"twin_saw":
			_saw_weapon(bot_id, st, weapon, socket)
		"napalm_cannon":
			_napalm_weapon(bot_id, st, weapon, socket, forward)
		"vortex_spinner":
			_vortex_weapon(bot_id, weapon, at)
			_blur(bot_id, weapon, "ring", float(_spec_of(weapon).get("reach", 0.48)), chassis)
		"full_body_spinner":
			_blur(bot_id, weapon, "ring", float(_spec_of(weapon).get("reach", 0.45)), chassis)
		"horizontal_spinner":
			_blur(bot_id, weapon, "bar", float(_spec_of(weapon).get("reach", 0.55)), chassis)
		"lifter":
			_lifter_weapon(bot_id, st, weapon, socket, forward)
		_:
			pass
	_electric_burns(bot_id, st)

	_drive(bot_id, st, machine, chassis, at, forward, delta)
	_cook(bot_id, st, machine, at, delta)
	_stall(st, machine, chassis)
	return true


func _new_state(machine: Variant) -> Dictionary:
	return {
		"bot": machine, "claimed": false,
		"arcs": -1, "shocks": -1, "shots": -1,
		"bore": 0.0, "bore_at": -100.0, "cut": 0.0, "cut_at": -100.0,
		"curl_at": -100.0,
		"stride": 0.0, "foot": 0, "steps": 0,
		"heat": 0.0, "cooked": 0.0, "tick_at": -100.0, "ticks": 0,
		"stall_at": -100.0, "stall_side": 0, "stalls": 0,
		"throw_at": -100.0, "throws": 0,
		"arc_to": Vector3.ZERO, "arc_until": -100.0,
		"prod_at": Vector3.ZERO, "prod_until": -100.0,
		"lifting": false, "lifts": 0, "rams": 0,
	}


# ---------------------------------------------------------------- the weapons

## The coil: a crackle that climbs with the charge, a glow on the electrode, and a
## bolt to whatever it just earthed itself through.
func _arc_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3, forward: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var charge := _f(weapon, "readiness", 0.0)
	var electrode := _socket(st, weapon, "socket_spark", socket)
	if charge > ARC_CHARGE_MIN:
		_loop("wp:arc:" + bot_id, "arc_crackle_loop", electrode,
			_span(ARC_CRACKLE_DB, charge), _span(ARC_CRACKLE_PITCH, charge))
		_hold_glow("arc:" + bot_id, electrode, ARC_GLOW_M, charge * 0.85, ARC_TINT)

	var arcs := int(_f(weapon, "arcs", 0.0))
	if int(st["arcs"]) < 0:
		st["arcs"] = arcs
		return
	if arcs <= int(st["arcs"]):
		return
	st["arcs"] = arcs
	var to := electrode + forward * ARC_STRAY_M
	if weapon.has_method("last_target"):
		var target: Variant = weapon.call("last_target")
		if target != null and is_instance_valid(target) and target is Node3D:
			to = (target as Node3D).global_position
	if _arcs != null:
		_arcs.strike(electrode, to, ARC_BOLT_SCALE)
	if _particles != null:
		var flash := _particles.flash_pool()
		if flash != null:
			flash.flash(electrode, 1.0, ARC_HIT_TINT)
			flash.flash(to, 1.6, ARC_HIT_TINT)
		_particles.burst_sparks(to, 0.55)
	# The blue burn stays on the struck part a beat after the bolt has gone, so the
	# discharge reads at phone size rather than as a one-frame white pop.
	st["arc_to"] = to
	st["arc_until"] = _now + ARC_BURN_S
	_play("arc_discharge", to, 0.0, 0.96 + 0.08 * _fract(electrode))
	# A machine is out of your hands for 1.6 s: the discharge is a big moment and it
	# gets a big tick. Nothing else on this weapon sends one, so the cap is untouched.
	_haptic("impact_heavy")


## The prod: a fizz while it is held against something, a little bolt across the
## prongs when it bites.
func _prod_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3, forward: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var head := socket
	var body: Variant = weapon.get("head")
	if body != null and is_instance_valid(body) and body is Node3D:
		head = (body as Node3D).global_position
	var contact := _f(weapon, "contact_seconds", 0.0)
	if contact > 0.0:
		var level := clampf(contact / PROD_ARM_S, 0.25, 1.0)
		_hold(FxEmitters.SPARK, "prod:" + bot_id, head + forward * 0.06,
			forward * 0.4 + Vector3.UP, level)
		_hold_glow("prod:" + bot_id, head, PROD_GLOW_M, level, PROD_TINT)

	var shocks := int(_f(weapon, "shocks", 0.0))
	if int(st["shocks"]) < 0:
		st["shocks"] = shocks
		return
	if shocks <= int(st["shocks"]):
		return
	st["shocks"] = shocks
	if _arcs != null:
		# Across the prongs, not out at the victim: a prod earths through whatever it
		# is touching and the visible arc is the one between its own tips.
		var across := Vector3(-forward.z, 0.0, forward.x) * PROD_ARC_M
		_arcs.strike(head - across * 0.5, head + across * 0.5, 0.7)
	if _particles != null:
		var flash := _particles.flash_pool()
		if flash != null:
			flash.flash(head, 1.1, PROD_TINT)
		_particles.burst_sparks(head, 0.35)
	st["prod_at"] = head
	st["prod_until"] = _now + PROD_BURN_S
	_play("prod_zap", head, 0.0, 0.95 + 0.1 * _fract(head))
	_haptic("impact_light")


## The lance: a grind that follows the spin, a spark stream out of the hole and a
## curl of swarf every fifth of a second it is actually boring.
func _drill_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3, forward: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var spin := _f(weapon, "spin", 0.0)
	var tip := socket + forward * 0.18
	var body: Variant = weapon.get("lance")
	if body != null and is_instance_valid(body) and body is Node3D:
		tip = (body as Node3D).global_position + forward * 0.15
	if spin > DRILL_SPIN_MIN:
		_loop("wp:drill:" + bot_id, "drill_grind_loop", tip,
			_span(DRILL_DB, spin), _span(DRILL_PITCH, spin))

	var bore := _f(weapon, "boring_seconds", 0.0)
	if bore > float(st["bore"]) + 0.0001:
		st["bore"] = bore
		st["bore_at"] = _now
	if _now - float(st["bore_at"]) > WORK_HOLD_S:
		return
	# Back along the lance and up: swarf and sparks come OUT of the hole, toward the
	# machine doing the boring, which is what makes the effect read as a hole.
	var out := (-forward * 0.75 + Vector3.UP * 0.65).normalized()
	_hold(FxEmitters.SPARK, "drill:" + bot_id, tip, out, clampf(spin, 0.4, 1.0))
	if _now - float(st["curl_at"]) >= CURL_EVERY_S:
		st["curl_at"] = _now
		if _emitters != null:
			_emitters.burst(FxEmitters.CURL, tip, out, 0.8)


## Two discs on one arbor: two spark lines and two voices an octave apart.
func _saw_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var spin := _f(weapon, "spin", 0.0)
	if spin > SAW_SPIN_MIN:
		var pitch := _span(SAW_PITCH, spin)
		var db := _span(SAW_DB, spin)
		_loop("wp:saw:" + bot_id + ":lo", "twin_saw_loop", socket, db, pitch)
		# The upper disc is a shade quieter: two blades at one level is one loud blade.
		_loop("wp:saw:" + bot_id + ":hi", "twin_saw_loop", socket, db - 2.5,
			pitch * SAW_OCTAVE)

	var cut := _f(weapon, "cutting_seconds", 0.0)
	if cut > float(st["cut"]) + 0.0001:
		st["cut"] = cut
		st["cut_at"] = _now
	if _now - float(st["cut_at"]) > WORK_HOLD_S:
		return
	var blades: Variant = weapon.get("blades")
	if not (blades is Array):
		return
	var index := 0
	for blade_variant in (blades as Array):
		var blade: Variant = blade_variant
		if blade == null or not is_instance_valid(blade) or not (blade is Node3D):
			index += 1
			continue
		if bool(blade.get("detached")):
			index += 1
			continue
		# Up and back off the rim: a disc in a cut throws its sparks over itself.
		_hold(FxEmitters.SPARK, "saw:%s:%d" % [bot_id, index],
			(blade as Node3D).global_position, Vector3.UP, clampf(spin, 0.4, 1.0))
		index += 1


## The mortar: the shot, the charge in flight, and the patches it leaves burning.
func _napalm_weapon(bot_id: String, st: Dictionary, weapon: Variant,
		socket: Vector3, forward: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var shots := int(_f(weapon, "shots_fired", 0.0))
	if int(st["shots"]) < 0:
		st["shots"] = shots
	elif shots > int(st["shots"]):
		st["shots"] = shots
		var muzzle := _socket(st, weapon, "socket_muzzle",
			socket + forward * 0.12 + Vector3.UP * 0.04)
		if _emitters != null:
			_emitters.burst(FxEmitters.SMOKE, muzzle,
				(forward * 0.6 + Vector3.UP).normalized(), 0.75)
		if _particles != null:
			var flash := _particles.flash_pool()
			if flash != null:
				flash.flash(muzzle, 1.2, FIRE_TINT)
		_play("napalm_launch", muzzle, 0.0, 0.97 + 0.06 * _fract(muzzle))
		_haptic("flip")

	if not weapon.has_method("patches"):
		return
	var patches: Variant = weapon.call("patches")
	if not (patches is Array):
		return
	var shown := 0
	var voiced := 0
	for patch_variant in (patches as Array):
		var patch: Variant = patch_variant
		if patch == null or not is_instance_valid(patch) or not (patch is Node3D):
			continue
		if shown >= MAX_PATCH_FX:
			break
		shown += 1
		var where: Vector3 = (patch as Node3D).global_position
		var key := "%s:%d" % [bot_id, (patch as Object).get_instance_id()]
		var lit: bool = patch.has_method("lit") and bool(patch.call("lit"))
		if not lit:
			# In flight: a glowing lump with a smoke tail. The lump itself is the
			# weapon's own emissive shell; this is the tail and the heat around it.
			_hold_glow("charge:" + key, where, CHARGE_GLOW_M, 0.85, FIRE_TINT)
			_hold(FxEmitters.SMOKE, "charge:" + key, where, Vector3.DOWN * 0.4
				+ Vector3.UP * 0.2, 0.45)
			continue
		# Alight: smoke standing off it, embers off the top, and the fire's own glow
		# on the floor. The flames are the weapon's `FlameCone`, which it already
		# stands on its end; everything here is what a fire has that a cone does not.
		_hold(FxEmitters.SMOKE, "patch:" + key, where + Vector3.UP * 0.30,
			Vector3.UP, 0.85)
		_hold(FxEmitters.EMBER, "ember:" + key, where + Vector3.UP * 0.12,
			Vector3.UP, 0.7)
		_hold_glow("patch:" + key, where + Vector3.UP * 0.05, PATCH_GLOW_M,
			0.75, FIRE_TINT)
		# The mark it leaves. Once per patch, the frame it lands: a scorch outlives the
		# fire, which is the whole reason the floor of a fought-in arena reads as fought
		# in, and the only thing wave P has that no damage event can describe.
		if not _scorched.has(key):
			_scorched[key] = true
			if _decals != null and is_instance_valid(_decals) \
					and _decals.has_method("add_scorch"):
				_decals.call("add_scorch", Vector3(where.x, 0.0, where.z),
					PATCH_GLOW_M * 1.4)
		if voiced < MAX_PATCH_VOICES:
			voiced += 1
			_loop("wp:patch:" + key, "fire_patch_loop", where, 0.0,
				0.94 + 0.1 * _fract(where))


## The vortex ring: a spin-up that is all air. The throw itself is a damage event.
func _vortex_weapon(bot_id: String, weapon: Variant, at: Vector3) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	var spin := _f(weapon, "readiness", 0.0)
	if spin <= 0.02:
		return
	_loop("wp:vortex:" + bot_id, "vortex_spin_loop", at,
		_span(VORTEX_DB, spin), _span(VORTEX_PITCH, spin))


# ---------------------------------------------------------------- the drives

## The two drives with no wheels. Everything a wheeled machine's contact with the
## floor says is said by `MachineAudio`'s roll; these two have no roll, so what they
## are doing has to be shown instead.
func _drive(bot_id: String, st: Dictionary, machine: Variant, chassis: RigidBody3D,
		at: Vector3, forward: Vector3, delta: float) -> void:
	var drive: Variant = machine.get("drive_module")
	if drive == null or not is_instance_valid(drive):
		return
	var drive_id := str(drive.get("id"))
	var v := chassis.linear_velocity
	var speed := Vector2(v.x, v.z).length()
	var power := clampf(_f(drive, "power_scale", 1.0), 0.0, 1.0)
	if power <= 0.0:
		return

	if drive_id == "hover":
		# The cushion is always blowing, so the dust is never off while the drive is
		# answering; it is thrown BACKWARD and slightly up, because that is where the
		# air under a moving skirt goes. The pods are E's model (see the note above).
		var ride := _f(drive, "hover_height", 0.2)
		var under := Vector3(at.x, maxf(at.y - ride * 0.9, 0.02), at.z)
		var level := clampf(SKIRT_IDLE + speed / SKIRT_SPEED_MS, 0.0, 1.0) * power
		_hold(FxEmitters.DUST, "skirt:" + bot_id, under,
			Vector3.UP * 0.3 - forward * 0.6, level)
		return

	if drive_id != "legs":
		return
	# The walker. There is no gait in the simulation (the feet are shapes on the hull,
	# docs/wave-p-d2-notes.md section 3), so the stride is worked out from how far the
	# machine has actually travelled and how far it has turned: a machine pivoting on
	# the spot is still putting feet down. That makes the footfall rate honest at every
	# speed without the drive having to expose a phase it does not have.
	var yaw := absf(chassis.angular_velocity.y)
	if speed < STRIDE_MIN_MS and yaw < 0.25:
		return
	st["stride"] = float(st["stride"]) \
		+ (speed * delta + yaw * delta * STRIDE_PER_RAD) / STRIDE_M
	if float(st["stride"]) < 1.0:
		return
	st["stride"] = float(st["stride"]) - 1.0
	st["steps"] = int(st["steps"]) + 1
	var foot := int(st["foot"])
	st["foot"] = (foot + 1) % 2
	# A TROT: the two diagonal pairs land alternately, which is the gait `legs.gd`
	# hands PartAnim and the only one a rigid four legged machine can use without
	# looking like it is falling over. The dust is put under the LEADING foot of the
	# pair that just landed, so it alternates corner to corner the way the legs do.
	var side_sign := 1.0 if foot == 0 else -1.0
	var fore_sign := 1.0
	var side := Vector3(-forward.z, 0.0, forward.x)
	var down := Vector3(at.x, 0.03, at.z) + forward * (0.16 * fore_sign) \
		+ side * (0.14 * side_sign)
	if _emitters != null:
		_emitters.burst(FxEmitters.DUST, down, Vector3.UP, 0.55)
	_play("footfall", down, 0.0, 0.94 + 0.12 * _fract(down))


# ---------------------------------------------------------------- the core

## The overcharge core cooking itself. `Bot._cook_core` takes condition off the core
## for every second the weapon is at full readiness; this is the same condition read
## as a TEMPERATURE, so it climbs while the weapon is held at full and falls back when
## it is let go. The damage never comes back; the picture of it does, because a core
## that stayed glowing for the rest of the fight would stop meaning anything.
func _cook(bot_id: String, st: Dictionary, machine: Variant, at: Vector3,
		delta: float) -> void:
	var rate: Variant = machine.get("_cook_rate")
	if not (rate is float or rate is int) or float(rate) <= 0.0:
		return
	var full: bool = machine.has_method("weapon_readiness") \
		and float(machine.call("weapon_readiness")) >= 1.0
	var heat := float(st["heat"])
	if full:
		heat = clampf(heat + float(rate) * delta / COOK_FULL, 0.0, 1.0)
		st["cooked"] = float(st["cooked"]) + float(rate) * delta
	else:
		heat = maxf(heat - delta / COOL_S, 0.0)
	st["heat"] = heat
	if heat <= 0.01:
		return

	var core := at + Vector3.UP * 0.06
	_hold_glow("core:" + bot_id, core, CORE_GLOW_M, heat, CORE_TINT)
	if heat >= COOK_SMOKE_AT:
		_hold(FxEmitters.SMOKE, "core:" + bot_id, core + Vector3.UP * 0.10,
			Vector3.UP, (heat - COOK_SMOKE_AT) / maxf(1.0 - COOK_SMOKE_AT, 0.01))
	if heat < COOK_WARN_AT or not full:
		return
	# The tick tightens as the core heats, the way the knockout count does: the rate
	# is the information, not the sound.
	var t := (heat - COOK_WARN_AT) / maxf(1.0 - COOK_WARN_AT, 0.01)
	var gap := lerpf(COOK_TICK_SLOW, COOK_TICK_FAST, clampf(t, 0.0, 1.0))
	if _now - float(st["tick_at"]) < gap:
		return
	st["tick_at"] = _now
	st["ticks"] = int(st["ticks"]) + 1
	_play("cook_warning", core, 0.0, 1.0 + 0.30 * clampf(t, 0.0, 1.0))
	_haptic("ko_tick")


## A machine whose drive has been cut. The prod, the arc and a fire patch all do this
## and NONE of them has an effect of its own on the machine that stops, so without
## this the only thing the player sees is an opponent that has inexplicably parked.
func _stall(st: Dictionary, machine: Variant, chassis: RigidBody3D) -> void:
	if not machine.has_method("is_disrupted") or not bool(machine.call("is_disrupted", "drive")):
		return
	if _now - float(st["stall_at"]) < STALL_EVERY_S:
		return
	st["stall_at"] = _now
	st["stalls"] = int(st["stalls"]) + 1
	var side := int(st["stall_side"])
	st["stall_side"] = (side + 1) % 4
	# The arc walks around the hull, a quarter turn at a time, so the stutter reads as
	# the whole machine shorting out rather than as one corner sparking.
	var basis := chassis.global_basis
	var a := chassis.global_position + basis.x * (0.14 if side % 2 == 0 else -0.14) \
		+ basis.z * (0.12 if side < 2 else -0.12)
	var b := a + basis.z * (STALL_ARC_M if side < 2 else -STALL_ARC_M)
	if _arcs != null:
		_arcs.strike(a, b, 0.55)
	if _particles != null:
		var flash := _particles.flash_pool()
		if flash != null:
			flash.flash(a, 0.5, ARC_TINT)


# ---------------------------------------------------------------- finding them

## Walk the fight world for machines, exactly as `MachineAudio` does: this node is a
## child of `FightFx`, which `fight.gd` swaps into the World, and the bots live beside
## it under "Bots", with a full walk as the fallback for a scene that differs.
func _scan() -> void:
	var found: Array = []
	var fx := get_parent()
	var world: Node = fx.get_parent() if fx != null else null
	if world != null:
		var holder := world.get_node_or_null(BOTS_HOLDER)
		if holder != null:
			for child in holder.get_children():
				if _is_machine(child):
					found.append(child)
		if found.is_empty():
			_collect(world, found, 0)
		if _decals == null or not is_instance_valid(_decals):
			_decals = world.get_node_or_null("DamageDecals")
	_machines = found


func _collect(node: Node, out: Array, depth: int) -> void:
	if depth > 3 or out.size() >= MAX_MACHINES:
		return
	for child in node.get_children():
		if _is_machine(child):
			out.append(child)
		else:
			_collect(child, out, depth + 1)


static func _is_machine(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Node):
		return false
	# Duck typed on purpose: the test's double is not a `Bot` and must still work.
	return node.get("chassis") is RigidBody3D and node.get("drive_module") != null


## A machine that has gone takes its loops, glows and emitters with it.
func _drop_dead() -> void:
	for id in _state.keys():
		var st: Dictionary = _state[id]
		var machine: Variant = st.get("bot", null)
		if machine == null or not is_instance_valid(machine) \
				or not (machine as Node).is_inside_tree():
			_state.erase(id)


func _bot_by_id(bot_id: String) -> Variant:
	var st: Dictionary = _state.get(bot_id, {})
	var machine: Variant = st.get("bot", null)
	if machine == null or not is_instance_valid(machine):
		return null
	return machine


## AGENT E'S SOCKETS. The models carry empties at the points an effect should leave
## from: `socket_spark` at the tesla coil's electrode tip and `socket_muzzle` at the
## napalm mortar's mouth (docs/wave-p-e-notes.md). They are ordinary named Node3Ds
## inside the instantiated model, so they are found by name once and then remembered.
##
## The fallback is the weapon's mount point, which is what this node used before the
## models landed and what a part still drawing its primitive fallback has: a machine
## whose model failed to load gets its bolt from the socket instead of from nowhere.
func _socket(st: Dictionary, root: Variant, socket_name: String,
		fallback: Vector3) -> Vector3:
	var key := "socket:" + socket_name
	var held: Variant = st.get(key, null)
	if held is bool:
		return fallback                      # looked for once, not there
	if held != null and is_instance_valid(held) and (held as Node3D).is_inside_tree():
		return (held as Node3D).global_position
	if root == null or not is_instance_valid(root) or not (root is Node):
		return fallback
	var found := _find_named(root as Node, socket_name, 0)
	if found == null:
		st[key] = false
		return fallback
	st[key] = found
	return found.global_position


static func _find_named(node: Node, socket_name: String, depth: int) -> Node3D:
	if depth > 5:
		return null
	for child in node.get_children():
		if child is Node3D and String(child.name).begins_with(socket_name):
			return child as Node3D
		var deeper := _find_named(child, socket_name, depth + 1)
		if deeper != null:
			return deeper
	return null


static func _weapon_id(machine: Variant) -> String:
	var weapon: Variant = machine.get("weapon")
	if weapon == null or not is_instance_valid(weapon):
		return ""
	var spec: Variant = weapon.get("spec")
	if spec is Dictionary:
		return str((spec as Dictionary).get("id", ""))
	return ""


# ---------------------------------------------------------------- the pools

## Start or re-point a loop, and remember that it was asked for this frame.
func _loop(key: String, sound: String, at: Vector3, db: float, pitch: float) -> void:
	if _mix == null:
		return
	_loops_touched[key] = true
	if not _loops.has(key):
		if _mix.start_loop(key, sound, at, db, pitch) == null:
			return
		_loops[key] = sound
		return
	_mix.set_loop(key, pitch, db, at)


func _hold(flavour: int, key: String, at: Vector3, aim: Vector3, level: float) -> void:
	if _emitters == null:
		return
	_emitters.hold("%d:%s" % [flavour, key], flavour, at, aim, level)


## A glow slot is handed out by key and handed back by `_sweep`, so a caller never
## holds a number and a machine that vanishes cannot keep a slot lit.
func _hold_glow(key: String, at: Vector3, size: float, level: float,
		tint: Color) -> void:
	if _glow == null:
		return
	_glow_touched[key] = true
	var slot: int = int(_glow_of.get(key, -1))
	if slot < 0:
		if _glow_free.is_empty():
			return
		slot = _glow_free.pop_back()
		_glow_of[key] = slot
	_glow.set_glow(slot, at, size, level, tint)


## Everything that was not asked for this frame stops. One sweep for the loops and
## one for the glows; `FxEmitters` sweeps itself the same way.
func _sweep() -> void:
	if not _loops.is_empty():
		var dead: Array[String] = []
		for key_variant in _loops.keys():
			var key := str(key_variant)
			if not _loops_touched.has(key):
				dead.append(key)
		for key in dead:
			if _mix != null:
				_mix.stop_loop(key)
			_loops.erase(key)
	_loops_touched.clear()

	if not _glow_of.is_empty():
		var cold: Array[String] = []
		for key_variant in _glow_of.keys():
			var key := str(key_variant)
			if not _glow_touched.has(key):
				cold.append(key)
		for key in cold:
			var slot: int = int(_glow_of[key])
			_glow_of.erase(key)
			if _glow != null:
				_glow.clear_glow(slot)
			_glow_free.append(slot)
	_glow_touched.clear()

	for key_variant in _blurs.keys():
		if not _blur_touched.has(key_variant):
			var pair: Dictionary = _blurs[key_variant]
			(pair["disc"] as MeshInstance3D).visible = false
			(pair["rim"] as MeshInstance3D).visible = false
	_blur_touched.clear()


func _play(sound: String, at: Variant, db: float, pitch: float) -> void:
	if _mix == null:
		return
	_mix.play(sound, at, db, pitch)


func _haptic(kind: String) -> void:
	if _haptics != null:
		_haptics.send(kind, _now)


# ---------------------------------------------------------------- introspection

func arc_bolts() -> ArcBolt:
	return _arcs


func glows() -> FxGlowPool:
	return _glow


func emitters() -> FxEmitters:
	return _emitters


func machine_count() -> int:
	return _machines.size()


func loop_keys() -> Array:
	return _loops.keys()


## The last frame's readings for one machine, for the test: heat, cooked, stride.
func state_of(bot_id: String) -> Dictionary:
	var st: Dictionary = (_state.get(bot_id, {}) as Dictionary).duplicate()
	st.erase("bot")
	return st


func now() -> float:
	return _now


# ---------------------------------------------------------------- small helpers

## A repeatable 0..1 from a world position, for pitch variation that must not call
## `randf()` and must not draw from `AudioMix.jitter` either: two machines firing in
## the same frame have to get different pitches in the same order in a replay.
static func _fract(at: Vector3) -> float:
	var v := absf(at.x * 37.1 + at.y * 91.7 + at.z * 13.3)
	return v - floor(v)


static func _span(pair: Variant, t: float) -> float:
	var a: Array = pair
	return lerpf(float(a[0]), float(a[1]), clampf(t, 0.0, 1.0))


## Every reading off a weapon or a drive goes through here, so a half built machine,
## a detached weapon or a test double cannot take the FX tree down with it.
static func _f(obj: Variant, method: String, fallback: float) -> float:
	if obj == null or not is_instance_valid(obj) or not obj.has_method(method):
		return fallback
	var v: Variant = obj.call(method)
	return float(v) if (v is float or v is int) else fallback


static func _as_vector3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
