class_name ArenaBase extends Node3D
## Everything six arenas share (docs/stage5-spec.md §3, brief §7): the floor slab, the
## walls with their chevron cap, G1's render setup (arena_env + key + fill + probe), the
## out-of-arena sensor, the two spawn markers, G2's PBR materials with a per-arena tint,
## a floor-marking kit, and the hazard construction kit (spike patch, grinder disc, flame
## jet) that more than one arena uses.
##
## The Yard is now the thinnest possible subclass of this; the Grinder, Drop Zone,
## Furnace, Crush and Coliseum are the others. Nothing here knows about the camera (agent
## C owns the rig) or about the fight (agent R owns fight.gd).
##
## THE CONTRACT fight.gd reads, and every subclass keeps:
##   signal body_out(body)          any body that left the arena
##   setup(rng)                     seeded hazard phase, called once before the countdown
##   spawn_position(i) / spawn_facing(i)
##   spikes_risen() / seconds_to_spike_rise() / spike_patch_centre()
##   hazard_helpers() -> Dictionary the AI's read of the danger
##   arena_size() / arena_half_extent()   NOT FightTypes.ARENA_SIZE: the Coliseum is 12 m
##   hazard_schedule() -> Array     wave A, READ-ONLY: every hazard's footprint and seconds
##                                  to its next activation, for the shared warning layer
##                                  (hazard_telegraph.gd). Never mutates anything.

signal body_out(body: Node)
## FX hook (docs/stage3-fx-notes.md): the arena says what its hazard is doing and agent
## G4's FightFx decides what that looks and sounds like. Kinds: "spikes", "grinder",
## "flame", "pit", "ram", "disc".
signal hazard_fx(kind: String, active: bool, position: Vector3)

## Kept for the subclasses and for fight/test_arena.gd, which reads it. It is the YARD's
## half extent; anything that has to work at any size uses `_half` instead.
const HALF := FightTypes.ARENA_SIZE * 0.5
const FLOOR_THICKNESS := 0.4
const GRID_STEP := 1.0
const GRID_WIDTH := 0.015
const MARK_Y := 0.004

## Spike patch (The Yard's hazard, and one of the Coliseum's)
const SPIKE_PATCH := 1.6
const SPIKE_RISE := 0.25
const SPIKE_CYCLE_S := 6.0
const SPIKE_UP_S := 1.2
const SPIKE_TRAVEL_S := 0.25
## Spikes have no contact impulse of their own (they are an Area3D), so the hazard
## supplies one on a fixed cadence while it is risen.
const HAZARD_IMPULSE := 26.0
const HAZARD_PERIOD_TICKS := 15

## Grinder discs (The Grinder's flanks, and two of the Coliseum's)
const GRINDER_RADIUS := 0.55
const GRINDER_SPIN := 34.0              # rad/s, visual only
const GRINDER_IMPULSE := 30.0
## 2 Hz, not 6: MEASURED, a parked bot at 6 Hz lost five of its eleven condition points
## in under three seconds, which turns a graze into a fight. At 2 Hz a wheel held on the
## disc goes in about three seconds and a steel plate takes about sixteen, which is the
## same per-part rate as the Yard's spikes at their peak, only without the gaps.
const GRINDER_PERIOD_TICKS := 30

## Flame jets (the Furnace's walls, and the Coliseum's)
const FLAME_REACH := 2.5
const FLAME_RADIUS := 0.55
const FLAME_BURN_S := 2.0
const FLAME_IMPULSE := 30.0
const FLAME_PERIOD_TICKS := 30          # 2 Hz, retuned with the grinder for the same reason
const FLAME_DISRUPT_AFTER_S := 1.0
const FLAME_DISRUPT_S := 0.9

## Wave A (docs/wave-a-hazards-notes.md): the shared warning language's fixed lead. Every
## timed hazard's wind-up sound starts, and its telegraph reaches the same fast red pulse,
## exactly this long before it acts. 1.25 s = 75 ticks: a quarter second to see it, a
## quarter to turn, and the rest to drive a 3.5 m/s machine the metre out of the widest
## footprint (the Coliseum's 2 m spike patch), with a little to spare and not so much
## that the hazard stops being a threat.
const WARN_LEAD_S := 1.25
## The same lead in ticks, plus one so the warning is never a tick short (systems gauntlet
## A3/A4 measured "warned" as the clock running down through the last 1.2 s).
const WARN_LEAD_TICKS := 76
## Owner rule (2026-09-24): a warning must start at least as early as the AI can perceive
## the hazard. OpponentAI reads the spike clock up to its Masters tier's danger_s (1.5 s)
## plus HAZARD_LEAD_S (2.0 s) ahead, and starts leaving at SPIKE_AVOID_LEAD_S (2.4 s), so
## the spike patch arms 3.5 s out. Every other hazard the AI knows about either has an
## arena warning at least that long already (Drop Zone 3 s: the pit joins the AI's danger
## list only when that warning starts) or is on the AI's danger list at ALL times with no
## clock (jets, rams, grinders), which the telegraph's always-on idle outline matches.
## hazard_warning_test.gd re-derives all of this from opponent_ai.gd and fails if the AI
## ever gets a longer look than the player.
const SPIKE_WARN_S := 3.5
const TELEGRAPH_SCRIPT := "res://arena/hazard_telegraph.gd"

## Wave A material SLOTS. The materials lead is building new masters in
## res://assets/materials/ in parallel; when a file with one of these names lands, every
## hazard picks it up with no code change. Until then each slot falls back to the
## existing library (see _slot_material).
const SLOT_HAZARD_STEEL := "res://assets/materials/hazard_steel.tres"      # machined faces, shafts
const SLOT_HAZARD_DARK := "res://assets/materials/hazard_dark.tres"        # housings, wells, collars
const SLOT_HAZARD_CHROME := "res://assets/materials/hazard_chrome.tres"    # piston rods
const SLOT_HAZARD_PAINT := "res://assets/materials/hazard_paint.tres"      # safety-yellow paint

## Render meshes for the hazards (wave A). Preloaded by path, not by class_name, so a
## headless --script run parses this file before the class cache exists.
const HM := preload("res://arena/hazard_meshes.gd")

const COL_FLOOR := Color(0.55, 0.56, 0.58)
const COL_GRID := Color(0.30, 0.31, 0.33)
const COL_WALL := Color(0.35, 0.36, 0.39)
const COL_SPIKE := Color(0.66, 0.67, 0.70)
const COL_BG := Color(0.21, 0.24, 0.29)      # flat grey-blue, no sky

## Rendering (agent G1): the environment resource and the quality autoload.
const ENV_RESOURCE := "res://render/arena_env.tres"
const QUALITY_SCRIPT := "res://render/graphics_quality.gd"
const PROBE_HEIGHT := 5.0
const PROBE_ENABLED := true

## G2's PBR materials (docs/graphics-textures-notes.md). Every one is DUPLICATED on load,
## because the tiling, the tint and the metallic are this scene's, not the shared
## resource's, and a scene must never write back to a resource on disk.
const MAT_PLATE := "res://assets/materials/arena_plate.tres"
const MAT_CONCRETE := "res://assets/materials/concrete_dark.tres"
const MAT_STEEL := "res://assets/materials/brushed_steel.tres"
const MAT_TITANIUM := "res://assets/materials/scratched_titanium.tres"
const MAT_CHEVRON := "res://assets/materials/chevron.tres"

## Agent G4's three layer fire (docs/stage3-fx-notes.md). Loaded by path rather than by
## its class_name so a checkout without res://fx/ still builds every arena.
const FLAME_CONE_SCRIPT := "res://fx/flame_cone.gd"

## The floor and wall meshes are built by BotMeshes.flat_box_mesh(), which writes vertices
## and normals and NO UVs at all, so a textured material on them has to be triplanar.
## Triplanar scale is in metres: 0.4 is a 2.5 m tile.
const FLOOR_TILE := 0.4
const WALL_TILE := 0.5
const CHEVRON_REPEAT := 6.0

## Albedo multipliers on the duplicated materials, tuned against a 0.5 key and 0.18
## ambient (docs/graphics-render-notes.md). THESE ARE THE BRIGHTNESS DIALS.
const FLOOR_TINT := Color(1.0, 1.02, 1.06)
const WALL_TINT := Color(2.6, 2.62, 2.75)
const FLOOR_METALLIC := 0.35

