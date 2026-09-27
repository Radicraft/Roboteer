class_name Yard extends ArenaBase
## The Yard (docs/stage3-spec.md §5, brief §7 arena 1): a 10 x 10 m floor, four low walls
## with a chevron strip, a central spike patch on a physics-tick timer, an out-of-arena
## sensor and the two spawn markers. The tutorial arena: one hazard, in the middle, where
## it cannot be avoided by accident and cannot be fallen into by surprise.
##
## Everything it is built from now lives in ArenaBase, which the other five arenas share
## (docs/stage5-arenas-notes.md). The Yard's own content is the marking scheme, the cold
## grey tint and the one spike patch below. Behaviour is unchanged from Stage 3: same
## floor, same walls, same spawn marks, same spike cadence and the same seeded phase.
##
## The camera is NOT here (agent C owns the rig).

## Kept as the Yard's own names so a reader of the Stage 3 spec finds them where the spec
## says they are; the values live in ArenaBase because the Coliseum uses the same patch.
const SPIKE_PATCH_SIZE := ArenaBase.SPIKE_PATCH


func arena_id() -> String:
	return "yard"


func _configure() -> void:
	# The Yard IS the render tuning the owner passed: everything else is measured against
	# it (docs/graphics-render-notes.md), so it takes the profile defaults unchanged.
	_arena_size = FightTypes.ARENA_SIZE
	_wall_height = FightTypes.WALL_HEIGHT
	_grid_enabled = true
	# Wave A: its own wall tint (every arena has one now): weathered breaker's-yard
	# concrete, a touch warmer and lower than the shared default so it stops glaring.
	_wall_tint = Color(2.2, 2.12, 2.02)


## Wave B pacing: two floor grinders in the middle of the north and south walls, asleep
## until the wake stage (1:30). A 180 degree rotation of each other, 3.2 m from either
## spawn mark and clear of the house corner (+X -Z, from x = 2.5), 1.4 m off the wall:
## the lane a machine circling the patch drives along.
const WAKE_GRINDERS := [Vector3(0.0, 0.0, -3.6), Vector3(0.0, 0.0, 3.6)]

var _wake_grinders: Array = []


func _build_hazards() -> void:
	_add_spike_patch(Vector3.ZERO, SPIKE_PATCH_SIZE)
	# Added after the patch, so the patch's bodies keep their place in the tree.
	for i in WAKE_GRINDERS.size():
		_wake_grinders.append(_add_grinder(WAKE_GRINDERS[i], "WakeGrinder%d" % i, true))


func _physics_process(delta: float) -> void:
	_tick_spikes()
	for g in _wake_grinders:
		_tick_grinder(g, delta)
	_ticks += 1


# ---------------------------------------------------------------------------
# Wave B pacing: the Yard's stages (ArenaBase "the round in stages")
#   0:45 the patch cycles every 4.5 s (base)   1:30 the wall grinders wake
#   2:00 the patch stays up, the grinders bite twice as often (endgame, unchanged)
# ---------------------------------------------------------------------------
func _on_stage(stage_index: int) -> void:
	super(stage_index)
	if stage_index == STAGE_WAKE:
		for g in _wake_grinders:
			_wake_grinder(g)


func _wake_word() -> String:
	return "GRINDERS WAKE"
