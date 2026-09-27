class_name GrinderArena extends ArenaBase
## The Grinder (brief §7 arena 2, docs/stage5-spec.md §3): two floor-mounted angle
## grinders on the flanks, discs flush with the floor, low walls. The free tier's second
## arena and the one the tutorial graduates into, so the hazard is ALWAYS on and always
## visible: nothing to time, only somewhere not to be.
##
##   FLOOR PLAN (10 x 10 m, north is -Z, the camera looks down the +X +Z diagonal)
##
##     -5                    0                    +5
##   -5 +-------------------------------------------+
##      |  P                        .-.             |   P  player spawn (-3.2, -3.2)
##      |                          ( G )            |   G  grinder, disc r = 0.55
##      |                           `-'             |   .  cut-lane arcs (floor paint)
##    0 |              \  cut lane  /               |
##      |               \          /                |
##      |             .-.                           |
##      |            ( G )                        O |   O  opponent spawn (3.2, 3.2)
##   +5 +-------------------------------------------+
##
## The two grinders sit at (-3.3, 0, +1.1) and (+3.3, 0, -1.1): a 180 degree rotation of
## each other about the centre, so each spawn is exactly 2.1 m from the NEAREST grinder
## and the layout is identical for both bots. They are ON the flanks and OFF the diagonal
## the bots charge along, so a grinder is something you push someone into, never something
## the opening drive lands you on.
##
## Marking scheme (original, brief §3: no copied floor markings): a painted keep-out ring
## around each grinder, a long cut lane bar running from each grinder toward the centre,
## and a plain centre cross. No grid: the rings ARE the read.

const GRINDER_A := Vector3(-3.3, 0.0, 1.1)
const GRINDER_B := Vector3(3.3, 0.0, -1.1)
## Cold steel: a shop floor, not a scrapyard.
const TINT_FLOOR := Color(0.94, 0.98, 1.08)
## Wave A: 2.3 to 2.6 blew the steel walls out to white (arenas.md §2.2 gap 3). The
## lighting does the work now; a cold blue-grey cast keeps the machine-shop read.
const TINT_WALL := Color(1.22, 1.3, 1.46)
const COL_KEEPOUT := Color(0.86, 0.71, 0.14)
const COL_LANE := Color(0.24, 0.25, 0.28)

var _grinders: Array = []
## Wave B: the dormant centre patch, a little smaller than the Yard's so the cut lanes
## still end on bare floor.
const WAKE_SPIKE_EXTENT := 1.4
## Visual spin phase, seeded so a replay's discs sit where the fight's did.
var _spin_phase := 0.0


func arena_id() -> String:
	return "grinder"


func _configure() -> void:
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT       # low walls, as the brief asks
	_floor_mat = MAT_PLATE
	_wall_mat = MAT_STEEL
	_floor_tint = TINT_FLOOR
	_wall_tint = TINT_WALL
	_floor_metallic = 0.42
	_ambient_tint = Color(0.92, 0.97, 1.10)     # cold steel
	_key_colour = Color(0.96, 0.98, 1.0)
	_key_energy = 0.55
	_bg_tint = Color(0.9, 0.95, 1.05)
	_grid_enabled = false


func _seed_hazards(rng: RandomNumberGenerator) -> void:
	# ONE draw, always, whether or not the discs are built: the order of rng consumers is
	# the seed (fight.gd's comment), so an arena must draw the same number of times every
	# run. The phase is visual only; the cut is on all fight.
	_spin_phase = rng.randf() * TAU if rng != null else 0.0
	for g in _grinders:
		var disc := g["disc"] as MeshInstance3D
		if is_instance_valid(disc):
			disc.rotation.y = _spin_phase