# --- the per-arena profile. A subclass sets these in _configure(); build() reads them. --
var _arena_size := FightTypes.ARENA_SIZE
var _wall_height := FightTypes.WALL_HEIGHT
var _floor_mat := MAT_PLATE
var _wall_mat := MAT_CONCRETE
var _floor_tint := FLOOR_TINT
var _wall_tint := WALL_TINT
var _floor_metallic := FLOOR_METALLIC
var _floor_friction := 0.6
## Multiplies arena_env's ambient colour and the key light, so each arena reads at a
## glance without any of them leaving G1's exposure (docs/graphics-bar.md).
var _ambient_tint := Color(1.0, 1.0, 1.0)
var _ambient_energy_scale := 1.0
var _key_colour := Color(1.0, 0.98, 0.94)
var _key_energy := 0.5
var _fill_colour := Color(0.72, 0.82, 1.0)
var _fill_energy := 0.12
var _bg_tint := Color(1.0, 1.0, 1.0)
var _grid_enabled := true
var _chevron_caps := true
## Spawn corners, scaled to the arena when it is not 10 m.
var _spawn_inset := 1.8            # metres in from the wall, along both axes

var _half := FightTypes.ARENA_SIZE * 0.5

var spawn_player: Marker3D = null
var spawn_opponent: Marker3D = null

## The Yard's spike patch. Named this way because fight/test_arena.gd reaches for both.
var _spikes: Array[AnimatableBody3D] = []
var _spike_area: Area3D = null
var _spike_centre := Vector3.ZERO
var _spike_phase_ticks := 0
var _spikes_up := false

var _ooa: Area3D = null
var _ticks := 0
var _built := false

## Wave A: presentation handles the warning layer reads. Filled at build time only.
var _spike_extent := SPIKE_PATCH
var _spike_lamp_mat: StandardMaterial3D = null
var _kit_grinders: Array = []
var _kit_jets: Array = []
var _kit_tables: Array = []


func _ready() -> void:
	if not _built:
		build()


## Called by fight.gd with the shared RNG, FIRST in the fixed order of consumers, so the
## hazard phase is part of the seed and a replay lands on the same timeline.
func setup(rng: RandomNumberGenerator) -> void:
	if not _built:
		build()
	_ticks = 0
	_seed_hazards(rng)


## Subclass hook: draw every phase here, in a FIXED order, and nowhere else.
func _seed_hazards(rng: RandomNumberGenerator) -> void:
	if _spikes.is_empty():
		return
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	_spike_phase_ticks = rng.randi_range(0, cycle - 1) if rng != null else 0
	if rng != null:
		_spike_phase_ticks = warned_phase(_spike_phase_ticks, cycle,
			int(round(SPIKE_UP_S * FightTypes.TICK_HZ)))
	_set_spikes(0.0)


## The arena ticks through the 3 s countdown too (fight.gd runs physics from start_fight),
## so the first FIGHTING tick is arena tick 181, not 0. A3 is judged from there.
const FIGHT_START_TICKS := int(FightTypes.COUNTDOWN_S * FightTypes.TICK_HZ) + 1
## Ticks of slack either side of the fold, so a tick either way on the countdown's float
## clock cannot put the hazard back on the edge.
const PHASE_SLACK_TICKS := 2


## Systems gauntlet A3: a seeded phase could put a hazard in its active window as the fight
## starts (both Crush rams pressing at 0.0 s, the spikes up at 0.0 s) or have it fire with
## less than the shared warning after FIGHT. `phase` is t at arena tick 0 of a clock that is
## active while (ticks + phase) % cycle < active_ticks and next acts in cycle - t ticks. If,
## at the fight's first tick, it is acting or would act inside the shared warning, the
## phase is folded so that it is idle then with at least WARN_LEAD_TICKS to go; a legal
## one is returned unchanged, so most seeds keep the exact timeline they always had and no
## rng draw moves. (Anything it does during the countdown, the telegraph warns of as usual.)
static func warned_phase(phase: int, cycle: int, active_ticks: int,
		start: int = FIGHT_START_TICKS) -> int:
	var lo := maxi(active_ticks, 1) + PHASE_SLACK_TICKS
	var hi := cycle - WARN_LEAD_TICKS - PHASE_SLACK_TICKS
	if hi < lo:
		return phase
	var t := posmod(phase + start, cycle)
	if t >= lo and t <= hi:
		return phase
	return posmod(lo + posmod(t, hi - lo + 1) - start, cycle)


## Systems gauntlet A4: the endgame re-times a periodic hazard on the tick it lands. Given
## the tick now, the new cycle and the phase the arena would like, returns a phase that
## does not START an activation inside the shared warning. `was_active` is whether the
## hazard is acting on this tick under the OLD timing: an activation already under way was
## warned, so it may carry on (its progress is kept, clamped inside the new window).
static func endgame_phase(now: int, phase: int, cycle: int, active_ticks: int,
		was_active: bool, progress: int = 0) -> int:
	var t := posmod(now + phase, cycle)
	if was_active:
		var keep := clampi(progress, 0, maxi(active_ticks - 1, 0))
		return posmod(keep - now, cycle)
	if t >= active_ticks and cycle - t >= WARN_LEAD_TICKS:
		return phase
	# Next activation exactly WARN_LEAD_TICKS from now.
	return posmod(cycle - WARN_LEAD_TICKS - now, cycle)


func build() -> void:
	if _built:
		return
	_built = true
	_configure()
	_half = _arena_size * 0.5
	_build_environment()
	_build_floor()
	_build_markings()
	_build_walls()
	_build_hazards()
	_build_decor()
	_build_ooa()
	_build_markers()
	_build_telegraph()


## Wave A: the shared hazard warning layer. A child node that only reads
## hazard_schedule(); a checkout without the script builds every arena exactly as before.
func _build_telegraph() -> void:
	if not ResourceLoader.exists(TELEGRAPH_SCRIPT):
		return
	var script: GDScript = load(TELEGRAPH_SCRIPT) as GDScript
	if script == null:
		return
	var telegraph := script.new() as Node3D
	if telegraph == null:
		return
	telegraph.name = "HazardTelegraph"
	add_child(telegraph)


## Subclass hooks. `_configure` runs before anything is built; the rest add to it.
func _configure() -> void:
	pass


func _build_hazards() -> void:
	pass


func _build_decor() -> void:
	pass


func arena_size() -> float:
	return _arena_size


func arena_half_extent() -> float:
	return _half


func arena_id() -> String:
	return "yard"


# ---------------------------------------------------------------------------
# The endgame (brief v4 §2, docs/wave-g-contracts.md). At 2:00 fight.gd calls
# set_phase(FightTypes.PHASE_ENDGAME) and the arena turns nasty for the last minute.
#
# Two rules hold for every arena. The escalation LATCHES: an arena that has been to the
# endgame never goes back, which is what "the pit opens and never closes again" means and
# what stops a mid-fight pause or a re-send from letting the floor off. And the escalation
# is a function of the TICK, never of wall time, so a replay escalates on the tick the
# fight did; only the key-light shift below is on the frame clock, because it is paint.
# ---------------------------------------------------------------------------
## Everything timed goes twice as fast (a period halves, a speed doubles).
const ENDGAME_RATE := 2.0
## The key light goes from the arena's own cold key to this, over LIGHT_SHIFT_S. The
## colour is a multiplier on the arena's key colour, so each arena keeps its own cast.
const ENDGAME_KEY_TINT := Color(1.12, 0.84, 0.62)
const ENDGAME_KEY_ENERGY := 1.35
const LIGHT_SHIFT_S := 0.6

var _phase := FightTypes.PHASE_OPEN
var _escalated := false
## The tick the endgame's spike hold ("up and stays up") starts. A hazard the endgame turns
## ON gets the same warning as everything else (A4): the hold waits WARN_LEAD_TICKS after the
## endgame, or less when the patch's own cycle already warned of a rise sooner, or starts at
## once when the patch is already inside a (warned) up window, so it never drops between.
var _spike_hold_tick := 0
## -1 when no shift is running, otherwise seconds into the 0.6 s cross-fade.
var _light_shift_s := -1.0
var _key_from := Color(1.0, 1.0, 1.0)
var _key_from_energy := 0.0


## fight.gd's call at the endgame tick. Subclasses override `_on_phase`, never this.
func set_phase(phase: String) -> void:
	if _escalated:
		return
	if phase != FightTypes.PHASE_ENDGAME:
		_phase = phase
		return
	_phase = FightTypes.PHASE_ENDGAME
	_escalated = true
	_spike_hold_tick = _ticks + _spike_hold_delay()
	_begin_light_shift()
	_on_phase(FightTypes.PHASE_ENDGAME)


func phase() -> String:
	return _phase


## True once the arena has escalated, and true for the rest of the fight.
func escalated() -> bool:
	return _escalated


## Subclass hook: turn the hazards up. Called ONCE, on the endgame tick.
func _on_phase(_phase_name: String) -> void:
	pass


## A hazard period in ticks, halved for the endgame. Never below one tick.
func _hazard_ticks(period: int) -> int:
	if not _escalated:
		return period
	return maxi(1, int(round(float(period) / ENDGAME_RATE)))


func _begin_light_shift() -> void:
	var key := get_node_or_null("KeyLight") as DirectionalLight3D
	if key == null:
		return
	# Read the LIVE values: GraphicsQuality may already have pulled the energy down for
	# this tier, and the shift has to start from what the player is actually looking at.
	_key_from = key.light_color
	_key_from_energy = key.light_energy
	_light_shift_s = 0.0


## Paint only: the cold-to-hot key over 0.6 s. Nothing here touches the simulation, which
## is why it may live on the frame clock while every hazard above lives on the tick.
func _process(delta: float) -> void:
	# Wave A: turn each turntable's top at its body's own rate (doubled at the endgame
	# with it). Paint only: the body never moves, Jolt reads constant_angular_velocity.
	for table_variant in _kit_tables:
		var table: Dictionary = table_variant
		var body := table["body"] as StaticBody3D
		var spin := table["spin"] as Node3D
		if is_instance_valid(body) and is_instance_valid(spin):
			spin.rotate_y(body.constant_angular_velocity.y * delta)
	if _light_shift_s < 0.0:
		return
	var key := get_node_or_null("KeyLight") as DirectionalLight3D
	if key == null:
		_light_shift_s = -1.0
		return
	_light_shift_s += delta
	var t := clampf(_light_shift_s / LIGHT_SHIFT_S, 0.0, 1.0)
	key.light_color = _key_from.lerp(_tinted(_key_from, ENDGAME_KEY_TINT), t)
	key.light_energy = lerpf(_key_from_energy, _key_from_energy * ENDGAME_KEY_ENERGY, t)
	if t >= 1.0:
		_light_shift_s = -1.0


## 0 before the shift, 1 once the key light is fully hot. The headless test reads it.
func light_shift_progress() -> float:
	if not _escalated:
		return 0.0
	if _light_shift_s < 0.0:
		return 1.0
	return clampf(_light_shift_s / LIGHT_SHIFT_S, 0.0, 1.0)


# ---------------------------------------------------------------------------
# The AI's read of the danger. Every arena fills this in; fight.gd puts it in the
# OpponentAI context (see docs/stage5-arenas-notes.md for the diff).
# ---------------------------------------------------------------------------
func hazard_helpers() -> Dictionary:
	return {
		"next_danger_in_s": seconds_to_spike_rise(),
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
	}


func _danger_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not _spikes.is_empty() and (_spikes_up or seconds_to_spike_rise() < 1.5):
		out.append(_spike_centre)
	return out


## Somewhere to run to. The default is the four quadrant midpoints, minus any that sit
## within 1.5 m of a live danger, which is enough for a bot that just wants off a hazard.
func _safe_positions() -> Array[Vector3]:
	var r := _half * 0.55
	var candidates: Array[Vector3] = [
		Vector3(-r, 0.0, -r), Vector3(r, 0.0, -r),
		Vector3(r, 0.0, r), Vector3(-r, 0.0, r),
	]
	var danger := _danger_positions()
	var out: Array[Vector3] = []
	for c in candidates:
		var clear := true
		for d in danger:
			if Vector2(c.x - d.x, c.z - d.z).length() < 1.5:
				clear = false
				break
		if clear:
			out.append(c)
	if out.is_empty():
		out.append(Vector3.ZERO)
	return out


# ---------------------------------------------------------------------------
# The spike patch contract fight.gd and the AI already speak
# ---------------------------------------------------------------------------
func spikes_risen() -> bool:
	return _spikes_up


## The endgame's "up and stays up", once the shared warning has run.
func _spikes_held_up() -> bool:
	return _escalated and _ticks >= _spike_hold_tick


## Ticks from the endgame to the spike hold: 0 inside the cycle's up window, else the
## sooner of the cycle's own next rise and the shared warning.
func _spike_hold_delay() -> int:
	if _spikes.is_empty():
		return WARN_LEAD_TICKS
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	var t := (_ticks + _spike_phase_ticks) % cycle
	if t < int(round(SPIKE_UP_S * FightTypes.TICK_HZ)):
		return 0
	return mini(WARN_LEAD_TICKS, cycle - t)


## Ticks until the endgame hold puts the spikes up, or -1 when it is not pending.
func _spike_hold_in() -> int:
	if not _escalated or _spikes_held_up():
		return -1
	return _spike_hold_tick - _ticks


func seconds_to_spike_rise() -> float:
	if _spikes.is_empty():
		return 999.0
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	var t := (_ticks + _spike_phase_ticks) % cycle
	var in_ticks := cycle - t
	if _spike_hold_in() >= 0:
		in_ticks = mini(in_ticks, _spike_hold_in())
	return float(in_ticks) / float(FightTypes.TICK_HZ)


func spike_patch_centre() -> Vector3:
	return _spike_centre


# ---------------------------------------------------------------------------
# Wave A: the warning layer's read of the hazards (docs/wave-a-hazards-notes.md).
#
# READ-ONLY. Every value below is derived from the same tick counter and seeded phases
# the hazards run on, the way hazard_helpers() already is; nothing here writes a
# variable, moves a body or draws from an RNG. It may be called any number of times per
# frame, from _process, without changing the fight.
#
# One Dictionary per hazard:
#   id        String   stable per hazard ("spikes", "jet_north_0", "ram_west", ...)
#   kind      String   spikes | flame | ram | pit | grinder | turntable
#   group     String   hazards that fire together share one wind-up, light and strike
#   position  Vector3  floor centre of the footprint (y = 0)
#   size      Vector2  rect: x by z metres; disc: (diameter, 0); ring: (outer, inner) diam.
#   shape     String   rect | disc | ring
#   yaw       float    rect rotation about Y (0 for every hazard today)
#   in_s      float    seconds until it next acts; 0 while active; 999 for never
#   active    bool     acting now
#   warn_s    float    visual warning window, never less than WARN_LEAD_S
#   always_on bool     no clock (grinders, turntables): the telegraph uses proximity
#   contact   bool     always-on hazards: something is on it now
#   sound_at  Vector3  where the wind-up is heard (the nozzle, the ram, the patch)
#   lamps     Array    the hazard's own emissive materials, driven in the shared rhythm
# ---------------------------------------------------------------------------
const NEVER_S := 999.0


func hazard_schedule() -> Array:
	var out: Array = []
	if not _spikes.is_empty():
		# The phase the NEXT tick will run (the counter has already moved on): "active"
		# covers the whole stroke, rising and falling, so the telegraph never drops back
		# to idle for the quarter second the spikes take to come up.
		var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
		var t := (_ticks + _spike_phase_ticks) % cycle
		var active := _spikes_up or _spikes_held_up() \
			or t < int(round(SPIKE_UP_S * FightTypes.TICK_HZ))
		var in_ticks := cycle - t
		if _spike_hold_in() >= 0:
			in_ticks = mini(in_ticks, _spike_hold_in())
		out.append(_schedule_entry("spikes", "spikes", "spikes", _spike_centre,
			Vector2(_spike_extent, _spike_extent) + Vector2(0.24, 0.24), "rect",
			0.0 if active else float(in_ticks) / float(FightTypes.TICK_HZ), active,
			[_spike_lamp_mat] if _spike_lamp_mat != null else [], SPIKE_WARN_S))
	for i in range(_kit_grinders.size()):
		var g: Dictionary = _kit_grinders[i]
		var touching := bool(g["touching"])
		var e := _schedule_entry("grinder_%d" % i, "grinder", "grinder_%d" % i,
			g["centre"], Vector2((GRINDER_RADIUS + 0.62) * 2.0, (GRINDER_RADIUS + 0.14) * 2.0),
			"ring", 0.0, touching, g.get("lamps", []))
		e["always_on"] = true
		e["contact"] = touching
		out.append(e)
	for i in range(_kit_jets.size()):
		var jet: Dictionary = _kit_jets[i]
		var firing := bool(jet["firing"])
		var bank := str(jet.get("bank", "jet_%d" % i))
		var e := _schedule_entry("jet_%d" % i, "flame", bank, jet.get("zone_centre", jet["centre"]),
			jet.get("footprint", Vector2(FLAME_RADIUS * 2.0, FLAME_REACH)), "rect",
			0.0 if firing else _jet_seconds_to_fire(jet), firing, jet.get("lamps", []))
		e["yaw"] = float(jet.get("footprint_yaw", 0.0))
		e["sound_at"] = (jet["holder"] as Node3D).position if is_instance_valid(jet["holder"]) \
			else jet["centre"]
		out.append(e)
	for i in range(_kit_tables.size()):
		var table: Dictionary = _kit_tables[i]
		var e := _schedule_entry("table_%d" % i, "turntable", "table_%d" % i,
			table["centre"], Vector2(float(table["radius"]) * 2.0 + 0.5,
				float(table["radius"]) * 2.0 + 0.02), "ring", 0.0, false, table.get("lamps", []))
		e["always_on"] = true
		out.append(e)
	_schedule_extra(out)
	return out