func _build_hazards() -> void:
	_grinders.append(_add_grinder(GRINDER_A, "GrinderWest"))
	_grinders.append(_add_grinder(GRINDER_B, "GrinderEast"))
	# Wave B pacing: a spike patch on the centre cross, asleep until the wake stage (1:30).
	# The middle is where two machines circling each other end up, and the grinders never
	# reach it. Added after the grinders so their areas keep their place in the tree.
	_add_spike_patch(Vector3.ZERO, WAKE_SPIKE_EXTENT)
	_spike_dormant = true


func _build_markings() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for centre in [GRINDER_A, GRINDER_B]:
		var c := Vector2(centre.x, centre.z)
		# Keep-out ring plus a broken outer ring, the arena's own warning language.
		_mark_ring(verts, norms, c, GRINDER_RADIUS + 0.30, 0.08, 36)
		for i in range(8):
			var a0 := TAU * float(i) / 8.0 + 0.10
			var a1 := a0 + 0.42
			_mark_ring(verts, norms, c, GRINDER_RADIUS + 0.62, 0.10, 4, a0, a1)
	var keepout := _mesh_from(verts, norms)
	_add_marking("KeepOut", keepout, COL_KEEPOUT, 0.0)

	var lane_verts := PackedVector3Array()
	var lane_norms := PackedVector3Array()
	# The cut lanes: a bar from each grinder toward the centre, the line a bot gets shoved
	# along. Reads as machined guidance rather than as show branding.
	for centre in [GRINDER_A, GRINDER_B]:
		var c := Vector2(centre.x, centre.z)
		var to_mid := (Vector2.ZERO - c).normalized()
		_mark_line(lane_verts, lane_norms, c + to_mid * 1.1, c + to_mid * 3.4, 0.5)
	# A plain centre cross: the only mark in the middle, so the fight reads as pushed out
	# from it rather than circling it.
	_mark_line(lane_verts, lane_norms, Vector2(-0.55, 0.0), Vector2(0.55, 0.0), 0.07)
	_mark_line(lane_verts, lane_norms, Vector2(0.0, -0.55), Vector2(0.0, 0.55), 0.07)
	_add_marking("CutLanes", _mesh_from(lane_verts, lane_norms), COL_LANE, 0.0)


# ---------------------------------------------------------------------------
# Hazard tick
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	for g in _grinders:
		_tick_grinder(g, delta)
	_tick_spikes()
	_ticks += 1


# ---------------------------------------------------------------------------
# Wave B pacing: the Grinder's stages (ArenaBase "the round in stages")
#   0:45 the discs bite every 20 ticks (base)   1:30 the centre spikes wake
#   2:00 the discs bite every 15 ticks and the patch stays up (endgame)
# ---------------------------------------------------------------------------
func _on_stage(stage_index: int) -> void:
	super(stage_index)
	if stage_index == STAGE_WAKE:
		_wake_spikes()


func _wake_word() -> String:
	return "SPIKES WAKE"


# ---------------------------------------------------------------------------
# The AI's read
# ---------------------------------------------------------------------------
## The discs never stop, so the danger is never more than zero seconds away. An AI that
## reads this arena is deciding where to be, not when.
func hazard_helpers() -> Dictionary:
	return {
		"next_danger_in_s": 0.0,
		"danger_positions": _danger_positions(),
		"safe_positions": _safe_positions(),
	}


func _danger_positions() -> Array[Vector3]:
	var out: Array[Vector3] = [GRINDER_A, GRINDER_B]
	# Wave B: the centre patch once it is awake and about to rise (or up).
	if _spikes_up or seconds_to_spike_rise() < 1.5:
		out.append(_spike_centre)
	return out


func grinder_positions() -> Array[Vector3]:
	return [GRINDER_A, GRINDER_B]


## True while any part of any bot is on a disc: the FX and the tests both read this.
func grinding() -> bool:
	for g in _grinders:
		if bool(g["touching"]):
			return true
	return false


## Wave B: the Grinder now has a spike patch, asleep until the wake stage; ArenaBase's
## spikes_risen() / seconds_to_spike_rise() read "never" until then, so fight.gd's spike
## clock and the AI see exactly what they saw before the patch existed.