## Subclass hook: append the arena's own hazards (pit, rams). Read-only, like the rest.
func _schedule_extra(_out: Array) -> void:
	pass


## Subclass hook: seconds until this jet next fires, from the arena's own clock. The base
## does not know a jet's timing, so a jet it cannot time is shown only while it burns.
func _jet_seconds_to_fire(_jet: Dictionary) -> float:
	return NEVER_S


func _schedule_entry(id: String, kind: String, group: String, position: Vector3,
		size: Vector2, shape: String, in_s: float, active: bool, lamps: Array = [],
		warn_s: float = WARN_LEAD_S) -> Dictionary:
	return {
		"id": id, "kind": kind, "group": group,
		"position": Vector3(position.x, 0.0, position.z),
		"size": size, "shape": shape, "yaw": 0.0,
		"in_s": in_s, "active": active, "warn_s": maxf(warn_s, WARN_LEAD_S),
		"always_on": false, "contact": false,
		"sound_at": Vector3(position.x, 0.3, position.z), "lamps": lamps,
	}


# ---------------------------------------------------------------------------
# Render setup (agent G1's pattern, docs/graphics-render-notes.md)
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	# The environment is a resource in res://render/ so the arenas and the App Store shots
	# cannot drift apart. It is DUPLICATED because GraphicsQuality turns features off on
	# the lower tiers, and a shared resource would carry that back to every other scene
	# (and, in the editor, to the file on disk). The per-arena tint is applied to the
	# duplicate, which is the only thing that makes six arenas read differently under one
	# exposure.
	var env: Environment = null
	if ResourceLoader.exists(ENV_RESOURCE):
		var loaded: Environment = load(ENV_RESOURCE) as Environment
		if loaded != null:
			env = loaded.duplicate() as Environment
	if env == null:
		# A checkout without res://render/ still builds a lit arena.
		env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = COL_BG
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.72, 0.78, 0.88)
		env.ambient_light_energy = 0.4
	env.ambient_light_color = _tinted(env.ambient_light_color, _ambient_tint)
	env.ambient_light_energy *= _ambient_energy_scale
	env.background_color = _tinted(env.background_color, _bg_tint)
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	# From the top left, matching the reference render's raking light.
	key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-135.0), 0.0)
	key.light_energy = _key_energy
	key.light_color = _key_colour
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 24.0
	key.shadow_normal_bias = 0.6
	key.shadow_bias = 0.04
	add_child(key)

	# A cold fill from the opposite side, no shadow: without it the shadowed faces of a
	# dark chassis go to the same value as the tyres and the silhouette closes up
	# (docs/stage2-art-direction.md: separate materials by VALUE).
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(48.0), 0.0)
	fill.light_energy = _fill_energy
	fill.light_color = _fill_colour
	fill.shadow_enabled = false
	add_child(fill)

	# One probe over the floor, baked once (UPDATE_ONCE): one render at the start of the
	# fight and nothing afterwards. Its box edge is outside the floor, so it cannot draw
	# a line on it.
	var probe := ReflectionProbe.new()
	probe.name = "FloorProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(_arena_size + 2.0, PROBE_HEIGHT, _arena_size + 2.0)
	probe.position = Vector3(0.0, PROBE_HEIGHT * 0.5 - 0.5, 0.0)
	probe.origin_offset = Vector3.ZERO
	probe.intensity = 0.6
	probe.blend_distance = 1.5
	probe.max_distance = 30.0
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(probe)

	_apply_quality(env, [key, fill])


func _tinted(base: Color, tint: Color) -> Color:
	return Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a)


## Push the current tier onto the environment and the lights. Lives here rather than in
## build() so a QA run can force a tier and call it again.
func _apply_quality(env: Environment, lights: Array) -> void:
	var script: GDScript = load(QUALITY_SCRIPT) as GDScript
	if script == null:
		return
	var quality: Node = script.call("resolve", self)
	if quality == null:
		return
	if quality.has_method("apply"):
		quality.call("apply", env, lights)
	# Hidden rather than freed on the low tier: the Compatibility renderer ignores
	# reflection probes anyway, and a node that is always there is one less thing for the
	# next agent to find missing.
	var probe := get_node_or_null("FloorProbe") as VisualInstance3D
	if probe != null:
		probe.visible = PROBE_ENABLED and bool(quality.call("allows", "reflection_probe"))


# ---------------------------------------------------------------------------
# Floor
# ---------------------------------------------------------------------------
func _build_floor() -> void:
	_add_floor_slab("Floor", Vector2.ZERO, Vector2(_arena_size, _arena_size))


## One floor slab. Subclasses that need a hole (the pit) or a separate surface (the
## conveyor) build several of these instead of calling the default _build_floor().
func _add_floor_slab(slab_name: String, centre: Vector2, size: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = _floor_friction
	pm.bounce = 0.0
	body.physics_material_override = pm
	body.position = Vector3(centre.x, -FLOOR_THICKNESS * 0.5, centre.y)

	var box_size := Vector3(size.x, FLOOR_THICKNESS, size.y)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = BotMeshes.flat_box_mesh(box_size)
	mi.material_override = _floor_material()
	body.add_child(mi)
	add_child(body)
	return body


func _floor_material() -> StandardMaterial3D:
	var mat := _textured(_floor_mat, _floor_tint, FLOOR_TILE, COL_FLOOR)
	mat.metallic = _floor_metallic
	return mat


func _wall_material() -> StandardMaterial3D:
	return _textured(_wall_mat, _wall_tint, WALL_TILE, COL_WALL)


# ---------------------------------------------------------------------------
# Floor markings. Every arena has its OWN scheme (brief §3: no copied floor markings);
# this is only the geometry kit they are drawn with.
# ---------------------------------------------------------------------------
func _build_markings() -> void:
	if not _grid_enabled:
		return
	var grid := MeshInstance3D.new()
	grid.name = "Grid"
	grid.mesh = _grid_mesh()
	grid.material_override = _flat(COL_GRID)
	grid.position = Vector3(0.0, 0.003, 0.0)
	add_child(grid)


## A subtle 1 m seam grid as one flat mesh of thin quads laid just over the floor.
func _grid_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var h := GRID_WIDTH * 0.5
	var n := int(_arena_size / GRID_STEP)
	for i in range(n + 1):
		var p := -_half + float(i) * GRID_STEP
		_quad(verts, norms, Vector3(p - h, 0, -_half), Vector3(p + h, 0, -_half),
			Vector3(p + h, 0, _half), Vector3(p - h, 0, _half))
		_quad(verts, norms, Vector3(-_half, 0, p - h), Vector3(-_half, 0, p + h),
			Vector3(_half, 0, p + h), Vector3(_half, 0, p - h))
	return _mesh_from(verts, norms)


## Add a flat marking mesh at MARK_Y. `colour` is emissive when `glow` is above zero, for
## the warning strips that have to read as lit rather than painted.
func _add_marking(mark_name: String, mesh: ArrayMesh, colour: Color,
		glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mark_name
	mi.mesh = mesh
	var mat := _flat(colour)
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = glow
	mi.material_override = mat
	mi.position = Vector3(0.0, MARK_Y, 0.0)
	add_child(mi)
	return mi


func _mesh_from(verts: PackedVector3Array, norms: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _mark_rect(verts: PackedVector3Array, norms: PackedVector3Array,
		centre: Vector2, size: Vector2) -> void:
	var h := size * 0.5
	_quad(verts, norms,
		Vector3(centre.x - h.x, 0, centre.y - h.y), Vector3(centre.x + h.x, 0, centre.y - h.y),
		Vector3(centre.x + h.x, 0, centre.y + h.y), Vector3(centre.x - h.x, 0, centre.y + h.y))


func _mark_line(verts: PackedVector3Array, norms: PackedVector3Array,
		a: Vector2, b: Vector2, width: float) -> void:
	var dir := (b - a)
	if dir.length() < 0.0001:
		return
	var n := Vector2(-dir.y, dir.x).normalized() * width * 0.5
	_quad(verts, norms,
		Vector3(a.x - n.x, 0, a.y - n.y), Vector3(a.x + n.x, 0, a.y + n.y),
		Vector3(b.x + n.x, 0, b.y + n.y), Vector3(b.x - n.x, 0, b.y - n.y))


func _mark_ring(verts: PackedVector3Array, norms: PackedVector3Array,
		centre: Vector2, radius: float, width: float, segments: int = 40,
		from_rad: float = 0.0, to_rad: float = TAU) -> void:
	var inner := radius - width * 0.5
	var outer := radius + width * 0.5
	for i in range(segments):
		var t0 := from_rad + (to_rad - from_rad) * float(i) / float(segments)
		var t1 := from_rad + (to_rad - from_rad) * float(i + 1) / float(segments)
		var a := centre + Vector2(cos(t0), sin(t0)) * inner
		var b := centre + Vector2(cos(t0), sin(t0)) * outer
		var c := centre + Vector2(cos(t1), sin(t1)) * outer
		var d := centre + Vector2(cos(t1), sin(t1)) * inner
		_quad(verts, norms, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y),
			Vector3(c.x, 0, c.y), Vector3(d.x, 0, d.y))


## A solid triangle marking, used for the Crush's floor chevrons.
func _mark_triangle(verts: PackedVector3Array, norms: PackedVector3Array,
		a: Vector2, b: Vector2, c: Vector2) -> void:
	var p0 := Vector3(a.x, 0, a.y)
	var p1 := Vector3(b.x, 0, b.y)
	var p2 := Vector3(c.x, 0, c.y)
	if (p1 - p0).cross(p2 - p0).dot(Vector3.UP) > 0.0:
		var s := p1
		p1 = p2
		p2 = s
	for p in [p0, p1, p2]:
		verts.append(p)
		norms.append(Vector3.UP)


func _quad(verts: PackedVector3Array, norms: PackedVector3Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0]
		var p1: Vector3 = tri[1]
		var p2: Vector3 = tri[2]
		if (p1 - p0).cross(p2 - p0).dot(Vector3.UP) > 0.0:
			var s := p1
			p1 = p2
			p2 = s
		verts.append(p0)
		verts.append(p1)
		verts.append(p2)
		for _i in range(3):
			norms.append(Vector3.UP)


# ---------------------------------------------------------------------------
# Walls
# ---------------------------------------------------------------------------
func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var t := FightTypes.WALL_THICKNESS
	var h := _wall_height
	var span := _arena_size + t
	var chevron := _chevron_strip_material()
	var layout := [
		{"name": "WallNorth", "pos": Vector3(0, h * 0.5, -_half), "size": Vector3(span, h, t)},
		{"name": "WallSouth", "pos": Vector3(0, h * 0.5, _half), "size": Vector3(span, h, t)},
		{"name": "WallWest", "pos": Vector3(-_half, h * 0.5, 0), "size": Vector3(t, h, span)},
		{"name": "WallEast", "pos": Vector3(_half, h * 0.5, 0), "size": Vector3(t, h, span)},
	]
	for entry_variant in layout:
		var entry: Dictionary = entry_variant
		var body := StaticBody3D.new()
		body.name = str(entry["name"])
		body.collision_layer = FightTypes.LAYER_ARENA
		body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
		body.position = entry["pos"]
		var size: Vector3 = entry["size"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = BotMeshes.flat_box_mesh(size)
		mi.material_override = _wall_material()
		body.add_child(mi)
		if _chevron_caps:
			# Yellow and black chevron strip capping the wall, as in the render.
			var strip := MeshInstance3D.new()
			strip.name = "Chevron"
			var strip_mesh := BoxMesh.new()
			strip_mesh.size = Vector3(size.x + 0.01, 0.06, size.z + 0.01)
			strip.mesh = strip_mesh
			strip.material_override = chevron
			strip.position = Vector3(0.0, size.y * 0.5, 0.0)
			body.add_child(strip)
		walls.add_child(body)


# ---------------------------------------------------------------------------
# Out of the arena: below y = OUT_OF_ARENA_Y, or outside the walls at any height, plus
# whatever extra volumes a subclass adds (the Drop Zone's pit).
# ---------------------------------------------------------------------------
func _build_ooa() -> void:
	_ooa = Area3D.new()
	_ooa.name = "OutOfArena"
	_ooa.collision_layer = FightTypes.LAYER_OOA
	_ooa.collision_mask = FightTypes.LAYER_BOT
	_ooa.monitoring = true
	var outside := _half + FightTypes.WALL_THICKNESS
	var far := 40.0
	var boxes := [
		{"size": Vector3(far * 2.0, 2.0, far * 2.0), "pos": Vector3(0, FightTypes.OUT_OF_ARENA_Y - 1.0, 0)},
		{"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(-outside - far * 0.5, 3.0, 0)},
		{"size": Vector3(far, 8.0, far * 2.0), "pos": Vector3(outside + far * 0.5, 3.0, 0)},
		{"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0, 3.0, -outside - far * 0.5)},
		{"size": Vector3(far * 2.0, 8.0, far), "pos": Vector3(0, 3.0, outside + far * 0.5)},
	]
	for extra_variant in _extra_ooa_volumes():
		boxes.append(extra_variant)
	for entry_variant in boxes:
		var entry: Dictionary = entry_variant
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry["size"]
		shape.shape = box
		shape.position = entry["pos"]
		_ooa.add_child(shape)
	_ooa.body_entered.connect(_on_ooa_body_entered)
	add_child(_ooa)


## Subclass hook: extra {"size": Vector3, "pos": Vector3} boxes for the OOA sensor.
func _extra_ooa_volumes() -> Array:
	return []


func _on_ooa_body_entered(body: Node3D) -> void:
	emit_signal("body_out", body)


# ---------------------------------------------------------------------------
# Spawns
# ---------------------------------------------------------------------------
func _build_markers() -> void:
	var p := spawn_position(0)
	var o := spawn_position(1)
	var player := Marker3D.new()
	player.name = "SpawnPlayer"
	player.position = p
	player.look_at_from_position(p, Vector3(o.x, p.y, o.z), Vector3.UP)
	add_child(player)
	spawn_player = player

	var opponent := Marker3D.new()
	opponent.name = "SpawnOpponent"
	opponent.position = o
	opponent.look_at_from_position(o, Vector3(p.x, o.y, p.z), Vector3.UP)
	add_child(opponent)
	spawn_opponent = opponent


func spawn_position(team_index: int) -> Vector3:
	if _arena_size == FightTypes.ARENA_SIZE:
		# The Yard's marks, unchanged: every existing test and replay depends on them.
		return FightTypes.SPAWN_PLAYER if team_index == 0 else FightTypes.SPAWN_OPPONENT
	var d := _half - _spawn_inset
	var y := FightTypes.SPAWN_PLAYER.y
	return Vector3(-d, y, -d) if team_index == 0 else Vector3(d, y, d)


## Spawn facings as world directions, so a Bot can be placed without caring which way a
## Marker3D's -Z points.
func spawn_facing(team_index: int) -> Vector3:
	var from := spawn_position(team_index)
	var to := spawn_position(1 - team_index)
	return (Vector3(to.x, 0.0, to.z) - Vector3(from.x, 0.0, from.z)).normalized()


# ---------------------------------------------------------------------------
# Hazard kit: the pieces more than one arena is built from
# ---------------------------------------------------------------------------
## A 3 x 3 patch of retracting spikes plus the Area3D that does the damage while they are
## up. Fills `_spikes` / `_spike_area`, which fight/test_arena.gd reaches for.
func _add_spike_patch(centre: Vector3, extent: float = SPIKE_PATCH) -> void:
	_spike_centre = Vector3(centre.x, 0.0, centre.z)
	_spike_extent = extent
	var patch := Node3D.new()
	patch.name = "SpikePatch"
	patch.position = _spike_centre
	add_child(patch)
	var step := extent / 3.0
	# Wave A: a real spike (collar, shaft, point) instead of a six-sided grey cone, and a
	# bezel with bored holes and lamp dashes so the patch is a machine, not a paint mark.
	# Render only: the CylinderShape3D below is exactly the one it always was.
	var spike_mesh: Mesh = HM.spike([_hazard_mat("dark"), _hazard_mat("steel")])
	_spike_lamp_mat = _lamp(Color(0.95, 0.56, 0.10), 0.4)
	for gx in range(3):
		for gz in range(3):
			var body := AnimatableBody3D.new()
			body.name = "Spike%d%d" % [gx, gz]
			body.sync_to_physics = false
			body.collision_layer = FightTypes.LAYER_HAZARD
			body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
			body.add_to_group("arena_hazard")
			body.position = Vector3((float(gx) - 1.0) * step, -0.2, (float(gz) - 1.0) * step)
			var shape := CollisionShape3D.new()
			var cone := CylinderShape3D.new()
			cone.radius = 0.06
			cone.height = 0.34
			shape.shape = cone
			body.add_child(shape)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = spike_mesh
			body.add_child(mi)
			patch.add_child(body)
			_spikes.append(body)

	# The risen spike tips stand at 0.42 m (body at 0.25, cylinder 0.34 tall), so the area
	# reaches 0.52: a machine RESTING on the tips is inside it. At 0.34 it only caught a
	# machine on the ticks it was being thrown up, so whether a parked bot was hurt came
	# down to the 15-tick damage cadence (arenas_test, Coliseum seed 59: 11.0 -> 11.0).
	_spike_area = _make_hazard_area("SpikeHazard",
		_box_shape(Vector3(extent, 0.52, extent), Vector3(0.0, 0.26, 0.0)), patch)
	_set_spikes(0.0)
	# Added after every body and area, so the tree order the physics sees is unchanged.
	var bezel := MeshInstance3D.new()
	bezel.name = "Bezel"
	bezel.mesh = HM.spike_bezel(extent, [_hazard_mat("dark"), _flat(Color(0.02, 0.02, 0.025)),
		_hazard_mat("paint"), _spike_lamp_mat])
	patch.add_child(bezel)


## The spike tick. Arenas with a patch call this from _physics_process.
func _tick_spikes() -> void:
	if _spikes.is_empty():
		return
	var cycle := int(round(SPIKE_CYCLE_S * FightTypes.TICK_HZ))
	var up_ticks := int(round(SPIKE_UP_S * FightTypes.TICK_HZ))
	var travel := int(round(SPIKE_TRAVEL_S * FightTypes.TICK_HZ))
	var t := (_ticks + _spike_phase_ticks) % cycle

	var height := 0.0
	if t < up_ticks:
		if t < travel:
			height = float(t) / float(travel)
		elif t > up_ticks - travel:
			height = float(up_ticks - t) / float(travel)
		else:
			height = 1.0
	# brief v4 §2, the Yard's endgame (and the Coliseum's): the patch comes up and STAYS
	# up for the rest of the fight. The cycle above keeps running underneath so nothing
	# else about the timeline moves; only the height it resolves to changes.
	if _spikes_held_up():
		height = maxf(height, 1.0)
	_set_spikes(clampf(height, 0.0, 1.0))

	var risen := height > 0.6
	if risen != _spikes_up:
		_spikes_up = risen
		if _spike_area != null:
			_spike_area.monitoring = risen
		emit_signal("hazard_fx", "spikes", risen, _spike_centre)
	# `_ticks + 1`, not `_ticks`: Stage 3's yard.gd incremented the counter in the middle
	# of this function and tested the INCREMENTED value, and the subclasses here increment
	# after the whole tick instead. Reproducing the old cadence exactly keeps the Yard's
	# simulation bit-identical to the one every Stage 3 and 4 test was tuned against; a
	# one tick shift is invisible on its own but a fight is chaotic and the outcome is not.
	if _spikes_up and (_ticks + 1) % HAZARD_PERIOD_TICKS == 0:
		_damage_overlaps(_spike_area, HAZARD_IMPULSE)


func _set_spikes(amount: float) -> void:
	var y := -0.2 + amount * (SPIKE_RISE + 0.2)
	for spike in _spikes:
		if is_instance_valid(spike):
			spike.position.y = y


## One floor-mounted angle grinder: a disc flush with the floor, a spark emitter and the
## Area3D that cuts anything sitting on it. Returns the handle dictionary the owner ticks.
func _add_grinder(centre: Vector3, grinder_name: String) -> Dictionary:
	var holder := Node3D.new()
	holder.name = grinder_name
	holder.position = Vector3(centre.x, 0.0, centre.z)
	add_child(holder)

	# The well the disc sits in, so it reads as mounted THROUGH the floor. Wave A: a dark
	# well, a raised safety-yellow collar and a ring of lamp dashes the warning layer
	# drives (they warm and pulse as a machine closes in).
	var lamp := _lamp(Color(0.95, 0.56, 0.10), 0.4)
	var well := MeshInstance3D.new()
	well.name = "Well"
	well.mesh = HM.grinder_well(GRINDER_RADIUS, [_hazard_mat("dark"), _hazard_mat("paint"), lamp])
	well.position = Vector3(0.0, 0.0, 0.0)
	holder.add_child(well)

	# The disc itself. It is a spinning MeshInstance3D, not a body: a body spinning at
	# 34 rad/s inside the floor is a solver problem and buys nothing, because the cut is
	# an Area3D either way. Wave A: a machined dish with 24 teeth, relief slots and a
	# bolted hub instead of a flat 18-sided cylinder, and NOT a mirror: at metallic 0.85
	# it reflected the empty sky and read as a black hole from the fight camera.
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = HM.grinder_disc(GRINDER_RADIUS, [_hazard_mat("disc"), _hazard_mat("dark"),
		_hazard_mat("steel")])
	disc.position = Vector3(0.0, 0.022, 0.0)
	holder.add_child(disc)

	var area := _make_hazard_area("Cut",
		_cylinder_shape(GRINDER_RADIUS + 0.08, 0.26, Vector3(0.0, 0.13, 0.0)), holder)
	area.monitoring = true

	var sparks := _spark_emitter(Vector3(0.0, 0.06, 0.0))
	holder.add_child(sparks)

	# Wave A, presentation only: a blur card over the disc (concentric streaks, so it
	# reads as spinning at any frame rate instead of strobing), and a constant trickle of
	# sparks off the cutting edge so an idle grinder looks like a running machine.
	var blur := MeshInstance3D.new()
	blur.name = "SpinBlur"
	var blur_mesh := PlaneMesh.new()
	blur_mesh.size = Vector2(GRINDER_RADIUS * 2.0 + 0.08, GRINDER_RADIUS * 2.0 + 0.08)
	blur.mesh = blur_mesh
	blur.material_override = _spin_blur_material()
	blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blur.position = Vector3(0.0, 0.052, 0.0)
	holder.add_child(blur)
	var idle := _spark_emitter(Vector3(GRINDER_RADIUS * 0.96, 0.05, 0.0))
	idle.name = "IdleSparks"
	idle.amount = 10
	idle.lifetime = 0.35
	var idle_mat := (idle.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	idle_mat.direction = Vector3(0.0, 0.35, -1.0)
	idle_mat.spread = 20.0
	idle_mat.initial_velocity_min = 1.2
	idle_mat.initial_velocity_max = 2.6
	idle_mat.scale_min = 0.25
	idle_mat.scale_max = 0.6
	idle.process_material = idle_mat
	idle.emitting = true
	holder.add_child(idle)

	var g := {"holder": holder, "disc": disc, "area": area, "sparks": sparks,
		"centre": Vector3(centre.x, 0.0, centre.z), "touching": false, "lamps": [lamp]}
	_kit_grinders.append(g)
	return g


## Spin the disc and cut whatever is on it. Two-way by construction: the Area3D does not
## know or care which bot the part belongs to.
func _tick_grinder(g: Dictionary, delta: float) -> void:
	var disc := g["disc"] as MeshInstance3D
	if is_instance_valid(disc):
		# brief v4 §2: at the endgame the discs spin up and bite twice as often.
		disc.rotate_y(GRINDER_SPIN * delta * (ENDGAME_RATE if _escalated else 1.0))
	var area := g["area"] as Area3D
	var touching := _area_has_part(area)
	if touching != bool(g["touching"]):
		g["touching"] = touching
		var sparks := g["sparks"] as GPUParticles3D
		if is_instance_valid(sparks):
			sparks.emitting = touching
		emit_signal("hazard_fx", "grinder", touching, g["centre"])
	if touching and _ticks % _hazard_ticks(GRINDER_PERIOD_TICKS) == 0:
		_damage_overlaps(area, GRINDER_IMPULSE)


## The grinders' bite, in ticks between hits: 30 in the open phase, 15 in the endgame.
## The Grinder and the Coliseum both read it, and so does arenas_test.
func grinder_period_ticks() -> int:
	return _hazard_ticks(GRINDER_PERIOD_TICKS)


## A wall flame jet. `origin` is on the wall face, `direction` points into the arena.
func _add_flame_jet(origin: Vector3, direction: Vector3, jet_name: String) -> Dictionary:
	var dir := Vector3(direction.x, 0.0, direction.z).normalized()
	var holder := Node3D.new()
	holder.name = jet_name
	holder.position = origin
	holder.look_at_from_position(origin, origin + dir, Vector3.UP)
	add_child(holder)

	# The nozzle. Wave A: a housing bolted to the wall, a lathed barrel, a bezel at the
	# mouth that the warning layer heats from amber to red in the shared rhythm, and a
	# fuel line up the wall. Render only; the burn volume below is unchanged.
	var bezel_lamp := _lamp(Color(0.95, 0.56, 0.10), 0.3)
	var nozzle := MeshInstance3D.new()
	nozzle.name = "Nozzle"
	nozzle.mesh = HM.flame_nozzle(_wall_height - origin.y, [_hazard_mat("dark"),
		_hazard_mat("steel"), bezel_lamp, _hazard_mat("steel")])
	holder.add_child(nozzle)

	# The fire itself is agent G4's FlameCone (res://fx/flame_cone.gd): additive particles
	# on an authored billboard, a haze glow and a flickering light, already built for the
	# flamethrower weapon and already tested. It fires along its own local +X, so it hangs
	# off a mount yawed 90 degrees to put +X on this jet's -Z.
	var flame: Node3D = null
	var mount := Node3D.new()
	mount.name = "FlameMount"
	mount.rotation = Vector3(0.0, PI * 0.5, 0.0)
	holder.add_child(mount)
	if ResourceLoader.exists(FLAME_CONE_SCRIPT):
		var script: GDScript = load(FLAME_CONE_SCRIPT) as GDScript
		if script != null:
			flame = script.new() as Node3D
	if flame != null:
		flame.name = "Flame"
		# Driven from the physics tick below rather than from _process, so the flicker is
		# part of the seeded timeline and a replay looks like its fight.
		flame.set("external_clock", true)
		mount.add_child(flame)
		flame.call("set_length", FLAME_REACH)
		flame.call("set_active", false)

	# The fallback fire, for a checkout without res://fx/: a plain emissive cone, a light
	# and one particle emitter. Hidden until the jet fires, and not built at all when the
	# real FlameCone is there.
	var cone: MeshInstance3D = null
	var light: OmniLight3D = null
	var flame_particles: GPUParticles3D = null
	if flame == null:
		cone = MeshInstance3D.new()
		cone.name = "Flame"
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = FLAME_RADIUS
		cone_mesh.bottom_radius = 0.08
		cone_mesh.height = FLAME_REACH
		cone_mesh.radial_segments = 10
		cone.mesh = cone_mesh
		cone.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		cone.position = Vector3(0.0, 0.0, -FLAME_REACH * 0.5 - 0.2)
		var flame_mat := StandardMaterial3D.new()
		flame_mat.albedo_color = Color(1.0, 0.55, 0.16, 0.55)
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.emission_enabled = true
		flame_mat.emission = Color(1.0, 0.52, 0.14)
		flame_mat.emission_energy_multiplier = 3.5
		flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material_override = flame_mat
		cone.visible = false
		holder.add_child(cone)

		light = OmniLight3D.new()
		light.name = "FlameLight"
		light.light_color = Color(1.0, 0.58, 0.22)
		light.light_energy = 3.0
		light.omni_range = 4.0
		light.shadow_enabled = false
		light.position = Vector3(0.0, 0.25, -1.0)
		light.visible = false
		holder.add_child(light)

		flame_particles = _flame_emitter(Vector3(0.0, 0.0, -0.3))
		holder.add_child(flame_particles)

	# The burn volume: a box along the jet, which is a cheap and honest stand-in for the
	# cone, because the flame's damage is time based and not shaped.
	var area := _make_hazard_area("Burn",
		_box_shape(Vector3(FLAME_RADIUS * 2.0, 0.7, FLAME_REACH),
			Vector3(0.0, 0.25, -FLAME_REACH * 0.5 - 0.2)), holder)
	area.monitoring = false

	var jet := {"holder": holder, "flame": flame, "cone": cone, "light": light, "area": area,
		"particles": flame_particles, "firing": false,
		"centre": origin + dir * (FLAME_REACH * 0.5), "exposure": {},
		# Wave A, read by hazard_schedule() only. The burn box is FLAME_RADIUS * 2 wide and
		# FLAME_REACH long, starting 0.2 m off the wall.
		"footprint": Vector2(FLAME_RADIUS * 2.0, FLAME_REACH) if absf(dir.z) >= absf(dir.x)
			else Vector2(FLAME_REACH, FLAME_RADIUS * 2.0),
		"lamps": [bezel_lamp]}
	jet["zone_centre"] = origin + dir * (FLAME_REACH * 0.5 + 0.2)
	_kit_jets.append(jet)
	return jet


## Fire or stop one jet, and burn what is in it. `exposure` counts consecutive seconds per
## bot so the drive disruption only lands after a full second in the flame.
func _tick_flame_jet(jet: Dictionary, firing: bool) -> void:
	var flame := jet["flame"] as Node3D
	if is_instance_valid(flame):
		# Stepped every tick, firing or not: FlameCone keeps its own clock and the
		# particles already in the air have to finish after the jet shuts off.
		flame.call("step", 1.0 / float(FightTypes.TICK_HZ))
	if firing != bool(jet["firing"]):
		jet["firing"] = firing
		if is_instance_valid(flame):
			flame.call("set_active", firing)
		var cone := jet["cone"] as MeshInstance3D
		if is_instance_valid(cone):
			cone.visible = firing
		var light := jet["light"] as OmniLight3D
		if is_instance_valid(light):
			light.visible = firing
		(jet["area"] as Area3D).monitoring = firing
		var particles := jet["particles"] as GPUParticles3D
		if is_instance_valid(particles):
			particles.emitting = firing
		if not firing:
			(jet["exposure"] as Dictionary).clear()
		emit_signal("hazard_fx", "flame", firing, jet["centre"])
	if not firing:
		return
	var area := jet["area"] as Area3D
	var exposure: Dictionary = jet["exposure"]
	var seen := {}
	for bot in _bots_in_area(area):
		var id: int = bot.get_instance_id()
		seen[id] = true
		var t := float(exposure.get(id, 0.0)) + 1.0 / float(FightTypes.TICK_HZ)
		exposure[id] = t
		if t >= FLAME_DISRUPT_AFTER_S and bot.has_method("disrupt"):
			bot.call("disrupt", "drive", FLAME_DISRUPT_S)
	for id_variant in exposure.keys():
		if not seen.has(id_variant):
			exposure.erase(id_variant)
	if _ticks % FLAME_PERIOD_TICKS == 0:
		_damage_overlaps(area, FLAME_IMPULSE)


## A turntable: a static disc that carries whatever stands on it round with it. Jolt
## honours `constant_angular_velocity` on a StaticBody3D (measured, see the notes).
func _add_turntable(centre: Vector3, radius: float, rate: float,
		table_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = table_name
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	# The top face stands 0.04 m PROUD of the floor. It used to be flush, and that was a
	# silent bug: the floor slab is one box under the whole arena, so a flush disc is
	# coplanar with it and the solver rests the bot on the static floor instead. Measured:
	# a bot on a flush disc swept 0.15 rad in three seconds, a bot on a proud one sweeps
	# the full 1.8. Four centimetres is well under the 0.11 m wheel radius, so it is a
	# lip to drive over, not a step to climb.
	body.position = Vector3(centre.x, -0.01, centre.z)
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	body.physics_material_override = pm
	body.constant_angular_velocity = Vector3(0.0, rate, 0.0)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.1
	shape.shape = cyl
	body.add_child(shape)

	# Wave A: the white disc was MAT_STEEL at 1.5x albedo. Now a darker machined plate
	# under a separate top (plate, painted edge band, direction arrows, rim lamps) that
	# turns as presentation in _process at the body's own rate, so the rotation the
	# player's machine feels is finally visible. The body itself never moves (Jolt reads
	# constant_angular_velocity), and its CylinderShape3D is unchanged.
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.1
	mesh.radial_segments = 48
	mi.mesh = mesh
	mi.material_override = _hazard_mat("dark")
	body.add_child(mi)

	var spin := Node3D.new()
	spin.name = "Spin"
	body.add_child(spin)
	var rim_lamp := _lamp(Color(0.95, 0.56, 0.10), 0.3)
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = HM.turntable_top(radius, rate < 0.0, [_hazard_mat("plate"), _hazard_mat("paint"),
		rim_lamp])
	spin.add_child(top)

	add_child(body)
	_kit_tables.append({"body": body, "spin": spin, "centre": Vector3(centre.x, 0.0, centre.z),
		"radius": radius, "lamps": [rim_lamp]})
	return body


# ---------------------------------------------------------------------------
# Hazard plumbing
# ---------------------------------------------------------------------------
func _make_hazard_area(area_name: String, shape: CollisionShape3D, parent: Node) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.collision_layer = FightTypes.LAYER_HAZARD
	area.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	area.monitoring = false
	area.add_to_group("arena_hazard")
	area.add_child(shape)
	parent.add_child(area)
	return area


func _box_shape(size: Vector3, offset: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	return shape


func _cylinder_shape(radius: float, height: float, offset: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position = offset
	return shape


## Every damaging hazard goes through here, so "two-way" is not a promise, it is the only
## code path there is: the area reports parts, and each part is told off to its own bot.
func _damage_overlaps(area: Area3D, impulse: float) -> void:
	if area == null or not is_instance_valid(area) or not area.monitoring:
		return
	for body in area.get_overlapping_bodies():
		if body is BotPart:
			var part: BotPart = body
			if part.detached or part.owner_bot == null:
				continue
			part.owner_bot.hazard_hit(part, impulse, part.global_position)


func _area_has_part(area: Area3D) -> bool:
	if area == null or not is_instance_valid(area) or not area.monitoring:
		return false
	for body in area.get_overlapping_bodies():
		if body is BotPart and not (body as BotPart).detached:
			return true
	return false


## The distinct Bots with a part inside this area.
func _bots_in_area(area: Area3D) -> Array:
	var out: Array = []
	if area == null or not is_instance_valid(area) or not area.monitoring:
		return out
	for body in area.get_overlapping_bodies():
		if not (body is BotPart):
			continue
		var part: BotPart = body
		if part.detached or part.owner_bot == null:
			continue
		if not out.has(part.owner_bot):
			out.append(part.owner_bot)
	return out


## The chassis parts inside an area, for a hazard that hits the TOP face rather than
## whatever plate happened to be nearest (the Crush).
func _crush_bots_in_area(area: Area3D, amount: float) -> void:
	if area == null or not is_instance_valid(area) or not area.monitoring:
		return
	for body in area.get_overlapping_bodies():
		if not (body is BotPart):
			continue
		var part: BotPart = body
		if part.detached or part.owner_bot == null or part.part_kind != "chassis":
			continue
		# take_direct_damage maps a chassis hit onto armour_top while the top plate is
		# there, and onto the core once it is gone: exactly a flattening.
		part.owner_bot.call("take_direct_damage", part, amount, "hazard", "arena")


# ---------------------------------------------------------------------------
# Particles (simple GPUParticles3D; agent G4 may replace them wholesale)
# ---------------------------------------------------------------------------
func _spark_emitter(offset: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.position = offset
	p.amount = 48
	p.lifetime = 0.45
	p.emitting = false
	p.explosiveness = 0.0
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.6, 0.0)
	mat.spread = 55.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0.0, -11.0, 0.0)
	mat.scale_min = 0.35
	mat.scale_max = 0.9
	mat.color = Color(1.0, 0.72, 0.28)
	p.process_material = mat
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.035)
	p.draw_pass_1 = mesh
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(1.0, 0.78, 0.35)
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.7, 0.25)
	draw_mat.emission_energy_multiplier = 4.0
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true
	mesh.material = draw_mat
	return p


func _flame_emitter(offset: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "FlameParticles"
	p.position = offset
	p.amount = 60
	p.lifetime = 0.5
	p.emitting = false
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	# -Z is the jet's forward, and the emitter is parented to the jet holder.
	mat.direction = Vector3(0.0, 0.0, -1.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0.0, 1.2, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.6
	mat.color = Color(1.0, 0.6, 0.2)
	p.process_material = mat
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.22, 0.22)
	p.draw_pass_1 = mesh
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.albedo_color = Color(1.0, 0.55, 0.2, 0.7)
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.5, 0.16)
	draw_mat.emission_energy_multiplier = 3.0
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = draw_mat
	return p


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------
## Load one of G2's materials, duplicate it, and make it fit a mesh with no UVs. Falls
## back to a flat colour when the resource is missing, so a checkout without
## assets/materials still builds a readable arena.
func _textured(path: String, tint: Color, tile: float, fallback: Color) -> StandardMaterial3D:
	if not ResourceLoader.exists(path):
		return _flat(fallback)
	var loaded: StandardMaterial3D = load(path) as StandardMaterial3D
	if loaded == null:
		return _flat(fallback)
	var mat: StandardMaterial3D = loaded.duplicate() as StandardMaterial3D
	mat.albedo_color = tint
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(tile, tile, tile)
	# Blend sharpness: high enough that the floor's top face does not smear its scratches
	# up the 0.4 m lip of the slab it is cut from.
	mat.uv1_triplanar_sharpness = 8.0
	return mat


## The chevron strip. A BoxMesh HAS UVs, so this one maps normally and only needs the
## repeat count along the wall.
func _chevron_strip_material() -> StandardMaterial3D:
	if not ResourceLoader.exists(MAT_CHEVRON):
		return _chevron_material()
	var loaded: StandardMaterial3D = load(MAT_CHEVRON) as StandardMaterial3D
	if loaded == null:
		return _chevron_material()
	var mat: StandardMaterial3D = loaded.duplicate() as StandardMaterial3D
	mat.uv1_scale = Vector3(CHEVRON_REPEAT, 1.0, 1.0)
	return mat


## Procedural fallback chevron, for a checkout without assets/textures.
func _chevron_material() -> StandardMaterial3D:
	var w := 32
	var img := Image.create(w, 8, false, Image.FORMAT_RGB8)
	var yellow := Color(0.93, 0.76, 0.13)
	var black := Color(0.10, 0.10, 0.11)
	for y in range(8):
		for x in range(w):
			# A diagonal band makes the chevron read from the isometric camera.
			var v := (x + y) % 16
			img.set_pixel(x, y, yellow if v < 8 else black)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(24.0, 1.0, 1.0)
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


## Wave A: the hazard material SLOTS (see the SLOT_ constants). A slot file from the
## materials lead wins; until it exists, each falls back to the current library, tuned so
## nothing blows out to white or sinks to black at the fight camera.
var _hazard_mats: Dictionary = {}


func _hazard_mat(slot: String) -> Material:
	if _hazard_mats.has(slot):
		return _hazard_mats[slot]
	var path := ""
	match slot:
		"steel", "disc", "plate":
			path = SLOT_HAZARD_STEEL
		"dark", "ram":
			path = SLOT_HAZARD_DARK
		"chrome":
			path = SLOT_HAZARD_CHROME
		"paint":
			path = SLOT_HAZARD_PAINT
	var mat: Material = null
	if path != "" and ResourceLoader.exists(path):
		var loaded := load(path) as Material
		if loaded != null:
			mat = loaded.duplicate() as Material
	if mat == null:
		mat = _hazard_fallback(slot)
	_hazard_mats[slot] = mat
	return mat


func _hazard_fallback(slot: String) -> Material:
	match slot:
		"steel", "disc", "plate":
			# Brushed steel on the mesh's own metre UVs. Metallic held well under 1: this
			# arena has no sky to reflect, and a true mirror reads as black from above.
			var mat := _flat(Color(0.62, 0.64, 0.68))
			if ResourceLoader.exists(MAT_STEEL):
				var loaded := load(MAT_STEEL) as StandardMaterial3D
				if loaded != null:
					mat = loaded.duplicate() as StandardMaterial3D
			var tint := {"steel": Color(1.05, 1.06, 1.1), "disc": Color(0.98, 1.0, 1.04),
				"plate": Color(0.72, 0.74, 0.78)}
			mat.albedo_color = tint[slot]
			mat.uv1_triplanar = false
			mat.uv1_scale = Vector3(1.6, 1.6, 1.0)
			mat.metallic = 0.55 if slot != "plate" else 0.45
			mat.roughness = 0.55 if slot == "plate" else 0.42
			return mat
		"dark":
			var mat := _flat(Color(0.2, 0.205, 0.22))
			mat.metallic = 0.35
			mat.roughness = 0.5
			return mat
		"ram":
			# Painted machine grey-blue: dark enough that the striped face and the chrome
			# rods carry the read, light enough not to be a hole in the floor.
			var mat := _flat(Color(0.38, 0.41, 0.46))
			mat.metallic = 0.15
			mat.roughness = 0.42
			return mat
		"chrome":
			var mat := _flat(Color(0.82, 0.84, 0.88))
			mat.metallic = 0.9
			mat.roughness = 0.14
			return mat
		"paint":
			var mat := _flat(Color(0.86, 0.62, 0.07))
			mat.roughness = 0.62
			return mat
	return _flat(Color(0.5, 0.5, 0.5))


## The grinder's spin-blur card: concentric streaks (a function of radius only), so the
## card looks the same at every angle and the eye reads it as motion blur, not a pattern.
static var _blur_shader: Shader = null


func _spin_blur_material() -> ShaderMaterial:
	if _blur_shader == null:
		_blur_shader = Shader.new()
		_blur_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float radius = 0.55;
varying vec2 xz;
void vertex() { xz = VERTEX.xz; }
float h(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void fragment() {
	float r = length(xz);
	float inside = 1.0 - smoothstep(radius - 0.01, radius + 0.03, r);
	float hub = smoothstep(0.14, 0.2, r);
	float band = floor(r * 90.0);
	float streak = mix(0.25, 1.0, h(band)) * (0.6 + 0.4 * sin(r * 211.0));
	float rim = exp(-abs(r - radius + 0.015) / 0.012) * 0.8;
	ALBEDO = vec3(0.55, 0.58, 0.62) * (streak * 0.12 * hub + rim * 0.6) * inside;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _blur_shader
	mat.set_shader_parameter("radius", GRINDER_RADIUS)
	return mat


func _flat(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


## An emissive warning lamp material, shared by every arena's warning strip.
func _lamp(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.4
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	return mat
